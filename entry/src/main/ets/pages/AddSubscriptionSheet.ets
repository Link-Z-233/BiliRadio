import { promptAction } from '@kit.ArkUI';
import { BiliService, UpInfo, SeasonMeta } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { Subscription } from '../model/Subscription';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Season } from '../model/Season';
import { FavFolder } from '../model/FavFolder';
import { PlayerController } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';

class RecognizeResult {
  type: string = '';
  id: string = '';
  ownerMid: string = '';
}

function recognizeInput(input: string): RecognizeResult {
  const r: RecognizeResult = new RecognizeResult();
  const trimmed: string = input.trim();
  if (trimmed === '') {
    return r;
  }
  let m: RegExpExecArray | null = new RegExp('BV[0-9A-Za-z]{10}').exec(trimmed);
  if (m !== null) {
    r.type = 'bv';
    r.id = m[0];
    return r;
  }
  m = new RegExp('space\\.bilibili\\.com/(\\d+)/lists/(\\d+)').exec(trimmed);
  if (m !== null) {
    r.ownerMid = m[1];
    r.id = m[2];
    r.type = new RegExp('type=series').test(trimmed) ? 'series' : 'season';
    return r;
  }
  m = new RegExp('seriesdetail\\?[^&]*sid=(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'series';
    r.id = m[1];
    const midM: RegExpExecArray | null = new RegExp('space\\.bilibili\\.com/(\\d+)').exec(trimmed);
    if (midM !== null) {
      r.ownerMid = midM[1];
    }
    return r;
  }
  m = new RegExp('collectiondetail\\?[^&]*sid=(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'season';
    r.id = m[1];
    const midM: RegExpExecArray | null = new RegExp('space\\.bilibili\\.com/(\\d+)').exec(trimmed);
    if (midM !== null) {
      r.ownerMid = midM[1];
    }
    return r;
  }
  m = new RegExp('(?:fid|media_id)=(\\d+)').exec(trimmed);
  if (m !== null && (trimmed.indexOf('fav') >= 0 || trimmed.indexOf('collection') >= 0 || trimmed.indexOf('favlist') >= 0)) {
    r.type = 'fav';
    r.id = m[1];
    return r;
  }
  m = new RegExp('space\\.bilibili\\.com/(\\d+)').exec(trimmed);
  if (m !== null) {
    r.type = 'up';
    r.id = m[1];
    return r;
  }
  m = new RegExp('^(\\d{5,})$').exec(trimmed);
  if (m !== null) {
    r.type = 'up';
    r.id = m[1];
    return r;
  }
  return r;
}

@Component
export struct AddSubscriptionSheet {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @State mainInput: string = '';
  @State mainBusy: boolean = false;
  @State mainMsg: string = '';
  @State uidInput: string = '';
  @State uidBusy: boolean = false;
  @State upInfo: UpInfo | null = null;
  @State upName: string = '';
  @State upFace: string = '';
  @State seasons: Season[] = [];
  @State series: Season[] = [];
  @State isLogged: boolean = false;
  @State folders: FavFolder[] = [];
  @State foldersBusy: boolean = false;
  @State folderView: boolean = false;
  onSubscribed: (sub: Subscription) => void = (sub: Subscription) => {
  };
  onDismiss: () => void = () => {
  };
  private controller: PlayerController = PlayerController.getInstance();

  aboutToAppear(): void {
    const session: BiliSession = BiliSession.getInstance();
    this.isLogged = session.isLogged();
    if (this.isLogged) {
      this.loadFolders();
    }
  }

  private loadFolders(): void {
    if (this.foldersBusy) {
      return;
    }
    this.foldersBusy = true;
    BiliService.fetchMyFolders().then((folders: FavFolder[]): void => {
      this.folders = folders;
      this.foldersBusy = false;
    }).catch((): void => {
      this.foldersBusy = false;
    });
  }

  private alreadySubscribed(id: string): boolean {
    const subs: Subscription[] = SubscriptionStore.loadSubscriptions();
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private emitSub(sub: Subscription): void {
    sub.id = Subscription.makeId(sub.type, sub.sourceId);
    if (this.alreadySubscribed(sub.id)) {
      promptAction.showToast({ message: '已订阅过该源' });
      return;
    }
    this.onSubscribed(sub);
    promptAction.showToast({ message: `已订阅「${sub.title}」` });
  }

  private handleMainInput(): void {
    const trimmed: string = this.mainInput.trim();
    if (trimmed.indexOf('b23.tv') >= 0) {
      if (this.mainBusy) {
        return;
      }
      this.mainBusy = true;
      this.mainMsg = '解析短链中…';
      BiliService.resolveShortUrl(trimmed).then((resolved: string): void => {
        this.mainBusy = false;
        this.mainMsg = '';
        const parsed: RecognizeResult = recognizeInput(resolved);
        if (parsed.type === '') {
          promptAction.showToast({ message: '短链解析后未识别到有效链接' });
          return;
        }
        this.mainInput = resolved;
        switch (parsed.type) {
          case 'bv':
            this.playBv(parsed.id);
            break;
          case 'up':
            this.lookupUid(parsed.id);
            break;
          case 'fav':
            this.subscribeFolderById(parsed.id);
            break;
          case 'season':
            this.subscribeSeasonById(parsed.id);
            break;
          case 'series':
            this.subscribeSeriesById(parsed.id);
            break;
          default:
            break;
        }
      }).catch((): void => {
        this.mainBusy = false;
        this.mainMsg = '';
        promptAction.showToast({ message: '短链解析失败' });
      });
      return;
    }
    const parsed: RecognizeResult = recognizeInput(this.mainInput);
    if (parsed.type === '') {
      promptAction.showToast({ message: '未识别到有效链接或ID' });
      return;
    }
    if (this.mainBusy) {
      return;
    }
    switch (parsed.type) {
      case 'bv':
        this.playBv(parsed.id);
        break;
      case 'up':
        this.lookupUid(parsed.id);
        break;
      case 'fav':
        this.subscribeFolderById(parsed.id);
        break;
      case 'season':
        this.subscribeSeasonById(parsed.id);
        break;
      case 'series':
        this.subscribeSeriesById(parsed.id);
        break;
      default:
        break;
    }
  }

  private playBv(bvid: string): void {
    if (this.mainBusy) {
      return;
    }
    this.mainBusy = true;
    this.controller.addToPlaylist(bvid).then((): void => {
      this.mainBusy = false;
      this.onDismiss();
      if (this.controller.goToPlayerTab !== undefined) {
        this.controller.goToPlayerTab();
      }
    }).catch((): void => {
      this.mainBusy = false;
    });
  }

  private lookupUid(uidStr: string): void {
    const uid: number = parseInt(uidStr, 10);
    if (isNaN(uid) || uid <= 0) {
      promptAction.showToast({ message: '请输入有效UID' });
      return;
    }
    if (this.uidBusy) {
      return;
    }
    this.uidBusy = true;
    this.upInfo = null;
    this.upName = '';
    this.upFace = '';
    this.seasons = [];
    this.series = [];
    BiliService.fetchUpInfo(uid).then((info: UpInfo): void => {
      this.upInfo = info;
      this.upName = info.name;
      this.upFace = info.face;
      this.uidBusy = false;
      this.mainBusy = false;
      BiliService.fetchSeasonsList(uid).then((seasons: Season[]): void => {
        this.seasons = seasons;
      }).catch((): void => {
      });
      BiliService.fetchSeriesList(uid).then((series: Season[]): void => {
        this.series = series;
      }).catch((): void => {
      });
    }).catch((): void => {
      this.uidBusy = false;
      this.mainBusy = false;
      promptAction.showToast({ message: '查询UP主失败，请稍后重试' });
    });
  }

  private subscribeUp(): void {
    const info: UpInfo | null = this.upInfo;
    if (info === null) {
      return;
    }
    const sub: Subscription = new Subscription();
    sub.type = Subscription.TYPE_UP;
    sub.sourceId = info.mid;
    sub.title = info.name;
    sub.cover = info.face;
    sub.upperName = info.name;
    this.emitSub(sub);
  }

  private subscribeSeason(s: Season): void {
    const info: UpInfo | null = this.upInfo;
    if (info === null) {
      return;
    }
    const sub: Subscription = new Subscription();
    sub.type = Subscription.TYPE_SEASON;
    sub.sourceId = s.seasonId;
    sub.ownerMid = info.mid;
    sub.title = s.title === '' ? `合集 ${s.seasonId}` : s.title;
    sub.cover = s.cover;
    this.emitSub(sub);
  }

  private subscribeSeries(s: Season): void {
    const info: UpInfo | null = this.upInfo;
    if (info === null) {
      return;
    }
    const sub: Subscription = new Subscription();
    sub.type = Subscription.TYPE_SERIES;
    sub.sourceId = s.seasonId;
    sub.ownerMid = info.mid;
    sub.title = s.title === '' ? `系列 ${s.seasonId}` : s.title;
    sub.cover = s.cover;
    this.emitSub(sub);
  }

  private subscribeFolderById(mediaIdStr: string): void {
    const mediaId: number = parseInt(mediaIdStr, 10);
    if (isNaN(mediaId) || mediaId <= 0) {
      promptAction.showToast({ message: '收藏夹ID无效' });
      return;
    }
    const sub: Subscription = new Subscription();
    sub.type = Subscription.TYPE_FAV;
    sub.sourceId = mediaId;
    sub.title = `收藏夹 ${mediaId}`;
    this.emitSub(sub);
  }

  private subscribeSeasonById(seasonIdStr: string): void {
    const seasonId: number = parseInt(seasonIdStr, 10);
    if (isNaN(seasonId) || seasonId <= 0) {
      promptAction.showToast({ message: '合集ID无效' });
      return;
    }
    if (this.mainBusy) {
      return;
    }
    this.mainBusy = true;
    BiliService.fetchSeasonMeta(seasonId).then((meta: SeasonMeta): void => {
      this.mainBusy = false;
      const sub: Subscription = new Subscription();
      sub.type = Subscription.TYPE_SEASON;
      sub.sourceId = seasonId;
      sub.ownerMid = meta.mid;
      sub.title = meta.name;
      sub.cover = meta.cover;
      this.emitSub(sub);
    }).catch((): void => {
      this.mainBusy = false;
      promptAction.showToast({ message: '合集信息获取失败' });
    });
  }

  private subscribeSeriesById(seriesIdStr: string): void {
    const seriesId: number = parseInt(seriesIdStr, 10);
    if (isNaN(seriesId) || seriesId <= 0) {
      promptAction.showToast({ message: '系列ID无效' });
      return;
    }
    if (this.mainBusy) {
      return;
    }
    this.mainBusy = true;
    BiliService.fetchSeriesMeta(seriesId).then((meta: SeasonMeta): void => {
      this.mainBusy = false;
      const sub: Subscription = new Subscription();
      sub.type = Subscription.TYPE_SERIES;
      sub.sourceId = seriesId;
      sub.ownerMid = meta.mid;
      sub.title = meta.name;
      this.emitSub(sub);
    }).catch((): void => {
      this.mainBusy = false;
      promptAction.showToast({ message: '系列信息获取失败' });
    });
  }

  private subscribeFolder(f: FavFolder): void {
    const sub: Subscription = new Subscription();
    sub.type = Subscription.TYPE_FAV;
    sub.sourceId = f.mediaId;
    sub.title = f.title;
    this.emitSub(sub);
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .margin({ top: 18, bottom: 8 })
  }

  @Builder
  private upResultsView() {
    if (this.upInfo !== null) {
      Row() {
        CoverThumb({ cover: this.upFace, thumbSize: 40, radius: 20 })
        Text(this.upName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 10, right: 8 })
        Text('订阅')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'))
          .onClick(() => {
            this.subscribeUp();
          })
      }
      .width('100%')
      .margin({ top: 12 })

      ForEach(this.seasons, (s: Season) => {
        Row() {
          Column() {
            Text(s.title)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`合集 · ${s.count}集`)
              .fontSize(12)
              .fontColor($r('app.color.text_disabled'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ right: 8 })
          Text('订阅')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .onClick(() => {
              this.subscribeSeason(s);
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }, (s: Season) => `season_${s.seasonId}`)

      ForEach(this.series, (s: Season) => {
        Row() {
          Column() {
            Text(s.title)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`系列 · ${s.count}集`)
              .fontSize(12)
              .fontColor($r('app.color.text_disabled'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ right: 8 })
          Text('订阅')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .onClick(() => {
              this.subscribeSeries(s);
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }, (s: Season) => `series_${s.seasonId}`)
    }
  }

  @Builder
  private mainView() {
    this.sectionTitle('添加订阅')
    Row() {
      TextInput({ placeholder: '视频/UP主/收藏夹/合集/系列 链接或ID', text: this.mainInput })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.placeholder_color'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.mainInput = value;
        })
      if (this.mainBusy) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(this.accentColor)
          .margin({ left: 10 })
      } else {
        Text('添加')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ left: 10 })
          .onClick(() => {
            this.handleMainInput();
          })
      }
    }
    .width('100%')

    if (this.upInfo !== null) {
      this.sectionTitle(`${this.upName} 的合集与系列`)
      this.upResultsView()
    }

    this.sectionTitle('我的收藏夹')
    if (!this.isLogged) {
      Text('登录 B 站账号后可订阅收藏夹')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    } else {
      Row() {
        Text('我的收藏夹')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.folderView = true;
      })
    }
  }

  @Builder
  private folderListView() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(16)
        .fontColor([$r('app.color.text_primary')])
        .onClick(() => {
          this.folderView = false;
        })
      Text('我的收藏夹')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })

    if (this.foldersBusy) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color(this.accentColor)
        .margin({ top: 8 })
    } else {
      ForEach(this.folders, (f: FavFolder) => {
        Row() {
          Column() {
            Text(f.title)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${f.count}条`)
              .fontSize(12)
              .fontColor($r('app.color.text_disabled'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ right: 8 })
          Text('订阅')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .onClick(() => {
              this.subscribeFolder(f);
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }, (f: FavFolder) => `fav_${f.mediaId}`)
    }
  }

  build() {
    Scroll() {
      Column() {
        if (this.folderView) {
          this.folderListView()
        } else {
          this.mainView()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
