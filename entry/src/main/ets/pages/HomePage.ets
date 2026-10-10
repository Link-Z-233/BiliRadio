import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';
import { EdgeHint } from '../component/EdgeHint';
import { AddSubscriptionSheet, AddSheetBackHandler } from './AddSubscriptionSheet';
import { promptAction } from '@kit.ArkUI';

interface PopupStateChange {
  isVisible: boolean;
}

class SubRow {
  sub: Subscription = new Subscription();
  latestTitle: string = '';
  newCount: number = 0;
}

class SubDataSource implements IDataSource {
  private rows: SubRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): SubRow {
    return this.rows[index];
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

  reload(rows: SubRow[]): void {
    this.rows = rows;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

// 主页：订阅源列表（新集徽标 / 长按置顶删除 / 空态）；下拉刷新已注释禁用（[DISABLED 2026-10]，见 PROJECT_NOTES.md）
@Component
export struct HomePage {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @StorageProp('miniPlayerVisible') miniPlayerVisible: boolean = false; // key 与 Constants.AS_MINI_PLAYER_VISIBLE 对应
  @StorageProp('navBarHeight') navBarHeight: number = 0; // key 与 Constants.AS_NAV_BAR_HEIGHT 对应
  // key 与 Constants.AS_HOME_REFRESH_TICK 对应：源页退出（onHidden）触发重算（US4 返回首页徽标清除）
  @StorageProp('homeRefreshTick') @Watch('onHomeRefreshTick') homeRefreshTick: number = 0;
  // [DISABLED 2026-10] 首页下拉刷新暂时禁用，恢复方式见 PROJECT_NOTES.md「已移除与禁用功能」
  // @State refreshing: boolean = false;
  @State rowCount: number = 0;
  @State showAddSheet: boolean = false;
  // US5 过冲提示（顶/底），空串不渲染
  @State topHint: string = '';
  @State bottomHint: string = '';
  // 添加订阅面板的系统返回拦截句柄（onWillDismiss PRESS_BACK 时经其询问面板是否消费）
  private addSheetBack: AddSheetBackHandler = new AddSheetBackHandler();
  private subs: Subscription[] = [];
  private provider: SubDataSource = new SubDataSource();
  private refreshingNow: boolean = false;
  // US9：拖拽中标志（onReachStart 初始化会误触发一次，仅拖拽期间允许置过冲提示）
  private dragging: boolean = false;
  private scroller: Scroller = new Scroller();
  // 触底时刻的列表偏移（US5 底部过冲判定基准）；-1 = 未捕获，列表重建后失效须重捕
  private endOffsetY: number = -1;
  navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.subs = SubscriptionStore.loadSubscriptions();
    this.rebuild();
    this.silentRefresh();
  }

  private rebuild(): void {
    this.subs = SubscriptionStore.loadSubscriptions();
    this.subs.sort((a: Subscription, b: Subscription): number => a.sortOrder - b.sortOrder);
    this.endOffsetY = -1;
    const rows: SubRow[] = [];
    for (let i = 0; i < this.subs.length; i++) {
      const sub: Subscription = this.subs[i];
      const row: SubRow = new SubRow();
      row.sub = sub;
      const episodes: BiliVideo[] = SubscriptionStore.loadEpisodes(sub.id);
      row.latestTitle = episodes.length > 0 ? episodes[0].title : '暂无节目';
      row.newCount = Subscription.countNew(episodes, sub.lastSeenAt);
      rows.push(row);
    }
    this.rowCount = rows.length;
    this.provider.reload(rows);
  }

  // US4：源页退出经 AppStorage tick 触发（onPop 对无参 pop() 永不回调，见 SourcePage.onHidden 注释）
  private onHomeRefreshTick(): void {
    this.rebuild();
  }

  private persistRefreshedSub(sub: Subscription, ok: boolean): void {
    SubscriptionStore.persistRefreshedSub(sub, ok);
    this.rebuild();
  }

  private silentRefresh(): void {
    if (this.refreshingNow) {
      return;
    }
    this.refreshingNow = true;
    SubscriptionStore.refreshAll(this.subs, false, (sub: Subscription, ok: boolean): void => {
      this.persistRefreshedSub(sub, ok);
    }).then((): void => {
      this.refreshingNow = false;
    }).catch((): void => {
      this.refreshingNow = false;
    });
  }

  // [DISABLED 2026-10] 随首页下拉刷新一并禁用（恢复时取消下方整段注释即可；
  // 恢复步骤详见 PROJECT_NOTES.md「已移除与禁用功能」）
  // private manualRefresh(): void {
  //   if (this.refreshingNow) {
  //     this.refreshing = false;
  //     return;
  //   }
  //   this.refreshingNow = true;
  //   SubscriptionStore.refreshAll(this.subs, true, (sub: Subscription, ok: boolean): void => {
  //     SubscriptionStore.saveSubscriptions(this.subs);
  //     this.rebuild();
  //   }).then((): void => {
  //     this.refreshingNow = false;
  //     this.refreshing = false;
  //   }).catch((): void => {
  //     this.refreshingNow = false;
  //     this.refreshing = false;
  //   });
  // }

  private pinToTop(row: SubRow): void {
    let min: number = 0;
    for (let i = 0; i < this.subs.length; i++) {
      if (this.subs[i].sortOrder < min) {
        min = this.subs[i].sortOrder;
      }
    }
    row.sub.sortOrder = min - 1;
    SubscriptionStore.saveSubscriptions(this.subs);
    this.rebuild();
  }

  private removeSub(row: SubRow): void {
    const idx: number = this.subs.indexOf(row.sub);
    if (idx < 0) {
      return;
    }
    this.subs.splice(idx, 1);
    SubscriptionStore.removeEpisodes(row.sub.id);
    SubscriptionStore.saveSubscriptions(this.subs);
    this.rebuild();
  }

  private addSubscription(sub: Subscription): void {
    for (let i = 0; i < this.subs.length; i++) {
      if (this.subs[i].id === sub.id) {
        promptAction.showToast({ message: '已订阅该源' });
        return;
      }
    }
    let max: number = 0;
    for (let i = 0; i < this.subs.length; i++) {
      if (this.subs[i].sortOrder > max) {
        max = this.subs[i].sortOrder;
      }
    }
    sub.sortOrder = max + 1;
    this.subs.push(sub);
    SubscriptionStore.saveSubscriptions(this.subs);
    this.rebuild();
    // 新源立即刷一次，拿到封面/剧集后再刷新列表
    SubscriptionStore.refreshSubscription(sub).then((): void => {
      this.persistRefreshedSub(sub, true);
    }).catch((err: Error): void => {
      promptAction.showToast({ message: `刷新节目失败: ${err.message}` });
    });
  }

  @Builder
  private addSheetBuilder() {
    AddSubscriptionSheet({
      backHandler: this.addSheetBack,
      onSubscribed: (sub: Subscription): void => {
        this.addSubscription(sub);
      },
      onDismiss: (): void => {
        this.showAddSheet = false;
      }
    })
  }

  @Builder
  private subRowItem(row: SubRow) {
    Row() {
      CoverThumb({ cover: row.sub.cover, thumbSize: 52, radius: 12 })
      Column() {
        Text(row.sub.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.latestTitle)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })
      if (row.newCount > 0) {
        Text(row.newCount > 99 ? '99+' : `${row.newCount}`)
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor(this.accentColor)
          .borderRadius(10)
          .constraintSize({ minWidth: 20 })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.navPathStack.pushPathByName('sourcePage', row.sub.id);
    })
    .bindContextMenu((): void => {
      this.subRowMenu(row);
    }, ResponseType.LongPress)
  }

  @Builder
  private subRowMenu(row: SubRow) {
    Menu() {
      MenuItem({ startIcon: $r('sys.symbol.pin'), content: '置顶' })
        .onClick(() => {
          this.pinToTop(row);
        })
      MenuItem({ startIcon: $r('sys.symbol.trash'), content: '删除订阅' })
        .onClick(() => {
          this.removeSub(row);
        })
    }
  }

  @Builder
  private emptyView() {
    Column() {
      Text('♪')
        .fontSize(42)
        .fontColor($r('app.color.placeholder_color'))
      Text('还没有订阅')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 12 })
      Text('点击右上角「＋」添加 UP 主、收藏夹或合集')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text('BiliRadio')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showAddSheet = true;
        })
        Row() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)
        .margin({ left: 8 })
        .onClick(() => {
          // 更多按钮直达设置页（US4）：播放历史/关于本就是设置页内入口，独立更多页已删除
          this.navPathStack.pushPathByName('settingsPage', '');
        })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 6, bottom: 10 })

      if (this.rowCount === 0) {
        this.emptyView()
      } else {
        // [DISABLED 2026-10] 首页下拉刷新暂时禁用，恢复方式见 PROJECT_NOTES.md「已移除与禁用功能」。
        // 恢复步骤：①取消下方 refreshing 状态与 manualRefresh() 的注释；
        // ②取消 Refresh 包裹层注释并把 List 的 layoutWeight(1) 移回 Refresh 上。
        // Refresh({ refreshing: $$this.refreshing }) {
        Stack() {
          EdgeHint({ text: this.topHint, edge: 'top' })
          EdgeHint({ text: this.bottomHint, edge: 'bottom' })
          List({ space: 8, scroller: this.scroller }) {
            LazyForEach(this.provider, (row: SubRow) => {
              ListItem() {
                this.subRowItem(row)
              }
            }, (row: SubRow) => `${row.sub.id}_${row.latestTitle}_${row.newCount}_${row.sub.cover}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12) + this.navBarHeight })
          // US9：内容不足一屏时 List 默认不开启边缘效果，须显式 alwaysEnabled 才有过冲提示；
          // onWillScroll 在纯边界过冲（偏移量不再变化）时不回调，到边提示改由 reach 回调驱动
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .onWillStartDragging(() => {
            this.dragging = true;
          })
          .onReachStart(() => {
            if (this.dragging) {
              this.topHint = '已经到顶了';
            }
          })
          .onReachEnd(() => {
            this.endOffsetY = this.scroller.currentOffset().yOffset;
            if (this.dragging) {
              this.bottomHint = '已经到底了';
            }
          })
          .onWillScroll((yOffset: number): void => {
            const y: number = this.scroller.currentOffset().yOffset;
            if (yOffset < 0) {
              this.bottomHint = '';
              if (y <= 0) {
                this.topHint = '已经到顶了';
              }
            } else if (yOffset > 0) {
              this.topHint = '';
              if (this.endOffsetY >= 0 && y >= this.endOffsetY) {
                this.bottomHint = '已经到底了';
              }
            }
          })
          .onScrollStop(() => {
            this.topHint = '';
            this.bottomHint = '';
          })
        }
        .width('100%')
        .layoutWeight(1)
        // } // Refresh 包裹层结束
        // .onRefreshing(() => {
        //   this.manualRefresh();
        // })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAddSheet, this.addSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      preferType: SheetType.BOTTOM,
      onWillDismiss: (dismiss: DismissSheetAction) => {
        // 系统返回时若面板处于二级视图（收藏夹/合集与系列），拦截关闭并退回一级视图；
        // 下滑关闭、右上角关闭按钮、点遮罩等其余关闭路径正常放行
        if (dismiss.reason === DismissReason.PRESS_BACK && this.addSheetBack.requestBack()) {
          return;
        }
        dismiss.dismiss();
      }
    })
  }
}
