import { PlayerController } from '../service/PlayerController';
import { SleepTimerController } from '../service/SleepTimerController';
import { GripDetector } from '../service/GripDetector';

import { HomePage } from './HomePage';
import { PlayerOverlay } from './PlayerOverlay';
import { GlassSheet } from '../component/GlassSheet';
import { QueueSheet } from '../component/QueueSheet';
import { MiniPlayer } from '../component/MiniPlayer';
import { mediaquery, promptAction } from '@kit.ArkUI';
import { Constants } from '../service/Constants';
import { Logger } from '../service/Logger';
import { AppStore } from '../service/AppStore';
import { connectBool, connectNum, BoolState, NumState } from '../service/V2State';
import { registerQueueClose, dismissOverlaysForBack } from '../service/BackHandler';

@Entry
@ComponentV2
struct Index {
  @Local statusBarHeight: NumState = connectNum(Constants.AS_STATUS_BAR_HEIGHT, 38);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  @Local showPlayerOverlay: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  @Local showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  @Local onSettingsPage: BoolState = connectBool(Constants.AS_ON_SETTINGS_PAGE, false);
  @Local isWideScreen: BoolState = connectBool(Constants.AS_IS_WIDE_SCREEN, false);
  // US6/T022：胶囊显隐动画态——由显隐条件翻转驱动，animateTo 属性动画（Visibility 不参与 transition 机制故弃用）
  @Local miniHidden: boolean = false;
  private navPathStack: NavPathStack = new NavPathStack();
  private pageWidth: number = 0;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;

  aboutToAppear(): void {
    this.wideListener = mediaquery.matchMediaSync('(min-width: 600vp)');
    this.isWideScreen.value = false;
    this.wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.isWideScreen.value = result.matches;
    });
    const controller: PlayerController = PlayerController.getInstance();
    // 语义从「切到播放页签」改为「唤起全屏播放层」；调用方（PlayerOverlay/队列/设置等）约定不变
    controller.goToPlayerTab = (): void => {
      connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = true;
    };
    controller.confirmCellularDownload = (): Promise<boolean> => {
      return new Promise<boolean>((resolve) => {
        AlertDialog.show({
          title: '非 Wi-Fi 网络',
          message: '当前非 Wi-Fi 网络，在线播放会消耗流量，是否继续？',
          autoCancel: true,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: '继续播放',
            action: (): void => {
              resolve(true);
            }
          },
          secondaryButton: {
            value: '取消',
            action: (): void => {
              resolve(false);
            }
          },
          cancel: (): void => {
            resolve(false);
          }
        });
      });
    };
    controller.init().then((): void => {
      // debug 恢复前移冷启动（v0.4-Part1-ux-fixes US10）：AppStore 就绪后恢复 Logger 并提醒，
      // 修复「不进设置页 debug 不生效」；开启时冷启动 toast 一次
      const storedDebug: boolean = AppStore.getNumber(Constants.KEY_DEBUG_MODE, 0) === 1;
      Logger.setDebugMode(storedDebug);
      if (storedDebug) {
        promptAction.showToast({ message: '调试模式运行中' });
      }
    });
    GripDetector.start();
    // 睡眠定时归零后的提醒弹窗：关闭仅收起弹窗，重置用刚才时长重新倒计时
    SleepTimerController.getInstance().onTimerExpired = (): void => {
      AlertDialog.show({
        title: '定时关闭',
        message: '计时已结束，已暂停播放',
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '关闭',
          action: (): void => {
            SleepTimerController.getInstance().cancelTimer();
          }
        },
        secondaryButton: {
          value: '重置',
          action: (): void => {
            SleepTimerController.getInstance().restartTimer();
          }
        }
      });
    };
  }

  aboutToDisappear(): void {
    this.wideListener?.off('change');
    GripDetector.stop();
  }

  // US6/T022：胶囊显隐条件（浮层展开或设置页在台）翻转时，以属性动画过渡 opacity/translateY；
  // T021 已把 onSettingsPage 置位提前到导航转场开始，胶囊随之即时平滑出现/隐藏
  // v0.4-Part1-ux-fixes US3：AS_MINI_PLAYER_VISIBLE（消费方底部避让 padding 源）移入动画闭包与 miniHidden 同帧翻转——
  // 原先闭包外单帧瞬跳使返回首页时列表先跳位、胶囊后突现（「消失-突现」根因）
  @Monitor('showPlayerOverlay.value', 'onSettingsPage.value')
  onMiniVisibilityChanged(): void {
    const hidden: boolean = this.showPlayerOverlay.value || this.onSettingsPage.value;
    if (Logger.debugEnabled) {
      Logger.log('player', 'miniChain monitor', `hidden=${hidden} ts=${Date.now()}`);
    }
    this.getUIContext().animateTo({ duration: Constants.MINI_VISIBILITY_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.miniHidden = hidden;
      connectBool(Constants.AS_MINI_PLAYER_VISIBLE, true).value = !hidden;
    });
  }

  // 拦截系统返回键：队列/浮层经 BackHandler 统一「先关队列（多选优先退出）→ 再关浮层」序列（US5），
  // 其余弹层逐层关闭，而不是直接退出应用
  onBackPress(): boolean {
    if (dismissOverlaysForBack()) {
      return true;
    }
    const playHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
    if (playHistory.value) {
      playHistory.value = false;
      return true;
    }
    const showSpeed: BoolState = connectBool(Constants.AS_SHOW_SPEED, false);
    if (showSpeed.value) {
      showSpeed.value = false;
      return true;
    }
    const showMode: BoolState = connectBool(Constants.AS_SHOW_MODE, false);
    if (showMode.value) {
      showMode.value = false;
      return true;
    }
    const showSleepTimerPicker: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
    if (showSleepTimerPicker.value) {
      showSleepTimerPicker.value = false;
      return true;
    }
    const showSleepTimer: BoolState = connectBool(Constants.AS_SHOW_SLEEP_TIMER, false);
    if (showSleepTimer.value) {
      showSleepTimer.value = false;
      return true;
    }
    const selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
    if (selectMode.value) {
      selectMode.value = false;
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        Navigation(this.navPathStack) {
          HomePage({ navPathStack: this.navPathStack })
        }
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight.value })

      // 悬浮播放胶囊：底部对齐覆盖在内容之上，内容可从其后方滚过；
      // 恒挂载不卸载（避免 MiniPlayer 反复 mount 造成 PlayerController 订阅累积），
      // 播放浮层展开或设置页在台时以 opacity/translateY 属性动画淡出（US6/T022），
      // BLOCK_DESCENDANTS：自身+全部子孙退出命中测试，触摸落回下层
      Column() {
        MiniPlayer()
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L })
      .opacity(this.miniHidden ? 0 : 1)
      .translate({ y: this.miniHidden ? 24 : 0 })
      .hitTestBehavior(this.miniHidden ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default)

      // 队列浮层：仅内容层渲染；播放页展开时改由 PlayerOverlay 层渲染，避免被封面图层遮挡
      if (this.showQueueSheet.value && !this.showPlayerOverlay.value) {
        GlassSheet({
          openState: this.showQueueSheet,
          panelHeight: '65%',
          onRegisterClose: registerQueueClose
        }) {
          QueueSheet()
        }
      }

      // 全屏播放层（KI-5 方案B）：API 24 上 bindContentCover(ModalPage) 挂载后渲染管线即断开
      // （仅渲染首帧、组件伪 aboutToDisappear 同步出现，全量刷机后依旧），改用树内条件渲染承载，
      // 生命周期与渲染管线回归常规路径；expandSafeArea 延伸系统栏区域复现 ModalPage 全窗口视觉，
      // 底部滑入/滑出转场近似原 ModalTransition.DEFAULT 手感
      if (this.showPlayerOverlay.value) {
        PlayerOverlay({
          onRegisterClose: registerQueueClose
        })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .transition(TransitionEffect.translate({ y: '100%' })
            .animation({ duration: 350, curve: Curve.Friction }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageWidth = newArea.width as number;
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.changedTouches.length > 0) {
        GripDetector.reportTouch(event.changedTouches[0].windowX, this.pageWidth);
      }
    })
  }
}
