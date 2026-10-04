// 更多页（NavDestination）：设置 / 播放历史 / 关于 三入口（ux-feedback-round2 US7）
// 首页右上角直达本页；播放历史/关于点击后复用 settingsPage 既有参数直开机制，设置项传空参数
@Builder
export function MorePageBuilder() {
  MorePage()
}

@Component
struct MorePage {
  // 仅供 onReady 前占位，onReady 后替换为真实路由栈
  private navPathStack: NavPathStack = new NavPathStack();

  private openSettings(param: string): void {
    this.navPathStack.pushPathByName('settingsPage', param);
  }

  build() {
    NavDestination() {
      Column() {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
            Text('设置')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 12 })
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openSettings('');
          })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ left: 48, right: 0 })

          Row() {
            SymbolGlyph($r('sys.symbol.clock_arrow_2_circlepath'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
            Text('播放历史')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 12 })
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openSettings('playHistory');
          })

          Divider()
            .color($r('app.color.track_color'))
            .strokeWidth(1)
            .margin({ left: 48, right: 0 })

          Row() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
            Text('关于')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 12 })
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openSettings('about');
          })
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .margin({ left: 16, right: 16, top: 12 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .title('更多')
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
    })
  }
}
