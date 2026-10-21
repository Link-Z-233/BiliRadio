import { componentUtils } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { BiliService, VideoDetail, UpInfo } from '../service/BiliService';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { PlayerController, EnqueueResult } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { dismissOverlaysForBack } from '../service/BackHandler';
import { SelectLogic, LongPressGuard, SweepSession, RowDragSession, EdgeAutoScroller } from '../service/SelectLogic';
import { Appearance } from '../service/Appearance';
import { connectNum, connectStr, NumState, StrState } from '../service/V2State';
import { CoverThumb } from '../component/CoverThumb';
import { SelectCheckbox } from '../component/SelectCheckbox';

// 拖选边缘带定位用 List 组件 id（checkSweepEdge 与 .id() 同源）
const SWEEP_LIST_ID: string = 'sourcePageList';

function formatDuration(sec: number): string {
  if (sec <= 0) {
    return '';
  }
  const m: number = Math.floor(sec / 60);
  const s: number = sec % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

function formatDate(sec: number): string {
  if (sec <= 0) {
    return '';
  }
  const d: Date = new Date(sec * 1000);
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const hh: number = d.getHours();
  const mm: number = d.getMinutes();
  const hhStr: string = hh < 10 ? `0${hh}` : `${hh}`;
  const mmStr: string = mm < 10 ? `0${mm}` : `${mm}`;
  const now: Date = new Date();
  if (now.getFullYear() === d.getFullYear() && now.getMonth() === d.getMonth() &&
    now.getDate() === d.getDate()) {
    return `${hhStr}:${mmStr}`;
  }
  if (now.getFullYear() === d.getFullYear()) {
    return `${m}-${day} ${hhStr}:${mmStr}`;
  }
  return `${d.getFullYear()}-${m}-${day} ${hhStr}:${mmStr}`;
}

@Builder
export function SourcePageBuilder() {
  SourcePage()
}

// 源详情：剧集列表（新在上）/ NEW 徽标 / 已播标记 / 顶栏 ··· 菜单（刷新/取消订阅）/ 多选批量入队
// 四类订阅（UP/收藏夹/合集/系列）统一支持触底「加载更早」（按需翻页，只进内存不写缓存）
@ComponentV2
struct SourcePage {
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  @Local navTitle: string = '';
  @Local episodes: BiliVideo[] = [];      // 展示序：倒序（新在上，与缓存一致）
  @Local refreshing: boolean = false;
  @Local canLoadOlder: boolean = false;
  @Local loadingOlder: boolean = false;
  @Local episodeCount: number = 0;
  @Local pressedKey: string = '';
  @Local selectMode: boolean = false;
  // 多选集合不可变整体换引用更新：V2 @Local 赋值观测不观测 Set 内部变更
  @Local selectedKeys: Set<string> = new Set<string>();
  // 复选框区拖选会话（FR-014）：null=未在拖选；方向性扫选模式按下时锁定，同次拖动不反转
  private sweepSession: SweepSession | null = null;
  // 整行拖选会话（US1）：null=未在拖选；与 sweepSession 单指手势互斥，新建另一方时先清本方
  private rowDrag: RowDragSession | null = null;
  // 边缘自动滚动器（FR-018）：拖选中手指进入列表可视区边缘带时驱动列表滚动续扫
  private edgeScroller: EdgeAutoScroller = new EdgeAutoScroller();
  private seenBefore: number = 0;         // 进入时的 lastSeenAt，NEW 徽标基准
  private olderPage: number = 1;          // 已加载的最大页号（sortReverse 语义）
  private olderFailAt: number = 0;        // 加载更早失败时间戳：冷却期内禁止重试（US2）
  // Web 降级链已成功取过的最大页号：起始页按列表长度对齐页界推算，此值兜底防跳条重复
  private upWebLastPage: number = 0;
  // 最近一次触底页的实际来源：APP 链稀疏（服务端钳 ps 至 20），仅 Web 链短页才是权威到底
  private upOlderViaWeb: boolean = false;
  @Local sub: Subscription = new Subscription();
  // 已播集契约同 selectedKeys：V2 @Local 赋值观测不观测 Set 内部变更，整体换引用驱动行上标记即时刷新
  @Local playedSet: Set<string> = new Set<string>();
  // 数据源异常集（v0.5-part5）：随 playedSet 同点从 controller.anomalySet 拷贝，行上 X 标记
  @Local anomalySet: Set<string> = new Set<string>();
  // 长按守卫（FR-009）：堵长按后的回退 onClick，三处多选统一模式
  private longPressGuard: LongPressGuard = new LongPressGuard();
  private scroller: Scroller = new Scroller();
  private navPathStack: NavPathStack = new NavPathStack();
  private controller: PlayerController = PlayerController.getInstance();

  private typeLabel(): string {
    if (this.sub.type === Subscription.TYPE_UP) {
      return 'UP主';
    }
    if (this.sub.type === Subscription.TYPE_FAV) {
      return '收藏夹';
    }
    if (this.sub.type === Subscription.TYPE_SEASON) {
      return '合集';
    }
    return '系列';
  }

  // 源内总集数（接口 total/count 真值）优先；未知回退已加载数（近期一页 + 滚动追加）
  private headerCount(): number {
    return this.sub.totalCount > 0 ? this.sub.totalCount : this.episodeCount;
  }

  private isPlayed(item: BiliVideo): boolean {
    return this.playedSet.has(item.bvid);
  }

  private isNew(item: BiliVideo): boolean {
    return this.seenBefore > 0 && item.pubdate > this.seenBefore;
  }

  // 进出多选统一入口（FR-005）：全链路（行首勾选框宽度/透明度、顶栏双态、底部操作条）
  // 随同一 animateTo 翻转 selectMode 驱动，进出同入口天然互逆；区间选择态与锚点进出时全量重置
  private enterSelectMode(preselect: string): void {
    if (this.selectMode) {
      return;
    }
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.selectMode = true;
      if (preselect !== '') {
        this.selectedKeys = new Set<string>([preselect]);
      }
    });
  }

  private exitSelectMode(): void {
    if (!this.selectMode) {
      return;
    }
    this.endSweep();
    this.endRowDrag();
    this.getUIContext().animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.selectMode = false;
      this.selectedKeys = new Set<string>();
    });
  }

  private toggleSelect(bvid: string): void {
    this.selectedKeys = SelectLogic.toggle(this.selectedKeys, bvid);
  }

  // 复选框区拖选（FR-014/FR-018）：方向性扫选——按下采样起点行选中态锁定加/减扫模式，
  // 按等高步长换算目标行，起点→目标区间按锁定模式整体 Set 换引用；
  // 手指进入列表边缘带时自动滚动续扫，订阅源触底照常触发加载更早（索引稳定，新载入行可被继续拖选）
  private sweepStep(): number {
    return Constants.EPISODE_THUMB_H + 2 * Constants.TOKEN_SPACE_10 + Constants.TOKEN_SPACE_XS;
  }

  private startSweep(index: number, event: GestureEvent): void {
    if (index < 0 || index >= this.episodes.length) {
      return;
    }
    // 整行拖选与扫选单指互斥：扫选起手即作废可能残留的整行会话
    this.rowDrag = null;
    this.sweepSession = new SweepSession();
    this.sweepSession.begin(this.selectedKeys.has(this.episodes[index].bvid), index,
      event.fingerList[0].globalY, this.scroller.currentOffset().yOffset);
    this.applySweepRange(index, index);
  }

  private updateSweep(globalY: number): void {
    if (this.sweepSession === null) {
      return;
    }
    const delta: number = this.sweepSession.delta(globalY, this.scroller.currentOffset().yOffset);
    const start: number = this.sweepSession.getStartIndex();
    const target: number = Math.max(0, Math.min(this.episodes.length - 1,
      start + Math.round(delta / this.sweepStep())));
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
      const bvid: string = this.episodes[i].bvid;
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
  // 普通态长按同时进多选（翻转即预选）；ForEach 闭包 index 传递，越界守卫容忍触底加载后的行号漂移
  private beginRowDrag(index: number, event: GestureEvent): void {
    if (index < 0 || index >= this.episodes.length) {
      return;
    }
    const bvid: string = this.episodes[index].bvid;
    const snapshot: Set<string> = new Set<string>(this.selectedKeys);
    const paintAdd: boolean = !snapshot.has(bvid);
    if (!this.selectMode) {
      this.enterSelectMode('');
    }
    this.selectedKeys = SelectLogic.toggle(snapshot, bvid);
    this.endSweep();
    this.rowDrag = new RowDragSession(
      (i: number): string => this.rowKeyAt(i),
      (s: Set<string>): void => {
        this.selectedKeys = s;
      }
    );
    this.rowDrag.begin(index, paintAdd, snapshot,
      event.fingerList[0].globalY, this.scroller.currentOffset().yOffset);
  }

  private rowKeyAt(i: number): string {
    if (i < 0 || i >= this.episodes.length) {
      return '';
    }
    return this.episodes[i].bvid;
  }

  private updateRowDrag(globalY: number): void {
    if (this.rowDrag === null) {
      return;
    }
    const delta: number = this.rowDrag.delta(globalY, this.scroller.currentOffset().yOffset);
    const start: number = this.rowDrag.getStartIndex();
    const target: number = Math.max(0, Math.min(this.episodes.length - 1,
      start + Math.round(delta / this.sweepStep())));
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

  // 尽头检测（US1 FR-003/FR-004）：顶部零偏移；底部 isAtEnd 且无可加载更早才算尽头——
  // canLoadOlder 时滚轮保持空转 tick，触底 onReachEnd 照常触发加载更早，新行追加后自然续滚续选
  private edgeAtEnd(downward: boolean): boolean {
    if (downward) {
      return this.scroller.isAtEnd() && !this.canLoadOlder;
    }
    return this.scroller.currentOffset().yOffset <= 0;
  }

  private startEdgeScroll(downward: boolean): void {
    this.edgeScroller.start(this.scroller, downward, (): void => {
      if (this.rowDrag !== null) {
        this.updateRowDrag(this.rowDrag.getLastGlobalY());
      } else {
        this.updateSweep(this.sweepSession === null ? 0 : this.sweepSession.getLastGlobalY());
      }
    }, (down: boolean): boolean => this.edgeAtEnd(down));
  }

  // 按列表序取选中剧集批量入队（US2）：复用 loadPlaylistAndPlay 全语义（空队列起播/非空追加
  // 不打断/复合键去重），toast 分型反馈，完成后退出多选清空集合
  private enqueueSelected(): void {
    if (this.selectedKeys.size === 0) {
      return;
    }
    const items: BiliVideo[] = [];
    for (let i = 0; i < this.episodes.length; i++) {
      if (this.selectedKeys.has(this.episodes[i].bvid)) {
        items.push(this.episodes[i]);
      }
    }
    this.controller.loadPlaylistAndPlay(items, 0)
      .then((result: EnqueueResult): void => {
        this.getUIContext().getPromptAction().showToast({ message: PlayerController.enqueueToast(result) });
        this.exitSelectMode();
      })
      .catch((): void => {
        this.exitSelectMode();
      });
  }

  // 标记已看完（FR-007）：二次确认（N 动态替换）→ markWatched 批量写本地历史（bvid 级幂等，仅本地）→
  // 重载已播集驱动行上标记立即可见 → toast → 退出多选；取消确认留在多选态无副作用
  private confirmMarkWatched(): void {
    const count: number = this.selectedKeys.size;
    if (count === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: Constants.DIALOG_MARK_WATCHED_TITLE,
      message: Constants.DIALOG_MARK_WATCHED_MSG.replace('N', `${count}`),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '标记',
        action: (): void => {
          const items: BiliVideo[] = [];
          for (let i = 0; i < this.episodes.length; i++) {
            if (this.selectedKeys.has(this.episodes[i].bvid)) {
              items.push(this.episodes[i]);
            }
          }
          this.controller.markWatched(items);
          this.loadPlayedSet();
          this.getUIContext().getPromptAction().showToast({ message: Constants.TOAST_MARK_WATCHED.replace('N', `${count}`) });
          this.exitSelectMode();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  private loadFromCache(): void {
    // 缓存本身即新→旧（SubscriptionStore 刷新时按 pubdate 倒序落盘），直接按缓存顺序渲染
    const cached: BiliVideo[] = SubscriptionStore.loadEpisodes(this.sub.id);
    this.episodes = cached.slice();
    this.episodeCount = this.episodes.length;
    this.olderPage = 1;
    this.upWebLastPage = 0;
    // 触底门槛按类型区分：
    // - UP/FAV：只要缓存非空即允许触底尝试（UP 的 APP 链服务端钳 ps 至 20 致短页假到底，
    //   Web 降级链无游标无法预知总页数；FAV 刷新只抓第一页且过滤失效视频，短页是正常现象）
    // - SEASON/SERIES：缓存达满页才可能有更早内容，短页即已到最早
    if (this.sub.type === Subscription.TYPE_FAV || this.sub.type === Subscription.TYPE_UP) {
      this.canLoadOlder = cached.length > 0;
    } else {
      this.canLoadOlder = cached.length >= this.olderPageSize();
    }
  }

  // 各类型翻页接口的单页大小（FAV 不走此门槛/终止规则，见 loadFromCache/loadOlder）
  private olderPageSize(): number {
    if (this.sub.type === Subscription.TYPE_UP) {
      return Constants.UP_PAGE_SIZE;
    }
    if (this.sub.type === Subscription.TYPE_SEASON) {
      return Constants.SEASON_PAGE_SIZE;
    }
    return 30;
  }

  // FR-009 数据路径兜底：合集/系列剧集接口上游不返回作者（biliRelay 实测），剧集缓存/刷新回填不可行；
  // 存量订阅 upperName 为空时经 ownerMid → fetchUpInfo（acc/info→card 降级链）拉取并持久化，失败下次进入再试
  private backfillUpperName(): void {
    if (this.sub.type !== Subscription.TYPE_SEASON && this.sub.type !== Subscription.TYPE_SERIES) {
      return;
    }
    if (this.sub.upperName !== '' || this.sub.ownerMid <= 0) {
      return;
    }
    BiliService.fetchUpInfo(this.sub.ownerMid).then((info: UpInfo): void => {
      if (info.name === '') {
        return;
      }
      this.sub.upperName = info.name;
      SubscriptionStore.persistRefreshedSub(this.sub, true);
    }).catch((): void => {
    });
  }

  private markSeen(): void {
    this.seenBefore = this.sub.lastSeenAt;
    const subs: Subscription[] = SubscriptionStore.loadSubscriptions();
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === this.sub.id) {
        subs[i].lastSeenAt = Math.floor(Date.now() / 1000);
        this.sub.lastSeenAt = subs[i].lastSeenAt;
        break;
      }
    }
    SubscriptionStore.saveSubscriptions(subs);
  }

  // 读内存真相源（controller.playHistory，FR-011）：markWatched 同步更新该数组，
  // 异步落盘与同步读文件的竞态致已播标记不出现的问题随之消除
  private loadPlayedSet(): void {
    const played: Set<string> = new Set<string>();
    const hist: PlayHistoryItem[] = this.controller.playHistory;
    for (let i = 0; i < hist.length; i++) {
      // 哨兵 -1 = 已听完；中途条目（progress>0）不算已播
      if (hist[i].progress === -1) {
        played.add(hist[i].bvid);
      }
    }
    this.playedSet = played;
    this.anomalySet = new Set<string>(this.controller.anomalySet);
  }

  private refreshSource(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    SubscriptionStore.refreshSubscription(this.sub).then((): void => {
      SubscriptionStore.persistRefreshedSub(this.sub, true);
      this.loadFromCache();
      this.refreshing = false;
      this.getUIContext().getPromptAction().showToast({ message: Constants.TOAST_REFRESHED });
      // 刷新完成后回到顶部，与「新在上」列表语义一致
      if (this.episodes.length > 0) {
        this.scroller.scrollToIndex(0);
      }
    }).catch((err: BusinessError): void => {
      this.refreshing = false;
      this.getUIContext().getPromptAction().showToast({ message: `刷新失败: ${err.message}` });
    });
  }

  // 触底加载更早：四类订阅统一分派（页号越大越老），只进内存不写缓存。
  // 失败进入 3 秒冷却（LOAD_OLDER_FAIL_COOLDOWN_MS）：ArkUI onReachEnd 在按住底端时每帧重触发，
  // 冷却窗口物理上杜绝链式重试打爆风控
  private loadOlder(): void {
    if (this.loadingOlder || !this.canLoadOlder) {
      return;
    }
    if (Date.now() - this.olderFailAt < Constants.LOAD_OLDER_FAIL_COOLDOWN_MS) {
      return;
    }
    this.loadingOlder = true;
    const nextPage: number = this.olderPage + 1;
    this.fetchOlderPage(nextPage).then((page: BiliVideo[]): void => {
      if (page.length === 0) {
        this.canLoadOlder = false;
        this.loadingOlder = false;
        return;
      }
      // 追加前按 bvid 去重：防刷新链与翻页链排序漂移产生重复条目
      const known: Set<string> = new Set<string>();
      for (let i = 0; i < this.episodes.length; i++) {
        known.add(this.episodes[i].bvid);
      }
      const fresh: BiliVideo[] = [];
      for (let i = 0; i < page.length; i++) {
        if (!known.has(page[i].bvid)) {
          fresh.push(page[i]);
          known.add(page[i].bvid);
        }
      }
      this.olderPage = nextPage;
      if (fresh.length > 0) {
        // 翻页链与缓存链排序基准可能漂移，追加后整体按发布时间降序重排，防乱序跳条
        this.episodes = this.episodes.concat(fresh);
        this.episodes.sort((a: BiliVideo, b: BiliVideo): number => b.pubdate - a.pubdate);
        this.episodeCount = this.episodes.length;
      }
      if (this.sub.type === Subscription.TYPE_FAV) {
        // FAV：失效视频过滤致短页是正常现象，不按短页终止；
        // 仅当整页全部重复（已翻到刷新链缓存过的内容）时判定到底
        if (fresh.length === 0) {
          this.canLoadOlder = false;
        }
      } else if (this.sub.type === Subscription.TYPE_UP) {
        // UP：APP 签名链稀疏（服务端钳 ps=20），其短页/游标耗尽不是真到底，续走 Web 链；
        // 仅 Web 链短页（Web 为完整权威链）才判定没有更多
        if (this.upOlderViaWeb && page.length < this.olderPageSize()) {
          this.canLoadOlder = false;
        }
      } else {
        // SEASON/SERIES：短页（< 页大小）即已到最早内容
        if (page.length < this.olderPageSize()) {
          this.canLoadOlder = false;
        }
      }
      this.loadingOlder = false;
    }).catch((err: BusinessError): void => {
      this.loadingOlder = false;
      this.olderFailAt = Date.now();
      this.getUIContext().getPromptAction().showToast({ message: `加载失败: ${err.message}` });
    });
  }

  // 各类型按页号取一页更早内容：UP/FAV 的 mid/mediaId 在 sourceId（ownerMid 仅合集/系列有值，
  // UP 订阅传 ownerMid 会得到 mid=0 → 三端点全失败 -400/-799）；SEASON/SERIES sortReverse 倒序翻页
  private fetchOlderPage(pn: number): Promise<BiliVideo[]> {
    if (this.sub.type === Subscription.TYPE_UP) {
      return this.fetchUpOlderPage();
    }
    if (this.sub.type === Subscription.TYPE_FAV) {
      return BiliService.fetchFolderVideosByPage(this.sub.sourceId, pn);
    }
    if (this.sub.type === Subscription.TYPE_SEASON) {
      return BiliService.fetchSeasonVideos(this.sub.ownerMid, this.sub.sourceId, pn, true);
    }
    return BiliService.fetchSeriesVideos(this.sub.ownerMid, this.sub.sourceId, pn, true);
  }

  // UP 触底翻页：APP 签名链 cursor 优先（aid=当前列表末条），失败或无游标降级 Web 链。
  // Web 起始页按当前列表长度对齐 ps=UP_PAGE_SIZE 页界推算，upWebLastPage 兜底（全重复页也能前进，防死循环）
  // 无游标（进程重启+TTL 内跳过刷新）时先用 APP 主干重建游标再续翻 older；重建后仍无游标才降级 Web
  private fetchUpOlderPage(rebuilt: boolean = false): Promise<BiliVideo[]> {
    const mid: number = this.sub.sourceId;
    if (!BiliService.hasUpAppCursor(mid)) {
      if (rebuilt) {
        return this.fetchUpWebOlder(mid);
      }
      return BiliService.fetchUpVideos(mid).then(
        (): Promise<BiliVideo[]> => this.fetchUpOlderPage(true));
    }
    const lastAid: number = this.episodes.length > 0 ? this.episodes[this.episodes.length - 1].aid : 0;
    return BiliService.fetchUpVideosOlder(mid, lastAid).then((page: BiliVideo[]): BiliVideo[] => {
      this.upOlderViaWeb = false;
      return page;
    }).catch(
      (): Promise<BiliVideo[]> => this.fetchUpWebOlder(mid));
  }

  private fetchUpWebOlder(mid: number): Promise<BiliVideo[]> {
    this.upOlderViaWeb = true;
    const pn: number = Math.max(Math.floor(this.episodes.length / this.olderPageSize()) + 1,
      this.upWebLastPage + 1);
    // pn=1 走纯 Web 头页：fetchUpVideosByPage(1) 内部先重试 APP 链，会使链路来源标记失真
    const request: Promise<BiliVideo[]> = pn === 1
      ? BiliService.fetchUpWebHead(mid)
      : BiliService.fetchUpVideosByPage(mid, pn);
    return request.then((page: BiliVideo[]): BiliVideo[] => {
      if (page.length > 0 && pn > this.upWebLastPage) {
        this.upWebLastPage = pn;
      }
      return page;
    });
  }

  // 入队 + toast 分型反馈（queue-redesign：已加入队列/开始播放/已在队列中）
  private enqueueAndToast(items: BiliVideo[]): void {
    this.controller.loadPlaylistAndPlay(items, 0)
      .then((result: EnqueueResult): void => {
        this.getUIContext().getPromptAction().showToast({ message: PlayerController.enqueueToast(result) });
      })
      .catch((): void => {
      });
  }

  private playEpisode(index: number): void {
    // US6：点单集仅把该集作为队列播放（与「全部播放」整季连播区分），避免误触发整季连播；
    // 多P 视频经 fetchVideoDetail 展开全部分P 入队（追加不打断，列表行保持视频级展示），
    // 拉取失败回退占位条目（起播时惰性展开兜底）
    const episode: BiliVideo = this.episodes[index];
    BiliService.fetchVideoDetail(episode.bvid).then((detail: VideoDetail): void => {
      this.enqueueAndToast(detail.parts);
    }).catch((): void => {
      this.enqueueAndToast([episode]);
    });
  }

  private unsubscribe(): void {
    this.getUIContext().showAlertDialog({
      title: '取消订阅',
      message: `确定取消订阅「${this.sub.displayTitle()}」吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消订阅',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          const subs: Subscription[] = SubscriptionStore.loadSubscriptions();
          for (let i = 0; i < subs.length; i++) {
            if (subs[i].id === this.sub.id) {
              subs.splice(i, 1);
              break;
            }
          }
          SubscriptionStore.removeEpisodes(this.sub.id);
          SubscriptionStore.saveSubscriptions(subs);
          this.navPathStack.pop();
        }
      },
      secondaryButton: {
        value: '保留',
        action: (): void => {
        }
      }
    });
  }

  // 多选底部独立悬浮按钮（FR-016）：不可见全宽 Row 承载两枚独立胶囊——左「标记已看完」
  // （card 底 + text_primary）/ 右「加入队列 (N)」（accent 底 + fg_on_dark，主按钮）；
  // 无选中共享禁用（opacity 降档 + enabled false）；bottom 避让 MiniPlayer 与导航区；
  // 各自底边滑入滑出过渡，随 selectMode 同一 animateTo 驱动（进出互逆）
  @Builder
  private selectActionBar() {
    Row() {
      Text('标记已看完')
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .padding({
          left: Constants.TOKEN_SPACE_XL,
          right: Constants.TOKEN_SPACE_XL,
          top: Constants.TOKEN_SPACE_M,
          bottom: Constants.TOKEN_SPACE_M
        })
        .borderRadius(Constants.TOKEN_RADIUS_XXL)
        .backgroundColor($r('app.color.card_background'))
        .shadow({
          radius: Constants.TOKEN_FLOATING_SHADOW_RADIUS,
          color: $r('app.color.shadow_ball'),
          offsetX: 0,
          offsetY: Constants.TOKEN_FLOATING_SHADOW_OFFSET_Y
        })
        .opacity(this.selectedKeys.size > 0 ? 1 : Constants.TOKEN_DISABLED_OPACITY)
        .animation({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut })
        .enabled(this.selectedKeys.size > 0)
        .onClick(() => {
          this.confirmMarkWatched();
        })
        .transition(TransitionEffect.move(TransitionEdge.START).combine(TransitionEffect.OPACITY))
      Text(`加入队列 (${this.selectedKeys.size})`)
        .fontSize(Constants.TOKEN_FONT_BODY_M)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.fg_on_dark'))
        .padding({
          left: Constants.TOKEN_SPACE_XL,
          right: Constants.TOKEN_SPACE_XL,
          top: Constants.TOKEN_SPACE_M,
          bottom: Constants.TOKEN_SPACE_M
        })
        .borderRadius(Constants.TOKEN_RADIUS_XXL)
        .backgroundColor(this.accentColor.value)
        .shadow({
          radius: Constants.TOKEN_FLOATING_SHADOW_RADIUS,
          color: $r('app.color.shadow_ball'),
          offsetX: 0,
          offsetY: Constants.TOKEN_FLOATING_SHADOW_OFFSET_Y
        })
        .opacity(this.selectedKeys.size > 0 ? 1 : Constants.TOKEN_DISABLED_OPACITY)
        .animation({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut })
        .enabled(this.selectedKeys.size > 0)
        .onClick(() => {
          this.enqueueSelected();
        })
        .transition(TransitionEffect.move(TransitionEdge.END).combine(TransitionEffect.OPACITY))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
    .margin({ bottom: Constants.MINI_PLAYER_CLEARANCE + this.navBarHeight.value })
  }

  // 标题栏双态（FR-001/FR-002）：系统返回钮样式不可定制，hideBackButton 后经自定义 title 重建；
  // Stack 承载两态 Row 条件渲染 + OPACITY 过渡交叉淡化（进出多选同 animateTo 驱动）——
  // 常规态：返回卡 + 标题 + 多选图标卡（episodeCount===0 不渲染）+ ··· 卡；
  // 多选态：取消卡（xmark 替换返回位）+ 居中「已选 N 项」，···/刷新/退订不可达；
  // 返回卡/取消卡均 36×36 圆卡（对齐设置页/日志页）；placement 显式 BottomRight
  // （默认 BottomLeft 会从左上角展开）；自控 Row 不依赖框架 menus 布局
  @Builder
  private sourceTitleBuilder() {
    Stack() {
      if (!this.selectMode) {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(Constants.GLASS_ICON_BTN_SIZE)
          .height(Constants.GLASS_ICON_BTN_SIZE)
          .borderRadius(Constants.TOKEN_RADIUS_18)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            if (!dismissOverlaysForBack()) {
              this.navPathStack.pop();
            }
          })

          Text(this.navTitle)
            .fontSize(Constants.TOKEN_FONT_24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: Constants.TOKEN_SPACE_10 })

          if (this.episodeCount > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.list_checkmark'))
                .fontSize(Constants.TOKEN_FONT_TITLE_L)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(Constants.TOKEN_ICON_BTN)
            .height(Constants.TOKEN_ICON_BTN)
            .borderRadius(Constants.TOKEN_RADIUS_XL)
            .backgroundColor($r('app.color.card_background'))
            .justifyContent(FlexAlign.Center)
            .margin({ left: Constants.TOKEN_SPACE_M })
            .onClick(() => {
              this.enterSelectMode('');
            })
          }

          Row() {
            if (this.refreshing) {
              LoadingProgress()
                .width(Constants.TOKEN_FONT_TITLE_L)
                .height(Constants.TOKEN_FONT_TITLE_L)
                .color(this.accentColor.value)
            } else {
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(Constants.TOKEN_FONT_TITLE_L)
                .fontColor([$r('app.color.text_primary')])
                .bindMenu([
                  {
                    value: '刷新',
                    action: (): void => {
                      this.refreshSource();
                    }
                  },
                  {
                    value: '取消订阅',
                    action: (): void => {
                      this.unsubscribe();
                    }
                  }
                ], { placement: Placement.BottomRight })
            }
          }
          .width(Constants.TOKEN_ICON_BTN)
          .height(Constants.TOKEN_ICON_BTN)
          .borderRadius(Constants.TOKEN_RADIUS_XL)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .margin({ left: Constants.TOKEN_SPACE_M })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY)
      }
      if (this.selectMode) {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(Constants.TOKEN_FONT_TITLE_L)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(Constants.GLASS_ICON_BTN_SIZE)
          .height(Constants.GLASS_ICON_BTN_SIZE)
          .borderRadius(Constants.TOKEN_RADIUS_18)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.exitSelectMode();
          })

          Text(`已选 ${this.selectedKeys.size} 项`)
            .fontSize(Constants.TOKEN_FONT_24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .margin({ left: Constants.TOKEN_SPACE_10 })

          Row()
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .margin({ left: Constants.TOKEN_SPACE_10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .alignContent(Alignment.Center)
    .margin({ top: Constants.TOKEN_SPACE_10 })
    .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_M })
  }

  // 页头（US3 FR-008/009/010）：List 首个 ListItem 随列表滚动离屏/回顶再现；
  // 水平 padding 与剧集行同令牌（List S + 行 M），封面左缘与剧集缩略图对齐；
  // 名称大字（displayTitle，合集·前缀已剥）+ 集数同行右对齐 + 标签行（类型胶囊 + UP 主）；
  // 收藏夹不渲染 UP 主行（FR-009），胶囊为 accent 淡底内联实现（单使用点不抽组件）
  @Builder
  private headerRow() {
    Row() {
      CoverThumb({ cover: this.sub.cover, thumbSize: Constants.SOURCE_HEADER_H, radius: Constants.TOKEN_RADIUS_14 })
      Column() {
        Row() {
          Text(this.sub.displayTitle())
            .fontSize(Constants.TOKEN_FONT_20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${this.headerCount()} 集`)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_disabled'))
            .margin({ left: Constants.TOKEN_SPACE_S })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Row({ space: Constants.TOKEN_SPACE_S }) {
          Text(this.typeLabel())
            .fontSize(Constants.TOKEN_FONT_BODY_S)
            .fontColor(this.accentColor.value)
            .padding({
              left: Constants.TOKEN_SPACE_S,
              right: Constants.TOKEN_SPACE_S,
              top: Constants.TOKEN_SPACE_XXS,
              bottom: Constants.TOKEN_SPACE_XXS
            })
            .backgroundColor(Appearance.hexWithAlpha(this.accentColor.value, 0.12))
            .borderRadius(Constants.TOKEN_RADIUS_S)
          if ((this.sub.type === Subscription.TYPE_SEASON || this.sub.type === Subscription.TYPE_SERIES) &&
            this.sub.upperName !== '') {
            Text(this.sub.upperName)
              .fontSize(Constants.TOKEN_FONT_BODY_S)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .margin({ top: Constants.TOKEN_SPACE_XS })
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_S })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_XS, bottom: Constants.TOKEN_SPACE_10 })
  }

  build() {
    NavDestination() {
      if (this.episodeCount === 0) {
        Column() {
          this.headerRow()
          Column() {
            Text('暂无节目')
              .fontSize(Constants.TOKEN_FONT_BODY_L)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ left: Constants.TOKEN_SPACE_S, right: Constants.TOKEN_SPACE_S })
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          List({ space: Constants.TOKEN_SPACE_XS, scroller: this.scroller }) {
            ListItem() {
              this.headerRow()
            }
            ForEach(this.episodes, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  // 行首勾选框共用组件（FR-012/FR-013）：恒挂载容器宽度/透明度随 selectMode 动画，
                  // 行内容随容器宽度真实让位/回位（非 translate 位移），动画由 enter/exit 的 animateTo 驱动；
                  // 外包 Column 承载复选框区拖选手势（FR-014）：多选态手指在勾选框列上下拖动扫选，
                  // Pan 位移阈值内为点按（Checkbox onChange 切勾不冲突），行其余区域维持列表滚动
                  Column() {
                    SelectCheckbox({
                      active: this.selectMode,
                      selected: this.selectedKeys.has(item.bvid),
                      gap: Constants.TOKEN_SPACE_M,
                      onChange: (value: boolean): void => {
                        const inSet: boolean = this.selectedKeys.has(item.bvid);
                        if (value !== inSet) {
                          this.toggleSelect(item.bvid);
                        }
                      }
                    })
                  }
                  .gesture(
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical })
                      .onActionStart((event: GestureEvent): void => {
                        if (!this.selectMode || event.fingerList.length === 0) {
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
                        this.checkEdge(globalY);
                      })
                      .onActionEnd((): void => {
                        this.endSweep();
                      })
                      .onActionCancel((): void => {
                        this.endSweep();
                      })
                  )
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    CoverThumb({
                      cover: item.cover,
                      thumbWidth: Constants.EPISODE_THUMB_W,
                      thumbHeight: Constants.EPISODE_THUMB_H,
                      radius: Constants.TOKEN_RADIUS_M
                    })
                    if (item.duration > 0) {
                      Text(formatDuration(item.duration))
                        .fontSize(Constants.TOKEN_FONT_BODY_S)
                        .fontColor($r('app.color.fg_on_dark'))
                        .maxLines(1)
                        .padding({
                          left: Constants.TOKEN_SPACE_XXS,
                          right: Constants.TOKEN_SPACE_XXS,
                          top: Constants.TOKEN_SPACE_XXS,
                          bottom: Constants.TOKEN_SPACE_XXS
                        })
                        .margin(Constants.TOKEN_SPACE_XXS)
                        .borderRadius(Constants.TOKEN_RADIUS_S)
                        .backgroundColor($r('app.color.duration_badge_scrim'))
                        .shadow({
                          radius: Constants.DURATION_BADGE_SHADOW_RADIUS,
                          color: $r('app.color.duration_badge_scrim'),
                          offsetX: 0,
                          offsetY: Constants.DURATION_BADGE_SHADOW_OFFSET_Y
                        })
                    }
                  }
                  Column() {
                    Text(item.title)
                      .fontSize(Constants.TOKEN_FONT_BODY_L)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row() {
                      Text(formatDate(item.pubdate))
                        .fontSize(Constants.TOKEN_FONT_BODY_S)
                        .fontColor($r('app.color.text_disabled'))
                      Blank()
                      // 充电角标待定（WBI 风控未放行无法测试；注释保留，恢复=取消注释）
                      // if (item.isUpowerExclusive) {
                      //   Text('充电')
                      //     .fontSize(Constants.TOKEN_FONT_AUX)
                      //     .fontWeight(FontWeight.Bold)
                      //     .fontColor($r('app.color.gold_accent'))
                      // }
                      if (this.isNew(item)) {
                        Text('NEW')
                          .fontSize(Constants.TOKEN_FONT_AUX)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.accentColor.value)
                          .margin({ left: item.isUpowerExclusive ? Constants.TOKEN_SPACE_S : 0 })
                      }
                      if (this.isPlayed(item)) {
                        SymbolGlyph($r('sys.symbol.checkmark_circle'))
                          .fontSize(Constants.TOKEN_FONT_TITLE)
                          .fontColor([$r('app.color.success_green')])
                          .margin({ left: this.isNew(item) || item.isUpowerExclusive ? Constants.TOKEN_SPACE_S : 0 })
                      }
                      if (this.anomalySet.has(item.bvid)) {
                        SymbolGlyph($r('sys.symbol.xmark_circle'))
                          .fontSize(Constants.TOKEN_FONT_TITLE)
                          .fontColor([$r('app.color.danger_red')])
                          .margin({ left: this.isNew(item) || this.isPlayed(item) ? Constants.TOKEN_SPACE_S : 0 })
                      }
                    }
                    .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .justifyContent(FlexAlign.SpaceBetween)
                  .height(Constants.EPISODE_THUMB_H)
                  .layoutWeight(1)
                  .margin({ left: Constants.TOKEN_SPACE_M })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
                .borderRadius(Constants.TOKEN_RADIUS_14)
                .backgroundColor(this.pressedKey === item.bvid ? $r('app.color.item_pressed_background') : $r('app.color.card_background'))
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.longPressGuard.reset();
                    this.pressedKey = item.bvid;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => {
                  if (this.longPressGuard.shouldSuppressClick()) {
                    return;
                  }
                  if (this.selectMode) {
                    this.toggleSelect(item.bvid);
                  } else {
                    this.playEpisode(index);
                  }
                })
                // 整行拖选（US1 D2）：Sequence(长按→拖) 常挂两态——普通竖滑未长按不触发归列表滚动；
                // 长按翻转起点行进多选/切选，随后拖动区间涂刷（双向画笔，多选态长按已选行起拖为减扫）；
                // 长按事件取不到触点时回退纯多选预选（不建会话）
                .gesture(
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture()
                      .onAction((event?: GestureEvent) => {
                        this.longPressGuard.arm();
                        if (event === undefined || event.fingerList.length === 0) {
                          if (!this.selectMode) {
                            this.enterSelectMode(item.bvid);
                          }
                          return;
                        }
                        this.beginRowDrag(index, event);
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
            }, (item: BiliVideo) => item.bvid)
            if (this.loadingOlder) {
              ListItem() {
                Row() {
                  LoadingProgress()
                    .width(Constants.TOKEN_FONT_18)
                    .height(Constants.TOKEN_FONT_18)
                    .color($r('app.color.text_secondary'))
                  Text('加载中...')
                    .fontSize(Constants.TOKEN_FONT_BODY)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: Constants.TOKEN_SPACE_6 })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: Constants.TOKEN_SPACE_6, bottom: Constants.TOKEN_SPACE_6 })
              }
            }
            if (!this.canLoadOlder) {
              ListItem() {
                Text('没有更多了')
                  .fontSize(Constants.TOKEN_FONT_BODY)
                  .fontColor($r('app.color.text_disabled'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: Constants.TOKEN_SPACE_6, bottom: Constants.TOKEN_SPACE_6 })
              }
            }
            }
            .width('100%')
            .height('100%')
            .id(SWEEP_LIST_ID)
            .padding({ left: Constants.TOKEN_SPACE_S, right: Constants.TOKEN_SPACE_S, top: Constants.TOKEN_SPACE_XS })
            // MiniPlayer 悬浮化（FR-015）：底部 padding 是内容裁剪边界（内容不能从胶囊下划过的根因），
            // 改挂 contentEndOffset——视口延伸至屏底、内容滚动时从胶囊下方穿过（毛玻璃透出），
            // 滚到底最后一条完整露出在胶囊上方；多选悬浮按钮避让值不变（D18/D19 联动）
            .contentEndOffset(Constants.MINI_PLAYER_CLEARANCE + this.navBarHeight.value)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .onReachEnd(() => {
              this.loadOlder();
            })
            if (this.selectMode) {
              this.selectActionBar()
            }
          }
          .width('100%')
          .height('100%')
        }
      }
    .title(this.sourceTitleBuilder())
    .hideBackButton(true)
    .backgroundColor($r('app.color.page_background'))
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      if (ctx.pathInfo.param === undefined || ctx.pathInfo.param === null) {
        this.navPathStack.pop();
        return;
      }
      const subId: string = ctx.pathInfo.param as string;
      const subs: Subscription[] = SubscriptionStore.loadSubscriptions();
      for (let i = 0; i < subs.length; i++) {
        if (subs[i].id === subId) {
          this.sub = subs[i];
          break;
        }
      }
      if (this.sub.id === '') {
        this.navPathStack.pop();
        return;
      }
      this.navTitle = this.sub.displayTitle();
      this.markSeen();
      this.loadPlayedSet();
      this.backfillUpperName();
      this.loadFromCache();
    })
    .onHidden(() => {
      // US4/FR-008：源页退出（标题栏返回/系统返回/退订 pop 均触发 onHidden）通知首页重算——
      // pushPathByName 的 onPop 仅在 pop(result) 带 result 时才触发（SDK 语义），本应用全部
      // 无参 pop() 故永不回调，徽标返回首页不清除；改经 AppStorage tick 驱动 HomePage @Watch 重建
      connectNum(Constants.AS_HOME_REFRESH_TICK, 0).value = Date.now();
    })
    // 系统返回层序（FR-010）：先经 BackHandler 自上而下逐层退出（队列/历史多选与面板），
    // 返回 false 再动画退自身多选，最后放行默认 pop——多层多选同开时先退最上层
    .onBackPressed((): boolean => {
      if (dismissOverlaysForBack()) {
        return true;
      }
      if (this.selectMode) {
        this.exitSelectMode();
        return true;
      }
      return false;
    })
  }
}
