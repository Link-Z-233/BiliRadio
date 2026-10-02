import { promptAction } from '@kit.ArkUI';
import { BiliService, UpInfo } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { Subscription } from '../model/Subscription';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Season } from '../model/Season';
import { FavFolder } from '../model/FavFolder';
import { PlayerController } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';

// 从粘贴文本中提取 BV 号（支持裸 BV 号或完整视频链接）
function extractBvid(input: string): string {
  const re: RegExp = new RegExp('BV[0-9A-Za-z]{10}');
  const m: RegExpExecArray | null = re.exec(input);
  if (m !== null) {
    return m[0];
  }
  return '';
}

// 添加订阅半模态：粘链接直接播 | UID→订阅UP/浏览其合集系列 | 收藏夹列表
@Component
export struct AddSubscriptionSheet {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @State linkInput: string = '';
  @State linkBusy: boolean = false;
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
      promptAction.showToast({ message: '收藏夹获取失败，请稍后重试' });
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

  private playLink(): void {
    const bv: string = extractBvid(this.linkInput);
    if (bv === '') {
      promptAction.showToast({ message: '未识别到BV号' });
      return;
    }
    if (this.linkBusy) {
      return;
    }
    this.linkBusy = true;
    this.controller.addToPlaylist(bv).then((): void => {
      this.linkBusy = false;
      this.onDismiss();
      if (this.controller.goToPlayerTab !== undefined) {
        this.controller.goToPlayerTab();
      }
    }).catch((): void => {
      this.linkBusy = false;
    });
  }

  private lookupUid(): void {
    const re: RegExp = new RegExp('^[0-9]+$');
    const trimmed: string = this.uidInput.trim();
    if (!re.test(trimmed)) {
      promptAction.showToast({ message: '请输入有效UID' });
      return;
    }
    const uid: number = parseInt(trimmed, 10);
    if (this.uidBusy) {
      return;
    }
    this.uidBusy = true;
    this.upInfo = null;
    this.upName = '';
    this.upFace = '';
    this.seasons = [];
    this.series = [];
    BiliService.fetchUpInfo(uid).then((info: UpInfo): Promise<Season[]> => {
      this.upInfo = info;
      this.upName = info.name;
      this.upFace = info.face;
      return BiliService.fetchSeasonsList(uid);
    }).then((seasons: Season[]): Promise<Season[]> => {
      this.seasons = seasons;
      return BiliService.fetchSeriesList(uid);
    }).then((series: Season[]): void => {
      this.series = series;
      this.uidBusy = false;
    }).catch((): void => {
      this.uidBusy = false;
      promptAction.showToast({ message: '查询失败，请稍后重试' });
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
    this.emitSub(sub);
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

  build() {
    Scroll() {
      Column() {
        this.sectionTitle('直接播放')
        Row() {
          TextInput({ placeholder: '粘贴BV号或视频链接', text: this.linkInput })
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.placeholder_color'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.linkInput = value;
            })
          if (this.linkBusy) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.accentColor)
              .margin({ left: 10 })
          } else {
            Text('播放')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .margin({ left: 10 })
              .onClick(() => {
                this.playLink();
              })
          }
        }
        .width('100%')

        this.sectionTitle('订阅 UP 主')
        Row() {
          TextInput({ placeholder: '输入UP主UID（个人空间网址里的数字）', text: this.uidInput })
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.placeholder_color'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.uidInput = value;
            })
          if (this.uidBusy) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.accentColor)
              .margin({ left: 10 })
          } else {
            Text('查询')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .margin({ left: 10 })
              .onClick(() => {
                this.lookupUid();
              })
          }
        }
        .width('100%')

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

        this.sectionTitle('收藏夹')
        if (!this.isLogged) {
          Text('登录 B 站账号后可订阅收藏夹')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        } else {
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
