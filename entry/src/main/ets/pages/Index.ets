import { PlayerController } from '../service/PlayerController';
import { SleepTimerController } from '../service/SleepTimerController';
import { GripDetector } from '../service/GripDetector';

import { HomePage } from './HomePage';
import { PlayerOverlay } from './PlayerOverlay';
import { QueueSheet } from '../component/QueueSheet';
import { MiniPlayer } from '../component/MiniPlayer';
import { mediaquery } from '@kit.ArkUI';
import { Constants } from '../service/Constants';

@Entry
@Component
struct Index {
  @StorageProp('statusBarHeight') statusBarHeight: number = 38;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('showPlayerOverlay') showPlayerOverlay: boolean = false; // key 与 Constants.AS_SHOW_PLAYER_OVERLAY 对应
  @StorageLink('showQueueSheet') showQueueSheet: boolean = false; // key 与 Constants.AS_SHOW_QUEUE_SHEET 对应
  private navPathStack: NavPathStack = new NavPathStack();
  private pageWidth: number = 0;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;

  aboutToAppear(): void {
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SPEED, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_MODE, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SEARCH, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAY_HISTORY, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_PLAYLIST_SELECT_MODE, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, false);
    this.wideListener = mediaquery.matchMediaSync('(min-width: 600vp)');
    AppStorage.setOrCreate<boolean>(Constants.AS_IS_WIDE_SCREEN, false);
    this.wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      AppStorage.setOrCreate<boolean>(Constants.AS_IS_WIDE_SCREEN, result.matches);
    });
    const controller: PlayerController = PlayerController.getInstance();
    // 语义从「切到播放页签」改为「唤起全屏播放层」；调用方（PlayerOverlay/队列/设置等）约定不变
    controller.goToPlayerTab = (): void => {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, true);
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
    controller.init();
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

  // 拦截系统返回键：各浮层打开时先逐层关闭，而不是直接退出应用
  onBackPress(): boolean {
    if (AppStorage.get<boolean>(Constants.AS_SHOW_QUEUE_SHEET) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_SPEED) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SPEED, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_MODE) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_MODE, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_SLEEP_TIMER_PICKER) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_SLEEP_TIMER) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_SEARCH) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SEARCH, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_PLAYLIST_SELECT_MODE) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_PLAYLIST_SELECT_MODE, false);
      return true;
    }
    return false;
  }

  @Builder
  private playerOverlayBuilder() {
    PlayerOverlay()
  }

  build() {
    Stack() {
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

        MiniPlayer()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })

      if (this.showQueueSheet) {
        Column()
          .width('60%')
          .height('100%')
          .onClick(() => {
            this.showQueueSheet = false;
          })
      }

      if (this.showQueueSheet) {
        Column() {
          QueueSheet()
        }
        .width('40%')
        .height('100%')
        .backgroundColor($r('app.color.sheet_background'))
        .borderRadius({ topLeft: 16, bottomLeft: 16 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .bindContentCover($$this.showPlayerOverlay, this.playerOverlayBuilder(), {
      modalTransition: ModalTransition.DEFAULT
    })
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
