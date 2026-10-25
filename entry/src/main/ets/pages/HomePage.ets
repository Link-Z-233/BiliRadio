import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Constants } from '../service/Constants';
import { AppStore } from '../service/AppStore';
import { registerHomeEditBack } from '../service/BackHandler';
import { connectBool, connectNum, connectStr, NumState, StrState } from '../service/V2State';
import { CoverThumb } from '../component/CoverThumb';
import { AddSubscriptionSheet, AddSheetBackHandler } from './AddSubscriptionSheet';
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

  // 拖拽落子静默重排（US5 FR-014）：LazyForEach.onMove 回调内修改数据源无需 DataChangeListener 通知，
  // 额外 onDataMove 会致框架缓存二次移动（UI 回原序、后续拖拽断裂）；越界静默返回
  silentMove(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.rows.length || to >= this.rows.length) {
      return;
    }
    const moved: SubRow = this.rows[from];
    this.rows.splice(from, 1);
    this.rows.splice(to, 0, moved);
  }

  // 置顶移动语义（US8 FR-022）：onDataMove 官方为交换语义（swapped），单发 onDataMove(idx, 0) 被框架
  // 渲染为与首位互换（真机实测脱节根因）；改为 rows 移至 0 + 相邻交换冒泡通知
  // （onDataMove(idx, idx-1)…onDataMove(1, 0)），N-1 步合法交换后框架索引映射与数据排列收敛一致
  // （移动视觉，置顶数量不限）；通知须落在 animateTo 闭包内；拖拽 onMove 落子场景禁用（走 silentMove，FR-014）；
  // idx<=0 幂等静默返回
  moveToFront(idx: number): void {
    if (idx <= 0 || idx >= this.rows.length) {
      return;
    }
    const moved: SubRow = this.rows[idx];
    this.rows.splice(idx, 1);
    this.rows.unshift(moved);
    for (let i = idx; i >= 1; i--) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataMove(i, i - 1);
      }
    }
  }

  // 把手手动拖拽换位（US9 FR-026）：相邻两元素互换与 onDataMove 官方交换语义（swapped）精确匹配，
  // 单发通知即驱动框架邻居补位动画；非相邻/越界静默返回；通知须落在 animateTo 闭包内
  swapNotify(from: number, to: number): void {
    if (Math.abs(from - to) !== 1 || from < 0 || to < 0 || from >= this.rows.length || to >= this.rows.length) {
      return;
    }
    const tmp: SubRow = this.rows[from];
    this.rows[from] = this.rows[to];
    this.rows[to] = tmp;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataMove(from, to);
    }
  }
}

// 主页：订阅源列表（新集徽标 / 长按弹行菜单 / 左滑删除 / 空态）
@ComponentV2
export struct HomePage {
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  // 源页退出（onHidden）经全局键触发重算（US4 返回首页徽标清除）
  @Local homeRefreshTick: NumState = connectNum(Constants.AS_HOME_REFRESH_TICK, 0);
  @Local rowCount: number = 0;
  @Local showAddSheet: boolean = false;
  @Local pressedKey: string = '';
  // 订阅排序编辑态（v0.6-part3 US1）：整页进入拖拽调序，「完成」/系统返回退出
  @Local editMode: boolean = false;
  // 长按行菜单显隐键（US5）：当前弹菜单行的 sub.id，空串表示无菜单
  @Local menuKey: string = '';
  // 把手手动拖拽态（US9 FR-026）：draggingKey 被拖行 sub.id（空串无拖拽）、dragOffsetY/dragBaseline
  // 为 translate 绑定所需响应式量（offsetY-按压起算累积纵偏移 GestureEvent.offsetY、
  // baseline-当前槽位偏移基准，swap 换位随方向累进阈值，两者差即被拖行位移）
  @Local draggingKey: string = '';
  @Local dragOffsetY: number = 0;
  @Local dragBaseline: number = 0;
  private dragActive: boolean = false;
  private dragFromIndex: number = -1;
  // 编辑态挂起的 rebuild 标记（US1）：编辑期间 rebuild 置脏，退出编辑态后补跑一次
  private rebuildPending: boolean = false;
  // 添加订阅面板的系统返回拦截句柄（onWillDismiss PRESS_BACK 时经其询问面板是否消费）
  private addSheetBack: AddSheetBackHandler = new AddSheetBackHandler();
  private subs: Subscription[] = [];
  private provider: SubDataSource = new SubDataSource();
  private refreshingNow: boolean = false;
  // 静默刷新失败 toast 去重窗基准（SILENT_REFRESH_FAIL_DEDUP_MS 内只弹一次）
  private lastSilentFailToastAt: number = 0;
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private scroller: ListScroller = new ListScroller();
  @Param navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.subs = SubscriptionStore.loadSubscriptions();
    this.rebuild();
    this.silentRefresh();
    // 编辑态系统返回消费句柄（US1）：句柄内自判编辑态，非编辑态返回 false 放行后续层
    registerHomeEditBack((): boolean => {
      if (this.editMode) {
        this.exitEditMode();
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    registerHomeEditBack(undefined);
  }

  private rebuild(): void {
    // 编辑态不重建列表（拖拽中数据被换走会打断排序），置脏挂起由 exitEditMode 补跑
    if (this.editMode) {
      this.rebuildPending = true;
      return;
    }
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

  private async silentRefresh(): Promise<void> {
    if (this.refreshingNow) {
      return;
    }
    // CD 门读 AppStore，须等 preferences 就绪（aboutToAppear 早于 PlayerController.init 的异步完成）
    await AppStore.init();
    const elapsed: number = Date.now() - AppStore.getNumber(Constants.KEY_LAST_SILENT_REFRESH_AT, 0);
    // D9：时钟回拨（elapsed 为负）视为 CD 过期放行
    if (elapsed >= 0 && elapsed < Constants.HOME_SILENT_REFRESH_CD_MS) {
      return;
    }
    this.refreshingNow = true;
    let failCount: number = 0;
    SubscriptionStore.refreshAll(this.subs, false, (sub: Subscription, ok: boolean): void => {
      if (!ok) {
        failCount++;
      }
      this.persistRefreshedSub(sub, ok);
    }).then((): void => {
      this.finishSilentRefresh(failCount);
    }).catch((): void => {
      this.finishSilentRefresh(failCount);
    });
  }

  // 静默刷新收尾（v0.5-part4 US3）：写 CD 时间戳 + 失败源聚合 toast（去重窗内只弹一次；CD 跳过路径零提示）
  private finishSilentRefresh(failCount: number): void {
    this.refreshingNow = false;
    AppStore.putNumber(Constants.KEY_LAST_SILENT_REFRESH_AT, Date.now());
    if (failCount > 0) {
      const now: number = Date.now();
      if (now - this.lastSilentFailToastAt >= Constants.SILENT_REFRESH_FAIL_DEDUP_MS) {
        this.lastSilentFailToastAt = now;
        this.getUIContext().getPromptAction().showToast({
          message: Constants.TOAST_SILENT_REFRESH_FAIL.replace('N', `${failCount}`)
        });
      }
    }
  }

  // 进出编辑态统一 animateTo 驱动（US7 FR-021）：与源详情页多选进出同构
  // （TOKEN_SELECT_ANIM_MS + EaseOut，transition 不带自带 animation 参数、参数由 animateTo 供给）
  private enterEditMode(): void {
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.editMode = true;
    });
  }

  // 统一退出（US1）：「完成」按钮与系统返回共用；挂起的 rebuild 补跑置于 animateTo 闭包外
  // （reload 不打断旧分支节点的消失动画）；把手手动拖拽态随编辑态退出中止清零（FR-026）
  private exitEditMode(): void {
    if (!this.editMode) {
      return;
    }
    this.dragActive = false;
    this.draggingKey = '';
    this.dragOffsetY = 0;
    this.dragBaseline = 0;
    this.dragFromIndex = -1;
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.editMode = false;
    });
    if (this.rebuildPending) {
      this.rebuildPending = false;
      this.rebuild();
    }
  }

  // 拖拽落子（US5 FR-014 / US8 FR-023）：编辑态闸（onMove 恒绑单 List，非编辑态落子不改序不落盘，
  // 拖动视觉回弹为已接受风险）；把手手动拖拽进行中系统落子拒收（FR-026 双路径互斥闸）；
  // subs 重排 → sortOrder 全量归一化 0..n-1 → 落盘 → provider 静默同步
  // （onMove 回调内修改数据源无需通知 listener，该路径禁调 onDataMove）
  private applyDragOrder(from: number, to: number): void {
    if (!this.editMode || this.draggingKey !== '') {
      return;
    }
    if (from === to || from < 0 || to < 0 || from >= this.subs.length || to >= this.subs.length) {
      return;
    }
    const moved: Subscription = this.subs[from];
    this.subs.splice(from, 1);
    this.subs.splice(to, 0, moved);
    for (let i = 0; i < this.subs.length; i++) {
      this.subs[i].sortOrder = i;
    }
    SubscriptionStore.saveSubscriptions(this.subs);
    this.provider.silentMove(from, to);
  }

  // 把手拖拽换位（US9 FR-026）：累积偏移每跨 TOKEN_DRAG_SWAP_DISTANCE 与目标方向相邻行交换
  // （subs splice 互换 + provider.swapNotify 单发 onDataMove，包 animateTo 驱动邻居补位），
  // dragBaseline 随交换按方向累进（translate 相对量归零基准随槽位走）；循环守卫 10 次兜底异常位移
  private processDragSwap(currentOffset: number): void {
    let guard: number = 0;
    while (guard < 10) {
      guard++;
      const rel: number = currentOffset - this.dragBaseline;
      const dir: number = rel >= 0 ? 1 : -1;
      if (Math.abs(rel) < Constants.TOKEN_DRAG_SWAP_DISTANCE) {
        break;
      }
      const target: number = this.dragFromIndex + dir;
      if (target < 0 || target >= this.subs.length) {
        break;
      }
      const from: number = this.dragFromIndex;
      const nextBaseline: number = this.dragBaseline + dir * Constants.TOKEN_DRAG_SWAP_DISTANCE;
      this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
        const tmp: Subscription = this.subs[from];
        this.subs[from] = this.subs[target];
        this.subs[target] = tmp;
        this.dragFromIndex = target;
        this.dragBaseline = nextBaseline;
        this.provider.swapNotify(from, target);
      });
    }
  }

  // 把手拖拽松手归位（US9 FR-026）：animateTo 内 dragOffsetY→dragBaseline（相对位移归零平滑落槽），
  // onFinish 经 dragActive 守卫清态（落槽动画窗口内重启拖拽不误清）；sortOrder 归一化 + 落盘
  private settleDrag(): void {
    if (this.draggingKey === '') {
      return;
    }
    this.getUIContext().animateTo({
      duration: Constants.TOKEN_SELECT_ANIM_MS,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        if (!this.dragActive) {
          this.draggingKey = '';
          this.dragOffsetY = 0;
          this.dragBaseline = 0;
          this.dragFromIndex = -1;
        }
      }
    }, (): void => {
      this.dragOffsetY = this.dragBaseline;
    });
    for (let i = 0; i < this.subs.length; i++) {
      this.subs[i].sortOrder = i;
    }
    SubscriptionStore.saveSubscriptions(this.subs);
  }

  // 置顶（US5 FR-013 / US8 FR-022）：移除该 sub → unshift 首位 → sortOrder 全量归一化 → 落盘 →
  // animateTo 内 provider.moveToFront（相邻交换冒泡 onDataMove）驱动行移动补位动画；已在首位幂等无变化；
  // 不 rebuild（reload 全量重建会打断移动动画）
  private pinToTop(row: SubRow): void {
    const subId: string = row.sub.id;
    let idx: number = -1;
    for (let i = 0; i < this.subs.length; i++) {
      if (this.subs[i].id === subId) {
        idx = i;
        break;
      }
    }
    if (idx <= 0) {
      return;
    }
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      const moved: Subscription = this.subs[idx];
      this.subs.splice(idx, 1);
      this.subs.unshift(moved);
      for (let i = 0; i < this.subs.length; i++) {
        this.subs[i].sortOrder = i;
      }
      SubscriptionStore.saveSubscriptions(this.subs);
      this.provider.moveToFront(idx);
    });
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
    this.getUIContext().showAlertDialog({
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
        this.getUIContext().getPromptAction().showToast({ message: '已订阅该源' });
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
      this.getUIContext().getPromptAction().showToast({ message: `刷新节目失败: ${err.message}` });
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

  // 行内容内核（v0.6-part3 US1）：封面 + 文字列 + 新集徽标，layoutWeight(1) 给行首恒挂载把手真实让位
  @Builder
  private subRowCore(row: SubRow) {
    Row() {
      CoverThumb({ cover: row.sub.cover, thumbSize: 52, radius: 12 })
      Column() {
        // 订阅列表条目剥「合集·」前缀（US4 FR-011 展示层，与详情页/导航标题同源）
        Text(row.sub.displayTitle())
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
          .textAlign(TextAlign.Center)
          .backgroundColor(this.accentColor.value)
          .borderRadius(Constants.TOKEN_RADIUS_10)
          .constraintSize({ minWidth: 20 })
          .padding({ left: Constants.TOKEN_SPACE_6, right: Constants.TOKEN_SPACE_6, top: Constants.TOKEN_SPACE_XXS, bottom: Constants.TOKEN_SPACE_XXS })
      }
    }
    .layoutWeight(1)
  }

  // 长按行菜单（US5 FR-012）：置顶/排序/删除三项，菜单项点击后置 menuKey 关菜单
  @Builder
  private subRowMenuBuilder(row: SubRow) {
    Menu() {
      MenuItem({ content: Constants.MENU_SUB_PIN_TO_TOP })
        .onClick(() => {
          this.menuKey = '';
          this.pinToTop(row);
        })
      MenuItem({ content: Constants.MENU_SUB_REORDER })
        .onClick(() => {
          this.menuKey = '';
          this.enterEditMode();
        })
      MenuItem({ content: Constants.MENU_SUB_DELETE })
        .onClick(() => {
          this.menuKey = '';
          this.confirmRemoveSub(row);
        })
    }
  }

  @Builder
  private subRowItem(row: SubRow) {
    Row() {
      // 恒挂载拖拽把手（US8 FR-023，SelectCheckbox 同构）：宽度 0↔把手宽 + 透明度 0↔1 随 editMode
      // 联动（动画由 enter/exitEditMode 既有 animateTo 驱动状态翻转，此处只做属性绑定）；
      // ArkUI width 是内容宽、padding 在外另加（bugfix 1）：正常态 width 0 + padding 12 实占 12vp 残带
      // （仅 pan 认领、长按漏给 List 系统拖拽），padding 须随 width 条件归零才是真零宽；
      // 编辑态 pad-L 12 + 内容 38 = 总 50，图标在行左缘↔内容起点间居中（US9 FR-025）；
      // 把手即按即拖（US9 FR-026）：Parallel 并行组——pan（移动识别即进手动拖拽，onActionStart
      // 移动触发非按下）+ 空长按认领（子组件同型手势优先于 List 内建，阻断把手长按触发系统拖拽，
      // 把手 pan-only）；并行仲裁 pan 不因长按认领出局，按住后再移动仍可拖
      Row() {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(Constants.TOKEN_FONT_TITLE_L)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(this.editMode ? Constants.TOKEN_DRAG_HANDLE_W : 0)
      .opacity(this.editMode ? 1 : 0)
      .padding({ left: this.editMode ? Constants.TOKEN_SPACE_M : 0 })
      .justifyContent(FlexAlign.Center)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart((e: GestureEvent): void => {
              if (!this.editMode || this.dragActive) {
                return;
              }
              let idx: number = -1;
              for (let i = 0; i < this.subs.length; i++) {
                if (this.subs[i].id === row.sub.id) {
                  idx = i;
                  break;
                }
              }
              if (idx < 0) {
                return;
              }
              this.dragActive = true;
              this.draggingKey = row.sub.id;
              this.dragOffsetY = e.offsetY;
              this.dragBaseline = e.offsetY;
              this.dragFromIndex = idx;
            })
            .onActionUpdate((e: GestureEvent): void => {
              if (this.draggingKey !== row.sub.id) {
                return;
              }
              this.dragOffsetY = e.offsetY;
              this.processDragSwap(e.offsetY);
            })
            .onActionEnd((): void => {
              if (this.draggingKey !== row.sub.id) {
                return;
              }
              this.dragActive = false;
              this.settleDrag();
            })
            .onActionCancel((): void => {
              if (this.draggingKey !== row.sub.id) {
                return;
              }
              this.dragActive = false;
              this.settleDrag();
            }),
          LongPressGesture()
            .onAction((): void => {
            })
        )
      )
      // 内容包装（US9 FR-026）：layoutWeight 让位 + 编辑态禁行级交互（触摸穿透保系统拖拽/按压链，
      // FR-024 三版语义随迁），正常态交互（onClick 闸/长按菜单/bindMenu）全部承载于此；
      // 行 padding 落此不落根 Row（bugfix 1）：正常态包装盒覆盖整卡，长按手势全域认领——
      // padding 带留在无手势的根节点时 List 恒绑 onMove 的内建长按在未认领区胜出，
      // 非编辑态卡片边缘长按直进系统拖拽；把手 pad-L + 包装 pad-L 恒 12，两种模式内容起点（12/50）不变
      Row() {
        this.subRowCore(row)
      }
      .layoutWeight(1)
      .enabled(!this.editMode)
      .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
      .onClick(() => {
        // menuKey 先置位拦截长按弹菜单尾随 Up 误触导航（D22 二版补丁，随三版回退保留无害）；编辑态早退兜底
        if (this.editMode || this.menuKey !== '') {
          return;
        }
        this.navPathStack.pushPathByName('sourcePage', row.sub.id);
      })
      // 长按达成即弹行菜单（US6 FR-016）：按压中触发（文件管理风格，不待抬手），行同步缩放强调；编辑态不弹菜单（editMode 闸）
      .gesture(
        LongPressGesture()
          .onAction((): void => {
            if (this.editMode) {
              return;
            }
            this.menuKey = row.sub.id;
          })
      )
      // 受控菜单（isShow 按行 id 单行显隐）；从行上方展开（FR-019）；onDisappear 复位防点外关闭后状态残留
      .bindMenu(this.menuKey === row.sub.id, this.subRowMenuBuilder(row), {
        placement: Placement.Top,
        onDisappear: (): void => {
          this.menuKey = '';
        }
      })
    }
    .width('100%')
    .borderRadius(Constants.TOKEN_RADIUS_14)
    .backgroundColor(this.pressedKey === row.sub.id ? $r('app.color.item_pressed_background') : $r('app.color.card_background'))
    // 长按弹菜单时命中行缩放强调（US6 FR-016），菜单关闭恢复 1 经同一属性动画平滑过渡
    .scale({
      x: this.menuKey === row.sub.id ? Constants.TOKEN_ROW_MENU_SCALE : 1,
      y: this.menuKey === row.sub.id ? Constants.TOKEN_ROW_MENU_SCALE : 1
    })
    .animation({ duration: Constants.TOKEN_ROW_MENU_SCALE_ANIM_MS })
    .shadow(this.pressedKey === row.sub.id ? {
      radius: Constants.TOKEN_FLOATING_SHADOW_RADIUS,
      color: $r('app.color.shadow_ball'),
      offsetX: 0,
      offsetY: Constants.TOKEN_FLOATING_SHADOW_OFFSET_Y
    } : undefined)
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
        if (this.editMode) {
          Text('调整排序')
            .fontSize(Constants.TOKEN_FONT_TITLE_L)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .transition(TransitionEffect.OPACITY)
        } else {
          Text('BiliRadio')
            .fontSize(Constants.TOKEN_FONT_TITLE_L)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .transition(TransitionEffect.OPACITY)
        }
        Blank()
        if (this.editMode) {
          // 「完成」退出编辑态（US1）：替换「＋/⋯」区
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.fg_on_dark')])
          }
          .width(Constants.TOKEN_ICON_BTN)
          .height(Constants.TOKEN_ICON_BTN)
          .borderRadius(Constants.TOKEN_RADIUS_XL)
          .backgroundColor(this.accentColor.value)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.exitEditMode();
          })
          .transition(TransitionEffect.OPACITY)
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(Constants.TOKEN_ICON_BTN)
          .height(Constants.TOKEN_ICON_BTN)
          .borderRadius(Constants.TOKEN_RADIUS_XL)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showAddSheet = true;
          })
          .transition(TransitionEffect.OPACITY)
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(Constants.TOKEN_ICON_BTN)
          .height(Constants.TOKEN_ICON_BTN)
          .borderRadius(Constants.TOKEN_RADIUS_XL)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .margin({ left: Constants.TOKEN_SPACE_S })
          .onClick(() => {
            // 更多按钮直达设置层（US4）：播放历史/关于本就是设置页内入口，独立更多页已删除
            connectBool(Constants.AS_SHOW_SETTINGS_PAGE, false).value = true;
          })
          .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_6, bottom: Constants.TOKEN_SPACE_10 })

      if (this.rowCount === 0) {
        this.emptyView()
      } else {
        // 单 List 恒绑 onMove（US8 FR-023）：行节点恒存续是行首把手宽度补间（恒挂载让位）的前提，
        // 双 List 分支替换会销毁重建行节点致补间无从发生；非编辑态落子由 applyDragOrder 编辑态闸拒绝
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
                // 按压链恒挂 ListItem（FR-024 三版）：编辑态行 enabled(false) 触摸穿透至此保按压反馈，
                // onTouch 纯监听不参与手势仲裁不阻塞系统拖拽；正常态触摸命中行冒泡至此不断；收不到穿透触摸则回退一版（放弃编辑态按压反馈）
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.pressedKey = row.sub.id;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                // 把手手动拖拽位移（US9 FR-026）：挂 ListItem 而非根 Row——根 Row 的 .animation()
                // 会给 translate 平滑滞后（拖拽跟手变橡皮筋）；zIndex 抬升被拖行盖过邻行
                .translate({ y: this.draggingKey === row.sub.id ? this.dragOffsetY - this.dragBaseline : 0 })
                .zIndex(this.draggingKey === row.sub.id ? 1 : 0)
            }, (row: SubRow) => `${row.sub.id}_${row.latestTitle}_${row.newCount}_${row.sub.cover}`)
              .onMove((from: number, to: number): void => {
                this.applyDragOrder(from, to);
              })
          }
          .width('100%')
          .height('100%')
          .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_XS })
          // MiniPlayer 悬浮化（FR-015）：底部 padding 是内容裁剪边界（内容不能从胶囊下划过的根因），
          // 改挂 contentEndOffset——视口延伸至屏底、内容滚动时从胶囊下方穿过（毛玻璃透出），
          // 滚到底最后一条完整露出在胶囊上方
          .contentEndOffset(Constants.MINI_PLAYER_CLEARANCE + this.navBarHeight.value)
          // US9：内容不足一屏时 List 默认不开启边缘效果，须显式 alwaysEnabled 才有过冲物理回弹
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .width('100%')
        .layoutWeight(1)
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
