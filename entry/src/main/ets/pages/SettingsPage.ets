import { BiliService, QrPollStatus, QrPollResult } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { SecureStore } from '../service/SecureStore';
import { PlayerController } from '../service/PlayerController';
import { QrCode, QrEcc } from '../service/QrCode';
import { AppStore } from '../service/AppStore';
import { Appearance } from '../service/Appearance';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, OpenLinkOptions, bundleManager } from '@kit.AbilityKit';
import { componentSnapshot, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CoverThumb } from '../component/CoverThumb';
import { SettingsGroup } from '../component/SettingsGroup';
import { SettingsRow } from '../component/SettingsRow';
import { Constants } from '../service/Constants';
import { dismissOverlaysForBack } from '../service/BackHandler';
import { connectBool, connectNum, connectStr, BoolState, NumState, StrState } from '../service/V2State';
import { Logger } from '../service/Logger';
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

// 设置页（NavDestination，US8 HarmonyOS 系统风格重写）：大标题 + 分组卡片（SettingsGroup/SettingsRow），
// 登录 / 播放设置 / 外观（含主题色板）/ 播放历史 / 日志 / 关于功能全保留；
// pushPathByName('settingsPage', param) 可带 'playHistory' / 'about' 直开对应面板
@ComponentV2
struct SettingsPage {
  @Local showQr: boolean = false;
  @Local isLogged: boolean = false;
  @Local loginName: string = '未登录';
  @Local cookieInput: string = '';
  @Local statusMsg: string = '';
  @Local qrStatus: string = '';
  @Local qrExpired: boolean = false;
  @Local qrUrl: string = '';
  @Local oneKeyLogging: boolean = false;
  @Local showAbout: boolean = false;
  @Local debugModeOn: boolean = false;
  @Local appVersion: string = '';

  // —— 播放历史 ——
  @Local showPlayHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
  @Local playHistoryItems: PlayHistoryItem[] = [];
  @Local playHistoryVersion: number = -1;

  // —— 应用内日志（US9） ——
  @Local logCount: number = 0;
  @Local pressedKey: string = '';

  @Local autoPlayOnStart: boolean = false;
  // —— 新增设置开关状态 ——
  @Local interruptResume: boolean = false;
  @Local wifiOnlyDownload: boolean = false;
  // —— 音质（audio-quality-settings）：双网络默认档 + 单 sheet 选择器（编辑目标标记）——
  @Local wifiQuality: QualityTier = QualityTier.MAX;
  @Local cellularQuality: QualityTier = QualityTier.Q132K;
  @Local showQualitySheet: boolean = false;
  @Local qualityEditTarget: string = 'wifi'; // 'wifi' | 'cellular'
  // 外观三态选中态（0=跟随系统 1=浅色 2=深色）：由 Appearance 写全局键驱动刷新
  @Local colorModeSetting: NumState =
    connectNum(Constants.AS_COLOR_MODE_SETTING, Appearance.MODE_FOLLOW_SYSTEM);

  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local miniPlayerVisible: BoolState =
    connectBool(Constants.AS_MINI_PLAYER_VISIBLE, true);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  private qrCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  private textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }

  // 强调色淡底（对齐原 material_tint_primary 的 0x59≈0.349 alpha）：随主题色运行时衍生
  private tintBg(): string {
    return Appearance.hexWithAlpha(this.accentColor.value, 0.349);
  }


  private qrCode: QrCode | undefined = undefined;
  private qrcodeKey: string = '';
  private pollTimer: number = -1;
  private polling: boolean = false;
  private pollGeneration: number = 0;
  private controller: PlayerController = PlayerController.getInstance();
  private playHistorySource: HistoryDataSource = new HistoryDataSource();
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private historyScroller: ListScroller = new ListScroller();
  private settingsScroller: Scroller = new Scroller();
  private navPathStack: NavPathStack = new NavPathStack();
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};
  private tapCount: number = 0;
  private lastTapTs: number = 0;
  private onSettingsPageTimer: number = -1;

  aboutToAppear(): void {
    this.refreshLoginState();
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    this.appVersion = bundleInfo.versionName;
    this.autoPlayOnStart = AppStore.getNumber(Constants.KEY_AUTO_PLAY_ON_START, 0) === 1;
    this.interruptResume = AppStore.getNumber(Constants.KEY_INTERRUPT_RESUME, 0) === 1;
    this.wifiOnlyDownload = AppStore.getNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, 0) === 1;
    this.wifiQuality = this.readStoredTier(Constants.KEY_WIFI_AUDIO_QUALITY, QualityTier.MAX);
    this.cellularQuality = this.readStoredTier(Constants.KEY_CELLULAR_AUDIO_QUALITY, QualityTier.Q132K);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.refreshLoginState();
      if (this.showPlayHistory.value && this.playHistoryVersion !== this.controller.playHistoryVersion) {
        this.playHistoryVersion = this.controller.playHistoryVersion;
        this.playHistoryItems = this.controller.playHistory.slice(0);
        this.playHistorySource.setItems(this.playHistoryItems);
      }
    }, 'SettingsPage');
    this.logCount = Logger.count();
    // debugMode 恢复：经 AppStore 读（Logger.init 的 getPreferencesSync 在 onCreate 阶段不可靠，已移除）
    const storedDebug: boolean = AppStore.getNumber(Constants.KEY_DEBUG_MODE, 0) === 1;
    Logger.setDebugMode(storedDebug);
    this.debugModeOn = storedDebug;
  }

  aboutToDisappear(): void {
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

  private openPlayHistory(): void {
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.playHistoryItems = this.controller.playHistory.slice(0);
    this.playHistorySource.setItems(this.playHistoryItems);
    this.showPlayHistory.value = true;
  }

  private handleAboutIconTap(): void {
    const now: number = Date.now();
    if (this.lastTapTs > 0 && now - this.lastTapTs <= Constants.DEBUG_TAP_WINDOW_MS) {
      this.tapCount++;
    } else {
      this.tapCount = 1;
    }
    this.lastTapTs = now;
    if (this.tapCount < 3) {
      return;
    }
    this.tapCount = 0;
    if (Logger.debugEnabled) {
      promptAction.showToast({ message: '调试模式已开启，可在下方开关关闭' });
      return;
    }
    Logger.setDebugMode(true);
    AppStore.putNumber(Constants.KEY_DEBUG_MODE, 1);
    this.debugModeOn = true;
    promptAction.showToast({ message: '已开启调试模式' });
  }

  private confirmExitDebug(): void {
    AlertDialog.show({
      title: '退出调试模式',
      message: '确定退出调试模式吗？关闭后日志将不再写入系统日志。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '确认关闭',
        action: (): void => {
          Logger.setDebugMode(false);
          AppStore.putNumber(Constants.KEY_DEBUG_MODE, 0);
          this.debugModeOn = false;
          promptAction.showToast({ message: '已退出调试模式' });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.debugModeOn = true;
        }
      },
      onWillDismiss: (dismiss: DismissDialogAction) => {
        this.debugModeOn = true;
        dismiss.dismiss();
      }
    });
  }

  private openLogPage(): void {
    this.navPathStack.pushPathByName('logPage', '');
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
    try {
      const v: BiliVideo = BiliVideo.create(item.bvid, 0, 0, item.title, item.cover, item.duration);
      v.ownerName = item.ownerName;
      await this.controller.playDownloadedSong(v);
      this.controller.goToPlayerTab?.();
    } catch (err) {
      const error = err as BusinessError;
      promptAction.showToast({ message: `播放失败: ${error.message}` });
    }
  }

  // 左滑单条删除（US3 FR-009）：点击时按 bvid 从当前 @State 数组实时解析下标，
  // 避免 LazyForEach 键复用导致的陈旧索引；@State splice 与 DataSource.notifyDataDelete 双侧同步
  // （包补位动画 US6），控制器侧异步写盘（removePlayHistoryItem 不 emitUi，面板自行刷新）
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
    this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.playHistoryItems.splice(idx, 1);
      this.playHistorySource.notifyDataDelete(idx);
    });
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除，取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveHistoryItem(item: PlayHistoryItem): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_HISTORY_TITLE,
      message: Constants.DIALOG_DELETE_HISTORY_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.removeHistoryItem(item);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.historyScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.historyScroller.closeAllSwipeActions();
      }
    });
  }

  // 左滑露出的红色垃圾桶删除钮（US1 双触发）：点击进确认弹窗，滑过阈值（onAction）同弹窗
  @Builder
  historyDeleteAction(item: PlayHistoryItem) {
    Column() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(Constants.SWIPE_DELETE_ICON_FONT)
          .fontColor([$r('app.color.fg_on_dark')])
          .fontWeight(FontWeight.Bold)
      }
      .width(Constants.SWIPE_DELETE_BTN_SIZE)
      .height(Constants.SWIPE_DELETE_BTN_SIZE)
      .backgroundColor($r('app.color.danger_red'))
      .borderRadius(Constants.SWIPE_DELETE_BTN_RADIUS)
      .onClick(() => {
        this.confirmRemoveHistoryItem(item);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
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
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.controller.clearPlayHistory();
          this.playHistoryVersion = this.controller.playHistoryVersion;
          this.playHistoryItems = [];
          this.playHistorySource.setItems(this.playHistoryItems);
        }
      }
    });
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
    for (let y: number = 0; y < code.size; y++) {
      for (let x: number = 0; x < code.size; x++) {
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

  // US7/FR-016：登出二次确认，取消不登出；确认后 logout 首行 stopPoll 停止轮询中的登录流程
  private confirmLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '确定退出当前 B 站账号吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '退出登录',
        action: (): void => {
          this.logout();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
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
    if (mode === this.colorModeSetting.value) {
      return;
    }
    // 立即生效：Appearance 内部完成持久化（key: colorMode）、应用层 setColorMode 与窗口层颜色重设
    Appearance.setUserMode(mode, getContext());
  }

  // 外观三选项分段按钮：当前生效项强调色淡底高亮
  @Builder
  appearanceOption(label: string, mode: number) {
    Text(label)
      .fontSize(Constants.TOKEN_FONT_BODY)
      .fontColor(this.colorModeSetting.value === mode ?
        $r('app.color.text_primary') : this.textSecondary())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(17)
      .backgroundColor(this.colorModeSetting.value === mode ?
        this.tintBg() : $r('app.color.page_background'))
      .onClick(() => {
        this.selectAppearance(mode);
      })
  }

  private selectAccent(color: string): void {
    if (color === this.accentColor.value) {
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
        .borderRadius(Constants.TOKEN_RADIUS_M)
        .backgroundColor(color)
    }
    .width(32)
    .height(32)
    .borderRadius(Constants.TOKEN_RADIUS_L)
    .justifyContent(FlexAlign.Center)
    .border({
      width: 2,
      color: this.accentColor.value === color ? this.accentColor.value : Color.Transparent
    })
    .onClick(() => {
      this.selectAccent(color);
    })
  }

  // 未登录账号区：一键登录/扫码登录按钮 + 二维码块（US8 卡片内布局）
  @Builder
  private loginControls() {
    Column() {
      if (this.oneKeyLogging) {
        Button('正在等待B站确认…（点击取消）')
          .width('100%')
          .height(40)
          .backgroundColor(this.tintBg())
          .fontColor($r('app.color.text_primary'))
          .borderRadius(Constants.TOKEN_RADIUS_XL)
          .fontSize(Constants.TOKEN_FONT_BODY_M)
          .onClick(() => {
            this.cancelOneKeyLogin();
          })

        Text(this.qrStatus)
          .fontSize(Constants.TOKEN_FONT_BODY)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_S })
      } else {
        Row({ space: Constants.TOKEN_SPACE_M }) {
          Button('B站一键登录')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.accentColor.value)
            .fontColor($r('app.color.fg_on_dark'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .onClick(() => {
              this.startOneKeyLogin();
            })

          Button('扫码登录')
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.page_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .onClick(() => {
              this.showQr = true;
              this.startQrLogin();
            })
        }
        .width('100%')

        if (!this.showQr && this.qrStatus !== '') {
          Text(this.qrStatus)
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: Constants.TOKEN_SPACE_S })
        }
      }

      if (this.showQr) {
        Column() {
          Canvas(this.qrCanvas)
            .id('bili_qr_canvas')
            .width(QR_CANVAS_SIZE)
            .height(QR_CANVAS_SIZE)
            .backgroundColor(Constants.QR_BG_COLOR)
            .borderRadius(Constants.TOKEN_RADIUS_M)
            .onReady(() => {
              this.drawQr();
            })

          Text(this.qrStatus)
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: Constants.TOKEN_SPACE_10 })

          Row({ space: Constants.TOKEN_SPACE_M }) {
            SaveButton({ text: SaveDescription.SAVE, buttonType: ButtonType.Capsule })
              .height(34)
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .fontSize(Constants.TOKEN_FONT_BODY)
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
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .backgroundColor($r('app.color.page_background'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(17)
              .fontSize(Constants.TOKEN_FONT_BODY)
              .onClick(() => {
                if (this.qrExpired) {
                  this.startQrLogin();
                } else {
                  this.showQr = false;
                  this.stopPoll();
                }
              })
          }
          .margin({ top: Constants.TOKEN_SPACE_10 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: Constants.TOKEN_SPACE_M })
      }
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14, top: Constants.TOKEN_SPACE_14, bottom: Constants.TOKEN_SPACE_14 })
  }

  // 手动粘贴 Cookie（US8 卡片内布局）
  @Builder
  private cookieBlock() {
    Column() {
      Text('手动粘贴Cookie（需包含 SESSDATA 和 bili_jct）')
        .fontSize(Constants.TOKEN_FONT_BODY)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row() {
        TextInput({ placeholder: '粘贴浏览器Cookie', text: this.cookieInput })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.page_background'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.placeholder_color'))
          .borderRadius(Constants.TOKEN_RADIUS_10)
          .fontSize(Constants.TOKEN_FONT_BODY)
          .onChange((value: string) => {
            this.cookieInput = value;
          })

        Button('保存')
          .height(40)
          .margin({ left: Constants.TOKEN_SPACE_S })
          .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L })
          .backgroundColor(this.tintBg())
          .fontColor($r('app.color.text_primary'))
          .borderRadius(Constants.TOKEN_RADIUS_10)
          .fontSize(Constants.TOKEN_FONT_BODY)
          .onClick(() => {
            this.saveCookie(this.cookieInput);
          })
      }
      .width('100%')
      .margin({ top: Constants.TOKEN_SPACE_S })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14, top: Constants.TOKEN_SPACE_14, bottom: Constants.TOKEN_SPACE_14 })
  }

  // 「关于」弹窗内的功能条目：圆点 + 说明文字，左侧对齐，支持多行
  @Builder
  aboutFeature(text: string) {
    Row({ space: Constants.TOKEN_SPACE_S }) {
      Text('·')
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontColor(this.accentColor.value)
      Text(text)
        .fontSize(Constants.TOKEN_FONT_BODY)
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
          .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .borderRadius(15)
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .onClick(() => {
            this.showAbout = false;
          })
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_S, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_XS })

      Scroll() {
        Column() {
          Image($r('app.media.startIcon'))
            .width(76)
            .height(76)
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              this.handleAboutIconTap();
            })

          if (this.debugModeOn) {
            SettingsRow({
              title: '调试模式',
              subtitle: '开启后日志同步写入系统 hilog',
              showToggle: true,
              toggleOn: this.debugModeOn,
              toggleChange: (isOn: boolean): void => {
                this.debugModeOn = isOn;
                this.confirmExitDebug();
              }
            })
          }

          Text('BiliRadio')
            .fontSize(Constants.TOKEN_FONT_20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .margin({ top: Constants.TOKEN_SPACE_M })

          Text(`版本 ${this.appVersion}`)
            .fontSize(Constants.TOKEN_FONT_BODY_S)
            .fontColor(this.textSecondary())
            .margin({ top: Constants.TOKEN_SPACE_XS })

          Text('BiliRadio 是一款 B 站音频播放器，把 B 站视频当作纯音乐来听：支持后台播放、进度记忆、锁屏控制。基于 taotie256 的 BiliMusic（Apache 2.0）开发。')
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor(this.textSecondary())
            .lineHeight(20)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: Constants.TOKEN_SPACE_L })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_14 })

          Text('核心功能')
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)

          Column({ space: Constants.TOKEN_SPACE_10 }) {
            this.aboutFeature('订阅收听：UP 主 / 收藏夹 / 合集 / 系列，新集自动标 NEW')
            this.aboutFeature('队列播放：整源入队、搜索、多选管理')
            this.aboutFeature('播放控制：倍速、播放模式、睡眠定时、进度续播')
            this.aboutFeature('外观：深浅色三态 + 六色主题色板')
          }
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_M })

        }
        .width('100%')
        .padding({ left: Constants.TOKEN_SPACE_XL, right: Constants.TOKEN_SPACE_XL, top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_XL })
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

  // 播放历史面板（bindSheet 呈现）：最近播放倒序，点击回放，清空需二次确认；
  // US6：背景与设置页统一（page_background），下拉关闭已被 onWillDismiss 拦截
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
            .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.danger_red'))
            .borderRadius(Constants.TOKEN_RADIUS_L)
            .fontSize(Constants.TOKEN_FONT_BODY_S)
            .onClick(() => {
              this.confirmClearPlayHistory();
            })
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })

      if (this.playHistoryItems.length === 0) {
        Column() {
          Text('暂无播放历史，听歌后会自动记录')
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        Stack() {
          List({ space: 0, scroller: this.historyScroller }) {
            LazyForEach(this.playHistorySource, (item: PlayHistoryItem) => {
            ListItem() {
              Row() {
                CoverThumb({ cover: item.cover })

                Column() {
                  Text(item.title)
                    .fontSize(Constants.TOKEN_FONT_BODY_M)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.historyMetaText(item))
                    .fontSize(Constants.TOKEN_FONT_AUX)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: Constants.TOKEN_SPACE_10 })
              }
              .width('100%')
              .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
              .backgroundColor(this.pressedKey === item.bvid ? $r('app.color.item_pressed_background') : Color.Transparent)
              .onTouch((e: TouchEvent): void => {
                if (e.type === TouchType.Down) {
                  this.pressedKey = item.bvid;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.pressedKey = '';
                }
              })
              .onClick(() => {
                this.replayHistory(item);
              })
            }
            // 左滑删除（US1 双触发）：SwipeActionItem——点垃圾桶/滑过阈值均进确认弹窗
            .swipeAction({
              end: {
                builder: (): void => {
                  this.historyDeleteAction(item);
                },
                onAction: (): void => {
                  this.confirmRemoveHistoryItem(item);
                }
              }
            })
          }, (item: PlayHistoryItem) => `${item.bvid}_${item.viewAt}_${item.progress}`)
          }
          .width('100%')
          .height('100%')
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // 音质档位选择面板（audio-quality-settings）：单 sheet + qualityEditTarget 标记当前编辑项；
  // 当前档 ✓ 高亮，选中即持久化并关闭；未登录仅渲染「最高」「64K」（FR-009）
  @Builder
  qualitySheetPanel() {
    Column() {
      Text(this.qualityEditTarget === 'wifi' ? 'Wi-Fi 默认音质' : '移动网络默认音质')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_S })

      ForEach(this.qualityOptions(), (tier: QualityTier) => {
        Row() {
          Text(AudioQuality.label(tier))
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontColor(this.currentEditTier() === tier
              ? this.accentColor.value : this.textPrimary())
            .layoutWeight(1)
          if (this.currentEditTier() === tier) {
            Text('✓')
              .fontSize(Constants.TOKEN_FONT_BODY_L)
              .fontColor(this.accentColor.value)
          }
        }
        .width('100%')
        .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: 13, bottom: 13 })
        .onClick(() => {
          this.applyQualityTier(tier);
        })
      }, (tier: QualityTier) => `${tier}`)

      if (!this.isLogged) {
        Text('未登录时最高 64K，登录后可用更高音质')
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor(this.accentColor.value)
          .width('100%')
          .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_L })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.sheet_background'))
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(36)
          .height(36)
          .borderRadius(Constants.TOKEN_RADIUS_18)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.navPathStack.pop();
          })

          Text('设置')
            .fontSize(Constants.TOKEN_FONT_24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .margin({ left: Constants.TOKEN_SPACE_10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_6, bottom: Constants.TOKEN_SPACE_10 })

        Stack() {
          Scroll(this.settingsScroller) {
            Column() {
              SettingsGroup({ title: '账号' }) {
                if (this.isLogged) {
                  SettingsRow({
                    title: this.loginName,
                    rowIcon: $r('sys.symbol.person'),
                    showDivider: true
                  })
                  SettingsRow({
                    title: '退出登录',
                    danger: true,
                    rowAction: (): void => {
                      this.confirmLogout();
                    }
                  })
                } else {
                  this.loginControls()
                  Divider()
                    .color($r('app.color.track_color'))
                    .margin({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L })
                  this.cookieBlock()
                }
              }

              SettingsGroup({ title: '播放设置' }) {
                SettingsRow({
                  title: '启动时自动播放',
                  subtitle: '打开应用后自动继续上次进度',
                  showToggle: true,
                  toggleOn: this.autoPlayOnStart,
                  showDivider: true,
                  toggleChange: (isOn: boolean): void => {
                    this.autoPlayOnStart = isOn;
                    AppStore.putNumber(Constants.KEY_AUTO_PLAY_ON_START, isOn ? 1 : 0);
                  }
                })
                SettingsRow({
                  title: '后台打断续播',
                  subtitle: '来电等打断结束后自动继续播放',
                  showToggle: true,
                  toggleOn: this.interruptResume,
                  showDivider: true,
                  toggleChange: (isOn: boolean): void => {
                    this.interruptResume = isOn;
                    AppStore.putNumber(Constants.KEY_INTERRUPT_RESUME, isOn ? 1 : 0);
                  }
                })
                SettingsRow({
                  title: 'Wi-Fi 默认音质',
                  valueText: AudioQuality.label(this.wifiQuality),
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    this.openQualitySheet('wifi');
                  }
                })
                SettingsRow({
                  title: '移动网络默认音质',
                  valueText: AudioQuality.label(this.cellularQuality),
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    this.openQualitySheet('cellular');
                  }
                })
                if (!this.isLogged) {
                  Text('未登录时最高 64K，登录后可用更高音质')
                    .fontSize(Constants.TOKEN_FONT_BODY_S)
                    .fontColor(this.accentColor.value)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_XS, bottom: Constants.TOKEN_SPACE_10 })
                }
                SettingsRow({
                  title: '仅在 Wi-Fi 环境播放',
                  subtitle: '非 Wi-Fi 网络播放需手动确认',
                  showToggle: true,
                  toggleOn: this.wifiOnlyDownload,
                  toggleChange: (isOn: boolean): void => {
                    this.wifiOnlyDownload = isOn;
                    AppStore.putNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, isOn ? 1 : 0);
                  }
                })
              }

              SettingsGroup({ title: '外观' }) {
                Row({ space: Constants.TOKEN_SPACE_S }) {
                  this.appearanceOption('跟随系统', Appearance.MODE_FOLLOW_SYSTEM)
                  this.appearanceOption('浅色', Appearance.MODE_LIGHT)
                  this.appearanceOption('深色', Appearance.MODE_DARK)
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14, top: Constants.TOKEN_SPACE_14, bottom: Constants.TOKEN_SPACE_14 })

                Divider()
                  .color($r('app.color.track_color'))
                  .margin({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L })

                Row({ space: Constants.TOKEN_SPACE_M }) {
                  ForEach(Constants.ACCENT_PRESETS, (color: string) => {
                    this.accentSwatch(color)
                  }, (color: string) => color)
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_14 })
              }

              SettingsGroup({ title: '通用' }) {
                SettingsRow({
                  title: '播放历史',
                  rowIcon: $r('sys.symbol.clock'),
                  valueText: this.controller.playHistory.length > 0
                    ? `${this.controller.playHistory.length} 条` : '',
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    this.openPlayHistory();
                  }
                })
                SettingsRow({
                  title: '日志查询',
                  rowIcon: $r('sys.symbol.doc_text'),
                  valueText: this.logCount > 0 ? `${this.logCount} 条` : '',
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    this.openLogPage();
                  }
                })
                SettingsRow({
                  title: '关于',
                  rowIcon: $r('sys.symbol.info_circle'),
                  showArrow: true,
                  rowAction: (): void => {
                    this.showAbout = true;
                  }
                })
              }

              if (this.statusMsg !== '') {
                Text(this.statusMsg)
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_XL })
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_XXS,
              bottom: (this.miniPlayerVisible.value ? Constants.MINI_PLAYER_CLEARANCE : 24) + this.navBarHeight.value })
            // ponytail: about 的 bindSheet 挂外层根 Column 或内层链首位时在 API 24 平板打开即自动关闭；单挂内容容器（HEAD 版 logSheet 同款宿主）稳定
            .bindSheet(this.showAbout, this.aboutSheet(), {
              height: '75%',
              dragBar: true,
              showClose: false,
              backgroundColor: $r('app.color.page_background'),
              preferType: SheetType.BOTTOM,
              onDisappear: (): void => {
                this.showAbout = false;
              }
            })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .layoutWeight(1)
        .bindSheet(this.showQualitySheet, this.qualitySheetPanel(), {
          height: '40%',
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.page_background'),
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showQualitySheet = false;
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .bindSheet(this.showPlayHistory.value, this.playHistoryPanel(), {
        height: '62%',
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.page_background'),
        preferType: SheetType.BOTTOM,
        onDisappear: (): void => {
          this.showPlayHistory.value = false;
        },
        onWillDismiss: (dismiss: DismissSheetAction) => {
          // US6：面板内下拉不关闭（只留蒙层点击/系统返回/清空按钮等其余关闭路径）
          if (dismiss.reason === DismissReason.SLIDE_DOWN) {
            return;
          }
          dismiss.dismiss();
        }
      })
    }
    .hideTitleBar(true)
    .onWillAppear(() => {
      // US7/T021：设置页在台标志提前到转场开始时置位——驱动首页播放胶囊在本页隐藏；
      // R4 US2：置位前先取消未触发的复位定时器（快速往返竞态消解）
      if (this.onSettingsPageTimer >= 0) {
        clearTimeout(this.onSettingsPageTimer);
        this.onSettingsPageTimer = -1;
      }
      connectBool(Constants.AS_ON_SETTINGS_PAGE, false).value = true;
    })
    .onShown(() => {
      // US5：日志页返回后刷新角标计数——pushPathByName 的 onPop 仅在 pop(result) 带 result 时触发，
      // 日志页返回按钮为无参 pop()，onPop 永不回调，须在设置页重新可见时主动重读
      // R4 US2：同取消 pending 定时器并补置位 true——修复日志页返回后标志残留 false 的缺口
      if (this.onSettingsPageTimer >= 0) {
        clearTimeout(this.onSettingsPageTimer);
        this.onSettingsPageTimer = -1;
      }
      connectBool(Constants.AS_ON_SETTINGS_PAGE, false).value = true;
      this.logCount = Logger.count();
    })
    .onWillDisappear(() => {
      this.onSettingsPageTimer = setTimeout(() => {
        this.onSettingsPageTimer = -1;
        connectBool(Constants.AS_ON_SETTINGS_PAGE, false).value = false;
      }, Constants.NAV_EXIT_TRANSITION_MS);
    })
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
      // US5：浮层/队列统一交 BackHandler 分层关闭（含浮层与历史面板同开先关面板语义），
      // 无可关走本页自身面板分支
      if (dismissOverlaysForBack()) {
        return true;
      }
      if (this.showQualitySheet) {
        this.showQualitySheet = false;
        return true;
      }
      if (this.showPlayHistory.value) {
        this.showPlayHistory.value = false;
        return true;
      }
      return false;
    })
  }
}
