import { PlayerController } from '../service/PlayerController';
import { PlayHistoryItem } from '../model/PlayHistoryItem';
import { BiliVideo } from '../model/BiliVideo';
import { Constants } from '../service/Constants';
import { connectBool, connectStr, BoolState, StrState } from '../service/V2State';
import { CoverThumb } from './CoverThumb';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

// 历史归并行（US6 纯展示层派生视图，不落盘）：bvid 聚合为一行，
// latest = 该视频 viewAt 最新的分P 历史（行状态源，点行续播目标）
class HistoryRow {
  bvid: string = '';
  latest: PlayHistoryItem = new PlayHistoryItem();
}

// 播放历史懒加载数据源：LazyForEach 只构建可视区域内的列表项，避免长历史一次性创建全部封面
class HistoryDataSource implements IDataSource {
  private rows: HistoryRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HistoryRow {
    return this.rows[index];
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

  setItems(next: HistoryRow[]): void {
    // 入参可能是 @Local 数组的代理对象（重新赋值后代理会更换），拷贝成普通数组避免渲染源失联
    this.rows = next.slice(0);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  // 归并行删除通知（US3 FR-009）：LazyForEach 增量删除指定下标；
  // 按 DataChangeListener 契约，先从自身数据删除对应下标再通知监听者
  notifyDataDelete(index: number): void {
    if (index < 0 || index >= this.rows.length) {
      return;
    }
    this.rows.splice(index, 1);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

// 播放历史面板（Index L4 独立层，GlassSheet 承载）：US6 按视频归并——一视频一行（主行 videoTitle，
// 副行「相对时间 · 看到Pn · 剩余/已听完」），点行续播最新分P，多选/左滑删除均 bvid 级；
// 点击仅起播不收面板，清空需二次确认；背景由容器提供（sheet_panel_background），关闭经容器动画滑出
@ComponentV2
export struct HistorySheet {
  @Local historyRows: HistoryRow[] = [];
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

  // US6 归并派生（D11）：按 bvid 聚合、viewAt 最新分P 为代表、按代表 viewAt 倒序；
  // 纯展示层派生（FR-015），controller 存储仍分P 粒度，不落盘
  private buildMergedRows(items: PlayHistoryItem[]): HistoryRow[] {
    const rows: HistoryRow[] = [];
    const byBvid: Map<string, HistoryRow> = new Map<string, HistoryRow>();
    for (let i = 0; i < items.length; i++) {
      const item: PlayHistoryItem = items[i];
      let row: HistoryRow | undefined = byBvid.get(item.bvid);
      if (row === undefined) {
        row = new HistoryRow();
        row.bvid = item.bvid;
        row.latest = item;
        byBvid.set(item.bvid, row);
        rows.push(row);
      } else if (item.viewAt > row.latest.viewAt) {
        row.latest = item;
      }
    }
    rows.sort((a: HistoryRow, b: HistoryRow): number => b.latest.viewAt - a.latest.viewAt);
    return rows;
  }

  private syncFrom(c: PlayerController): void {
    if (this.playHistoryVersion !== c.playHistoryVersion) {
      this.playHistoryVersion = c.playHistoryVersion;
      this.historyRows = this.buildMergedRows(c.playHistory);
      this.playHistorySource.setItems(this.historyRows);
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

  // 归并行主行标题：纯视频标题（videoTitle，旧数据/空缺回退 title）
  private rowTitle(row: HistoryRow): string {
    return row.latest.videoTitle !== '' ? row.latest.videoTitle : row.latest.title;
  }

  // 归并行副行三段文案（D14，修订：分P 名不展示）：相对时间恒最前；代表分P page>1 时插「看到Pn」；
  // 尾段沿用既有规则（progress===-1 已听完 / 有进度且时长已知 剩 mm:ss / 其余降级省略）。
  // 单P 与仅 P1 历史的多P 无中段，形态与第一轮一致
  private historyMetaText(item: PlayHistoryItem): string {
    const segments: string[] = [this.formatPlayedAt(item.viewAt)];
    if (item.page > 1) {
      segments.push(`看到P${item.page}`);
    }
    if (item.progress === -1) {
      segments.push('已听完');
    } else if (item.progress > 0 && item.duration > 0 && item.duration > item.progress) {
      segments.push(`剩 ${this.formatRemainingSec(item.duration - item.progress)}`);
    }
    return segments.join(' · ');
  }

  // 点归并行：以代表分P（viewAt 最新）走既有历史点播链路起播 + 唤起播放浮层；播放层（L3）物理在
  // 历史面板（L4）之下，面板保持打开，收起面板即见播放页；page/cid/videoTitle/partTitle 透传
  // 保证点播为分P 粒度条目且历史写入链自动携带新字段
  private async replayHistory(item: PlayHistoryItem): Promise<void> {
    try {
      const v: BiliVideo = BiliVideo.create(item.bvid, 0, item.cid, item.title, item.cover, item.duration);
      v.ownerName = item.ownerName;
      v.page = item.page;
      v.videoTitle = item.videoTitle !== '' ? item.videoTitle : item.title;
      v.partTitle = item.partTitle;
      await this.controller.playDownloadedSong(v);
      connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = true;
    } catch (err) {
      const error = err as BusinessError;
      promptAction.showToast({ message: `播放失败: ${error.message}` });
    }
  }

  // 左滑删除归并行（US6 bvid 级，D11）：一行 = 该视频全部分P 历史——先从 controller 实时历史
  // 展开该 bvid 全部复合键，逐键调既有 removePlayHistoryItem（存储零变化），再做行级补位动画；
  // 点击时实时解析下标，避免 LazyForEach 键复用导致的陈旧索引
  private removeHistoryRow(row: HistoryRow): void {
    if (row.bvid === '') {
      return;
    }
    const pages: number[] = [];
    const history: PlayHistoryItem[] = this.controller.playHistory;
    for (let i = 0; i < history.length; i++) {
      if (history[i].bvid === row.bvid) {
        pages.push(history[i].page);
      }
    }
    if (pages.length === 0) {
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < this.historyRows.length; i++) {
      if (this.historyRows[i].bvid === row.bvid) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    for (let i = 0; i < pages.length; i++) {
      this.controller.removePlayHistoryItem(row.bvid, pages[i]);
    }
    this.playHistoryVersion = this.controller.playHistoryVersion;
    this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
      this.historyRows.splice(idx, 1);
      this.playHistorySource.notifyDataDelete(idx);
    });
  }

  // 左滑删除确认（US1 双触发）：点垃圾桶/滑过阈值（SwipeActionItem.onAction）均进本弹窗，
  // 确认后删除，取消/点外围经 closeAllSwipeActions 复位收起滑动行
  private confirmRemoveHistoryRow(row: HistoryRow): void {
    AlertDialog.show({
      title: Constants.DIALOG_DELETE_HISTORY_TITLE,
      message: Constants.DIALOG_DELETE_HISTORY_MSG,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger_red'),
        action: (): void => {
          this.removeHistoryRow(row);
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
  historyDeleteAction(row: HistoryRow) {
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
        this.confirmRemoveHistoryRow(row);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Constants.TOKEN_SPACE_M, right: Constants.TOKEN_SPACE_M })
  }

  private toggleHistorySelect(key: string): void {
    const idx: number = this.selectedHistoryIds.indexOf(key);
    if (idx >= 0) {
      this.selectedHistoryIds.splice(idx, 1);
    } else {
      this.selectedHistoryIds.push(key);
    }
    this.selectedHistoryIds = this.selectedHistoryIds.slice(0);
  }

  private isAllHistorySelected(): boolean {
    return this.historyRows.length > 0 && this.selectedHistoryIds.length === this.historyRows.length;
  }

  private toggleHistorySelectAll(): void {
    if (this.isAllHistorySelected()) {
      this.selectedHistoryIds = [];
    } else {
      const all: string[] = [];
      for (let i = 0; i < this.historyRows.length; i++) {
        all.push(this.historyRows[i].bvid);
      }
      this.selectedHistoryIds = all;
    }
  }

  private exitHistorySelectMode(): void {
    this.selectMode.value = false;
    this.selectedHistoryIds = [];
  }

  // 删除所选归并行（US6 bvid 级，D11）：二次确认后 UI 层把每个选中 bvid 展开为该视频全部分P
  // 复合键（itemKeyOf 合成）调既有 removeSelectedHistory（controller 存储零变化），
  // 先退多选再高→低增量补位动画，交互对齐队列
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
          const bvids: string[] = this.selectedHistoryIds.slice(0);
          this.exitHistorySelectMode();
          const keys: string[] = [];
          const history: PlayHistoryItem[] = this.controller.playHistory;
          for (let i = 0; i < history.length; i++) {
            if (bvids.indexOf(history[i].bvid) >= 0) {
              keys.push(BiliVideo.itemKeyOf(history[i].bvid, history[i].page));
            }
          }
          this.controller.removeSelectedHistory(keys);
          this.playHistoryVersion = this.controller.playHistoryVersion;
          this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS, curve: Curve.EaseOut }, (): void => {
            const idxList: number[] = [];
            for (let i = 0; i < this.historyRows.length; i++) {
              if (bvids.indexOf(this.historyRows[i].bvid) >= 0) {
                idxList.push(i);
              }
            }
            for (let k = idxList.length - 1; k >= 0; k--) {
              this.historyRows.splice(idxList[k], 1);
              this.playHistorySource.notifyDataDelete(idxList[k]);
            }
            if (this.historyRows.length === 0) {
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

            if (this.historyRows.length > 0) {
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

      if (this.historyRows.length === 0) {
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
            LazyForEach(this.playHistorySource, (row: HistoryRow) => {
              ListItem() {
                Row() {
                  if (this.selectMode.value) {
                    Checkbox()
                      .select(this.selectedHistoryIds.indexOf(row.bvid) >= 0)
                      .selectedColor(this.accentColor.value)
                      .width(Constants.SELECT_CHECKBOX_SIZE)
                      .height(Constants.SELECT_CHECKBOX_SIZE)
                      .margin({ right: Constants.TOKEN_SPACE_S })
                      .onChange((value: boolean) => {
                        const inList: boolean = this.selectedHistoryIds.indexOf(row.bvid) >= 0;
                        if (value !== inList) {
                          this.toggleHistorySelect(row.bvid);
                        }
                      })
                  }

                  CoverThumb({ cover: row.latest.cover })

                  Column() {
                    Text(this.rowTitle(row))
                      .fontSize(Constants.TOKEN_FONT_BODY_M)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.historyMetaText(row.latest))
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
                .backgroundColor(this.pressedKey === row.bvid ? $r('app.color.item_pressed_background') : Color.Transparent)
                .onTouch((e: TouchEvent): void => {
                  if (e.type === TouchType.Down) {
                    this.pressedKey = row.bvid;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedKey = '';
                  }
                })
                .onClick(() => {
                  if (this.selectMode.value) {
                    this.toggleHistorySelect(row.bvid);
                  } else {
                    this.replayHistory(row.latest);
                  }
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (!this.selectMode.value) {
                        this.selectMode.value = true;
                        this.selectedHistoryIds = [row.bvid];
                      }
                    })
                )
              }
              // 左滑删除（US1 双触发，US6 bvid 级）：SwipeActionItem——点垃圾桶/滑过阈值均进确认弹窗；
              // 多选态不挂载删除动作，退出多选恢复
              .swipeAction(this.selectMode.value ? {} : {
                end: {
                  builder: (): void => {
                    this.historyDeleteAction(row);
                  },
                  onAction: (): void => {
                    this.confirmRemoveHistoryRow(row);
                  }
                }
              })
            }, (row: HistoryRow) => `${row.bvid}_${row.latest.viewAt}`)
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
