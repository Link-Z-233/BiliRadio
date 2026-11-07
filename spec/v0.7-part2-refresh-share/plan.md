# Implementation Plan: 回前台静默刷新、新集提醒、首页拖拽边缘滚动与分享导入（v0.7-part2-refresh-share）

**Input**: Feature specification from `spec/v0.7-part2-refresh-share/spec.md`

## Summary

part2 含三批需求：① 回前台触发静默刷新（Index.onPageShow bump 既有 `AS_HOME_REFRESH_TICK`，HomePage 既有 @Monitor 补调 silentRefresh，三层门收敛）+ 静默刷新新集正向增量 toast（刷新窗前后全源新集总数对比，仅 N>0 弹）；② 首页列表底缘永久让位 MiniPlayer（视口收短替代 contentEndOffset，内建拖拽触发区随视口上提，真机验证）+ 把手拖拽补边缘自动滚动（复用 SelectLogic 的 EdgeAutoScroller 与 SourcePage 边缘带模式，滚动位移并入换位基准）；③ 系统分享到应用导入（module.json5 注册文本类分享接收，EntryAbility onCreate/onNewWant 经 systemShare.getSharedData 取数写全局键，HomePage 消费门控——extractBiliUrl 抽到 B 站链接开加号面板灌入+自动检索，抽不到 toast 拒收）。

## Technical Context

- **Language/Version**: ArkTS（compatibleSdkVersion 26.0.0，单模块 HarmonyOS NEXT，零第三方依赖）
- **State Management**: 增量改动沿用项目现状——页面/组件 V2（@Local/@Param/@Monitor/V2State connect*），PlayerController 零装饰器广播，不引入代际迁移
- **Storage**: 既有 AppStore（preferences）+ SubscriptionStore（订阅/集数落盘），无新增持久化实体；分享文本经 V2State 全局键瞬态传递（AppStorageV2 同 key 全局共享实例）
- **Testing**: 无测试套件（devDependencies 有 hypium 但无测试文件）；验证走 arkts_check + devecocli build + 真机自查
- **Constraints**: Constants.ets 唯一真相源（零裸数字/裸文案）；代码零注释（`ponytail:` 例外）；文档随代码同步（architecture.md）
- **Scale/Scope**: 改动 5 个源文件 + 1 常量文件 + module.json5 + 文档同步，无新文件

## Project Structure

```text
spec/v0.7-part2-refresh-share/
├── spec.md               # 本轮规格（五 US）
├── plan.md               # 本文件
└── tasks.md              # Phase 3 产出

entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets  # US5：onCreate/onNewWant getSharedData 取分享文本写全局键（传输层，零业务逻辑）
├── pages/
│   ├── Index.ets         # US1：onPageShow bump homeRefreshTick
│   ├── HomePage.ets      # US1 Monitor 补调；US2 总数对比+toast；US3 让位；US4 把手边缘滚动；US5 分享键消费门控+开面板
│   ├── AddSubscriptionSheet.ets  # US5：initialInput @Param 灌入+自动检索（@Param+@Monitor V2 既有代际内组合）
│   └── SourcePage.ets    # 不改（EdgeAutoScroller/边缘带模式复用来源）
├── service/
│   ├── Constants.ets     # US2：TOAST_NEW_EPISODES_FOUND；US5：AS_SHARE_IMPORT_TEXT、TOAST_SHARE_UNSUPPORTED
│   ├── LinkResolver.ets  # 不改（extractBiliUrl 复用，US5 门控）
│   └── SelectLogic.ets   # 不改（EdgeAutoScroller 原样复用）
└── component/
    └── MiniPlayer.ets    # 不改（让位在 HomePage 侧收短视口，胶囊布局不动）

entry/src/main/module.json5  # US5：EntryAbility skills 追加分享接收注册
docs/architecture.md         # 同步：HomePage/AddSubscriptionSheet/EntryAbility 职责、FR-015 下穿过设计废止记载
```

**Structure Decision**: 沿用既有项目架构（entryability/pages/service/component 分层，依赖单向：pages→service），不引入 MVVM 迁移、不新建文件——全部改动落在既有文件内，复用既有服务（EdgeAutoScroller、AppStore、SubscriptionStore、LinkResolver.extractBiliUrl、V2State）。

## Research & Decisions

- **D1 回前台触发点（US1）**
  - **Decision**: Index（唯一 @Entry）增加页面显示生命周期回调 onPageShow，内以既有惯例 bump 全局键（`connectNum(AS_HOME_REFRESH_TICK, 0).value = Date.now()`，与 SourcePage.onHidden/SettingsPage 同款写法）；HomePage 既有 `@Monitor('homeRefreshTick.value')` 由只调 rebuild 扩为 rebuild + silentRefresh；CD 分层（⑭ 拍板）：silentRefresh 参数化（cdMs）——aboutToAppear 冷启动直调传 `HOME_COLD_START_REFRESH_CD_MS`（15 分钟）、@Monitor tick 链传 `HOME_FOREGROUND_REFRESH_CD_MS`（1 小时），同一 `KEY_LAST_SILENT_REFRESH_AT` 时间戳判定；设置层关闭成为回首页触发点：SettingsPage.aboutToDisappear（Index 条件渲染卸载点）bump 同键，与源页退出同构；导入链 bump 移除导入完成时的首次 bump（保留新订阅拉取完成后令首页重算的 bump），新订阅数据由导入链 `refreshAll(newSubs)` 自拉无 CD
  - **Rationale**: 子组件无页面级生命周期，Index.onPageShow 是回前台唯一挂点；复用既有键链路使三层门（分源 CD/TTL/防重入）天然收敛多触发点（冷启动 aboutToAppear 与 onPageShow 并存收敛为单次实际刷新，属预期空转）；CD 分层消除回前台频繁触发顾虑（1 小时内触发仅重算列表零网络请求），冷启动保持 15 分钟拿数据更勤；触发点 4 迁移到设置层关闭因导入链自拉新订阅数据（tick bump 仅为首页重算时机），「回首页才刷新」语义与源页退出同构成立
  - **Alternatives considered**: Ability 级 onForeground（走 UIAbility 不经页面，需另建桥接键，多一层间接无收益）；直接在 HomePage 监听 AppStorage 前后台态（无此既有机制，新造轮子）；严格「回首页才触发」（回前台加首页无遮挡判定——需感知源页/设置/日志/浮层/面板各层状态，耦合面大，可观察收益仅 toast 位置，⑭ 弃用）；设置页导入完成即时 bump 保持原位（刷新在设置层底下进行、toast 弹在设置页上，与「回首页刷新」语义不符，⑭ 迁移）

- **D2 新集总数口径与对比窗（US2）**
  - **Decision**: silentRefresh 过 CD 门后、发起刷新前快照全源新集总数（各源 countNew(loadEpisodes, lastSeenAt) 之和，直接读 SubscriptionStore，不经 rebuild 行缓存）；刷新收尾重算总数，正向增量 N>0 弹 `TOAST_NEW_EPISODES_FOUND`（N 占位替换），与失败 toast 按各自语义并存
  - **Rationale**: 直读存储口径不受编辑态挂起 rebuild 影响（spec 边界情况「编辑态差值退化」由此规避）；刷新前后两次快照即完整对比窗，无额外状态
  - **Alternatives considered**: 从 rebuild 行数据聚合（耦合编辑态挂起语义）；per-sub 回调增量累计（与 lastSeenAt 写入竞态，口径不稳）

- **D3 列表底缘让位实现（US3）**
  - **Decision**: HomePage 列表容器（现 `Stack { List }.layoutWeight(1)`）加底部让位量 = `MINI_PLAYER_CLEARANCE + navBarHeight`（与现 contentEndOffset 同值同式），同时移除 List 的 `.contentEndOffset(...)`；让位对正常态/编辑态恒生效（永久）
  - **Rationale**: 同值迁移保证滚到底最后一条静止位置与现状完全一致（视觉零跳变）；视口底缘从屏底上移到胶囊上方后，内建拖拽触发区随视口上提（实测推断，D4 验证）；空态 emptyView 分支不收短（无滚动/拖拽需求，胶囊悬浮空态为既有观感）
  - **Alternatives considered**: 编辑态临时收短（用户已拍板「永久」）；编辑态隐藏 MiniPlayer（触发区未上提仅去遮挡，且排序中丢失播放信息）；保留 contentEndOffset 仅收短容器（双让位叠加，最后一条被推高，视觉跳变）

- **D4 内建触发区跟随视口的验证义务（US3）**
  - **Decision**: 「内建拖拽触发区位于 List 视口底缘」是从现状观察反推的系统行为（现触发区在屏底=现视口底缘），非文档承诺；实施后须真机验证 US3 场景 2，不成立则回退重议（候选回退：编辑态临时隐藏 MiniPlayer），不静默绕过
  - **Rationale**: 系统 onMove 拖拽无公开触发区配置 API（文档检索确认）；把不可控系统行为列为显式验证点而非假设
  - **Alternatives considered**: 预先写死回退实现（过度设计，验证失败才需要）

- **D5 把手边缘滚动接入（US4）**
  - **Decision**: HomePage 持 EdgeAutoScroller 实例（SelectLogic 原样复用），按 SourcePage 既有模式接入：List 挂 id（模块级 const，同 SWEEP_LIST_ID 先例）供 getRectangleById 量视口矩形；边缘带沿用 `SELECT_SWEEP_EDGE_ZONE`（48vp，零新常量，EdgeAutoScroller 内部速度/时钟常量自带给养）；onActionUpdate 与边缘滚动 tick 均做带位检查——globalY 进顶部/底部带起滚、出带停、atEnd（isAtEnd / yOffset≤0）停；onActionEnd/Cancel 与既有 settleDrag 前统一 stop
  - **Rationale**: 拖选场景同构先例全套搬用（时钟驱动 scrollBy 走列表既有滚动管线、atEnd 尽头停滚、幂等 start/stop），把新逻辑压缩到「带位检查 + 换位基准」两点
  - **Alternatives considered**: 新写滚动器（重复造轮子）；把 EdgeAutoScroller 泛化改名（无行为收益的翻新，触 SourcePage 回归面）

- **D6 滚动位移并入换位基准（US4）**
  - **Decision**: 起拖时快照列表 yOffset；换位判定位移由「手指累积纵向偏移」扩为「手指累积纵向偏移 +（当前 yOffset − 起拖快照）」；dragBaseline/dragFromIndex 既有语义不变（基准随换位累进、阈值交换、落槽归零），settleDrag 落位与 sortOrder 归一化落盘链路零改动
  - **Rationale**: 手指按住触发带时列表滚动，被拖行 translate 锁手指、邻行随内容滚动，相对位移即滚动量——并入基准后换位判定在纯手指移动与纯边缘滚动两种路径下同一套逻辑成立
  - **Alternatives considered**: 边缘滚动时另走独立换位路径（双路径分叉，落位/落盘语义易漂移）

- **D7 分享接收注册与传输层（US5）**
  - **Decision**: module.json5 EntryAbility.skills 追加分享 skill（actions `ohos.want.action.sendData`，uris 穷举 `general.text` 文本类型，照官方应用内处理示例配置）；EntryAbility 增 onNewWant 回调并在 onCreate 内处理分享 want——`systemShare.getSharedData(want)` 取分享数据，records 首条文本（record.content 为文本内容——本机 SDK d.ts 证实：content 承载 text/link 类型数据，uri 仅承载文件 URI）**原文**写入全局键 `AS_SHARE_IMPORT_TEXT`（StrState，connectStr 惯例）；getSharedData 失败静默记日志不崩；EntryAbility 只做「取数→写键」传输，不引任何业务逻辑（extractBiliUrl 不进 Ability 层）
  - **Rationale**: 应用内处理分享内容的官方路线（UIAbility 接收，文档示例确证 onCreate/onNewWant 取数、onForeground 取不到）；写原文而非预抽链接保持传输层零业务依赖，且门控/拒收均需 UI 上下文（Ability 层无 UIContext，冷启动时序不可控）；V2State 键为 AppStorageV2 同 key 全局共享实例，冷启动早于页面挂载的写入天然不丢（HomePage 挂载时读当前值兜底，D8）
  - **Alternatives considered**: ShareExtensionAbility 分享详情页（面板内嵌页，非「打开应用加号面板」的产品语义）；EntryAbility 预抽链接再写键（业务逻辑进 Ability 层，拒收 toast 仍需 UI 层二次通道，逻辑分叉两处）

- **D8 分享门控与视频短路路由（US5 UI 层）**
  - **Decision**: HomePage 消费 `AS_SHARE_IMPORT_TEXT`：`@Monitor('shareImportText.value')`（镜像既有 homeRefreshTick 监听模式）+ aboutToAppear 兜底读当前值（冷启动写入早于挂载场景）；消费即清键（拷贝到 @Local 后置 ''，支持面板已开时再次分享）；门控用既有 `extractBiliUrl`（LinkResolver，含尾随标点清除、b23.tv 短链语义）——抽到 B 站链接进入路由分流（routeShareImport → dispatchShareTarget）：短链先 resolveShortLink 解析，解析失败回退 openShareSheet（灌原始 cleaned 链接，面板内重新走完整链含再解析）；**视频类（识别 bv/av）直接入队**——bv 调 addSingleVideo、av 经 fetchVideoInfoByAid 归一化后入队，入队结果 APPENDED/STARTED/DUPLICATE 仅 toast（PlayerController.enqueueToast 既有）不开面板，FAILED/异常回退 openShareSheet；**订阅类及其他识别结果 openShareSheet**（抽得链接存 @Local + showAddSheet = true，走 D9 面板链）；抽不到 B 站链接 → toast `TOAST_SHARE_UNSUPPORTED` 不弹面板
  - **Rationale**: 门控/路由集中在 HomePage（showAddSheet 是其 @Local，单消费方）；视频短路消除「面板弹出动画未完成即被 onDismiss 关闭」的闪现（⑨ 用户拍板「分享在视频在不出错时不开面板」），失败回退面板保留反馈+重试能力；订阅类保留面板确认环节；拒收文案落 Constants 遵 TOAST_* 惯例
  - **Alternatives considered**: 全部分享一律开面板（视频类闪现，原 D8 方案被 ⑨ 推翻）；视频失败仅 toast 不开面板（丢失面板内反馈与手动重试环节）；分享进来直接订阅不入面板（丢失确认环节）

- **D9 面板灌入与自动检索（US5 订阅类与视频失败回退路径）**
  - **Decision**: AddSubscriptionSheet 新增 `@Param initialInput: string = ''`（HomePage addSheetBuilder 传入 @Local shareImportText）；aboutToAppear 内非空 → mainInput = initialInput + 调既有 handleMainInput()（一次检索）；`@Monitor('initialInput')` 处理面板已开时再次分享（输入更新+重检索）；视频入队失败/短链解析失败回退经 openShareSheet 走本链（initialInput 为原始 cleaned 链接，面板内重新走完整识别链）；handleMainInput 既有链零改动（清洗→短链解析→识别分发全复用）；面板按既有 bindSheet z 序叠加，BackHandler 返回链零改动（FR-017）
  - **Rationale**: 分享导入 = 自动化「加号→粘贴→检索」手动链，面板复用最大化、零新识别逻辑；@Param+@Monitor 为 V2 代际内合法组合，bindSheet builder 依赖 HomePage @Local 自动重渲染传参；编辑态/播放浮层上叠加弹面板属 spec 已接受边界（关闭回原界面）
  - **Alternatives considered**: 每次分享先关再开面板（闪烁，且 onDismiss 链路多触发一次）

- **D10 源页下拉刷新与自定义「更多」菜单（US6）**
  - **Decision**: SourcePage Stack 内 Refresh 包裹既有 List：`Refresh({ refreshing: this.refreshing!!, refreshingContent: this.refreshContent })`（@Local refreshing 双向绑定，refresh.d.ts 证实 refreshing 支持 $/!! 双向）+ `.onRefreshing(() => this.refreshSource())` 复用既有刷新链（toast「已更新」/回顶部/失败复位全复用）；刷新提示区经 refreshingContent 自定义承载（⑪/⑫ 真机反馈修正+拍板）：模块级 `class RefreshHintParams`（text/visible）+ `@Builder function refreshIndicatorBuilder(params)`（visible 时渲染自转 LoadingProgress + params.text，均 text_secondary 色）+ `wrapBuilder` 包装 + `aboutToAppear` 内 `new ComponentContent(this.getUIContext(), wrapBuilder(refreshIndicatorBuilder), this.refreshParams)` 创建（字段 `ComponentContent<RefreshHintParams> | undefined`，@kit.ArkUI re-export 证实）、`aboutToDisappear` 内 `dispose()` 释放，`.constraintSize({ minHeight: TOKEN_REFRESH_HINT_MIN_H })` 防高度塌缩（refresh.d.ts 证实 refreshingContent 自定义区高度随下拉距离自适应，官方 FAQ 同款约束）；提示文案全状态机（⑫ 用户拍板）：`.onStateChange`（RefreshStatus：OverDrag→REFRESH_HINT_RELEASE / Refresh→REFRESH_HINT_REFRESHING / 其余→REFRESH_HINT_PULL）改 params.text 后 `refreshContent.update(params)` 驱动重渲染（ComponentContent 不感知组件状态，须显式 update，官方 FAQ 证实；下拉与菜单两入口同态）；提示区可见性刷新态门控（⑬ 真机反馈修复——minHeight 使自适应高度静息下限 32，不门控详情页挂载即现加载动画）：params.visible 默认 false，onStateChange 计算（Drag/OverDrag/Refresh 且非多选 → 可见，Inactive/Done → 隐藏），builder 以 `.visibility(Visible/None)` 属性绑定承载（弃 if 结构渲染，规避 ComponentContent update 结构 diff 风险）；多选禁用（⑫ 拍板「恢复回弹藏图标」）：`.pullToRefresh(!this.selectMode)` 只挡发起刷新 + 可见性门控 !selectMode 条件（多选拉动自动不显）+ enterSelectMode 置 false / exitSelectMode 按 this.refreshing 恢复（刷新中退出多选提示区回显，静息退出不误显）（顶部跟手回弹保留、图标文案不出现；多选下拉露出页面底色空白为接受代价）；refreshSource 既有 `if (this.refreshing) return` 守卫移除（双向绑定下组件先行置 true，守卫会使下拉刷新永不执行），防重入由组件 refreshing 态 + 刷新中「···→LoadingProgress」图标替换承担；「更多」菜单由 bindMenu 数组形态改自定义 @Builder（Menu + MenuItem）：「刷新」默认色、「取消订阅」`.contentFontColor($r('app.color.danger_red'))`（menu_item.d.ts 证实 contentFontColor 存在；bindMenu CustomBuilder 传参形态为方法引用 `this.moreMenuBuilder`，官方 FAQ 证实）；placement BottomRight 保留；文案落 Constants `MENU_LABEL_REFRESH`/`MENU_LABEL_UNSUBSCRIBE`（替换原数组裸字面量）
  - **Rationale**: onRefreshing 直连 refreshSource 是最小接入（刷新链零复制）；守卫移除经两入口分析确认安全（下拉不重触发、菜单刷新中不可达）；refreshingContent 替代 builder 承载刷新提示区（builder 形态刷新中销毁重建自定义区致动画中断+闪烁，官方 FAQ 证实，API 12+ 明示用 refreshingContent）；多选禁用经三段演进收敛（pullDownRatio(0) 彻底禁用连顶部跟手回弹一起焊死，真机反馈推翻；终态 pullToRefresh 挡发起 + 刷区内容隐藏，「多选不触发刷新」与「回弹保留」兼得）；提示区静息可见 bug 修复经状态门控收敛（⑬：visible 默认 false + onStateChange 刷新态计算 + visibility 属性绑定，静息常显与挂载首帧闪现一并堵死；Done 后 Inactive 是否必至无文档保证故完成即隐藏，瞬时隐藏替代随区收起）；自定义 MenuItem 承载是 bindMenu 单项着色的唯一路径（数组形态 MenuElement 无文字色参数）；danger_red 明暗双态既有资源零新增
  - **Alternatives considered**: Refresh 单向绑定 + 保留守卫（下拉触发链依赖推测行为，双向绑定文档确证更稳）；onRefreshing 内 selectMode guard（spinner 卡刷新态，改 pullToRefresh 开关）；pullDownRatio(selectMode ? 0 : undefined) 彻底禁多选下拉（官方 FAQ 唯一记载彻底禁用法，真机复测顶部跟手回弹一并焊死，⑫ 拍板弃用）；提示文案静态恒显「下拉刷新」（刷新中文字与状态不匹配，用户质疑后 ⑫ 拍板全状态机，弃）；builder 形态自定义刷新区（刷新中销毁重建致动画中断，弃）；refreshColor 自定义刷新色（refresh.d.ts 证实不存在该属性，用默认色）

## Data Model

- **无新增持久化实体**。既有 Subscription.sortOrder/countNew、AppStore CD 时间戳语义不变
- **Constants 新增**：`TOAST_NEW_EPISODES_FOUND`（「发现 N 集新节目」，N 占位）、`AS_SHARE_IMPORT_TEXT`（'shareImportText'，AS_* 键惯例）、`TOAST_SHARE_UNSUPPORTED`（TOAST_* 惯例）、`MENU_LABEL_REFRESH`/`MENU_LABEL_UNSUBSCRIBE`（「刷新」「取消订阅」，US6 菜单文案）、`REFRESH_HINT_PULL`/`REFRESH_HINT_RELEASE`/`REFRESH_HINT_REFRESHING`（「下拉刷新」「释放刷新」「刷新中」，US6 刷新提示区状态机三态）/`TOKEN_REFRESH_HINT_MIN_H`（32，US6 刷新提示区最小高约束）、`HOME_COLD_START_REFRESH_CD_MS`（15 分钟，⑭ 由 `HOME_SILENT_REFRESH_CD_MS` 更名）、`HOME_FOREGROUND_REFRESH_CD_MS`（1 小时，⑭ CD 分层）
- **HomePage 瞬态**：EdgeAutoScroller 实例、起拖 yOffset 快照、新集总数前后快照（刷新窗局部量）、Home 列表 id 模块级 const、@Local shareImportText（分享灌入值）
- **AddSubscriptionSheet 新增**：@Param initialInput: string（默认 ''，非分享路径零影响）
- **EntryAbility 瞬态**：无新增成员（getSharedData 结果即写即抛）
- **复用不改**：SELECT_SWEEP_EDGE_ZONE、MINI_PLAYER_CLEARANCE、AS_HOME_REFRESH_TICK、AS_NAV_BAR_HEIGHT、KEY_LAST_SILENT_REFRESH_AT、extractBiliUrl、handleMainInput

## Contracts & Interfaces

- **刷新链路（US1）**: Index.onPageShow（回前台）/ SourcePage.onHidden（源页退出）/ SettingsPage.aboutToDisappear（设置层关闭，⑭）→ bump `AS_HOME_REFRESH_TICK` → HomePage `@Monitor('homeRefreshTick.value')` → rebuild + silentRefresh(1h)；冷启动 aboutToAppear 直调 silentRefresh(15min)；CD 分层（⑭：冷启动 `HOME_COLD_START_REFRESH_CD_MS` 15 分钟 / tick 链 `HOME_FOREGROUND_REFRESH_CD_MS` 1 小时，同一 `KEY_LAST_SILENT_REFRESH_AT` 时间戳）+ 15min 单源 TTL + refreshingNow 对四触发点收敛为单次实际刷新；设置页导入链自拉新订阅（refreshAll(newSubs) 无 CD），拉取完成后 bump 令首页重算；CD 门读 AppStore 须先 await AppStore.init()（既有约束沿用）
- **新集提醒（US2）**: 仅实际发起刷新（过 CD 门）才有对比窗；快照口径 = Σ countNew(episodes, lastSeenAt) 直读 SubscriptionStore；N = after − before，N>0 弹一次；失败 toast、CD 跳过、未实际刷新零新集提示
- **让位契约（US3）**: List 视口底缘 = 屏底 − (MINI_PLAYER_CLEARANCE + navBarHeight)，两态恒成立；滚到底最后一条完整露出位置与现状一致；内建拖拽底部触发区随视口底缘（真机验证点）
- **边缘滚动契约（US4）**: 触发带 = 列表视口顶/底各内缩 SELECT_SWEEP_EDGE_ZONE（globalY 判定）；换位判定位移 = 手指累积纵向偏移 + 拖拽期间滚动位移增量；带内起滚/出带停滚/尽头停滚；与既有 FR-026 双路径互斥、编辑态闸、行节点恒存续前提不冲突
- **分享传输契约（US5 传输层）**: 系统分享面板选 BiliRadio → EntryAbility onCreate（冷启动）/onNewWant（热启动）→ systemShare.getSharedData(want) → 首条文本 record.uri 原文写 `AS_SHARE_IMPORT_TEXT`；仅文本类分享注册（uris `general.text`）；图片/文件分享不进面板推荐区
- **分享消费契约（US5 UI 层）**: HomePage @Monitor + aboutToAppear 兜底消费 AS_SHARE_IMPORT_TEXT（读后清键）；extractBiliUrl 抽到链接后路由分流——视频（bv 直接入队 / av 归一化入队，短链先解析）成功仅 toast 不开面板、失败回退 openShareSheet；短链解析失败回退 openShareSheet；订阅类 openShareSheet（showAddSheet=true + initialInput=抽得链接）→ AddSubscriptionSheet 灌入+检索；抽不到 → TOAST_SHARE_UNSUPPORTED 不弹面板；识别分发行为与手动输入完全一致
- **源页刷新契约（US6）**: 下拉（Refresh onRefreshing）与菜单「刷新」两入口收敛到同一 refreshSource；refreshing `!!` 双向绑定驱动下拉提示区与右上 LoadingProgress 同态；下拉提示区经 refreshingContent（ComponentContent<RefreshHintParams> + wrapBuilder，aboutToAppear 创建/aboutToDisappear dispose）承载自转 LoadingProgress + 全状态机文案（onStateChange：下拉刷新/释放刷新/刷新中，update() 重渲染）；提示区可见性刷新态门控（visible 默认 false，onStateChange 计算，.visibility(Visible/None) 属性绑定）；selectMode 经 pullToRefresh 挡发起 + 可见性门控 !selectMode 条件隐藏刷区内容（顶部跟手回弹保留）；「取消订阅」红色警示经自定义 MenuItem contentFontColor 承载
