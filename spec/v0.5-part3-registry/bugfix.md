# bugfix（v0.5-part3-registry 轮）

## 1. 页头「N 集」位置随源类型漂移

- 现象：「N 集」在 UP/合集/系列页头贴右缘（被 UP 名 layoutWeight 顶出），收藏夹页头（FR-009 无 UP 行）紧贴类型胶囊——四种源类型落点不一致
- 根因：「N 集」在标签行内顺序排布，无右锚定，落点取决于前置 UP 名是否存在
- 修复：「N 集」上移至名称大字行（标题 layoutWeight(1) 省略截断 + 集数右对齐一行），字号 TOKEN_FONT_BODY_S(12)→TOKEN_FONT_BODY_M(14)；标签行仅剩类型胶囊 + UP 主
- 涉及：`entry/src/main/ets/pages/SourcePage.ets` headerRow

## 2. 订阅详情页底色与首页壳层不一致

- 现象：订阅详情页整体底色与首页（通知栏下区域）底色不同
- 根因：SourcePage 的 NavDestination 未显式设底色，吃系统主题默认背景；首页壳层（Index 背景柱）显式刷 `page_background`（浅 #F6F6FA / 深 #121214）——两个色源不同
- 修复：NavDestination 显式 `.backgroundColor($r('app.color.page_background'))`，深浅色随 token 资源自动切换
- 涉及：`entry/src/main/ets/pages/SourcePage.ets` build

## 3. 首页新集徽标单数字不居中

- 现象：新集数圆点徽标在数字为一位时明显偏左
- 根因：单数字内容宽（约 19px）小于 `constraintSize({ minWidth: 20 })`，组件被撑到 20px 而 `Text` 默认 `textAlign: Start` 左对齐，空隙全落右侧；两位数/99+ 内容宽超 20 不受影响
- 修复：徽标 Text 补 `.textAlign(TextAlign.Center)`
- 涉及：`entry/src/main/ets/pages/HomePage.ets` subRowItem
