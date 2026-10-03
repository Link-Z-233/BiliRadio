import { promptAction } from '@kit.ArkUI';
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

// 源详情：剧集列表（正序展示，老在上）/ NEW 徽标 / 已播置灰 / 播放全部 / 刷新 / 取消订阅
// season/series 支持向上「加载更早」（按需翻页，只进内存不写缓存）
@Component
struct SourcePage {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @StorageProp('miniPlayerVisible') miniPlayerVisible: boolean = false; // key 与 Constants.AS_MINI_PLAYER_VISIBLE 对应
  @State navTitle: string = '';
  @State episodes: BiliVideo[] = [];      // 展示序：正序（老在上）
  @State refreshing: boolean = false;
  @State canLoadOlder: boolean = false;
  @State loadingOlder: boolean = false;
  @State episodeCount: number = 0;
  private seenBefore: number = 0;         // 进入时的 lastSeenAt，NEW 徽标基准
  private olderPage: number = 1;          // 已加载的最大页号（sortReverse 语义）
  private sub: Subscription = new Subscription();
  private playedSet: Set<string> = new Set();
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
    const cached: BiliVideo[] = SubscriptionStore.loadEpisodes(this.sub.id);
    this.episodes = cached.slice().reverse();
    this.episodeCount = this.episodes.length;
    this.olderPage = 1;
    const paginated: boolean = this.sub.type === Subscription.TYPE_SEASON || this.sub.type === Subscription.TYPE_SERIES;
    this.canLoadOlder = paginated && cached.length > 0;
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
    }).catch((): void => {
      this.refreshing = false;
      promptAction.showToast({ message: '刷新失败，请稍后重试' });
    });
  }

  // 向上加载更早：season/series 按需翻页（sortReverse 倒序，页号越大越老），只进内存不写缓存
  private loadOlder(): void {
    if (this.loadingOlder || !this.canLoadOlder) {
      return;
    }
    this.loadingOlder = true;
    const nextPage: number = this.olderPage + 1;
    const task: Promise<BiliVideo[]> = this.sub.type === Subscription.TYPE_SEASON
      ? BiliService.fetchSeasonVideos(this.sub.ownerMid, this.sub.sourceId, nextPage, true)
      : BiliService.fetchSeriesVideos(this.sub.ownerMid, this.sub.sourceId, nextPage, true);
    task.then((page: BiliVideo[]): void => {
      if (page.length === 0) {
        this.canLoadOlder = false;
      } else {
        this.olderPage = nextPage;
        const older: BiliVideo[] = page.slice().reverse();
        this.episodes = older.concat(this.episodes);
        this.episodeCount = this.episodes.length;
        const ps: number = this.sub.type === Subscription.TYPE_SEASON ? 20 : 30;
        if (page.length < ps) {
          this.canLoadOlder = false;
        }
      }
      this.loadingOlder = false;
    }).catch((): void => {
      this.loadingOlder = false;
      promptAction.showToast({ message: '加载失败，请稍后重试' });
    });
  }

  private playAll(): void {
    if (this.episodes.length === 0) {
      return;
    }
    this.controller.loadPlaylistAndPlay(this.episodes, 0);
  }

  private playEpisode(index: number): void {
    this.controller.loadPlaylistAndPlay(this.episodes, index);
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

        if (this.loadingOlder) {
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
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .margin({ left: 16, bottom: 8 })
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
          List({ space: 4 }) {
            ForEach(this.episodes, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(item.title)
                      .fontSize(15)
                      .fontColor(this.isPlayed(item) ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
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
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12 })
          .layoutWeight(1)
          .onReachStart(() => {
            this.loadOlder();
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
