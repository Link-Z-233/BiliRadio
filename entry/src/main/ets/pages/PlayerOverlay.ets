import { PlayerController, PlayMode as MusicPlayMode, PLAYBACK_RATES, PLAY_MODES } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliService } from '../service/BiliService';
import { Constants } from '../service/Constants';
import { CoverUrl } from '../service/CoverUrl';
import { Appearance } from '../service/Appearance';
import { CoverPalette } from '../service/CoverPalette';
import { SleepTimerController } from '../service/SleepTimerController';
import { AppStore } from '../service/AppStore';
import { BiliSession } from '../service/BiliSession';
import { AudioTrack, AudioQuality, QualityTier } from '../model/AudioQuality';
import { connectBool, connectNum, connectStr, BoolState, NumState, StrState } from '../service/V2State';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 封面光晕两态参数：静止亮度 / 活动亮度 / 播放态淡入时长（v0.3 US1：原无限呼吸已收敛为一次性过渡）
const GLOW_IDLE: number = 0.35;
const GLOW_ACTIVE: number = 0.8;
const GLOW_FADE_IN_MS: number = 3200;
const GLOW_FADE_OUT_MS: number = 800;

// 下滑退出播放层的位移阈值（vp）：内容已到顶部时，下滑超过该距离才退出
const PLAYER_DISMISS_SWIPE: number = 80;

// ±15s 进度微调步长已收敛至 Constants.SEEK_STEP_MS（全库唯一常量点，与播控中心共用）

@ComponentV2
export struct PlayerOverlay {
  @Local isPrepared: boolean = false;
  @Local isPreparing: boolean = false;
  @Local playIntent: boolean = false;
  @Local currentTime: number = 0;
  @Local duration: number = 0;
  // 进度条受控值：拖动时实时跟随手指，松开才真正 seek，避免受控值回弹导致拖不动
  @Local sliderValue: number = 0;
  @Local isSeeking: boolean = false;
  @Local statusMsg: string = '';
  @Local trackTitle: string = '未在播放';
  @Local trackCover: string = '';
  @Local ownerName: string = '';
  @Local ownerFace: string = '';
  @Local playMode: MusicPlayMode = MusicPlayMode.SEQUENTIAL;
  @Local playbackRate: number = 1.0;
  @Local showSpeed: BoolState = connectBool(Constants.AS_SHOW_SPEED, false);
  @Local showMode: BoolState = connectBool(Constants.AS_SHOW_MODE, false);
  @Local showSleepTimer: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER, false);
  @Local showSleepTimerPicker: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
  @Local showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  // 浮层显示标志（KI-5）：与 Index 树内条件渲染的显隐同源；
  // 任何关闭路径先将该标志置 false，随后组件卸载触发 aboutToDisappear
  @Local showOverlayActive: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  @Local statusBarHeight: NumState = connectNum(Constants.AS_STATUS_BAR_HEIGHT, 38);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  // 宽屏断言（平板竖屏适配）：根 Stack onAreaChange 维护（首次布局与旋转均触发）；
  // 宽屏下底栏内部间距按 overlayHeightVp 比例拉大，窄屏走原固定间距
  @Local isWide: boolean = false;
  @Local overlayHeightVp: number = 0;
  // 主题色：全部着色点运行时跟随，衍生色经 Appearance.hexWithAlpha 计算
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  // 生效深浅色（1=浅色 2=深色）：驱动深浅色差异化 alpha
  @Local colorModeResolved: NumState = connectNum(Constants.AS_COLOR_MODE_RESOLVED, 1);

  // 封面取色基色（palette-glow）：光晕着色源，'' = 未取到回退主题色
  @Local paletteColor: string = '';
  // 背景渐变淡入进度（palette-bg）：0-1，首取色 animateTo 拉满
  @Local paletteReveal: number = 0;
  @Local glowStrength: number = GLOW_IDLE;
  @Local playBtnScale: number = 1;
  @Local prevBtnScale: number = 1;
  @Local nextBtnScale: number = 1;
  @Local trackIndex: number = -1;
  @Local playlistCount: number = 0;
  @Local showDetail: boolean = false;
  // 详情箭头指向（T011）：独立于 showDetail，sheet 任何关闭路径即时翻转
  @Local detailArrowUp: boolean = false;
  @Local sleepTimerActive: boolean = false;
  // 播完暂停模式（queue-redesign US3）：激活时 timer 入口仅图标高亮，不显示剩余数字
  @Local sleepTimerPlayToEof: boolean = false;
  @Local sleepTimerRemaining: number = 0;
  @Local pickerHour: number = 0;
  @Local pickerMinute: number = 0;
  @Local trackView: number = 0;
  @Local trackPubdate: number = 0;
  @Local trackDesc: string = '';
  // 音质面板镜像（audio-quality-settings US3）：syncFrom 增量同步 controller 公开音质状态
  @Local showQuality: boolean = false;
  @Local availableTracks: AudioTrack[] = [];
  @Local currentQualityCode: number = 0;
  @Local currentTrackSource: string = '';
  private trackBvid: string = '';
  private wasPlayIntent: boolean = false;
  // 取色防抖键（palette-glow）：当前已请求取色的 bvid，防重复请求
  private paletteBvid: string = '';
  // 简介懒加载（T014）：进行中标志防并发；已尝试的 bvid 防重复请求
  private descLoading: boolean = false;
  private descTriedBvid: string = '';
  private controller: PlayerController = PlayerController.getInstance();
  // 内容滚动控制器：滑动手势结束时据此判断内容是否已滚到顶部
  private contentScroller: Scroller = new Scroller();

  private textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  private textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }

  // ===== 主题色衍生取色（T006）：alpha 沿用 base/dark 资源键原有取值 =====

  private isDarkMode(): boolean {
    return this.colorModeResolved.value === 2;
  }

  // 播放键底色/面板选中底色：主题色 + material_tint_primary 原 alpha（0x59 ≈ 0.349，深浅色同值）
  private tintBg(): string {
    return Appearance.hexWithAlpha(this.accentColor.value, 0.349);
  }

  // ===== 播放按钮尺寸同源（US1）：按钮直径为唯一尺寸源，缓冲加载指示与图标字号由此派生 =====

  // 封面光晕梯度：取色基色（无则主题色） + halo_pink_0..3 原 alpha 序列（浅色 [0x80,0x3D,0x14,0x00] / 深色 [0x66,0x29,0x0D,0x00]）
  private haloColors(): Array<[ResourceColor, number]> {
    const alphas: number[] = this.isDarkMode() ? [0.4, 0.161, 0.051, 0] : [0.502, 0.239, 0.078, 0];
    // 深色外观光晕基色经 glowTint 压明度保色相；纯灰白取色（glowTint 返回 ''）回退主题色，保证光晕始终彩色
    const tinted: string = this.paletteColor !== '' ?
      CoverPalette.glowTint(this.paletteColor, this.isDarkMode()) : '';
    const base: string = tinted !== '' ? tinted : this.accentColor.value;
    const colors: Array<[ResourceColor, number]> = [
      [Appearance.hexWithAlpha(base, alphas[0]), 0],
      [Appearance.hexWithAlpha(base, alphas[1]), 0.45],
      [Appearance.hexWithAlpha(base, alphas[2]), 0.75],
      [Appearance.hexWithAlpha(base, alphas[3]), 1]
    ];
    return colors;
  }

  // 换曲取色（palette-glow/palette-bg）：bvid 防抖；结果回填经一致性校验丢弃过期响应；失败/空回退主题色
  private requestPalette(rawCover: string): void {
    const bvid: string = this.paletteBvid;
    CoverPalette.dominantOf(bvid, rawCover).then((hex: string): void => {
      if (this.paletteBvid !== bvid) {
        return;
      }
      this.applyPalette(hex === '' ? this.accentColor.value : hex);
    }).catch((): void => {
      if (this.paletteBvid !== bvid) {
        return;
      }
      this.applyPalette(this.accentColor.value);
    });
  }

  // 应用取色：光晕基色直接用取色；首取色背景渐变淡入（此后换曲直接换色）
  private applyPalette(color: string): void {
    this.paletteColor = color;
    if (this.paletteReveal === 0) {
      this.getUIContext().animateTo({ duration: Constants.PALETTE_BG_REVEAL_MS, curve: Curve.FastOutSlowIn }, (): void => {
        this.paletteReveal = 1;
      });
    }
  }

  // 背景衍生色渐变（palette-bg）：washTint 压饱和/定明度后的柔和色铺顶部渐变（幅度有限），
  // 非取色态全透明（纯 page_background）
  private bgStops(): Array<[ResourceColor, number]> {
    if (this.paletteColor === '') {
      return [[Color.Transparent, 0], [Color.Transparent, 1]];
    }
    const tint: string = CoverPalette.washTint(this.paletteColor, this.isDarkMode());
    if (tint === '') {
      return [[Color.Transparent, 0], [Color.Transparent, 1]];
    }
    return [
      [Appearance.hexWithAlpha(tint, this.paletteReveal), 0],
      [Appearance.hexWithAlpha(tint, 0), 1]
    ];
  }


  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.wasPlayIntent = this.playIntent;
    // KI-5：挂载期状态变更在 API 24 疑似引发 ModalPage 渲染管线冻结（仅渲染首帧），
    // 光晕强度初始化延后到构建完成后的下一拍执行，延迟一帧对视觉无感知影响
    setTimeout((): void => {
      this.updateGlow();
    }, 0);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
      // 光晕强度以意图翻转为动画触发源（US1 意图先行）
      if (this.playIntent !== this.wasPlayIntent) {
        this.wasPlayIntent = this.playIntent;
        this.updateGlow();
      }
    }, 'PlayerOverlay');
    this.unsubscribeSleepTimer = SleepTimerController.getInstance().subscribe((): void => {
      this.syncSleepTimer();
    }, 'PlayerOverlay');
    this.syncSleepTimer();
  }

  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积截断广播
  private unsubscribePlayer: () => void = (): void => {};
  // 睡眠定时退订句柄（KI-2）：同型修复，避免播放层反复挂载导致秒级回调监听器累积
  private unsubscribeSleepTimer: () => void = (): void => {};

  aboutToDisappear(): void {
    // KI-5：API 24 上 bindContentCover 内容组件挂载后 ~10ms 会收到伪 aboutToDisappear（浮层实际仍显示）。
    // 此时必须跳过退订，监听器保活才能继续接收 emitUi，否则 @State 冻结在挂载快照、按钮 UI 不再刷新。
    // 真关闭时 $$ 双向绑定先将 showOverlayActive 置 false，走到这里的退订才是真销毁；
    // 若真销毁时序反了（先回调后翻转），漏退订的旧监听器由 subscribe 的同 owner 单槽覆盖兜底清理。
    if (this.showOverlayActive.value) {
      // KI-5 诊断：API 24 上该伪回调若持续出现且渲染仍冻结，
      // 则需放弃 bindContentCover（ModalPage）改用树内条件渲染承载播放层
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG,
        'PlayerOverlay aboutToDisappear skipped: overlay still visible (KI-5 probe)');
      return;
    }
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
    this.unsubscribeSleepTimer();
    this.unsubscribeSleepTimer = (): void => {};
  }

  private syncSleepTimer(): void {
    const st: SleepTimerController = SleepTimerController.getInstance();
    this.sleepTimerActive = st.active;
    this.sleepTimerPlayToEof = st.isPlayToEofActive();
    this.sleepTimerRemaining = st.getRemainingSeconds();
  }

  // 光晕动画改由光晕节点自身 animation 属性承载（节点级隔离）：animateTo 会波及同帧内
  // 播放键图标的透明度翻转，产生数秒交叉渐变（按钮"每次按都渐变"的根因）
  private updateGlow(): void {
    this.glowStrength = this.playIntent ? GLOW_ACTIVE : GLOW_IDLE;
  }

  // 缩放回弹延后一拍启动：与按键状态翻转解耦，避免 animateTo 同帧污染图标切换（交叉渐变）
  private popPlay(): void {
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
        this.playBtnScale = 0.88;
      });
      setTimeout((): void => {
        this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
          this.playBtnScale = 1;
        });
      }, 120);
    }, 0);
  }

  private popPrev(): void {
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
        this.prevBtnScale = 0.9;
      });
      setTimeout((): void => {
        this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
          this.prevBtnScale = 1;
        });
      }, 120);
    }, 0);
  }

  private popNext(): void {
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
        this.nextBtnScale = 0.9;
      });
      setTimeout((): void => {
        this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
          this.nextBtnScale = 1;
        });
      }, 120);
    }, 0);
  }

  // 详情简介懒加载（T014）：空简介时后台拉取；回填写入队列条目避免下次 syncFrom 覆盖本地态；
  // 失败静默保留「暂无简介」占位（无 toast），每个 bvid 单次会话内只尝试一次
  private loadTrackDescIfNeeded(): void {
    if (this.descLoading || this.trackDesc !== '' || this.trackBvid === '' ||
      this.descTriedBvid === this.trackBvid) {
      return;
    }
    this.descLoading = true;
    this.descTriedBvid = this.trackBvid;
    BiliService.fetchVideoInfo(this.trackBvid).then((video: BiliVideo): void => {
      this.descLoading = false;
      if (video.desc !== '') {
        this.trackDesc = video.desc;
        const idx: number = this.controller.currentIndex;
        if (idx >= 0 && idx < this.controller.playlist.length &&
          this.controller.playlist[idx].bvid === this.trackBvid) {
          this.controller.playlist[idx].desc = video.desc;
        }
      }
    }).catch((): void => {
      this.descLoading = false;
    });
  }

  private syncFrom(c: PlayerController): void {
    this.isPrepared = c.isPrepared;
    this.isPreparing = c.isPreparing;
    this.playIntent = c.playIntent;
    this.currentTime = c.currentTime;
    this.duration = c.duration;
    // US2：切剧瞬间（controller 进入 preparing）复位拖拽状态，
    // 避免切剧时正在拖动进度条导致 sliderValue 永久停更
    if (c.isPreparing && this.isSeeking) {
      this.isSeeking = false;
    }
    if (!this.isSeeking) {
      this.sliderValue = c.duration > 0 ? c.currentTime / c.duration * 100 : 0;
    }
    this.statusMsg = c.statusMsg;
    this.playMode = c.playMode;
    this.playbackRate = c.playbackRate;
    this.availableTracks = c.availableTracks;
    this.currentQualityCode = c.currentQualityCode;
    this.currentTrackSource = c.currentTrackSource;
    this.playlistCount = c.playlist.length;
    if (c.currentIndex >= 0 && c.currentIndex < c.playlist.length) {
      const item: BiliVideo = c.playlist[c.currentIndex];
      // US6：大封面按显示尺寸取图，非 Wi-Fi 降省流档（UP 头像保持原图，不参与取档）
      const wifi: boolean = c.isWifiNow();
      const coverW: number = wifi ? Constants.COVER_BIG_W : Constants.COVER_SAVER_W;
      const coverH: number = wifi ? Constants.COVER_BIG_H : Constants.COVER_SAVER_H;
      this.trackTitle = item.title;
      this.trackCover = CoverUrl.sized(item.cover, coverW, coverH);
      this.ownerName = item.ownerName;
      this.ownerFace = item.ownerFace;
      this.trackBvid = item.bvid;
      this.trackIndex = c.currentIndex;
      this.trackView = item.view;
      this.trackPubdate = item.pubdate;
      this.trackDesc = item.desc;
      // 换曲才重新取色（palette-glow），同曲广播不重复请求
      if (item.bvid !== this.paletteBvid) {
        this.paletteBvid = item.bvid;
        this.requestPalette(item.cover);
      }
    } else {
      this.trackTitle = '未在播放';
      this.trackCover = '';
      this.ownerName = '';
      this.ownerFace = '';
      this.trackBvid = '';
      this.trackIndex = -1;
      this.trackView = 0;
      this.trackPubdate = 0;
      this.trackDesc = '';
      // 空态退出取色（palette-glow/palette-bg）：光晕与背景渐变复位
      if (this.paletteBvid !== '') {
        this.paletteBvid = '';
        this.paletteColor = '';
        this.paletteReveal = 0;
      }
    }
  }

  private openOriginal(): void {
    if (this.trackBvid === '') {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: `https://www.bilibili.com/video/${this.trackBvid}`,
    };
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility(want)
      .catch((err: BusinessError) => {
        this.statusMsg = `打开浏览器失败: ${err.message}`;
      });
  }

  formatTime(ms: number): string {
    const totalSeconds: number = Math.floor(ms / 1000);
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    const minStr: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const secStr: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minStr}:${secStr}`;
  }

  formatCount(n: number): string {
    if (n <= 0) {
      return '0';
    }
    if (n >= 100000000) {
      return `${(n / 100000000).toFixed(1)}亿`;
    }
    if (n >= 10000) {
      return `${(n / 10000).toFixed(1)}万`;
    }
    return `${n}`;
  }

  formatPubDate(sec: number): string {
    if (sec <= 0) {
      return '发布时间未知';
    }
    const d: Date = new Date(sec * 1000);
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  private formatRemaining(totalSec: number): string {
    const h: number = Math.floor(totalSec / 3600);
    const m: number = Math.floor((totalSec % 3600) / 60);
    const s: number = totalSec % 60;
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    if (h > 0) {
      return `${h}:${pad(m)}:${pad(s)}`;
    }
    return `${pad(m)}:${pad(s)}`;
  }

  private presetLabel(seconds: number): string {
    return `${Math.floor(seconds / 60)} 分钟`;
  }

  private hourRange(): string[] {
    const result: string[] = [];
    for (let i = 0; i <= Constants.SLEEP_TIMER_MAX_HOURS; i++) {
      result.push(`${i}`);
    }
    return result;
  }

  private minuteRange(): string[] {
    const result: string[] = [];
    for (let i = 0; i < 60; i++) {
      result.push(`${i}`);
    }
    return result;
  }

  // 播放模式四态映射符号：顺序/倒序=order_play（倒序另经 playModeRotate 旋转 180°）/ 随机=shuffle / 单曲循环=repeat_1
  private playModeIcon(): Resource {
    if (this.playMode === MusicPlayMode.RANDOM) {
      return $r('sys.symbol.shuffle');
    }
    if (this.playMode === MusicPlayMode.REPEAT_ONE) {
      return $r('sys.symbol.repeat_1');
    }
    return $r('sys.symbol.order_play');
  }

  // 倒序模式图标旋转角（度）：仅 REVERSE 旋转 180°，表达「方向相反=倒序」
  private playModeRotate(): number {
    return this.playMode === MusicPlayMode.REVERSE ? 180 : 0;
  }

  // 音质入口按钮短名（T017，替代波形图标）：dash 流式 → 当前音轨码精确档名
  // （trackLabel 可显示 Hi-Res/杜比，比按档位归并的 label 更精确）；空闲 → 缓存的上次实际档
  // （无缓存回退当前网络设置默认档）；durl 兜底流 →「默认」（无档位概念）
  private qualityEntryLabel(): string {
    if (this.currentTrackSource === 'dash') {
      return AudioQuality.trackLabel(this.currentQualityCode);
    }
    if (this.currentTrackSource === '') {
      if (this.currentQualityCode > 0) {
        return AudioQuality.trackLabel(this.currentQualityCode);
      }
      return AudioQuality.label(this.idleTier());
    }
    return '默认';
  }

  // 空闲回退档（无缓存时）：当前网络设置默认档，按登录/会员收敛显示
  private idleTier(): QualityTier {
    const key: string = this.controller.isWifiNow()
      ? Constants.KEY_WIFI_AUDIO_QUALITY : Constants.KEY_CELLULAR_AUDIO_QUALITY;
    const stored: number = AppStore.getNumber(key, -1);
    return AudioQuality.clampTier(AudioQuality.fromStored(stored),
      BiliSession.getInstance().isLogged(), BiliSession.getInstance().vipStatus);
  }

  @Builder
  speedPanel() {
    Column() {
      Column() {
        Text('播放倍速')
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: Constants.TOKEN_SPACE_14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(PLAYBACK_RATES, (rate: number) => {
            Button(PlayerController.rateLabel(rate))
              .width('30%')
              .height(40)
              .backgroundColor(rate === this.playbackRate ? this.tintBg() : $r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .fontColor(rate === this.playbackRate ? $r('app.color.text_primary') : this.textPrimary())
              .borderRadius(Constants.TOKEN_RADIUS_XL)
              .fontSize(Constants.TOKEN_FONT_BODY_M)
              .margin(Constants.TOKEN_SPACE_XS)
              .onClick(() => {
                this.controller.setPlaybackRate(rate);
                this.showSpeed.value = false;
              })
          }, (rate: number) => rate.toString())
        }
        .width('100%')
      }
      .width('76%')
      .padding(Constants.TOKEN_SPACE_20)
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 弹层遮罩：深色保持现状，浅色调亮
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSpeed.value = false;
    })
  }

  @Builder
  modePanel() {
    Column() {
      Column() {
        Text('播放顺序')
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: Constants.TOKEN_SPACE_14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(PLAY_MODES, (mode: MusicPlayMode) => {
            Button(PlayerController.modeLabel(mode))
              .width('44%')
              .height(40)
              .backgroundColor(mode === this.playMode ? this.tintBg() : $r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .fontColor(mode === this.playMode ? $r('app.color.text_primary') : this.textPrimary())
              .borderRadius(Constants.TOKEN_RADIUS_XL)
              .fontSize(Constants.TOKEN_FONT_BODY_M)
              .margin(Constants.TOKEN_SPACE_6)
              .onClick(() => {
                this.controller.setPlayMode(mode);
                this.showMode.value = false;
              })
          }, (mode: MusicPlayMode) => `${mode}`)
        }
        .width('100%')
      }
      .width('76%')
      .padding(Constants.TOKEN_SPACE_20)
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showMode.value = false;
    })
  }

  @Builder
  sleepTimerPanel() {
    Column() {
      Column() {
        Text('定时关闭')
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: Constants.TOKEN_SPACE_10 })

        Text('设置计时结束后，将暂停播放并提醒')
          .fontSize(Constants.TOKEN_FONT_BODY)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Constants.TOKEN_SPACE_14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(Constants.SLEEP_TIMER_PRESETS, (seconds: number) => {
            Button(this.presetLabel(seconds))
              .width('30%')
              .height(40)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .fontColor(this.textPrimary())
              .borderRadius(Constants.TOKEN_RADIUS_XL)
              .fontSize(Constants.TOKEN_FONT_BODY_M)
              .margin(Constants.TOKEN_SPACE_XS)
              .onClick(() => {
                SleepTimerController.getInstance().startTimer(seconds);
                this.showSleepTimer.value = false;
              })
          }, (seconds: number) => `${seconds}`)

          Button('自定义')
            .width('30%')
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor(this.textPrimary())
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .margin(Constants.TOKEN_SPACE_XS)
            .onClick(() => {
              this.pickerHour = 0;
              this.pickerMinute = 0;
              this.showSleepTimerPicker.value = true;
            })

          Button('播完暂停')
            .width('30%')
            .height(40)
            .backgroundColor(this.sleepTimerPlayToEof ? this.tintBg() : $r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .margin(Constants.TOKEN_SPACE_XS)
            .onClick(() => {
              const st: SleepTimerController = SleepTimerController.getInstance();
              if (st.isPlayToEofActive()) {
                st.disarmPlayToEof();
              } else {
                st.armPlayToEof();
              }
              this.showSleepTimer.value = false;
            })
        }
        .width('100%')

        if (this.sleepTimerActive) {
          Button('取消定时')
            .width('100%')
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .margin({ top: Constants.TOKEN_SPACE_S })
            .onClick(() => {
              SleepTimerController.getInstance().cancelTimer();
              this.showSleepTimer.value = false;
            })
        }
      }
      .width('76%')
      .padding(Constants.TOKEN_SPACE_20)
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSleepTimer.value = false;
    })
  }

  // 音质面板（audio-quality-settings FR-005）：dash 源列出实际下发音轨（当前档高亮，点选换档并写回默认）；
  // 空闲源显示将用档（缓存上次实际档优先，无缓存回退设置默认档）；durl 兜底流为「默认」单选项
  @Builder
  qualityPanel() {
    Column() {
      Column() {
        Text('音质选择')
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: Constants.TOKEN_SPACE_14 })

        if (this.currentTrackSource === 'dash' && this.availableTracks.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.availableTracks, (track: AudioTrack) => {
              Button(AudioQuality.trackLabel(track.id))
                .width('44%')
                .height(40)
                .backgroundColor(track.id === this.currentQualityCode ? this.tintBg() : $r('app.color.btn_glass'))
                .backdropBlur(Constants.GLASS_BLUR)
                .fontColor(track.id === this.currentQualityCode ? $r('app.color.text_primary') : this.textPrimary())
                .borderRadius(Constants.TOKEN_RADIUS_XL)
                .fontSize(Constants.TOKEN_FONT_BODY_M)
                .margin(Constants.TOKEN_SPACE_6)
                .onClick(() => {
                  this.showQuality = false;
                  this.controller.setQualityTier(AudioQuality.tierOfTrackId(track.id), true);
                })
            }, (track: AudioTrack) => `${track.id}`)
          }
          .width('100%')
        } else if (this.currentTrackSource === '') {
          Text(this.qualityEntryLabel())
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: Constants.TOKEN_SPACE_6 })
          Text('起播后显示实际可用音轨')
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor(this.textSecondary())
            .textAlign(TextAlign.Center)
            .width('100%')
        } else {
          Button('默认')
            .width('44%')
            .height(40)
            .backgroundColor(this.tintBg())
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .margin(Constants.TOKEN_SPACE_6)
            .onClick(() => {
              this.showQuality = false;
            })
        }
      }
      .width('76%')
      .padding(Constants.TOKEN_SPACE_20)
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showQuality = false;
    })
  }

  @Builder
  sleepTimerPicker() {
    Column() {
      Column() {
        Text('自定义关闭时间')
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: Constants.TOKEN_SPACE_14 })

        Row() {
          TextPicker({ range: this.hourRange(), selected: this.pickerHour })
            .layoutWeight(1)
            .height(160)
            .onChange((value: string | string[], index: number | number[]) => {
              this.pickerHour = index as number;
            })

          Text('小时')
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: Constants.TOKEN_SPACE_S, right: Constants.TOKEN_SPACE_L })

          TextPicker({ range: this.minuteRange(), selected: this.pickerMinute })
            .layoutWeight(1)
            .height(160)
            .onChange((value: string | string[], index: number | number[]) => {
              this.pickerMinute = index as number;
            })

          Text('分钟')
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: Constants.TOKEN_SPACE_S })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: Constants.TOKEN_SPACE_M }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor(this.textPrimary())
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .onClick(() => {
              this.showSleepTimerPicker.value = false;
              this.showSleepTimer.value = true;
            })

          Button('确定')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.tintBg())
            .backdropBlur(Constants.GLASS_BLUR)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .onClick(() => {
              const totalSec: number = this.pickerHour * 3600 + this.pickerMinute * 60;
              if (totalSec <= 0) {
                this.getUIContext().getPromptAction().showToast({ message: '请选择至少 1 分钟', duration: 2000 });
                return;
              }
              SleepTimerController.getInstance().startTimer(totalSec);
              this.showSleepTimerPicker.value = false;
              this.showSleepTimer.value = false;
            })
        }
        .width('100%')
        .margin({ top: Constants.TOKEN_SPACE_14 })
      }
      .width('76%')
      .padding(Constants.TOKEN_SPACE_20)
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSleepTimerPicker.value = false;
      this.showSleepTimer.value = true;
    })
  }

  @Builder
  detailSheet() {
    Column() {
      Text(this.trackTitle)
        .fontSize(Constants.TOKEN_FONT_18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: Constants.TOKEN_SPACE_XS })

      Row() {
        Text(`播放 ${this.formatCount(this.trackView)}`)
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor($r('app.color.text_secondary'))

        Text(this.formatPubDate(this.trackPubdate))
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: Constants.TOKEN_SPACE_M })

        Blank()

        Text(this.trackBvid)
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: Constants.TOKEN_SPACE_10 })

      Divider()
        .color($r('app.color.track_color'))
        .strokeWidth(1)
        .margin({ top: Constants.TOKEN_SPACE_14, bottom: Constants.TOKEN_SPACE_14 })

      Scroll() {
        Text(this.trackDesc !== '' ? this.trackDesc : '暂无简介')
          .fontSize(Constants.TOKEN_FONT_BODY_M)
          .fontColor(this.trackDesc !== '' ? $r('app.color.detail_text') : $r('app.color.text_secondary'))
          .lineHeight(24)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Constants.TOKEN_SPACE_XL, right: Constants.TOKEN_SPACE_XL, top: Constants.TOKEN_SPACE_XS, bottom: Constants.TOKEN_SPACE_XL })
    // 玻璃公式（v0.4-Part1-ux-fixes US6）：与队列面板同款面板色+顶部分隔线，blur 作用于 sheet 底色已转透明的下层内容
    .backgroundColor($r('app.color.sheet_panel_background'))
    .backdropBlur(Constants.GLASS_BLUR)
    .border({ width: { top: 1 }, color: $r('app.color.sheet_top_separator') })
  }

  build() {
    Stack() {
      Column() {
        // US5 骨架修正：顶栏移入滚动内容，Scroll 视口自屏幕顶起算，封面光晕不再被视口顶边截断；
        // 顶栏与封面同组（SpaceBetween 间隙数不变，静止布局逐像素等价）
          Scroll(this.contentScroller) {
            Column() {
              Column() {
                Row() {
                  Row() {
                    SymbolGlyph($r('sys.symbol.chevron_down'))
                      .fontSize(Constants.TOKEN_FONT_TITLE_L)
                      .fontColor([$r('app.color.text_primary')])
                  }
                  .width(Constants.CONTROL_BTN_SIZE)
                  .height(Constants.CONTROL_BTN_SIZE)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => {
                    connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = false;
                  })
                  Blank()
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10, top: this.statusBarHeight.value + 6, bottom: Constants.TOKEN_SPACE_XS })

              Stack() {
                // 封面环境光晕 — 多段衰减模拟自然光扩散，播放时淡入高亮（v0.3 US1 一次性过渡，无往复）
                Column()
                  .width(450)
                  .height(450)
                  .borderRadius(225)
                  .position({ x: -75, y: -131 })
                  // v0.4-Part1-ux-fixes US1：光晕 450vp 超出封面 Stack 覆盖上半滚动区，Default 命中拦截顶栏/标题行点击
                  // （hilog 证据：chevron 点击零 miniChain 链路），None 使纯装饰节点退出命中测试
                  .hitTestBehavior(HitTestMode.None)
                  .opacity(this.glowStrength)
                  // 节点级属性动画（animation 仅对其前面的属性生效）：光晕淡入/淡出不产生
                  // 同帧动画作用域，不会波及播放键图标的透明度翻转；radialGradient 在其后，色彩切换即时
                  .animation({ duration: this.playIntent ? GLOW_FADE_IN_MS : GLOW_FADE_OUT_MS, curve: Curve.EaseInOut })
                  .radialGradient({
                    center: [225, 225],
                    radius: 225,
                    colors: this.haloColors()
                  })

                Stack({ alignContent: Alignment.BottomEnd }) {
                  if (this.trackCover !== '') {
                    Image(this.trackCover)
                      .width(300)
                      .height(188)
                      .borderRadius(Constants.TOKEN_RADIUS_18)
                      .objectFit(ImageFit.Cover)
                      .contentTransition(ContentTransitionEffect.OPACITY)
                  } else {
                    Column() {
                      SymbolGlyph($r('sys.symbol.headphones'))
                        .fontSize(Constants.TOKEN_FONT_56)
                        .fontColor([this.accentColor.value])
                    }
                    .width(300)
                    .height(188)
                    .borderRadius(Constants.TOKEN_RADIUS_18)
                    .backgroundColor($r('app.color.card_background'))
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }

                  Row({ space: Constants.TOKEN_SPACE_XS }) {
                    SymbolGlyph($r('sys.symbol.play_round_rectangle'))
                      .fontSize(Constants.TOKEN_FONT_BODY_S)
                      .fontColor([this.textPrimary()])
                    Text('视频')
                      .fontSize(Constants.TOKEN_FONT_AUX)
                      .fontColor(this.textPrimary())
                  }
                  .height(26)
                  .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(Constants.GLASS_BLUR)
                  .borderRadius(13)
                  .margin(Constants.TOKEN_SPACE_S)
                  .enabled(this.trackBvid !== '')
                  .opacity(this.trackBvid !== '' ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
                  .onClick(() => {
                    this.openOriginal();
                  })
                }
                .width(300)
                .height(188)
                .borderRadius(Constants.TOKEN_RADIUS_18)
                .clip(true)
                .shadow({ radius: 30, color: $r('app.color.shadow_cover'), offsetY: 16 })
                .brightness(this.playIntent ? 1 : 0.88)
                .animation({ duration: 400, curve: Curve.FastOutSlowIn })
              }
              .width(300)
              .height(188)
              .margin({ top: Constants.COVER_TOP_GAP })
              .alignSelf(ItemAlign.Center)
              .scale({ x: this.playIntent ? 1 : 0.94, y: this.playIntent ? 1 : 0.94 })
              .animation({ duration: 350, curve: Curve.FastOutSlowIn })
              }
              .width('100%')

              Row() {
                Text(this.trackTitle)
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textPrimary())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)

                if (this.trackIndex >= 0) {
                  // 展开指示（v0.4-Part1-ux-fixes US6）：系统图标替换裸「▼」字符，旋转动画保留
                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(Constants.TOKEN_FONT_TITLE)
                    .fontColor([this.textSecondary()])
                    .margin({ left: Constants.TOKEN_SPACE_XXS })
                    .padding(Constants.TOKEN_SPACE_M)
                    .rotate({ angle: this.detailArrowUp ? 180 : 0 })
                    .animation({ duration: 200, curve: Curve.Smooth })
                }
              }
              .width('92%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_XS })
              .onClick(() => {
                if (this.trackBvid !== '') {
                  this.detailArrowUp = true;
                  this.showDetail = true;
                  this.loadTrackDescIfNeeded();
                }
              })

              if (this.ownerName !== '') {
                Row() {
                  Row({ space: Constants.TOKEN_SPACE_6 }) {
                    if (this.ownerFace !== '') {
                      Image(this.ownerFace)
                        .width(22)
                        .height(22)
                        .borderRadius(11)
                        .objectFit(ImageFit.Cover)
                        .interpolation(ImageInterpolation.Low)
                    } else {
                      Stack({ alignContent: Alignment.Center }) {
                        Text(this.ownerName.charAt(0))
                          .fontSize(Constants.TOKEN_FONT_AUX)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.accentColor.value)
                      }
                      .width(22)
                      .height(22)
                      .borderRadius(11)
                      .backgroundColor($r('app.color.card_background'))
                    }

                    Text(this.ownerName)
                      .fontSize(Constants.TOKEN_FONT_BODY_S)
                      .fontColor(this.textSecondary())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(VerticalAlign.Center)
                  .constraintSize({ maxWidth: '70%' })

                  if (this.playlistCount > 0) {
                    Blank()

                    Text(this.trackIndex >= 0 ? `${this.trackIndex + 1} / ${this.playlistCount}` : `共 ${this.playlistCount} 首`)
                      .fontSize(Constants.TOKEN_FONT_BODY_S)
                      .fontColor(this.textSecondary())
                  }
                }
                .width('92%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: Constants.TOKEN_SPACE_XXS })
              } else if (this.playlistCount > 0) {
                Text(this.trackIndex >= 0 ? `${this.trackIndex + 1} / ${this.playlistCount}` : `共 ${this.playlistCount} 首`)
                  .fontSize(Constants.TOKEN_FONT_BODY_S)
                  .fontColor(this.textSecondary())
              }

              if (!this.isWide) {
                // 统计行已删，窄屏隐藏占位保持 SpaceBetween 分布与原版一致，防止标题/UP 下垂
                Text(`播放 ${this.formatCount(this.trackView)} · ${this.formatPubDate(this.trackPubdate)}`)
                  .fontSize(Constants.TOKEN_FONT_BODY_S)
                  .fontColor(this.textSecondary())
                  .margin({ top: Constants.TOKEN_SPACE_6 })
                  .visibility(Visibility.Hidden)
              }
            }
            .width('100%')
            // 信息区留白铺满（T007）：内容不足一屏时拉开分布铺满，超出仍可滚动（Scroll 行为不变）；
            // 底部留白仅宽屏：防止 SpaceBetween 末位子项贴进度条；窄屏无 padding 保持原版逐像素不变
            .constraintSize({ minHeight: '100%' })
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ bottom: this.isWide ? this.overlayHeightVp * Constants.PLAYER_WIDE_CTRL_GAP_RATIO : 0 })
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .scrollable(ScrollDirection.Vertical)

          // 固定底栏（plan R1）：进度条/时间行/控制栏/底部操作行/状态行常驻底部，不随信息区滚动
          Column() {
            // 进度区（spec FR-004 / plan R5）：细进度条 + 独立时间行，宽 92% 居中
            Column() {
              // 细进度条：轨道高 5vp、圆点直径 12vp；受控 sliderValue + isSeeking 防回弹
              Slider({
                value: this.sliderValue,
                min: 0,
                max: 100,
                step: 1,
              })
                .trackThickness(5)
                .blockSize({ width: 12, height: 12 })
                .trackColor($r('app.color.track_color'))
                .selectedColor(this.accentColor.value)
                .blockColor(this.accentColor.value)
                .width('100%')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.sliderValue = value;
                  if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                    this.isSeeking = true;
                  } else {
                    this.isSeeking = false;
                    if (this.duration > 0) {
                      this.controller.seek(Math.floor(value / 100 * this.duration));
                    }
                  }
                })

              // 时间行：左=当前时间（拖拽中显示拖拽位置）、右=总时长，13vp 次要色
              Row() {
                Text(this.formatTime(this.isSeeking ? this.sliderValue / 100 * this.duration : this.currentTime))
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontColor(this.textSecondary())

                Blank()

                Text(this.formatTime(this.duration))
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontColor(this.textSecondary())
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: Constants.TOKEN_SPACE_XXS })
            }
            .width('92%')

            // 控制栏（spec FR-005）：传输五键横排居中，播放键 72×72 主按钮，其余四键次级
            Row({ space: Constants.TOKEN_SPACE_M }) {
              Row() {
                SymbolGlyph($r('sys.symbol.backward_end_fill'))
                  .fontSize(Constants.TOKEN_FONT_TITLE_L)
                  .fontColor([this.textPrimary()])
              }
              .width(Constants.CONTROL_BTN_SIZE)
              .height(Constants.CONTROL_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.prevBtnScale, y: this.prevBtnScale })
              .enabled(this.playlistCount > 0)
              .opacity(this.playlistCount > 0 ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
              .onClick(() => {
                this.popPrev();
                this.controller.prev();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.gobackward_15'))
                  .fontSize(Constants.TOKEN_FONT_TITLE_L)
                  .fontColor([this.textPrimary()])
              }
              .width(Constants.CONTROL_BTN_SIZE)
              .height(Constants.CONTROL_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .enabled(this.isPrepared)
              .opacity(this.isPrepared ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
              .onClick(() => {
                this.controller.seekBy(-Constants.SEEK_STEP_MS);
              })

              // 播放键（US1 尺寸同源 / round3 判定表）：三态由三个常驻节点 + opacity 互斥表达——
              // 缓冲（isPreparing && playIntent）→ 加载圈；playIntent → 暂停键；否则播放键。
              // 常驻节点无创建/销毁、无 symbol 资源切换：此前 if/else 换节点与单节点切资源在
              // API 24/26 渲染管线残留旧图层（首次播放 glyph→圈→glyph 后播放/暂停同屏、转圈不可见），
              // opacity 方案从根上消除残影来源
              Stack() {
                LoadingProgress()
                  .color(this.accentColor.value)
                  .width(Constants.PLAY_BTN_DIAMETER * 0.5)
                  .height(Constants.PLAY_BTN_DIAMETER * 0.5)
                  .opacity(this.isPreparing && this.playIntent ? 1 : 0)
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(Constants.PLAY_BTN_DIAMETER * 0.45)
                  .fontColor([$r('app.color.text_primary')])
                  .opacity(this.playIntent ? 0 : 1)
                SymbolGlyph($r('sys.symbol.pause_fill'))
                  .fontSize(Constants.PLAY_BTN_DIAMETER * 0.45)
                  .fontColor([$r('app.color.text_primary')])
                  .opacity(this.playIntent && !this.isPreparing ? 1 : 0)
              }
              .width(Constants.PLAY_BTN_DIAMETER)
              .height(Constants.PLAY_BTN_DIAMETER)
              .borderRadius(Constants.PLAY_BTN_DIAMETER / 2)
              .scale({ x: this.playBtnScale, y: this.playBtnScale })
              .enabled(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0)
              .opacity(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0 ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
              .onClick(() => {
                this.popPlay();
                this.controller.togglePlay();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.goforward_15'))
                  .fontSize(Constants.TOKEN_FONT_TITLE_L)
                  .fontColor([this.textPrimary()])
              }
              .width(Constants.CONTROL_BTN_SIZE)
              .height(Constants.CONTROL_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .enabled(this.isPrepared)
              .opacity(this.isPrepared ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
              .onClick(() => {
                this.controller.seekBy(Constants.SEEK_STEP_MS);
              })

              Row() {
                SymbolGlyph($r('sys.symbol.forward_end_fill'))
                  .fontSize(Constants.TOKEN_FONT_TITLE_L)
                  .fontColor([this.textPrimary()])
              }
              .width(Constants.CONTROL_BTN_SIZE)
              .height(Constants.CONTROL_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.nextBtnScale, y: this.nextBtnScale })
              .enabled(this.playlistCount > 0)
              .opacity(this.playlistCount > 0 ? 1.0 : Constants.TOKEN_DISABLED_OPACITY)
              .onClick(() => {
                this.popNext();
                this.controller.next();
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: this.isWide ? this.overlayHeightVp * Constants.PLAYER_WIDE_CTRL_GAP_RATIO : Constants.TOKEN_SPACE_M })

            // 底部操作行（spec FR-006 / plan R6）：倍速/播放模式/定时/队列，沿用现有全局键开关
            Row({ space: Constants.TOKEN_SPACE_M }) {
              Row({ space: Constants.TOKEN_SPACE_XS }) {
                SymbolGlyph($r('sys.symbol.speed_multiple'))
                  .fontSize(Constants.TOKEN_FONT_TITLE)
                  .fontColor([this.playbackRate === 1.0 ? this.textPrimary() : this.accentColor.value])
                Text(PlayerController.rateLabel(this.playbackRate))
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontColor(this.playbackRate === 1.0 ? this.textPrimary() : this.accentColor.value)
              }
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .onClick(() => {
                this.showSpeed.value = true;
              })

              Row() {
                SymbolGlyph(this.playModeIcon())
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([this.accentColor.value])
                  .rotate({ angle: this.playModeRotate() })
              }
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .onClick(() => {
                this.showMode.value = true;
              })

              // 音质入口（audio-quality-settings FR-005 + T017）：直接显示当前音质档位短名；
              // dash 多音轨可用时以主题色高亮示意
              Row() {
                Text(this.qualityEntryLabel())
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.currentTrackSource === 'dash' ? this.accentColor.value : this.textPrimary())
              }
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .onClick(() => {
                this.showQuality = true;
              })

              Row({ space: Constants.TOKEN_SPACE_XS }) {
                SymbolGlyph($r('sys.symbol.timer'))
                  .fontSize(Constants.TOKEN_FONT_TITLE)
                  .fontColor([this.sleepTimerActive ? this.accentColor.value : this.textPrimary()])
                if (this.sleepTimerActive && !this.sleepTimerPlayToEof) {
                  Text(this.formatRemaining(this.sleepTimerRemaining))
                    .fontSize(Constants.TOKEN_FONT_BODY)
                    .fontColor(this.accentColor.value)
                }
              }
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .padding({ left: Constants.TOKEN_SPACE_14, right: Constants.TOKEN_SPACE_14 })
              .onClick(() => {
                this.showSleepTimer.value = true;
              })

              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(Constants.TOKEN_FONT_TITLE_L)
                  .fontColor([this.textPrimary()])
              }
              .width(Constants.CONTROL_BTN_SIZE)
              .height(Constants.CONTROL_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                connectBool(Constants.AS_SHOW_QUEUE_SHEET, false).value = true;
              })
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: this.isWide ? this.overlayHeightVp * Constants.PLAYER_WIDE_ACTION_GAP_RATIO : Constants.TOKEN_SPACE_14 })
          }
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_S })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: this.navBarHeight.value + (this.isWide ? this.overlayHeightVp * Constants.PLAYER_WIDE_BOTTOM_GAP_RATIO : 0) })

      if (this.showSpeed.value) {
        this.speedPanel()
      }

      if (this.showMode.value) {
        this.modePanel()
      }

      if (this.showSleepTimer.value) {
        this.sleepTimerPanel()
      }

      if (this.showSleepTimerPicker.value) {
        this.sleepTimerPicker()
      }

      if (this.showQuality) {
        this.qualityPanel()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.isWide = Number(newArea.width) >= Constants.WIDE_BREAKPOINT_VP;
      this.overlayHeightVp = Number(newArea.height);
    })
    .backgroundColor($r('app.color.page_background'))
    // 背景衍生色渐变（palette-bg）：封面取色洗淡（压饱和/定明度）后铺顶部，影响幅度有限
    .linearGradient({
      angle: 180,
      colors: this.bgStops()
    })
    // 下滑退出播放层：仅在内容已滚到顶部时生效，避免与内容滚动冲突
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionEnd((event: GestureEvent) => {
          // ponytail: currentOffset() 类型上不可空，但浮层刚挂载时运行时返回 undefined（模拟器实测 crash），防御判空；根因在 Scroller attach 时序，无公开 API 可查
          const offset: OffsetResult | undefined = this.contentScroller.currentOffset();
          const atTop: boolean = offset === undefined || offset.yOffset <= 0;
          const noOverlayOpen: boolean = !this.showQueueSheet.value && !this.showSpeed.value && !this.showMode.value &&
            !this.showSleepTimer.value && !this.showSleepTimerPicker.value && !this.showDetail && !this.showQuality;
          if (noOverlayOpen && atTop && event.offsetY > PLAYER_DISMISS_SWIPE) {
            connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = false;
          }
        })
    )
    .bindSheet(this.showDetail, this.detailSheet(), {
      height: '62%',
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      preferType: SheetType.BOTTOM,
      // 手势下滑/遮罩关闭判定通过时：先即时翻转箭头再真正关闭（T011）
      shouldDismiss: (sheetDismiss: SheetDismiss) => {
        this.detailArrowUp = false;
        sheetDismiss.dismiss();
      },
      // 兜底：任何其他关闭路径同步箭头状态并复位打开标志
      onDisappear: () => {
        this.detailArrowUp = false;
        this.showDetail = false;
      }
    })
  }
}
