import { Constants } from '../service/Constants';

@Builder
function groupEmptyContent() {
}

@Component
export struct SettingsGroup {
  @Prop title: string = '';
  @BuilderParam content: () => void = groupEmptyContent;

  build() {
    Column() {
      if (this.title !== '') {
        Text(this.title)
          .fontSize(Constants.TOKEN_FONT_BODY)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_S })
      }
      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius(Constants.TOKEN_RADIUS_L)
      .backgroundColor($r('app.color.card_background'))
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 22 })
  }
}
