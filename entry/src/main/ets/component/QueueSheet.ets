import { PlayerController } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';
import { PlayHistoryItem } from '../model/PlayHistoryItem';


import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { closeBothLayersNow } from '../service/BackHandler';
import { CoverThumb } from './CoverThumb';
import { promptAction } from '@kit.ArkUI';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 列表上下边缘渐变模糊半径；sheet 底部安全留白
const EDGE_BLUR_RADIUS: number = 48;
const LIST_BOTTOM_GAP: number = 12;
// 列表项近似高度：长按滑动多选时把手指位移换算成经过的条目数（富列表：44 封面 + 上下各 12 内边距）
// ponytail: 分P 窄行（约 36）低于本估算，滑动范围选对窄行计数偏保守；需要精确时改按行实际高度累积
const ITEM_HEIGHT: number = 68;

// 播放列表懒加载数据源：配合 LazyForEach 只构建可视区域内的列表项，
// 避免长歌单一次性创建全部条目（每项都要下载并解码一张封面，会瞬间打满内存）
class PlaylistDataSource implements IDataSource {
  private items: BiliVideo[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): BiliVideo {
    return this.items[index];
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

  setItems(next: BiliVideo[]): void {
    // 入参可能是 @State 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.items = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  // 单项增量删除通知（queue-redesign plan R7）：镜像 HistoryDataSource——先裁自身再广播，
  // 供左滑删除/清除已播从高索引向低索引逐项刷新，避免整表 reload 造成的封面闪烁
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    this.items.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }

  // 单项变更通知：LazyForEach 删除后不重绑部分缓存条目生成器闭包里的 index（过期下标对已缩短
  // 数组越界即 jscrash），增量删除后从最低删除位到末尾逐项 onDataChange 强制重绑，使 index 恢复可信
  notifyDataChange(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}

// 队列 diff（queue-redesign plan R7）：next 可由 old 纯删除得到时返回被删下标（升序），
// 否则（增长/重排）返回 undefined，调用方走整表 reload；相等返回空数组（no-op，不触发刷新）
// 比较键为复合键（bvid:page）——同视频多分P 条目 bvid 不再唯一
function diffRemovedIndices(old: BiliVideo[], next: BiliVideo[]): number[] | undefined {
  const removed: number[] = [];
  let j: number = 0;
  for (let i = 0; i < old.length; i++) {
    if (j < next.length && BiliVideo.itemKeyOf(old[i].bvid, old[i].page) ===
      BiliVideo.itemKeyOf(next[j].bvid, next[j].page)) {
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

// 播放队列抽屉：单行图标头部（清除已播/多选/清空）、左滑单条删除、多选批量移除
@ComponentV2
export struct QueueSheet {
  @Local items: BiliVideo[] = [];
  @Local currentIndex: number = -1;
  @Local currentItemEnded: boolean = false;
  @Local playlistVersion: number = -1;
  @Local selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
  @Local selectedBvids: string[] = [];
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
  private swipeStartIndex: number = -1;
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
    }, 'QueueSheet');
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
  }

  // 面板关闭（遮罩/返回/滑出任一方式）自动退出多选（v0.3 US7 FR-009）
  @Monitor('showQueueSheet.value')
  onQueueSheetVisibilityChanged(): void {
    if (!this.showQueueSheet.value) {
      this.exitSelectMode();
    }
  }

  // 多选退出即清选中（v0.3 US7）：外部（Index 系统返回）仅翻转 selectMode，选中项由本侧复位
  @Monitor('selectMode.value')
  onSelectModeChanged(): void {
    if (!this.selectMode.value) {
      this.selectedBvids = [];
    } else {
      // 进入多选即收起已滑出的行（v0.4-Part1-ux-fixes US5）：多选态不再挂载左滑删除动作
      this.listScroller.closeAllSwipeActions();
    }
  }

  private syncFrom(c: PlayerController): void {
    if (this.playlistVersion !== c.playlistVersion) {
      this.playlistVersion = c.playlistVersion;
      const next: BiliVideo[] = c.playlist.slice(0);
      // 纯删除走增量 notifyDataDelete（从高到低），增长/重排走整表 reload，相等 no-op
      const removed: number[] | undefined = diffRemovedIndices(this.items, next);
      if (removed === undefined) {
        this.items = next;
        this.listSource.setItems(this.items);
      } else {
        for (let i = removed.length - 1; i >= 0; i--) {
          this.listSource.notifyDataDelete(removed[i]);
        }
        this.items = next;
        // 删除后强制重绑（机制见 PlaylistDataSource.notifyDataChange 注释）：
        // 从最低删除位扫到末尾，防止缓存条目闭包 index 过期
        if (removed.length > 0) {
          for (let i = removed[removed.length - 1]; i < next.length; i++) {
            this.listSource.notifyDataChange(i);
          }
        }
      }
      if (this.selectMode.value) {
        const valid: string[] = [];
        for (let i = 0; i < this.selectedBvids.length; i++) {
          if (this.items.findIndex((v: BiliVideo): boolean => this.itemKey(v) === this.selectedBvids[i]) >= 0) {
            valid.push(this.selectedBvids[i]);
          }
        }
        this.selectedBvids = valid;
        if (this.items.length === 0) {
          this.selectMode.value = false;
        }
      }
    }
    this.currentIndex = c.currentIndex;
    this.currentItemEnded = c.currentItemEnded;
  }

  // 队列条目复合键（bvid:page）唯一合成点：多选 ID / 按压高亮 / 删除入参共用
  private itemKey(item: BiliVideo): string {
    return BiliVideo.itemKeyOf(item.bvid, item.page);
  }

  // US7 组头标志派生（D12）：组首 = 分P 条目（page≥1）、前一条目不构成同组、后一条目同 bvid 且
  // 同为分P 条目（相邻 ≥2 条成组）；随机打散后不相邻自然无头，占位条目不成组。
  // 纯展示层派生（FR-015），随 items 整体重算，删至不成组时组头自动消失
  private hasGroupHeader(index: number): boolean {
    const items: BiliVideo[] = this.items;
    // 边界守卫：index 可能是 LazyForEach 未重绑的过期闭包值（见 notifyDataChange 注释），越界一律无头
    if (index < 0 || index >= items.length) {
      return false;
    }
    const cur: BiliVideo = items[index];
    if (cur.page < 1 || index + 1 >= items.length) {
      return false;
    }
    if (index > 0) {
      const prev: BiliVideo = items[index - 1];
      if (prev.bvid === cur.bvid && prev.page >= 1) {
        return false;
      }
    }
    const next: BiliVideo = items[index + 1];
    return next.bvid === cur.bvid && next.page >= 1;
  }

  // 组头标题：纯视频标题（videoTitle，旧数据/占位回退 title）
  private groupHeaderTitle(item: BiliVideo): string {
    return item.videoTitle !== '' ? item.videoTitle : item.title;
  }

  // 组内分P 条目判定（D15）：前或后相邻条目同 bvid 且同为分P 条目——组首（hasGroupHeader）与
  // 组身共用；孤立/单P/占位条目不满足，走原有整行
  private isGroupedPart(index: number): boolean {
    const items: BiliVideo[] = this.items;
    if (index < 0 || index >= items.length) {
      return false;
    }
    const cur: BiliVideo = items[index];
    if (cur.page < 1) {
      return false;
    }
    if (index > 0) {
      const prev: BiliVideo = items[index - 1];
      if (prev.bvid === cur.bvid && prev.page >= 1) {
        return true;
      }
    }
    if (index + 1 < items.length) {
      const next: BiliVideo = items[index + 1];
      if (next.bvid === cur.bvid && next.page >= 1) {
        return true;
      }
    }
    return false;
  }

  // 组内分P 数（头行「共 nP」）：以组首为起点向后数相邻同 bvid 分P 条目
  private groupPartCount(index: number): number {
    const items: BiliVideo[] = this.items;
    if (index < 0 || index >= items.length) {
      return 0;
    }
    const bvid: string = items[index].bvid;
    let count: number = 0;
    for (let i = index; i < items.length; i++) {
      if (items[i].bvid !== bvid || items[i].page < 1) {
        break;
      }
      count++;
    }
    return count;
  }

  // 组内任意成员的组首下标（D15-Trim 整组语义用）：沿前邻同 bvid 分P 链回溯
  private groupStartIndex(index: number): number {
    let start: number = index;
    while (start > 0) {
      const prev: BiliVideo = this.items[start - 1];
      const cur: BiliVideo = this.items[start];
      if (prev.bvid !== cur.bvid || prev.page < 1 || cur.page < 1) {
        break;
      }
      start--;
    }
    return start;
  }

  // 组键收集（D15 头行多选/整组移除共用）：从组首（index）向后收集相邻同 bvid 分P 条目复合键
  private groupKeys(index: number): string[] {
    const keys: string[] = [];
    const items: BiliVideo[] = this.items;
    if (index < 0 || index >= items.length) {
      return keys;
    }
    const bvid: string = items[index].bvid;
    for (let i = index; i < items.length; i++) {
      const cur: BiliVideo = items[i];
      if (cur.bvid !== bvid || cur.page < 1) {
        break;
      }
      keys.push(this.itemKey(cur));
    }
    return keys;
  }

  // 头行整组选中态：全组复合键均在 selectedBvids 才算选中
  // （管理收敛头行后组勾选恒全选/全不选，无部分选中路径，全检保留作兜底）
  private isGroupFullySelected(index: number): boolean {
    const keys: string[] = this.groupKeys(index);
    for (let i = 0; i < keys.length; i++) {
      if (this.selectedBvids.indexOf(keys[i]) < 0) {
        return false;
      }
    }
    return keys.length > 0;
  }

  // 头行整组切换（D15 多选）：全选则清本组，否则补齐本组未选键
  private toggleGroupSelect(index: number): void {
    const keys: string[] = this.groupKeys(index);
    if (keys.length === 0) {
      return;
    }
    if (this.isGroupFullySelected(index)) {
      const next: string[] = [];
      for (let i = 0; i < this.selectedBvids.length; i++) {
        if (keys.indexOf(this.selectedBvids[i]) < 0) {
          next.push(this.selectedBvids[i]);
        }
      }
      this.selectedBvids = next;
    } else {
      const next: string[] = this.selectedBvids.slice(0);
      for (let i = 0; i < keys.length; i++) {
        if (next.indexOf(keys[i]) < 0) {
          next.push(keys[i]);
        }
      }
      this.selectedBvids = next;
    }
  }

  // 分P 窄行主文本：Pn + 分P 标题（partTitle 空回退 title）
  private partRowTitle(item: BiliVideo): string {
    const name: string = item.partTitle !== '' ? item.partTitle : item.title;
    return `P${item.page} ${name}`;
  }

  // US7 组头点击两段判定（D13）：① latestHistoryOf 有历史 → 目标 = 最新 viewAt 分P（续播其历史进度）；
  // ② 无历史 → 目标 = 组内最小 page 条目（通常 P1，从头播）。目标在队列内（复合键匹配，占位 0≡1）
  // 复用既有跳播入口；队外（仅①可能）以该历史条目元数据构造分P 条目走 playDownloadedSong 插播
  private onGroupHeaderClick(item: BiliVideo): void {
    if (item.bvid === '') {
      return;
    }
    const latest: PlayHistoryItem | null = this.controller.latestHistoryOf(item.bvid);
    let targetPage: number = 0;
    if (latest !== null) {
      targetPage = latest.page;
    } else {
      targetPage = this.minGroupPage(item.bvid);
    }
    const idx: number = this.indexOfQueueItem(item.bvid, targetPage);
    if (idx >= 0) {
      this.controller.playIndex(idx, 0);
      return;
    }
    if (latest !== null) {
      this.playHistoryEntry(latest);
    }
  }

  // 该视频在队列内分P 条目的最小页号（②段目标；组内条目全为分P 条目，通常 P1）
  private minGroupPage(bvid: string): number {
    let minPage: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      const cur: BiliVideo = this.items[i];
      if (cur.bvid === bvid && cur.page >= 1 && (minPage === 0 || cur.page < minPage)) {
        minPage = cur.page;
      }
    }
    return minPage;
  }

  // 队列内复合键定位（占位 0≡1 经 itemKeyOf 归一化比较）
  private indexOfQueueItem(bvid: string, page: number): number {
    const key: string = BiliVideo.itemKeyOf(bvid, page);
    for (let i = 0; i < this.items.length; i++) {
      if (this.itemKey(this.items[i]) === key) {
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

  private toggleSelect(key: string): void {
    const idx: number = this.selectedBvids.indexOf(key);
    if (idx >= 0) {
      this.selectedBvids.splice(idx, 1);
    } else {
      this.selectedBvids.push(key);
    }
    this.selectedBvids = this.selectedBvids.slice(0);
  }

  private selectAll(): void {
    const all: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      all.push(this.itemKey(this.items[i]));
    }
    this.selectedBvids = all;
  }

  private isAllSelected(): boolean {
    return this.items.length > 0 && this.selectedBvids.length === this.items.length;
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedBvids = [];
    } else {
      this.selectAll();
    }
  }

  // 长按滑动多选：把 from..to 区间内所有条目选中（只增不减）；
  // 组感知（D15-Trim）：区间碰到的组整组补齐，孤立/单P 条目按单键
  private selectRange(from: number, to: number): void {
    const lo: number = Math.max(0, Math.min(from, to));
    const hi: number = Math.min(this.items.length - 1, Math.max(from, to));
    let changed: boolean = false;
    for (let i = lo; i <= hi; i++) {
      const keys: string[] = this.isGroupedPart(i)
        ? this.groupKeys(this.groupStartIndex(i))
        : [this.itemKey(this.items[i])];
      for (let k = 0; k < keys.length; k++) {
        if (this.selectedBvids.indexOf(keys[k]) < 0) {
          this.selectedBvids.push(keys[k]);
          changed = true;
        }
      }
    }
    if (changed) {
      this.selectedBvids = this.selectedBvids.slice(0);
    }
  }

  private exitSelectMode(): void {
    this.selectMode.value = false;
    this.selectedBvids = [];
  }

  // 多选移除（US2）：二次确认防误触；确认后批量移除包补位动画（US6）
  private removeSelected(): void {
    const count: number = this.selectedBvids.length;
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
          const keys: string[] = this.selectedBvids.slice(0);
          this.exitSelectMode();
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

  // 左滑单条删除（US2 FR-004/FR-005）：按复合键走既有批量移除链路
  // （含当前条目自动切播语义，FR-010），UI 刷新交由 syncFrom 的 diff 增量通知
  private removeQueueItem(item: BiliVideo): void {
    if (item.bvid === '') {
      return;
    }
    this.controller.removeSelectedFromPlaylist([this.itemKey(item)]);
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除（US6 补位动画），取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveQueueItem(item: BiliVideo): void {
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
            this.removeQueueItem(item);
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

  // 组首条目左滑整组移除（D15）：头行与组首分P 同属一个 ListItem，swipeAction 只能挂 ListItem，
  // 故组首左滑语义为整组移除（确认弹窗标注分P 数防误触）；确认后走既有批量移除链路（含自动切播）
  private confirmRemoveGroup(index: number): void {
    const keys: string[] = this.groupKeys(index);
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

  // 清除已播（US3）：无可清 toast 不弹框；可清时按可清计数二次确认，确认后按 playedSet 语义清理
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

  // 清空队列（R3 US4）：移除全部条目（含当前播放），二次确认防误触；
  // 确认后两层同收（closeBothLayersNow）+ 停声先行、延时清数据（clearAllWithExitDelay）
  private clearQueue(): void {
    if (this.items.length === 0) {
      return;
    }
    AlertDialog.show({
      title: '清空队列',
      message: `确定移除全部 ${this.items.length} 首吗？`,
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
  // 组首条目（含视频头行）按整组移除弹窗，其余按单条
  @Builder
  queueDeleteAction(item: BiliVideo, index: number) {
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
        if (this.hasGroupHeader(index)) {
          this.confirmRemoveGroup(index);
        } else {
          this.confirmRemoveQueueItem(item);
        }
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  // 视频头行（D15）：封面 + 视频标题 + 共 nP 独占一行；多选态前置换 Checkbox（整组切换，
  // 管理收敛头行后组勾选恒全选/全不选）；非多选点击整组续播（D13 两段判定）；不参与按压高亮
  @Builder
  videoHeaderRow(item: BiliVideo, index: number) {
    Row() {
      if (this.selectMode.value) {
        Checkbox()
          .select(this.isGroupFullySelected(index))
          .selectedColor(this.accentColor.value)
          .width(20)
          .height(20)
          .margin({ right: Constants.TOKEN_SPACE_S })
          .onChange((value: boolean) => {
            if (value !== this.isGroupFullySelected(index)) {
              this.toggleGroupSelect(index);
            }
          })
      }
      CoverThumb({ cover: item.cover, highlight: false, accent: this.accentColor.value })
      Text(this.groupHeaderTitle(item))
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: Constants.TOKEN_SPACE_10 })
      Text(`共 ${this.groupPartCount(index)}P`)
        .fontSize(Constants.TOKEN_FONT_AUX)
        .fontColor(this.textSecondary())
        .margin({ left: Constants.TOKEN_SPACE_S })
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_S })
    .onClick(() => {
      if (this.selectMode.value) {
        this.toggleGroupSelect(index);
      } else {
        this.onGroupHeaderClick(item);
      }
    })
  }

  // 分P 窄行（D15）：无封面，Pn + 分P 标题 + 时长，左缩进对齐头行标题；
  // 管理收敛头行（D15-Trim）：无勾选框/无左滑，点击切播，多选点击与长按均为整组语义；已播 ✓ 为 bvid 级（D7 口径）
  @Builder
  queuePartRow(item: BiliVideo, index: number) {
    Row() {
      Text(this.partRowTitle(item))
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontColor(index === this.currentIndex ? this.accentColor.value : this.textPrimary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (item.duration > 0) {
        Text(this.formatTime(item.duration * 1000))
          .fontSize(Constants.TOKEN_FONT_AUX)
          .fontColor(this.textSecondary())
          .margin({ left: Constants.TOKEN_SPACE_S })
      }
      if (!this.selectMode.value && this.controller.isPlayed(item.bvid)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontColor([$r('app.color.success_green')])
          .margin({ left: Constants.TOKEN_SPACE_XS })
      }
    }
    .width('100%')
    .padding({ left: Constants.QUEUE_PART_INDENT, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
    .backgroundColor(this.pressedKey === this.itemKey(item) ? $r('app.color.item_pressed_background') : Color.Transparent)
    .borderRadius(Constants.TOKEN_RADIUS_M)
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.pressedKey = this.itemKey(item);
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (this.selectMode.value) {
        this.toggleGroupSelect(this.groupStartIndex(index));
      } else {
        this.controller.playIndex(index, 0);
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture()
          .onAction(() => {
            if (!this.selectMode.value) {
              const start: number = this.groupStartIndex(index);
              this.selectMode.value = true;
              this.selectedBvids = this.groupKeys(start);
              this.swipeStartIndex = start;
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.selectMode.value || this.isWideScreen.value) {
              return;
            }
            const target: number = this.swipeStartIndex +
              Math.round(event.offsetY / ITEM_HEIGHT);
            this.selectRange(this.swipeStartIndex, target);
          })
      )
    )
  }

  // 孤立/单P 条目整行（原有渲染原样保留）：封面 + 标题 + UP 主/时长
  @Builder
  queueFullRow(item: BiliVideo, index: number) {
    Row() {
      if (this.selectMode.value) {
        Checkbox()
          .select(this.selectedBvids.indexOf(this.itemKey(item)) >= 0)
          .selectedColor(this.accentColor.value)
          .width(20)
          .height(20)
          .margin({ right: Constants.TOKEN_SPACE_S })
          .onChange((value: boolean) => {
            const inList: boolean = this.selectedBvids.indexOf(this.itemKey(item)) >= 0;
            if (value !== inList) {
              this.toggleSelect(this.itemKey(item));
            }
          })
      }

      CoverThumb({ cover: item.cover, highlight: index === this.currentIndex, accent: this.accentColor.value })

      Column() {
        Row() {
          Text(item.title)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor(index === this.currentIndex ? this.accentColor.value : this.textPrimary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        // FR-104：duration 未知（0）不渲染 00:00 占位，只显示 UP 主名
        Text(item.duration > 0 ? `${item.ownerName} · ${this.formatTime(item.duration * 1000)}` : item.ownerName)
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
      if (!this.selectMode.value && this.controller.isPlayed(item.bvid)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(Constants.TOKEN_FONT_TITLE)
          .fontColor([$r('app.color.success_green')])
          .margin({ left: Constants.TOKEN_SPACE_XS })
      }
    }
    .width('100%')
    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_M })
    .backgroundColor(this.pressedKey === this.itemKey(item) ? $r('app.color.item_pressed_background') : Color.Transparent)
    .borderRadius(Constants.TOKEN_RADIUS_M)
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.pressedKey = this.itemKey(item);
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (this.selectMode.value) {
        this.toggleSelect(this.itemKey(item));
      } else {
        // 仅切换歌曲，不跳转播放页
        this.controller.playIndex(index, 0);
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture()
          .onAction(() => {
            if (!this.selectMode.value) {
              this.selectMode.value = true;
              this.selectedBvids = [this.itemKey(item)];
              this.swipeStartIndex = index;
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.selectMode.value || this.isWideScreen.value) {
              return;
            }
            const target: number = this.swipeStartIndex +
              Math.round(event.offsetY / ITEM_HEIGHT);
            this.selectRange(this.swipeStartIndex, target);
          })
      )
    )
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 单行头部（US1）：标题 + 清除已播/多选/清空三图标；多选态整行替换为多选操作行
      Column() {
        if (!this.selectMode.value) {
          Row() {
            Text(`播放队列 (${this.items.length})`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .layoutWeight(1)

            if (this.items.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
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
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
              .onClick(() => {
                this.selectMode.value = true;
                this.selectedBvids = [];
              })

              Row() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
              .onClick(() => {
                this.clearQueue();
              })
            }
          }
          .width('100%')
        } else {
          // 多选操作行（US1 FR-006/FR-011/FR-012）：全选/移除所选(计数)/返回全部图标化
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_on_circle'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([this.isAllSelected() ? this.accentColor.value : $r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
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
              Text(`${this.selectedBvids.length}`)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.danger_red'))
            }
            .height(36)
            .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .opacity(this.selectedBvids.length > 0 ? 1 : 0.4)
            .onClick(() => {
              this.removeSelected();
            })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .margin({ left: Constants.TOKEN_SPACE_S })
            .onClick(() => {
              this.exitSelectMode();
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_20, bottom: Constants.TOKEN_SPACE_S })
      .zIndex(1)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.headerHeight = newArea.height as number;
      })

      if (this.items.length === 0) {
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
            LazyForEach(this.listSource, (item: BiliVideo, index: number) => {
              ListItem() {
                Column() {
                  // US7→D15 视频级分组：组首条目顶部渲染视频头行（封面+标题独占一行），
                  // 组内条目渲染分P 窄行（按分P 标题），孤立/单P 条目保持原有整行
                  if (this.hasGroupHeader(index)) {
                    this.videoHeaderRow(item, index)
                  }
                  if (this.isGroupedPart(index)) {
                    this.queuePartRow(item, index)
                  } else {
                    this.queueFullRow(item, index)
                  }
                }
              }
              // 多选态不挂载删除动作（v0.4-Part1-ux-fixes US5）：左滑手势随 end 缺失整体禁用，退出多选恢复；
              // 组身分P 管理收敛头行（D15-Trim）亦不挂；组首 ListItem（含视频头行）左滑整组移除（D15），整行保持单条删除
              .swipeAction((this.selectMode.value || (this.isGroupedPart(index) && !this.hasGroupHeader(index))) ? {} : {
                end: {
                  builder: (): void => {
                    this.queueDeleteAction(item, index);
                  },
                  onAction: (): void => {
                    if (this.hasGroupHeader(index)) {
                      this.confirmRemoveGroup(index);
                    } else {
                      this.confirmRemoveQueueItem(item);
                    }
                  }
                }
              })
            }, (item: BiliVideo) => `${item.bvid}_${item.page}_${item.ownerName}`)
          }
          .width('100%')
          .height('100%')
          // FR-103：alwaysEnabled 使未铺满面板的短队列仍可拖动过冲（写法对齐 SettingsPage 历史面板）
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .contentStartOffset(this.headerHeight)
          .contentEndOffset(LIST_BOTTOM_GAP)
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
