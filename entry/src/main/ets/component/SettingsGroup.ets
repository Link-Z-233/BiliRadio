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
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 16, bottom: 8 })
      }
      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 22 })
  }
}
