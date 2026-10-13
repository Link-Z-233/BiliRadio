import { PlayerController } from '../service/PlayerController';
import { BiliVideo } from '../model/BiliVideo';


import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { closeBothLayersNow } from '../service/BackHandler';
import { CoverThumb } from './CoverThumb';
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
@ComponentV2
export struct QueueSheet {
  @Local items: BiliVideo[] = [];
  @Local currentIndex: number = -1;
  @Local currentItemEnded: boolean = false;
  @Local playlistVersion: number = -1;
  @Local selectMode: BoolState = connectBool(Constants.AS_PLAYLIST_SELECT_MODE, false);
  @Local selectedBvids: string[] = [];
  @Local pressedKey: string = '';
  // 面板显隐同源（v0.3 US7）：与 GlassSheet/Index 共享同键实例，关闭时驱动多选复位
  @Local showQueueSheet: BoolState = connectBool(Constants.AS_SHOW_QUEUE_SHEET, false);

  @Local pageHeight: number = 0;
  @Local headerHeight: number = 72;

  // 主题色（T016）：强调色运行时跟随外观设置（Appearance 写入 AppStorage），衍生色一律经 hexWithAlpha
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local isWideScreen: BoolState = connectBool(Constants.AS_IS_WIDE_SCREEN, false);
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
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private listScroller: ListScroller = new ListScroller();
  private swipeStartIndex: number = -1;
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

  // 面板关闭（遮罩/返回/滑出任一方式）自动退出多选（v0.3 US7 FR-009）
  @Monitor('showQueueSheet.value')
  onQueueSheetVisibilityChanged(): void {
    if (!this.showQueueSheet.value) {
      this.exitSelectMode();
    }
  }

  // 多选退出即清选中（v0.3 US7）：外部（Index 系统返回）仅翻转 selectMode，选中项由本侧复位
  @Monitor('selectMode.value')
  onSelectModeChanged(): void {
    if (!this.selectMode.value) {
      this.selectedBvids = [];
    } else {
      // 进入多选即收起已滑出的行（v0.4-Part1-ux-fixes US5）：多选态不再挂载左滑删除动作
      this.listScroller.closeAllSwipeActions();
    }
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
      if (this.selectMode.value) {
        const valid: string[] = [];
        for (let i = 0; i < this.selectedBvids.length; i++) {
          if (this.items.findIndex((v: BiliVideo): boolean => v.bvid === this.selectedBvids[i]) >= 0) {
            valid.push(this.selectedBvids[i]);
          }
        }
        this.selectedBvids = valid;
        if (this.items.length === 0) {
          this.selectMode.value = false;
        }
      }
    }
    this.currentIndex = c.currentIndex;
    this.currentItemEnded = c.currentItemEnded;
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
    this.selectMode.value = false;
    this.selectedBvids = [];
  }

  // 多选移除（US2）：二次确认防误触；确认后批量移除包补位动画（US6）
  private removeSelected(): void {
    const count: number = this.selectedBvids.length;
    if (count === 0) {
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_REMOVE_SELECTED_TITLE,
      message: Constants.DIALOG_REMOVE_SELECTED_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          const bvids: string[] = this.selectedBvids.slice(0);
          this.exitSelectMode();
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.removeSelectedFromPlaylist(bvids);
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  // 左滑单条删除（US2 FR-004/FR-005）：按 bvid 走既有批量移除链路
  // （含当前条目自动切播语义，FR-010），UI 刷新交由 syncFrom 的 diff 增量通知
  private removeQueueItem(item: BiliVideo): void {
    if (item.bvid === '') {
      return;
    }
    this.controller.removeSelectedFromPlaylist([item.bvid]);
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除（US6 补位动画），取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveQueueItem(item: BiliVideo): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_QUEUE_ITEM_TITLE,
      message: Constants.DIALOG_DELETE_QUEUE_ITEM_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '移除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.removeQueueItem(item);
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.listScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.listScroller.closeAllSwipeActions();
      }
    });
  }

  // 清除已播（US3）：无可清 toast 不弹框；可清时按可清计数二次确认，确认后按 playedSet 语义清理
  private confirmClearPlayed(): void {
    const count: number = this.controller.playedRemovableCount();
    if (count === 0) {
      promptAction.showToast({ message: Constants.TOAST_QUEUE_NO_PLAYED });
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_CLEAR_PLAYED_TITLE,
      message: Constants.DIALOG_CLEAR_PLAYED_COUNT_MSG.replace('N', `${count}`),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '清除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            this.controller.clearPlayedItems();
          });
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  // 清空队列（R3 US4）：移除全部条目（含当前播放），二次确认防误触；
  // 确认后两层同收（closeBothLayersNow）+ 停声先行、延时清数据（clearAllWithExitDelay）
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
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          closeBothLayersNow();
          this.controller.clearAllWithExitDelay();
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

  // 左滑露出的红色垃圾桶删除钮（US1 双触发）：点击进确认弹窗，滑过阈值（onAction）同弹窗
  @Builder
  queueDeleteAction(item: BiliVideo) {
    Column() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(Constants.SWIPE_DELETE_ICON_FONT)
          .fontColor([$r('app.color.fg_on_dark')])
          .fontWeight(FontWeight.Bold)
      }
      .width(Constants.SWIPE_DELETE_BTN_SIZE)
      .height(Constants.SWIPE_DELETE_BTN_SIZE)
      .backgroundColor($r('app.color.danger_red'))
      .borderRadius(Constants.SWIPE_DELETE_BTN_RADIUS)
      .onClick(() => {
        this.confirmRemoveQueueItem(item);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 单行头部（US1）：标题 + 清除已播/多选/清空三图标；多选态整行替换为多选操作行
      Column() {
        if (!this.selectMode.value) {
          Row() {
            Text(`播放队列 (${this.items.length})`)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary())
              .layoutWeight(1)

            if (this.items.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .onClick(() => {
                this.confirmClearPlayed();
              })

              Row() {
                SymbolGlyph($r('sys.symbol.list_checkmark'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
              .onClick(() => {
                this.selectMode.value = true;
                this.selectedBvids = [];
              })

              Row() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.danger_red')])
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(20)
              .border({ width: 1, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .margin({ left: Constants.TOKEN_SPACE_S })
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
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([this.isAllSelected() ? this.accentColor.value : $r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .onClick(() => {
              this.toggleSelectAll();
            })

            Blank()

            Row({ space: Constants.TOKEN_SPACE_XS }) {
              SymbolGlyph($r('sys.symbol.trash_fill'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.danger_red')])
              Text(`${this.selectedBvids.length}`)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.danger_red'))
            }
            .height(36)
            .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .opacity(this.selectedBvids.length > 0 ? 1 : 0.4)
            .onClick(() => {
              this.removeSelected();
            })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(20)
            .border({ width: 1, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .margin({ left: Constants.TOKEN_SPACE_S })
            .onClick(() => {
              this.exitSelectMode();
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_20, bottom: Constants.TOKEN_SPACE_S })
      .zIndex(1)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.headerHeight = newArea.height as number;
      })

      if (this.items.length === 0) {
        Column() {
          Text('队列为空')
            .fontSize(Constants.TOKEN_FONT_TITLE)
            .fontColor(this.textSecondary())
            .margin({ top: 60 })
          Text(Constants.QUEUE_EMPTY_HINT)
            .fontSize(Constants.TOKEN_FONT_BODY)
            .fontColor(this.textDisabled())
            .margin({ top: Constants.TOKEN_SPACE_S })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .padding({ top: this.headerHeight })
      } else {
        Stack() {
          List({ space: 0, scroller: this.listScroller }) {
            LazyForEach(this.listSource, (item: BiliVideo, index: number) => {
              ListItem() {
                Row() {
                  if (this.selectMode.value) {
                    Checkbox()
                      .select(this.selectedBvids.indexOf(item.bvid) >= 0)
                      .selectedColor(this.accentColor.value)
                      .width(20)
                      .height(20)
                      .margin({ right: Constants.TOKEN_SPACE_S })
                      .onChange((value: boolean) => {
                        const inList: boolean = this.selectedBvids.indexOf(item.bvid) >= 0;
                        if (value !== inList) {
                          this.toggleSelect(item.bvid);
                        }
                      })
                  }

                  CoverThumb({ cover: item.cover, highlight: index === this.currentIndex, accent: this.accentColor.value })

                  Column() {
                    Row() {
                      Text(item.title)
                        .fontSize(Constants.TOKEN_FONT_BODY_M)
                        .fontColor(index === this.currentIndex ? this.accentColor.value : this.textPrimary())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')

                    // FR-104：duration 未知（0）不渲染 00:00 占位，只显示 UP 主名
                    Text(item.duration > 0 ? `${item.ownerName} · ${this.formatTime(item.duration * 1000)}` : item.ownerName)
                      .fontSize(Constants.TOKEN_FONT_AUX)
                      .fontColor(this.textSecondary())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .margin({ top: Constants.TOKEN_SPACE_XS })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: Constants.TOKEN_SPACE_10 })

                  // 已播标记（US4）：非当前条目且已播完时行尾绿 ✓，对齐 SourcePage NEW 徽标视觉
                  if (!this.selectMode.value && this.controller.isPlayed(item.bvid)) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(Constants.TOKEN_FONT_TITLE)
                      .fontColor([$r('app.color.success_green')])
                      .margin({ left: Constants.TOKEN_SPACE_XS })
                  }
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_M, bottom: Constants.TOKEN_SPACE_M })
                .backgroundColor(this.pressedKey === item.bvid ? $r('app.color.item_pressed_background') : Color.Transparent)
                .borderRadius(Constants.TOKEN_RADIUS_M)
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.pressedKey = item.bvid;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => {
                  if (this.selectMode.value) {
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
                        if (!this.selectMode.value) {
                          this.selectMode.value = true;
                          this.selectedBvids = [item.bvid];
                          this.swipeStartIndex = index;
                        }
                      }),
                    PanGesture({ fingers: 1, direction: PanDirection.Vertical })
                      .onActionUpdate((event: GestureEvent) => {
                        if (!this.selectMode.value || this.isWideScreen.value) {
                          return;
                        }
                        const target: number = this.swipeStartIndex +
                          Math.round(event.offsetY / ITEM_HEIGHT);
                        this.selectRange(this.swipeStartIndex, target);
                      })
                  )
                )
              }
              // 多选态不挂载删除动作（v0.4-Part1-ux-fixes US5）：左滑手势随 end 缺失整体禁用，退出多选恢复
              .swipeAction(this.selectMode.value ? {} : {
                end: {
                  builder: (): void => {
                    this.queueDeleteAction(item);
                  },
                  onAction: (): void => {
                    this.confirmRemoveQueueItem(item);
                  }
                }
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
