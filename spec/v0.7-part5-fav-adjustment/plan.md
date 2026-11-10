# Implementation Plan: v0.7-part5-fav-adjustment（收藏夹功能调整与交互补充）

**Input**: Feature specification from `spec/v0.7-part5-fav-adjustment/spec.md`

## Summary

对 part4 交付的四项真机反馈调整：收藏夹源互动稿豁免拦截（`loadPlaylistAndPlay` 加 `allowInteractive` 豁免参，单击/批量随源放行，浏览源与 BV 解析入口保留拦截）；pill 底色不透明（alpha 提满）；特殊标记与队列/历史状态标多选模式常显（门控移除）；fav 批量入队先退多选再异步补全 + 过程提示 + 防重入（修退出动画）。

增补三项交互设计：①收藏夹/合集/系列默认按接口返回顺序展示（刷新/缓存/触底全链路去掉统一发布时间重排，UP 保留双链合并排序），「更多」菜单新增「按时间排序」会话级开关（MenuItem symbolEndIcon 尾部对号形态，默认关=获取顺序，fetchOrder 行序基准支持关闭还原）；②播放列表点击正在播放条目无操作（QueueSheet 三处点击路径加「目标复合键 === currentKey 即返回」守卫）；③首页订阅行标题前类型色点（四类四色，新增色彩令牌与尺寸令牌）。全部改动落在既有文件，零新增文件。

增补批次交付后真机反馈修正两项：排序开关勾选标记移菜单项右侧（symbolEndIcon 对号，去左侧图标空位）；源页页头类型胶囊四色与首页色点同源（文字=类型色、底=同色 tint 令牌）。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: 零第三方依赖（@kit.* 系）
**State Management**: 既有混合态——PlayerController 零装饰器广播（字段 + `emitUi`）；页面已迁 V2（SourcePage/HomePage 均 `@ComponentV2`，会话开关用 `@Local`）。本轮不引入新代际、不改观测模式
**Storage**: 排序开关纯内存态（不持久化，随 SourcePage 实例生命周期）；色点为编译期资源
**Testing**: 无测试套件；`devecocli check arkts` + `devecocli build` + 真机日志验证（项目惯例）
**Target Platform**: HarmonyOS NEXT 单模块应用
**Performance Goals**: 排序开关切换为本地内存重排（0 请求）；队列守卫与色点为纯渲染/参数级改动，零新增请求
**Constraints**: Constants.ets 唯一真相源；令牌化（色值 `$r('app.color.*')`、数值 `Constants.TOKEN_*`）；代码零注释（`ponytail:` 除外）；禁 `any`/`as` 断言
**Scale/Scope**: 原四项改 5 个文件（PlayerController/SourcePage/QueueSheet/Constants + color.json）；增补改 6 个文件（SubscriptionStore/SourcePage/QueueSheet/HomePage/Constants + color.json，SourcePage/Constants/color.json 与原四项重叠）

## Project Structure

### Documentation (this feature)

```text
spec/v0.7-part5-fav-adjustment/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/PlayerController.ets     # [原四项] loadPlaylistAndPlay 增 allowInteractive 豁免参
├── service/SubscriptionStore.ets    # [增补] refreshSubscription 排序收窄至 UP；latestPubAt 取 pubdate 最大值
├── pages/SourcePage.ets             # [原四项] enqueueSelected 先退多选+过程提示+防重入；两入队路径传豁免参
│                                    # [增补] sortByTime 会话开关 + fetchOrder 行序基准 + moreMenuBuilder 排序开关 + loadOlder 排序条件化
│                                    # [反馈修正] 排序开关勾选标记右移（symbolEndIcon）+ 页头类型胶囊四色
├── component/QueueSheet.ets         # [原四项] specialMarkPrefix 与六处状态标 selectMode 门控移除
│                                    # [增补] 三处点击路径（queueFullRow/queuePartRow/onGroupHeaderClick）加当前条目无操作守卫
├── pages/HomePage.ets               # [增补] subRowCore 标题前类型色点
├── service/Constants.ets            # [原四项] TOAST_FAV_COMPLETING；[增补] MENU_LABEL_SORT_BY_TIME、SUB_TYPE_DOT_SIZE
entry/src/main/resources/base/element/color.json   # [原四项] 四类 pill_bg alpha FF；[增补] 四类 sub_type_* 色点色；[反馈修正] 四类 sub_type_*_tint 淡底
```

**Structure Decision**: 沿用既有架构零新增文件——豁免是既有函数加可选参、常显是门控移除、不透明是资源 alpha 更新；增补三项分别为刷新链排序收窄（SubscriptionStore）、内存态开关+行序基准（SourcePage）、点击守卫（QueueSheet）、纯展示元素（HomePage）与令牌新增（Constants/color.json）。

## Complexity Tracking

无宪法违规。全部为既有文件的增量修改。

## Research & Decisions

### 原四项（已实施）

- **Decision**: 豁免收敛在 `loadPlaylistAndPlay` 单点可选参 `allowInteractive`（默认 false），SourcePage 两入队路径按 `sub.type === TYPE_FAV` 传入；`addSingleVideo` 不传参保留拦截
  **Rationale**: 该函数是点播/入队/分享导入唯一汇聚点，单点参数即全入口可控；默认 false 保证未传参调用方零改动零回归
  **Alternatives considered**: 各调用方各自过滤——多入口重复且易漏，弃；仅批量豁免（单击仍拦）——同页面单击/批量语义分裂，弃

- **Decision**: 批量入队先退多选再异步补全，对齐队列/历史「先退多选再操作」既有模式；fav 路径弹过程提示（`TOAST_FAV_COMPLETING`）+ `enqueueInFlight` 防重入
  **Rationale**: 详情拉取数秒，先入队再退会吞掉退出动画；fav 批量补全在途期间重复确认会重复入队，防重入标志兜底
  **Alternatives considered**: 保持先补全再退多选——动画缺陷保留，弃；过程提示复用 statusMsg——statusMsg 是入队结果通道，语义混用，弃

- **Decision**: 多选常显直接移除 QueueSheet 六处状态标与 `specialMarkPrefix` 的 `selectMode` 门控（最小 diff），HistorySheet 状态标本无门控不动
  **Rationale**: 门控移除即常显，无需新增渲染分支
  **Alternatives considered**: 加常显开关配置——无此需求，弃

- **Decision**: pill 不透明直接改四类 `*_pill_bg` 资源 alpha D9→FF，不新增资源
  **Rationale**: 半透明变体无其他消费方（pill 底色专用），就地更新即全部生效
  **Alternatives considered**: 新增不透明变体资源并存——旧变体无消费方，多一份死资源，弃

### 增补三项

- **Decision**: 获取顺序落在刷新链源头——`refreshSubscription` 的统一发布时间降序重排收窄为仅 UP（fav/season/series 保留接口返回顺序直接落缓存）；`latestPubAt` 由「取排序后首条」改为「遍历取 pubdate 最大值」
  **Rationale**: 缓存即获取顺序，SourcePage 侧 `loadFromCache` 零改动即得默认顺序；UP 的 APP+Web 双链合并结果必须按 pubdate 排序才能正确交错（APP 链稀疏），保留；获取顺序下首条不再是最新发布，`latestPubAt` 取首条会回退
  **Alternatives considered**: SourcePage 渲染时才排序、缓存仍存时间序——开关关闭还原需重拉或双份顺序记录，缓存顺序与展示顺序分裂，弃；四类全部保留接口顺序——UP 双链合并交错乱序风险，弃

- **Decision**: 排序开关为 SourcePage 会话级 `@Local sortByTime`（默认 false），「更多」菜单用 MenuItem 尾部对号形态（`symbolEndIcon: SymbolGlyphModifier`，开启态 accent 色对号在菜单项右侧、关闭态无图标，`onClick` 翻转并重排；真机反馈修正——原 selected/selectIcon 左侧勾选留图标空位，文字与其他菜单项不对齐）；关闭还原依赖 `fetchOrder` 行序基准（bvid 序列，`loadFromCache` 初始化、`loadOlder` 追加时同步记录，还原时按键索引重排）；`loadOlder` 追加后仅 UP 或开关开启时按发布时间重排；开关仅对 fav/season/series 显示（UP 时间序即获取语义，开关无意义不显示）
  **Rationale**: symbolEndIcon 渲染在菜单项尾部（本机 SDK menu_item.d.ts 核实），对号在右侧且文字与「刷新/取消订阅」左对齐一致；`fetchOrder` 是「不重新拉取还原获取顺序」的最小记录（列表 bvid 去重保证键唯一）；SourcePage 实例生命周期即「会话」（返回首页再进入重建实例），`@Local` 默认值天然实现「重进复位」
  **Alternatives considered**: 渲染层双数组（主列表+显示副本）——所有行级交互（多选/入队/触底）需区分读写对象，改动面大，弃；开关对 UP 也显示——UP 开关两侧顺序相同，误导，弃；保留 selected/selectIcon 原生开关——左侧勾选留图标空位且文字不对齐（真机反馈），弃

- **Decision**: 队列当前条目守卫在 QueueSheet 三处点击路径（`queueFullRow`、`queuePartRow`、`onGroupHeaderClick`）加「目标复合键（`BiliVideo.itemKeyOf`）=== `currentKey` 即返回」判定，多选分支前置不动
  **Rationale**: `currentKey` 已在 `syncFrom` 中与 PlayerController 同步（复合键实时解析），守卫是纯前置判断；`onGroupHeaderClick` 两段判定算出目标分P 后再比对（目标=最新历史分P，播放中点击组头目标即当前分P → 无操作；目标为其他分P 时是组内正常切播不拦）
  **Alternatives considered**: 在 `playIndex` 加同索引守卫——会改变切音质/重播/断点恢复等内部路径语义（多处以 playIndex 复位重启），影响面不可控，弃；点击当前条目改为暂停/续播切换——用户已拍板「无操作」，弃

- **Decision**: 首页色点为 `subRowCore` 标题行内纯展示元素（标题文本前置小圆点 + 间距令牌），四色新增专属色彩令牌 `sub_type_up`（#007AFF 蓝）/`sub_type_fav`（#FFB027 黄，B 站收藏星标色）/`sub_type_season`（#AF52DE 紫）/`sub_type_series`（#34C759 绿），尺寸 `Constants.SUB_TYPE_DOT_SIZE`（8vp）
  **Rationale**: 色点嵌在标题行内不占行高、不与封面/徽标争位；四色取 iOS 系色板（与既有 success_green/warning_amber 同族）+ B 站收藏黄品牌色，饱和度足以在深浅外观下辨识；专属令牌不与语义色（success_green 等）复用，防语义耦合
  **Alternatives considered**: 复用既有语义色——series=success_green、fav=warning_amber 会与 ✓/! 状态色语义混淆，弃；色点叠封面左上角——封面被裁切为圆角缩略图，叠点在视觉上侵入封面主体，弃

- **Decision**: [反馈修正] 源页页头类型胶囊同源四色：文字=类型色资源、底=新增 `sub_type_*_tint`（#1F，12% 淡底）静态 tint 令牌，替代该处 accent 运行时 `hexWithAlpha`
  **Rationale**: 类型色为编译期常量，静态 tint 资源优于运行时计算（原用 hexWithAlpha 因 accent 用户可变，类型色固定改静态资源）；胶囊与首页色点同源保证跨页类型辨识一致
  **Alternatives considered**: 胶囊维持 accent 主题色——真机反馈要求与首页色点一致，弃；tint 运行时计算——类型色是 `$r` 资源取不到 hex 字符串，须双份硬编码，弃

## Data Model

无模型改动。新增常量、令牌与参数：

- [原四项] `Constants.TOAST_FAV_COMPLETING`：fav 批量补全过程提示文案
- [原四项] `PlayerController.loadPlaylistAndPlay` 第 4 参 `allowInteractive: boolean = false`
- [原四项] `SourcePage.enqueueInFlight: boolean`：fav 批量补全防重入标志
- [增补] `Constants.MENU_LABEL_SORT_BY_TIME`：「按时间排序」菜单项文案
- [增补] `Constants.SUB_TYPE_DOT_SIZE: number = 8`：首页类型色点尺寸（vp）
- [增补] `SourcePage.sortByTime: boolean`（`@Local`）：会话级排序开关，默认 false（获取顺序）
- [增补] `SourcePage.fetchOrder: string[]`（private）：获取顺序行序基准（bvid 序列，还原开关关闭时的接口返回顺序）
- [增补] color.json 四条：`sub_type_up` / `sub_type_fav` / `sub_type_season` / `sub_type_series`
- [反馈修正] color.json 四条：`sub_type_up_tint`（#1F007AFF）/ `sub_type_fav_tint`（#1FFFB027）/ `sub_type_season_tint`（#1FAF52DE）/ `sub_type_series_tint`（#1F34C759）——源页类型胶囊 12% 淡底（深浅外观同值，仅 base 定义）

## Contracts & Interfaces

### [原四项] `PlayerController.loadPlaylistAndPlay(items, startIndex, insertAfterCurrent, allowInteractive) → EnqueueResult`

`allowInteractive`（默认 false）为 true 时跳过互动过滤（`!allowInteractive && items[i].isInteractive`），互动稿照常入队走默认路线；false 时行为与 part4 交付一致（全互动返 `INTERACTIVE`、混合场景过滤 + statusMsg 通报）。调用方：SourcePage `enqueueAndToast`/`enqueueSelected` 传 `sub.type === TYPE_FAV`；HomePage/AddSubscriptionSheet 经 `addSingleVideo` 不传参（默认拦截）。

### [原四项] `SourcePage.enqueueSelected`（fav 源批量入队详情补全）

确认入队后：快照选中条目 → 立即 `exitSelectMode()`（动画即刻起播）→ fav 路径置 `enqueueInFlight` 并弹 `TOAST_FAV_COMPLETING` → 异步并行补全（并发上限 Constants 令牌）→ `loadPlaylistAndPlay(…, favPath)` → 结果 toast。`enqueueInFlight` 在途时重复确认直接忽略。单条详情失败降级原列表行入队（无标志、互动不拦）。UP 源/合集批量不拉详情（行自带标志）。

### [增补] `SubscriptionStore.refreshSubscription` 排序契约

- UP：合并 APP+Web 结果后按 pubdate 降序排序（现状保留）
- FAV/SEASON/SERIES：保留接口返回顺序（收藏时间序/集数序），不排序直接 `saveEpisodes`
- `latestPubAt`：遍历 items 取 `pubdate` 最大值（>0 才更新），不再依赖排序后首条
- 首页 `latestTitle`（取 episodes[0].title）随获取顺序变化：fav 首条 = 最近收藏条目（语义上更贴合「最新内容」），接受该展示变化

### [增补] `SourcePage` 排序开关契约

- `sortByTime` 默认 false；仅 fav/season/series 的「更多」菜单显示「按时间排序」MenuItem（开启态 `symbolEndIcon` 右侧 accent 色对号 + `onClick` 翻转并重排；关闭态无尾部图标，文字与其他菜单项左对齐一致）
- 开启：`episodes` 按 pubdate 降序重排（含已触底加载条目，纯内存，0 请求）
- 关闭：按 `fetchOrder` 键索引还原接口返回顺序（纯内存，0 请求）
- `loadOlder`：追加 fresh 后同步追加 `fetchOrder`；仅 UP 或 `sortByTime` 开启时按 pubdate 降序重排，否则直接追加尾部
- 重进源页：SourcePage 实例重建，`sortByTime` 回 false，`loadFromCache` 读缓存（获取顺序）
- 多选/入队/播放等行级交互以重排后的 `episodes` 行序为准（重排仅改顺序不改内容，行内 bvid 键不遍）

### [增补] `QueueSheet` 当前条目守卫契约

三处非多选点击路径加前置判定「目标复合键 === `currentKey` 即返回」：

- `queueFullRow`：目标 = `entry.videos[0]`（bvid, page）
- `queuePartRow`：目标 = `part`（bvid, page）
- `onGroupHeaderClick`：两段判定算出目标分P 后，目标键 === `currentKey` 即返回；目标为其他分P 时照常 `playIndex`（组内切播）

多选分支（`toggleSelect`）与长按进多选不受影响；点击非当前条目切播零变化；HistorySheet 不改。

### [增补] `HomePage` 类型色点契约

`subRowCore` 标题行：类型色点（`SUB_TYPE_DOT_SIZE` 圆点，色值按 `sub.type` 映射 `$r('app.color.sub_type_up'/'sub_type_fav'/'sub_type_season'/'sub_type_series')`）+ 标题文本，文本截断行为不变。色点为纯展示元素，不参与行点击/长按/拖拽/编辑态交互。

### [反馈修正] `SourcePage` 页头类型胶囊契约

`headerRow` 类型胶囊（typeLabel Text）：fontColor 按类型映射 `$r('app.color.sub_type_up'/'sub_type_fav'/'sub_type_season'/'sub_type_series')`，backgroundColor 为对应 `sub_type_*_tint`（同色 12% 淡底）；不再使用 `accentColor`/`hexWithAlpha`。胶囊为纯展示元素，与首页色点同源四色。

### 渲染层（原四项）

- `SourcePage` markPills：pill 底色资源 alpha FF（不透明），渲染逻辑零改动
- `QueueSheet`：`specialMarkPrefix` 去 `!selectMode` 门控；✓/✗/! 六处状态标（分P 行 isPartPlayed/hasInvalid/hasAnomaly + 条目组头行同三处）门控移除，多选模式常显
- `HistorySheet`：无门控，零改动

### 自检与验证口径

- 豁免与拦截分路径行为以真机样本验证（fav 互动稿放行/UP 源拦截），纳入 Verification 真机自查事项
- 门控移除为纯渲染 diff（删条件），构建通过即逻辑等价常显
- [增补] 排序：fav 源刷新后列表首条为最近收藏条目（非最新发布）；开关开启/关闭/重进复位三态在真机自查；UP 源顺序与改前一致
- [增补] 队列守卫：播放中点击当前行（组头/分P/单条目）播放不中断，点击其他条目正常切播
- [增补] 色点：四类源色点颜色一一对应，新增订阅色点正确；[反馈修正] 源页四类胶囊颜色与首页色点一致、开关开启态右侧对号文字左对齐

## Changelog

- 增补 part5 更改内容补充三项设计：`refreshSubscription` 排序收窄（US4 数据链）、SourcePage 会话排序开关与 fetchOrder 还原基准（US4 交互）、QueueSheet 三处点击守卫（US5）、HomePage 类型色点与四色令牌（US6）；Summary/Technical Context/Project Structure/Data Model 同步增补范围
- 真机反馈修正两项设计：排序开关 symbolEndIcon 右侧对号（US4/FR-007，去 selected/selectIcon 左侧图标空位）、源页类型胶囊四色同源 + sub_type_*_tint 令牌（US6/FR-009）；对应 Decision/契约/Data Model 就地更新
