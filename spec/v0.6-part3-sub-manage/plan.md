# Implementation Plan: 订阅源管理三件套（v0.6-part3）

**Input**: Feature specification from `spec/v0.6-part3-sub-manage/spec.md`

## Summary

三项能力：① 首页长按订阅行弹菜单（置顶/排序/删除；LongPressGesture + 受控 bindMenu），「排序」进入整页列表编辑态，行拖拽调序（单 List 恒绑 `LazyForEach.onMove` + editMode 闸，落子静默重排；拖拽把手即按即拖——把手挂 PanGesture 自定义手动拖拽，按下移动立即拖动免长按等待，整行长按系统拖拽由内容区触摸穿透承担，把手长按被空 LongPressGesture 认领阻断（pan-only），D24），置顶为移动语义（相邻交换冒泡通知 + animateTo 补位动画），退出双轨（「完成」按钮 + BackHandler 链返回），原失效 `bindContextMenu` 菜单废弃；② 订阅全量导出 JSON 写沙箱缓存文件，经 `@kit.ShareKit` systemShare 分享面板发出；③ 文档选择器选入 JSON，`SubscriptionStore` 校验去重合并，新源自动刷新。跨设备（US4）为 ②+③ 串联验收，零新增代码。全部平台 Kit，零新增依赖，零新增文件。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0，API 26）
**Primary Dependencies**: 零第三方依赖；本功能涉及平台 Kit：`@kit.ShareKit`（systemShare）、`@kit.CoreFileKit`（fileIo/fileUri/picker）、`@kit.PerformanceAnalysisKit`（hilog）
**State Management**: 沿用现状——页面 `@ComponentV2` + `@Local`；`PlayerController` 零装饰器广播不涉及；`AS_*` 瞬态键经 `V2State` 包装类
**Storage**: 既有 `subscriptions.json`（filesDir）+ 新增导出缓存文件（cacheDir，覆盖写）
**Testing**: 无测试套件；验证走构建 + 真机自查（`docs/agents/verifying.md`）
**Target Platform**: HarmonyOS NEXT 华为真机（phone/tablet）
**Project Type**: 单模块移动应用（entry 单 HAP）
**Performance Goals**: 编辑态拖拽跟手（系统拖拽默认帧率）；导入解析 100 源内秒级
**Constraints**: ArkTS 严格模式（禁 any/unknown/as）；代码零注释（`ponytail:` 除外）；令牌/数值进 Constants
**Scale/Scope**: 改动 6 个既有文件，无新增文件；4 个用户故事

## Project Structure

### Documentation (this feature)

```text
spec/v0.6-part3-sub-manage/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── HomePage.ets          # US1/US5–US9：编辑态/拖拽/长按菜单/置顶/按压反馈；移除 bindContextMenu
│   └── SettingsPage.ets      # US2/US3：新增「订阅管理」分组（导出/导入两行）
├── service/
│   ├── SubscriptionStore.ets # US2/US3：exportToCacheFile / importFromFile（数据层）
│   ├── FileUtil.ets          # US3：新增按 URI 读文本（fd 读取，用户文件）
│   ├── BackHandler.ets       # US1：首页编辑态返回句柄注册与优先消费
│   └── Constants.ets         # 新增常量：导出文件名/UTD/toast 文案/动画令牌
```

**Structure Decision**: 沿用既有架构（service→model、pages→service/model 单向依赖），不引入新目录/新分层/新文件——编辑态 UI 并入 HomePage（复用 List/SubDataSource），导入导出数据操作并入 SubscriptionStore（订阅数据唯一存取点），分享/选择器编排在 SettingsPage。符合 architecture.md 边界契约。

## Complexity Tracking

无 Constitution 违规。D1 曾以编辑/正常双 List 分支规避拖拽回调与长按的干扰，D21 为恒挂载让位动画合并为单 List（onMove 恒绑 + 行内三闸消解干扰），为最终形态。

## Research & Decisions

- **D1 拖拽排序通道**
  - **Decision**: 编辑态内 List 绑定 `onItemDragStart`（返回 CustomBuilder 作拖拽预览）/ `onItemDragMove` / `onItemDrop`；`SubDataSource` 扩展 `move(from, to)` 调 `DataChangeListener.onDataMove`。编辑态与正常态**分离渲染**（两 List 分支）：正常态 List 不绑拖拽回调，避免长按（进编辑态）与拖拽发起（同为长按触发）互相干扰；编辑态分支内不再挂编辑入口手势，拖拽独占长按通道。
  - **Rationale**: List 级拖拽 API 本机声明齐全（`list.d.ts` since 8，`common.d.ts:25680` `OnItemDragStartCallback = (event, itemIndex) => CustomBuilder`）；`onDataMove` 声明齐全（`lazy_for_each.d.ts:701`）；分离渲染让两种手势各处其位，无需验证「回调内守卫返回 undefined 是否取消拖拽」这类未定义行为。
  - **Alternatives considered**: 单 List + 回调内 editMode 守卫（返回 undefined 行为未证实，弃）；行尾拖拽把手 + PanGesture 手动实现（工作量大 3 倍，作真机验证失败后的备选）。
- **D2 长按进入编辑态的手势实现与失效 bug 处置**
  - **Decision**: 移除 `bindContextMenu(ResponseType.LongPress)`（真机失效的菜单整体废弃），行上以 `LongPressGesture` 触发进入编辑态。实施时真机优先验证 LongPressGesture 触发；若同样不触发（说明竞争根因在 swipeAction/onTouch 事件链），备选：编辑入口改为首页标题栏显式按钮（「⋯」菜单内加「编辑排序」，或「＋」旁独立图标按钮），绕开手势竞争。
  - **Rationale**: 用户报告 `bindContextMenu` 真机无反应，根因未查证；LongPressGesture 走通用手势系统，与 bindContextMenu 内部长按机制不同，竞争面更小；备选方案完全不依赖长按，保证功能可达。
  - **Alternatives considered**: 修复 bindContextMenu 保菜单（用户已选「列表编辑态」形态，菜单无存在必要，弃）。
- **D3 编辑态落盘与顺序归一化**
  - **Decision**: 每次拖拽落子（onItemDrop）后：subs 数组按落点重排 → sortOrder 全量归一化（0..n-1）→ `saveSubscriptions`。不再沿用「置顶 = sortOrder-1」的稀疏值策略（pinToTop 随菜单废弃）。
  - **Rationale**: 归一化使磁盘顺序即显示顺序，rebuild 的 sortOrder 排序天然稳定；松手即落盘使编辑态任何退出路径（完成/返回/杀进程）都不丢顺序。
  - **Alternatives considered**: 退出编辑态时一次性落盘（中途杀进程丢全部调整，弃）。
- **D4 编辑态期间的 rebuild 抑制**
  - **Decision**: 编辑态激活时挂起 rebuild（静默刷新回调/homeRefreshTick 到达时置脏标记，退出编辑态时补一次 rebuild）；若进入编辑态时静默刷新已在途，允许其完成 persist 但 rebuild 延迟到退出后。
  - **Rationale**: 拖拽中 rebuild 会重建 LazyForEach 导致拖拽断裂/行错位；persistRefreshedSub 落盘与编辑态内存数组分离（saveSubscriptions 全量覆盖），在途刷新落盘后编辑态退出时 rebuild 会重读磁盘，数据无损。
  - **Alternatives considered**: 编辑态直接放行 rebuild（拖拽断裂，弃）。
- **D5 编辑态返回消费（BackHandler 接入）**
  - **Decision**: BackHandler 新增首页编辑态句柄注册（对齐既有 `registerSettingsBack` 模式）；`dismissOverlaysForBack` 中编辑态消费置于**最前**（编辑态属 L1 首页内部交互，物理上处于所有浮层之下但交互上为当前焦点；编辑态与队列/历史等浮层不同时开启，置前无优先级冲突）。「完成」按钮与返回消费走同一退出函数。
  - **Rationale**: 复用模块级句柄注册模式（宿主生命周期上报），不新增返回链分层概念。
  - **Alternatives considered**: 编辑态经 AS_* 键接入 dismissOverlaysForBack 既有键判断（编辑态是页面内瞬态非全局层，键化会污染全局键空间，弃）。
- **D6 导出通道（系统分享面板）**
  - **Decision**: `@kit.ShareKit` 的 `systemShare`：全量订阅 `toRecord` 序列化为 `{items:[...]}` 写入 cacheDir 固定文件（每次覆盖），`fileUri.getUriFromPath` 转 app file URI，`new SharedData({utd, uri, title, description})` → `new ShareController(data)` → `show(UIAbilityContext, {selectionMode: SINGLE})`。
  - **Rationale**: 本机 HMS 声明齐全（`@hms.collaboration.systemShare.d.ts`，kit 映射 `@kit.ShareKit`）；SharedRecord 文档明确支持 app file URI；SINGLE 单选默认即所需；华为分享/保存到文件/第三方应用均由系统面板承载。
  - **Alternatives considered**: SaveButton 保存到用户目录（用户已选分享面板，弃；面板内「保存到文件」能力可覆盖该场景）。
- **D7 导出文件 UTD 类型**
  - **Decision**: 首选 `general.json`（UDMF 标准 UTD ID，运行时字符串，SDK 不内嵌声明）；真机分享面板若出现目标应用匹配异常（无应用可识别），回退 `general.file`（通用文件类型，所有文件类目标可达）。
  - **Rationale**: 精确类型让面板优先匹配文档类应用；json 属非主流分享类型，回退路径必须预留。
  - **Alternatives considered**: 直接用 `general.file`（匹配面最宽但面板预览类型显示为泛文件，弃作首选）。
- **D8 导入通道与文件读取**
  - **Decision**: `@ohos.file.picker` 的 `DocumentViewPicker.select()`（单选）返回用户文件 URI；FileUtil 新增按 URI 读文本方法（`fs.openSync(uri, READ_ONLY)` 得 fd 后按 fd 读，不复用现有 `readTextFile` 的 path+statSync 路径——statSync 对 user file URI 的兼容性未验证）。
  - **Rationale**: 选择器返回的 URI 带临时读授权，openSync 原生支持；fd 读取避开 path/stat 的 URI 兼容性未知面。
  - **Alternatives considered**: 扩展现有 readTextFile 兼容 URI（改动共享方法，回归面大，弃）。
- **D9 导入合并语义与刷新编排**
  - **Decision**: `SubscriptionStore` 新增导入方法：读文本 → JSON.parse → 逐条 `Subscription.fromRecord`（既有逐字段 undefined 守卫）→ id/type 缺失条目跳过计入 skipped → 本机已有 id 跳过计入 skipped → 新源 sortOrder 自 max+1 递增追加 → saveSubscriptions → 返回 {added, skipped}。新源刷新复用 `refreshAll(newSubs, true, callback)`（串行 + 既有 800ms 间隔，单源失败不阻塞）；导入完成 bump `AS_HOME_REFRESH_TICK` 令 HomePage 重建。
  - **Rationale**: 去重键即 Subscription.id（复合键天然唯一）；fromRecord 容错已内建；refreshAll 的串行/TTL/失败语义现成；homeRefreshTick 是既有首页重建通道（US4 v0.5），零新机制。
  - **Alternatives considered**: 导入时逐源同步刷新阻塞 UI（源多时卡顿明显，弃）。
- **D10 UI 入口落位（SettingsPage）**
  - **Decision**: SettingsPage 新增「订阅管理」SettingsGroup，含两行 SettingsRow（导出订阅/导入订阅，箭头行样式）；空列表导出 toast 拦截（不发空文件）；导入/导出失败 toast；导入结果 toast「新增 N 个，跳过 M 个」。分组位置实施时对齐既有分组节奏（账号/播放/外观/历史与日志之间）。
  - **Rationale**: 复用 SettingsGroup/SettingsRow 既有组件与分组模式，零新组件。
  - **Alternatives considered**: 入口放首页标题栏（首页按钮语义已满载——＋/⋯，且导入导出属低频操作，设置页更合理，弃）。

- **D11 真机验证风险登记（实施轮逐项验证，均已配决策内备选）**
  - `LongPressGesture` 真机触发（原 bindContextMenu 失效根因未查证；失效则启用 D2 备选显式入口）
  - List 拖拽（onItemDragStart 发起条件/预览渲染/与 LazyForEach 协作）真机行为；失败则启用 D1 备选 PanGesture 手动实现
  - `general.json` UTD 分享面板目标匹配；异常回退 `general.file`（D7）
  - 分享面板对 cacheDir app file URI 的跨应用/跨设备可达性（华为分享直发、微信发送）——US4 双设备验收覆盖

- **D12 拖拽落子通知修正（FR-014 bug 根因）**
  - **Decision**: `applyDragOrder` 不再调 `SubDataSource.move`（内含 onDataMove 通知）；SubDataSource 提供静默重排（数组 splice 不通知 listener）——subs 重排 → sortOrder 归一化 → 落盘 → 静默同步 provider 数组。
  - **Rationale**: 官方文档明确「onMove 事件中根据上报索引修改数据源，**无需调用 DataChangeListener 接口通知**」；真机症状（落子后 UI 回原序、无法继续拖、退出后顺序正确）与「额外 onDataMove 致框架内部缓存二次移动」完全吻合。
  - **Alternatives considered**: 保留通知（真机已证伪，弃）。
- **D13 长按菜单实现（FR-012/013）**
  - **Decision**: 保留行上 `LongPressGesture`（真机已验证触发），改 `onActionEnd`（抬手后弹菜单，规避弹菜单瞬间抬手误触菜单项）；onActionEnd 内记录长按行并翻转菜单显隐状态；行挂受控 `bindMenu(isShow, CustomBuilder, MenuOptions)`（API 11+，common.d.ts:14952 声明确认），builder 内 Menu + 三 MenuItem（置顶/排序/删除）。置顶：subs 移除该 sub → unshift → sortOrder 归一化 → saveSubscriptions → rebuild；排序：`enterEditMode`（既有链路）；删除：`confirmRemoveSub`（既有确认弹窗）。菜单项点击后置 isShow=false，`onDisappear` 同步复位状态。
  - **Rationale**: `bindContextMenu` 长按识别真机曾失效，不复用；LongPressGesture + 受控 bindMenu 组合避开失效面（手势已验证，菜单仅响应显式状态翻转）；菜单样式/自动关闭由系统承载。
  - **Alternatives considered**: `bindContextMenu(ResponseType.LongPress)`（真机失效史，弃）；bindPopup 自绘菜单（无系统菜单样式与关闭管理，代码更多，弃）。
- **D14 编辑态转场（FR-015）**
  - **Decision**: 编辑态/正常态两个分支容器及标题区（标题文字、按钮组）加 `.transition(TransitionEffect.OPACITY)`；`@Local editMode` 翻转驱动 if/else 分支切换时自动播放转场（隐式转场，无需 animateTo）。
  - **Rationale**: 项目已有先例（SourcePage.ets:808 同款）；最小动画补齐，不做 translate/scale 组合。
  - **Alternatives considered**: animateTo 显式动画（分支切换是组件树替换非属性变化，不适用，弃）。
- **D15 长按即时菜单与行强调（FR-016/019）**
  - **Decision**: `LongPressGesture` 从 `onActionEnd`（抬手触发）改回 `onAction`（长按达成即触发，按压中弹菜单，对齐文件管理）；行挂 `.scale()`——menuKey 命中行缩至约 0.97 强调，配属性动画 `.animation({ duration: 令牌 })` 平滑过渡，菜单关闭恢复 1.0；bindMenu options 补 `placement: Placement.Top`（菜单从行上方展开，空间不足系统自动调整）；按压行（pressedKey 态）加浮起阴影——`.shadow({ radius: TOKEN_FLOATING_SHADOW_RADIUS, color: shadow_ball, offsetX: 0, offsetY: TOKEN_FLOATING_SHADOW_OFFSET_Y })` 复用悬浮件阴影令牌（MiniPlayer 胶囊同款），按压中显现、松开消失，编辑态 enabled(false) 无按压自然无阴影。
  - **Rationale**: 用户明确要求按压达成即弹（文件管理同款）；系统菜单（bindMenu 承载）弹出后由框架接管触摸序列，抬手误触风险由真机验证；scale 强调是文件管理长按的最小视觉对应；按压浮起阴影复用既有令牌零新增（「复用就行」——用户原话）。
  - **Alternatives considered**: 保留 onActionEnd 抬手触发（用户已明确否决，弃）；强调改背景色变化（按压背景已有 pressedKey 承载，叠加易混淆，弃）。
- **D16 编辑态转场修正（FR-017，FR-015 实施无效的根因）**
  - **Decision**: 7 处 `.transition(TransitionEffect.OPACITY)` 补 `.animation({ duration: 300 })`（时长令牌入 Constants）；`@Local editMode` 翻转不在 animateTo 内，须靠 TransitionEffect 自带 animation 参数驱动转场。
  - **Rationale**: 官方文档明示「如果未使用 animateTo 触发转场动画且 TransitionEffect 中也无 animation 参数，则该组件直接出现或者消失」——D14 无 animation 参数即无动画，与真机观察一致；PlayerOverlay 既有 `.animation({ duration: 200 })` 为同款正确写法先例。
  - **Alternatives considered**: editMode 翻转包 animateTo（分支切换是组件树替换，animateTo 语义不匹配，弃）。
- **D17 拖拽把手加大（FR-018）**
  - **Decision**: 编辑态行 `editRowItem` 拖拽把手 SymbolGlyph（line_3_horizontal）字号上调至大号令牌，周边留白相应加大；尺寸数值入 Constants（令牌优先复用既有，不足新增）。
  - **Rationale**: 真机反馈把手过小不易识别；仅视觉尺寸调整，拖拽行为不变（编辑态整行可拖）。
  - **Alternatives considered**: 换更醒目的图标（如 list_bullet 行为语义不变下无必要，弃）。
- **D18 置顶补位动画（FR-020）**
  - **Decision**: `pinToTop` 改 `animateTo({ duration: TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, ...)` 包「subs 重排（unshift 首位）→ sortOrder 归一化 → saveSubscriptions → provider move 通知」；`SubDataSource` 恢复 `move(from, to)`（数组 splice + 遍历 listener 调 `onDataMove(from, to)`，上批因拖拽改静默而删除）；置顶后**不调 rebuild**（显示数据不变，reload 全量重建会打断移动动画）。
  - **Rationale**: 置顶是主动数据变化（非 onMove 拖拽，拖拽场景框架自管视觉），LazyForEach 须收 onDataMove 才更新，通知落在 animateTo 内即产生行移动补间动画（行飞至首位、其余行让位）；removeSub 的「animateTo 包 provider.delete + 落盘」为同构先例（HomePage.ets:265）；动画参数取 TOKEN_SELECT_ANIM_MS(300)/EaseOut 与本轮整体动画节奏一致。
  - **Alternatives considered**: 置顶后直接 rebuild（瞬间跳位，用户已否决，弃）；FLIP 手动位移动画（LazyForEach 键控节点无稳定句柄，工作量 5 倍，弃）。
- **D19 编辑态动画与多选同构（FR-021，D16 的 animateTo 形态）**
  - **Decision**: `enterEditMode`/`exitEditMode` 各包 `animateTo({ duration: Constants.TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut }, ...)` 翻转 editMode（对齐 SourcePage enterSelectMode/exitSelectMode :131/:145 同款写法）；7 处 transition 的 `.animation({ duration: TOKEN_EDIT_MODE_TRANSITION_MS })` 参数**移除**（改回纯 `TransitionEffect.OPACITY`，动画参数由 animateTo 统一供给，与多选 transition 写法一字不差）；`TOKEN_EDIT_MODE_TRANSITION_MS` 令牌随无消费方删除；`exitEditMode` 的 rebuildPending 补跑移至 animateTo 闭包外（rebuild 触发的 reload 不打断旧分支节点消失动画）。
  - **Rationale**: 用户要求与多选动画一致——多选的实现即「transition 无参数 + animateTo 供参数」（D16 生效顺序：TransitionEffect 自带 animation 优先于 animateTo，故须移除自带参数才能与多选完全一致）；多选标题栏双态同为 Stack/条件渲染 + OPACITY 交叉淡化，形态同构。
  - **Alternatives considered**: 保留 7 处自带 animation 参数仅数值对齐（曲线无法与 animateTo EaseOut 完全一致且双参数源易漂移，弃）。
- **D20 置顶移动语义修复（FR-022，FR-020 互换 bug 根因）**
  - **Decision**: `pinToTop` 的 provider 通知由单发 `onDataMove(idx, 0)` 改为**相邻交换冒泡序列**——`onDataMove(idx, idx-1)`、`onDataMove(idx-1, idx-2)`、…、`onDataMove(1, 0)`，全序列在同一 animateTo 闭包内逐个发出；数据层照旧 splice unshift + 归一化 + 落盘；`SubDataSource` 的 `move(from, to)` 改造为 `moveToFront(idx)`（rows splice 移至 0 + 冒泡通知序列），原单发 move 形态废弃。
  - **Rationale**: 本机 SDK lazy_for_each.d.ts onDataMove 官方注释明示「data is **swapped** between the from and to positions」——**交换语义**；FR-020 单发 onDataMove(idx, 0) 被框架按交换渲染（视觉：置顶行与首位行互换、中间行不动），数据层是移动语义（unshift），两层脱节——与真机实测「置顶条与当前条互换」完全吻合。冒泡序列每步是合法的相邻交换，N-1 步后框架索引映射与数据源最终排列一致；同一 animateTo 内全序列补间 = 被置顶行一路飞向首位、途经行各退一位（移动视觉）。连续置顶多次同样正确（每步后框架与数据保持同构收敛）。
  - **Alternatives considered**: 单发 onDataMove + 事后 rebuild 纠偏（动画被打断且互换视觉先出现，弃）；onDataDelete+onDataAdd 模拟移动（删除塌陷+顶部插入下推，非移动视觉，弃）。
- **D21 单 List 合并与恒挂载把手（FR-023，多选机制复刻）**
  - **Decision**: 编辑/正常**双 List 分支合并为单 List**——`LazyForEach` 恒绑 `.onMove`（`applyDragOrder` 内加 `editMode` 闸：非编辑态落子不改序）；行结构合并（`editRowItem` 废弃，`subRowItem` 承载全部形态）：拖拽把手容器**恒挂载行首**（`width(editMode ? 把手宽 : 0)` + `opacity(editMode ? 1 : 0)`，机制与 SelectCheckbox.ets:29 一字不差），`subRowCore` layoutWeight 真实让位；把手宽/图标尺寸令牌入 Constants；编辑态行为闸下沉行内——onClick 导航闸（既有）、LongPressGesture.onAction 弹菜单闸、swipeAction 保留（编辑态侧滑删除可用，无害）；List 层 transition（编辑/正常两处 Stack 的 OPACITY）随分支合并删除；标题/按钮 5 处 transition 保留。`applyDragOrder` 落子通知照旧 silentMove（D12 纪律不变）。
  - **Rationale**: 多选让位动画成立的机制三要素——单 List（无分支替换）+ 勾选框恒挂载（宽度/透明度绑定）+ 内容 layoutWeight 真实让位；编辑态此前因「拖拽 onMove 与长按菜单同用长按手势冲突」被迫双 List 分支，分支替换销毁重建行节点致恒挂载补间无从发生。onMove 无禁用开关，恒绑是单 List 的必要代价；行内三闸（导航/菜单/落子）消解正常态语义混入。正常态长按弹菜单时行可能伴随系统拖拽浮起（onMove 恒绑副作用）、正常态拖动落子被闸拒后视觉回弹——均登记真机自查，观感不可接受时回退方案为恢复双 List 分支（仅丢让位动画）。
  - **Alternatives considered**: 维持双 List 仅做行内恒挂载（分支替换销毁重建节点，无补间空间，弃）；正常态长按菜单改其他触发方式（US6 已定案长按语义，弃）。
- **D22 编辑态整行可拖放修复（FR-024，US8 单 List 合并引入的拖拽回归）**
  - **Decision**: 第一版（已真机验证修复拖拽）：`subRowItem` 根 Row 加 `.enabled(!this.editMode)`——编辑态行级全部交互禁用，触摸穿透给 LazyForEach.onMove 系统拖拽。第二版（真机验证失败已回退）：去除 `.enabled()`、LongPressGesture 改 `.parallelGesture()` 并行挂载——按压反馈恢复（用户确认「按压效果有了」）但**编辑态拖拽回归**（「进入排序模式的条目无法拖动」），并行挂载未消除长按手势对系统拖拽的阻塞；二版补丁（副作用，随回退保留无害）：onClick 闸扩 `editMode || menuKey !== ''`（并行识别下长按序列尾部 Up 仍判 click 致弹菜单同时导航，menuKey 先置位拦截）。第三版（当前）：`.enabled(!editMode)` 恢复（拖拽保证）+ LongPressGesture 恢复 `.gesture()` 原挂载 + **onTouch（pressedKey 按压链）从行根 Row 移到 ListItem 恒挂**——编辑态行 enabled(false) 触摸穿透落到父级 ListItem（LazyForEach 直接子节点），ListItem.onTouch 收到触摸更新 pressedKey（按压背景+阴影照常）；onTouch 纯监听不参与手势仲裁，理论不阻塞系统拖拽；正常态触摸命中行、冒泡到 ListItem.onTouch，按压反馈不变。**回退条件**：真机编辑态 ListItem.onTouch 收不到穿透触摸（按压反馈仅正常态）或拖拽仍回归 → 纯回退第一版（编辑态按压反馈放弃）。
  - **Rationale**: 拖拽回归的时间线证据链：US5–US7 期间双 List 分支、编辑行零手势，编辑态整行拖拽一直正常；US8 合并单 List 后失效——唯一变量是编辑行带上了行级手势，其中 LongPressGesture 与 onMove 拖拽同为长按触发，手势仲裁中行级手势识别达成即阻塞系统拖拽接管。enabled(false) 使组件不响应触摸、事件穿透给父层（LazyForEach/List 层手势正常识别），是禁行级交互的最小开关；但用户真机反馈要求编辑态保留按压反馈（「我只想做按压反馈」），enabled 全禁与按压反馈互斥，故第二版改攻竞争源本身——parallelGesture 并行仲裁理论上行级手势不再阻塞系统拖拽识别，且 onTouch 纯监听不参与手势仲裁、按压链不受影响。
  - **Alternatives considered**: 行内 if/else 切换带手势/无手势两版行结构（分支替换销毁重建节点，US8 让位动画丢失，弃）；GesturePriority 优先级调参（对系统内建手势仲裁不可预期，弃）；行内透明手势宿主子组件条件挂载（结构复杂度高于 parallelGesture 一行改动，弃）。
- **D23 把手留白对称（FR-025）**
  - **Decision**: 恒挂载把手容器内 SymbolGlyph 保持水平居中（justifyContent(FlexAlign.Center) 既有），确认图标至行左缘与图标至内容起点两侧留白等值——数值不等时以 padding/令牌微调对齐（TOKEN_DRAG_HANDLE_W 38vp 容器下图标 22vp 两侧各 8vp 基准）。
  - **Rationale**: 用户真机反馈左右留白不对称；视觉一致性微调，无行为变更。
- **D24 把手即按即拖（FR-026，自定义手动拖拽路径）**
  - **Decision**: 把手挂 `PanGesture({ direction: PanDirection.Vertical })` 手动拖拽。行结构重排：`subRowItem` 根 Row（视觉承载——padding/borderRadius/背景/scale/shadow/translate，恒 enabled）内分两段——把手容器（宽度/透明度绑 editMode 既有 + Parallel 并行手势组：PanGesture + 空长按认领阻断）与内容包装 Row（`layoutWeight(1)`、`.enabled(!editMode)` 保留 D22 禁穿透语义、onClick 闸/LongPressGesture/bindMenu 随迁入内）；正常态把手真零宽无触面零回归（ArkUI `.width()` 内容宽语义——width(0)+padding 有残带，padding 须随宽度同条件归零，bugfix.md §1）。拖拽状态：`@Local draggingKey/dragOffsetY/dragBaseline`（translate 绑定需三者响应式，偏移取 GestureEvent.offsetY 按压起算）+ private dragActive/dragFromIndex（dragActive 兼作 settle onFinish 清态守卫，防落槽动画窗口内重启拖拽被误清）；被拖行 `.translate({ y: draggingKey===row.sub.id ? dragOffsetY - dragBaseline : 0 })` + `.zIndex(1)` 挂 ListItem（translate 不经根 Row `.animation()`——无 value 过滤的 animation 覆盖含 translate 在内全部可动画属性，挂根 Row 拖拽跟手变橡皮筋）。换位：累积位移每跨 `TOKEN_DRAG_SWAP_DISTANCE`（行高+List 间距常量 80，行高统一前提）即与目标方向相邻行交换——subs splice 相邻互换 + `provider.swapNotify(from, to)`（相邻守卫 + 单发 onDataMove，相邻两元素互换与 swap 语义精确匹配，D20 同源结论），包 `animateTo(TOKEN_SELECT_ANIM_MS/EaseOut)` 驱动邻居补位；dragBaseline 随每次交换按方向累进阈值。松手 settleDrag：animateTo 内 dragOffsetY→dragBaseline（相对位移归零），`onFinish`（dragActive 守卫）清拖拽态；sortOrder 归一化 + saveSubscriptions 落盘。互斥闸：`applyDragOrder` 加 draggingKey!=='' 早退（手动拖拽中系统 onMove 落子拒绝）；pan onActionStart 加 !editMode 守卫；exitEditMode 清拖拽态；多指边缘以循环守卫（单次拖拽最多 10 次换位）兜底。
  - **Rationale**: 用户要求把手按下直接进拖拽；onMove 系统拖拽长按阈值内建不可配（FAQ faqs-arkui-310 明示不支持修改，唯一途径自定义重写）；PanGesture onActionStart 在移动识别时触发（非按下）——触把手立即移动→pan 认领；触把手按住不动→空长按（子组件同型手势优先于 List 内建）认领阻断系统拖拽（用户决策去除把手长按触发，把手 pan-only）；并行仲裁 pan 不因长按认领出局，按住后再移动仍入手写拖拽（Exclusive 初版有「按住 500ms 后移动无反应」死区，真机反馈改 Parallel）；编辑态整行长按系统拖拽由内容区触摸穿透承担；换位复用相邻交换语义（onDataMove 官方 swap 语义）保证框架索引与数据源同构收敛；无 API 实测行高，行高统一（52+2×10+List 间距 8=80）前提下取常量入 Constants。
  - **Alternatives considered**: 手动拖拽 v1 自动滚动（长距离拖拽改用整行长按系统拖——系统自带边缘滚动，弃）；onLongPress 回调（onMove 20+）改造系统拖拽起拖时点（回调仅事件通知无起拖控制能力，弃）。

## Data Model

- **导出文件（JSON，与 subscriptions.json 完全同构）**:
  - 结构：`{ "items": [ <Subscription 记录> ... ] }`
  - Subscription 记录 14 字段全量携带（id/type/sourceId/ownerMid/title/cover/upperName/folderOwnerMid/folderOwnerName/lastSeenAt/lastRefreshAt/latestPubAt/totalCount/sortOrder），复用 `toRecord`/`fromRecord`，不建新模型
  - 落点：`cacheDir` 固定文件名（Constants 定义），每次导出覆盖写
- **Subscription（既有，零结构变更）**: 排序仅操作 sortOrder；D3 归一化后 sortOrder = 显示下标
- **SubDataSource（HomePage 内既有类，扩展）**: `moveToFront(idx)`——rows splice 移至 0 + 相邻交换冒泡通知序列 `onDataMove(idx, idx-1)`…`onDataMove(1, 0)`（置顶路径专用，移动语义视觉，D20）；静默重排方法（数组 splice 不通知 listener，onMove 拖拽落子路径专用——官方文档 onMove 场景无需通知，D12）；`swapNotify(from, to)`——相邻守卫 + rows splice 相邻互换 + 单发 onDataMove（把手手动拖拽换位专用，相邻两元素互换与 swap 语义精确匹配，D24）
- **ImportResult（SubscriptionStore 内新接口）**: `{ added: number, skipped: number }`——导入结果计数，供 UI toast

## Contracts & Interfaces

- **SubscriptionStore（新增静态方法）**:
  - 导出：读全量订阅 → 写 cacheDir 导出文件 → 返回沙箱路径（无订阅返回空串，UI 层拦截）
  - 导入：入参用户文件 URI → 校验（JSON 可解析/含 items/条目 id+type 齐全）→ 去重合并落盘 → 返回 ImportResult；非法文件抛错（UI 层 toast），现有订阅数据零改动
- **BackHandler（新增注册函数）**: 首页编辑态退出句柄（模块级变量 + register/unregister），`dismissOverlaysForBack` 最前消费；句柄语义对齐 `registerSettingsBack`（返回 boolean 表是否消化）
- **FileUtil（新增静态方法）**: 按用户文件 URI 读文本（openSync(uri) → fd 读取 → utf-8 解码），异常上抛由调用方兜底
- **Constants（新增，唯一真相源）**: 导出文件名、UTD 类型串、导出/导入/合并结果/失败 toast 文案、菜单/编辑态/拖拽把手动画与尺寸令牌（TOKEN_SELECT_ANIM_MS、TOKEN_ROW_MENU_SCALE、TOKEN_ROW_MENU_SCALE_ANIM_MS、TOKEN_DRAG_HANDLE_W、TOKEN_DRAG_SWAP_DISTANCE、TOKEN_FLOATING_SHADOW_RADIUS、TOKEN_FLOATING_SHADOW_OFFSET_Y）；零业务 import 不变
- **SettingsPage（新增分组）**: 「订阅管理」group 两行——导出订阅（点击→空列表拦截 toast / 生成文件→拉起分享面板）、导入订阅（点击→文档选择器→合并→结果 toast→bump 首页重建键）
- **HomePage（US1/US5–US9 改造面）**: 编辑态状态位；单 List（恒绑 `LazyForEach.onMove` + `applyDragOrder` editMode 闸 + draggingKey 早退闸，落子静默重排 D12）；长按弹菜单（LongPressGesture.onAction 按压达成即触发 + 受控 bindMenu 置顶/排序/删除，placement Top，D13/D15）；置顶 pinToTop（animateTo 包数据重排 + `moveToFront` 冒泡通知，不调 rebuild，D18/D20）；进退编辑态 animateTo(TOKEN_SELECT_ANIM_MS/EaseOut) 驱动 7 处 OPACITY transition（D19）；恒挂载拖拽把手（宽度/透明度绑 editMode，行内容 layoutWeight 让位，D21）；行根 `.enabled(!editMode)` + ListItem 恒挂 onTouch 按压链（按压背景/浮起阴影，D22）；把手留白对称（D23）；把手即按即拖（把手挂 PanGesture 手动拖拽 + 相邻交换换位 swapNotify + settle 归位落盘 + 双路径互斥闸，D24）；标题栏「完成」按钮、rebuild 挂起/恢复（D4）；`bindContextMenu` 及 subRowMenu 移除；confirmRemoveSub 保留（左滑入口继续使用）
