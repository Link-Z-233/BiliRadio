import { PlayerController } from '../service/PlayerController';
import { SleepTimerController } from '../service/SleepTimerController';
import { GripDetector } from '../service/GripDetector';

import { PlayerPage } from './PlayerPage';
import { PlaylistPage } from './PlaylistPage';
import { FoldersPage } from './FoldersPage';
import { SettingsPage } from './SettingsPage';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { SymbolGlyphModifier, mediaquery } from '@kit.ArkUI';
import { Constants } from '../service/Constants';
import { AppStore } from '../service/AppStore';

class TabItem {
  title: string = '';
  normalIcon: SymbolGlyphModifier;
  selectedIcon: SymbolGlyphModifier;

  constructor(title: string, symbol: Resource) {
    this.title = title;
    // 颜色使用资源引用：深浅色切换时框架按 base/dark 自动解析，底栏图标随外观联动
    this.normalIcon = new SymbolGlyphModifier(symbol).fontColor([$r('app.color.text_primary')]);
    this.selectedIcon = new SymbolGlyphModifier(symbol).fontColor([$r('app.color.primary_color')]);
  }
}

@Entry
@Component
struct Index {
  private tabsController: HdsTabsController = new HdsTabsController();
  private tabs: TabItem[] = [
    new TabItem('播放', $r('sys.symbol.play')),
    new TabItem('播放列表', $r('sys.symbol.list_bullet')),
    new TabItem('歌曲源', $r('sys.symbol.star')),
    new TabItem('设置', $r('sys.symbol.gearshape')),
  ];
  // 仅记录当前页签，不驱动 UI，避免 @State 触发无谓的全页重渲染
  private currentTab: number = 0;
  // 背景模糊强度：播放页较弱，其余页更模糊（切页时更新）
  @State bgBlur: number = 12;
  // 悬浮页签材质等级：满血沉浸光感过于通透影响图标可读性，支持 IMMERSIVE 的设备用 GENTLE，其余降级 SMOOTH
  @State barMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.GENTLE;
  @State coverUrl: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 38;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 封面模糊背景压暗滤镜：由 Appearance 按生效外观写入（深色 0.8，浅色 1.0 避免发黑）
  @StorageProp('coverBrightness') coverBrightness: number = 0.55;
  private pageWidth: number = 0;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;

  aboutToAppear(): void {
    try {
      const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
        this.barMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
      }
    } catch (e) {
      this.barMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
    }
    AppStorage.setOrCreate<number>(Constants.AS_FLOATING_TAB_HEIGHT, Constants.FLOATING_TAB_HEIGHT);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_HISTORY, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SPEED, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_MODE, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SLEEP_TIMER_PICKER, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_SEARCH, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAY_HISTORY, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_PLAYLIST_SELECT_MODE, false);
    AppStorage.setOrCreate<boolean>(Constants.AS_FOLDER_DOWNLOAD_SELECT_MODE, false);
    this.wideListener = mediaquery.matchMediaSync('(min-width: 600vp)');
    AppStorage.setOrCreate<boolean>(Constants.AS_IS_WIDE_SCREEN, false);
    this.wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      AppStorage.setOrCreate<boolean>(Constants.AS_IS_WIDE_SCREEN, result.matches);
    });
    const controller: PlayerController = PlayerController.getInstance();
    controller.goToPlayerTab = (): void => {
      this.tabsController.changeIndex(0);
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
    controller.subscribe((): void => {
      this.syncCover();
    });
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

  // 拦截系统返回键：取消收藏历史/倍速浮层打开时先关闭浮层，而不是直接退出应用
  onBackPress(): boolean {
    if (AppStorage.get<boolean>(Constants.AS_SHOW_HISTORY) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_HISTORY, false);
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
    if (AppStorage.get<boolean>(Constants.AS_SHOW_PLAY_HISTORY) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAY_HISTORY, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_PLAYLIST_SELECT_MODE) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_PLAYLIST_SELECT_MODE, false);
      return true;
    }
    if (AppStorage.get<boolean>(Constants.AS_FOLDER_SELECT_MODE) === true) {
      AppStorage.setOrCreate<boolean>(Constants.AS_FOLDER_SELECT_MODE, false);
      return true;
    }
    return false;
  }

  private syncCover(): void {
    const c: PlayerController = PlayerController.getInstance();
    let url: string = '';
    const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    if (!dataSaver && c.currentIndex >= 0 && c.currentIndex < c.playlist.length) {
      url = c.playlist[c.currentIndex].cover;
    }
    // emitUi 在播放进度等高频回调中触发，仅封面真正变化时才更新状态，避免反复进入状态管理
    if (url !== this.coverUrl) {
      this.coverUrl = url;
    }
  }

  build() {
    Stack() {
      // 页面背景 — 延伸到顶部和底部安全区
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 全局封面背景 — 与当前歌曲封面同步，切歌渐变过渡
      if (this.coverUrl !== '') {
        Stack() {
          Image(this.coverUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .interpolation(ImageInterpolation.Low)
            .saturate(1.5)
            .brightness(this.coverBrightness)
            .blur(this.bgBlur)
            .contentTransition(ContentTransitionEffect.OPACITY)

          // 遮罩颜色为资源引用：深色保持现有深蓝紫重遮罩，浅色为白色系协调遮罩
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [
                [$r('app.color.cover_mask_top'), 0],
                [$r('app.color.cover_mask_mid'), 0.45],
                [$r('app.color.cover_mask_end'), 1]
              ]
            })
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.Smooth }))
      }

      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          PlayerPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: this.tabs[0].normalIcon,
          selected: this.tabs[0].selectedIcon
        }, this.tabs[0].title)
          .labelStyle({
            unselectedColor: $r('app.color.text_primary'),
            selectedColor: $r('app.color.primary_color')
          }))

        TabContent() {
          PlaylistPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: this.tabs[1].normalIcon,
          selected: this.tabs[1].selectedIcon
        }, this.tabs[1].title)
          .labelStyle({
            unselectedColor: $r('app.color.text_primary'),
            selectedColor: $r('app.color.primary_color')
          }))

        TabContent() {
          FoldersPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: this.tabs[2].normalIcon,
          selected: this.tabs[2].selectedIcon
        }, this.tabs[2].title)
          .labelStyle({
            unselectedColor: $r('app.color.text_primary'),
            selectedColor: $r('app.color.primary_color')
          }))

        TabContent() {
          SettingsPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: this.tabs[3].normalIcon,
          selected: this.tabs[3].selectedIcon
        }, this.tabs[3].title)
          .labelStyle({
            unselectedColor: $r('app.color.text_primary'),
            selectedColor: $r('app.color.primary_color')
          }))
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .scrollable(false)
      .barOverlap(true)
      .barFloatingStyle({
        barBottomMargin: 0,
        // 全透明遮罩，深浅色一致；悬浮材质本身为系统 ADAPTIVE 材质，自动适配深浅色
        gradientMask: {
          maskColor: 'rgba(0, 0, 0, 0)',
          maskHeight: 92
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.barMaterialLevel
        }
      })
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentTab = index;
        const target: number = index === 0 ? 12 : 28;
        this.getUIContext().animateTo({ duration: 400, curve: Curve.EaseInOut }, (): void => {
          this.bgBlur = target;
        });
      })
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
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
