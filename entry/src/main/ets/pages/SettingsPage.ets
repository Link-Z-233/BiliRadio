import { BiliService, QrPollStatus, QrPollResult } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { SecureStore } from '../service/SecureStore';
import { PlayerController } from '../service/PlayerController';
import { QrCode, QrEcc } from '../service/QrCode';
import { AppContext } from '../service/AppContext';
import { AppStore } from '../service/AppStore';
import { Appearance } from '../service/Appearance';
import { BusinessError } from '@kit.BasicServicesKit';
import { OpenLinkOptions, bundleManager } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SettingsGroup } from '../component/SettingsGroup';
import { SettingsRow } from '../component/SettingsRow';
import { Constants } from '../service/Constants';
import { registerSettingsBack } from '../service/BackHandler';
import { connectBool, connectNum, connectStr, NumState, StrState } from '../service/V2State';
import { Logger } from '../service/Logger';
import { AudioQuality, QualityTier } from '../model/AudioQuality';

const QR_CANVAS_SIZE: number = 280;

// 设置页（US8 HarmonyOS 系统风格重写）：大标题 + 分组卡片（SettingsGroup/SettingsRow），
// 登录 / 播放设置 / 外观（含主题色板）/ 播放历史入口 / 日志 / 关于功能全保留；
// Index 树内层级承载（设置层，导航+胶囊之上、播放浮层之下），历史面板为 Index L4 独立层
@ComponentV2
export struct SettingsPage {
  @Local showQr: boolean = false;
  @Local isLogged: boolean = false;
  // 冷启动恢复完成前的账号区占位（避免闪现「未登录」），initDone 广播后翻 false
  @Local accountLoading: boolean = true;
  @Local loginName: string = '未登录';
  @Local avatarUrl: string = '';
  @Local cookieInput: string = '';
  @Local statusMsg: string = '';
  @Local qrStatus: string = '';
  @Local qrExpired: boolean = false;
  @Local qrUrl: string = '';
  @Local oneKeyLogging: boolean = false;
  @Local showAbout: boolean = false;
  @Local debugModeOn: boolean = false;
  @Local appVersion: string = '';

  @Local autoPlayOnStart: boolean = false;
  // 历史同步开关（v0.5-part1-play-history-sync US4）：读写 KEY_HISTORY_SYNC（默认开），仅登录时展示
  @Local historySyncOn: boolean = true;
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
  private settingsScroller: Scroller = new Scroller();
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};
  private tapCount: number = 0;
  private lastTapTs: number = 0;

  aboutToAppear(): void {
    this.refreshLoginState();
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    this.appVersion = bundleInfo.versionName;
    this.autoPlayOnStart = AppStore.getNumber(Constants.KEY_AUTO_PLAY_ON_START, 0) === 1;
    this.historySyncOn = AppStore.getNumber(Constants.KEY_HISTORY_SYNC, 1) === 1;
    this.interruptResume = AppStore.getNumber(Constants.KEY_INTERRUPT_RESUME, 0) === 1;
    this.wifiOnlyDownload = AppStore.getNumber(Constants.KEY_WIFI_ONLY_DOWNLOAD, 0) === 1;
    this.wifiQuality = this.readStoredTier(Constants.KEY_WIFI_AUDIO_QUALITY, QualityTier.MAX);
    this.cellularQuality = this.readStoredTier(Constants.KEY_CELLULAR_AUDIO_QUALITY, QualityTier.Q132K);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.refreshLoginState();
    }, 'SettingsPage');
    // debugMode 开关显示：仅读 AppStore 供 UI；Logger 恢复与启动提醒已前移 Index 冷启动链路（v0.4-Part1-ux-fixes US10）
    this.debugModeOn = AppStore.getNumber(Constants.KEY_DEBUG_MODE, 0) === 1;
    registerSettingsBack((): boolean => {
      if (this.showQualitySheet) {
        this.showQualitySheet = false;
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    registerSettingsBack(undefined);
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
    this.stopPoll();
  }

  private refreshLoginState(): void {
    const session: BiliSession = BiliSession.getInstance();
    this.accountLoading = !this.controller.isInited();
    this.isLogged = session.isLogged();
    if (session.isLogged()) {
      this.loginName = session.uname !== '' ? session.uname : `已登录 (UID ${session.mid})`;
      this.avatarUrl = session.face;
    } else {
      this.loginName = '未登录';
      this.avatarUrl = '';
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

  // 档位选择器可选项（v0.4-Part1-ux-fixes FR-014）：按登录+会员态过滤；nav 失败时 vipStatus 保持 0 按非会员
  private qualityOptions(): QualityTier[] {
    return AudioQuality.availableTiers(this.isLogged, BiliSession.getInstance().vipStatus);
  }

  // 当前编辑项的已存档位（选择器 ✓ 高亮依据）：不可用档位显示层收敛（US2 场景 4）
  private currentEditTier(): QualityTier {
    const stored: QualityTier = this.qualityEditTarget === 'wifi' ? this.wifiQuality : this.cellularQuality;
    return AudioQuality.clampTier(stored, this.isLogged, BiliSession.getInstance().vipStatus);
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
      this.getUIContext().getPromptAction().showToast({ message: '调试模式已开启，可在下方开关关闭' });
      return;
    }
    Logger.setDebugMode(true);
    AppStore.putNumber(Constants.KEY_DEBUG_MODE, 1);
    this.debugModeOn = true;
    this.getUIContext().getPromptAction().showToast({ message: '已开启调试模式' });
  }

  private confirmExitDebug(): void {
    this.getUIContext().showAlertDialog({
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
          this.getUIContext().getPromptAction().showToast({ message: '已退出调试模式' });
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
    connectBool(Constants.AS_SHOW_LOG_PAGE, false).value = true;
  }

  // 外链统一跳转（US7）：四链接复用——二次确认后 openLink 拉起系统浏览器，失败 toast
  private confirmOpenLink(url: string): void {
    const ctx = AppContext.require();
    this.getUIContext().showAlertDialog({
      title: Constants.DIALOG_OPEN_LINK_TITLE,
      message: url,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '打开',
        fontColor: this.accentColor.value,
        action: (): void => {
          const opts: OpenLinkOptions = { appLinkingOnly: false };
          ctx.openLink(url, opts).catch((error: BusinessError) => {
            this.getUIContext().getPromptAction().showToast({ message: '打开链接失败' });
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
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
    const ctx = AppContext.require();
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
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().get('bili_qr_canvas');
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(AppContext.require());
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
    this.getUIContext().showAlertDialog({
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
    Appearance.setUserMode(mode, AppContext.require());
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
    Appearance.setAccentColor(color, AppContext.require());
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

  // 「关于」弹窗（v0.4-Part1-ux-fixes US7 重写）：FR-009 确切文案，四链接二次确认跳浏览器
  @Builder
  aboutSheet() {
    Column() {
      Row() {
        Blank()
        Button('完成')
          .height(30)
          .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(Constants.GLASS_BLUR)
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

          Text('把 B 站视频当播客听的鸿蒙音频应用：只取声音，不亮屏幕。订阅 UP 主、收藏夹、合集、系列，新视频自动标 NEW，一键入队；亦可通过粘贴链接或 BV 号手动添加。')
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
            this.aboutFeature('订阅追更：UP 主 / 收藏夹 / 合集 / 系列四类源，新视频自动标 NEW')
            this.aboutFeature('即点即听：粘贴链接或 BV 号，立即播放音频')
            this.aboutFeature('随心播控：倍速、随机循环、睡眠定时、断点续播')
            this.aboutFeature('后台不断：锁屏、控制中心、实况窗都能控制播放')
            this.aboutFeature('听得讲究：四档音质可选，深浅色主题随心换')
          }
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_M })

          Text('关于本项目')
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: Constants.TOKEN_SPACE_L })

          Text() {
            Span('代码完全由 AI 生成（Vibecoding 作品），参考开源项目 ')
              .fontColor(this.textSecondary())
            Span('BiliMusic')
              .fontColor(this.accentColor.value)
              .onClick(() => {
                this.confirmOpenLink(Constants.LINK_BILIMUSIC_REPO);
              })
            Span('（Apache 2.0）、')
              .fontColor(this.textSecondary())
            Span('PiliPlus')
              .fontColor(this.accentColor.value)
              .onClick(() => {
                this.confirmOpenLink(Constants.LINK_PILIPLUS_REPO);
              })
            Span('（GPL-3.0）开发。个人学习自用作品，与哔哩哔哩官方无关。')
              .fontColor(this.textSecondary())
          }
          .fontSize(Constants.TOKEN_FONT_BODY)
          .lineHeight(20)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: Constants.TOKEN_SPACE_M })

          Text('项目地址')
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: Constants.TOKEN_SPACE_L })

          Column({ space: Constants.TOKEN_SPACE_10 }) {
            this.aboutLinkRow('GitCode', Constants.LINK_PROJECT_GITCODE)
            this.aboutLinkRow('GitHub', Constants.LINK_PROJECT_GITHUB)
          }
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_M })

        }
        .width('100%')
        .padding({ left: Constants.TOKEN_SPACE_XL, right: Constants.TOKEN_SPACE_XL, top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_XL })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_panel_background'))
    .backdropBlur(Constants.GLASS_BLUR)
    .border({ width: { top: 1 }, color: $r('app.color.sheet_top_separator') })
  }

  // 关于页项目地址行（US7）：label + URL 一行，点击走统一外链确认
  @Builder
  aboutLinkRow(label: string, url: string) {
    Row({ space: Constants.TOKEN_SPACE_S }) {
      Text(label)
        .fontSize(Constants.TOKEN_FONT_BODY)
        .fontColor(this.textPrimary())
      Text(url)
        .fontSize(Constants.TOKEN_FONT_BODY)
        .fontColor(this.accentColor.value)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .onClick(() => {
      this.confirmOpenLink(url);
    })
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
      } else if (BiliSession.getInstance().vipStatus !== 1) {
        Text('192K/Hi-Res/杜比需大会员')
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
    Stack() {
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
            connectBool(Constants.AS_SHOW_SETTINGS_PAGE, false).value = false;
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
                if (this.accountLoading) {
                  SettingsRow({
                    title: '正在恢复登录状态…',
                    rowIcon: $r('sys.symbol.person')
                  })
                } else if (this.isLogged) {
                  SettingsRow({
                    title: this.loginName,
                    rowIcon: $r('sys.symbol.person'),
                    avatarUrl: this.avatarUrl,
                    vipBadge: BiliSession.getInstance().vipStatus === 1,
                    showDivider: true
                  })
                  SettingsRow({
                    title: '历史同步',
                    subtitle: '播放进度与 B 站云端双向同步，支持跨设备续播',
                    showToggle: true,
                    toggleOn: this.historySyncOn,
                    showDivider: true,
                    toggleChange: (isOn: boolean): void => {
                      this.historySyncOn = isOn;
                      AppStore.putNumber(Constants.KEY_HISTORY_SYNC, isOn ? 1 : 0);
                    }
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
                  valueText: AudioQuality.label(AudioQuality.clampTier(this.wifiQuality, this.isLogged, BiliSession.getInstance().vipStatus)),
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    this.openQualitySheet('wifi');
                  }
                })
                SettingsRow({
                  title: '移动网络默认音质',
                  valueText: AudioQuality.label(AudioQuality.clampTier(this.cellularQuality, this.isLogged, BiliSession.getInstance().vipStatus)),
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
                } else if (BiliSession.getInstance().vipStatus !== 1) {
                  Text('192K/Hi-Res/杜比需大会员')
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
                  showArrow: true,
                  showDivider: true,
                  rowAction: (): void => {
                    connectBool(Constants.AS_SHOW_PLAY_HISTORY, false).value = true;
                  }
                })
                SettingsRow({
                  title: '日志查询',
                  rowIcon: $r('sys.symbol.doc_text'),
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
              bottom: Constants.MINI_PLAYER_CLEARANCE + this.navBarHeight.value })
            // ponytail: about 的 bindSheet 挂外层根 Column 或内层链首位时在 API 24 平板打开即自动关闭；单挂内容容器（HEAD 版 logSheet 同款宿主）稳定
            .bindSheet(this.showAbout, this.aboutSheet(), {
              height: '75%',
              dragBar: true,
              showClose: false,
              backgroundColor: Color.Transparent,
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
    }
    .width('100%')
    .height('100%')
  }
}
