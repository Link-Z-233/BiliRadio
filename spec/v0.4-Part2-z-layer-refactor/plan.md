# Implementation Plan: 四层 z 序重构（v0.4-Part2-z-layer-refactor）

**Input**: Feature specification from `spec/v0.4-Part2-z-layer-refactor/spec.md`

## Summary

将 Index 的 Stack 重组为严格四层 z 序栈（L1 导航+胶囊 → L2 设置+日志 → L3 播放浮层 → L4 队列）：设置页与日志页退出系统路由改树内条件渲染层，队列面板收敛为单一挂载点，胶囊显隐的全部时序修补机制（在台标志/400ms 退场延时/250ms 显隐动画/可见性全局键/日志计数缓存）随「高层物理覆盖低层」语义整体退役，返回链按层自上而下统一进 BackHandler（行为语义维持现状，仅机制收敛——去路由后 NavDestination.onBackPressed 消失，返回键只达 Index @Entry）。历史面板维持设置页树内承载（L2），点播行为与现状一致。另含三项经批准的展示层变更：未登录音质档位显示 64K 并引导登录、账号栏大会员标识、历史/日志计数移除。净删除为主的增量重构，零新增文件、零新依赖、零未批准的用户可感知行为变化。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion = 26.0.0，不考虑 API<26 兼容）
**Primary Dependencies**: ArkUI 现有 Kit 集合，本轮零新依赖
**State Management**: 状态管理 V2 沿用（@ComponentV2/@Local/@Monitor；瞬态键经 V2State 包装类走 AppStorageV2.connect，读写 `.value`）
**Storage**: 无持久化变化（本轮纯 UI 层级重构）
**Testing**: 项目无测试套件；验证 = 构建 + 模拟器 UI 实测（用完关闭模拟器，结果回填 PROJECT_NOTES §五）
**Target Platform**: HarmonyOS NEXT（真机为主，模拟器辅助）
**Project Type**: 单模块 HarmonyOS 应用，增量重构
**Performance Goals**: 层转场流畅无掉帧；运行时开销净减少（删定时器与广播链）
**Constraints**: ArkTS 严格模式（禁 any/unknown/as 类型断言）；代码零注释（`ponytail:` 标注除外）；数值一律 Constants 令牌、色彩一律 `$r('app.color.*')`；Constants.ets 唯一真相源
**Scale/Scope**: 11 个源/资源/配置文件 + 2 个文档文件改动；净删除为主

## Project Structure

### Documentation (this feature)

```text
spec/v0.4-Part2-z-layer-refactor/
├── spec.md              # 层序契约 + 用户故事（历史面板定案 L2 + 三项批准变更）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── Index.ets            # 主战场：Stack 层序重排 + 删胶囊隐藏机制 + 返回收敛
│   ├── SettingsPage.ets     # 去路由化 + logCount 删除 + VIP 徽标 + 计数移除（历史面板保留不动）
│   ├── LogPage.ets          # 去路由化
│   ├── PlayerOverlay.ets    # 删内部队列渲染 + onRegisterClose；音质兜底 64K + 登录引导
│   ├── HomePage.ets         # 设置入口改键 + padding 静态化
│   └── SourcePage.ets       # padding 静态化（保留路由承载）
├── component/
│   └── SettingsRow.ets      # VIP 徽标参数扩展
├── service/
│   ├── Constants.ets        # 键/常量增删
│   └── BackHandler.ets      # 返回链统一 + registerSettingsBack
└── resources/
    ├── base/profile/router_map.json   # 摘除 settingsPage/logPage
    └── base/element/color.json        # 新增大会员徽标色
PROJECT_NOTES.md              # 轮次登记 + 实测结果回填
AGENTS.md                     # 架构/导航节更新
```

**Structure Decision**: 沿用现有单模块架构（pages/service/component/model 分层），不引入新目录、新文件或 MVVM 化。层承载在 Index 既有 Stack 内扩展（PlayerOverlay 树内条件渲染先例，KI-5 方案 B）。历史面板维持设置页树内承载（L2），不抽出、不新增文件——历史与队列同级方案（HistorySheet 抽取）经评估后放弃：多一个新文件、一次 ~250 行搬动与一场互斥讨论，换来的仅是概念一致与浅一层点播返回链。

### 分文件变更目标（Implementation Targets）

> 行号为 2026-10-13 基线（commit f228390）参考值，实施时以实际内容定位为准。

**1. `entry/src/main/ets/service/Constants.ets`**
- 增：`AS_SHOW_SETTINGS_PAGE`、`AS_SHOW_LOG_PAGE`（AS_* 瞬态键段，L50-61 区域）；`PAGE_LAYER_SLIDE_MS = 350`（层滑入时长，置于动画常量段）
- 删（收尾任务执行，待消费方全部移除后）：`AS_MINI_PLAYER_VISIBLE`（L59）、`AS_ON_SETTINGS_PAGE`（L60）、`NAV_EXIT_TRANSITION_MS`（L119）、`MINI_VISIBILITY_ANIM_MS`（L121）
- 留：`MINI_PLAYER_CLEARANCE`（L96，静态 padding 取值源）、`AS_SHOW_PLAY_HISTORY`（历史面板标志，设置页树内承载不变）

**2. `entry/src/main/ets/service/BackHandler.ets`**
- `dismissOverlaysForBack` 扩为全链分层序列（自上而下）：队列（多选优先 → 滑出句柄/标志）→ 倍速 → 模式 → 睡眠时长选择 → 睡眠 → 播放浮层 → 日志层 → 设置层内部句柄 → 设置层 → 返回 false
- 现浮层分支内的历史面板处理（L32-35）迁出——历史面板归设置层内部句柄
- 新增模块级 `registerSettingsBack(handle)`（对齐 `registerQueueClose` 范式 L8-12）：SettingsPage aboutToAppear 注册、aboutToDisappear 注销
- `closeBothLayersNow` 语义不变保留；头注释（L4-6）更新为统一入口说明

**3. `entry/src/main/resources/base/profile/router_map.json`**
- 摘除 `settingsPage`、`logPage` 两项；保留 `sourcePage`

**4. `entry/src/main/ets/pages/Index.ets`**
- 删：`onSettingsPage` 成员（L24）、`miniHidden`（L26-27）、`@Monitor onMiniVisibilityChanged` 全段（L106-119）
- 胶囊列（L186-193）：删 opacity/translate/hitTestBehavior 三属性，保留包裹与 padding（恒挂载防订阅累积注释保留）
- `onBackPress`（L124-159）：收敛为单调用 `dismissOverlaysForBack()`，原自维护链（playHistory/speed/mode/sleepPicker/sleepTimer/selectMode）迁 BackHandler
- 增：`@Local showSettingsPage/showLogPage`（connectBool 新键）
- build Stack 层序（自下而上）：背景 Column（L163-167）→ Navigation Column（L169-180 不动）→ 胶囊 Column → **设置层条件块** → **日志层条件块** → PlayerOverlay 条件块（L210-217）→ **队列 GlassSheet 条件块**（自 L196-204 移入末位，条件改仅 `showQueueSheet`，删 `&& !showPlayerOverlay`）
- 设置/日志层条件块：`Column{ ... }` 包裹，`.padding({ top: statusBarHeight })` 对齐 Navigation 包裹层范式，`.transition(TransitionEffect.translate({ x: '100%' }).animation({ duration: PAGE_LAYER_SLIDE_MS, curve: Curve.Friction }))`
- PlayerOverlay 传参删 `onRegisterClose`（L211-213）；导入 SettingsPage/LogPage

**5. `entry/src/main/ets/pages/SettingsPage.ets`**
- 删：`SettingsPageBuilder`（L76-78）、`navPathStack`（L158）、`onSettingsPageTimer`（L163）、`miniPlayerVisible`（L126-127）
- 删 `logCount`（L108 成员、L182 初始化、L1763 onShown 刷新）——原「logCount 迁移 + @Monitor 日志层关闭刷新角标」设计随计数移除整体消亡
- 删计数展示：历史面板标题（L1262）、历史入口行 valueText（L1655-1656）、日志入口行 valueText（L1666）
- 历史面板全套保留不动：`playHistoryPanel`（L1256-1452）、`historyClose`（L153-154）、多选态（L104-105）、`openPlayHistory`（L244-246）、`replayHistory`（L351-361）、数据同步（L176-178）、GlassSheet 挂载（L1734）——仅标题去计数
- 根节点 `NavDestination`（L1505）→ `Stack`（子结构不变；确认根有不透明背景色，缺则补 `page_background`/`sheet_background`——层级覆盖依赖不透明底）
- 返回按钮（L1519-1521）：pop() → 置 `AS_SHOW_SETTINGS_PAGE` 假值
- `openLogPage`（L301-303）：pushPathByName → 置 `AS_SHOW_LOG_PAGE` 真值
- 删 NavDestination 属性链 L1744-1789 全段（hideTitleBar/onWillAppear/onShown/onWillDisappear/onReady——含 `AS_ON_SETTINGS_PAGE` 三段定时器逻辑与 'playHistory'/'about' 参数处理，该参数无调用方）
- settingsBackHandle 注册：句柄内容 = `showQualitySheet` → `showPlayHistory`（多选优先 → historyClose 句柄 → 标志），与原 onBackPressed L1796-1811 逻辑一致（迁移非重写）
- padding（L1694）三元删 miniPlayerVisible，恒取 `MINI_PLAYER_CLEARANCE`
- VIP 徽标：账号行（L1538-1544）SettingsRow 传 `vipBadge`（BiliSession vipStatus === 1 时真）
- 确认 `struct SettingsPage` 导出（Index 直接引用）

**6. `entry/src/main/ets/pages/LogPage.ets`**
- 删：`LogPageBuilder`（L43-46）、`navPathStack`（L59）、`dismissOverlaysForBack` 导入（L3）
- `struct LogPage` 加 export（当前仅 Builder 导出）
- 根 `NavDestination`（L128）→ `Column`（子结构 L129-250 不变，含底部 navBarHeight padding；补不透明背景）
- 返回按钮（L141-143）：pop() → 置 `AS_SHOW_LOG_PAGE` 假值
- 删属性链 L251-256（hideTitleBar/onReady/onBackPressed）

**7. `entry/src/main/ets/pages/PlayerOverlay.ets`**
- 删内部队列渲染块（L1319-1334，含注释）
- 删 `onRegisterClose` 参数（成员声明 + Index 传参）
- 保留 L1351 `noOverlayOpen` 中 showQueueSheet 判定（队列在台时浮层下滑关闭仍不触发——队列已不在浮层内，但标志语义不变）
- 音质兜底（qualityPanel L664-704 else 分支）：档位显示「默认」→「64K」，提示文案「当前内容未提供多音质选择」→ 登录引导（措辞实施定稿，方向「登录后可选更高音质」）；L664 旁「未登录不额外提示」注释随改移除
- 音质入口标签（qualityEntryLabel，L1246-1258）：兜底分支同步「64K」
- 不改取流、不新增面板内登录跳转（登录入口在设置页账号栏已有）

**8. `entry/src/main/ets/pages/HomePage.ets`**
- 设置入口（L400-403）：pushPathByName('settingsPage','') → 置 `AS_SHOW_SETTINGS_PAGE` 真值
- 删 `miniPlayerVisible`（L70-71）；padding（L435）三元删，恒取 `MINI_PLAYER_CLEARANCE`
- `navPathStack` @Param 保留（sourcePage 推送仍在）

**9. `entry/src/main/ets/pages/SourcePage.ets`**
- 删 `miniPlayerVisible`（L57-58）；padding（L495）三元删，恒取 `MINI_PLAYER_CLEARANCE`
- 其余不动（保留路由承载与 onBackPressed）

**10. `entry/src/main/ets/component/SettingsRow.ets` + `entry/src/main/resources/base/element/color.json`**
- SettingsRow 新增可选 `@Param vipBadge`（默认 false），标题侧渲染「大会员」小标签（小号圆角、品牌粉底白字，贴近 B 站官方视觉）
- color.json 新增 `vip_badge_bg`（品牌粉）、`vip_badge_text`（白），经 `$r('app.color.*')` 引用

**11. `PROJECT_NOTES.md` / `AGENTS.md`（Polish 阶段）**
- PROJECT_NOTES：§三补轮次条目；§五登记本轮流模拟器实测项（层转场/返回链分层/队列盖浮层/历史点播覆盖序/深栈逐层关闭/静态 padding 空态/未登录音质 64K/VIP 徽标/计数移除后走查，结果由验证阶段回填）；原「退出设置页胶囊突现」bug 销项说明（根因 z 序，时序修补整体退役）
- AGENTS.md：架构「导航」节更新（设置/日志去路由改层级、历史面板留 L2、router_map 仅 sourcePage、四层 z 序）

## Research & Decisions

**D1: 设置层层位——L2（浮层之下）vs 用户初稿 L5（最高层）**
- **Decision**: L2（导航+胶囊之上、播放浮层之下）
- **Rationale**: 历史点播打开的浮层必须盖住设置层（现状行为零回归）；置最高层则浮层被盖、点播需「收设置层」补丁且返回语义变化。L2 同时满足原诉求（设置层盖胶囊）
- **Alternatives considered**: 设置层最高——历史点播场景破坏现状行为；被否

**D2: 层承载机制——树内条件渲染 vs 保留路由**
- **Decision**: Index Stack 树内条件渲染 + `TransitionEffect.translate`（x 轴）
- **Rationale**: PlayerOverlay 同范式已在真机验证可行（KI-5 方案 B 先例）；路由承载下浮层/队列/胶囊 z 序不可控，正是本轮 bug 根因
- **Alternatives considered**: bindContentCover（API 24 渲染管线断裂，KI-5 已否）；多 @Entry（架构禁）

**D3: `AS_MINI_PLAYER_VISIBLE` 处置——删除+静态 padding vs 语义收窄为「有曲目」**
- **Decision**: 删除，三页 padding 静态化（恒取 `MINI_PLAYER_CLEARANCE`）
- **Rationale**: MiniPlayer 空态渲染「暂无播放内容」占位条（L127-146），胶囊冷启动即可见——静态预留本就是现状实际行为，收窄方案反而引入行为变化（占位条消失）
- **Alternatives considered**: 收窄为 hasTrack——比现状多一层隐藏逻辑；被否

**D4: 队列挂载点——Index 单挂载（L4）vs 维持双挂载**
- **Decision**: 单挂载，条件仅 `showQueueSheet`，Stack 末位（PlayerOverlay 之后）
- **Rationale**: 删 PlayerOverlay 内部份（L1319-1334）；「挂载点两处无法传宿主成员」的模块级注册背景消失（机制保留、注释更新）；两入口视觉不变
- **Alternatives considered**: 双挂载保留——冗余；被否

**D5: 返回链——BackHandler 统一全链 vs 各页分散**
- **Decision**: `dismissOverlaysForBack` 扩为全链单入口；Index onBackPress 收敛为单调用
- **Rationale**: 返回行为语义维持现状（每次按返回关当前最上层，逐场景与今天一致），仅机制收敛——去路由后 NavDestination.onBackPressed 消失，返回键只达 Index @Entry，分散在三处（Index 自维护链/SettingsPage onBackPressed/LogPage onBackPressed）的返回逻辑必须归一，否则设置层在台按返回穿透到底层默认行为（直接退出应用）。固定链序按层自上而下（队列→播放附属→浮层→日志→设置句柄→设置层），层物理堆叠保证链命中的永远是当前最上层
- **Alternatives considered**: 各层自持返回处理——去路由后无承载点；被否

**D6: 计数移除连带 logCount 机制删除**
- **Decision**: 历史面板标题计数（L1262）、历史入口行计数（L1655-1656）、日志入口行计数（L1666）全删；`logCount` 成员（L108）/初始化（L182）/onShown 刷新（L1763）全删
- **Rationale**: 计数展示是 logCount 机制唯一存在理由，展示删则机制删；原「日志层关闭时 @Monitor 刷新角标」设计（旧 D6）随之消亡，日志层返回后设置页无任何需刷新的计数态
- **Alternatives considered**: 保留机制留后续用——无人要的抽象；被否

**D7: 层滑入时长常量 `PAGE_LAYER_SLIDE_MS = 350`**
- **Decision**: 新增常量，曲线 Curve.Friction
- **Rationale**: AGENTS.md 禁裸数字；取值与手感对齐 PlayerOverlay 现行 350ms/Friction

**D8: 转场方向——自右滑入（translate x 100%）**
- **Decision**: 设置/日志层自右侧滑入，退出自动反演回滑
- **Rationale**: 对齐原 Navigation push 手感（两页原为 push 进栈右滑入），用户可感知方向零变化

**D9: 未登录音质显示——纯展示层改写，不动取流**
- **Decision**: 兜底分支档位「默认」→「64K」、文案改登录引导；入口标签兜底同步；不新增面板内登录跳转
- **Rationale**: 未登录兜底流固定 64K（B 站未登录取流现状，参考项目实测），如实标注即可传达音质信息；登录入口设置页账号栏已有，面板内跳转是多余路径
- **Alternatives considered**: 面板内点文案跳登录页——多一条导航路径，登录回流状态复杂；被否

**D10: 大会员标识——SettingsRow 参数扩展 + 本地 vipStatus 判定 + 色资源令牌**
- **Decision**: SettingsRow 新增可选 `vipBadge` 参数；账号行以 BiliSession vipStatus === 1 判定；徽标色新增 `app.color.vip_badge_bg/vip_badge_text` 资源
- **Rationale**: 账号行已用 SettingsRow，参数扩展是最小 diff；vipStatus 与 loginName 同源同生命周期（BiliService L363-364 解析、随登录信息更新），账号栏既有登录态刷新链同步生效；色值走 `$r('app.color.*')` 符合令牌规范
- **Alternatives considered**: 账号行内联徽标（不复用 SettingsRow）——行结构重复；网络图标识（依赖外链、离线失效）；被否

## Data Model

**瞬态 UI 键变化（AppStorageV2，V2State BoolState 包装）**

| 键 | 处置 | 写方 | 读方 |
|---|---|---|---|
| `AS_SHOW_SETTINGS_PAGE` | 新增 | HomePage 设置入口 / SettingsPage 返回按钮 | Index 条件渲染 / BackHandler 返回链 |
| `AS_SHOW_LOG_PAGE` | 新增 | SettingsPage openLogPage / LogPage 返回按钮 | Index 条件渲染 / BackHandler 返回链 |
| `AS_MINI_PLAYER_VISIBLE` | 删除 | （原 Index Monitor） | （原三页 padding——改静态） |
| `AS_ON_SETTINGS_PAGE` | 删除 | （原 SettingsPage 生命周期三段） | （原 Index Monitor） |

**常量变化**：`NAV_EXIT_TRANSITION_MS` 删、`MINI_VISIBILITY_ANIM_MS` 删、`PAGE_LAYER_SLIDE_MS` 增（350）；`MINI_PLAYER_CLEARANCE` 留。

**色资源变化**：`vip_badge_bg`（品牌粉）、`vip_badge_text`（白）新增于 `resources/base/element/color.json`。

无持久化数据变化、无模型类变化。

## Contracts & Interfaces

**层序契约**：见 spec.md「Layer Model」——L1 导航+胶囊 → L2 设置+日志（日志在设置之上，历史面板留设置页树内）→ L3 播放浮层 → L4 队列；高层物理覆盖低层。

**`registerSettingsBack(handle: (() => boolean) | undefined): void`**（BackHandler 导出，新增）
- SettingsPage aboutToAppear 注册真句柄、aboutToDisappear 注销（传 undefined）
- 句柄返回 true = 已消化一次返回（关闭了音质选择器或历史面板）；false = 内部无面板可关
- 句柄内部次序：`showQualitySheet` → 关闭返 true；`showPlayHistory` → 多选态先退多选返 true → historyClose 句柄（无则直置标志）返 true；否则 false——与原 SettingsPage.onBackPressed 逻辑一致（迁移非重写）
- 链内调用位置：日志层关闭之后、设置层关闭之前

**`dismissOverlaysForBack(): boolean`**（扩展）
- 全链分层序列（见分文件目标 #2）；true = 已消化一次返回，false = 无层可关放行默认行为
- Index onBackPress 唯一调用方

**`registerQueueClose(handle)`**：保留（队列滑出句柄，GlassSheet 注册），注释背景更新为单挂载

**`closeBothLayersNow()`**：语义不变（标志驱动，与挂载位置无关）

**结构导出契约**：`struct SettingsPage`、`struct LogPage` 需 export（Index 直接导入）；`SettingsPageBuilder`/`LogPageBuilder` 删除；`router_map.json` 仅存 `sourcePage`

## Changelog

- **2026-10-13（二）**：历史面板定案回 L2（不与队列同级），撤销 HistorySheet 抽取方案与 `registerHistoryClose`，队列/历史互斥讨论（旧 D7）整体消亡；并入三项批准变更（未登录音质 64K、大会员标识、计数移除），D6 由「logCount @Monitor 刷新」改为「计数移除连带机制删除」，新增 D9/D10；分文件目标恢复原版骨架 + SettingsRow/color.json；零新增文件。
- **2026-10-13（一）**：初版（历史面板 L4 同级方案）。
