import { BiliService, QrPollStatus, QrPollResult } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { SecureStore } from '../service/SecureStore';
import { PlayerController } from '../service/PlayerController';
import { QrCode, QrEcc } from '../service/QrCode';
import { AppStore } from '../service/AppStore';
import { Appearance } from '../service/Appearance';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CoverThumb } from '../component/CoverThumb';
import { Constants } from '../service/Constants';
import { Logger } from '../service/Logger';
import { LogSheet } from '../component/LogSheet';
import { UnfavoriteRecord } from '../model/UnfavoriteRecord';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { BiliVideo } from '../model/BiliVideo';
import { AudioQuality, QualityTier } from '../model/AudioQuality';

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

  // 单条删除通知（US3 FR-009）：LazyForEach 增量删除指定下标；
  // 按 DataChangeListener 契约，先从自身数据删除对应下标再通知监听者
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    this.items.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

@Builder
export function SettingsPageBuilder() {
  SettingsPage()
}

// 设置页（NavDestination）：登录 / 播放设置 / 外观（含主题色板）/ 历史记录 / 关于
// pushPathByName('settingsPage', param) 可带 'playHistory' / 'about' 直开对应面板
@Component
struct SettingsPage {
  @State showQr: boolean = false;
  @State isLogged: boolean = false;
  @State loginName: string = '未登录';
  @State cookieInput: string = '';
  @State statusMsg: string = '';
  @State qrStatus: string = '';
  @State qrExpired: boolean = false;
  @State qrUrl: string = '';
  @State oneKeyLogging: boolean = false;
  @State showAbout: boolean = false;

  // —— 取消收藏历史 ——
  @StorageLink('showHistory') showHistory: boolean = false; // key 与 Constants.AS_SHOW_HISTORY 对应
  @State historyItems: UnfavoriteRecord[] = [];
  @State historyVersion: number = -1;

  // —— 播放历史 ——
  @StorageLink('showPlayHistory') showPlayHistory: boolean = false; // key 与 Constants.AS_SHOW_PLAY_HISTORY 对应
  @State playHistoryItems: PlayHistoryItem[] = [];
  @State playHistoryVersion: number = -1;

  // —— 应用内日志（US9） ——
  @State showLogSheet: boolean = false;
  @State logCount: number = 0;

  @State autoPlayOnStart: boolean = false;
  // —— 四个新增设置开关状态 ——
  @State interruptResume: boolean = false;
  @State dataSaver: boolean = false;
  @State wifiOnlyDownload: boolean = false;
  // —— 音质（audio-quality-settings）：双网络默认档 + 单 sheet 选择器（编辑目标标记）——
  @State wifiQuality: QualityTier = QualityTier.MAX;
  @State cellularQuality: QualityTier = QualityTier.Q132K;
  @State showQualitySheet: boolean = false;
  @State qualityEditTarget: string = 'wifi'; // 'wifi' | 'cellular'
  // 外观三态选中态（0=跟随系统 1=浅色 2=深色）：由 Appearance 写入 AppStorage 驱动刷新
  @StorageProp('colorModeSetting') colorModeSetting: number = 0;

  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @StorageProp('miniPlayerVisible') miniPlayerVisible: boolean = false; // key 与 Constants.AS_MINI_PLAYER_VISIBLE 对应
  private qrCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  private textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }

  // 强调色淡底（T016，对齐原 material_tint_primary 的 0x59≈0.349 alpha）：随主题色运行时衍生
  private tintBg(): string {
    return Appearance.hexWithAlpha(this.accentColor, 0.349);
  }


  private qrCode: QrCode | undefined = undefined;
  private qrcodeKey: string = '';
  private pollTimer: number = -1;
  private polling: boolean = false;
  private pollGeneration: number = 0;
  private controller: PlayerController = PlayerController.getInstance();
  private playHistorySource: HistoryDataSource = new HistoryDataSource();
  private navPathStack: NavPathStack = new NavPathStack();
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    // US7：设置页在台标志——驱动首页播放胶囊在本页隐藏
    AppStorage.setOrCreate<boolean>(Constants.AS_ON_SETTINGS_PAGE, true);
    this.refreshLoginState();
    this.autoPlayOnStart = AppStore.getNumber(Constants.KEY_AUTO_PLAY_ON_START, 0) === 1;
    this.interruptResume = AppStore.getNumber(Constants.KEY_INTERRUPT_RESUME, 0) === 1;
    this.dataSaver = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    this.wifiOnlyDownload = AppStore.getNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, 0) === 1;
    this.wifiQuality = this.readStoredTier(Constants.KEY_WIFI_AUDIO_QUALITY, QualityTier.MAX);
    this.cellularQuality = this.readStoredTier(Constants.KEY_CELLULAR_AUDIO_QUALITY, QualityTier.Q132K);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
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
    }, 'SettingsPage');
    this.logCount = Logger.count();
  }

  aboutToDisappear(): void {
    // US7：离开设置页恢复胶囊展示
    AppStorage.setOrCreate<boolean>(Constants.AS_ON_SETTINGS_PAGE, false);
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
    this.stopPoll();
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

  // —— 音质（audio-quality-settings）——

  // 读持久化档位：未初始化（<0，如 init 迁移尚未跑完）显示默认值但不落盘，不干扰迁移哨兵
  private readStoredTier(key: string, fallback: QualityTier): QualityTier {
    const stored: number = AppStore.getNumber(key, -1);
    if (stored < 0) {
      return fallback;
    }
    return AudioQuality.fromStored(stored);
  }

  // 档位选择器可选项（FR-009）：未登录仅「最高」「64K」，登录后四档全显（已存高档值不改动）
  private qualityOptions(): QualityTier[] {
    if (this.isLogged) {
      return [QualityTier.MAX, QualityTier.Q192K, QualityTier.Q132K, QualityTier.Q64K];
    }
    return [QualityTier.MAX, QualityTier.Q64K];
  }

  // 当前编辑项的已存档位（选择器 ✓ 高亮依据）
  private currentEditTier(): QualityTier {
    return this.qualityEditTarget === 'wifi' ? this.wifiQuality : this.cellularQuality;
  }

  private openQualitySheet(target: string): void {
    this.qualityEditTarget = target;
    this.showQualitySheet = true;
  }

  // 选中档位：putNumber 立即持久化（FR-001），刷新副标题后关闭选择器
  private applyQualityTier(tier: QualityTier): void {
    if (this.qualityEditTarget === 'wifi') {
      this.wifiQuality = tier;
      AppStore.putNumber(Constants.KEY_WIFI_AUDIO_QUALITY, tier);
    } else {
      this.cellularQuality = tier;
      AppStore.putNumber(Constants.KEY_CELLULAR_AUDIO_QUALITY, tier);
    }
    this.showQualitySheet = false;
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

  // 打开日志面板（US9）：先刷新角标计数；面板数据由 LogSheet 自己在 aboutToAppear 读取
  private openLogSheet(): void {
    this.logCount = Logger.count();
    this.showLogSheet = true;
  }

  // viewAt 为秒级时间戳（play-history-progress 迁移后统一单位），内部转毫秒做相对时间计算
  private formatPlayedAt(viewAt: number): string {
    const playedAtMs: number = viewAt * 1000;
    const diff: number = Date.now() - playedAtMs;
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
    const d: Date = new Date(playedAtMs);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const monthStr: string = month < 10 ? `0${month}` : `${month}`;
    const dayStr: string = day < 10 ? `0${day}` : `${day}`;
    return `${monthStr}-${dayStr}`;
  }

  // 剩余时长格式化（plan R10）：mm:ss，分钟数不封顶，与 QueueSheet.formatTime 风格一致
  private formatRemainingSec(remainingSec: number): string {
    const minutes: number = Math.floor(remainingSec / 60);
    const seconds: number = remainingSec % 60;
    const minStr: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const secStr: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minStr}:${secStr}`;
  }

  // 历史条目第二行文案（FR-008/FR-010）：已听完 → 「日期 · 已听完」；
  // 有进度且时长已知 → 「日期 · 剩 mm:ss」；其余（未记录进度/时长未知）降级为仅日期
  private historyMetaText(item: PlayHistoryItem): string {
    const timeText: string = this.formatPlayedAt(item.viewAt);
    if (item.progress === -1) {
      return `${timeText} · 已听完`;
    }
    if (item.progress > 0 && item.duration > 0 && item.duration > item.progress) {
      return `${timeText} · 剩 ${this.formatRemainingSec(item.duration - item.progress)}`;
    }
    return timeText;
  }

  private async replayHistory(item: PlayHistoryItem): Promise<void> {
    const v: BiliVideo = BiliVideo.create(item.bvid, 0, 0, item.title, item.cover, 0);
    v.ownerName = item.ownerName;
    await this.controller.playFromLibraryResult(v);
    this.controller.goToPlayerTab?.();
  }

  // 左滑单条删除（US3 FR-009）：点击时按 bvid 从当前 @State 数组实时解析下标，
  // 避免 LazyForEach 键复用导致的陈旧索引；@State splice 与 DataSource.notifyDataDelete 双侧同步，
  // 控制器侧异步写盘（removePlayHistoryItem 不 emitUi，面板自行刷新）
  private removeHistoryItem(item: PlayHistoryItem): void {
    const bvid: string = item.bvid;
    if (bvid === '') {
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < this.playHistoryItems.length; i++) {
      if (this.playHistoryItems[i].bvid === bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    this.controller.removePlayHistoryItem(bvid);
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.playHistoryItems.splice(idx, 1);
    this.playHistorySource.notifyDataDelete(idx);
  }

  // 左滑露出的红色「删除」按钮（KI-3 交互约定：露出按钮、点击确认删除，不做滑过阈值直删）
  @Builder
  historyDeleteAction(item: PlayHistoryItem) {
    Button('删除')
      .height('100%')
      .padding({ left: 18, right: 18 })
      .backgroundColor($r('app.color.danger_red'))
      .fontColor(Color.White)
      .fontSize(13)
      .borderRadius(0)
      .onClick(() => {
        this.removeHistoryItem(item);
      })
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
        this.tintBg() : $r('app.color.btn_glass'))
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
        .fontColor(this.accentColor)
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

  // 「关于」弹窗：应用图标/名称 + 简介 + 核心功能
  @Builder
  aboutSheet() {
    Column() {
      Row() {
        Blank()
        Button('完成')
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .borderRadius(15)
          .fontSize(12)
          .onClick(() => {
            this.showAbout = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 8, bottom: 4 })

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

          Text('版本 0.1.0')
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
            this.aboutFeature('队列播放：整源入队、搜索、多选管理')
            this.aboutFeature('播放控制：倍速、播放模式、睡眠定时、进度续播')
            this.aboutFeature('外观：深浅色三态 + 六色主题色板')
          }
          .width('100%')
          .margin({ top: 12 })

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
          .fontColor(this.accentColor)
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
                  .fontColor(this.accentColor)
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
    .padding({ bottom: this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 16 })
    .zIndex(3)
  }

  // 播放历史面板（bindSheet 呈现，与播放页详情 Sheet 同构）：最近播放倒序，点击回放，清空需二次确认
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
            .onClick(() => {
              this.confirmClearPlayHistory();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

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
                  Text(this.historyMetaText(item))
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
            // 左滑露出删除按钮（US3 FR-009）：CustomBuilder 的 void 分支接受 @Builder 调用表达式
            .swipeAction({
              end: this.historyDeleteAction(item)
            })
          }, (item: PlayHistoryItem) => `${item.bvid}_${item.viewAt}_${item.progress}`)
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
  }

  // 日志面板（US9）：bindSheet 承载 LogSheet 组件，数据读取与清空均在组件内完成
  @Builder
  logSheetPanel() {
    LogSheet()
  }

  // 音质档位选择面板（audio-quality-settings）：单 sheet + qualityEditTarget 标记当前编辑项；
  // 当前档 ✓ 高亮，选中即持久化并关闭；未登录仅渲染「最高」「64K」（FR-009）
  @Builder
  qualitySheetPanel() {
    Column() {
      Text(this.qualityEditTarget === 'wifi' ? 'Wi-Fi 默认音质' : '蜂窝默认音质')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      ForEach(this.qualityOptions(), (tier: QualityTier) => {
        Row() {
          Text(AudioQuality.label(tier))
            .fontSize(15)
            .fontColor(this.currentEditTier() === tier
              ? this.accentColor : this.textPrimary())
            .layoutWeight(1)
          if (this.currentEditTier() === tier) {
            Text('✓')
              .fontSize(15)
              .fontColor(this.accentColor)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        .onClick(() => {
          this.applyQualityTier(tier);
        })
      }, (tier: QualityTier) => `${tier}`)

      if (!this.isLogged) {
        Text('未登录时最高 64K，登录后可用更高音质')
          .fontSize(12)
          .fontColor(this.accentColor)
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.sheet_background'))
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
              .backgroundColor(this.tintBg())
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
                .backgroundColor(this.tintBg())
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
              .fontColor(this.accentColor)
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
            .selectedColor(this.accentColor)

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
            .selectedColor(this.accentColor)
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

        Text('音质')
          .fontSize(15)
          .fontColor(this.textPrimary())
          .width('92%')
          .margin({ top: 14, bottom: 8 })

        Row() {
          Text('Wi-Fi 默认音质')
            .fontSize(14)
            .fontColor(this.textPrimary())
            .layoutWeight(1)
          Text(AudioQuality.label(this.wifiQuality))
            .fontSize(13)
            .fontColor(this.accentColor)
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
        .onClick(() => {
          this.openQualitySheet('wifi');
        })

        Row() {
          Text('蜂窝默认音质')
            .fontSize(14)
            .fontColor(this.textPrimary())
            .layoutWeight(1)
          Text(AudioQuality.label(this.cellularQuality))
            .fontSize(13)
            .fontColor(this.accentColor)
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
        .margin({ top: 8 })
        .onClick(() => {
          this.openQualitySheet('cellular');
        })
        .bindSheet($$this.showQualitySheet, this.qualitySheetPanel(), {
          height: '40%',
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.sheet_background'),
          preferType: SheetType.BOTTOM
        })

        if (!this.isLogged) {
          Text('未登录时最高 64K，登录后可用更高音质')
            .fontSize(12)
            .fontColor(this.accentColor)
            .width('92%')
            .margin({ top: 6 })
        }

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
            .selectedColor(this.accentColor)
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
            Text('仅在 Wi-Fi 环境播放')
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
            .selectedColor(this.accentColor)
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
          Text('日志查询')
            .fontSize(15)
            .fontColor(this.textPrimary())
          Blank()
          Text(this.logCount > 0 ? `${this.logCount} 条` : '')
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
          this.openLogSheet();
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
      .padding({ top: 12, bottom: this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 24 })
      .bindSheet($$this.showLogSheet, this.logSheetPanel(), {
        height: '62%',
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.sheet_background'),
        preferType: SheetType.BOTTOM,
        onDisappear: (): void => {
          // 面板内清空/新增日志后同步角标计数
          this.logCount = Logger.count();
        }
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAbout, this.aboutSheet(), {
      height: '75%',
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.sheet_background'),
      preferType: SheetType.BOTTOM
    })

      if (this.showHistory) {
        this.historyPanel()
      }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showPlayHistory, this.playHistoryPanel(), {
        height: '62%',
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.sheet_background'),
        preferType: SheetType.BOTTOM
      })
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
      if (this.showQualitySheet) {
        this.showQualitySheet = false;
        return true;
      }
      if (this.showLogSheet) {
        this.showLogSheet = false;
        return true;
      }
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
