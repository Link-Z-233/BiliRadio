import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { BiliService } from '../service/BiliService';
import { AppStore } from '../service/AppStore';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { PlayerController } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';

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
  return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`;
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
  @State navTitle: string = '';
  @State episodes: BiliVideo[] = [];      // 展示序：倒序（新在上，与缓存一致）
  @State refreshing: boolean = false;
  @State canLoadOlder: boolean = false;
  @State loadingOlder: boolean = false;
  @State episodeCount: number = 0;
  private seenBefore: number = 0;         // 进入时的 lastSeenAt，NEW 徽标基准
  private olderPage: number = 1;          // 已加载的最大页号（sortReverse 语义）
  private endArmed: boolean = true;       // 触底触发权：每次触摸手势（TouchType.Down）武装一次，加载一页即没收，
                                         // 抬手重新按下才归还——一次手势最多一页请求，防按住不放链式连发打爆风控
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
    this.endArmed = true;
    // 触底门槛按类型区分：
    // - UP：游标在（has_next=true）即有更早内容，缓存短页不算到底（服务端钳 ps 至 20）
    // - SEASON/SERIES：缓存达满页才可能有更早内容，短页即已到最早
    // - FAV：刷新只抓第一页且会过滤失效视频，缓存短页是正常现象，只要非空即允许触底尝试
    if (this.sub.type === Subscription.TYPE_FAV) {
      this.canLoadOlder = cached.length > 0;
    } else if (this.sub.type === Subscription.TYPE_UP) {
      this.canLoadOlder =
        cached.length >= this.olderPageSize() || BiliService.hasUpAppCursor(this.sub.sourceId);
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
      this.playedSet.add(hist[i].bvid);
    }
  }

  private refreshSource(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    SubscriptionStore.refreshSubscription(this.sub).then((): void => {
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

  // 触底加载更早：四类订阅统一分派（页号越大越老），只进内存不写缓存。
  // endArmed 触发权：一次触摸手势最多加载一页（TouchType.Down 武装，加载即没收）——
  // ArkUI onReachEnd 在按住底端时每帧重触发，且追加内容/移除指示器引发的 onScrollIndex 布局回调
  // 无法与真实滚离区分，故不采用"滚离归还"方案，改按手势武装，物理上杜绝链式连发打爆风控
  private loadOlder(): void {
    if (this.loadingOlder || !this.canLoadOlder || !this.endArmed) {
      return;
    }
    this.endArmed = false;
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
        // page 本身即新→旧序，直接追加到列表尾部
        this.episodes = this.episodes.concat(fresh);
        this.episodeCount = this.episodes.length;
      }
      if (this.sub.type === Subscription.TYPE_FAV) {
        // FAV：失效视频过滤致短页是正常现象，不按短页终止；
        // 仅当整页全部重复（已翻到刷新链缓存过的内容）时判定到底
        if (fresh.length === 0) {
          this.canLoadOlder = false;
        }
      } else if (this.sub.type === Subscription.TYPE_UP) {
        // UP：APP 签名链以服务端 has_next 为准（游标仍在则短页续翻，防服务端钳 ps 假到底）；
        // 游标已失（到底/链路失败降级 Web）时保持短页到底语义
        if (page.length < this.olderPageSize() && !BiliService.hasUpAppCursor(this.sub.sourceId)) {
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
      // 失败不归还触发权（防按住底端时 onReachEnd 每帧重试形成 403 风暴），
      // 重试 = 抬手后再次触摸滚动到底
      promptAction.showToast({ message: `加载失败: ${err.message}` });
    });
  }

  // 各类型按页号取一页更早内容：UP/FAV 的 mid/mediaId 在 sourceId（ownerMid 仅合集/系列有值，
  // UP 订阅传 ownerMid 会得到 mid=0 → 三端点全失败 -400/-799）；SEASON/SERIES sortReverse 倒序翻页
  private fetchOlderPage(pn: number): Promise<BiliVideo[]> {
    if (this.sub.type === Subscription.TYPE_UP) {
      return this.fetchUpOlderPage(pn);
    }
    if (this.sub.type === Subscription.TYPE_FAV) {
      return BiliService.fetchFolderVideosByPage(this.sub.sourceId, pn);
    }
    if (this.sub.type === Subscription.TYPE_SEASON) {
      return BiliService.fetchSeasonVideos(this.sub.ownerMid, this.sub.sourceId, pn, true);
    }
    return BiliService.fetchSeriesVideos(this.sub.ownerMid, this.sub.sourceId, pn, true);
  }

  // UP 触底翻页：APP 签名链 cursor 优先（aid=当前列表末条），失败降级 Web 同页号（ps 同为 30，页界对齐）
  private fetchUpOlderPage(pn: number): Promise<BiliVideo[]> {
    const mid: number = this.sub.sourceId;
    if (!BiliService.hasUpAppCursor(mid)) {
      return BiliService.fetchUpVideosByPage(mid, pn);
    }
    const lastAid: number = this.episodes.length > 0 ? this.episodes[this.episodes.length - 1].aid : 0;
    return BiliService.fetchUpVideosOlder(mid, lastAid).catch(
      (): Promise<BiliVideo[]> => BiliService.fetchUpVideosByPage(mid, pn));
  }

  private playAll(): void {
    if (this.episodes.length === 0) {
      return;
    }
    this.controller.loadPlaylistAndPlay(this.episodes, 0);
  }

  private playEpisode(index: number): void {
    // US6：点单集仅把该集作为队列播放（与「全部播放」整季连播区分），避免误触发整季连播
    this.controller.loadPlaylistAndPlay([this.episodes[index]], 0);
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
          List({ space: 4, scroller: this.scroller }) {
            ForEach(this.episodes, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(item.title)
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row() {
                      if (this.isPlayed(item)) {
                        SymbolGlyph($r('sys.symbol.checkmark_circle'))
                          .fontSize(13)
                          .fontColor([$r('app.color.text_disabled')])
                          .margin({ right: 4 })
                      }
                      Text(formatDate(item.pubdate))
                        .fontSize(12)
                        .fontColor($r('app.color.text_disabled'))
                      if (item.duration > 0) {
                        Text(formatDuration(item.duration))
                          .fontSize(12)
                          .fontColor($r('app.color.text_disabled'))
                          .margin({ left: 10 })
                      }
                    }
                    .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  if (this.isNew(item)) {
                    Text('NEW')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.accentColor)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
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
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12 })
          .layoutWeight(1)
          .onReachEnd(() => {
            this.loadOlder();
          })
          .onTouch((event: TouchEvent): void => {
            // 触底触发权按手势武装：手指按下（新拖拽开始）时归还，一次手势最多加载一页。
            // 不用 onScrollIndex 归还——追加内容/移除加载指示器引发的布局回调与真实滚离无法区分
            if (event.type === TouchType.Down) {
              this.endArmed = true;
            }
          })
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
  }
}
