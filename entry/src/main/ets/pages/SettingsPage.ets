import { BiliService, QrPollStatus, QrPollResult } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { SecureStore } from '../service/SecureStore';
import { PlayerController } from '../service/PlayerController';
import { QrCode, QrEcc } from '../service/QrCode';
import { AppStore } from '../service/AppStore';
import { Appearance } from '../service/Appearance';
import { DownloadManager } from '../service/DownloadManager';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CoverThumb } from '../component/CoverThumb';
import { Constants } from '../service/Constants';
import { UnfavoriteRecord } from '../model/UnfavoriteRecord';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { BiliVideo } from '../model/BiliVideo';

const QR_CANVAS_SIZE: number = 280;

// 播放历史懒加载数据源：LazyForEach 只构建可视区域内的列表项，避免长历史一次性创建全部封面
class HistoryDataSource implements IDataSource {
  private items: PlayHistoryItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PlayHistoryItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  setItems(next: PlayHistoryItem[]): void {
    // 入参可能是 @State 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.items = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

@Builder
export function SettingsPageBuilder() {
  SettingsPage()
}

// 设置页（NavDestination）：登录 / 本地缓存 / 播放设置 / 外观（含主题色板）/ 历史记录 / 关于
// pushPathByName('settingsPage', param) 可带 'playHistory' / 'about' 直开对应面板
@Component
struct SettingsPage {
  @State showQr: boolean = false;
  @State isLogged: boolean = false;
  @State loginName: string = '未登录';
  @State cookieInput: string = '';
  @State statusMsg: string = '';
  @State cacheText: string = '';
  @State cacheSubText: string = '';
  @State qrStatus: string = '';
  @State qrExpired: boolean = false;
  @State qrUrl: string = '';
  @State oneKeyLogging: boolean = false;
  @State showAbout: boolean = false;
  @State aboutTip: string = '';

  // —— 取消收藏历史 ——
  @StorageLink('showHistory') showHistory: boolean = false; // key 与 Constants.AS_SHOW_HISTORY 对应
  @State historyItems: UnfavoriteRecord[] = [];
  @State historyVersion: number = -1;

  // —— 播放历史 ——
  @StorageLink('showPlayHistory') showPlayHistory: boolean = false; // key 与 Constants.AS_SHOW_PLAY_HISTORY 对应
  @State playHistoryItems: PlayHistoryItem[] = [];
  @State playHistoryVersion: number = -1;

  @State autoPlayOnStart: boolean = true;
  // —— 四个新增设置开关状态 ——
  @State interruptResume: boolean = false;
  @State dataSaver: boolean = false;
  @State preferLowBitrate: boolean = false;
  @State wifiOnlyDownload: boolean = false;
  // 与其他媒体同时播放：默认开=共存混音（与 1.0.1 行为一致），关=独占音频焦点
  @State coPlayWithOthers: boolean = true;
  // 外观三态选中态（0=跟随系统 1=浅色 2=深色）：由 Appearance 写入 AppStorage 驱动刷新
  @StorageProp('colorModeSetting') colorModeSetting: number = 0;

  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  private qrCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  private textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }


  private qrCode: QrCode | undefined = undefined;
  private qrcodeKey: string = '';
  private pollTimer: number = -1;
  private polling: boolean = false;
  private pollGeneration: number = 0;
  private controller: PlayerController = PlayerController.getInstance();
  private playHistorySource: HistoryDataSource = new HistoryDataSource();
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.refreshLoginState();
    this.autoPlayOnStart = AppStore.getNumber(Constants.KEY_AUTO_PLAY_ON_START, 1) === 1;
    this.interruptResume = AppStore.getNumber(Constants.KEY_INTERRUPT_RESUME, 0) === 1;
    this.dataSaver = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    this.preferLowBitrate = AppStore.getNumber(Constants.KEY_PREFER_LOW_BITRATE, 0) === 1;
    this.wifiOnlyDownload = AppStore.getNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, 0) === 1;
    this.coPlayWithOthers = AppStore.getNumber(Constants.KEY_CO_PLAY_WITH_OTHERS, 1) === 1;
    this.controller.subscribe((): void => {
      this.refreshLoginState();
      if (this.showHistory && this.historyVersion !== this.controller.historyVersion) {
        this.historyVersion = this.controller.historyVersion;
        this.historyItems = this.controller.unfavoriteHistory.slice(0);
      }
      if (this.showPlayHistory && this.playHistoryVersion !== this.controller.playHistoryVersion) {
        this.playHistoryVersion = this.controller.playHistoryVersion;
        this.playHistoryItems = this.controller.playHistory.slice(0);
        this.playHistorySource.setItems(this.playHistoryItems);
      }
    });
    this.refreshCacheText();
  }

  aboutToDisappear(): void {
    this.stopPoll();
  }

  private refreshCacheText(): void {
    const dm: DownloadManager = DownloadManager.getInstance();
    const count: number = dm.downloads.length;
    const sizeMB: number = dm.downloadSizeMB();
    this.cacheText = count > 0
      ? `已保存 ${count} 首 · ${sizeMB.toFixed(1)} MB` : '暂无本地歌曲，可在播放队列中多选后保存到本地';
    const cacheMB: number = BiliService.cacheSizeMB();
    this.cacheSubText = cacheMB > 0.5
      ? `播放缓存 ${cacheMB.toFixed(1)} MB（播过的歌临时存放，可清理）` : '';
  }

  private refreshLoginState(): void {
    const session: BiliSession = BiliSession.getInstance();
    this.isLogged = session.isLogged();
    if (session.isLogged()) {
      this.loginName = session.uname !== '' ? session.uname : `已登录 (UID ${session.mid})`;
    } else {
      this.loginName = '未登录';
    }
  }

  private openHistory(): void {
    this.historyVersion = this.controller.historyVersion;
    this.historyItems = this.controller.unfavoriteHistory.slice(0);
    this.showHistory = true;
  }

  private openPlayHistory(): void {
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.playHistoryItems = this.controller.playHistory.slice(0);
    this.playHistorySource.setItems(this.playHistoryItems);
    this.showPlayHistory = true;
  }

  private sourceLabel(sourceType: number): string {
    return BiliVideo.sourceLabelOf(sourceType);
  }

  private formatPlayedAt(playedAt: number): string {
    const diff: number = Date.now() - playedAt;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    if (diff < 7 * 86400000) {
      return `${Math.floor(diff / 86400000)} 天前`;
    }
    const d: Date = new Date(playedAt);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const monthStr: string = month < 10 ? `0${month}` : `${month}`;
    const dayStr: string = day < 10 ? `0${day}` : `${day}`;
    return `${monthStr}-${dayStr}`;
  }

  private async replayHistory(item: PlayHistoryItem): Promise<void> {
    const v: BiliVideo = BiliVideo.create(item.bvid, 0, 0, item.title, item.cover, 0);
    v.ownerName = item.ownerName;
    await this.controller.playFromLibraryResult(v);
    this.controller.goToPlayerTab?.();
  }

  private confirmClearPlayHistory(): void {
    AlertDialog.show({
      title: '清空播放历史',
      message: '确定清空全部播放历史吗？此操作不可恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '清空',
        action: (): void => {
          this.controller.clearPlayHistory();
          this.playHistoryVersion = this.controller.playHistoryVersion;
          this.playHistoryItems = [];
          this.playHistorySource.setItems(this.playHistoryItems);
        }
      }
    });
  }

  private formatRemovedAt(removedAt: number): string {
    const d: Date = new Date(removedAt);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const hour: number = d.getHours();
    const minute: number = d.getMinutes();
    const hh: string = hour < 10 ? `0${hour}` : `${hour}`;
    const mi: string = minute < 10 ? `0${minute}` : `${minute}`;
    return `${month}-${day} ${hh}:${mi}`;
  }

  private async saveCookie(raw: string): Promise<void> {
    const session: BiliSession = BiliSession.getInstance();
    const trimmed: string = raw.trim();
    if (trimmed.indexOf('SESSDATA') < 0) {
      this.statusMsg = 'Cookie中缺少SESSDATA，无法登录';
      this.qrStatus = this.statusMsg;
      return;
    }
    session.setCookieString(trimmed);
    this.statusMsg = '正在验证登录...';
    this.emitQrStatus('正在验证登录...');
    try {
      await BiliService.ensureBuvid();
      await BiliService.fetchNav();
      await SecureStore.save(Constants.COOKIE_ALIAS, trimmed);
      this.showQr = false;
      this.stopPoll();
      this.oneKeyLogging = false;
      this.qrStatus = '';
      this.statusMsg = `登录成功：${session.uname}`;
    } catch (err) {
      const error = err as BusinessError;
      session.clear();
      this.oneKeyLogging = false;
      this.statusMsg = `登录失败: ${error.message}`;
      this.qrStatus = this.statusMsg;
    }
    this.refreshLoginState();
  }

  private emitQrStatus(msg: string): void {
    this.qrStatus = msg;
  }

  private async startQrLogin(): Promise<void> {
    this.pollGeneration++;
    const gen: number = this.pollGeneration;
    this.qrExpired = false;
    this.qrStatus = '正在获取二维码...';
    try {
      await BiliService.ensureBuvid();
      const info = await BiliService.fetchQrLoginUrl();
      if (gen !== this.pollGeneration) {
        return;
      }
      this.qrcodeKey = info.qrcodeKey;
      this.qrUrl = info.url;
      this.qrCode = QrCode.encodeText(info.url, QrEcc.MEDIUM);
      this.qrStatus = '请使用B站App扫码登录';
      this.drawQr();
      this.startPoll();
    } catch (err) {
      if (gen !== this.pollGeneration) {
        return;
      }
      const error = err as BusinessError;
      this.qrStatus = `获取二维码失败: ${error.message}`;
    }
  }

  private drawQr(): void {
    const code: QrCode | undefined = this.qrCode;
    if (code === undefined) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.qrCanvas;
    ctx.fillStyle = Constants.QR_BG_COLOR;
    ctx.fillRect(0, 0, QR_CANVAS_SIZE, QR_CANVAS_SIZE);
    ctx.fillStyle = Constants.QR_FG_COLOR;
    const quiet: number = 4;
    const total: number = code.size + quiet * 2;
    const scale: number = QR_CANVAS_SIZE / total;
    for (let y = 0; y < code.size; y++) {
      for (let x = 0; x < code.size; x++) {
        if (code.getModule(x, y)) {
          ctx.fillRect((x + quiet) * scale, (y + quiet) * scale, scale, scale);
        }
      }
    }
  }

  // 二维码处于可用状态（未过期且已取得确认链接）才允许「在B站打开」/「保存」
  private qrReady(): boolean {
    if (this.qrExpired) {
      this.qrStatus = '二维码已过期，请先刷新';
      return false;
    }
    return this.qrUrl !== '';
  }

  // 拉起B站App打开登录确认页（免扫码确认）；B站未响应深链时退回浏览器打开同一链接。
  // 返回是否成功打开；失败时调用方自行决定降级（如改为展示二维码）
  private async openInBiliApp(): Promise<boolean> {
    if (!this.qrReady()) {
      return false;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const options: OpenLinkOptions = { appLinkingOnly: false };
    const deepLink: string = `bilibili://browser/?url=${encodeURIComponent(this.qrUrl)}`;
    let opened: boolean = false;
    try {
      await ctx.openLink(deepLink, options);
      opened = true;
    } catch (err) {
      // B站未安装或未响应深链，走浏览器兜底
    }
    if (!opened) {
      try {
        await ctx.openLink(this.qrUrl, options);
        opened = true;
      } catch (err) {
        this.qrStatus = '未能打开B站，请扫码或保存二维码后用B站App识别';
      }
    }
    if (opened) {
      this.qrStatus = '已跳转B站，请确认登录后返回本应用';
    }
    return opened;
  }

  // 一键登录：生成确认链接后直接拉起B站App确认，无需展示二维码，轮询在后台进行
  private async startOneKeyLogin(): Promise<void> {
    if (this.polling) {
      return;
    }
    this.showQr = false;
    this.stopPoll();
    this.pollGeneration++;
    const gen: number = this.pollGeneration;
    this.oneKeyLogging = true;
    this.qrExpired = false;
    this.qrStatus = '正在准备登录...';
    try {
      await BiliService.ensureBuvid();
      const info = await BiliService.fetchQrLoginUrl();
      if (gen !== this.pollGeneration) {
        return;
      }
      this.qrcodeKey = info.qrcodeKey;
      this.qrUrl = info.url;
      this.startPoll();
      const opened: boolean = await this.openInBiliApp();
      if (!opened) {
        this.oneKeyLogging = false;
        this.stopPoll();
      }
    } catch (err) {
      if (gen !== this.pollGeneration) {
        return;
      }
      const error = err as BusinessError;
      this.qrStatus = `登录失败: ${error.message}`;
      this.oneKeyLogging = false;
      this.stopPoll();
    }
  }

  private cancelOneKeyLogin(): void {
    this.oneKeyLogging = false;
    this.stopPoll();
    this.qrcodeKey = '';
    this.qrUrl = '';
    this.qrStatus = '';
  }

  // 由安全控件 SaveButton 的点击回调调用（临时授权写相册，无需申请权限）
  private async saveQrToAlbum(): Promise<void> {
    if (!this.qrReady()) {
      return;
    }
    try {
      const pixelMap: image.PixelMap = await componentSnapshot.get('bili_qr_canvas');
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(getContext(this));
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
      const file: fs.File = await fs.open(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      const packer: image.ImagePacker = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/png', quality: 100 };
      await packer.packToFile(pixelMap, file.fd, opts);
      await fs.close(file.fd);
      this.qrStatus = '已保存到相册，可在B站App「扫一扫-相册」中识别';
    } catch (err) {
      this.qrStatus = '保存二维码失败，请重试';
    }
  }

  private startPoll(): void {
    this.stopPoll();
    this.pollTimer = setInterval((): void => {
      this.pollOnce();
    }, 2000);
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async pollOnce(): Promise<void> {
    if (this.polling || this.qrcodeKey === '' || (!this.showQr && !this.oneKeyLogging)) {
      return;
    }
    const gen: number = this.pollGeneration;
    this.polling = true;
    let result: QrPollResult | undefined = undefined;
    let errMsg: string = '';
    try {
      result = await BiliService.pollQrLogin(this.qrcodeKey);
    } catch (err) {
      errMsg = (err as BusinessError).message;
    }
    this.polling = false;
    if (gen !== this.pollGeneration) {
      return;
    }
    if (result === undefined) {
      this.qrStatus = `登录出错: ${errMsg}，将继续重试`;
      return;
    }
    if (result.status === QrPollStatus.SCANNED) {
      if (!this.qrExpired && this.qrStatus !== '已扫码，请在手机上确认') {
        this.qrStatus = '已扫码，请在手机上确认';
      }
    } else if (result.status === QrPollStatus.EXPIRED) {
      this.qrStatus = '二维码已过期，请点击刷新';
      this.qrExpired = true;
      this.oneKeyLogging = false;
      this.stopPoll();
    } else if (result.status === QrPollStatus.SUCCESS) {
      this.stopPoll();
      this.qrStatus = '扫码成功，正在登录...';
      await this.saveCookie(result.cookie);
    }
  }

  private async logout(): Promise<void> {
    this.stopPoll();
    this.showQr = false;
    BiliSession.getInstance().clear();
    await SecureStore.remove(Constants.COOKIE_ALIAS);
    this.statusMsg = '已退出登录';
    this.refreshLoginState();
  }

  private openBiliSpace(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const options: OpenLinkOptions = { appLinkingOnly: false };
    ctx.openLink('https://space.bilibili.com/604142543', options)
      .catch((err: BusinessError) => {
        this.aboutTip = `打开B站主页失败: ${err.message}`;
      });
  }

  private async copyEmail(): Promise<void> {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, 'heartthrobwood@qq.com');
    const systemPasteboard = pasteboard.getSystemPasteboard();
    await systemPasteboard.setData(pasteData);
    this.aboutTip = '反馈邮箱已复制';
  }


  private selectAppearance(mode: number): void {
    if (mode === this.colorModeSetting) {
      return;
    }
    // 立即生效：Appearance 内部完成持久化（key: colorMode）、应用层 setColorMode 与窗口层颜色重设
    Appearance.setUserMode(mode, getContext());
  }

  // 外观三选项分段按钮：当前生效项粉色高亮，其余为未选中态
  @Builder
  appearanceOption(label: string, mode: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.colorModeSetting === mode ?
        $r('app.color.text_primary') : this.textSecondary())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(17)
      .backgroundColor(this.colorModeSetting === mode ?
        $r('app.color.material_tint_primary') : $r('app.color.btn_glass'))
      .onClick(() => {
        this.selectAppearance(mode);
      })
  }

  private selectAccent(color: string): void {
    if (color === this.accentColor) {
      return;
    }
    // 立即生效：Appearance 内部完成持久化并写入 AppStorage('accentColor') 驱动全 UI 刷新
    Appearance.setAccentColor(color, getContext(this));
  }

  // 主题色色板圆点：选中项外圈描边高亮
  @Builder
  accentSwatch(color: string) {
    Row() {
      Row()
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(color)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .justifyContent(FlexAlign.Center)
    .border({
      width: 2,
      color: this.accentColor === color ? this.accentColor : Color.Transparent
    })
    .onClick(() => {
      this.selectAccent(color);
    })
  }

  // 「关于」弹窗内的功能条目：圆点 + 说明文字，左侧对齐，支持多行
  @Builder
  aboutFeature(text: string) {
    Row({ space: 8 }) {
      Text('·')
        .fontSize(14)
        .fontColor($r('app.color.primary_color'))
      Text(text)
        .fontSize(13)
        .fontColor(this.textSecondary())
        .lineHeight(20)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 「关于」弹窗：应用图标/名称 + 简介 + 核心功能 + 联系我们 + 作者
  @Builder
  aboutSheet() {
    Column() {
      Scroll() {
        Column() {
          Image($r('app.media.startIcon'))
            .width(76)
            .height(76)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)

          Text('BiliRadio')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .margin({ top: 12 })

          Text('版本 1.0.0')
            .fontSize(12)
            .fontColor(this.textSecondary())
            .margin({ top: 4 })

          Text('BiliRadio 是一款 B 站音频播放器，把 B 站视频当作纯音乐来听：支持后台播放、进度记忆、锁屏控制。基于 taotie256 的 BiliMusic（Apache 2.0）开发。')
            .fontSize(13)
            .fontColor(this.textSecondary())
            .lineHeight(20)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 16 })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ top: 16, bottom: 14 })

          Text('核心功能')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)

          Column({ space: 10 }) {
            this.aboutFeature('订阅收听：UP 主 / 收藏夹 / 合集 / 系列，新集自动标 NEW')
            this.aboutFeature('队列播放：整源入队、搜索、多选管理与保存到本地')
            this.aboutFeature('播放控制：倍速、播放模式、睡眠定时、进度续播')
            this.aboutFeature('下载管理：离线保存、存储占用概览、批量删除')
            this.aboutFeature('外观：深浅色三态 + 六色主题色板')
          }
          .width('100%')
          .margin({ top: 12 })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ top: 16, bottom: 14 })

          Text('联系我们')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)

          Row() {
            Text('B站主页')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Blank()
            Text('space.bilibili.com/604142543')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .borderRadius(10)
          .margin({ top: 12 })
          .onClick(() => {
            this.openBiliSpace();
          })

          Row() {
            Text('反馈邮箱')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Blank()
            Text('heartthrobwood@qq.com')
              .fontSize(12)
              .fontColor(this.textSecondary())
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .borderRadius(10)
          .margin({ top: 8 })
          .onClick(() => {
            this.copyEmail();
          })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ top: 16, bottom: 14 })

          Text('作者')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)

          Row({ space: 12 }) {
            Image($r('app.media.headpic'))
              .width(44)
              .height(44)
              .borderRadius(22)
              .objectFit(ImageFit.Cover)
              .border({ width: 1, color: $r('app.color.btn_border') })
            Text('盖世木头')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimary())
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .borderRadius(10)
          .margin({ top: 12 })
          .alignItems(VerticalAlign.Center)

          if (this.aboutTip !== '') {
            Text(this.aboutTip)
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 12 })
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 24 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_background'))
    .backdropBlur(20)
  }

  // 取消收藏历史浮层：半透明毛玻璃，覆盖在设置页之上
  @Builder
  historyPanel() {
    Column() {
      Row() {
        Text(`取消收藏历史 (${this.historyItems.length})`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.historyItems.length > 0) {
          Button('清空')
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor($r('app.color.danger_red'))
            .borderRadius(16)
            .fontSize(12)
            .margin({ right: 8 })
            .onClick(() => {
              this.controller.clearUnfavoriteHistory();
              this.historyVersion = this.controller.historyVersion;
              this.historyItems = [];
            })
        }

        Button('关闭')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .borderRadius(16)
          .fontSize(12)
          .onClick(() => {
            this.showHistory = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (!BiliSession.getInstance().isLogged() && this.historyItems.length > 0) {
        Text('当前未登录，恢复收藏需要先登录')
          .fontSize(12)
          .fontColor($r('app.color.gold_accent'))
          .width('100%')
          .padding({ left: 16, bottom: 4 })
      }

      if (this.historyItems.length === 0) {
        Column() {
          Text('暂无取消收藏记录')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        List({ space: 0 }) {
          ForEach(this.historyItems, (record: UnfavoriteRecord, index: number) => {
            ListItem() {
              Row() {
                Column() {
                  Text(record.title)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`取消于 ${this.formatRemovedAt(record.removedAt)} · ${record.bvid}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button('恢复收藏')
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .border({ width: 1, color: $r('app.color.btn_border') })
                  .fontColor($r('app.color.primary_color'))
                  .borderRadius(16)
                  .fontSize(12)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.controller.refavoriteFromHistory(index);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
          }, (record: UnfavoriteRecord) => `${record.bvid}_${record.removedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
      }

      Text(this.controller.statusMsg)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_background'))
    .backdropBlur(20)
    .padding({ bottom: 16 })
    .zIndex(3)
  }

  // 播放历史浮层：半透明毛玻璃覆盖层，最近播放倒序，点击回放，清空需二次确认
  @Builder
  playHistoryPanel() {
    Column() {
      Row() {
        Text(`播放历史 (${this.playHistoryItems.length})`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.playHistoryItems.length > 0) {
          Button('清空')
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor($r('app.color.danger_red'))
            .borderRadius(16)
            .fontSize(12)
            .margin({ right: 8 })
            .onClick(() => {
              this.confirmClearPlayHistory();
            })
        }

        Button('关闭')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .borderRadius(16)
          .fontSize(12)
          .onClick(() => {
            this.showPlayHistory = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.playHistoryItems.length === 0) {
        Column() {
          Text('暂无播放历史，听歌后会自动记录')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        List({ space: 0 }) {
          LazyForEach(this.playHistorySource, (item: PlayHistoryItem) => {
            ListItem() {
              Row() {
                CoverThumb({ cover: item.cover })

                Column() {
                  Text(item.title)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.sourceLabel(item.sourceType)} · ${this.formatPlayedAt(item.playedAt)}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                this.replayHistory(item);
              })
            }
          }, (item: PlayHistoryItem) => `${item.bvid}_${item.playedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
      }

      Text(this.controller.statusMsg)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_background'))
    .backdropBlur(20)
    .padding({ bottom: 16 })
    .zIndex(3)
  }


  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Scroll() {
          Column() {
            Row() {
          Text('账号')
            .fontSize(15)
            .fontColor(this.textPrimary())
          Blank()
          Text(this.loginName)
            .fontSize(14)
            .fontColor(this.textSecondary())
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)

        if (!this.isLogged) {
          if (this.oneKeyLogging) {
            Button('正在等待B站确认…（点击取消）')
              .width('92%')
              .height(42)
              .backgroundColor($r('app.color.material_tint_primary'))
              .backdropBlur(20)
              .fontColor($r('app.color.text_primary'))
              .borderRadius(21)
              .fontSize(15)
              .margin({ top: 12 })
              .onClick(() => {
                this.cancelOneKeyLogin();
              })

            Text(this.qrStatus)
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('92%')
              .margin({ top: 8 })
          } else {
            Row({ space: 12 }) {
              Button('B站一键登录')
                .layoutWeight(1)
                .height(42)
                .backgroundColor($r('app.color.material_tint_primary'))
                .backdropBlur(20)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(21)
                .fontSize(15)
                .onClick(() => {
                  this.startOneKeyLogin();
                })

              Button('扫码登录')
                .layoutWeight(1)
                .height(42)
                .backgroundColor($r('app.color.btn_glass'))
                .backdropBlur(20)
                .border({ width: 1, color: $r('app.color.btn_border') })
                .fontColor(this.textPrimary())
                .borderRadius(21)
                .fontSize(15)
                .onClick(() => {
                  this.showQr = true;
                  this.startQrLogin();
                })
            }
            .width('92%')
            .margin({ top: 12 })

            if (!this.showQr && this.qrStatus !== '') {
              Text(this.qrStatus)
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('92%')
                .margin({ top: 8 })
            }
          }
        } else {
          Button('退出登录')
            .width('92%')
            .height(42)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor(this.textPrimary())
            .borderRadius(21)
            .fontSize(15)
            .margin({ top: 12 })
            .onClick(() => {
              this.logout();
            })
        }

        if (!this.isLogged) {
          if (this.showQr) {
            Column() {
              Canvas(this.qrCanvas)
                .id('bili_qr_canvas')
                .width(QR_CANVAS_SIZE)
                .height(QR_CANVAS_SIZE)
                .backgroundColor(Constants.QR_BG_COLOR)
                .borderRadius(12)
                .margin({ top: 12 })
                .onReady(() => {
                  this.drawQr();
                })

              Text(this.qrStatus)
                .fontSize(13)
                .fontColor(this.textSecondary())
                .margin({ top: 10 })

              Row({ space: 12 }) {
                SaveButton({ text: SaveDescription.SAVE, buttonType: ButtonType.Capsule })
                  .height(34)
                  .padding({ left: 14, right: 14 })
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.page_background'))
                  .onClick(async (event: ClickEvent, result: SaveButtonOnClickResult) => {
                    if (result === SaveButtonOnClickResult.SUCCESS) {
                      await this.saveQrToAlbum();
                    } else {
                      this.qrStatus = '未获得保存授权，请重试';
                    }
                  })

                Button(this.qrExpired ? '刷新二维码' : '取消')
                  .height(34)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .border({ width: 1, color: $r('app.color.btn_border') })
                  .fontColor(this.textPrimary())
                  .borderRadius(17)
                  .fontSize(13)
                  .onClick(() => {
                    if (this.qrExpired) {
                      this.startQrLogin();
                    } else {
                      this.showQr = false;
                      this.stopPoll();
                    }
                  })
              }
              .margin({ top: 10 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }

          Column() {
            Text('手动粘贴Cookie（需包含 SESSDATA 和 bili_jct）')
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .margin({ bottom: 8 })

            Row() {
              TextInput({ placeholder: '粘贴浏览器Cookie', text: this.cookieInput })
                .layoutWeight(1)
                .height(40)
                .backgroundColor($r('app.color.btn_glass'))
                .backdropBlur(20)
                .border({ width: 1, color: $r('app.color.btn_border') })
                .fontColor(this.textPrimary())
                .placeholderColor($r('app.color.placeholder_color'))
                .borderRadius(8)
                .fontSize(13)
                .onChange((value: string) => {
                  this.cookieInput = value;
                })

              Button('保存')
                .height(40)
                .margin({ left: 8 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor($r('app.color.primary_color'))
              .borderRadius(8)
                .fontSize(13)
                .onClick(() => {
                  this.saveCookie(this.cookieInput);
                })
            }
            .width('100%')
          }
          .width('92%')
          .padding(14)
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .borderRadius(12)
          .margin({ top: 12 })
        }

        Text('本地与缓存')
          .fontSize(15)
          .fontColor(this.textPrimary())
          .width('92%')
          .margin({ top: 14, bottom: 8 })

        Row() {
          Column() {
            Text(this.cacheText)
              .fontSize(14)
              .fontColor(this.textPrimary())
            if (this.cacheSubText !== '') {
              Text(this.cacheSubText)
                .fontSize(12)
                .fontColor(this.textSecondary())
                .margin({ top: 3 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.cacheSubText !== '') {
            Button('清播放缓存')
              .height(34)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(17)
              .fontSize(13)
              .margin({ left: 8 })
              .onClick(() => {
                const clearedMB: number = BiliService.cacheSizeMB();
                BiliService.clearAllCache();
                this.refreshCacheText();
                hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
                  'clearPlayCache clearedMB=%{public}s', clearedMB.toFixed(1));
                this.getUIContext().getPromptAction().showToast({
                  message: `已清除 ${clearedMB.toFixed(1)} MB`,
                  duration: 2000
                });
              })
          }
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)

        Text('播放设置')
          .fontSize(15)
          .fontColor(this.textPrimary())
          .width('92%')
          .margin({ top: 14, bottom: 8 })

        Row() {
          Column() {
            Text('启动时自动播放')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('打开应用后自动继续上次进度')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.autoPlayOnStart })
            .selectedColor($r('app.color.primary_color'))

            .onChange((isOn: boolean) => {
              this.autoPlayOnStart = isOn;
              AppStore.putNumber(Constants.KEY_AUTO_PLAY_ON_START, isOn ? 1 : 0);
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)

        Row() {
          Column() {
            Text('后台打断续播')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('来电等打断结束后自动继续播放')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.interruptResume })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.interruptResume = isOn;
              AppStore.putNumber(Constants.KEY_INTERRUPT_RESUME, isOn ? 1 : 0);
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 8 })

        Row() {
          Column() {
            Text('与其他媒体同时播放')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('开启后听歌时允许其他应用声音同时播放')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.coPlayWithOthers })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.coPlayWithOthers = isOn;
              this.controller.setCoPlayWithOthers(isOn);
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 8 })

        Text('省流量设置')
          .fontSize(15)
          .fontColor(this.textPrimary())
          .width('92%')
          .margin({ top: 14, bottom: 8 })

        Row() {
          Column() {
            Text('省流量模式')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('不加载歌曲封面与UP主头像')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.dataSaver })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.dataSaver = isOn;
              AppStore.putNumber(Constants.KEY_DATA_SAVER, isOn ? 1 : 0);
              this.controller.refreshUi();
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)

        Row() {
          Column() {
            Text('优先低码率音频流')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('在线播放选择较低码率，节省流量')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.preferLowBitrate })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.preferLowBitrate = isOn;
              AppStore.putNumber(Constants.KEY_PREFER_LOW_BITRATE, isOn ? 1 : 0);
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 8 })

        Row() {
          Column() {
            Text('仅 Wi-Fi 下在线播放')
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('非 Wi-Fi 网络播放需手动确认')
              .fontSize(12)
              .fontColor(this.textSecondary())
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.wifiOnlyDownload })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.wifiOnlyDownload = isOn;
              AppStore.putNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, isOn ? 1 : 0);
            })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 8 })

        Text('外观')
          .fontSize(15)
          .fontColor(this.textPrimary())
          .width('92%')
          .margin({ top: 14, bottom: 8 })

        Row({ space: 8 }) {
          this.appearanceOption('跟随系统', Appearance.MODE_FOLLOW_SYSTEM)
          this.appearanceOption('浅色', Appearance.MODE_LIGHT)
          this.appearanceOption('深色', Appearance.MODE_DARK)
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)

        Row({ space: 12 }) {
          ForEach(Constants.ACCENT_PRESETS, (color: string) => {
            this.accentSwatch(color)
          }, (color: string) => color)
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 8 })

        Row() {
          Text('播放历史')
            .fontSize(15)
            .fontColor(this.textPrimary())
          Blank()
          Text(this.controller.playHistory.length > 0
            ? `${this.controller.playHistory.length} 条` : '')
            .fontSize(13)
            .fontColor(this.textSecondary())
          Text('›')
            .fontSize(16)
            .fontColor(this.textSecondary())
            .margin({ left: 4 })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.openPlayHistory();
        })

        Row() {
          Text('取消收藏历史')
            .fontSize(15)
            .fontColor(this.textPrimary())
          Blank()
          Text(this.controller.unfavoriteHistory.length > 0
            ? `${this.controller.unfavoriteHistory.length} 条` : '')
            .fontSize(13)
            .fontColor(this.textSecondary())
          Text('›')
            .fontSize(16)
            .fontColor(this.textSecondary())
            .margin({ left: 4 })
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.openHistory();
        })

        Row() {
          Text('关于')
            .fontSize(15)
            .fontColor(this.textPrimary())
          Blank()
          Text('›')
            .fontSize(16)
            .fontColor(this.textSecondary())
        }
        .width('92%')
        .padding(14)
        .backgroundColor($r('app.color.btn_glass'))
        .backdropBlur(20)
        .border({ width: 1, color: $r('app.color.btn_border') })
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.showAbout = true;
        })

        Text(this.statusMsg)
          .fontSize(13)
          .fontColor(this.textSecondary())
          .margin({ top: 16, bottom: 24 })
          .width('92%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAbout, this.aboutSheet(), {
      height: '75%',
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.sheet_background'),
    })

      if (this.showHistory) {
        this.historyPanel()
      }

      if (this.showPlayHistory) {
        this.playHistoryPanel()
      }
      }
      .width('100%')
      .height('100%')
    }
    .title('设置')
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      if (ctx.pathInfo.param === undefined || ctx.pathInfo.param === null) {
        return;
      }
      const p: string = ctx.pathInfo.param as string;
      if (p === 'playHistory') {
        this.openPlayHistory();
      } else if (p === 'about') {
        this.showAbout = true;
      }
    })
    .onBackPressed((): boolean => {
      if (this.showPlayHistory) {
        this.showPlayHistory = false;
        return true;
      }
      if (this.showHistory) {
        this.showHistory = false;
        return true;
      }
      return false;
    })
  }
}
