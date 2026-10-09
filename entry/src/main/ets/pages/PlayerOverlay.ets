import { PlayerController, PlayMode as MusicPlayMode, PLAYBACK_RATES, PLAY_MODES } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStore } from '../service/AppStore';
import { BiliService } from '../service/BiliService';
import { Constants } from '../service/Constants';
import { CoverUrl } from '../service/CoverUrl';
import { Appearance } from '../service/Appearance';
import { SleepTimerController } from '../service/SleepTimerController';
import { QueueDrawer } from '../component/QueueDrawer';
import { AudioTrack, AudioQuality } from '../model/AudioQuality';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 封面光晕呼吸参数：静止亮度 / 呼吸峰值 / 呼吸周期
const GLOW_IDLE: number = 0.35;
const GLOW_ACTIVE: number = 0.8;
const GLOW_BREATH_MS: number = 3200;

// 下滑退出播放层的位移阈值（vp）：内容已到顶部时，下滑超过该距离才退出
const PLAYER_DISMISS_SWIPE: number = 80;

// ±15s 进度微调步长已收敛至 Constants.SEEK_STEP_MS（全库唯一常量点，与播控中心共用）

@Component
export struct PlayerOverlay {
  @State isPlaying: boolean = false;
  @State isPrepared: boolean = false;
  @State isPreparing: boolean = false;
  @State playWhenReady: boolean = true;
  @State currentTime: number = 0;
  @State duration: number = 0;
  // 进度条受控值：拖动时实时跟随手指，松开才真正 seek，避免受控值回弹导致拖不动
  @State sliderValue: number = 0;
  @State isSeeking: boolean = false;
  @State statusMsg: string = '';
  @State trackTitle: string = '未在播放';
  @State trackCover: string = '';
  @State ownerName: string = '';
  @State ownerFace: string = '';
  @State playMode: MusicPlayMode = MusicPlayMode.SEQUENTIAL;
  @State playbackRate: number = 1.0;
  @StorageLink('showSpeed') showSpeed: boolean = false; // key 与 Constants.AS_SHOW_SPEED 对应
  @StorageLink('showMode') showMode: boolean = false; // key 与 Constants.AS_SHOW_MODE 对应
  @StorageLink('showSleepTimer') showSleepTimer: boolean = false; // key 与 Constants.AS_SHOW_SLEEP_TIMER 对应
  @StorageLink('showSleepTimerPicker') showSleepTimerPicker: boolean = false; // key 与 Constants.AS_SHOW_SLEEP_TIMER_PICKER 对应
  @StorageLink('showQueueSheet') showQueueSheet: boolean = false; // key 与 Constants.AS_SHOW_QUEUE_SHEET 对应
  // 浮层显示标志（KI-5，key 与 Constants.AS_SHOW_PLAYER_OVERLAY 对应）：与 Index 树内条件渲染的
  // 显隐同源；任何关闭路径先将该标志置 false，随后组件卸载触发 aboutToDisappear
  @StorageLink('showPlayerOverlay') showOverlayActive: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 38; // key 与 Constants.AS_STATUS_BAR_HEIGHT 对应
  @StorageProp('navBarHeight') navBarHeight: number = 0; // key 与 Constants.AS_NAV_BAR_HEIGHT 对应
  // 主题色（key 与 Constants.AS_ACCENT_COLOR 对应）：全部着色点运行时跟随，衍生色经 Appearance.hexWithAlpha 计算
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  // 生效深浅色（1=浅色 2=深色，key 与 Constants.AS_COLOR_MODE_RESOLVED 对应）：驱动深浅色差异化 alpha
  @StorageProp('colorModeResolved') colorModeResolved: number = 1;

  @State glowStrength: number = GLOW_IDLE;
  @State playBtnScale: number = 1;
  @State prevBtnScale: number = 1;
  @State nextBtnScale: number = 1;
  @State trackIndex: number = -1;
  @State playlistCount: number = 0;
  @State showDetail: boolean = false;
  // 详情箭头指向（T011）：独立于 showDetail，sheet 任何关闭路径即时翻转
  @State detailArrowUp: boolean = false;
  @State sleepTimerActive: boolean = false;
  @State sleepTimerRemaining: number = 0;
  @State pickerHour: number = 0;
  @State pickerMinute: number = 0;
  @State trackView: number = 0;
  @State trackPubdate: number = 0;
  @State trackDesc: string = '';
  // 音质面板镜像（audio-quality-settings US3）：syncFrom 增量同步 controller 公开音质状态
  @State showQuality: boolean = false;
  @State availableTracks: AudioTrack[] = [];
  @State currentQualityCode: number = 0;
  @State currentTrackSource: string = '';
  private trackBvid: string = '';
  private wasPlaying: boolean = false;
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

  private textDisabled(): Resource {
    return $r('app.color.text_disabled');
  }

  // ===== 主题色衍生取色（T006）：alpha 沿用 base/dark 资源键原有取值 =====

  private isDarkMode(): boolean {
    return this.colorModeResolved === 2;
  }

  // 播放键底色/面板选中底色：主题色 + material_tint_primary 原 alpha（0x59 ≈ 0.349，深浅色同值）
  private tintBg(): string {
    return Appearance.hexWithAlpha(this.accentColor, 0.349);
  }

  // 播放键阴影：主题色 + shadow_play 原 alpha（浅色 0x8C ≈ 0.549 / 深色 0x73 ≈ 0.451）
  private playBtnShadowColor(): string {
    return Appearance.hexWithAlpha(this.accentColor, this.isDarkMode() ? 0.451 : 0.549);
  }

  // ===== 播放按钮尺寸同源（US1）：按钮直径为唯一尺寸源，缓冲加载指示尺寸由此派生 =====

  // 封面光晕梯度：主题色 + halo_pink_0..3 原 alpha 序列（浅色 [0x80,0x3D,0x14,0x00] / 深色 [0x66,0x29,0x0D,0x00]）
  private haloColors(): Array<[ResourceColor, number]> {
    const alphas: number[] = this.isDarkMode() ? [0.4, 0.161, 0.051, 0] : [0.502, 0.239, 0.078, 0];
    const colors: Array<[ResourceColor, number]> = [
      [Appearance.hexWithAlpha(this.accentColor, alphas[0]), 0],
      [Appearance.hexWithAlpha(this.accentColor, alphas[1]), 0.45],
      [Appearance.hexWithAlpha(this.accentColor, alphas[2]), 0.75],
      [Appearance.hexWithAlpha(this.accentColor, alphas[3]), 1]
    ];
    return colors;
  }


  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.wasPlaying = this.isPlaying;
    // KI-5：aboutToAppear 运行于节点构建中，此处调用 animateTo 会触发框架告警
    // （"node stack is not empty, not suitable for animateTo"），
    // 且疑似在 API 24 上引发 ModalPage 渲染管线挂载后冻结（仅渲染首帧）——
    // 光晕初始化延后到构建完成后的下一拍执行，延迟一帧对视觉无感知影响
    setTimeout((): void => {
      this.updateGlow();
    }, 0);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
      if (this.isPlaying !== this.wasPlaying) {
        this.wasPlaying = this.isPlaying;
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
    if (this.showOverlayActive) {
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
    this.sleepTimerRemaining = st.getRemainingSeconds();
  }

  private updateGlow(): void {
    if (this.isPlaying) {
      this.getUIContext().animateTo({
        duration: GLOW_BREATH_MS,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, (): void => {
        this.glowStrength = GLOW_ACTIVE;
      });
    } else {
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut }, (): void => {
        this.glowStrength = GLOW_IDLE;
      });
    }
  }

  private popPlay(): void {
    this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
      this.playBtnScale = 0.88;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
        this.playBtnScale = 1;
      });
    }, 120);
  }

  private popPrev(): void {
    this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
      this.prevBtnScale = 0.9;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
        this.prevBtnScale = 1;
      });
    }, 120);
  }

  private popNext(): void {
    this.getUIContext().animateTo({ duration: 100, curve: Curve.Friction }, (): void => {
      this.nextBtnScale = 0.9;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, (): void => {
        this.nextBtnScale = 1;
      });
    }, 120);
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
    this.isPlaying = c.isPlaying;
    this.isPrepared = c.isPrepared;
    this.isPreparing = c.isPreparing;
    this.playWhenReady = c.playWhenReady;
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
      const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
      // US6：大封面按显示尺寸取图，非 Wi-Fi 降省流档（UP 头像保持原图，不参与取档）
      const wifi: boolean = c.isWifiNow();
      const coverW: number = wifi ? Constants.COVER_BIG_W : Constants.COVER_SAVER_W;
      const coverH: number = wifi ? Constants.COVER_BIG_H : Constants.COVER_SAVER_H;
      this.trackTitle = item.title;
      this.trackCover = dataSaver ? '' : CoverUrl.sized(item.cover, coverW, coverH);
      this.ownerName = item.ownerName;
      this.ownerFace = dataSaver ? '' : item.ownerFace;
      this.trackBvid = item.bvid;
      this.trackIndex = c.currentIndex;
      this.trackView = item.view;
      this.trackPubdate = item.pubdate;
      this.trackDesc = item.desc;
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

  // 播放模式四态映射符号（T009）：顺序=order_play / 随机=shuffle / 单曲循环=repeat_1 / 倒序=reverse_order
  private playModeIcon(): Resource {
    if (this.playMode === MusicPlayMode.RANDOM) {
      return $r('sys.symbol.shuffle');
    }
    if (this.playMode === MusicPlayMode.REPEAT_ONE) {
      return $r('sys.symbol.repeat_1');
    }
    if (this.playMode === MusicPlayMode.REVERSE) {
      return $r('sys.symbol.reverse_order');
    }
    return $r('sys.symbol.order_play');
  }

  // 音质入口按钮短名（T017，替代波形图标）：dash 流式 → 当前音轨码精确档名
  // （trackLabel 可显示 Hi-Res/杜比，比按档位归并的 label 更精确）；其余（未起播/未知）→「默认」
  private qualityEntryLabel(): string {
    if (this.currentTrackSource === 'dash') {
      return AudioQuality.trackLabel(this.currentQualityCode);
    }
    return '默认';
  }

  @Builder
  speedPanel() {
    Column() {
      Column() {
        Text('播放倍速')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(PLAYBACK_RATES, (rate: number) => {
            Button(PlayerController.rateLabel(rate))
              .width('30%')
              .height(40)
              .backgroundColor(rate === this.playbackRate ? this.tintBg() : $r('app.color.btn_glass'))
              .backdropBlur(20)
              .fontColor(rate === this.playbackRate ? $r('app.color.text_primary') : this.textPrimary())
              .borderRadius(20)
              .fontSize(14)
              .margin(4)
              .onClick(() => {
                this.controller.setPlaybackRate(rate);
                this.showSpeed = false;
              })
          }, (rate: number) => rate.toString())
        }
        .width('100%')
      }
      .width('76%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 弹层遮罩：深色保持现状，浅色调亮
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSpeed = false;
    })
  }

  @Builder
  modePanel() {
    Column() {
      Column() {
        Text('播放顺序')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(PLAY_MODES, (mode: MusicPlayMode) => {
            Button(PlayerController.modeLabel(mode))
              .width('44%')
              .height(40)
              .backgroundColor(mode === this.playMode ? this.tintBg() : $r('app.color.btn_glass'))
              .backdropBlur(20)
              .fontColor(mode === this.playMode ? $r('app.color.text_primary') : this.textPrimary())
              .borderRadius(20)
              .fontSize(14)
              .margin(6)
              .onClick(() => {
                this.controller.setPlayMode(mode);
                this.showMode = false;
              })
          }, (mode: MusicPlayMode) => `${mode}`)
        }
        .width('100%')
      }
      .width('76%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showMode = false;
    })
  }

  @Builder
  sleepTimerPanel() {
    Column() {
      Column() {
        Text('定时关闭')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 10 })

        Text('设置计时结束后，将暂停播放并提醒')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: 14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(Constants.SLEEP_TIMER_PRESETS, (seconds: number) => {
            Button(this.presetLabel(seconds))
              .width('30%')
              .height(40)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .fontColor(this.textPrimary())
              .borderRadius(20)
              .fontSize(14)
              .margin(4)
              .onClick(() => {
                SleepTimerController.getInstance().startTimer(seconds);
                this.showSleepTimer = false;
              })
          }, (seconds: number) => `${seconds}`)

          Button('自定义')
            .width('30%')
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .fontColor(this.textPrimary())
            .borderRadius(20)
            .fontSize(14)
            .margin(4)
            .onClick(() => {
              this.pickerHour = 0;
              this.pickerMinute = 0;
              this.showSleepTimerPicker = true;
            })
        }
        .width('100%')

        if (this.sleepTimerActive) {
          Button('取消定时')
            .width('100%')
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(20)
            .fontSize(14)
            .margin({ top: 8 })
            .onClick(() => {
              SleepTimerController.getInstance().cancelTimer();
              this.showSleepTimer = false;
            })
        }
      }
      .width('76%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSleepTimer = false;
    })
  }

  // 音质面板（audio-quality-settings FR-005）：dash 源列出实际下发音轨（当前档高亮，点选换档并写回默认）；
  // durl/空闲源显示默认占位，无可选项；
  // 未登录时高档位由服务端决定是否下发，面板天然只显示实际可用音轨（US4 不额外提示）
  @Builder
  qualityPanel() {
    Column() {
      Column() {
        Text('音质选择')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 14 })

        if (this.currentTrackSource === 'dash' && this.availableTracks.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.availableTracks, (track: AudioTrack) => {
              Button(AudioQuality.trackLabel(track.id))
                .width('44%')
                .height(40)
                .backgroundColor(track.id === this.currentQualityCode ? this.tintBg() : $r('app.color.btn_glass'))
                .backdropBlur(20)
                .fontColor(track.id === this.currentQualityCode ? $r('app.color.text_primary') : this.textPrimary())
                .borderRadius(20)
                .fontSize(14)
                .margin(6)
                .onClick(() => {
                  this.showQuality = false;
                  this.controller.setQualityTier(AudioQuality.tierOfTrackId(track.id), true);
                })
            }, (track: AudioTrack) => `${track.id}`)
          }
          .width('100%')
        } else {
          Text('默认')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 6 })
          Text('当前内容未提供多音质选择')
            .fontSize(13)
            .fontColor(this.textSecondary())
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .width('76%')
      .padding(20)
      .borderRadius(16)
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
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 14 })

        Row() {
          TextPicker({ range: this.hourRange(), selected: this.pickerHour })
            .layoutWeight(1)
            .height(160)
            .onChange((value: string | string[], index: number | number[]) => {
              this.pickerHour = index as number;
            })

          Text('小时')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8, right: 16 })

          TextPicker({ range: this.minuteRange(), selected: this.pickerMinute })
            .layoutWeight(1)
            .height(160)
            .onChange((value: string | string[], index: number | number[]) => {
              this.pickerMinute = index as number;
            })

          Text('分钟')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .fontColor(this.textPrimary())
            .borderRadius(20)
            .fontSize(14)
            .onClick(() => {
              this.showSleepTimerPicker = false;
              this.showSleepTimer = true;
            })

          Button('确定')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.tintBg())
            .backdropBlur(20)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(20)
            .fontSize(14)
            .onClick(() => {
              const totalSec: number = this.pickerHour * 3600 + this.pickerMinute * 60;
              if (totalSec <= 0) {
                this.getUIContext().getPromptAction().showToast({ message: '请选择至少 1 分钟', duration: 2000 });
                return;
              }
              SleepTimerController.getInstance().startTimer(totalSec);
              this.showSleepTimerPicker = false;
              this.showSleepTimer = false;
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('76%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.mask_heavy'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showSleepTimerPicker = false;
      this.showSleepTimer = true;
    })
  }

  @Builder
  detailSheet() {
    Column() {
      Text(this.trackTitle)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 4 })

      Row() {
        Text(`播放 ${this.formatCount(this.trackView)}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(this.formatPubDate(this.trackPubdate))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 12 })

        Blank()

        Text(this.trackBvid)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 10 })

      Divider()
        .color($r('app.color.track_color'))
        .strokeWidth(1)
        .margin({ top: 14, bottom: 14 })

      Scroll() {
        Text(this.trackDesc !== '' ? this.trackDesc : '暂无简介')
          .fontSize(14)
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
    .padding({ left: 24, right: 24, top: 4, bottom: 24 })
    .backgroundColor($r('app.color.sheet_background'))
    .backdropBlur(20)
  }

  build() {
    Stack() {
      Column() {
        // 顶栏：仅保留收起按钮（spec FR-007，无标题文字与功能图标）
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
            .padding(6)
            .onClick(() => {
              AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, false);
            })
          Blank()
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: this.statusBarHeight + 6, bottom: 4 })

        // 空态判定（US2 统一口径）：无当前曲目（trackIndex<0）或队列为空任一成立即显示占位，
        // 与播放键 enabled 条件（isPrepared || trackIndex>=0 || playlistCount>0）对称
        if (this.trackIndex < 0 || this.playlistCount === 0) {
          Column() {
            Text('暂无播放内容')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .margin({ top: 60 })

            Text('在首页点「＋」粘贴BV号直接播放\n或订阅UP主/收藏夹/合集后收听')
              .fontSize(14)
              .fontColor(this.textSecondary())
              .textAlign(TextAlign.Center)
              .margin({ top: 24 })

            Text('添加内容后即可开始收听')
              .fontSize(13)
              .fontColor(this.textDisabled())
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll(this.contentScroller) {
            Column() {
              Stack() {
                // 封面环境光晕 — 多段衰减模拟自然光扩散，播放时呼吸；粉色系资源，浅色下适当调亮保持协调
                Column()
                  .width(450)
                  .height(450)
                  .borderRadius(225)
                  .radialGradient({
                    center: [225, 225],
                    radius: 225,
                    colors: this.haloColors()
                  })
                  .position({ x: -75, y: -131 })
                  .opacity(this.glowStrength)

                Stack({ alignContent: Alignment.BottomEnd }) {
                  if (this.trackCover !== '') {
                    Image(this.trackCover)
                      .width(300)
                      .height(188)
                      .borderRadius(18)
                      .objectFit(ImageFit.Cover)
                      .contentTransition(ContentTransitionEffect.OPACITY)
                  } else {
                    Column() {
                      Text('♪')
                        .fontSize(56)
                        .fontColor(this.accentColor)
                    }
                    .width(300)
                    .height(188)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.card_background'))
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }

                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.play_round_rectangle'))
                      .fontSize(12)
                      .fontColor([this.textPrimary()])
                    Text('视频')
                      .fontSize(11)
                      .fontColor(this.textPrimary())
                  }
                  .height(26)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .borderRadius(13)
                  .margin(8)
                  .enabled(this.trackBvid !== '')
                  .opacity(this.trackBvid !== '' ? 1.0 : 0.4)
                  .onClick(() => {
                    this.openOriginal();
                  })
                }
                .width(300)
                .height(188)
                .borderRadius(18)
                .clip(true)
                .shadow({ radius: 30, color: $r('app.color.shadow_cover'), offsetY: 16 })
                .brightness(this.isPlaying ? 1 : 0.88)
                .animation({ duration: 400, curve: Curve.FastOutSlowIn })
              }
              .width(300)
              .height(188)
              .margin({ top: 24 }) // US10：原 8 过挤，展开态封面与状态栏留出呼吸感
              .alignSelf(ItemAlign.Center)
              .scale({ x: this.isPlaying ? 1 : 0.94, y: this.isPlaying ? 1 : 0.94 })
              .animation({ duration: 350, curve: Curve.FastOutSlowIn })

              Row() {
                Text(this.trackTitle)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textPrimary())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)

                if (this.trackIndex >= 0) {
                  Text('▼')
                    .fontSize(16)
                    .fontColor(this.textSecondary())
                    .margin({ left: 2 })
                    .padding(12)
                    .rotate({ angle: this.detailArrowUp ? 180 : 0 })
                    .animation({ duration: 200, curve: Curve.Smooth })
                }
              }
              .width('92%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 16, bottom: 4 })
              .onClick(() => {
                if (this.trackBvid !== '') {
                  this.detailArrowUp = true;
                  this.showDetail = true;
                  this.loadTrackDescIfNeeded();
                }
              })

              if (this.ownerName !== '') {
                Row() {
                  Row({ space: 6 }) {
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
                          .fontSize(11)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.accentColor)
                      }
                      .width(22)
                      .height(22)
                      .borderRadius(11)
                      .backgroundColor($r('app.color.card_background'))
                    }

                    Text(this.ownerName)
                      .fontSize(12)
                      .fontColor(this.textSecondary())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(VerticalAlign.Center)
                  .constraintSize({ maxWidth: '70%' })

                  if (this.playlistCount > 0) {
                    Blank()

                    Text(this.trackIndex >= 0 ? `${this.trackIndex + 1} / ${this.playlistCount}` : `共 ${this.playlistCount} 首`)
                      .fontSize(12)
                      .fontColor(this.textSecondary())
                  }
                }
                .width('92%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: 2 })
              } else if (this.playlistCount > 0) {
                Text(this.trackIndex >= 0 ? `${this.trackIndex + 1} / ${this.playlistCount}` : `共 ${this.playlistCount} 首`)
                  .fontSize(12)
                  .fontColor(this.textSecondary())
              }

              // 统计行（plan R8）：播放量 · 发布时间，居中次要色 12vp；无数据时沿用现有占位文案
              Text(`播放 ${this.formatCount(this.trackView)} · ${this.formatPubDate(this.trackPubdate)}`)
                .fontSize(12)
                .fontColor(this.textSecondary())
                .margin({ top: 6 })
            }
            .width('100%')
            // 信息区留白铺满（T007）：内容不足一屏时拉开分布铺满，超出仍可滚动（Scroll 行为不变）
            .constraintSize({ minHeight: '100%' })
            .justifyContent(FlexAlign.SpaceBetween)
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
                .selectedColor(this.accentColor)
                .blockColor(this.accentColor)
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
                  .fontSize(13)
                  .fontColor(this.textSecondary())

                Blank()

                Text(this.formatTime(this.duration))
                  .fontSize(13)
                  .fontColor(this.textSecondary())
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 2 })
            }
            .width('92%')

            // 控制栏（spec FR-005）：传输五键横排居中，播放键 72×72 主按钮，其余四键次级
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.backward_end_fill'))
                  .fontSize(22)
                  .fontColor([this.textPrimary()])
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.prevBtnScale, y: this.prevBtnScale })
              .enabled(this.playlistCount > 0)
              .opacity(this.playlistCount > 0 ? 1.0 : 0.4)
              .onClick(() => {
                this.popPrev();
                this.controller.prev();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.gobackward_15'))
                  .fontSize(22)
                  .fontColor([this.textPrimary()])
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .justifyContent(FlexAlign.Center)
              .enabled(this.isPrepared)
              .opacity(this.isPrepared ? 1.0 : 0.4)
              .onClick(() => {
                this.controller.seekBy(-Constants.SEEK_STEP_MS);
              })

              // 播放键（US1 尺寸同源）：缓冲中（isPreparing && playWhenReady）以系统 LoadingProgress
              // 反馈加载状态（US4，跨 API 版本表现一致），其余时间显示播放/暂停图标
              Stack() {
                if (this.isPreparing && this.playWhenReady) {
                  LoadingProgress()
                    .color(this.accentColor)
                    .width(Constants.PLAY_BTN_DIAMETER * 0.5)
                    .height(Constants.PLAY_BTN_DIAMETER * 0.5)
                } else if (this.isPlaying) {
                  SymbolGlyph($r('sys.symbol.pause_fill'))
                    .fontSize(32)
                    .fontColor([$r('app.color.text_primary')])
                } else {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(32)
                    .fontColor([$r('app.color.text_primary')])
                }
              }
              .width(Constants.PLAY_BTN_DIAMETER)
              .height(Constants.PLAY_BTN_DIAMETER)
              .borderRadius(Constants.PLAY_BTN_DIAMETER / 2)
              .backgroundColor(this.tintBg())
              .backdropBlur(20)
              .shadow({ radius: 18, color: this.playBtnShadowColor(), offsetY: 0 })
              .scale({ x: this.playBtnScale, y: this.playBtnScale })
              .enabled(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0)
              .opacity(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0 ? 1.0 : 0.4)
              .onClick(() => {
                this.popPlay();
                this.controller.togglePlay();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.goforward_15'))
                  .fontSize(22)
                  .fontColor([this.textPrimary()])
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .justifyContent(FlexAlign.Center)
              .enabled(this.isPrepared)
              .opacity(this.isPrepared ? 1.0 : 0.4)
              .onClick(() => {
                this.controller.seekBy(Constants.SEEK_STEP_MS);
              })

              Row() {
                SymbolGlyph($r('sys.symbol.forward_end_fill'))
                  .fontSize(22)
                  .fontColor([this.textPrimary()])
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .justifyContent(FlexAlign.Center)
              .scale({ x: this.nextBtnScale, y: this.nextBtnScale })
              .enabled(this.playlistCount > 0)
              .opacity(this.playlistCount > 0 ? 1.0 : 0.4)
              .onClick(() => {
                this.popNext();
                this.controller.next();
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: 12 })

            // 底部操作行（spec FR-006 / plan R6）：倍速/播放模式/定时/队列，沿用现有浮层与 @StorageLink 开关
            Row({ space: 12 }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.speed_multiple'))
                  .fontSize(16)
                  .fontColor([this.playbackRate === 1.0 ? this.textPrimary() : this.accentColor])
                Text(PlayerController.rateLabel(this.playbackRate))
                  .fontSize(13)
                  .fontColor(this.playbackRate === 1.0 ? this.textPrimary() : this.accentColor)
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .borderRadius(18)
              .onClick(() => {
                this.showSpeed = true;
              })

              Row() {
                SymbolGlyph(this.playModeIcon())
                  .fontSize(18)
                  .fontColor([this.accentColor])
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .borderRadius(18)
              .onClick(() => {
                this.showMode = true;
              })

              // 音质入口（audio-quality-settings FR-005 + T017）：直接显示当前音质档位短名；
              // dash 多音轨可用时以主题色高亮示意
              Row() {
                Text(this.qualityEntryLabel())
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.currentTrackSource === 'dash' ? this.accentColor : this.textPrimary())
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .borderRadius(18)
              .onClick(() => {
                this.showQuality = true;
              })

              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.timer'))
                  .fontSize(16)
                  .fontColor([this.sleepTimerActive ? this.accentColor : this.textPrimary()])
                if (this.sleepTimerActive) {
                  Text(this.formatRemaining(this.sleepTimerRemaining))
                    .fontSize(13)
                    .fontColor(this.accentColor)
                }
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .borderRadius(18)
              .onClick(() => {
                this.showSleepTimer = true;
              })

              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(22)
                  .fontColor([this.textPrimary()])
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, true);
              })
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: 14 })

            // 状态行（plan R10）：statusMsg 常驻固定底栏，任意滚动位置可见；isPreparing 时行首显示加载指示
            Row({ space: 6 }) {
              if (this.isPreparing) {
                LoadingProgress()
                  .color(this.accentColor)
                  .width(20)
                  .height(20)
              }

              Text(this.statusMsg)
                .fontSize(13)
                .fontColor(this.textSecondary())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .constraintSize({ maxWidth: '80%' })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .margin({ top: 10, bottom: 4 })
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: this.navBarHeight })

      if (this.showSpeed) {
        this.speedPanel()
      }

      if (this.showMode) {
        this.modePanel()
      }

      if (this.showSleepTimer) {
        this.sleepTimerPanel()
      }

      if (this.showSleepTimerPicker) {
        this.sleepTimerPicker()
      }

      if (this.showQuality) {
        this.qualityPanel()
      }

      // 播放队列抽屉：渲染在播放层内；显式最高 zIndex（US1）压过倍速/模式/睡眠面板与内容层，
      // 修复 API 24 平板 zIndex 失效导致抽屉被遮挡的问题（全平台行为一致）
      if (this.showQueueSheet) {
        QueueDrawer()
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    // 下滑退出播放层：仅在内容已滚到顶部时生效，避免与内容滚动冲突
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionEnd((event: GestureEvent) => {
          const atTop: boolean = this.contentScroller.currentOffset().yOffset <= 0;
          const noOverlayOpen: boolean = !this.showQueueSheet && !this.showSpeed && !this.showMode &&
            !this.showSleepTimer && !this.showSleepTimerPicker && !this.showDetail && !this.showQuality;
          if (noOverlayOpen && atTop && event.offsetY > PLAYER_DISMISS_SWIPE) {
            AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, false);
          }
        })
    )
    .bindSheet($$this.showDetail, this.detailSheet(), {
      height: '62%',
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.sheet_background'),
      preferType: SheetType.BOTTOM,
      // 手势下滑/遮罩关闭判定通过时：先即时翻转箭头再真正关闭（T011）
      shouldDismiss: (sheetDismiss: SheetDismiss) => {
        this.detailArrowUp = false;
        sheetDismiss.dismiss();
      },
      // 兜底：任何其他关闭路径同步箭头状态
      onDisappear: () => {
        this.detailArrowUp = false;
      }
    })
  }
}
