import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Constants } from '../service/Constants';
import { connectBool, connectNum, connectStr, NumState, StrState } from '../service/V2State';
import { CoverThumb } from '../component/CoverThumb';
import { AddSubscriptionSheet, AddSheetBackHandler } from './AddSubscriptionSheet';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

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

  // 删除单行（US2）：notifyDataDelete 通知 LazyForEach 走补位动画；越界静默返回
  delete(index: number): void {
    if (index < 0 || index >= this.rows.length) {
      return;
    }
    this.rows.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

// 主页：订阅源列表（新集徽标 / 长按置顶删除 / 空态）；下拉刷新已注释禁用（[DISABLED 2026-10]，见 PROJECT_NOTES.md）
@ComponentV2
export struct HomePage {
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  // 源页退出（onHidden）经全局键触发重算（US4 返回首页徽标清除）
  @Local homeRefreshTick: NumState = connectNum(Constants.AS_HOME_REFRESH_TICK, 0);
  // [DISABLED 2026-10] 首页下拉刷新暂时禁用，恢复方式见 PROJECT_NOTES.md「已移除与禁用功能」
  // @Local refreshing: boolean = false;
  @Local rowCount: number = 0;
  @Local showAddSheet: boolean = false;
  @Local pressedKey: string = '';
  // 添加订阅面板的系统返回拦截句柄（onWillDismiss PRESS_BACK 时经其询问面板是否消费）
  private addSheetBack: AddSheetBackHandler = new AddSheetBackHandler();
  private subs: Subscription[] = [];
  private provider: SubDataSource = new SubDataSource();
  private refreshingNow: boolean = false;
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private scroller: ListScroller = new ListScroller();
  @Param navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.subs = SubscriptionStore.loadSubscriptions();
    this.rebuild();
    this.silentRefresh();
  }

  private rebuild(): void {
    this.subs = SubscriptionStore.loadSubscriptions();
    this.subs.sort((a: Subscription, b: Subscription): number => a.sortOrder - b.sortOrder);
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

  // US4：源页退出经全局键触发（onPop 对无参 pop() 永不回调，见 SourcePage.onHidden 注释）
  @Monitor('homeRefreshTick.value')
  onHomeRefreshTick(): void {
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

  // 删除订阅（US2 健壮化）：按 sub.id 定位（替代引用匹配，消除闭包陈旧引用静默早退），
  // animateTo 闭包内经 provider.delete 补位动画，闭包内不 rebuild；保存后校验持久化结果
  private removeSub(row: SubRow): void {
    const subId: string = row.sub.id;
    let idx: number = -1;
    for (let i = 0; i < this.subs.length; i++) {
      if (this.subs[i].id === subId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.provider.delete(idx);
      this.subs.splice(idx, 1);
      SubscriptionStore.saveSubscriptions(this.subs);
      SubscriptionStore.removeEpisodes(subId);
      this.rowCount = this.subs.length;
      if (SubscriptionStore.subExists(subId)) {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG,
          'removeSub persist check failed, sub still on disk: %{public}s', subId);
      }
    });
  }

  // 删除订阅确认（US1/US2 双入口）：左滑垃圾桶/长按菜单共用同弹窗，
  // 取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveSub(row: SubRow): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_SUB_TITLE,
      message: Constants.DIALOG_DELETE_SUB_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.removeSub(row);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.scroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.scroller.closeAllSwipeActions();
      }
    });
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
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.latestTitle)
          .fontSize(Constants.TOKEN_FONT_BODY)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_S })
      if (row.newCount > 0) {
        Text(row.newCount > 99 ? '99+' : `${row.newCount}`)
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor($r('app.color.fg_on_dark'))
          .backgroundColor(this.accentColor.value)
          .borderRadius(Constants.TOKEN_RADIUS_10)
          .constraintSize({ minWidth: 20 })
          .padding({ left: Constants.TOKEN_SPACE_6, right: Constants.TOKEN_SPACE_6, top: Constants.TOKEN_SPACE_XXS, bottom: Constants.TOKEN_SPACE_XXS })
      }
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
    .borderRadius(Constants.TOKEN_RADIUS_14)
    .backgroundColor(this.pressedKey === row.sub.id ? $r('app.color.item_pressed_background') : $r('app.color.card_background'))
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.pressedKey = row.sub.id;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
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
          this.confirmRemoveSub(row);
        })
    }
  }

  @Builder
  private subDeleteAction(row: SubRow) {
    Column() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(Constants.SWIPE_DELETE_ICON_FONT)
          .fontColor([$r('app.color.fg_on_dark')])
          .fontWeight(FontWeight.Bold)
      }
      .width(Constants.SWIPE_DELETE_BTN_SIZE)
      .height(Constants.SWIPE_DELETE_BTN_SIZE)
      .backgroundColor($r('app.color.danger_red'))
      .borderRadius(Constants.SWIPE_DELETE_BTN_RADIUS)
      .onClick(() => {
        this.confirmRemoveSub(row);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  @Builder
  private emptyView() {
    Column() {
      SymbolGlyph($r('sys.symbol.headphones'))
        .fontSize(42)
        .fontColor([$r('app.color.placeholder_color')])
      Text('还没有订阅')
        .fontSize(Constants.TOKEN_FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: Constants.TOKEN_SPACE_M })
      Text('点击右上角「＋」添加 UP 主、收藏夹或合集')
        .fontSize(Constants.TOKEN_FONT_BODY)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: Constants.TOKEN_SPACE_6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text('BiliRadio')
          .fontSize(Constants.TOKEN_FONT_TITLE_L)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(Constants.TOKEN_FONT_TITLE_L)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(Constants.TOKEN_RADIUS_XL)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showAddSheet = true;
        })
        Row() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(Constants.TOKEN_FONT_TITLE_L)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(Constants.TOKEN_RADIUS_XL)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)
        .margin({ left: Constants.TOKEN_SPACE_S })
        .onClick(() => {
          // 更多按钮直达设置层（US4）：播放历史/关于本就是设置页内入口，独立更多页已删除
          connectBool(Constants.AS_SHOW_SETTINGS_PAGE, false).value = true;
        })
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_6, bottom: Constants.TOKEN_SPACE_10 })

      if (this.rowCount === 0) {
        this.emptyView()
      } else {
        // [DISABLED 2026-10] 首页下拉刷新暂时禁用，恢复方式见 PROJECT_NOTES.md「已移除与禁用功能」。
        // 恢复步骤：①取消下方 refreshing 状态与 manualRefresh() 的注释；
        // ②取消 Refresh 包裹层注释并把 List 的 layoutWeight(1) 移回 Refresh 上。
        // Refresh({ refreshing: $$this.refreshing }) {
        Stack() {
          List({ space: Constants.TOKEN_SPACE_S, scroller: this.scroller }) {
            LazyForEach(this.provider, (row: SubRow) => {
              ListItem() {
                this.subRowItem(row)
              }
               .swipeAction({
                 end: {
                   builder: (): void => {
                     this.subDeleteAction(row);
                   },
                   onAction: (): void => {
                     this.confirmRemoveSub(row);
                   }
                 }
               })
            }, (row: SubRow) => `${row.sub.id}_${row.latestTitle}_${row.newCount}_${row.sub.cover}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_XS, bottom: Constants.MINI_PLAYER_CLEARANCE + this.navBarHeight.value })
          // US9：内容不足一屏时 List 默认不开启边缘效果，须显式 alwaysEnabled 才有过冲物理回弹
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
    .bindSheet(this.showAddSheet, this.addSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showAddSheet = false;
      },
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
