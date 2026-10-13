import { Constants } from '../service/Constants';
import { BoolState, NumState, connectNum } from '../service/V2State';
import { Appearance } from '../service/Appearance';

@Builder
function glassSheetEmptyBody() {
}

// 通用玻璃浮层容器（v0.4-Part1 sheet-visual-redesign）：遮罩 + 面板壳 + 进出场动画 + 关闭句柄注册，
// 队列浮层（Index/PlayerOverlay）与播放历史面板（SettingsPage）共用同一实现（FR-008）。
// 进出场由挂载时 animateTo 驱动的显式位移/透明度状态实现（TransitionEffect.translate
// 在部分平台 zIndex 场景不可靠，沿用状态驱动）；面板内容经 @BuilderParam body 由宿主注入。
@ComponentV2
export struct GlassSheet {
  // 浮层可见性状态（宿主持有并传入）：关闭时容器内置 false 触发宿主条件卸载
  @Require @Param openState: BoolState;
  // 面板高度（屏幕高度百分比）
  @Param panelHeight: string = '65%';
  // 关闭句柄注册回调：aboutToAppear 上报动画关闭句柄，aboutToDisappear 上报 undefined 注销
  @Param onRegisterClose: (close: (() => void) | undefined) => void =
    (close: (() => void) | undefined): void => {
    };
  // 面板内容
  @BuilderParam body: () => void = glassSheetEmptyBody;
  // 面板垂直位移：进场 '100%'→'0%'，退出反向；translate 百分比相对面板自身高度
  @Local panelOffsetY: string = '100%';
  // 面板透明度：进场 0→1 与位移同帧驱动，退出镜像反向（FR-006）
  @Local panelOpacity: number = 0;
  // 生效深浅色（1=浅色 2=深色）：投影参数随外观实时切换（US2）
  @Local colorModeResolved: NumState =
    connectNum(Constants.AS_COLOR_MODE_RESOLVED, Appearance.MODE_LIGHT);
  private closing: boolean = false;
  private closeTimer: number = -1;

  aboutToAppear(): void {
    this.onRegisterClose((): void => {
      this.closeWithSlide();
    });
    this.getUIContext().animateTo({ duration: Constants.SHEET_SLIDE_MS, curve: Curve.EaseOut }, (): void => {
      this.panelOffsetY = '0%';
      this.panelOpacity = 1;
    });
  }

  aboutToDisappear(): void {
    this.onRegisterClose(undefined);
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  private shadowRadius(): number {
    return this.colorModeResolved.value === Appearance.MODE_DARK
      ? Constants.SHEET_SHADOW_RADIUS_DARK
      : Constants.SHEET_SHADOW_RADIUS_LIGHT;
  }

  private shadowOffsetY(): number {
    return this.colorModeResolved.value === Appearance.MODE_DARK
      ? Constants.SHEET_SHADOW_OFFSET_DARK
      : Constants.SHEET_SHADOW_OFFSET_LIGHT;
  }

  // 关闭：面板反向滑出+渐隐，动画结束后置 openState=false 真正卸载
  private closeWithSlide(): void {
    if (this.closing) {
      return;
    }
    this.closing = true;
    this.getUIContext().animateTo({ duration: Constants.SHEET_SLIDE_MS, curve: Curve.EaseOut }, (): void => {
      this.panelOffsetY = '100%';
      this.panelOpacity = 0;
    });
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
    }
    this.closeTimer = setTimeout((): void => {
      this.closeTimer = -1;
      this.openState.value = false;
    }, Constants.DRAWER_CLOSE_DELAY_MS);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 全屏遮罩：点击动画关闭（面板声明在后、位于上层，点击面板区域不触发关闭）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask_heavy'))
        .transition(TransitionEffect.OPACITY.animation({ duration: Constants.SHEET_SLIDE_MS }))
        .onClick(() => {
          this.closeWithSlide();
        })

      // 面板壳：玻璃底 + 顶圆角/分隔线/向上投影；body 底部叠加渐隐带（不拦截列表交互）
      Stack({ alignContent: Alignment.Bottom }) {
        this.body()
        Column()
          .width('100%')
          .height(Constants.SHEET_FADE_HEIGHT)
          .linearGradient({
            angle: 180,
            colors: [[$r('app.color.sheet_fade_from'), 0], [$r('app.color.sheet_panel_background'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .constraintSize({ minWidth: 320 })
      .height(this.panelHeight)
      .backgroundColor($r('app.color.sheet_panel_background'))
      .backdropBlur(20)
      .borderRadius({ topLeft: Constants.TOKEN_RADIUS_XXL, topRight: Constants.TOKEN_RADIUS_XXL })
      .border({ width: { top: 1 }, color: $r('app.color.sheet_top_separator') })
      .shadow({
        radius: this.shadowRadius(),
        offsetY: this.shadowOffsetY(),
        color: $r('app.color.sheet_shadow')
      })
      .clip(true)
      .translate({ y: this.panelOffsetY })
      .opacity(this.panelOpacity)
    }
    .width('100%')
    .height('100%')
  }
}
