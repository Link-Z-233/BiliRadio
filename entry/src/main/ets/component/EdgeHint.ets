// US5 列表回弹过冲提示（FR-009/010）：纯展示组件，宿主以 Stack 承载并声明在 List 之前（z 序更低），
// 过冲空隙露出提示文字；可见性由宿主过冲状态驱动（text 空串不渲染），组件自身无状态无计时器
@Component
export struct EdgeHint {
  @Prop text: string = '';
  @Prop edge: string = 'top';

  build() {
    if (this.text !== '') {
      Column() {
        Text(this.text)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(this.edge === 'top' ? FlexAlign.Start : FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.edge === 'top' ? 22 : 0, bottom: this.edge === 'bottom' ? 22 : 0 })
      .hitTestBehavior(HitTestMode.None)
    }
  }
}
