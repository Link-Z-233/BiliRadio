import { PlayerController } from '../service/PlayerController';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { BiliVideo } from '../model/BiliVideo';
import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { CoverThumb } from './CoverThumb';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

// 播放历史懒加载数据源：LazyForEach 只构建可视区域内的列表项，避免长历史一次性创建全部封面
class HistoryDataSource implements IDataSource {
  private items: PlayHistoryItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PlayHistoryItem {
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

  setItems(next: PlayHistoryItem[]): void {
    // 入参可能是 @State 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.items = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  // 单条删除通知（US3 FR-009）：LazyForEach 增量删除指定下标；
  // 按 DataChangeListener 契约，先从自身数据删除对应下标再通知监听者
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

// 播放历史面板（Index L4 独立层，GlassSheet 承载）：最近播放倒序，点击仅起播不收面板，
// 左滑单删/多选批删/清空需二次确认；背景由容器提供（sheet_panel_background），关闭经容器动画滑出
@ComponentV2
export struct HistorySheet {
  @Local playHistoryItems: PlayHistoryItem[] = [];
  @Local playHistoryVersion: number = -1;
  // 多选管理：面板关闭/退出多选时清空，交互对齐队列
  @Local selectMode: BoolState = connectBool(Constants.AS_HISTORY_SELECT_MODE, false);
  @Local selectedHistoryIds: string[] = [];
  @Local pressedKey: string = '';
  // 面板显隐同源：与 GlassSheet/Index 共享同键实例，关闭时驱动多选复位
  @Local showPlayHistory: BoolState = connectBool(Constants.AS_SHOW_PLAY_HISTORY, false);
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  private controller: PlayerController = PlayerController.getInstance();
  private playHistorySource: HistoryDataSource = new HistoryDataSource();
  // ListScroller（extends Scroller）：取消确认后经 closeAllSwipeActions 复位滑动行（US1）
  private historyScroller: ListScroller = new ListScroller();
  // 进度广播退订句柄：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncFrom(this.controller);
    this.unsubscribePlayer = this.controller.subscribe((): void => {
      this.syncFrom(this.controller);
    }, 'HistorySheet');
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
  }

  private syncFrom(c: PlayerController): void {
    if (this.playHistoryVersion !== c.playHistoryVersion) {
      this.playHistoryVersion = c.playHistoryVersion;
      this.playHistoryItems = c.playHistory.slice(0);
      this.playHistorySource.setItems(this.playHistoryItems);
    }
  }

  // 面板关闭（遮罩/返回/滑出任一方式）自动退出多选并清选中
  @Monitor('showPlayHistory.value')
  onPlayHistoryVisibilityChanged(): void {
    if (!this.showPlayHistory.value) {
      this.exitHistorySelectMode();
    }
  }

  // 多选退出即清选中；进入多选即收起已滑出的行（多选态不挂载左滑删除动作）
  @Monitor('selectMode.value')
  onSelectModeChanged(): void {
    if (!this.selectMode.value) {
      this.selectedHistoryIds = [];
    } else {
      this.historyScroller.closeAllSwipeActions();
    }
  }

  // viewAt 为秒级时间戳，内部转毫秒做相对时间计算
  private formatPlayedAt(viewAt: number): string {
    const playedAtMs: number = viewAt * 1000;
    const diff: number = Date.now() - playedAtMs;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    if (diff < 7 * 86400000) {
      return `${Math.floor(diff / 86400000)} 天前`;
    }
    const d: Date = new Date(playedAtMs);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const monthStr: string = month < 10 ? `0${month}` : `${month}`;
    const dayStr: string = day < 10 ? `0${day}` : `${day}`;
    return `${monthStr}-${dayStr}`;
  }

  // 剩余时长格式化：mm:ss，分钟数不封顶，与 QueueSheet.formatTime 风格一致
  private formatRemainingSec(remainingSec: number): string {
    const minutes: number = Math.floor(remainingSec / 60);
    const seconds: number = remainingSec % 60;
    const minStr: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const secStr: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minStr}:${secStr}`;
  }

  // 历史条目第二行文案：已听完 → 「日期 · 已听完」；
  // 有进度且时长已知 → 「日期 · 剩 mm:ss」；其余（未记录进度/时长未知）降级为仅日期
  private historyMetaText(item: PlayHistoryItem): string {
    const timeText: string = this.formatPlayedAt(item.viewAt);
    if (item.progress === -1) {
      return `${timeText} · 已听完`;
    }
    if (item.progress > 0 && item.duration > 0 && item.duration > item.progress) {
      return `${timeText} · 剩 ${this.formatRemainingSec(item.duration - item.progress)}`;
    }
    return timeText;
  }

  // 点历史条目：起播 + 唤起播放浮层；播放层（L3）物理在历史面板（L4）之下，
  // 面板保持打开，收起面板即见播放页
  private async replayHistory(item: PlayHistoryItem): Promise<void> {
    try {
      const v: BiliVideo = BiliVideo.create(item.bvid, 0, 0, item.title, item.cover, item.duration);
      v.ownerName = item.ownerName;
      await this.controller.playDownloadedSong(v);
      connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = true;
    } catch (err) {
      const error = err as BusinessError;
      promptAction.showToast({ message: `播放失败: ${error.message}` });
    }
  }

  // 左滑单条删除（US3 FR-009）：点击时按 bvid 从当前数组实时解析下标，
  // 避免 LazyForEach 键复用导致的陈旧索引；数组 splice 与 DataSource.notifyDataDelete 双侧同步
  // （包补位动画 US6），控制器侧异步写盘（removePlayHistoryItem 不 emitUi，面板自行刷新）
  private removeHistoryItem(item: PlayHistoryItem): void {
    const bvid: string = item.bvid;
    if (bvid === '') {
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < this.playHistoryItems.length; i++) {
      if (this.playHistoryItems[i].bvid === bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    this.controller.removePlayHistoryItem(bvid);
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.playHistoryItems.splice(idx, 1);
      this.playHistorySource.notifyDataDelete(idx);
    });
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除，取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveHistoryItem(item: PlayHistoryItem): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_HISTORY_TITLE,
      message: Constants.DIALOG_DELETE_HISTORY_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.removeHistoryItem(item);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
          this.historyScroller.closeAllSwipeActions();
        }
      },
      cancel: (): void => {
        this.historyScroller.closeAllSwipeActions();
      }
    });
  }

  // 左滑露出的红色垃圾桶删除钮（US1 双触发）：点击进确认弹窗，滑过阈值（onAction）同弹窗
  @Builder
  historyDeleteAction(item: PlayHistoryItem) {
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
        this.confirmRemoveHistoryItem(item);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  private toggleHistorySelect(bvid: string): void {
    const idx: number = this.selectedHistoryIds.indexOf(bvid);
    if (idx >= 0) {
      this.selectedHistoryIds.splice(idx, 1);
    } else {
      this.selectedHistoryIds.push(bvid);
    }
    this.selectedHistoryIds = this.selectedHistoryIds.slice(0);
  }

  private isAllHistorySelected(): boolean {
    return this.playHistoryItems.length > 0 && this.selectedHistoryIds.length === this.playHistoryItems.length;
  }

  private toggleHistorySelectAll(): void {
    if (this.isAllHistorySelected()) {
      this.selectedHistoryIds = [];
    } else {
      const all: string[] = [];
      for (let i = 0; i < this.playHistoryItems.length; i++) {
        all.push(this.playHistoryItems[i].bvid);
      }
      this.selectedHistoryIds = all;
    }
  }

  private exitHistorySelectMode(): void {
    this.selectMode.value = false;
    this.selectedHistoryIds = [];
  }

  // 删除所选（US4）：二次确认后批量删除，先退多选再高→低增量补位动画，交互对齐队列
  private removeSelectedHistory(): void {
    const count: number = this.selectedHistoryIds.length;
    if (count === 0) {
      return;
    }
    AlertDialog.show({
      title: Constants.DIALOG_REMOVE_SELECTED_TITLE,
      message: Constants.DIALOG_REMOVE_SELECTED_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          const ids: string[] = this.selectedHistoryIds.slice(0);
          this.exitHistorySelectMode();
          this.controller.removeSelectedHistory(ids);
          this.playHistoryVersion = this.controller.playHistoryVersion;
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            const idxList: number[] = [];
            for (let i = 0; i < this.playHistoryItems.length; i++) {
              if (ids.indexOf(this.playHistoryItems[i].bvid) >= 0) {
                idxList.push(i);
              }
            }
            for (let k = idxList.length - 1; k >= 0; k--) {
              this.playHistoryItems.splice(idxList[k], 1);
              this.playHistorySource.notifyDataDelete(idxList[k]);
            }
            if (this.playHistoryItems.length === 0) {
              this.exitHistorySelectMode();
            }
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

  build() {
    Column() {
      Column() {
        if (!this.selectMode.value) {
          Row() {
            Text('播放历史')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            if (this.playHistoryItems.length > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.list_checkmark'))
                  .fontSize(Constants.TOKEN_FONT_18)
                  .fontColor([$r('app.color.text_primary')])
              }
              .width(Constants.GLASS_ICON_BTN_SIZE)
              .height(Constants.GLASS_ICON_BTN_SIZE)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.btn_glass'))
              .backdropBlur(Constants.GLASS_ICON_BTN_BLUR)
              .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
              .borderRadius(Constants.TOKEN_RADIUS_18)
              .onClick(() => {
                this.selectMode.value = true;
                this.selectedHistoryIds = [];
              })
            }
          }
          .width('100%')
        } else {
          // 多选操作行（US4，对齐队列）：全选/删除所选(计数)/返回
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_on_circle'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([this.isAllHistorySelected() ? this.accentColor.value : $r('app.color.text_primary')])
            }
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_ICON_BTN_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .onClick(() => {
              this.toggleHistorySelectAll();
            })

            Blank()

            Row({ space: Constants.TOKEN_SPACE_XS }) {
              SymbolGlyph($r('sys.symbol.trash_fill'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.danger_red')])
              Text(`${this.selectedHistoryIds.length}`)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.danger_red'))
            }
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_ICON_BTN_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .opacity(this.selectedHistoryIds.length > 0 ? 1 : 0.4)
            .onClick(() => {
              this.removeSelectedHistory();
            })

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(Constants.TOKEN_FONT_18)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(Constants.GLASS_ICON_BTN_SIZE)
            .height(Constants.GLASS_ICON_BTN_SIZE)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.btn_glass'))
            .backdropBlur(Constants.GLASS_ICON_BTN_BLUR)
            .border({ width: Constants.GLASS_ICON_BTN_BORDER, color: $r('app.color.btn_border') })
            .borderRadius(Constants.TOKEN_RADIUS_18)
            .margin({ left: Constants.TOKEN_SPACE_S })
            .onClick(() => {
              this.exitHistorySelectMode();
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })

      if (this.playHistoryItems.length === 0) {
        Column() {
          Text('暂无播放历史，听歌后会自动记录')
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 80 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        Stack() {
          List({ space: 0, scroller: this.historyScroller }) {
            LazyForEach(this.playHistorySource, (item: PlayHistoryItem) => {
              ListItem() {
                Row() {
                  if (this.selectMode.value) {
                    Checkbox()
                      .select(this.selectedHistoryIds.indexOf(item.bvid) >= 0)
                      .selectedColor(this.accentColor.value)
                      .width(Constants.SELECT_CHECKBOX_SIZE)
                      .height(Constants.SELECT_CHECKBOX_SIZE)
                      .margin({ right: Constants.TOKEN_SPACE_S })
                      .onChange((value: boolean) => {
                        const inList: boolean = this.selectedHistoryIds.indexOf(item.bvid) >= 0;
                        if (value !== inList) {
                          this.toggleHistorySelect(item.bvid);
                        }
                      })
                  }

                  CoverThumb({ cover: item.cover })

                  Column() {
                    Text(item.title)
                      .fontSize(Constants.TOKEN_FONT_BODY_M)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.historyMetaText(item))
                      .fontSize(Constants.TOKEN_FONT_AUX)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: Constants.TOKEN_SPACE_10 })
                }
                .width('100%')
                .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_10, bottom: Constants.TOKEN_SPACE_10 })
                .backgroundColor(this.pressedKey === item.bvid ? $r('app.color.item_pressed_background') : Color.Transparent)
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.pressedKey = item.bvid;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => {
                  if (this.selectMode.value) {
                    this.toggleHistorySelect(item.bvid);
                  } else {
                    this.replayHistory(item);
                  }
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (!this.selectMode.value) {
                        this.selectMode.value = true;
                        this.selectedHistoryIds = [item.bvid];
                      }
                    })
                )
              }
              // 左滑删除（US1 双触发）：SwipeActionItem——点垃圾桶/滑过阈值均进确认弹窗；
              // 多选态不挂载删除动作，退出多选恢复
              .swipeAction(this.selectMode.value ? {} : {
                end: {
                  builder: (): void => {
                    this.historyDeleteAction(item);
                  },
                  onAction: (): void => {
                    this.confirmRemoveHistoryItem(item);
                  }
                }
              })
            }, (item: PlayHistoryItem) => `${item.bvid}_${item.viewAt}_${item.progress}`)
          }
          .width('100%')
          .height('100%')
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
