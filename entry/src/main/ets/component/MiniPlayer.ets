import { PlayerController } from '../service/PlayerController';
import { AppStore } from '../service/AppStore';
import { Constants } from '../service/Constants';
import { CoverThumb } from './CoverThumb';

// 底部迷你播放条：队列有内容时显示曲目信息，为空时显示占位条（US2）；点按唤起全屏播放层
@Component
export struct MiniPlayer {
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  @StorageProp('navBarHeight') navBarHeight: number = 0; // key 与 Constants.AS_NAV_BAR_HEIGHT 对应
  @State hasContent: boolean = false;
  @State cover: string = '';
  @State title: string = '';
  @State ownerName: string = '';
  @State isPlaying: boolean = false;
  @State isPreparing: boolean = false;

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
    AppStorage.setOrCreate<boolean>(Constants.AS_MINI_PLAYER_VISIBLE, false);
  }

  private syncFromPlayer(): void {
    const c: PlayerController = PlayerController.getInstance();
    const idxOk: boolean = c.currentIndex >= 0 && c.currentIndex < c.playlist.length;
    const dataSaver: boolean = AppStore.getNumber(Constants.KEY_DATA_SAVER, 0) === 1;
    const has: boolean = c.playlist.length > 0;
    // 悬浮胶囊可见性上报（US2）：空态渲染占位条，与内容条占据相同底部空间，
    // 列表避让高度一致，故恒上报可见（值变化时才写，避免秒级 tick 抖动）
    const prevVisible: boolean = AppStorage.get<boolean>(Constants.AS_MINI_PLAYER_VISIBLE) === true;
    if (!prevVisible) {
      AppStorage.setOrCreate<boolean>(Constants.AS_MINI_PLAYER_VISIBLE, true);
    }
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
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
          .padding(8)
          .onClick(() => {
            AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_QUEUE_SHEET, true);
          })
      }
      .width('100%')
      .padding({ left: 10, right: 6, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.miniplayer_background'))
      .backdropBlur(24)
      .borderRadius(24)
      .margin({ bottom: this.navBarHeight + 8 })
      .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 2 })
      .onClick(() => {
        AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, true);
      })
    } else {
      // 空态占位条（US2）：队列无内容时显示占位封面+提示，不显示残留歌曲信息；
      // 点击同样唤起播放层（播放层空态有完整引导文案）
      Row() {
        CoverThumb({ cover: '', thumbSize: 44, radius: 8 })
        Text('暂无播放内容')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 10, right: 6 })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.miniplayer_background'))
      .backdropBlur(24)
      .borderRadius(24)
      .margin({ bottom: this.navBarHeight + 8 })
      .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 2 })
      .onClick(() => {
        AppStorage.setOrCreate<boolean>(Constants.AS_SHOW_PLAYER_OVERLAY, true);
      })
    }
  }
}
