import { PlayerController } from '../service/PlayerController';
import { SleepTimerController } from '../service/SleepTimerController';
import { GripDetector } from '../service/GripDetector';

import { HomePage } from './HomePage';
import { PlayerOverlay } from './PlayerOverlay';
import { QueueDrawer } from '../component/QueueDrawer';
import { MiniPlayer } from '../component/MiniPlayer';
import { mediaquery } from '@kit.ArkUI';
import { Constants } from '../service/Constants';

@Entry
@Component
struct Index {
  @StorageProp('statusBarHeight') statusBarHeight: number = 38;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('showPlayerOverlay') @Watch('onMiniVisibilityChanged') showPlayerOverlay: boolean = false; // key 与 Constants.AS_SHOW_PLAYER_OVERLAY 对应
  @StorageLink('showQueueSheet') showQueueSheet: boolean = false; // key 与 Constants.AS_SHOW_QUEUE_SHEET 对应
  @StorageLink('onSettingsPage') @Watch('onMiniVisibilityChanged') onSettingsPage: boolean = false; // key 与 Constants.AS_ON_SETTINGS_PAGE 对应
  // US6/T022：胶囊显隐动画态——由显隐条件翻转驱动，animateTo 属性动画（Visibility 不参与 transition 机制故弃用）
  @State miniHidden: boolean = false;
  private navPathStack: NavPathStack = new NavPathStack();
  private pageWidth: number = 0;
  // US7/T024：QueueDrawer 注册的关闭句柄（先播滑出动画再卸载）；空句柄回退直接卸载
  private queueClose: (() => void) | undefined = undefined;
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
    // US7：设置页在台标志初始化（SettingsPage aboutToAppear/Disappear 维护）
    AppStorage.setOrCreate<boolean>(Constants.AS_ON_SETTINGS_PAGE, false);
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

  // US6/T022：胶囊显隐条件（浮层展开或设置页在台）翻转时，以属性动画过渡 opacity/translateY；
  // T021 已把 onSettingsPage 置位提前到导航转场开始，胶囊随之即时平滑出现/隐藏
  private onMiniVisibilityChanged(): void {
    const hidden: boolean = this.showPlayerOverlay || this.onSettingsPage;
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
      this.miniHidden = hidden;
    });
  }

  // 拦截系统返回键：各浮层打开时先逐层关闭，而不是直接退出应用
  onBackPress(): boolean {
    if (AppStorage.get<boolean>(Constants.AS_SHOW_QUEUE_SHEET) === true) {
      // US7/T024：返回键退出播放队列也走滑出动画（与遮罩点击一致）；句柄为空（如极端时序下
      // 抽屉刚被卸载未及注册）回退直接置 false 卸载
      if (this.queueClose !== undefined) {
        this.queueClose();
      } else {
        AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, false);
      }
      return true;
    }
    // US4：浮层与历史面板同开时，第一次返回仅关面板（播放不中断），再按才收浮层；
    // 禁止返回事件穿透弹回首页
    if (AppStorage.get<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY) === true) {
      if (AppStorage.get<boolean>(Constants.AS_SHOW_PLAY_HISTORY) === true) {
        AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAY_HISTORY, false);
        return true;
      }
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_SHOW_PLAY_HISTORY) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAY_HISTORY, false);
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
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })

      // 悬浮播放胶囊：底部对齐覆盖在内容之上，内容可从其后方滚过；
      // 恒挂载不卸载（避免 MiniPlayer 反复 mount 造成 PlayerController 订阅累积），
      // 播放浮层展开或设置页在台时以 opacity/translateY 属性动画淡出（US6/T022），
      // 透明时不响应点击；AS_MINI_PLAYER_VISIBLE 上报与 MINI_PLAYER_CLEARANCE 避让不变
      Column() {
        MiniPlayer()
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .opacity(this.miniHidden ? 0 : 1)
      .translate({ y: this.miniHidden ? 24 : 0 })
      .hitTestBehavior(this.miniHidden ? HitTestMode.None : HitTestMode.Default)

      // 队列抽屉：仅内容层渲染；播放页展开时改由 PlayerOverlay 层渲染，避免被封面图层遮挡
      if (this.showQueueSheet && !this.showPlayerOverlay) {
        QueueDrawer({
          onRegisterClose: (close: (() => void) | undefined): void => {
            this.queueClose = close;
          }
        })
      }

      // 全屏播放层（KI-5 方案B）：API 24 上 bindContentCover(ModalPage) 挂载后渲染管线即断开
      // （仅渲染首帧、组件伪 aboutToDisappear 同步出现，全量刷机后依旧），改用树内条件渲染承载，
      // 生命周期与渲染管线回归常规路径；expandSafeArea 延伸系统栏区域复现 ModalPage 全窗口视觉，
      // 底部滑入/滑出转场近似原 ModalTransition.DEFAULT 手感
      if (this.showPlayerOverlay) {
        PlayerOverlay()
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
