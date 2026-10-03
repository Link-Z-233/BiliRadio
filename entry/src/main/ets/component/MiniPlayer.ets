import { PlayerController } from '../service/PlayerController';
import { AppStore } from '../service/AppStore';
import { Constants } from '../service/Constants';
import { CoverThumb } from './CoverThumb';

// 底部迷你播放条：队列有内容时常驻；点按左侧区域唤起全屏播放层
@Component
export struct MiniPlayer {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @State hasContent: boolean = false;
  @State cover: string = '';
  @State title: string = '';
  @State ownerName: string = '';
  @State isPlaying: boolean = false;
  @State isPreparing: boolean = false;

  aboutToAppear(): void {
    PlayerController.getInstance().subscribe((): void => {
      this.syncFromPlayer();
    });
    this.syncFromPlayer();
  }

  private syncFromPlayer(): void {
    const c: PlayerController = PlayerController.getInstance();
    const idxOk: boolean = c.currentIndex >= 0 && c.currentIndex < c.playlist.length;
    const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    const has: boolean = c.playlist.length > 0;
    const cover: string = idxOk && !dataSaver ? c.playlist[c.currentIndex].cover : '';
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
    if (c.isPlaying !== this.isPlaying) {
      this.isPlaying = c.isPlaying;
    }
    if (c.isPreparing !== this.isPreparing) {
      this.isPreparing = c.isPreparing;
    }
  }

  build() {
    if (this.hasContent) {
      Row() {
        Row() {
          CoverThumb({ cover: this.cover, thumbSize: 44, radius: 8 })
          Column() {
            Text(this.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.ownerName !== '') {
              Text(this.ownerName)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 10, right: 6 })
        }
        .layoutWeight(1)
        .onClick(() => {
          AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, true);
        })

        if (this.isPlaying || this.isPreparing) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(24)
            .fontColor([this.accentColor])
            .padding(8)
            .onClick(() => {
              PlayerController.getInstance().togglePlay();
            })
        } else {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(24)
            .fontColor([this.accentColor])
            .padding(8)
            .onClick(() => {
              PlayerController.getInstance().togglePlay();
            })
        }
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
          .padding(8)
          .onClick(() => {
            PlayerController.getInstance().next();
          })
        SymbolGlyph($r('sys.symbol.chevron_up'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
          .padding(8)
          .onClick(() => {
            AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, true);
          })
      }
      .width('100%')
      .padding({ left: 10, right: 6, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(24)
      .margin({ left: 16, right: 16, bottom: 6 })
      .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 2 })
    }
  }
}
