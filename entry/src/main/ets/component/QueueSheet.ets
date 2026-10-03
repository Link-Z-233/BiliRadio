import { PlayerController } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';


import { DownloadManager } from '../service/DownloadManager';
import { Constants } from '../service/Constants';
import { CoverThumb } from './CoverThumb';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

const FLASH_DURATION_MS: number = 1600;

// 列表上下边缘渐变模糊半径；sheet 底部安全留白
const EDGE_BLUR_RADIUS: number = 48;
const HEADER_FADE_TAIL: number = 8;
const LIST_BOTTOM_GAP: number = 12;
// 列表项近似高度：长按滑动多选时把手指位移换算成经过的条目数（富列表：44 封面 + 上下各 12 内边距）
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
}

// 播放队列半模态：计数/定位当前播放/清空/搜索/添加歌曲/多选删除与保存
@Component
export struct QueueSheet {
  @State items: BiliVideo[] = [];
  @State currentIndex: number = -1;
  @State isPlaying: boolean = false;
  @State playlistVersion: number = -1;
  @State bvInput: string = '';
  @State addMsg: string = '';
  @StorageLink('playlistSelectMode') selectMode: boolean = false; // key 与 Constants.AS_PLAYLIST_SELECT_MODE 对应
  @State selectedBvids: string[] = [];
  @State downloadMsg: string = '';

  // —— 歌曲搜索浮层（本地检索播放列表，零网络请求） ——
  @StorageLink('showSearch') showSearch: boolean = false; // key 与 Constants.AS_SHOW_SEARCH 对应
  @State searchKeyword: string = '';
  @State searchResults: BiliVideo[] = [];
  @State searched: boolean = false;


  @State pageWidth: number = 0;
  @State pageHeight: number = 0;
  @State headerHeight: number = 138;
  @State flashIndex: number = -1;

  @StorageLink('showQueueSheet') showQueueSheet: boolean = false;
  @StorageProp('isWideScreen') isWideScreen: boolean = false;
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

  // 播放列表检索：纯内存遍历，不发起任何网络请求
  private doSearch(): void {
    this.searchResults = this.controller.searchLibrary(this.searchKeyword);
    this.searched = true;
  }

  private async playSearchResult(video: BiliVideo): Promise<void> {
    await this.controller.playFromLibraryResult(video);
    this.controller.goToPlayerTab?.();
  }


  private listSource: PlaylistDataSource = new PlaylistDataSource();
  private listScroller: Scroller = new Scroller();
  private flashTimer: number = -1;
  private swipeStartIndex: number = -1;

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
      this.addMsg = this.controller.statusMsg;

    });
  }

  aboutToDisappear(): void {
    if (this.flashTimer >= 0) {
      clearTimeout(this.flashTimer);
      this.flashTimer = -1;
    }
  }

  private locateCurrent(): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.items.length) {
      return;
    }
    // 平滑滚动会逐项穿过中间所有条目（每项都要建组件、加载封面），长歌单上极易卡顿；
    // 定位场景改为直接跳到目标位置，只构建目标附近的列表项
    this.listScroller.scrollToIndex(this.currentIndex, false, ScrollAlign.CENTER);
    this.flashIndex = this.currentIndex;
    if (this.flashTimer >= 0) {
      clearTimeout(this.flashTimer);
    }
    this.flashTimer = setTimeout((): void => {
      this.flashIndex = -1;
      this.flashTimer = -1;
    }, FLASH_DURATION_MS);
  }

  private syncFrom(c: PlayerController): void {
    if (this.playlistVersion !== c.playlistVersion) {
      this.playlistVersion = c.playlistVersion;
      this.items = c.playlist.slice(0);
      this.listSource.setItems(this.items);
      if (this.selectMode) {
        const valid: string[] = [];
        for (let i = 0; i < this.selectedBvids.length; i++) {
          if (this.items.findIndex((v: BiliVideo): boolean => v.bvid === this.selectedBvids[i]) >= 0) {
            valid.push(this.selectedBvids[i]);
          }
        }
        this.selectedBvids = valid;
      }
    }
    this.currentIndex = c.currentIndex;
    this.isPlaying = c.isPlaying;

  }


  private addByBv(): void {
    const raw: string = this.bvInput.trim();
    if (raw === '') {
      this.addMsg = '请输入BV号';
      return;
    }
    const parts: string[] = raw.split(/[\s,，;；\n]+/);
    const bvs: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const p: string = parts[i].trim();
      if (p !== '' && bvs.indexOf(p) < 0) {
        bvs.push(p);
      }
    }
    if (bvs.length === 0) {
      this.addMsg = '请输入BV号';
      return;
    }
    this.bvInput = '';
    if (bvs.length === 1) {
      this.addMsg = '正在解析...';
      this.controller.addToPlaylist(bvs[0]);
    } else {
      if (bvs.length > 50) {
        this.addMsg = '一次最多添加50个BV号';
        return;
      }
      this.controller.addManyToPlaylist(bvs);
    }
  }

  private toggleSelect(bvid: string): void {
    const idx: number = this.selectedBvids.indexOf(bvid);
    if (idx >= 0) {
      this.selectedBvids.splice(idx, 1);
    } else {
      this.selectedBvids.push(bvid);
    }
    this.selectedBvids = this.selectedBvids.slice(0);
  }

  private selectAll(): void {
    const all: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      all.push(this.items[i].bvid);
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

  // 长按滑动多选：把 from..to 区间内所有条目选中（只增不减）
  private selectRange(from: number, to: number): void {
    const lo: number = Math.max(0, Math.min(from, to));
    const hi: number = Math.min(this.items.length - 1, Math.max(from, to));
    let changed: boolean = false;
    for (let i = lo; i <= hi; i++) {
      const bvid: string = this.items[i].bvid;
      if (this.selectedBvids.indexOf(bvid) < 0) {
        this.selectedBvids.push(bvid);
        changed = true;
      }
    }
    if (changed) {
      this.selectedBvids = this.selectedBvids.slice(0);
    }
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedBvids = [];
  }

  private removeSelected(): void {
    const count: number = this.selectedBvids.length;
    if (count === 0) {
      return;
    }
    const bvids: string[] = this.selectedBvids.slice(0);
    this.exitSelectMode();
    this.controller.removeSelectedFromPlaylist(bvids);
  }

  // 清空队列：移除全部条目（含当前播放），二次确认防误触
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
        action: (): void => {
          const all: string[] = [];
          for (let i = 0; i < this.items.length; i++) {
            all.push(this.items[i].bvid);
          }
          this.controller.removeSelectedFromPlaylist(all);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  // 批量下载选中的歌曲到本地（持久离线缓存）
  private async downloadSelected(): Promise<void> {
    const bvids: string[] = this.selectedBvids.slice(0);
    if (bvids.length === 0) {
      return;
    }
    const dm: DownloadManager = DownloadManager.getInstance();
    let done: number = 0;
    let failed: number = 0;
    let skipped: number = 0;
    for (let i = 0; i < bvids.length; i++) {
      if (dm.isDownloaded(bvids[i])) {
        skipped++;
        continue;
      }
      this.downloadMsg = `正在保存到本地 ${i + 1}/${bvids.length}...`;
      try {
        await dm.downloadSong(bvids[i]);
        done++;
      } catch (e) {
        failed++;
      }
    }
    let msg: string = `保存完成：新增 ${done} 首`;
    if (skipped > 0) {
      msg += `，已保存跳过 ${skipped} 首`;
    }
    if (failed > 0) {
      msg += `，失败 ${failed} 首`;
    }
    this.downloadMsg = '';
    this.exitSelectMode();
    this.addMsg = msg;
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Row() {
          Text('播放队列')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary())
            .layoutWeight(1)

          if (this.items.length > 0) {
            Text(`共 ${this.items.length} 首`)
              .fontSize(13)
              .fontColor(this.textSecondary())
              .margin({ right: 4 })
          }

          if (!this.selectMode) {
            if (this.currentIndex >= 0) {
              Button('定位')
                .height(30)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.btn_glass'))
                .backdropBlur(20)
                .border({ width: 1, color: $r('app.color.btn_border') })
                .fontColor(this.textPrimary())
                .borderRadius(15)
                .fontSize(12)
                .margin({ right: 8 })
                .onClick(() => {
                  this.locateCurrent();
                })
            }

            Button('搜索')
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(15)
              .fontSize(12)
              .margin({ right: 8 })
              .onClick(() => {
                this.showSearch = true;
              })
          }

          if (this.items.length > 0 && !this.selectMode) {
            Button('多选')
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(15)
              .fontSize(12)
              .margin({ right: 8 })
              .onClick(() => {
                this.selectMode = true;
                this.selectedBvids = [];
              })

            Button('清空')
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(15)
              .fontSize(12)
              .onClick(() => {
                this.clearQueue();
              })
          }

          Button('完成')
            .height(30)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .fontColor(this.textPrimary())
            .borderRadius(15)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.showQueueSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 8 })

        if (!this.selectMode) {
          Row() {
            TextInput({ placeholder: 'BV号，多个用空格/逗号/换行分隔', text: this.bvInput })
              .layoutWeight(1)
              .height(40)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .placeholderColor(this.textSecondary())
              .borderRadius(8)
              .fontSize(13)
              .type(InputType.Normal)
              .onChange((value: string) => {
                this.bvInput = value;
              })
              .onSubmit(() => {
                this.addByBv();
              })

            Button('添加并播放')
              .height(40)
              .margin({ left: 8 })
              .backgroundColor($r('app.color.material_tint_primary'))
              .backdropBlur(20)
              .fontColor($r('app.color.text_primary'))
              .borderRadius(8)
              .fontSize(13)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.addByBv();
              })
          }
          .width('92%')
          .margin({ bottom: 4 })

          if (this.addMsg !== '') {
            Text(this.addMsg)
              .fontSize(12)
              .fontColor(this.textSecondary())
              .width('92%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ bottom: 4 })
          }
        } else {
          Row() {
            Button(this.isAllSelected() ? '取消全选' : '全选')
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(18)
              .fontSize(13)
              .onClick(() => {
                this.toggleSelectAll();
              })

            Blank()

            Button(`移除所选(${this.selectedBvids.length})`)
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.selectedBvids.length > 0 ? $r('app.color.material_tint_primary') : $r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .fontSize(13)
              .margin({ left: 8 })
              .onClick(() => {
                this.removeSelected();
              })

            Button(`保存到本地(${this.selectedBvids.length})`)
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.selectedBvids.length > 0 ? $r('app.color.primary_color') : this.textPrimary())
              .borderRadius(18)
              .fontSize(13)
              .margin({ left: 8 })
              .onClick(() => {
                this.downloadSelected();
              })

            Button('返回')
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .fontColor(this.textPrimary())
              .borderRadius(18)
              .fontSize(13)
              .margin({ left: 8 })
              .onClick(() => {
                this.exitSelectMode();
              })
          }
          .width('92%')
          .margin({ bottom: 4 })

          if (this.downloadMsg !== '') {
            Text(this.downloadMsg)
              .fontSize(12)
              .fontColor(this.textSecondary())
              .width('92%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ bottom: 4 })
          }
        }

      }
      .width('100%')
      .padding({ bottom: HEADER_FADE_TAIL })
      .zIndex(1)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.headerHeight = newArea.height as number;
      })

      if (this.items.length === 0) {
        Column() {
          Text('队列为空')
            .fontSize(16)
            .fontColor(this.textSecondary())
            .margin({ top: 60 })
          Text('输入BV号添加歌曲，或到订阅源详情页播放节目')
            .fontSize(13)
            .fontColor(this.textDisabled())
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .padding({ top: this.headerHeight })
      } else {
          List({ space: 0, scroller: this.listScroller }) {
            LazyForEach(this.listSource, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  if (this.selectMode) {
                    Checkbox()
                      .select(this.selectedBvids.indexOf(item.bvid) >= 0)
                      .selectedColor($r('app.color.primary_color'))
                      .width(20)
                      .height(20)
                      .margin({ right: 8 })
                      .onChange((value: boolean) => {
                        const inList: boolean = this.selectedBvids.indexOf(item.bvid) >= 0;
                        if (value !== inList) {
                          this.toggleSelect(item.bvid);
                        }
                      })
                  }

                  CoverThumb({ cover: item.cover, highlight: index === this.currentIndex })

                  Column() {
                    Row() {
                      Text(item.title)
                        .fontSize(14)
                        .fontColor(index === this.currentIndex ? $r('app.color.primary_color') : this.textPrimary())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)

                      Text(item.sourceLabel())
                        .fontSize(10)
                        .fontColor(this.textSecondary())
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor($r('app.color.btn_glass'))
                        .border({ width: 1, color: $r('app.color.btn_border') })
                        .borderRadius(4)
                        .margin({ left: 8 })
                    }
                    .width('100%')

                    Text(`${item.ownerName} · ${this.formatTime(item.duration > 0 ? item.duration * 1000 : 0)}`)
                      .fontSize(11)
                      .fontColor(this.textSecondary())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor(this.flashIndex === index ? $r('app.color.flash_highlight') : Color.Transparent)
                .borderRadius(12)
                .margin({
                  left: this.flashIndex === index ? 8 : 0,
                  right: this.flashIndex === index ? 8 : 0
                })
                .animation({ duration: 300, curve: Curve.FastOutSlowIn })
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(item.bvid);
                  } else {
                    this.controller.playIndex(index, 0);
                    if (this.controller.goToPlayerTab !== undefined) {
                      this.controller.goToPlayerTab();
                    }
                  }
                })
                .gesture(
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture()
                      .onAction(() => {
                        if (!this.selectMode) {
                          this.selectMode = true;
                          this.selectedBvids = [item.bvid];
                          this.swipeStartIndex = index;
                        }
                      }),
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical })
                      .onActionUpdate((event: GestureEvent) => {
                        if (!this.selectMode || this.isWideScreen) {
                          return;
                        }
                        const target: number = this.swipeStartIndex +
                          Math.round(event.offsetY / ITEM_HEIGHT);
                        this.selectRange(this.swipeStartIndex, target);
                      })
                  )
                )
              }
            }, (item: BiliVideo) => item.bvid)
          }
          .width('100%')
          .height('100%')
          .contentStartOffset(this.headerHeight)
          .contentEndOffset(LIST_BOTTOM_GAP)
          .linearGradientBlur(EDGE_BLUR_RADIUS, {
            fractionStops: this.listBlurStops(),
            direction: GradientDirection.Bottom
          })
          .lanes(this.isWideScreen ? 2 : 1)

        }

      if (this.showSearch) {
        this.searchPanel()
      }

    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageWidth = newArea.width as number;
      this.pageHeight = newArea.height as number;
    })
  }

  // 歌曲搜索浮层：半透明毛玻璃覆盖层，本地检索播放列表（零网络请求）
  @Builder
  searchPanel() {
    Column() {
      Row() {
        Text('搜索歌曲')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button('关闭')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .borderRadius(16)
          .fontSize(12)
          .onClick(() => {
            this.showSearch = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Row() {
        TextInput({ placeholder: '搜索歌名或UP主', text: this.searchKeyword })
          .id('search_input')
          .layoutWeight(1)
          .height(40)
          .enterKeyType(EnterKeyType.Search)
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor(this.textPrimary())
          .placeholderColor($r('app.color.placeholder_color'))
          .borderRadius(8)
          .fontSize(13)
          .maxLength(Constants.SEARCH_MAX_INPUT_LEN)
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })

        Button('搜索')
          .height(40)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.btn_glass'))
          .backdropBlur(20)
          .border({ width: 1, color: $r('app.color.btn_border') })
          .fontColor($r('app.color.primary_color'))
          .borderRadius(8)
          .fontSize(13)
          .onClick(() => {
            this.doSearch();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.searched && this.searchResults.length === 0) {
        Column() {
          Text('未找到相关歌曲')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else if (this.searched) {
        Column() {
          Text(`共命中 ${this.searchResults.length} 首`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, bottom: 4 })

          List({ space: 0 }) {
            ForEach(this.searchResults, (video: BiliVideo) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(video.title)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(video.ownerName)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  this.playSearchResult(video);
                })
              }
            }, (video: BiliVideo) => video.bvid)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          Text('输入关键词，搜索播放列表中的歌曲')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      }

      Text(this.controller.statusMsg)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sheet_background'))
    .backdropBlur(20)
    .zIndex(3)
  }
}
