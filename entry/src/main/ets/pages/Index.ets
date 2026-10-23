import { PlayerController } from '../service/PlayerController';
import { SleepTimerController } from '../service/SleepTimerController';
import { GripDetector } from '../service/GripDetector';

import { HomePage } from './HomePage';
import { PlayerOverlay } from './PlayerOverlay';
import { SettingsPage } from './SettingsPage';
import { LogPage } from './LogPage';
import { GlassSheet } from '../component/GlassSheet';
import { QueueSheet } from '../component/QueueSheet';
import { HistorySheet } from '../component/HistorySheet';
import { MiniPlayer } from '../component/MiniPlayer';
import { mediaquery } from '@kit.ArkUI';
import { Constants } from '../service/Constants';
import { Logger } from '../service/Logger';
import { AppStore } from '../service/AppStore';
import { connectBool, connectNum, BoolState, NumState } from '../service/V2State';
import { registerQueueClose, registerHistoryClose, dismissOverlaysForBack } from '../service/BackHandler';

@Entry
@ComponentV2
struct Index {
  @Local statusBarHeight: NumState = connectNum(Constants.AS_STATUS_BAR_HEIGHT, 38);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  @Local showPlayerOverlay: BoolState = connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false);
  @Local showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);
  @Local showPlayHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
  @Local showSettingsPage: BoolState = connectBool(Constants.AS_SHOW_SETTINGS_PAGE, false);
  @Local showLogPage: BoolState = connectBool(Constants.AS_SHOW_LOG_PAGE, false);
  @Local isWideScreen: BoolState = connectBool(Constants.AS_IS_WIDE_SCREEN, false);
  private navPathStack: NavPathStack = new NavPathStack();
  private pageWidth: number = 0;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;
  private unsubPlayer: (() => void) | undefined = undefined;
  private lastErrorTick: number = 0;
  private lastUnfavToastTick: number = 0;
  private lastAnomalyToastTick: number = 0;

  aboutToAppear(): void {
    this.wideListener = this.getUIContext().getMediaQuery().matchMediaSync('(min-width: 600vp)');
    this.isWideScreen.value = false;
    this.wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.isWideScreen.value = result.matches;
    });
    const controller: PlayerController = PlayerController.getInstance();
    controller.confirmCellularDownload = (): Promise<boolean> => {
      return new Promise<boolean>((resolve) => {
        this.getUIContext().showAlertDialog({
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
    controller.confirmUnfavoriteRemoval = (count: number): Promise<boolean> => {
      return new Promise<boolean>((resolve) => {
        this.getUIContext().showAlertDialog({
          title: Constants.DIALOG_UNFAVORITE_TITLE,
          message: Constants.DIALOG_UNFAVORITE_MSG.replace('N', `${count}`),
          autoCancel: true,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: Constants.DIALOG_UNFAVORITE_CONFIRM,
            action: (): void => {
              resolve(true);
            }
          },
          secondaryButton: {
            value: Constants.DIALOG_UNFAVORITE_CANCEL,
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
    // 播放出错提醒（v0.5-part3 US6）：emitUi 广播内比对 errorTick 版本计数，变化即弹系统 toast；
    // 须在 init() 前订阅，冷启动自动续播（init 内起播路径）的早期错误不漏；
    // emitUi 每秒进度节流也会进此回调，tick 比对恒假零开销
    this.lastErrorTick = controller.errorTick;
    this.lastUnfavToastTick = controller.unfavToastTick;
    this.lastAnomalyToastTick = controller.anomalyToastTick;
    this.unsubPlayer = controller.subscribe((): void => {
      if (controller.errorTick !== this.lastErrorTick) {
        this.lastErrorTick = controller.errorTick;
        this.getUIContext().getPromptAction().showToast({ message: Constants.TOAST_PLAYBACK_ERROR });
      }
      if (controller.unfavToastTick !== this.lastUnfavToastTick) {
        this.lastUnfavToastTick = controller.unfavToastTick;
        this.getUIContext().getPromptAction().showToast({ message: controller.unfavToastMsg });
      }
      if (controller.anomalyToastTick !== this.lastAnomalyToastTick) {
        this.lastAnomalyToastTick = controller.anomalyToastTick;
        this.getUIContext().getPromptAction().showToast({ message: controller.anomalyToastMsg });
      }
    }, 'Index');
    controller.init().then((): void => {
      // debug 恢复前移冷启动（v0.4-Part1-ux-fixes US10）：AppStore 就绪后恢复 Logger 并提醒，
      // 修复「不进设置页 debug 不生效」；开启时冷启动 toast 一次
      const storedDebug: boolean = AppStore.getNumber(Constants.KEY_DEBUG_MODE, 0) === 1;
      Logger.setDebugMode(storedDebug);
      if (storedDebug) {
        this.getUIContext().getPromptAction().showToast({ message: '调试模式运行中' });
      }
    });
    GripDetector.start();
    // 睡眠定时归零后的提醒弹窗：关闭仅收起弹窗，重置用刚才时长重新倒计时
    SleepTimerController.getInstance().onTimerExpired = (): void => {
      this.getUIContext().showAlertDialog({
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
    this.unsubPlayer?.();
    this.wideListener?.off('change');
    GripDetector.stop();
  }

  // 拦截系统返回键：BackHandler 全链分层关闭（队列→倍速→模式→睡眠选择→睡眠→浮层→日志层→设置句柄→设置层），
  // 无层可关返回 false 放行默认行为
  onBackPress(): boolean {
    return dismissOverlaysForBack();
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
      // 设置/日志/播放浮层在 Stack 中位于其上，物理覆盖替代原显隐动画
      Column() {
        MiniPlayer()
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L })

      // 设置层（L2）：自右侧滑入，覆盖胶囊；历史面板已升为 L4 独立层（层序契约）
      if (this.showSettingsPage.value) {
        Column() {
          SettingsPage()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight.value })
        .transition(TransitionEffect.translate({ x: '100%' })
          .animation({ duration: Constants.PAGE_LAYER_SLIDE_MS, curve: Curve.Friction }))
      }

      // 日志层（L2）：设置层之上，同转场
      if (this.showLogPage.value) {
        Column() {
          LogPage()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight.value })
        .transition(TransitionEffect.translate({ x: '100%' })
          .animation({ duration: Constants.PAGE_LAYER_SLIDE_MS, curve: Curve.Friction }))
      }

      // 全屏播放层（KI-5 方案B）：API 24 上 bindContentCover(ModalPage) 挂载后渲染管线即断开
      // （仅渲染首帧、组件伪 aboutToDisappear 同步出现，全量刷机后依旧），改用树内条件渲染承载，
      // 生命周期与渲染管线回归常规路径；expandSafeArea 延伸系统栏区域复现 ModalPage 全窗口视觉，
      // 底部滑入/滑出转场近似原 ModalTransition.DEFAULT 手感
      if (this.showPlayerOverlay.value) {
        PlayerOverlay()
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .transition(TransitionEffect.translate({ y: '100%' })
            .animation({ duration: 350, curve: Curve.Friction }))
      }

      // 历史面板（L4 独立层）：设置层之上、队列之下，入口在设置页，点条目仅起播不收面板
      if (this.showPlayHistory.value) {
        GlassSheet({
          openState: this.showPlayHistory,
          panelHeight: '62%',
          onRegisterClose: registerHistoryClose
        }) {
          HistorySheet()
        }
      }

      // 队列浮层（L5 层序最高）：单一挂载点，展开态两入口（胶囊长按/播放浮层）共用
      if (this.showQueueSheet.value) {
        GlassSheet({
          openState: this.showQueueSheet,
          panelHeight: '65%',
          onRegisterClose: registerQueueClose
        }) {
          QueueSheet()
        }
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
