import { Constants } from '../service/Constants';
import { connectStr, StrState } from '../service/V2State';

// 多选行首勾选框共用组件（FR-012）：恒挂载容器宽度 0↔勾选框容器宽 + opacity 0↔1 随 active
// 联动（动画由父组件 animateTo 驱动状态翻转，本组件只做属性绑定），Checkbox 统一样式；
// onChange 仅用户点 Checkbox 本身时回调，行点击切换仍走父组件行 onClick
@ComponentV2
export struct SelectCheckbox {
  @Param active: boolean = false;
  @Param selected: boolean = false;
  // 勾选框右侧留白（FR-013）：按各场景行左内边距注入同档值，两侧空白对称；默认 S 向后兼容
  // （V2 普通成员禁止父组件初始化，须 @Param 暴露注入点）
  @Param gap: number = Constants.TOKEN_SPACE_S;
  @Event onChange: (value: boolean) => void = (value: boolean): void => {};
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);

  build() {
    Row() {
      Checkbox()
        .select(this.selected)
        .selectedColor(this.accentColor.value)
        .width(Constants.SELECT_CHECKBOX_SIZE)
        .height(Constants.SELECT_CHECKBOX_SIZE)
        .onChange((value: boolean) => {
          this.onChange(value);
        })
    }
    .width(this.active ? Constants.SELECT_CHECKBOX_SIZE + this.gap : 0)
    .opacity(this.active ? 1 : 0)
  }
}
