import { PlayerController } from '../service/PlayerController';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { BiliVideo } from '../model/BiliVideo';
import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { registerHistorySelectExit } from '../service/BackHandler';
import { SelectLogic, LongPressGuard, SweepSession, RowDragSession, EdgeAutoScroller } from '../service/SelectLogic';
import { CoverThumb } from './CoverThumb';
import { SelectCheckbox } from './SelectCheckbox';
import { componentUtils } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

// 拖选等高步长（FR-014）：归并行固定 44 高 + 上下 padding TOKEN_SPACE_10（List space 0），
// 沿 QueueSheet EST_* 文件级常量先例
const HISTORY_SWEEP_STEP: number = Constants.LIST_THUMB_SIZE + 2 * Constants.TOKEN_SPACE_10;
// 拖选边缘带定位用 List 组件 id（checkSweepEdge 与 .id() 同源）
const SWEEP_LIST_ID: string = 'historySheetList';

// 历史归并行（US6 纯展示层派生视图，不落盘）：bvid 聚合为一行，
// latest = 该视频 viewAt 最新的分P 历史（行状态源，点行续播目标）
class HistoryRow {
  bvid: string = '';
  latest: PlayHistoryItem = new PlayHistoryItem();
}

// 播放历史懒加载数据源：LazyForEach 只构建可视区域内的列表项，避免长历史一次性创建全部封面
class HistoryDataSource implements IDataSource {
  private rows: HistoryRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HistoryRow {
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

  setItems(next: HistoryRow[]): void {
    // 入参可能是 @Local 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.rows = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  // 归并行删除通知（US3 FR-009）：LazyForEach 增量删除指定下标；
  // 按 DataChangeListener 契约，先从自身数据删除对应下标再通知监听者
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.rows.length) {
      return;
    }
    this.rows.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

// 播放历史面板（Index L4 独立层，GlassSheet 承载）：US6 按视频归并——一视频一行（主行 videoTitle，
// 副行「相对时间 · 看到Pn · 剩余/已听完」），点行续播最新分P，多选/左滑删除均 bvid 级；
// 点击仅起播不收面板，清空需二次确认；背景由容器提供（sheet_panel_background），关闭经容器动画滑出
@ComponentV2
export struct HistorySheet {
  @Local historyRows: HistoryRow[] = [];
  @Local playHistoryVersion: number = -1;
  // 多选管理：面板关闭/退出多选时清空，交互对齐队列
  @Local selectMode: BoolState = connectBool(Constants.AS_HISTORY_SELECT_MODE, false);
  // 多选集合不可变整体换引用更新：V2 @Local 赋值观测不观测 Set 内部变更
  @Local selectedKeys: Set<string> = new Set<string>();
  @Local pressedKey: string = '';
  // 面板显隐同源：与 GlassSheet/Index 共享同键实例，关闭时驱动多选复位
  @Local showPlayHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  private controller: PlayerController = PlayerController.getInstance();
  private playHistorySource: HistoryDataSource = new HistoryDataSource();
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private historyScroller: ListScroller = new ListScroller();
  // 长按守卫（FR-009）：堵长按后的回退 onClick，统一三处模式
  private longPressGuard: LongPressGuard = new LongPressGuard();
  // 复选框区拖选会话（FR-014）：null=未在拖选；方向性扫选模式按下时锁定，同次拖动不反转
  private sweepSession: SweepSession | null = null;
  // 整行拖选会话（US1）：null=未在拖选；与 sweepSession 单指手势互斥，新建另一方时先清本方
  private rowDrag: RowDragSession | null = null;
  // 边缘自动滚动器（FR-018）：拖选中手指进入列表可视区边缘带时驱动列表滚动续扫
  private edgeScroller: EdgeAutoScroller = new EdgeAutoScroller();
  // 进度广播退订句柄：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
    }, 'HistorySheet');
    registerHistorySelectExit((): void => {
      this.exitSelectModeAnimated();
    });
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
    registerHistorySelectExit(undefined);
  }

  // US6 归并派生（D11）：按 bvid 聚合、viewAt 最新分P 为代表、按代表 viewAt 倒序；
  // 纯展示层派生（FR-015），controller 存储仍分P 粒度，不落盘
  private buildMergedRows(items: PlayHistoryItem[]): HistoryRow[] {
    const rows: HistoryRow[] = [];
    const byBvid: Map<string, HistoryRow> = new Map<string, HistoryRow>();
    for (let i = 0; i < items.length; i++) {
      const item: PlayHistoryItem = items[i];
      let row: HistoryRow | undefined = byBvid.get(item.bvid);
      if (row === undefined) {
        row = new HistoryRow();
        row.bvid = item.bvid;
        row.latest = item;
        byBvid.set(item.bvid, row);
        rows.push(row);
      } else if (item.viewAt > row.latest.viewAt) {
        row.latest = item;
      }
    }
    rows.sort((a: HistoryRow, b: HistoryRow): number => b.latest.viewAt - a.latest.viewAt);
    return rows;
  }

  private syncFrom(c: PlayerController): void {
    if (this.playHistoryVersion !== c.playHistoryVersion) {
      this.playHistoryVersion = c.playHistoryVersion;
      this.historyRows = this.buildMergedRows(c.playHistory);
      this.playHistorySource.setItems(this.historyRows);
    }
  }

  // 面板关闭（遮罩/返回/滑出任一方式）自动退出多选并清选中
  @Monitor('showPlayHistory.value')
  onPlayHistoryVisibilityChanged(): void {
    if (!this.showPlayHistory.value) {
      this.exitSelectModeAnimated();
    }
  }

  // 多选退出即清选中；进入多选即收起已滑出的行（多选态不挂载左滑删除动作）
  @Monitor('selectMode.value')
  onSelectModeChanged(): void {
    if (!this.selectMode.value) {
      this.selectedKeys = new Set<string>();
    } else {
      this.historyScroller.closeAllSwipeActions();
    }
  }

  // viewAt 为秒级时间戳，内部转毫秒做相对时间计算
  private formatPlayedAt(viewAt: number): string {
    const playedAtMs: number = viewAt * 1000;
    const diff: number = Date.now() - playedAtMs;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    if (diff < 7 * 86400000) {
      return `${Math.floor(diff / 86400000)} 天前`;
    }
    const d: Date = new Date(playedAtMs);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const monthStr: string = month < 10 ? `0${month}` : `${month}`;
    const dayStr: string = day < 10 ? `0${day}` : `${day}`;
    return `${monthStr}-${dayStr}`;
  }

  // 剩余时长格式化：mm:ss，分钟数不封顶，与 QueueSheet.formatTime 风格一致
  private formatRemainingSec(remainingSec: number): string {
    const minutes: number = Math.floor(remainingSec / 60);
    const seconds: number = remainingSec % 60;
    const minStr: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const secStr: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minStr}:${secStr}`;
  }

  // 归并行主行标题：纯视频标题（videoTitle，旧数据/空缺回退 title）
  private rowTitle(row: HistoryRow): string {
    return row.latest.videoTitle !== '' ? row.latest.videoTitle : row.latest.title;
  }

  // 归并行副行三段文案（D14，修订：分P 名不展示）：相对时间恒最前；代表分P page>1 时插「看到Pn」；
  // 尾段沿用既有规则（progress===-1 已听完 / 有进度且时长已知 剩 mm:ss / 其余降级省略）。
  // 单P 与仅 P1 历史的多P 无中段，形态与第一轮一致
  private historyMetaText(item: PlayHistoryItem): string {
    const segments: string[] = [this.formatPlayedAt(item.viewAt)];
    if (item.page > 1) {
      segments.push(`看到P${item.page}`);
    }
    if (item.progress === -1) {
      segments.push('已听完');
    } else if (item.progress > 0 && item.duration > 0 && item.duration > item.progress) {
      segments.push(`剩 ${this.formatRemainingSec(item.duration - item.progress)}`);
    }
    return segments.join(' · ');
  }

  // 点归并行：以代表分P（viewAt 最新）走既有历史点播链路起播 + 唤起播放浮层；播放层（L3）物理在
  // 历史面板（L4）之下，面板保持打开，收起面板即见播放页；page/cid/videoTitle/partTitle 透传
  // 保证点播为分P 粒度条目且历史写入链自动携带新字段
  private async replayHistory(item: PlayHistoryItem): Promise<void> {
    try {
      const v: BiliVideo = BiliVideo.create(item.bvid, 0, item.cid, item.title, item.cover, item.duration);
      v.ownerName = item.ownerName;
      v.page = item.page;
      v.videoTitle = item.videoTitle !== '' ? item.videoTitle : item.title;
      v.partTitle = item.partTitle;
      await this.controller.playDownloadedSong(v);
      connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = true;
    } catch (err) {
      const error = err as BusinessError;
      this.getUIContext().getPromptAction().showToast({ message: `播放失败: ${error.message}` });
    }
  }

  // 左滑删除归并行（US6 bvid 级，D11）：一行 = 该视频全部分P 历史——先从 controller 实时历史
  // 展开该 bvid 全部复合键，逐键调既有 removePlayHistoryItem（存储零变化），再做行级补位动画；
  // 点击时实时解析下标，避免 LazyForEach 键复用导致的陈旧索引
  private removeHistoryRow(row: HistoryRow): void {
    if (row.bvid === '') {
      return;
    }
    const pages: number[] = [];
    const history: PlayHistoryItem[] = this.controller.playHistory;
    for (let i = 0; i < history.length; i++) {
      if (history[i].bvid === row.bvid) {
        pages.push(history[i].page);
      }
    }
    if (pages.length === 0) {
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < this.historyRows.length; i++) {
      if (this.historyRows[i].bvid === row.bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    for (let i = 0; i < pages.length; i++) {
      this.controller.removePlayHistoryItem(row.bvid, pages[i]);
    }
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.historyRows.splice(idx, 1);
      this.playHistorySource.notifyDataDelete(idx);
    });
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除，取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveHistoryRow(row: HistoryRow): void {
    this.getUIContext().showAlertDialog({
      title: Constants.DIALOG_DELETE_HISTORY_TITLE,
      message: Constants.DIALOG_DELETE_HISTORY_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.removeHistoryRow(row);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.historyScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.historyScroller.closeAllSwipeActions();
      }
    });
  }

  // 左滑露出的红色垃圾桶删除钮（US1 双触发）：点击进确认弹窗，滑过阈值（onAction）同弹窗
  @Builder
  historyDeleteAction(row: HistoryRow) {
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
        this.confirmRemoveHistoryRow(row);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  private toggleSelect(key: string): void {
    this.selectedKeys = SelectLogic.toggle(this.selectedKeys, key);
  }

  private isAllHistorySelected(): boolean {
    return this.historyRows.length > 0 && this.selectedKeys.size === this.historyRows.length;
  }

  private toggleHistorySelectAll(): void {
    if (this.isAllHistorySelected()) {
      this.selectedKeys = new Set<string>();
    } else {
      const all: Set<string> = new Set<string>();
      for (let i = 0; i < this.historyRows.length; i++) {
        all.add(this.historyRows[i].bvid);
      }
      this.selectedKeys = all;
    }
  }

  private exitSelectMode(): void {
    this.endSweep();
    this.endRowDrag();
    this.selectMode.value = false;
    this.selectedKeys = new Set<string>();
  }

  // 复选框区拖选（FR-014/FR-018）：方向性扫选——按下按 bvid 实时查行号采样选中态锁定加/减扫模式
  // （LazyForEach 不取 index 闭包，删除后键查找天然容忍行号漂移），等高步长换算目标行，
  // 起点→目标区间按锁定模式整体 Set 换引用；手指进入列表边缘带时自动滚动续扫
  private startSweep(bvid: string, event: GestureEvent): void {
    let idx: number = -1;
    for (let i = 0; i < this.historyRows.length; i++) {
      if (this.historyRows[i].bvid === bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    // 整行拖选与扫选单指互斥：扫选起手即作废可能残留的整行会话
    this.rowDrag = null;
    this.sweepSession = new SweepSession();
    this.sweepSession.begin(this.selectedKeys.has(bvid), idx,
      event.fingerList[0].globalY, this.historyScroller.currentOffset().yOffset);
    this.applySweepRange(idx, idx);
  }

  private updateSweep(globalY: number): void {
    if (this.sweepSession === null) {
      return;
    }
    const delta: number = this.sweepSession.delta(globalY, this.historyScroller.currentOffset().yOffset);
    const start: number = this.sweepSession.getStartIndex();
    const target: number = Math.max(0, Math.min(this.historyRows.length - 1,
      start + Math.round(delta / HISTORY_SWEEP_STEP)));
    this.applySweepRange(start, target);
  }

  private applySweepRange(from: number, to: number): void {
    if (this.sweepSession === null) {
      return;
    }
    const lo: number = Math.min(from, to);
    const hi: number = Math.max(from, to);
    const next: Set<string> = new Set<string>(this.selectedKeys);
    let changed: boolean = false;
    for (let i = lo; i <= hi; i++) {
      const bvid: string = this.historyRows[i].bvid;
      if (this.sweepSession.isAddMode()) {
        if (!next.has(bvid)) {
          next.add(bvid);
          changed = true;
        }
      } else if (next.has(bvid)) {
        next.delete(bvid);
        changed = true;
      }
    }
    if (changed) {
      this.selectedKeys = next;
    }
  }

  private endSweep(): void {
    this.edgeScroller.stop();
    this.sweepSession = null;
  }

  // 整行拖选（US1 D2）：长按完成翻转起点行并锁定画笔方向（原未选=加扫、原已选=减扫），
  // 普通态长按同时进多选（翻转即预选）；bvid 实时查行号（LazyForEach 不取 index 闭包，
  // 删除后键查找天然容忍行号漂移）；会话重建即取代可能残留的扫选会话
  private beginRowDrag(bvid: string, event: GestureEvent): void {
    let idx: number = -1;
    for (let i = 0; i < this.historyRows.length; i++) {
      if (this.historyRows[i].bvid === bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    const snapshot: Set<string> = new Set<string>(this.selectedKeys);
    const paintAdd: boolean = !snapshot.has(bvid);
    if (!this.selectMode.value) {
      this.enterSelectMode();
    }
    this.selectedKeys = SelectLogic.toggle(snapshot, bvid);
    this.endSweep();
    this.rowDrag = new RowDragSession(
      (i: number): string => this.rowKeyAt(i),
      (s: Set<string>): void => {
        this.selectedKeys = s;
      }
    );
    this.rowDrag.begin(idx, paintAdd, snapshot,
      event.fingerList[0].globalY, this.historyScroller.currentOffset().yOffset);
  }

  private rowKeyAt(i: number): string {
    if (i < 0 || i >= this.historyRows.length) {
      return '';
    }
    return this.historyRows[i].bvid;
  }

  private updateRowDrag(globalY: number): void {
    if (this.rowDrag === null) {
      return;
    }
    const delta: number = this.rowDrag.delta(globalY, this.historyScroller.currentOffset().yOffset);
    const start: number = this.rowDrag.getStartIndex();
    const target: number = Math.max(0, Math.min(this.historyRows.length - 1,
      start + Math.round(delta / HISTORY_SWEEP_STEP)));
    this.rowDrag.applyAt(target);
  }

  private endRowDrag(): void {
    this.edgeScroller.stop();
    this.rowDrag = null;
  }

  // 拖选/扫选共用边缘带检查：任一会话活跃即驱动对应方向自动滚动
  private checkEdge(globalY: number): void {
    if (this.sweepSession === null && this.rowDrag === null) {
      return;
    }
    const rect: componentUtils.ComponentInfo =
      this.getUIContext().getComponentUtils().getRectangleById(SWEEP_LIST_ID);
    const topY: number = this.getUIContext().px2vp(rect.windowOffset.y);
    const bottomY: number = topY + this.getUIContext().px2vp(rect.size.height);
    if (globalY <= topY + Constants.SELECT_SWEEP_EDGE_ZONE) {
      this.startEdgeScroll(false);
    } else if (globalY >= bottomY - Constants.SELECT_SWEEP_EDGE_ZONE) {
      this.startEdgeScroll(true);
    } else {
      this.edgeScroller.stop();
    }
  }

  // 尽头检测（US1 FR-003）：顶部零偏移、底部 isAtEnd，到尽头停滚清理
  private edgeAtEnd(downward: boolean): boolean {
    if (downward) {
      return this.historyScroller.isAtEnd();
    }
    return this.historyScroller.currentOffset().yOffset <= 0;
  }

  private startEdgeScroll(downward: boolean): void {
    this.edgeScroller.start(this.historyScroller, downward, (): void => {
      if (this.rowDrag !== null) {
        this.updateRowDrag(this.rowDrag.getLastGlobalY());
      } else {
        this.updateSweep(this.sweepSession === null ? 0 : this.sweepSession.getLastGlobalY());
      }
    }, (down: boolean): boolean => this.edgeAtEnd(down));
  }

  // 进出多选统一动画入口（FR-006）：行首勾选框宽度/透明度与头部双态随同一 animateTo 翻转
  // selectMode 驱动，进出互逆；动画中断终态以 selectMode 状态为准
  private enterSelectMode(): void {
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.selectMode.value = true;
    });
  }

  private exitSelectModeAnimated(): void {
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.exitSelectMode();
    });
  }

  // 删除所选归并行（US6 bvid 级，D11）：二次确认后 UI 层把每个选中 bvid 展开为该视频全部分P
  // 复合键（itemKeyOf 合成）调既有 removeSelectedHistory（controller 存储零变化），
  // 先退多选再高→低增量补位动画，交互对齐队列
  private removeSelectedHistory(): void {
    const count: number = this.selectedKeys.size;
    if (count === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: Constants.DIALOG_REMOVE_SELECTED_TITLE,
      message: Constants.DIALOG_REMOVE_SELECTED_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          // 先快照选中集再退多选（退出即清选中）
          const bvids: Set<string> = new Set<string>(this.selectedKeys);
          this.exitSelectModeAnimated();
          const keys: string[] = [];
          const history: PlayHistoryItem[] = this.controller.playHistory;
          for (let i = 0; i < history.length; i++) {
            if (bvids.has(history[i].bvid)) {
              keys.push(BiliVideo.itemKeyOf(history[i].bvid, history[i].page));
            }
          }
          this.controller.removeSelectedHistory(keys);
          this.playHistoryVersion = this.controller.playHistoryVersion;
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            const idxList: number[] = [];
            for (let i = 0; i < this.historyRows.length; i++) {
              if (bvids.has(this.historyRows[i].bvid)) {
                idxList.push(i);
              }
            }
            for (let k = idxList.length - 1; k >= 0; k--) {
              this.historyRows.splice(idxList[k], 1);
              this.playHistorySource.notifyDataDelete(idxList[k]);
            }
            if (this.historyRows.length === 0) {
              this.exitSelectMode();
            }
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  build() {
    Column() {
      // Stack 承载双态条件渲染 + OPACITY 过渡交叉淡化（进出多选同 animateTo 驱动，FR-006）
      Stack() {
        if (!this.selectMode.value) {
          Row() {
            Text('播放历史')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            if (this.historyRows.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.list_checkmark'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(Constants.GLASS_ICON_BTN_SIZE)
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .onClick(() => {
                this.enterSelectMode();
                this.selectedKeys = new Set<string>();
              })
            }
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY)
        } else {
          // 多选操作行（US4，对齐队列）：全选/删除所选(计数)/返回
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_on_circle'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([this.isAllHistorySelected() ? this.accentColor.value : $r('app.color.text_primary')])
            }
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .onClick(() => {
              this.toggleHistorySelectAll();
            })

            Blank()

            Row({ space: Constants.TOKEN_SPACE_XS }) {
              SymbolGlyph($r('sys.symbol.trash_fill'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.danger_red')])
              Text(`${this.selectedKeys.size}`)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.danger_red'))
            }
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .opacity(this.selectedKeys.size > 0 ? 1 : Constants.TOKEN_DISABLED_OPACITY)
            .onClick(() => {
              this.removeSelectedHistory();
            })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .margin({ left: Constants.TOKEN_SPACE_S })
            .onClick(() => {
              this.exitSelectModeAnimated();
            })
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })

      if (this.historyRows.length === 0) {
        Column() {
          Text('暂无播放历史，听歌后会自动记录')
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        Stack() {
          List({ space: 0, scroller: this.historyScroller }) {
            LazyForEach(this.playHistorySource, (row: HistoryRow) => {
              ListItem() {
                Row() {
                  // 勾选框区拖选（FR-014）：外包 Column 承载扫选手势，热区限勾选框列，
                  // Pan 位移阈值内为点按（Checkbox onChange 切勾不冲突），行其余区域维持列表滚动
                  Column() {
                    SelectCheckbox({
                      active: this.selectMode.value,
                      selected: this.selectedKeys.has(row.bvid),
                      gap: Constants.TOKEN_SPACE_L,
                      onChange: (value: boolean): void => {
                        const inSet: boolean = this.selectedKeys.has(row.bvid);
                        if (value !== inSet) {
                          this.toggleSelect(row.bvid);
                        }
                      }
                    })
                  }
                  .gesture(
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical })
                      .onActionStart((event: GestureEvent): void => {
                        if (!this.selectMode.value || event.fingerList.length === 0) {
                          return;
                        }
                        this.startSweep(row.bvid, event);
                      })
                      .onActionUpdate((event: GestureEvent): void => {
                        if (this.sweepSession === null) {
                          return;
                        }
                        const globalY: number = event.fingerList.length > 0
                          ? event.fingerList[0].globalY : this.sweepSession.getLastGlobalY();
                        this.updateSweep(globalY);
                        this.checkEdge(globalY);
                      })
                      .onActionEnd((): void => {
                        this.endSweep();
                      })
                      .onActionCancel((): void => {
                        this.endSweep();
                      })
                  )

                  CoverThumb({ cover: row.latest.cover })

                  Column() {
                    Text(this.rowTitle(row))
                      .fontSize(Constants.TOKEN_FONT_BODY_M)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.historyMetaText(row.latest))
                      .fontSize(Constants.TOKEN_FONT_AUX)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: Constants.TOKEN_SPACE_10 })
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
                .backgroundColor(this.pressedKey === row.bvid ? $r('app.color.item_pressed_background') : Color.Transparent)
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.longPressGuard.reset();
                    this.pressedKey = row.bvid;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => {
                  if (this.longPressGuard.shouldSuppressClick()) {
                    return;
                  }
                  if (this.selectMode.value) {
                    this.toggleSelect(row.bvid);
                  } else {
                    this.replayHistory(row.latest);
                  }
                })
                // 整行拖选（US1 D2）：Sequence(长按→拖) 常挂两态——普通竖滑未长按不触发归列表滚动；
                // 长按翻转起点行进多选/切选，随后拖动区间涂刷（双向画笔）；
                // 长按事件取不到触点时回退纯多选预选（不建会话）
                .gesture(
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture()
                      .onAction((event?: GestureEvent) => {
                        this.longPressGuard.arm();
                        if (event === undefined || event.fingerList.length === 0) {
                          if (!this.selectMode.value) {
                            this.enterSelectMode();
                            this.selectedKeys = new Set<string>([row.bvid]);
                          }
                          return;
                        }
                        this.beginRowDrag(row.bvid, event);
                      }),
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical })
                      .onActionUpdate((event: GestureEvent): void => {
                        if (this.rowDrag === null) {
                          return;
                        }
                        const globalY: number = event.fingerList.length > 0
                          ? event.fingerList[0].globalY : this.rowDrag.getLastGlobalY();
                        this.updateRowDrag(globalY);
                        this.checkEdge(globalY);
                      })
                      .onActionEnd((): void => {
                        this.endRowDrag();
                      })
                      .onActionCancel((): void => {
                        this.endRowDrag();
                      })
                  )
                )
              }
              // 左滑删除（US1 双触发，US6 bvid 级）：SwipeActionItem——点垃圾桶/滑过阈值均进确认弹窗；
              // 多选态不挂载删除动作，退出多选恢复
              .swipeAction(this.selectMode.value ? {} : {
                end: {
                  builder: (): void => {
                    this.historyDeleteAction(row);
                  },
                  onAction: (): void => {
                    this.confirmRemoveHistoryRow(row);
                  }
                }
              })
            }, (row: HistoryRow) => `${row.bvid}_${row.latest.viewAt}`)
            // 容量尾注（US7 FR-017）：列表非空恒显（空态走外层分支不渲染本 List）、不可交互、
            // 多选/删除后仍居队尾；N 动态引用 HISTORY_MAX（上限同源）；contentEndOffset 保证可完整滚出渐隐带
            ListItem() {
              Text(`仅保留最近 ${Constants.HISTORY_MAX} 条播放记录`)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.text_disabled'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_L })
            }
          }
          .width('100%')
          .height('100%')
          .id(SWEEP_LIST_ID)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          // 末行逃出 GlassSheet 底部渐隐带（T018）：与 QueueSheet 同根因，此前无任何 end offset 更严重
          .contentEndOffset(Constants.SHEET_FADE_HEIGHT)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
