import { PlayerController } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';
import { PlayHistoryItem } from '../model/PlayHistoryItem';


import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { closeBothLayersNow, registerQueueSelectExit } from '../service/BackHandler';
import { SelectLogic, LongPressGuard, SweepSession, EdgeAutoScroller } from '../service/SelectLogic';
import { CoverThumb } from './CoverThumb';
import { SelectCheckbox } from './SelectCheckbox';
import { promptAction, componentUtils } from '@kit.ArkUI';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 列表上下边缘渐变模糊半径；sheet 底部安全留白
const EDGE_BLUR_RADIUS: number = 48;
const LIST_BOTTOM_GAP: number = 12;
// 条目估算高度（拖选位移换算用）：单条目整行沿用 68（封面 LIST_THUMB_SIZE + 上下各 TOKEN_SPACE_M 内边距）；
// 组头行 ≈ 封面 LIST_THUMB_SIZE + 上 TOKEN_SPACE_M 下 TOKEN_SPACE_S；分P 窄行 ≈ 字号 14 行高 + 上下各 8
// ponytail: 估算偏保守只影响拖选效率不影响正确性；需精确时改按 onAreaChange 逐条目回填实际高度
const EST_FULL_ROW_HEIGHT: number = Constants.LIST_THUMB_SIZE + 2 * Constants.TOKEN_SPACE_M;
const EST_GROUP_HEADER_HEIGHT: number = Constants.LIST_THUMB_SIZE + Constants.TOKEN_SPACE_M + Constants.TOKEN_SPACE_S;
const EST_PART_ROW_HEIGHT: number = 36;
// 拖选边缘带定位用 List 组件 id（checkSweepEdge 与 .id() 同源）
const SWEEP_LIST_ID: string = 'queueSheetList';

// 展示条目（plan D1）：队列渲染与交互的最小单位，随 playlistVersion 整体重建、不落盘。
// 组条目 = 相邻（≥2）同 bvid 且页号≥1 的分P（头行+分P 窄行同属一个 ListItem、一体滑动）；
// 单条目 = 单P/孤立分P/占位整行。组内扁平下标 = startIndex + 组内偏移
class QueueEntry {
  isGroup: boolean = false;
  videos: BiliVideo[] = [];
  startIndex: number = 0;
  key: string = '';
  estHeight: number = 0;
}

// 由扁平分P 队列 + PlayerController 条目游程构建展示条目（游程与条目一一对应）
function buildQueueEntries(flat: BiliVideo[], groups: number[][]): QueueEntry[] {
  const entries: QueueEntry[] = [];
  // 同 bvid 多组并存（插播拆组等路径）时附加序号消歧，保证条目键全表唯一（LazyForEach 键约束）
  const groupSeen: Map<string, number> = new Map<string, number>();
  for (let g = 0; g < groups.length; g++) {
    const run: number[] = groups[g];
    const entry: QueueEntry = new QueueEntry();
    entry.startIndex = run[0];
    for (let i = 0; i < run.length; i++) {
      entry.videos.push(flat[run[i]]);
    }
    if (run.length >= 2) {
      const bvid: string = entry.videos[0].bvid;
      const seen: number = groupSeen.get(bvid) ?? 0;
      groupSeen.set(bvid, seen + 1);
      entry.isGroup = true;
      entry.key = seen === 0 ? `g:${bvid}` : `g:${bvid}#${seen + 1}`;
      entry.estHeight = EST_GROUP_HEADER_HEIGHT + run.length * EST_PART_ROW_HEIGHT;
    } else {
      const v: BiliVideo = entry.videos[0];
      entry.isGroup = false;
      entry.key = `s:${BiliVideo.itemKeyOf(v.bvid, v.page)}`;
      entry.estHeight = EST_FULL_ROW_HEIGHT;
    }
    entries.push(entry);
  }
  return entries;
}

// 条目内容一致性校验（diff 辅助）：键相同但 videos 变化（组裁剪/组内增长）不算纯删除
function sameEntryVideos(a: QueueEntry, b: QueueEntry): boolean {
  if (a.videos.length !== b.videos.length) {
    return false;
  }
  for (let i = 0; i < a.videos.length; i++) {
    if (a.videos[i] !== b.videos[i]) {
      return false;
    }
  }
  return true;
}

// 队列条目 diff（plan D2）：next 可由 old 纯删除得到时返回被删下标（升序），
// 否则（增长/重排/组分裂/组缩减）返回 undefined，调用方走整表 reload；相等返回空数组（no-op）
function diffRemovedEntries(old: QueueEntry[], next: QueueEntry[]): number[] | undefined {
  const removed: number[] = [];
  let j: number = 0;
  for (let i = 0; i < old.length; i++) {
    if (j < next.length && old[i].key === next[j].key && sameEntryVideos(old[i], next[j])) {
      j++;
    } else {
      removed.push(i);
    }
  }
  if (j !== next.length) {
    return undefined;
  }
  return removed;
}

// 播放列表懒加载数据源：配合 LazyForEach 只构建可视区域内的列表条目，
// 避免长歌单一次性创建全部条目（每项都要下载并解码一张封面，会瞬间打满内存）
class PlaylistDataSource implements IDataSource {
  private entries: QueueEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): QueueEntry {
    return this.entries[index];
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

  setItems(next: QueueEntry[]): void {
    this.entries = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  // 条目级增量删除通知：先裁自身再广播，供纯删除路径从高索引向低索引逐项刷新，
  // 避免整表 reload 造成的封面闪烁
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.entries.length) {
      return;
    }
    this.entries.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }

  // 条目变更通知：LazyForEach 删除后不重绑部分缓存条目生成器闭包里的 index（过期下标对已缩短
  // 数组越界即 jscrash），增量删除后从最低删除位到末尾逐项 onDataChange 强制重绑，使 index 恢复可信
  notifyDataChange(index: number): void {
    if (index < 0 || index >= this.entries.length) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}

// 播放队列抽屉：单行图标头部（清除已播/多选/清空）、左滑条目删除、多选批量移除
@ComponentV2
export struct QueueSheet {
  @Local entries: QueueEntry[] = [];
  @Local currentIndex: number = -1;
  @Local currentItemEnded: boolean = false;
  @Local playlistVersion: number = -1;
  @Local selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
  // 多选集合不可变整体换引用更新：V2 @Local 赋值观测不观测 Set 内部变更
  @Local selectedKeys: Set<string> = new Set<string>();
  @Local pressedKey: string = '';
  // 面板显隐同源（v0.3 US7）：与 GlassSheet/Index 共享同键实例，关闭时驱动多选复位
  @Local showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);

  @Local pageHeight: number = 0;
  @Local headerHeight: number = 72;

  // 主题色（T016）：强调色运行时跟随外观设置（Appearance 写入 AppStorage），衍生色一律经 hexWithAlpha
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local isWideScreen: BoolState = connectBool(Constants.AS_IS_WIDE_SCREEN, false);
  private controller: PlayerController = PlayerController.getInstance();

  private textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  private textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }

  private textDisabled(): Resource {
    return $r('app.color.text_disabled');
  }

  private listSource: PlaylistDataSource = new PlaylistDataSource();
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private listScroller: ListScroller = new ListScroller();
  // 拖选起始条目下标（长按进入多选时记录，Pan 拖选换算起点）
  private dragStartEntryIndex: number = -1;
  // 长按守卫（FR-009）：堵 Sequence 组失败后的回退 onClick 取消预选，拖选路径不受影响
  private longPressGuard: LongPressGuard = new LongPressGuard();
  // 复选框区拖选会话（FR-014）：null=未在拖选；方向性扫选模式按下时锁定，同次拖动不反转
  private sweepSession: SweepSession | null = null;
  // 边缘自动滚动器（FR-018）：拖选中手指进入列表可视区边缘带时驱动列表滚动续扫
  private edgeScroller: EdgeAutoScroller = new EdgeAutoScroller();
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
    }, 'QueueSheet');
    registerQueueSelectExit((): void => {
      this.exitSelectModeAnimated();
    });
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
    registerQueueSelectExit(undefined);
  }

  // 面板关闭（遮罩/返回/滑出任一方式）自动退出多选（v0.3 US7 FR-009）
  @Monitor('showQueueSheet.value')
  onQueueSheetVisibilityChanged(): void {
    if (!this.showQueueSheet.value) {
      this.exitSelectModeAnimated();
    }
  }

  // 多选退出即清选中（v0.3 US7）：外部（Index 系统返回）仅翻转 selectMode，选中项由本侧复位
  @Monitor('selectMode.value')
  onSelectModeChanged(): void {
    if (!this.selectMode.value) {
      this.selectedKeys = new Set<string>();
    } else {
      // 进入多选即收起已滑出的行（v0.4-Part1-ux-fixes US5）：多选态不再挂载左滑删除动作
      this.listScroller.closeAllSwipeActions();
    }
  }

  private syncFrom(c: PlayerController): void {
    if (this.playlistVersion !== c.playlistVersion) {
      this.playlistVersion = c.playlistVersion;
      const next: QueueEntry[] = buildQueueEntries(c.playlist, c.getQueueEntryGroups());
      // 纯删除走增量 notifyDataDelete（从高到低），增长/重排/组分裂/组缩减走整表 reload，相等 no-op
      const removed: number[] | undefined = diffRemovedEntries(this.entries, next);
      if (removed === undefined) {
        this.entries = next;
        this.listSource.setItems(next);
      } else {
        // 数据源持旧条目对象（notifyDataDelete 只裁数组），扁平删除使存活条目 startIndex 移位，
        // 先按 next 对齐再通知，保证重绑后「startIndex+组内偏移」换算的扁平下标可信
        let k: number = 0;
        for (let i = 0; i < this.entries.length; i++) {
          if (removed.indexOf(i) < 0) {
            this.entries[i].startIndex = next[k].startIndex;
            k++;
          }
        }
        for (let i = removed.length - 1; i >= 0; i--) {
          this.listSource.notifyDataDelete(removed[i]);
        }
        this.entries = next;
        // 删除后强制重绑（bugfix #1 机制保留）：从最低删除位扫到末尾，
        // 防止缓存条目闭包 index 过期（LazyForEach 使用 index 参数时删除后框架不保证重绑）
        if (removed.length > 0) {
          for (let i = removed[removed.length - 1]; i < next.length; i++) {
            this.listSource.notifyDataChange(i);
          }
        }
      }
      if (this.selectMode.value) {
        // 引用替换：仅保留仍存在的条目键（批删/清空后选中集失效项剔除）
        const valid: Set<string> = new Set<string>();
        for (let i = 0; i < this.entries.length; i++) {
          if (this.selectedKeys.has(this.entries[i].key)) {
            valid.add(this.entries[i].key);
          }
        }
        this.selectedKeys = valid;
        if (this.entries.length === 0) {
          this.selectMode.value = false;
        }
      }
    }
    this.currentIndex = c.currentIndex;
    this.currentItemEnded = c.currentItemEnded;
  }

  // 组头标题：纯视频标题（videoTitle，旧数据/占位回退 title）
  private groupHeaderTitle(item: BiliVideo): string {
    return item.videoTitle !== '' ? item.videoTitle : item.title;
  }

  // 分P 窄行主文本：Pn + 分P 标题（partTitle 空回退 title）
  private partRowTitle(item: BiliVideo): string {
    const name: string = item.partTitle !== '' ? item.partTitle : item.title;
    return `P${item.page} ${name}`;
  }

  // 组头点击两段判定（plan D4，沿第三轮 D13）：① latestHistoryOf 有历史 → 目标 = 最新 viewAt 分P
  // （续播其历史进度）；② 无历史 → 目标 = 条目内最小 page 条目（通常 P1，从头播）。目标在队列内
  // （复合键匹配，占位 0≡1）复用既有跳播入口；队外（仅①可能）以该历史条目元数据构造分P 条目
  // 走 playDownloadedSong 插播
  private onGroupHeaderClick(entry: QueueEntry): void {
    const head: BiliVideo = entry.videos[0];
    if (head.bvid === '') {
      return;
    }
    const latest: PlayHistoryItem | null = this.controller.latestHistoryOf(head.bvid);
    const targetPage: number = latest !== null ? latest.page : this.minEntryPage(entry);
    const idx: number = this.indexOfQueueItem(head.bvid, targetPage);
    if (idx >= 0) {
      this.controller.playIndex(idx, 0);
      return;
    }
    if (latest !== null) {
      this.playHistoryEntry(latest);
    }
  }

  // 条目内分P 条目的最小页号（②段目标；组内条目全为分P 条目，通常 P1）
  private minEntryPage(entry: QueueEntry): number {
    let minPage: number = 0;
    for (let i = 0; i < entry.videos.length; i++) {
      const cur: number = entry.videos[i].page;
      if (cur >= 1 && (minPage === 0 || cur < minPage)) {
        minPage = cur;
      }
    }
    return minPage;
  }

  // 队列内复合键定位（占位 0≡1 经 itemKeyOf 归一化比较）
  private indexOfQueueItem(bvid: string, page: number): number {
    const key: string = BiliVideo.itemKeyOf(bvid, page);
    const list: BiliVideo[] = this.controller.playlist;
    for (let i = 0; i < list.length; i++) {
      if (BiliVideo.itemKeyOf(list[i].bvid, list[i].page) === key) {
        return i;
      }
    }
    return -1;
  }

  // 队外目标插播（D13 回退语义）：以历史条目元数据构造分P 条目走既有历史点播路径（播完回原当前条目）
  private playHistoryEntry(entry: PlayHistoryItem): void {
    const v: BiliVideo = BiliVideo.create(entry.bvid, 0, entry.cid, entry.title, entry.cover, entry.duration);
    v.ownerName = entry.ownerName;
    v.page = entry.page;
    v.videoTitle = entry.videoTitle !== '' ? entry.videoTitle : entry.title;
    v.partTitle = entry.partTitle;
    this.controller.playDownloadedSong(v);
  }

  // 条目全部分P 复合键（plan D3）：确认移除时把选中条目键展开为分P 键，
  // 走既有 removeSelectedFromPlaylist（存储删除保持分P 粒度，索引修正/自动切播/持久化零改动）
  private entryPartKeys(entry: QueueEntry): string[] {
    const keys: string[] = [];
    for (let i = 0; i < entry.videos.length; i++) {
      keys.push(BiliVideo.itemKeyOf(entry.videos[i].bvid, entry.videos[i].page));
    }
    return keys;
  }

  private toggleSelect(key: string): void {
    this.selectedKeys = SelectLogic.toggle(this.selectedKeys, key);
  }

  private selectAll(): void {
    const all: Set<string> = new Set<string>();
    for (let i = 0; i < this.entries.length; i++) {
      all.add(this.entries[i].key);
    }
    this.selectedKeys = all;
  }

  private isAllSelected(): boolean {
    return this.entries.length > 0 && this.selectedKeys.size === this.entries.length;
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedKeys = new Set<string>();
    } else {
      this.selectAll();
    }
  }

  // 长按拖动范围选（plan D5）：from..to 区间内条目整条目选中（组键/单键，只增不减）
  private selectRange(from: number, to: number): void {
    const lo: number = Math.max(0, Math.min(from, to));
    const hi: number = Math.min(this.entries.length - 1, Math.max(from, to));
    const next: Set<string> = new Set<string>(this.selectedKeys);
    let changed: boolean = false;
    for (let i = lo; i <= hi; i++) {
      const key: string = this.entries[i].key;
      if (!next.has(key)) {
        next.add(key);
        changed = true;
      }
    }
    if (changed) {
      this.selectedKeys = next;
    }
  }

  // 拖选位移换算目标条目（plan D5）：从起始条目按条目估算高度累积换算（组条目高度可变），
  // 取代定值高度换算；估算保守只影响拖选效率
  private targetEntryIndex(start: number, offsetY: number): number {
    let idx: number = start;
    if (idx < 0) {
      return 0;
    }
    if (idx >= this.entries.length) {
      idx = this.entries.length - 1;
    }
    if (offsetY >= 0) {
      let acc: number = 0;
      while (idx + 1 < this.entries.length) {
        acc += this.entries[idx].estHeight;
        if (offsetY < acc) {
          break;
        }
        idx++;
      }
    } else {
      let acc: number = 0;
      while (idx - 1 >= 0) {
        acc -= this.entries[idx - 1].estHeight;
        if (offsetY >= acc) {
          break;
        }
        idx--;
      }
    }
    return idx;
  }

  // 复选框区拖选（FR-014/FR-018）：方向性扫选——按下采样起点条目选中态锁定加/减扫模式，
  // 按条目估算高度换算目标条目（组条目高度可变，复用既有 targetEntryIndex），
  // 起点→目标区间按锁定模式整体 Set 换引用；手指进入列表边缘带时自动滚动续扫；
  // 与行级 Sequence 长按拖选（只增不减）并存，二者手势热区互斥（勾选框列 vs 行主体）
  private startSweep(index: number, event: GestureEvent): void {
    if (index < 0 || index >= this.entries.length) {
      return;
    }
    this.sweepSession = new SweepSession();
    this.sweepSession.begin(this.selectedKeys.has(this.entries[index].key), index,
      event.fingerList[0].globalY, this.listScroller.currentOffset().yOffset);
    this.applySweepRange(index, index);
  }

  private updateSweep(globalY: number): void {
    if (this.sweepSession === null) {
      return;
    }
    const delta: number = this.sweepSession.delta(globalY, this.listScroller.currentOffset().yOffset);
    const target: number = this.targetEntryIndex(this.sweepSession.getStartIndex(), delta);
    this.applySweepRange(this.sweepSession.getStartIndex(), target);
  }

  private applySweepRange(from: number, to: number): void {
    if (this.sweepSession === null) {
      return;
    }
    const lo: number = Math.max(0, Math.min(from, to));
    const hi: number = Math.min(this.entries.length - 1, Math.max(from, to));
    const next: Set<string> = new Set<string>(this.selectedKeys);
    let changed: boolean = false;
    for (let i = lo; i <= hi; i++) {
      const key: string = this.entries[i].key;
      if (this.sweepSession.isAddMode()) {
        if (!next.has(key)) {
          next.add(key);
          changed = true;
        }
      } else if (next.has(key)) {
        next.delete(key);
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

  private checkSweepEdge(globalY: number): void {
    if (this.sweepSession === null) {
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

  private startEdgeScroll(downward: boolean): void {
    this.edgeScroller.start(this.listScroller, downward, (): void => {
      this.updateSweep(this.sweepSession === null ? 0 : this.sweepSession.getLastGlobalY());
    });
  }

  private exitSelectMode(): void {
    this.endSweep();
    this.selectMode.value = false;
    this.selectedKeys = new Set<string>();
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

  // 多选移除（US2）：二次确认防误触；确认后选中条目键展开为分P 键批量移除（US6 补位动画）
  private removeSelected(): void {
    const count: number = this.selectedKeys.size;
    if (count === 0) {
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_REMOVE_SELECTED_TITLE,
      message: Constants.DIALOG_REMOVE_SELECTED_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          const keys: string[] = [];
          for (let i = 0; i < this.entries.length; i++) {
            if (this.selectedKeys.has(this.entries[i].key)) {
              const parts: string[] = this.entryPartKeys(this.entries[i]);
              for (let p = 0; p < parts.length; p++) {
                keys.push(parts[p]);
              }
            }
          }
          this.exitSelectModeAnimated();
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.removeSelectedFromPlaylist(keys);
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

  // 左滑单条目删除确认（US1 双触发）：点垃圾桶/滑过阈值均进本弹窗；确认后按分P 键走既有
  // 批量移除链路（含当前条目自动切播语义），UI 刷新交由 syncFrom 的 diff 增量通知；
  // 取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveQueueItem(entry: QueueEntry): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_QUEUE_ITEM_TITLE,
      message: Constants.DIALOG_DELETE_QUEUE_ITEM_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.removeSelectedFromPlaylist(this.entryPartKeys(entry));
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.listScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.listScroller.closeAllSwipeActions();
      }
    });
  }

  // 左滑组条目整组移除确认（plan D6）：确认弹窗标注整组分P 数防误触；
  // 确认后走既有批量移除链路（含当前条目自动切播）
  private confirmRemoveGroup(entry: QueueEntry): void {
    const keys: string[] = this.entryPartKeys(entry);
    if (keys.length === 0) {
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_QUEUE_ITEM_TITLE,
      message: Constants.DIALOG_REMOVE_QUEUE_GROUP_MSG.replace('N', `${keys.length}`),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.removeSelectedFromPlaylist(keys);
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.listScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.listScroller.closeAllSwipeActions();
      }
    });
  }

  // 清除已播（US3）：无可清 toast 不弹框；可清时按可清计数（条目口径，plan D7）二次确认
  private confirmClearPlayed(): void {
    const count: number = this.controller.playedRemovableCount();
    if (count === 0) {
      promptAction.showToast({ message: Constants.TOAST_QUEUE_NO_PLAYED });
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_CLEAR_PLAYED_TITLE,
      message: Constants.DIALOG_CLEAR_PLAYED_COUNT_MSG.replace('N', `${count}`),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '清除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.clearPlayedItems();
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

  // 清空队列（R3 US4）：移除全部条目（含当前播放），二次确认防误触（计数为条目口径，plan D7）；
  // 确认后两层同收（closeBothLayersNow）+ 停声先行、延时清数据（clearAllWithExitDelay）
  private clearQueue(): void {
    if (this.entries.length === 0) {
      return;
    }
    AlertDialog.show({
      title: '清空队列',
      message: `确定移除全部 ${this.entries.length} 首吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          closeBothLayersNow();
          this.controller.clearAllWithExitDelay();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
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

  private listBlurStops(): FractionStop[] {
    const listHeight: number = this.pageHeight > 0 ? this.pageHeight : 800;
    const topEdge: number = Math.max(0.03, Math.min(0.45,
      this.headerHeight / listHeight));
    return [
      [1, 0],
      [1, topEdge * 0.7],
      [0, topEdge],
      [0, 1]
    ];
  }

  // 左滑露出的红色垃圾桶删除钮（US1 双触发）：点击进确认弹窗，滑过阈值（onAction）同弹窗；
  // 组条目按整组移除弹窗（标注分P 数），单条目按单删确认
  @Builder
  queueDeleteAction(entry: QueueEntry) {
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
        if (entry.isGroup) {
          this.confirmRemoveGroup(entry);
        } else {
          this.confirmRemoveQueueItem(entry);
        }
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  // 组条目视频头行（plan D4/D9）：封面 + 视频标题 + 共 nP 独占一行；多选态行首恒挂载 Checkbox
  // 容器（宽度/透明度随 selectMode 动画，整组切换，选择单位=条目）；
  // 按压高亮 + 长按进多选（选中本组条目）+ Pan 拖选与单条目整行同构；
  // 非多选点击整组续播（两段判定），多选点击整组切换
  @Builder
  videoHeaderRow(entry: QueueEntry, index: number) {
    Row() {
      // 勾选框区拖选（FR-014）：外包 Column 承载扫选手势，热区限勾选框列，
      // 行主体 Sequence 拖选（只增不减）与勾选框扫选（可加可减）并存互不冲突
      Column() {
        SelectCheckbox({
          active: this.selectMode.value,
          selected: this.selectedKeys.has(entry.key),
          gap: Constants.TOKEN_SPACE_L,
          onChange: (value: boolean): void => {
            const inSet: boolean = this.selectedKeys.has(entry.key);
            if (value !== inSet) {
              this.toggleSelect(entry.key);
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
            this.startSweep(index, event);
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.sweepSession === null) {
              return;
            }
            const globalY: number = event.fingerList.length > 0
              ? event.fingerList[0].globalY : this.sweepSession.getLastGlobalY();
            this.updateSweep(globalY);
            this.checkSweepEdge(globalY);
          })
          .onActionEnd((): void => {
            this.endSweep();
          })
          .onActionCancel((): void => {
            this.endSweep();
          })
      )
      CoverThumb({ cover: entry.videos[0].cover, highlight: false, accent: this.accentColor.value })
      Text(this.groupHeaderTitle(entry.videos[0]))
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: Constants.TOKEN_SPACE_10 })
      Text(`共 ${entry.videos.length}P`)
        .fontSize(Constants.TOKEN_FONT_AUX)
        .fontColor(this.textSecondary())
        .margin({ left: Constants.TOKEN_SPACE_S })
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_S })
    .backgroundColor(this.pressedKey === entry.key ? $r('app.color.item_pressed_background') : Color.Transparent)
    .borderRadius(Constants.TOKEN_RADIUS_M)
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.longPressGuard.reset();
        this.pressedKey = entry.key;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (this.longPressGuard.shouldSuppressClick()) {
        return;
      }
      if (this.selectMode.value) {
        this.toggleSelect(entry.key);
      } else {
        this.onGroupHeaderClick(entry);
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture()
          .onAction(() => {
            this.longPressGuard.arm();
            if (!this.selectMode.value) {
              this.enterSelectMode();
              this.selectedKeys = new Set<string>([entry.key]);
              this.dragStartEntryIndex = index;
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.selectMode.value || this.isWideScreen.value) {
              return;
            }
            const target: number = this.targetEntryIndex(this.dragStartEntryIndex, event.offsetY);
            this.selectRange(this.dragStartEntryIndex, target);
          })
      )
    )
  }

  // 组条目分P 窄行（plan D9）：无封面，Pn + 分P 标题 + 时长，左缩进对齐头行标题；
  // 点击切播（扁平下标 = startIndex+偏移）、当前播放高亮；多选点击/长按均为整条目（组）语义；
  // 已播 ✓ 为 bvid 级（D7 口径）；拖选/按压与头行同构（组为最小管理粒度，D15-Trim 语义保持）
  @Builder
  queuePartRow(part: BiliVideo, entry: QueueEntry, entryIndex: number, partIdx: number) {
    Row() {
      Text(this.partRowTitle(part))
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontColor(entry.startIndex + partIdx === this.currentIndex ? this.accentColor.value : this.textPrimary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (part.duration > 0) {
        Text(this.formatTime(part.duration * 1000))
          .fontSize(Constants.TOKEN_FONT_AUX)
          .fontColor(this.textSecondary())
          .margin({ left: Constants.TOKEN_SPACE_S })
      }
      if (!this.selectMode.value && this.controller.isPlayed(part.bvid)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontColor([$r('app.color.success_green')])
          .margin({ left: Constants.TOKEN_SPACE_XS })
      }
    }
    .width('100%')
    .padding({ left: Constants.QUEUE_PART_INDENT, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
    .backgroundColor(this.pressedKey === BiliVideo.itemKeyOf(part.bvid, part.page) ? $r('app.color.item_pressed_background') : Color.Transparent)
    .borderRadius(Constants.TOKEN_RADIUS_M)
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.longPressGuard.reset();
        this.pressedKey = BiliVideo.itemKeyOf(part.bvid, part.page);
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (this.longPressGuard.shouldSuppressClick()) {
        return;
      }
      if (this.selectMode.value) {
        this.toggleSelect(entry.key);
      } else {
        this.controller.playIndex(entry.startIndex + partIdx, 0);
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture()
          .onAction(() => {
            this.longPressGuard.arm();
            if (!this.selectMode.value) {
              this.enterSelectMode();
              this.selectedKeys = new Set<string>([entry.key]);
              this.dragStartEntryIndex = entryIndex;
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.selectMode.value || this.isWideScreen.value) {
              return;
            }
            const target: number = this.targetEntryIndex(this.dragStartEntryIndex, event.offsetY);
            this.selectRange(this.dragStartEntryIndex, target);
          })
      )
    )
  }

  // 单条目整行（原有渲染原样保留）：封面 + 标题 + UP 主/时长；多选态行首恒挂载 Checkbox
  // 容器（宽度/透明度随 selectMode 动画）；选择/按压/手势改条目键
  @Builder
  queueFullRow(entry: QueueEntry, index: number) {
    Row() {
      // 勾选框区拖选（FR-014）：外包 Column 承载扫选手势，热区限勾选框列，
      // 行主体 Sequence 拖选（只增不减）与勾选框扫选（可加可减）并存互不冲突
      Column() {
        SelectCheckbox({
          active: this.selectMode.value,
          selected: this.selectedKeys.has(entry.key),
          gap: Constants.TOKEN_SPACE_L,
          onChange: (value: boolean): void => {
            const inSet: boolean = this.selectedKeys.has(entry.key);
            if (value !== inSet) {
              this.toggleSelect(entry.key);
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
            this.startSweep(index, event);
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.sweepSession === null) {
              return;
            }
            const globalY: number = event.fingerList.length > 0
              ? event.fingerList[0].globalY : this.sweepSession.getLastGlobalY();
            this.updateSweep(globalY);
            this.checkSweepEdge(globalY);
          })
          .onActionEnd((): void => {
            this.endSweep();
          })
          .onActionCancel((): void => {
            this.endSweep();
          })
      )

      CoverThumb({ cover: entry.videos[0].cover, highlight: entry.startIndex === this.currentIndex, accent: this.accentColor.value })

      Column() {
        Row() {
          Text(entry.videos[0].title)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor(entry.startIndex === this.currentIndex ? this.accentColor.value : this.textPrimary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        // FR-104：duration 未知（0）不渲染 00:00 占位，只显示 UP 主名
        Text(entry.videos[0].duration > 0 ? `${entry.videos[0].ownerName} · ${this.formatTime(entry.videos[0].duration * 1000)}` : entry.videos[0].ownerName)
          .fontSize(Constants.TOKEN_FONT_AUX)
          .fontColor(this.textSecondary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: Constants.TOKEN_SPACE_XS })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Constants.TOKEN_SPACE_10 })

      // 已播标记（US4）：非当前条目且已播完时行尾绿 ✓，对齐 SourcePage NEW 徽标视觉
      if (!this.selectMode.value && this.controller.isPlayed(entry.videos[0].bvid)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontColor([$r('app.color.success_green')])
          .margin({ left: Constants.TOKEN_SPACE_XS })
      }
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_M })
    .backgroundColor(this.pressedKey === entry.key ? $r('app.color.item_pressed_background') : Color.Transparent)
    .borderRadius(Constants.TOKEN_RADIUS_M)
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.longPressGuard.reset();
        this.pressedKey = entry.key;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (this.longPressGuard.shouldSuppressClick()) {
        return;
      }
      if (this.selectMode.value) {
        this.toggleSelect(entry.key);
      } else {
        // 仅切换歌曲，不跳转播放页
        this.controller.playIndex(entry.startIndex, 0);
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture()
          .onAction(() => {
            this.longPressGuard.arm();
            if (!this.selectMode.value) {
              this.enterSelectMode();
              this.selectedKeys = new Set<string>([entry.key]);
              this.dragStartEntryIndex = index;
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.selectMode.value || this.isWideScreen.value) {
              return;
            }
            const target: number = this.targetEntryIndex(this.dragStartEntryIndex, event.offsetY);
            this.selectRange(this.dragStartEntryIndex, target);
          })
      )
    )
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 单行头部（US1）：标题 + 清除已播/多选/清空三图标；多选态整行替换为多选操作行；
      // Stack 承载双态条件渲染 + OPACITY 过渡交叉淡化（进出多选同 animateTo 驱动，FR-006）
      Stack() {
        if (!this.selectMode.value) {
          Row() {
            Text(`播放队列 (${this.entries.length})`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .layoutWeight(1)

            if (this.entries.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(Constants.GLASS_ICON_BTN_SIZE)
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .onClick(() => {
                this.confirmClearPlayed();
              })

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
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
              .onClick(() => {
                this.enterSelectMode();
                this.selectedKeys = new Set<string>();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(Constants.GLASS_ICON_BTN_SIZE)
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_BLUR)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
              .onClick(() => {
                this.clearQueue();
              })
            }
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY)
        } else {
          // 多选操作行（US1 FR-006/FR-011/FR-012）：全选/移除所选(计数)/返回全部图标化
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_on_circle'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([this.isAllSelected() ? this.accentColor.value : $r('app.color.text_primary')])
            }
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_BLUR)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .onClick(() => {
              this.toggleSelectAll();
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
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .opacity(this.selectedKeys.size > 0 ? 1 : Constants.TOKEN_DISABLED_OPACITY)
            .onClick(() => {
              this.removeSelected();
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
            .border({ width: 1, color: $r('app.color.btn_border') })
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
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_20, bottom: Constants.TOKEN_SPACE_S })
      .zIndex(1)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.headerHeight = newArea.height as number;
      })

      if (this.entries.length === 0) {
        Column() {
          Text('队列为空')
            .fontSize(Constants.TOKEN_FONT_TITLE)
            .fontColor(this.textSecondary())
            .margin({ top: 60 })
          Text(Constants.QUEUE_EMPTY_HINT)
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor(this.textDisabled())
            .margin({ top: Constants.TOKEN_SPACE_S })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .padding({ top: this.headerHeight })
      } else {
        Stack() {
          List({ space: 0, scroller: this.listScroller }) {
            LazyForEach(this.listSource, (entry: QueueEntry, index: number) => {
              ListItem() {
                // 条目分发渲染（plan D9）：组条目 = Column{ 头行 + ForEach(分P 窄行) } 一体滑动，
                // 单条目沿用整行；外层键 = 条目键，组内键 = 分P 复合键
                if (entry.isGroup) {
                  Column() {
                    this.videoHeaderRow(entry, index)
                    ForEach(entry.videos, (part: BiliVideo, partIdx: number) => {
                      this.queuePartRow(part, entry, index, partIdx)
                    }, (part: BiliVideo) => BiliVideo.itemKeyOf(part.bvid, part.page))
                  }
                } else {
                  this.queueFullRow(entry, index)
                }
              }
              // 条目级横删（plan D6）：组条目整组滑出（组/单删双弹窗），多选态不挂载删除动作
              // （左滑手势随 end 缺失整体禁用，退出多选恢复）；删除按钮点击与滑过阈值（onAction）双触发
              .swipeAction(this.selectMode.value ? {} : {
                end: {
                  builder: (): void => {
                    this.queueDeleteAction(entry);
                  },
                  onAction: (): void => {
                    if (entry.isGroup) {
                      this.confirmRemoveGroup(entry);
                    } else {
                      this.confirmRemoveQueueItem(entry);
                    }
                  }
                }
              })
            }, (entry: QueueEntry) => entry.key)
          }
          .width('100%')
          .height('100%')
          .id(SWEEP_LIST_ID)
          // FR-103：alwaysEnabled 使未铺满面板的短队列仍可拖动过冲（写法对齐 SettingsPage 历史面板）
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .contentStartOffset(this.headerHeight)
          // 末行逃出 GlassSheet 底部渐隐带（T018）：SHEET_FADE_HEIGHT 渐变叠加罩住列表底部 80px，
          // end offset 至少盖过带高再留 LIST_BOTTOM_GAP 视觉间距，末行才能完整滚出渐隐区
          .contentEndOffset(Constants.SHEET_FADE_HEIGHT + LIST_BOTTOM_GAP)
          .linearGradientBlur(EDGE_BLUR_RADIUS, {
            fractionStops: this.listBlurStops(),
            direction: GradientDirection.Bottom
          })
        }
        .width('100%')
        .height('100%')
      }

    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageHeight = newArea.height as number;
    })
  }
}
