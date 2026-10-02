import { BiliService, FolderFetchResult } from '../service/BiliService';
import { BiliSession } from '../service/BiliSession';
import { AppStore } from '../service/AppStore';
import { PlayerController, PlayMode } from '../service/PlayerController';
import { FavFolder } from '../model/FavFolder';
import { BiliVideo } from '../model/BiliVideo';
import { Season } from '../model/Season';
import { SelectedSeason } from '../model/SelectedSeason';
import { DownloadedSong } from '../model/DownloadedSong';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { statfs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

import { ForegroundColor } from '../component/ForegroundColor';
import { Constants } from '../service/Constants';
import { DownloadManager } from '../service/DownloadManager';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 列表上下边缘渐变模糊半径；悬浮头部/底部留白；列表底部超出悬浮菜单栏的余量
const EDGE_BLUR_RADIUS: number = 48;
const HEADER_FADE_TAIL: number = 8;
const FOOTER_FADE_TAIL: number = 12;
const LIST_BOTTOM_GAP: number = 12;

@Component
export struct FoldersPage {
  @State folders: FavFolder[] = [];
  @State selectedIds: number[] = [];
  @State loading: boolean = false;
  @State statusMsg: string = '';
  @State summaryMsg: string = '';
  @State warningMsg: string = '';

  // —— UP主合集来源状态 ——
  // 来源模式：0=收藏夹 1=UP主合集 2=下载内容
  @State sourceMode: number = 0;
  @State uidInput: string = '';
  @State seasons: Season[] = [];
  @State seasonsLoading: boolean = false;
  @State seasonStatusMsg: string = '';
  private currentMid: number = 0;

  // —— 多选模式（三个来源共用，@StorageLink 便于返回键拦截退出多选） ——
  @StorageLink('folderSelectMode') selectMode: boolean = false; // key 与 Constants.AS_FOLDER_SELECT_MODE 对应
  @State selectedSeasonIds: number[] = [];

  // —— 下载内容来源状态 ——
  @State downloads: DownloadedSong[] = [];
  @State downloadSelectedBvids: string[] = [];
  @State downloadMsg: string = '';
  @State downloadsBytes: number = 0;
  @State freeBytes: number = -1;
  @State totalBytes: number = -1;


  @State headerHeight: number = 118;
  @State footerHeight: number = 90;
  @State pageHeight: number = 0;
  @StorageProp('floatingTabHeight') floatingTabHeight: number = 90;
  // 智能反色：封面偏暗时 true，前景文字自动转浅色保证可读
  @StorageProp('coverIsDark') coverIsDark: boolean = false;
  @StorageProp('isWideScreen') isWideScreen: boolean = false;
  private controller: PlayerController = PlayerController.getInstance();

  private textPrimary(): Resource {
    return ForegroundColor.primary(this.coverIsDark);
  }

  private textSecondary(): Resource {
    return ForegroundColor.secondary(this.coverIsDark);
  }

  private textDisabled(): Resource {
    return ForegroundColor.disabled(this.coverIsDark);
  }


  aboutToAppear(): void {
    const saved: string = AppStore.getString(Constants.KEY_SELECTED_FOLDER_IDS, '[]');
    try {
      const ids: number[] = JSON.parse(saved) as number[];
      this.selectedIds = ids;
    } catch (e) {
      this.selectedIds = [];
    }
    this.refresh();
  }

  private isSelected(mediaId: number): boolean {
    return this.selectedIds.indexOf(mediaId) >= 0;
  }

  private toggleSelect(mediaId: number): void {
    const pos: number = this.selectedIds.indexOf(mediaId);
    if (pos >= 0) {
      this.selectedIds.splice(pos, 1);
    } else {
      this.selectedIds.push(mediaId);
    }
    AppStore.putString(Constants.KEY_SELECTED_FOLDER_IDS, JSON.stringify(this.selectedIds));
  }

  // 来源切换：0=收藏夹 1=UP主合集 2=下载内容；切到 UP主合集时预填上次成功查询的 UID，
  // 切到下载内容时加载已下载列表与存储空间；切来源时退出多选
  private switchSource(mode: number): void {
    if (mode === this.sourceMode) {
      return;
    }
    this.sourceMode = mode;
    this.selectMode = false;
    this.selectedSeasonIds = [];
    this.downloadSelectedBvids = [];
    if (mode === 1) {
      const saved: string = AppStore.getString(Constants.KEY_LAST_SEASON_MID, '');
      this.uidInput = saved;
      this.seasons = [];
      this.seasonStatusMsg = '';
      this.seasonsLoading = false;
    } else if (mode === 2) {
      this.downloadMsg = '';
      this.refreshDownloads();
    }
  }

  // 查询 UP 主的公开合集列表
  private async querySeasons(): Promise<void> {
    const trimmed: string = this.uidInput.trim();
    const mid: number = parseInt(trimmed);
    if (trimmed === '' || isNaN(mid) || mid <= 0 || !/^\d+$/.test(trimmed)) {
      this.seasonStatusMsg = 'UID 无效，请填写数字';
      return;
    }
    if (this.seasonsLoading) {
      return;
    }
    this.seasonsLoading = true;
    this.seasonStatusMsg = '正在获取合集列表...';
    try {
      const list: Season[] = await BiliService.fetchSeasonsList(mid);
      this.seasons = list;
      if (list.length === 0) {
        this.seasonStatusMsg = '该UP主没有公开合集';
      } else {
        this.seasonStatusMsg = '';
        this.currentMid = mid;
        AppStore.putString(Constants.KEY_LAST_SEASON_MID, trimmed);
      }
    } catch (err) {
      const error = err as BusinessError;
      this.seasonStatusMsg = `获取失败: ${error.message}`;
    }
    this.seasonsLoading = false;
  }

  // 点击合集：读取合集内视频并生成歌单立即播放
  private async playSeason(season: Season): Promise<void> {
    if (this.seasonsLoading || this.currentMid <= 0) {
      return;
    }
    this.seasonsLoading = true;
    this.seasonStatusMsg = `正在加载合集「${season.title}」...`;
    try {
      const items: BiliVideo[] = await BiliService.fetchSeasonVideos(this.currentMid, season.seasonId);
      if (items.length === 0) {
        this.seasonStatusMsg = '该合集没有可播放内容';
        return;
      }
      this.seasonStatusMsg = '';
      const startIndex: number = this.controller.playMode === PlayMode.RANDOM
        ? Math.floor(Math.random() * items.length) : 0;
      await this.controller.loadPlaylistAndPlay(items, startIndex);
      if (this.controller.goToPlayerTab !== undefined) {
        this.controller.goToPlayerTab();
      }
    } catch (err) {
      const error = err as BusinessError;
      this.seasonStatusMsg = `加载失败: ${error.message}`;
    }
    this.seasonsLoading = false;
  }

  private findSeason(seasonId: number): Season | undefined {
    for (let i = 0; i < this.seasons.length; i++) {
      if (this.seasons[i].seasonId === seasonId) {
        return this.seasons[i];
      }
    }
    return undefined;
  }

  // 多选：批量读取选中合集的视频，合并生成歌单（追加去重，不打断播放）
  private async buildSeasonsPlaylist(): Promise<void> {
    if (this.selectedSeasonIds.length === 0 || this.currentMid <= 0) {
      return;
    }
    if (this.seasonsLoading) {
      return;
    }
    this.seasonsLoading = true;
    this.seasonStatusMsg = '正在加载选中的合集...';
    try {
      const items: BiliVideo[] = [];
      const seen: Map<string, number> = new Map<string, number>();
      for (let i = 0; i < this.selectedSeasonIds.length; i++) {
        const seasonId: number = this.selectedSeasonIds[i];
        const season: Season | undefined = this.findSeason(seasonId);
        if (season !== undefined) {
          this.seasonStatusMsg = `正在加载「${season.title}」...`;
        }
        const list: BiliVideo[] = await BiliService.fetchSeasonVideos(this.currentMid, seasonId);
        for (let j = 0; j < list.length; j++) {
          const v: BiliVideo = list[j];
          if (seen.get(v.bvid) === undefined) {
            seen.set(v.bvid, items.length);
            items.push(v);
          }
        }
      }
      this.seasonStatusMsg = '';
      if (items.length === 0) {
        this.seasonStatusMsg = '所选合集没有可播放内容';
        return;
      }
      const startIndex: number = this.controller.playMode === PlayMode.RANDOM
        ? Math.floor(Math.random() * items.length) : 0;
      this.exitSelectMode();
      await this.controller.loadPlaylistAndPlay(items, startIndex);
      if (this.controller.goToPlayerTab !== undefined) {
        this.controller.goToPlayerTab();
      }
    } catch (err) {
      const error = err as BusinessError;
      this.seasonStatusMsg = `加载失败: ${error.message}`;
    }
    this.seasonsLoading = false;
  }

  // 来源二选一分段按钮：与设置页「外观」三选一同款视觉
  @Builder
  sourceOption(label: string, mode: number) {
    Text(label)
      .id(`source_option_${mode}`)
      .fontSize(13)
      .fontColor(this.sourceMode === mode ?
        $r('app.color.text_primary') : this.textSecondary())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(17)
      .backgroundColor(this.sourceMode === mode ?
        $r('app.color.material_tint_primary') : $r('app.color.btn_glass'))
      .onClick(() => {
        this.switchSource(mode);
      })
  }


  async refresh(): Promise<void> {
    const session: BiliSession = BiliSession.getInstance();
    if (!session.isLogged()) {
      this.folders = [];
      this.statusMsg = '请先在"设置"页登录B站账号';
      return;
    }
    this.loading = true;
    this.statusMsg = '正在获取收藏夹列表...';
    try {
      this.folders = await BiliService.fetchMyFolders();
      this.statusMsg = this.folders.length > 0
        ? '点一下收藏夹直接播放，点右上角"多选"可批量生成歌单' : '没有获取到收藏夹';
    } catch (err) {
      const error = err as BusinessError;
      this.statusMsg = `获取失败: ${error.message}`;
    }
    this.loading = false;
  }

  private findFolder(mediaId: number): FavFolder | undefined {
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].mediaId === mediaId) {
        return this.folders[i];
      }
    }
    return undefined;
  }

  async buildPlaylist(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.statusMsg = '请先勾选收藏夹';
      return;
    }
    const session: BiliSession = BiliSession.getInstance();
    if (!session.isLogged()) {
      this.statusMsg = '请先在"设置"页登录B站账号';
      return;
    }
    this.loading = true;
    this.summaryMsg = '';
    this.warningMsg = '';
    try {
      const items: BiliVideo[] = [];
      const seen: Map<string, number> = new Map<string, number>();
      let loadedRaw: number = 0;
      let skippedInvalid: number = 0;
      let removedDuplicates: number = 0;
      const warnings: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        const folder: FavFolder | undefined = this.findFolder(this.selectedIds[i]);
        if (folder === undefined) {
          continue;
        }
        this.statusMsg = `正在加载「${folder.title}」...`;
        let result: FolderFetchResult;
        try {
          result = await BiliService.fetchFolderVideos(
            folder.mediaId,
            folder.count,
            (fetched: number, total: number): void => {
              const totalText: string = total > 0 ? `${total}` : '?';
              this.statusMsg = `加载「${folder.title}」${fetched}/${totalText}...`;
            }
          );
        } catch (err) {
          const error = err as BusinessError;
          warnings.push(`「${folder.title}」加载失败: ${error.message}（若频繁失败请等几分钟再试，B站风控）`);
          continue;
        }
        loadedRaw += result.rawCount;
        skippedInvalid += result.skipped;
        if (result.partialMsg !== '') {
          warnings.push(`「${folder.title}」${result.partialMsg}`);
        }
        if (result.rawCount < folder.count && result.partialMsg === '') {
          warnings.push(`「${folder.title}」取到${result.rawCount}/${folder.count}（B站接口上限或含失效视频）`);
        }
        for (let j = 0; j < result.items.length; j++) {
          const v: BiliVideo = result.items[j];
          const existing: number | undefined = seen.get(v.bvid);
          if (existing !== undefined) {
            items[existing].folderIds.push(folder.mediaId);
            removedDuplicates++;
          } else {
            v.folderIds.push(folder.mediaId);
            seen.set(v.bvid, items.length);
            items.push(v);
          }
        }
      }
      if (items.length === 0) {
        this.statusMsg = `所选收藏夹共 ${loadedRaw} 个视频，但没有可用内容`;
        if (warnings.length > 0) {
          this.warningMsg = warnings.join('；');
        }
        this.loading = false;
        return;
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'merged playlist size: %{public}d', items.length);
      let summary: string = `共拉取 ${loadedRaw} 条，生成歌单 ${items.length} 首`;
      if (removedDuplicates > 0) {
        summary += `，去重 ${removedDuplicates}`;
      }
      if (skippedInvalid > 0) {
        summary += `，失效 ${skippedInvalid}`;
      }
      this.summaryMsg = summary;
      if (warnings.length > 0) {
        this.warningMsg = warnings.join('；');
      }
      const startIndex: number = this.controller.playMode === PlayMode.RANDOM
        ? Math.floor(Math.random() * items.length) : 0;
      this.loading = false;
      await this.controller.loadPlaylistAndPlay(items, startIndex);
      if (this.controller.goToPlayerTab !== undefined) {
        this.controller.goToPlayerTab();
      }
    } catch (err) {
      const error = err as BusinessError;
      this.statusMsg = `生成歌单失败: ${error.message}`;
      this.loading = false;
    }
  }

  // 非多选：点收藏夹直接生成该收藏夹歌单并播放
  private playFolder(folder: FavFolder): void {
    this.selectedIds = [folder.mediaId];
    AppStore.putString(Constants.KEY_SELECTED_FOLDER_IDS, JSON.stringify(this.selectedIds));
    this.buildPlaylist();
  }

  // —— 下载内容来源 ——

  private refreshDownloads(): void {
    const dm: DownloadManager = DownloadManager.getInstance();
    this.downloads = dm.downloads.slice(0);
    let bytes: number = 0;
    for (let i = 0; i < this.downloads.length; i++) {
      bytes += this.downloads[i].size;
    }
    this.downloadsBytes = bytes;
    this.refreshStorage();
  }

  private async refreshStorage(): Promise<void> {
    try {
      const context = getContext() as common.UIAbilityContext;
      const path: string = context.filesDir;
      this.totalBytes = await statfs.getTotalSize(path);
      this.freeBytes = await statfs.getFreeSize(path);
    } catch (e) {
      this.totalBytes = -1;
      this.freeBytes = -1;
    }
  }

  private isDownloadSelected(bvid: string): boolean {
    return this.downloadSelectedBvids.indexOf(bvid) >= 0;
  }

  private toggleDownloadSelect(bvid: string): void {
    const idx: number = this.downloadSelectedBvids.indexOf(bvid);
    if (idx >= 0) {
      this.downloadSelectedBvids.splice(idx, 1);
    } else {
      this.downloadSelectedBvids.push(bvid);
    }
    this.downloadSelectedBvids = this.downloadSelectedBvids.slice(0);
  }

  private toggleSeasonSelect(seasonId: number): void {
    const idx: number = this.selectedSeasonIds.indexOf(seasonId);
    if (idx >= 0) {
      this.selectedSeasonIds.splice(idx, 1);
    } else {
      this.selectedSeasonIds.push(seasonId);
    }
    this.selectedSeasonIds = this.selectedSeasonIds.slice(0);
    this.persistSeasonSelection();
  }

  private isSeasonSelected(seasonId: number): boolean {
    return this.selectedSeasonIds.indexOf(seasonId) >= 0;
  }

  // —— UP主合集勾选持久化：同步按钮据此拉取勾选合集（跨 UP 主，需 mid+seasonId） ——

  private loadSelectedSeasons(): SelectedSeason[] {
    const saved: string = AppStore.getString(Constants.KEY_SELECTED_SEASONS, '[]');
    try {
      const arr: Record<string, Object>[] = JSON.parse(saved) as Record<string, Object>[];
      const list: SelectedSeason[] = [];
      for (let i = 0; i < arr.length; i++) {
        list.push(SelectedSeason.fromRecord(arr[i]));
      }
      return list;
    } catch (e) {
      return [];
    }
  }

  private saveSelectedSeasons(list: SelectedSeason[]): void {
    const arr: Record<string, Object>[] = [];
    for (let i = 0; i < list.length; i++) {
      arr.push(list[i].toRecord());
    }
    AppStore.putString(Constants.KEY_SELECTED_SEASONS, JSON.stringify(arr));
  }

  // 把当前 UP 主下的临时勾选写入持久化（替换该 mid 的旧记录，其它 UP 主保留）
  private persistSeasonSelection(): void {
    if (this.currentMid <= 0) {
      return;
    }
    const all: SelectedSeason[] = this.loadSelectedSeasons();
    const others: SelectedSeason[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].mid !== this.currentMid) {
        others.push(all[i]);
      }
    }
    for (let i = 0; i < this.selectedSeasonIds.length; i++) {
      const season: Season | undefined = this.findSeason(this.selectedSeasonIds[i]);
      if (season !== undefined) {
        others.push(new SelectedSeason(this.currentMid, season.seasonId, season.title, season.count));
      }
    }
    this.saveSelectedSeasons(others);
  }

  // 进入多选时从持久化恢复当前 UP 主已勾选的合集
  private restoreCurrentSeasonSelection(): void {
    this.selectedSeasonIds = [];
    if (this.currentMid <= 0) {
      return;
    }
    const all: SelectedSeason[] = this.loadSelectedSeasons();
    for (let i = 0; i < all.length; i++) {
      if (all[i].mid === this.currentMid) {
        this.selectedSeasonIds.push(all[i].seasonId);
      }
    }
  }

  private enterSelectMode(): void {
    this.selectMode = true;
    if (this.sourceMode === 1) {
      this.restoreCurrentSeasonSelection();
    } else if (this.sourceMode === 2) {
      this.downloadSelectedBvids = [];
    }
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedSeasonIds = [];
    this.downloadSelectedBvids = [];
  }

  private hasCurrentData(): boolean {
    if (this.sourceMode === 0) {
      return this.folders.length > 0;
    }
    if (this.sourceMode === 1) {
      return this.seasons.length > 0;
    }
    return this.downloads.length > 0;
  }

  private currentSelectCount(): number {
    if (this.sourceMode === 0) {
      return this.selectedIds.length;
    }
    if (this.sourceMode === 1) {
      return this.selectedSeasonIds.length;
    }
    return this.downloadSelectedBvids.length;
  }

  private isCurrentAllSelected(): boolean {
    if (this.sourceMode === 0) {
      return this.folders.length > 0 && this.selectedIds.length === this.folders.length;
    }
    if (this.sourceMode === 1) {
      return this.seasons.length > 0 && this.selectedSeasonIds.length === this.seasons.length;
    }
    return this.downloads.length > 0 && this.downloadSelectedBvids.length === this.downloads.length;
  }

  private toggleSelectAllCurrent(): void {
    if (this.isCurrentAllSelected()) {
      if (this.sourceMode === 0) {
        this.selectedIds = [];
      } else if (this.sourceMode === 1) {
        this.selectedSeasonIds = [];
        this.persistSeasonSelection();
      } else {
        this.downloadSelectedBvids = [];
      }
      return;
    }
    if (this.sourceMode === 0) {
      const all: number[] = [];
      for (let i = 0; i < this.folders.length; i++) {
        all.push(this.folders[i].mediaId);
      }
      this.selectedIds = all;
    } else if (this.sourceMode === 1) {
      const all: number[] = [];
      for (let i = 0; i < this.seasons.length; i++) {
        all.push(this.seasons[i].seasonId);
      }
      this.selectedSeasonIds = all;
      this.persistSeasonSelection();
    } else {
      const all: string[] = [];
      for (let i = 0; i < this.downloads.length; i++) {
        all.push(this.downloads[i].bvid);
      }
      this.downloadSelectedBvids = all;
    }
  }

  private currentActionLabel(): string {
    if (this.sourceMode === 2) {
      return `删除(${this.downloadSelectedBvids.length})`;
    }
    return `生成歌单(${this.currentSelectCount()})`;
  }

  private currentMultiAction(): void {
    if (this.sourceMode === 0) {
      this.buildPlaylist();
    } else if (this.sourceMode === 1) {
      this.buildSeasonsPlaylist();
    } else {
      this.deleteSelectedDownloads();
    }
  }

  private deleteSelectedDownloads(): void {
    const count: number = this.downloadSelectedBvids.length;
    if (count === 0) {
      return;
    }
    const dm: DownloadManager = DownloadManager.getInstance();
    const removed: number = dm.deleteDownloads(this.downloadSelectedBvids);
    this.exitSelectMode();
    this.refreshDownloads();
    this.downloadMsg = `已删除 ${removed} 首本地歌曲`;
  }

  private playDownload(song: DownloadedSong): void {
    const video: BiliVideo = song.toBiliVideo();
    this.controller.playDownloadedSong(video).catch((): void => {});
    if (this.controller.goToPlayerTab !== undefined) {
      this.controller.goToPlayerTab();
    }
  }

  private formatMB(bytes: number): string {
    if (bytes < 0) {
      return '—';
    }
    const mb: number = bytes / Constants.BYTES_PER_MB;
    if (mb >= 1024) {
      return `${(mb / 1024).toFixed(1)} GB`;
    }
    return `${mb.toFixed(1)} MB`;
  }

  private formatDownloadTime(ts: number): string {
    const d: Date = new Date(ts);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    return `${month}-${day}`;
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.sourceMode === 0) {
        List({ space: 0 }) {
          ForEach(this.folders, (folder: FavFolder) => {
            ListItem() {
              Row() {
                if (this.selectMode) {
                  Checkbox()
                    .select(this.isSelected(folder.mediaId))
                    .selectedColor($r('app.color.primary_color'))
                    .hitTestBehavior(HitTestMode.None)
                    .width(24)
                }

                Column() {
                  Text(folder.title)
                    .fontSize(15)
                    .fontColor(this.textPrimary())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${folder.count} 个视频`)
                    .fontSize(12)
                    .fontColor(this.textSecondary())
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: this.selectMode ? 12 : 0 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                if (this.selectMode) {
                  this.toggleSelect(folder.mediaId);
                } else {
                  this.playFolder(folder);
                }
              })
            }
          }, (folder: FavFolder) => folder.mediaId.toString())
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(this.headerHeight)
        .contentEndOffset(this.selectMode ? this.footerHeight + this.floatingTabHeight + LIST_BOTTOM_GAP : this.floatingTabHeight + LIST_BOTTOM_GAP)
        .linearGradientBlur(EDGE_BLUR_RADIUS, {
          fractionStops: this.listBlurStops(),
          direction: GradientDirection.Bottom
        })
        .lanes(this.isWideScreen ? 2 : 1)
      } else if (this.sourceMode === 1) {
        List({ space: 0 }) {
          ForEach(this.seasons, (season: Season) => {
            ListItem() {
              Row() {
                if (this.selectMode) {
                  Checkbox()
                    .select(this.isSeasonSelected(season.seasonId))
                    .selectedColor($r('app.color.primary_color'))
                    .hitTestBehavior(HitTestMode.None)
                    .width(24)
                }

                Column() {
                  Text(season.title)
                    .fontSize(15)
                    .fontColor(this.textPrimary())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${season.count} 个视频`)
                    .fontSize(12)
                    .fontColor(this.textSecondary())
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: this.selectMode ? 12 : 0 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                if (this.selectMode) {
                  this.toggleSeasonSelect(season.seasonId);
                } else {
                  this.playSeason(season);
                }
              })
            }
          }, (season: Season) => season.seasonId.toString())
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(this.headerHeight)
        .contentEndOffset(this.selectMode ? this.footerHeight + this.floatingTabHeight + LIST_BOTTOM_GAP : this.floatingTabHeight + LIST_BOTTOM_GAP)
        .linearGradientBlur(EDGE_BLUR_RADIUS, {
          fractionStops: this.listBlurStops(),
          direction: GradientDirection.Bottom
        })
        .lanes(this.isWideScreen ? 2 : 1)
      } else {
        List({ space: 0 }) {
          ForEach(this.downloads, (song: DownloadedSong) => {
            ListItem() {
              Row() {
                if (this.selectMode) {
                  Checkbox()
                    .select(this.isDownloadSelected(song.bvid))
                    .selectedColor($r('app.color.primary_color'))
                    .hitTestBehavior(HitTestMode.None)
                    .width(24)
                }

                Column() {
                  Text(song.title)
                    .fontSize(15)
                    .fontColor(this.textPrimary())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.formatMB(song.size)} · ${this.formatDownloadTime(song.downloadTime)} 保存`)
                    .fontSize(12)
                    .fontColor(this.textSecondary())
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: this.selectMode ? 12 : 0 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                if (this.selectMode) {
                  this.toggleDownloadSelect(song.bvid);
                } else {
                  this.playDownload(song);
                }
              })
            }
          }, (song: DownloadedSong) => song.bvid)
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(this.headerHeight)
        .contentEndOffset(this.footerHeight + this.floatingTabHeight + LIST_BOTTOM_GAP)
        .linearGradientBlur(EDGE_BLUR_RADIUS, {
          fractionStops: this.listBlurStops(),
          direction: GradientDirection.Bottom
        })
        .lanes(this.isWideScreen ? 2 : 1)
      }

      Column() {
        Row() {
          Row({ space: 8 }) {
            this.sourceOption('个人收藏夹', 0)
            this.sourceOption('UP主合集', 1)
            this.sourceOption('本地内容', 2)
          }
          .layoutWeight(1)


          if (this.hasCurrentData() && !this.selectMode) {
            Button('多选')
              .height(32)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(16)
              .fontSize(13)
              .margin({ right: 8 })
              .onClick(() => {
                this.enterSelectMode();
              })
          }

          Button('刷新')
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor(this.textPrimary())
            .borderRadius(16)
            .fontSize(13)
            .enabled(!this.loading && !this.seasonsLoading)
            .opacity((!this.loading && !this.seasonsLoading) ? 1.0 : 0.4)
            .onClick(() => {
              if (this.sourceMode === 0) {
                this.refresh();
              } else if (this.sourceMode === 1) {
                this.querySeasons();
              } else {
                this.refreshDownloads();
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 8 })

        if (this.sourceMode === 0) {
          Text(this.statusMsg)
            .fontSize(13)
            .fontColor(this.textSecondary())
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.summaryMsg !== '') {
            Text(this.summaryMsg)
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 4 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.warningMsg !== '') {
            Text(this.warningMsg)
              .fontSize(12)
              .fontColor($r('app.color.gold_accent'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 4 })
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.loading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .color($r('app.color.primary_color'))
                .width(24)
                .height(24)
              Text('加载中...')
                .fontSize(13)
                .fontColor(this.textSecondary())
            }
            .margin({ top: 12, bottom: 4 })
          }
        } else if (this.sourceMode === 1) {
          Row() {
            TextInput({ placeholder: '请输入UP主UID', text: this.uidInput })
              .id('season_uid_input')
              .layoutWeight(1)
              .height(40)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .placeholderColor($r('app.color.placeholder_color'))
              .borderRadius(8)
              .fontSize(13)
              .onChange((value: string) => {
                this.uidInput = value;
              })

            Button('查询')
              .height(40)
              .margin({ left: 8 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor($r('app.color.primary_color'))
              .borderRadius(8)
              .fontSize(13)
              .enabled(!this.seasonsLoading)
              .opacity(this.seasonsLoading ? 0.4 : 1.0)
              .onClick(() => {
                this.querySeasons();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 4 })

          Text(this.seasonStatusMsg)
            .fontSize(13)
            .fontColor(this.textSecondary())
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 4 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.seasonsLoading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .color($r('app.color.primary_color'))
                .width(24)
                .height(24)
              Text('加载中...')
                .fontSize(13)
                .fontColor(this.textSecondary())
            }
            .margin({ top: 12, bottom: 4 })
          }
        } else {
          Row() {
            Text(`已保存 ${this.formatMB(this.downloadsBytes)}`)
              .fontSize(13)
              .fontColor(this.textPrimary())
            Text(`可用 ${this.formatMB(this.freeBytes)} / 总 ${this.formatMB(this.totalBytes)}`)
              .fontSize(13)
              .fontColor(this.textSecondary())
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 16, right: 16, bottom: 6 })

          if (this.totalBytes > 0) {
            Row() {
              Row()
                .layoutWeight(Math.max(0, this.downloadsBytes))
                .backgroundColor($r('app.color.primary_color'))
              Row()
                .layoutWeight(Math.max(0, this.totalBytes - this.downloadsBytes - this.freeBytes))
                .backgroundColor($r('app.color.track_color'))
              Row()
                .layoutWeight(Math.max(0, this.freeBytes))
                .backgroundColor($r('app.color.success_green'))
            }
            .width('100%')
            .height(10)
            .borderRadius(5)
            .clip(true)
            .margin({ left: 16, right: 16, bottom: 6 })
          }

          if (this.downloads.length === 0) {
            Text('暂无本地内容，可在「播放列表」页多选后保存到本地')
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 4 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.downloadMsg !== '') {
            Text(this.downloadMsg)
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 4 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .width('100%')
      .padding({ bottom: HEADER_FADE_TAIL })
      .zIndex(1)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.headerHeight = newArea.height as number;
      })

      if (this.selectMode) {
        Column() {
          Column() {
            Row({ space: 10 }) {
              Button(this.isCurrentAllSelected() ? '取消全选' : '全选')
                .layoutWeight(1)
                .height(46)
                .backgroundColor($r('app.color.btn_glass'))
                .backdropBlur(20)
                .border({ width: 1, color: $r('app.color.btn_border') })
                .fontColor(this.textPrimary())
                .borderRadius(23)
                .fontSize(14)
                .onClick(() => {
                  this.toggleSelectAllCurrent();
                })

              Button(this.currentActionLabel())
                .layoutWeight(1)
                .height(46)
                .backgroundColor(this.sourceMode === 2 ? $r('app.color.danger_red') : $r('app.color.material_tint_primary'))
                .backdropBlur(20)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(23)
                .fontSize(14)
                .enabled(this.currentSelectCount() > 0)
                .opacity(this.currentSelectCount() > 0 ? 1.0 : 0.4)
                .onClick(() => {
                  this.currentMultiAction();
                })

              Button('返回')
                .layoutWeight(1)
                .height(46)
                .backgroundColor($r('app.color.btn_glass'))
                .backdropBlur(20)
                .border({ width: 1, color: $r('app.color.btn_border') })
                .fontColor(this.textPrimary())
                .borderRadius(23)
                .fontSize(14)
                .onClick(() => {
                  this.exitSelectMode();
                })
            }
            .width('92%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: FOOTER_FADE_TAIL, bottom: 16 })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.footerHeight = newArea.height as number;
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: this.floatingTabHeight - 28 })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(1)
      } else if (this.sourceMode === 2) {
        Column() {
          Column() {
            Button('管理')
              .width('92%')
              .height(46)
              .backgroundColor($r('app.color.material_tint_primary'))
              .backdropBlur(20)
              .fontColor($r('app.color.text_primary'))
              .borderRadius(23)
              .fontSize(16)
              .enabled(this.downloads.length > 0)
              .opacity(this.downloads.length > 0 ? 1.0 : 0.4)
              .onClick(() => {
                this.enterSelectMode();
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: FOOTER_FADE_TAIL, bottom: 16 })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.footerHeight = newArea.height as number;
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: this.floatingTabHeight - 28 })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(1)
      }


    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageHeight = newArea.height as number;
    })
  }

}
