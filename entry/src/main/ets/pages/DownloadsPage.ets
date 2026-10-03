import { DownloadedSong } from '../model/DownloadedSong';
import { BiliVideo } from '../model/BiliVideo';
import { PlayerController } from '../service/PlayerController';
import { DownloadManager } from '../service/DownloadManager';
import { Constants } from '../service/Constants';
import { statfs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

@Builder
export function DownloadsPageBuilder() {
  DownloadsPage()
}

// 下载管理（NavDestination）：本地歌曲列表（点击播放 / 多选删除）+ 存储占用概览
@Component
struct DownloadsPage {
  @State downloads: DownloadedSong[] = [];
  @State selectMode: boolean = false;
  @State downloadSelectedBvids: string[] = [];
  @State downloadMsg: string = '';
  @State downloadsBytes: number = 0;
  @State freeBytes: number = -1;
  @State totalBytes: number = -1;
  private navPathStack: NavPathStack = new NavPathStack();
  private controller: PlayerController = PlayerController.getInstance();

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
      const context = getContext(this) as common.UIAbilityContext;
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

  private isAllSelected(): boolean {
    return this.downloads.length > 0 && this.downloadSelectedBvids.length === this.downloads.length;
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.downloadSelectedBvids = [];
      return;
    }
    const all: string[] = [];
    for (let i = 0; i < this.downloads.length; i++) {
      all.push(this.downloads[i].bvid);
    }
    this.downloadSelectedBvids = all;
  }

  private enterSelectMode(): void {
    this.selectMode = true;
    this.downloadSelectedBvids = [];
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.downloadSelectedBvids = [];
  }

  private deleteSelectedDownloads(): void {
    const count: number = this.downloadSelectedBvids.length;
    if (count === 0) {
      return;
    }
    AlertDialog.show({
      title: '删除本地歌曲',
      message: `确定删除选中的 ${count} 首本地歌曲吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        action: (): void => {
          const dm: DownloadManager = DownloadManager.getInstance();
          const removed: number = dm.deleteDownloads(this.downloadSelectedBvids);
          this.exitSelectMode();
          this.refreshDownloads();
          this.downloadMsg = `已删除 ${removed} 首本地歌曲`;
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
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

  build() {
    NavDestination() {
      Column() {
        Column() {
          Row() {
            Text(`已保存 ${this.formatMB(this.downloadsBytes)}`)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
            Text(`可用 ${this.formatMB(this.freeBytes)} / 总 ${this.formatMB(this.totalBytes)}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

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
            .margin({ top: 10 })
          }

          if (this.downloads.length === 0) {
            Text('暂无本地内容，可在播放队列中多选后保存到本地')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 10 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.downloadMsg !== '') {
            Text(this.downloadMsg)
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .width('100%')
              .margin({ top: 8 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 12, right: 12, top: 4 })

        List({ space: 4 }) {
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
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.formatMB(song.size)} · ${this.formatDownloadTime(song.downloadTime)} 保存`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: this.selectMode ? 12 : 0 })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(14)
              .backgroundColor($r('app.color.card_background'))
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
        .padding({ left: 12, right: 12, top: 8, bottom: 12 })
        .layoutWeight(1)

        if (!this.selectMode) {
          Button('管理')
            .width('92%')
            .height(46)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(23)
            .fontSize(16)
            .margin({ bottom: 12 })
            .enabled(this.downloads.length > 0)
            .opacity(this.downloads.length > 0 ? 1.0 : 0.4)
            .onClick(() => {
              this.enterSelectMode();
            })
        } else {
          Row({ space: 10 }) {
            Button(this.isAllSelected() ? '取消全选' : '全选')
              .layoutWeight(1)
              .height(46)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(23)
              .fontSize(14)
              .onClick(() => {
                this.toggleSelectAll();
              })

            Button(`删除(${this.downloadSelectedBvids.length})`)
              .layoutWeight(1)
              .height(46)
              .backgroundColor($r('app.color.danger_red'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(23)
              .fontSize(14)
              .enabled(this.downloadSelectedBvids.length > 0)
              .opacity(this.downloadSelectedBvids.length > 0 ? 1.0 : 0.4)
              .onClick(() => {
                this.deleteSelectedDownloads();
              })

            Button('返回')
              .layoutWeight(1)
              .height(46)
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(23)
              .fontSize(14)
              .onClick(() => {
                this.exitSelectMode();
              })
          }
          .width('92%')
          .margin({ bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('下载管理')
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      this.refreshDownloads();
    })
    .onBackPressed((): boolean => {
      if (this.selectMode) {
        this.exitSelectMode();
        return true;
      }
      return false;
    })
  }
}
