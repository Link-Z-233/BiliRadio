import { PlayerController, PlayMode as MusicPlayMode, PLAYBACK_RATES, PLAY_MODES } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
// import { uiMaterial } from '@kit.ArkUI';
import { ForegroundColor } from '../component/ForegroundColor';
import { AppStore } from '../service/AppStore';
import { Constants } from '../service/Constants';
import { SleepTimerController } from '../service/SleepTimerController';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 封面光晕呼吸参数：静止亮度 / 呼吸峰值 / 呼吸周期
const GLOW_IDLE: number = 0.35;
const GLOW_ACTIVE: number = 0.8;
const GLOW_BREATH_MS: number = 3200;

@Component
export struct PlayerPage {
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

  @State glowStrength: number = GLOW_IDLE;
  @State playBtnScale: number = 1;
  @State prevBtnScale: number = 1;
  @State nextBtnScale: number = 1;
  @State trackIndex: number = -1;
  @State playlistCount: number = 0;
  @State canUnfavorite: boolean = false;
  @State showDetail: boolean = false;
  @State sleepTimerActive: boolean = false;
  @State sleepTimerRemaining: number = 0;
  @State pickerHour: number = 0;
  @State pickerMinute: number = 0;
  @State trackView: number = 0;
  @State trackPubdate: number = 0;
  @State trackDesc: string = '';
  private trackBvid: string = '';
  private wasPlaying: boolean = false;
  @StorageProp('floatingTabHeight') floatingTabHeight: number = 90;
  // 智能反色：封面偏暗时 true，前景文字自动转浅色保证可读
  @StorageProp('coverIsDark') coverIsDark: boolean = false;
  private controller: PlayerController = PlayerController.getInstance();

  private textPrimary(): Resource {
    return ForegroundColor.primary(this.coverIsDark);
  }

  private textSecondary(): Resource {
    return ForegroundColor.secondary(this.coverIsDark);
  }

  private textDisabled(): Resource {
    return ForegroundColor.disabled(this.coverIsDark);
  }


  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.wasPlaying = this.isPlaying;
    this.updateGlow();
    this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
      if (this.isPlaying !== this.wasPlaying) {
        this.wasPlaying = this.isPlaying;
        this.updateGlow();
      }
    });
    SleepTimerController.getInstance().subscribe((): void => {
      this.syncSleepTimer();
    });
    this.syncSleepTimer();
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


  private syncFrom(c: PlayerController): void {
    this.isPlaying = c.isPlaying;
    this.isPrepared = c.isPrepared;
    this.isPreparing = c.isPreparing;
    this.playWhenReady = c.playWhenReady;
    this.currentTime = c.currentTime;
    this.duration = c.duration;
    if (!this.isSeeking) {
      this.sliderValue = c.duration > 0 ? c.currentTime / c.duration * 100 : 0;
    }
    this.statusMsg = c.statusMsg;
    this.playMode = c.playMode;
    this.playbackRate = c.playbackRate;
    this.playlistCount = c.playlist.length;
    if (c.currentIndex >= 0 && c.currentIndex < c.playlist.length) {
      const item: BiliVideo = c.playlist[c.currentIndex];
      const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
      this.trackTitle = item.title;
      this.trackCover = dataSaver ? '' : item.cover;
      this.ownerName = item.ownerName;
      this.ownerFace = dataSaver ? '' : item.ownerFace;
      this.trackBvid = item.bvid;
      this.trackIndex = c.currentIndex;
      this.canUnfavorite = item.folderIds.length > 0;
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
      this.canUnfavorite = false;
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
              .backgroundColor(rate === this.playbackRate ? $r('app.color.material_tint_primary') : $r('app.color.btn_glass'))
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
              .backgroundColor(mode === this.playMode ? $r('app.color.material_tint_primary') : $r('app.color.btn_glass'))
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
            .backgroundColor($r('app.color.material_tint_primary'))
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
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
        if (this.trackIndex < 0 && this.playlistCount === 0) {
          Column() {
            Text('BiliRadio')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .margin({ top: 60 })

            Text('未在播放')
              .fontSize(16)
              .fontColor(this.textSecondary())
              .margin({ top: 40 })

            Text('去"歌单"页输入BV号添加歌曲\n或在"歌曲源"页生成歌单')
              .fontSize(13)
              .fontColor(this.textDisabled())
              .textAlign(TextAlign.Center)
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
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
                    colors: [
                      [$r('app.color.halo_pink_0'), 0],
                      [$r('app.color.halo_pink_1'), 0.45],
                      [$r('app.color.halo_pink_2'), 0.75],
                      [$r('app.color.halo_pink_3'), 1]
                    ]
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
                        .fontColor($r('app.color.primary_color'))
                    }
                    .width(300)
                    .height(188)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.card_background'))
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }

                  Button('播放视频')
                    .height(26)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor($r('app.color.btn_glass'))
                    .backdropBlur(20)
                    .fontColor(this.textPrimary())
                    .borderRadius(13)
                    .fontSize(11)
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
              .margin({ top: 32 })
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
                    .fontSize(12)
                    .fontColor(this.textSecondary())
                    .margin({ left: 6 })
                    .padding(4)
                    .rotate({ angle: this.showDetail ? 180 : 0 })
                    .animation({ duration: 200, curve: Curve.Smooth })
                }
              }
              .width('92%')
              .height(52)
              .alignItems(VerticalAlign.Center)
              .margin({ top: 16, bottom: 4 })
              .onClick(() => {
                if (this.trackBvid !== '') {
                  this.showDetail = true;
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
                          .fontColor($r('app.color.primary_color'))
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

              Row() {
                Text(this.formatTime(this.isSeeking ? this.sliderValue / 100 * this.duration : this.currentTime))
                  .fontSize(12)
                  .fontColor(this.textSecondary())
                  .width(48)

                Slider({
                  value: this.sliderValue,
                  min: 0,
                  max: 100,
                  step: 1,
                })
                  .layoutWeight(1)
                  .trackColor($r('app.color.track_color'))
                  .selectedColor($r('app.color.primary_color'))
                  .blockColor($r('app.color.primary_color'))
                  // TODO: uiMaterial.ImmersiveStyle 在 API 24 模拟器不可用，待升级后恢复
                  // .systemMaterial(new uiMaterial.ImmersiveMaterial({
                  //   style: uiMaterial.ImmersiveStyle.REGULAR,
                  //   interactive: true,
                  //   lightEffect: { color: $r('app.color.primary_color') },
                  // }))
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

                Text(this.formatTime(this.duration))
                  .fontSize(12)
                  .fontColor(this.textSecondary())
                  .width(48)
                  .textAlign(TextAlign.End)
              }
              .width('92%')
              .justifyContent(FlexAlign.Center)
              .margin({ top: 20 })

              Row({ space: 24 }) {
                Button('上一首')
                  .height(44)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor(this.textPrimary())
                  .borderRadius(22)
                  .fontSize(14)
                  .scale({ x: this.prevBtnScale, y: this.prevBtnScale })
                  .enabled(this.playlistCount > 0)
                  .opacity(this.playlistCount > 0 ? 1.0 : 0.4)
                  .onClick(() => {
                    this.popPrev();
                    this.controller.prev();
                  })

                Button(this.isPlaying || (this.isPreparing && this.playWhenReady) ? '暂停' : '播放')
                  .width(72)
                  .height(72)
                  .borderRadius(36)
                  .backgroundColor($r('app.color.material_tint_primary'))
                  .backdropBlur(20)
                  .fontColor($r('app.color.text_primary'))
                  .fontSize(18)
                  .shadow({ radius: 18, color: $r('app.color.shadow_play'), offsetY: 0 })
                  .scale({ x: this.playBtnScale, y: this.playBtnScale })
                  .enabled(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0)
                  .opacity(this.isPrepared || this.trackIndex >= 0 || this.playlistCount > 0 ? 1.0 : 0.4)
                  .onClick(() => {
                    this.popPlay();
                    this.controller.togglePlay();
                  })

                Button('下一首')
                  .height(44)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor(this.textPrimary())
                  .borderRadius(22)
                  .fontSize(14)
                  .scale({ x: this.nextBtnScale, y: this.nextBtnScale })
                  .enabled(this.playlistCount > 0)
                  .opacity(this.playlistCount > 0 ? 1.0 : 0.4)
                  .onClick(() => {
                    this.popNext();
                    this.controller.next();
                  })
              }
              .margin({ top: 24 })
              .justifyContent(FlexAlign.Center)

              Row({ space: 12 }) {
                Button(`倍速 ${PlayerController.rateLabel(this.playbackRate)}`)
                  .height(36)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor(this.playbackRate === 1.0 ? this.textPrimary() : $r('app.color.primary_color'))
                  .borderRadius(18)
                  .fontSize(13)
                  .onClick(() => {
                    this.showSpeed = true;
                  })

                Button(PlayerController.modeLabel(this.playMode))
                  .height(36)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor($r('app.color.primary_color'))
                  .borderRadius(18)
                  .fontSize(13)
                  .onClick(() => {
                    this.showMode = true;
                  })

                Button('取消收藏')
                  .height(36)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor(this.textPrimary())
                  .borderRadius(18)
                  .fontSize(13)
                  .enabled(this.canUnfavorite)
                  .opacity(this.canUnfavorite ? 1.0 : 0.4)
                  .onClick(() => {
                    this.controller.unfavoriteCurrent();
                  })

                Button(this.sleepTimerActive ? this.formatRemaining(this.sleepTimerRemaining) : '定时关闭')
                  .height(36)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor($r('app.color.btn_glass'))
                  .backdropBlur(20)
                  .fontColor(this.sleepTimerActive ? $r('app.color.primary_color') : this.textPrimary())
                  .borderRadius(18)
                  .fontSize(13)
                  .onClick(() => {
                    this.showSleepTimer = true;
                  })
              }
              .margin({ top: 16 })
              .justifyContent(FlexAlign.Center)

              Text(this.statusMsg)
                .fontSize(13)
                .fontColor(this.textSecondary())
                .margin({ top: 16, bottom: 24 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('92%')
                .textAlign(TextAlign.Center)

              if (this.isPreparing) {
                LoadingProgress()
                  .color($r('app.color.primary_color'))
                  .width(36)
                  .height(36)
                  .margin({ bottom: 24 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .scrollable(ScrollDirection.Vertical)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.floatingTabHeight })

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
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showDetail, this.detailSheet(), {
      height: '62%',
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.sheet_background'),
    })
  }
}
