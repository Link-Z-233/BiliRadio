import { QueueSheet } from './QueueSheet';

// 抽屉滑入/滑出动画时长（ms）：与遮罩 OPACITY 过渡一致；关闭延时比动画略长，保证滑出完整
const DRAWER_SLIDE_MS: number = 250;
const DRAWER_CLOSE_DELAY_MS: number = 260;

// 底部弹出播放队列面板（FR-101/plan D1）：点击遮罩关闭；面板从底部平移进出场（退出时反向滑出）。
// 进出场由挂载时 animateTo 驱动的显式位移状态实现（US1：TransitionEffect.translate
// 在 API 24 平板 zIndex 失效场景下表现不可靠，改为状态驱动保证全平台一致）；遮罩保留 OPACITY 过渡。
// 仅负责“打开态”绘制，挂载到哪一图层（Index 内容层 / PlayerOverlay 播放层）由调用方决定。
@Component
export struct QueueDrawer {
  @StorageLink('showQueueSheet') showQueueSheet: boolean = false; // key 与 Constants.AS_SHOW_QUEUE_SHEET 对应
  // 面板垂直位移：进场 '100%'（屏幕底部外）动画至 '0%'，退出反向；translate 百分比相对面板自身高度
  @State panelOffsetY: string = '100%';
  // US7/T023：关闭句柄注册回调——aboutToAppear 时向宿主上报 closeWithSlide（返回键路径复用滑出动画），
  // aboutToDisappear 时上报 undefined 注销；未注册的宿主（PlayerOverlay 内实例）保持既有行为
  onRegisterClose: (close: (() => void) | undefined) => void = (close: (() => void) | undefined): void => {
  };
  private closing: boolean = false;
  private closeTimer: number = -1;

  aboutToAppear(): void {
    this.onRegisterClose((): void => {
      this.closeWithSlide();
    });
    this.getUIContext().animateTo({ duration: DRAWER_SLIDE_MS, curve: Curve.EaseOut }, (): void => {
      this.panelOffsetY = '0%';
    });
  }

  aboutToDisappear(): void {
    // 注销关闭句柄：宿主不再持有已卸载实例的引用
    this.onRegisterClose(undefined);
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  // 遮罩点击关闭：面板先反向滑出，动画结束后再真正卸载（置 showQueueSheet=false）
  private closeWithSlide(): void {
    if (this.closing) {
      return;
    }
    this.closing = true;
    this.getUIContext().animateTo({ duration: DRAWER_SLIDE_MS, curve: Curve.EaseOut }, (): void => {
      this.panelOffsetY = '100%';
    });
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
    }
    this.closeTimer = setTimeout((): void => {
      this.closeTimer = -1;
      this.showQueueSheet = false;
    }, DRAWER_CLOSE_DELAY_MS);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 全屏遮罩：点击关闭（面板声明在后、位于上层，点击面板区域不会触发关闭）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask_heavy'))
        .transition(TransitionEffect.OPACITY.animation({ duration: DRAWER_SLIDE_MS }))
        .onClick(() => {
          this.closeWithSlide();
        })

      // 队列面板：底部对齐，位移由 panelOffsetY 状态驱动；全宽 65% 屏高，顶部圆角
      Column() {
        QueueSheet()
      }
      .width('100%')
      .constraintSize({ minWidth: 320 })
      .height('65%')
      .backgroundColor($r('app.color.queue_panel_background'))
      .backdropBlur(20)
      .borderRadius({ topLeft: 16, topRight: 16 })
      .clip(true)
      .translate({ y: this.panelOffsetY })
    }
    .width('100%')
    .height('100%')
  }
}
