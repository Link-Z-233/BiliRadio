import { PlayerController } from '../service/PlayerController';
import { Constants } from '../service/Constants';
import { connectBool, connectNum, connectStr, NumState, StrState } from '../service/V2State';
import { CoverThumb } from './CoverThumb';

// 底部迷你播放条：队列有内容时显示曲目信息，为空时显示占位条（US2）；点按唤起全屏播放层
@ComponentV2
export struct MiniPlayer {
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local navBarHeight: NumState = connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);
  @Local hasContent: boolean = false;
  @Local cover: string = '';
  @Local title: string = '';
  @Local ownerName: string = '';
  @Local playIntent: boolean = false;

  // 进度广播退订句柄（US2/KI-1）：aboutToDisappear 中调用，避免监听器累积
  private unsubscribePlayer: () => void = (): void => {};

  aboutToAppear(): void {
    this.unsubscribePlayer = PlayerController.getInstance().subscribe((): void => {
      this.syncFromPlayer();
    }, 'MiniPlayer');
    this.syncFromPlayer();
  }

  aboutToDisappear(): void {
    this.unsubscribePlayer();
    this.unsubscribePlayer = (): void => {};
  }

  private syncFromPlayer(): void {
    const c: PlayerController = PlayerController.getInstance();
    const idxOk: boolean = c.currentIndex >= 0 && c.currentIndex < c.playlist.length;
    const has: boolean = c.playlist.length > 0;
    const cover: string = idxOk ? c.playlist[c.currentIndex].cover : '';
    const title: string = idxOk ? c.playlist[c.currentIndex].title : '';
    const owner: string = idxOk ? c.playlist[c.currentIndex].ownerName : '';
    // emitUi 在秒级进度 tick 中触发，仅值真正变化时才写状态
    if (has !== this.hasContent) {
      this.hasContent = has;
    }
    if (cover !== this.cover) {
      this.cover = cover;
    }
    if (title !== this.title) {
      this.title = title;
    }
    if (owner !== this.ownerName) {
      this.ownerName = owner;
    }
    if (c.playIntent !== this.playIntent) {
      this.playIntent = c.playIntent;
    }
  }

  build() {
    if (this.hasContent) {
      Row() {
        Row() {
          CoverThumb({ cover: this.cover, radius: 8 })
          Column() {
            Text(this.title)
              .fontSize(Constants.TOKEN_FONT_BODY_M)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.ownerName !== '') {
              Text(this.ownerName)
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: Constants.TOKEN_SPACE_XXS })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_6 })
        }
        .layoutWeight(1)

        if (this.playIntent) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(Constants.TOKEN_FONT_24)
            .fontColor([this.accentColor.value])
            .padding(Constants.TOKEN_SPACE_S)
            .onClick(() => {
              PlayerController.getInstance().togglePlay();
            })
        } else {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(Constants.TOKEN_FONT_24)
            .fontColor([this.accentColor.value])
            .padding(Constants.TOKEN_SPACE_S)
            .onClick(() => {
              PlayerController.getInstance().togglePlay();
            })
        }
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(Constants.TOKEN_FONT_20)
          .fontColor([$r('app.color.text_primary')])
          .padding(Constants.TOKEN_SPACE_S)
          .onClick(() => {
            PlayerController.getInstance().next();
          })
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(Constants.TOKEN_FONT_20)
          .fontColor([$r('app.color.text_primary')])
          .padding(Constants.TOKEN_SPACE_S)
          .onClick(() => {
            connectBool(Constants.AS_SHOW_QUEUE_SHEET, false).value = true;
          })
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_6, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
      .backgroundColor($r('app.color.miniplayer_background'))
      .backdropBlur(24)
      .borderRadius(Constants.TOKEN_RADIUS_XXL)
      .margin({ bottom: this.navBarHeight.value + 8 })
      .shadow({ radius: Constants.TOKEN_FLOATING_SHADOW_RADIUS, color: $r('app.color.shadow_ball'), offsetX: 0, offsetY: Constants.TOKEN_FLOATING_SHADOW_OFFSET_Y })
      .onClick(() => {
        connectBool(Constants.AS_SHOW_PLAYER_OVERLAY, false).value = true;
      })
    } else {
      // 空态占位条（US2）：队列无内容时显示占位封面+提示，不显示残留歌曲信息；点按无动作（R3 US4）
      Row() {
        CoverThumb({ cover: '', radius: 8 })
        Text('暂无播放内容')
          .fontSize(Constants.TOKEN_FONT_BODY_M)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_6 })
      }
      .width('100%')
      .padding({ left: Constants.TOKEN_SPACE_10, right: Constants.TOKEN_SPACE_10, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.miniplayer_background'))
      .backdropBlur(24)
      .borderRadius(Constants.TOKEN_RADIUS_XXL)
      .margin({ bottom: this.navBarHeight.value + 8 })
      .shadow({ radius: Constants.TOKEN_FLOATING_SHADOW_RADIUS, color: $r('app.color.shadow_ball'), offsetX: 0, offsetY: Constants.TOKEN_FLOATING_SHADOW_OFFSET_Y })
    }
  }
}
