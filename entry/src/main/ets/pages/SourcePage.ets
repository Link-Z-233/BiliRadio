import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { BiliService } from '../service/BiliService';
import { AppStore } from '../service/AppStore';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { PlayerController, EnqueueResult } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';
import { EdgeHint } from '../component/EdgeHint';

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

// 源详情：剧集列表（新在上）/ NEW 徽标 / 已播标记 / 播放全部 / 刷新 / 取消订阅
// 四类订阅（UP/收藏夹/合集/系列）统一支持触底「加载更早」（按需翻页，只进内存不写缓存）
@Component
struct SourcePage {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @StorageProp('miniPlayerVisible') miniPlayerVisible: boolean = false; // key 与 Constants.AS_MINI_PLAYER_VISIBLE 对应
  @StorageProp('navBarHeight') navBarHeight: number = 0; // key 与 Constants.AS_NAV_BAR_HEIGHT 对应
  @State navTitle: string = '';
  @State episodes: BiliVideo[] = [];      // 展示序：倒序（新在上，与缓存一致）
  @State refreshing: boolean = false;
  @State canLoadOlder: boolean = false;
  @State loadingOlder: boolean = false;
  @State episodeCount: number = 0;
  // US5 过冲提示：顶部固定文案，底部与触底加载联动三态
  @State topHint: string = '';
  @State bottomHint: string = '';
  private seenBefore: number = 0;         // 进入时的 lastSeenAt，NEW 徽标基准
  private olderPage: number = 1;          // 已加载的最大页号（sortReverse 语义）
  private olderFailAt: number = 0;        // 加载更早失败时间戳：冷却期内禁止重试（US2）
  // Web 降级链已成功取过的最大页号：起始页按列表长度对齐页界推算，此值兜底防跳条重复
  private upWebLastPage: number = 0;
  // 最近一次触底页的实际来源：APP 链稀疏（服务端钳 ps 至 20），仅 Web 链短页才是权威到底
  private upOlderViaWeb: boolean = false;
  // 触底时刻的列表偏移（US5 底部过冲判定基准）；-1 = 未捕获，列表内容增删后失效须重捕
  private endOffsetY: number = -1;
  private dragging: boolean = false;
  private sub: Subscription = new Subscription();
  private playedSet: Set<string> = new Set();
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

  private subtitle(): string {
    if (this.sub.upperName !== '') {
      return `${this.typeLabel()} · ${this.sub.upperName}`;
    }
    return this.typeLabel();
  }

  private isPlayed(item: BiliVideo): boolean {
    return this.playedSet.has(item.bvid);
  }

  private isNew(item: BiliVideo): boolean {
    return this.seenBefore > 0 && item.pubdate > this.seenBefore;
  }

  private loadFromCache(): void {
    // 缓存本身即新→旧（SubscriptionStore 刷新时按 pubdate 倒序落盘），直接按缓存顺序渲染
    const cached: BiliVideo[] = SubscriptionStore.loadEpisodes(this.sub.id);
    this.episodes = cached.slice();
    this.episodeCount = this.episodes.length;
    this.olderPage = 1;
    this.upWebLastPage = 0;
    this.endOffsetY = -1;
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
    return this.sub.type === Subscription.TYPE_SEASON ? 20 : 30;
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

  private loadPlayedSet(): void {
    this.playedSet.clear();
    const hist: PlayHistoryItem[] = AppStore.loadPlayHistoryFile();
    for (let i = 0; i < hist.length; i++) {
      // 哨兵 -1 = 已听完；中途条目（progress>0）不算已播
      if (hist[i].progress === -1) {
        this.playedSet.add(hist[i].bvid);
      }
    }
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
      // 刷新完成后回到顶部，与「新在上」列表语义一致
      if (this.episodes.length > 0) {
        this.scroller.scrollToIndex(0);
      }
    }).catch((err: BusinessError): void => {
      this.refreshing = false;
      promptAction.showToast({ message: `刷新失败: ${err.message}` });
    });
  }

  // 底部过冲提示三态（FR-010）：加载中／没有更多／可加载（含失败冷却期）不显示
  private bottomHintText(): string {
    if (this.loadingOlder) {
      return '加载中…';
    }
    if (!this.canLoadOlder) {
      return '没有更多了';
    }
    return '';
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
        this.endOffsetY = -1;
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
      promptAction.showToast({ message: `加载失败: ${err.message}` });
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
  // Web 起始页按当前列表长度对齐 ps=30 页界推算，upWebLastPage 兜底（全重复页也能前进，防死循环）
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

  private playAll(): void {
    if (this.episodes.length === 0) {
      return;
    }
    this.controller.loadPlaylistAndPlay(this.episodes, 0);
  }

  private playEpisode(index: number): void {
    // US6：点单集仅把该集作为队列播放（与「全部播放」整季连播区分），避免误触发整季连播；
    // queue-redesign：入队结果 toast 分型反馈（已加入队列/开始播放/已在队列中）
    this.controller.loadPlaylistAndPlay([this.episodes[index]], 0)
      .then((result: EnqueueResult): void => {
        promptAction.showToast({ message: PlayerController.enqueueToast(result) });
      })
      .catch((): void => {
      });
  }

  private unsubscribe(): void {
    AlertDialog.show({
      title: '取消订阅',
      message: `确定取消订阅「${this.sub.title}」吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消订阅',
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

  build() {
    NavDestination() {
      Column() {
        Row() {
          CoverThumb({ cover: this.sub.cover, thumbSize: 56, radius: 14 })
          Column() {
            Text(this.subtitle())
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.episodeCount} 集`)
              .fontSize(12)
              .fontColor($r('app.color.text_disabled'))
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12, right: 8 })
          if (this.refreshing) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.accentColor)
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
              .onClick(() => {
                this.refreshSource();
              })
          }
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ left: 16 })
            .onClick(() => {
              this.unsubscribe();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })

        if (this.episodeCount > 0) {
          Row() {
            Text('播放全部')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor)
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor($r('app.color.card_background'))
          .margin({ left: 16, bottom: 8 })
          .onClick(() => {
            this.playAll();
          })
        }

        if (this.episodeCount === 0) {
          Column() {
            Text('暂无节目')
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Stack() {
            EdgeHint({ text: this.topHint, edge: 'top' })
            EdgeHint({ text: this.bottomHint, edge: 'bottom' })
            List({ space: 4, scroller: this.scroller }) {
            ForEach(this.episodes, (item: BiliVideo, index: number) => {
              ListItem() {
                Column() {
                  Text(item.title)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(formatDate(item.pubdate))
                      .fontSize(12)
                      .fontColor($r('app.color.text_disabled'))
                    if (item.duration > 0) {
                      Text(formatDuration(item.duration))
                        .fontSize(12)
                        .fontColor($r('app.color.text_disabled'))
                        .margin({ left: 10 })
                    }
                    Blank()
                    if (this.isNew(item)) {
                      Text('NEW')
                        .fontSize(11)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.accentColor)
                    }
                    if (this.isPlayed(item)) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle'))
                        .fontSize(16)
                        .fontColor([$r('app.color.success_green')])
                        .margin({ left: this.isNew(item) ? 8 : 0 })
                    }
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(14)
                .backgroundColor($r('app.color.card_background'))
                .onClick(() => {
                  this.playEpisode(index);
                })
              }
            }, (item: BiliVideo) => item.bvid)
            if (this.loadingOlder) {
              ListItem() {
                Row() {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color($r('app.color.text_secondary'))
                  Text('加载中...')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 6 })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 6, bottom: 6 })
              }
            }
            if (!this.canLoadOlder) {
              ListItem() {
                Text('没有更多了')
                  .fontSize(13)
                  .fontColor($r('app.color.text_disabled'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 6, bottom: 6 })
              }
            }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12) + this.navBarHeight })
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
              this.loadOlder();
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
                  this.bottomHint = this.bottomHintText();
                }
              }
            })
            .onScrollStop(() => {
              this.topHint = '';
              this.bottomHint = '';
              this.dragging = false;
            })
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.navTitle)
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
      this.navTitle = this.sub.title;
      this.markSeen();
      this.loadPlayedSet();
      this.loadFromCache();
    })
    .onHidden(() => {
      // US4/FR-008：源页退出（标题栏返回/系统返回/退订 pop 均触发 onHidden）通知首页重算——
      // pushPathByName 的 onPop 仅在 pop(result) 带 result 时才触发（SDK 语义），本应用全部
      // 无参 pop() 故永不回调，徽标返回首页不清除；改经 AppStorage tick 驱动 HomePage @Watch 重建
      AppStorage.setOrCreate<number>(Constants.AS_HOME_REFRESH_TICK, Date.now());
    })
  }
}
