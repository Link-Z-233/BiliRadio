import { PlayerController } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';


import { Constants } from '../service/Constants';
import { AppStore } from '../service/AppStore';
import { CoverThumb } from './CoverThumb';
import { EdgeHint } from './EdgeHint';
import { promptAction } from '@kit.ArkUI';

// 颜色全部使用 base/dark 双份颜色资源：浅色/深色外观下自动匹配（见 resources/base|dark/element/color.json）

// 列表上下边缘渐变模糊半径；sheet 底部安全留白
const EDGE_BLUR_RADIUS: number = 48;
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

  // 单项增量删除通知（queue-redesign plan R7）：镜像 HistoryDataSource——先裁自身再广播，
  // 供左滑删除/清除已播从高索引向低索引逐项刷新，避免整表 reload 造成的封面闪烁
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    this.items.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

// 队列 diff（queue-redesign plan R7）：next 可由 old 纯删除得到时返回被删下标（升序），
// 否则（增长/重排）返回 undefined，调用方走整表 reload；相等返回空数组（no-op，不触发刷新）
function diffRemovedIndices(old: BiliVideo[], next: BiliVideo[]): number[] | undefined {
  const removed: number[] = [];
  let j: number = 0;
  for (let i = 0; i < old.length; i++) {
    if (j < next.length && old[i].bvid === next[j].bvid) {
      j++;
    } else {
      removed.push(i);
    }
  }
  if (j !== next.length) {
    return undefined;
  }
  return removed;
}

// 播放队列抽屉：单行图标头部（清除已播/多选/清空）、左滑单条删除、多选批量移除
@Component
export struct QueueSheet {
  @State items: BiliVideo[] = [];
  @State currentIndex: number = -1;
  @State currentItemEnded: boolean = false;
  @State playlistVersion: number = -1;
  @StorageLink('playlistSelectMode') selectMode: boolean = false; // key 与 Constants.AS_PLAYLIST_SELECT_MODE 对应
  @State selectedBvids: string[] = [];
  // US5：无图模式下条目封面置空（走 CoverThumb 占位），读取链路对齐 MiniPlayer
  @State dataSaverOn: boolean = false;

  @State pageHeight: number = 0;
  @State headerHeight: number = 72;
  @State queueTopHint: string = '';
  @State queueBottomHint: string = '';

  @StorageLink('showQueueSheet') showQueueSheet: boolean = false;
  @StorageProp('isWideScreen') isWideScreen: boolean = false;
  // 主题色（T016）：强调色运行时跟随外观设置（Appearance 写入 AppStorage），衍生色一律经 hexWithAlpha
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
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

  private listSource: PlaylistDataSource = new PlaylistDataSource();
  private listScroller: Scroller = new Scroller();
  private swipeStartIndex: number = -1;
  private queueEndY: number = -1;
  private queueDragging: boolean = false;
  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
    }, 'QueueSheet');
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
  }

  private syncFrom(c: PlayerController): void {
    if (this.playlistVersion !== c.playlistVersion) {
      this.playlistVersion = c.playlistVersion;
      const next: BiliVideo[] = c.playlist.slice(0);
      // 纯删除走增量 notifyDataDelete（从高到低），增长/重排走整表 reload，相等 no-op
      const removed: number[] | undefined = diffRemovedIndices(this.items, next);
      if (removed === undefined) {
        this.items = next;
        this.listSource.setItems(this.items);
      } else {
        for (let i = removed.length - 1; i >= 0; i--) {
          this.listSource.notifyDataDelete(removed[i]);
        }
        this.items = next;
      }
      if (this.selectMode) {
        const valid: string[] = [];
        for (let i = 0; i < this.selectedBvids.length; i++) {
          if (this.items.findIndex((v: BiliVideo): boolean => v.bvid === this.selectedBvids[i]) >= 0) {
            valid.push(this.selectedBvids[i]);
          }
        }
        this.selectedBvids = valid;
        if (this.items.length === 0) {
          this.selectMode = false;
        }
      }
    }
    this.currentIndex = c.currentIndex;
    this.currentItemEnded = c.currentItemEnded;
    this.dataSaverOn = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
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

  // 左滑单条删除（US2 FR-004/FR-005）：按 bvid 走既有批量移除链路
  // （含当前条目自动切播语义，FR-010），UI 刷新交由 syncFrom 的 diff 增量通知
  private removeQueueItem(item: BiliVideo): void {
    if (item.bvid === '') {
      return;
    }
    this.queueEndY = -1;
    this.controller.removeSelectedFromPlaylist([item.bvid]);
  }

  // 清除已播（US4 FR-009）：无可清（无前缀且未播完）toast 不弹框，可清时二次确认
  private confirmClearPlayed(): void {
    const canClear: boolean = this.controller.currentIndex > 0 || this.controller.currentItemEnded;
    if (!canClear) {
      promptAction.showToast({ message: Constants.TOAST_QUEUE_NO_PLAYED });
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_CLEAR_PLAYED_TITLE,
      message: this.controller.currentItemEnded
        ? Constants.DIALOG_CLEAR_PLAYED_ENDED_MSG : Constants.DIALOG_CLEAR_PLAYED_PLAYING_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '清除',
        action: (): void => {
          this.controller.clearPlayedItems();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
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

  // 左滑露出的红色「删除」按钮（US2，样式对齐 SettingsPage.historyDeleteAction：
  // 露出按钮、点击执行删除，不做滑过阈值直删）
  @Builder
  queueDeleteAction(item: BiliVideo) {
    Button('删除')
      .height('100%')
      .padding({ left: 18, right: 18 })
      .backgroundColor($r('app.color.danger_red'))
      .fontColor(Color.White)
      .fontSize(13)
      .borderRadius(0)
      .onClick(() => {
        this.removeQueueItem(item);
      })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 单行头部（US1）：标题 + 清除已播/多选/清空三图标；多选态整行替换为多选操作行
      Column() {
        if (!this.selectMode) {
          Row() {
            Text(`播放队列 (${this.items.length})`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .layoutWeight(1)

            if (this.items.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(18)
              .onClick(() => {
                this.confirmClearPlayed();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.list_checkmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(18)
              .margin({ left: 8 })
              .onClick(() => {
                this.selectMode = true;
                this.selectedBvids = [];
              })

              Row() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(18)
              .margin({ left: 8 })
              .onClick(() => {
                this.clearQueue();
              })
            }
          }
          .width('100%')
        } else {
          // 多选操作行（US1 FR-006/FR-011/FR-012）：全选/移除所选(计数)/返回全部图标化
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_on_circle'))
                .fontSize(18)
                .fontColor([this.isAllSelected() ? this.accentColor : $r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(18)
            .onClick(() => {
              this.toggleSelectAll();
            })

            Blank()

            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.trash_fill'))
                .fontSize(18)
                .fontColor([$r('app.color.danger_red')])
              Text(`${this.selectedBvids.length}`)
                .fontSize(12)
                .fontColor($r('app.color.danger_red'))
            }
            .height(36)
            .padding({ left: 10, right: 10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(18)
            .opacity(this.selectedBvids.length > 0 ? 1 : 0.4)
            .onClick(() => {
              this.removeSelected();
            })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(18)
            .margin({ left: 8 })
            .onClick(() => {
              this.exitSelectMode();
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
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
          Text(Constants.QUEUE_EMPTY_HINT)
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
        Stack() {
          EdgeHint({ text: this.queueTopHint, edge: 'top' })
          EdgeHint({ text: this.queueBottomHint, edge: 'bottom' })
          List({ space: 0, scroller: this.listScroller }) {
            LazyForEach(this.listSource, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  if (this.selectMode) {
                    Checkbox()
                      .select(this.selectedBvids.indexOf(item.bvid) >= 0)
                      .selectedColor(this.accentColor)
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

                  CoverThumb({ cover: this.dataSaverOn ? '' : item.cover, highlight: index === this.currentIndex })

                  Column() {
                    Row() {
                      Text(item.title)
                        .fontSize(14)
                        .fontColor(index === this.currentIndex ? this.accentColor : this.textPrimary())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')

                    // FR-104：duration 未知（0）不渲染 00:00 占位，只显示 UP 主名
                    Text(item.duration > 0 ? `${item.ownerName} · ${this.formatTime(item.duration * 1000)}` : item.ownerName)
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
                .backgroundColor(Color.Transparent)
                .borderRadius(12)
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(item.bvid);
                  } else {
                    // 仅切换歌曲，不跳转播放页
                    this.controller.playIndex(index, 0);
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
              .swipeAction({
                end: this.queueDeleteAction(item)
              })
            }, (item: BiliVideo) => `${item.bvid}_${item.ownerName}`)
          }
          .width('100%')
          .height('100%')
          // FR-103：alwaysEnabled 使未铺满面板的短队列仍可拖动过冲（写法对齐 SettingsPage 历史面板）
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .contentStartOffset(this.headerHeight)
          .contentEndOffset(LIST_BOTTOM_GAP)
          .linearGradientBlur(EDGE_BLUR_RADIUS, {
            fractionStops: this.listBlurStops(),
            direction: GradientDirection.Bottom
          })
          // FR-103（修订 US5/FR-008）：双向过冲提示——拖拽中拉过顶/底露出「已经到顶了/已经到底了」，回弹消失
          // （模式对齐设置页历史面板；onReachStart 初始化误触发一次，故须拖拽中守卫）
          .onWillStartDragging(() => {
            this.queueDragging = true;
          })
          .onReachStart(() => {
            if (this.queueDragging) {
              this.queueTopHint = '已经到顶了';
            }
          })
          .onReachEnd(() => {
            this.queueEndY = this.listScroller.currentOffset().yOffset;
            if (this.queueDragging) {
              this.queueBottomHint = '已经到底了';
            }
          })
          .onWillScroll((yOffset: number): void => {
            const y: number = this.listScroller.currentOffset().yOffset;
            if (yOffset < 0) {
              this.queueBottomHint = '';
              if (y <= 0) {
                this.queueTopHint = '已经到顶了';
              }
            } else if (yOffset > 0) {
              this.queueTopHint = '';
              if (this.queueEndY >= 0 && y >= this.queueEndY) {
                this.queueBottomHint = '已经到底了';
              }
            }
          })
          .onScrollStop(() => {
            this.queueTopHint = '';
            this.queueBottomHint = '';
            this.queueDragging = false;
          })
        }
        .width('100%')
        .height('100%')
      }

    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageHeight = newArea.height as number;
    })
  }
}
