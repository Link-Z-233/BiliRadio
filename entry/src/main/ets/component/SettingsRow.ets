import { Constants } from '../service/Constants';

@Component
export struct SettingsRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop valueText: string = '';
  @Prop rowIcon: Resource | undefined = undefined;
  @Prop showArrow: boolean = false;
  @Prop showToggle: boolean = false;
  @Prop toggleOn: boolean = false;
  @Prop showDivider: boolean = false;
  @Prop danger: boolean = false;
  @StorageProp('accentColor') accentColor: string = Constants.ACCENT_DEFAULT;
  rowAction: () => void = (): void => {};
  toggleChange: (on: boolean) => void = (_on: boolean): void => {};

  @Builder
  private iconSlot(icon: Resource | undefined) {
    if (icon !== undefined) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ right: 12 })
    }
  }

  build() {
    Column() {
      Row() {
        this.iconSlot(this.rowIcon)
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontColor(this.danger ? $r('app.color.danger_red') : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.valueText !== '') {
          Text(this.valueText)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 6 })
        }
        if (this.showToggle) {
          Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
            .selectedColor(this.accentColor)
            .onChange((isOn: boolean) => {
              this.toggleChange(isOn);
            })
        }
        if (this.showArrow) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.placeholder_color')])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(() => {
        this.rowAction();
      })
      if (this.showDivider) {
        Divider()
          .color($r('app.color.track_color'))
          .margin({ left: 16 })
      }
    }
    .width('100%')
  }
}
