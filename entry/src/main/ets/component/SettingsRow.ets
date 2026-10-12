import { Constants } from '../service/Constants';
import { connectStr, StrState } from '../service/V2State';

@ComponentV2
export struct SettingsRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param valueText: string = '';
  @Param rowIcon: Resource | undefined = undefined;
  @Param showArrow: boolean = false;
  @Param showToggle: boolean = false;
  @Param toggleOn: boolean = false;
  @Param showDivider: boolean = false;
  @Param danger: boolean = false;
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Param rowAction: () => void = (): void => {};
  @Param toggleChange: (on: boolean) => void = (_on: boolean): void => {};

  @Builder
  private iconSlot(icon: Resource | undefined) {
    if (icon !== undefined) {
      SymbolGlyph(icon)
        .fontSize(Constants.TOKEN_FONT_TITLE_L)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ right: Constants.TOKEN_SPACE_M })
    }
  }

  @Styles
  pressedStyle() {
    .backgroundColor($r('app.color.item_pressed_background'))
  }

  build() {
    Column() {
      Row() {
        this.iconSlot(this.rowIcon)
        Column() {
          Text(this.title)
            .fontSize(Constants.TOKEN_FONT_TITLE)
            .fontColor(this.danger ? $r('app.color.danger_red') : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(Constants.TOKEN_FONT_BODY_S)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: Constants.TOKEN_SPACE_XXS })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.valueText !== '') {
          Text(this.valueText)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: Constants.TOKEN_SPACE_6 })
        }
        if (this.showToggle) {
          Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
            .selectedColor(this.accentColor.value)
            .onChange((isOn: boolean) => {
              this.toggleChange(isOn);
            })
        }
        if (this.showArrow) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(Constants.TOKEN_FONT_TITLE)
            .fontColor([$r('app.color.placeholder_color')])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
      .stateStyles({ pressed: this.pressedStyle })
      .onClick(() => {
        this.rowAction();
      })
      if (this.showDivider) {
        Divider()
          .color($r('app.color.track_color'))
          .margin({ left: Constants.TOKEN_SPACE_L })
      }
    }
    .width('100%')
  }
}
