import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { inputMethod } from '@kit.IMEKit';
import { BiliService, UpInfo, SeasonMeta } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { Subscription } from '../model/Subscription';
import { BiliVideo } from '../model/BiliVideo';
import { SubscriptionStore } from '../service/SubscriptionStore';
import { Season } from '../model/Season';
import { FavFolder } from '../model/FavFolder';
import { PlayerController } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { CoverThumb } from '../component/CoverThumb';
import {
  RecognizeResult,
  recognizeInput,
  extractBiliUrl,
  isBiliShortLink,
  normalizeShortLinkUrl,
  resolveShortLink,
  ShortLinkOutcome,
  ShortLinkResult,
} from '../service/LinkResolver';

// 系统返回拦截句柄：宿主页面在 bindSheet onWillDismiss 中经 requestBack 询问面板是否消费返回事件
// （返回 true=面板已处理——如从二级视图退回一级；false=未消费，宿主正常关闭面板）
export class AddSheetBackHandler {
  requestBack: () => boolean = (): boolean => false;
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
  // UP 合集/系列二级视图（对齐 folderView 模式；builder 方法名为 upDetailListView，避免与同名状态冲突）
  @State upDetailView: boolean = false;
  // seasons/series 两个请求是否已 settle（then/catch 均置 true），用于二级视图区分加载态与空态
  @State seasonsLoaded: boolean = false;
  @State seriesLoaded: boolean = false;
  onSubscribed: (sub: Subscription) => void = (sub: Subscription) => {
  };
  onDismiss: () => void = () => {
  };
  // 系统返回拦截句柄（由宿主 HomePage 持有并传入，onWillDismiss PRESS_BACK 时调用）
  backHandler: AddSheetBackHandler = new AddSheetBackHandler();
  private controller: PlayerController = PlayerController.getInstance();

  aboutToAppear(): void {
    this.backHandler.requestBack = (): boolean => {
      return this.handleSheetBackPress();
    };
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

  // 识别结果 → 既有六分支分发（bv/av/up/fav/season/series；六个动作方法零改动）
  private dispatchRecognized(parsed: RecognizeResult): void {
    switch (parsed.type) {
      case 'bv':
        this.playBv(parsed.id);
        break;
      case 'av':
        this.playAv(parsed.id);
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

  private handleMainInput(): void {
    // US5：提交查询统一收起软键盘（覆盖按钮点击/输入法提交/非法输入全部分支）
    try {
      inputMethod.getController().stopInputSession();
    } catch (e) {
      // 收起失败静默：不影响查询主流程
    }
    // KI-4：全分支统一前置清洗——从分享文案抽取第一个 B 站链接（含尾随标点清除），未抽到回退 trim 原文
    const cleaned: string = extractBiliUrl(this.mainInput);
    const normalized: string = normalizeShortLinkUrl(cleaned);
    if (isBiliShortLink(normalized)) {
      if (this.mainBusy) {
        return;
      }
      this.mainBusy = true;
      this.mainMsg = '解析短链中…';
      resolveShortLink(normalized).then((res: ShortLinkResult): void => {
        this.mainBusy = false;
        this.mainMsg = '';
        if (res.outcome !== ShortLinkOutcome.OK) {
          // 失败分型提示：网络失败 / 超出跳数 / 无有效目标 / 目标无法识别（FR-005）
          promptAction.showToast({ message: res.message });
          return;
        }
        // 解析成功不回写输入框（FR-010），识别目标后走既有分发
        const parsed: RecognizeResult = recognizeInput(res.target);
        if (parsed.type === '') {
          promptAction.showToast({ message: '短链目标无法识别' });
          return;
        }
        this.dispatchRecognized(parsed);
      }).catch((): void => {
        // 防御网：resolveShortLink 内部已捕获全部失败，此处仅兜底复位 busy 状态
        this.mainBusy = false;
        this.mainMsg = '';
        promptAction.showToast({ message: '短链解析失败' });
      });
      return;
    }
    // 非短链分支：对清洗后文本直接识别（修复未 trim 失配）+ 既有分发
    const parsed: RecognizeResult = recognizeInput(cleaned);
    if (parsed.type === '') {
      promptAction.showToast({ message: '未识别到有效链接、BV 号 / av 号或 UP 主 UID' });
      return;
    }
    if (this.mainBusy) {
      return;
    }
    this.dispatchRecognized(parsed);
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

  // av 号查询：经 view 接口 aid 参数归一化出 bvid 后，复用既有 playBv 播放链路
  private playAv(avStr: string): void {
    const aid: number = parseInt(avStr, 10);
    if (isNaN(aid) || aid <= 0) {
      promptAction.showToast({ message: 'av 号无效' });
      return;
    }
    if (this.mainBusy) {
      return;
    }
    this.mainBusy = true;
    BiliService.fetchVideoInfoByAid(aid).then((video: BiliVideo): void => {
      this.mainBusy = false;
      if (video.bvid === '') {
        promptAction.showToast({ message: '未查询到该 av 号对应的视频' });
        return;
      }
      this.playBv(video.bvid);
    }).catch((): void => {
      this.mainBusy = false;
      promptAction.showToast({ message: 'av 号查询失败' });
    });
  }

  private lookupUid(uidStr: string): void {
    const uid: number = parseInt(uidStr, 10);
    if (isNaN(uid) || uid <= 0) {
      promptAction.showToast({ message: '请输入有效的 UP 主 UID' });
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
    this.seasonsLoaded = false;
    this.seriesLoaded = false;
    this.upDetailView = false;
    BiliService.fetchUpInfo(uid).then((info: UpInfo): void => {
      this.uidBusy = false;
      this.mainBusy = false;
      // 查询结果出现包在 animateTo 中，配合结果区域 TransitionEffect 消除瞬间弹出
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.upInfo = info;
        this.upName = info.name;
        this.upFace = info.face;
      });
      BiliService.fetchSeasonsList(uid).then((seasons: Season[]): void => {
        this.seasons = seasons;
        this.seasonsLoaded = true;
      }).catch((): void => {
        this.seasonsLoaded = true;
      });
      BiliService.fetchSeriesList(uid).then((series: Season[]): void => {
        this.series = series;
        this.seriesLoaded = true;
      }).catch((): void => {
        this.seriesLoaded = true;
      });
    }).catch((err: BusinessError): void => {
      this.uidBusy = false;
      this.mainBusy = false;
      // 透出真实错误码：-352/-412/风控页等按「疑似风控+建议登录」提示，其余直接附带错误信息
      const msg: string = err.message;
      if (msg.indexOf('-352') >= 0 || msg.indexOf('-412') >= 0 || msg.indexOf('风控') >= 0) {
        const codeMatch: RegExpMatchArray | null = msg.match(/-\d{1,5}/);
        const code: string = codeMatch !== null ? codeMatch[0] : '';
        promptAction.showToast({
          message: code !== '' ? `查询UP主失败(${code})，疑似风控，建议登录后重试` : '查询UP主失败，疑似风控，建议登录后重试'
        });
      } else {
        promptAction.showToast({ message: `查询UP主失败: ${msg}` });
      }
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

  // 一级↔二级视图切换统一走 animateTo，配合 build() 内各分支 TransitionEffect 实现层级转场
  // （二级视图右侧滑入，一级视图左滑淡出，返回反向）
  private enterFolderView(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, (): void => {
      this.upDetailView = false;
      this.folderView = true;
    });
  }

  private enterUpDetailView(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, (): void => {
      this.folderView = false;
      this.upDetailView = true;
    });
  }

  private backToMainView(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, (): void => {
      this.folderView = false;
      this.upDetailView = false;
    });
  }

  // 系统返回（bindSheet onWillDismiss 的 PRESS_BACK）：二级视图在场时消费返回事件，退回一级视图
  private handleSheetBackPress(): boolean {
    if (this.upDetailView || this.folderView) {
      this.backToMainView();
      return true;
    }
    return false;
  }

  // 二级视图标题行：返回图标外扩至 40vp 触控区（padding 10），负 margin 抵消布局位移保持视觉位置不变
  @Builder
  private secondaryHeader(title: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([$r('app.color.text_primary')])
        .padding(10)
        .margin({ left: -10 })
        .borderRadius(20)
        .onClick(() => {
          this.backToMainView();
        })
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: -6 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })
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
        // UP 头像 URL 拼缩略后缀会 404，raw=true 直接加载原图
        CoverThumb({ cover: this.upFace, thumbSize: 40, radius: 20, raw: true })
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
    }
  }

  @Builder
  private mainView() {
    this.sectionTitle('添加订阅')
    Row() {
      TextInput({ placeholder: '粘贴 B 站链接或 ID', text: this.mainInput })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.placeholder_color'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Search)
        .onSubmit(() => {
          this.handleMainInput();
        })
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
        Text('查询')
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

    // 能力枚举放说明行而非占位符：Text 可自动换行，大字模式缩放不溢出
    Text('支持分享文案、短链、BV 号、av 号、UP 主 UID')
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .margin({ top: 6 })

    if (this.upInfo !== null) {
      // 查询结果区域整体挂出现/消失过渡（透明度+位移入位），配合 lookupUid 内 animateTo
      Column() {
        this.sectionTitle(`${this.upName} 的合集与系列`)
        this.upResultsView()
        // 入口行：样式对齐「我的收藏夹」入口行，点击进入 UP 合集/系列二级视图（与 folderView 互斥）
        Row() {
          Text(`合集与系列 (${this.seasons.length + this.series.length})`)
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
          this.enterUpDetailView();
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 300, curve: Curve.EaseOut }))
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
        this.enterFolderView();
      })
    }
  }

  @Builder
  private folderListView() {
    this.secondaryHeader('我的收藏夹')

    if (this.foldersBusy) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color(this.accentColor)
        .margin({ top: 8 })
    } else {
      ForEach(this.folders, (f: FavFolder) => {
        Row() {
          // 收藏夹无封面字段：统一走 CoverThumb ♪ 占位，与其余类型无封面形态一致
          CoverThumb({ thumbSize: 40, radius: 8 })
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
          .margin({ left: 10, right: 8 })
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

  // UP 合集/系列二级视图：返回行对齐 folderListView，条目行样式沿用原 upResultsView
  @Builder
  private upDetailListView() {
    this.secondaryHeader(`${this.upName} 的合集与系列`)

    if (this.seasons.length + this.series.length === 0) {
      if (this.seasonsLoaded && this.seriesLoaded) {
        Text('该 UP 主暂无合集与系列')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
      } else {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(this.accentColor)
          .margin({ top: 8 })
      }
    } else {
      if (this.seasons.length > 0) {
        this.sectionTitle('合集')
      }
      ForEach(this.seasons, (s: Season) => {
        Row() {
          // 合集封面 URL 拼缩略后缀会 404，raw=true 直接加载原图
          CoverThumb({ cover: s.cover, thumbSize: 40, radius: 8, raw: true })
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
          .margin({ left: 10, right: 8 })
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

      if (this.series.length > 0) {
        this.sectionTitle('系列')
      }
      ForEach(this.series, (s: Season) => {
        Row() {
          // 系列封面 URL 拼缩略后缀会 404，raw=true 直接加载原图
          CoverThumb({ cover: s.cover, thumbSize: 40, radius: 8, raw: true })
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
          .margin({ left: 10, right: 8 })
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

  build() {
    Scroll() {
      Column() {
        if (this.upDetailView) {
          // 二级视图：右侧滑入，返回时右侧滑出（进出场同向）
          Column() {
            this.upDetailListView()
          }
          .width('100%')
          .transition(TransitionEffect.translate({ x: '100%' })
            .animation({ duration: 300, curve: Curve.Friction }))
        } else if (this.folderView) {
          // 二级视图：右侧滑入，返回时右侧滑出（进出场同向）
          Column() {
            this.folderListView()
          }
          .width('100%')
          .transition(TransitionEffect.translate({ x: '100%' })
            .animation({ duration: 300, curve: Curve.Friction }))
        } else {
          // 一级视图：被二级覆盖时左滑淡出，返回时反向滑回
          Column() {
            this.mainView()
          }
          .width('100%')
          .transition(TransitionEffect.translate({ x: '-25%' }).combine(TransitionEffect.OPACITY)
            .animation({ duration: 300, curve: Curve.Friction }))
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
