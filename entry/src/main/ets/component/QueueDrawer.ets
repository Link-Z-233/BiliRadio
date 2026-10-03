import { QueueSheet } from './QueueSheet';

// 右侧滑出播放队列抽屉：点击遮罩关闭；面板从右侧平移进出场（退出时反向滑出）。
// 仅负责“打开态”绘制，挂载到哪一图层（Index 内容层 / PlayerOverlay 播放层）由调用方决定。
@Component
export struct QueueDrawer {
  @StorageLink('showQueueSheet') showQueueSheet: boolean = false; // key 与 Constants.AS_SHOW_QUEUE_SHEET 对应
  @StorageProp('statusBarHeight') statusBarHeight: number = 38; // key 与 Constants.AS_STATUS_BAR_HEIGHT 对应

  build() {
    Stack({ alignContent: Alignment.End }) {
      // 全屏遮罩：点击关闭（面板声明在后、位于上层，点击面板区域不会触发关闭）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask_heavy'))
        .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
        .onClick(() => {
          this.showQueueSheet = false;
        })

      // 队列面板：右对齐，从右侧滑入 / 反向滑出；顶部留出状态栏高度，内容不压状态栏
      Column() {
        QueueSheet()
      }
      .width('40%')
      .constraintSize({ minWidth: 320 })
      .height('100%')
      .padding({ top: this.statusBarHeight })
      .backgroundColor($r('app.color.queue_panel_background'))
      .backdropBlur(20)
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .clip(true)
      .transition(
        TransitionEffect.translate({ x: '100%' })
          .animation({ duration: 250, curve: Curve.EaseOut })
      )
    }
    .width('100%')
    .height('100%')
  }
}
