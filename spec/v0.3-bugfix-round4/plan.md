# Implementation Plan: v0.3 真机反馈第四轮修复

**Input**: Feature specification from `spec/v0.3-bugfix-round4/spec.md`

## Summary

四个 bug 的定点修复，全部为 UI/交互层，不动数据模型与播放链路：①`closeBothLayersNow` 在浮层打开时改为「队列标志直接复位 + 浮层同帧收起」，消除 Index 层二次挂载 QueueDrawer 的闪现；②设置页 `onHidden` 的在台标志复位改为「定值延时」，使胶囊在退场转场播完后才上浮，配定时器取消机制消解快速往返竞态；③全库 8 文件 13 处 `stateStyles({ pressed })` 按压反馈整体替换为系统级「按压阴影」（`hdsEffect.pressShadow(BLEND_WHITE)` + `.visualEffect()`，UIDesignKit 托管按压态生命周期，机制上不可能卡死）；④三处左滑删除按钮容器补对称左侧内边距实现停留位左右等距。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 26.0.0，不考虑 API<26 兼容）
**Primary Dependencies**: ArkUI（State Management V2）、@kit.UIDesignKit（`hdsEffect`，API 20+，本机 SDK `@hms.hds.hdsBaseComponent.d.ets` 已核实）
**State Management**: 沿用项目现状——页面/组件 V2（`@Local`/`@Param`/`@Monitor`）、`AS_*` 经 `V2State.ets` 走 `AppStorageV2.connect`、PlayerController 零装饰器广播
**Storage**: 无变更（不动 AppStore/preferences/文件持久化）
**Testing**: 无测试套件；静态预检 `arkts_check` + `devecocli build`（验证范围 Phase 3 定，默认 build-only）
**Target Platform**: HarmonyOS NEXT 真机/模拟器（平板与手机形态）
**Project Type**: 单模块 HarmonyOS 应用（BiliRadio）
**Performance Goals**: 按压视效走系统渲染管线，无应用侧状态机开销；其余无新增性能面
**Constraints**: 代码零注释（豁免 `ponytail:` 标注）、数值一律 Constants 令牌、禁 any/unknown/as、V2 组件内禁 V1 装饰器
**Scale/Scope**: 改动 10 个源文件 + 1 个颜色资源清理，无新文件目录结构变化

## Project Structure

### Documentation (this feature)

```text
spec/v0.3-bugfix-round4/
├── spec.md              # 已批准（Phase 1）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── BackHandler.ets          # US1：closeBothLayersNow 分支重写
│   └── Constants.ets            # US2：新增退场转场定值常量
├── component/
│   ├── PressShadow.ets          # US3：新建——按压阴影视效构建助手（唯一新文件）
│   ├── SettingsRow.ets          # US3：stateStyles → visualEffect
│   └── QueueSheet.ets           # US3：行按压替换；US4：左滑删除按钮容器补左内边距
├── pages/
│   ├── SettingsPage.ets         # US2：onHidden 延时复位 + 竞态消解；US3/US4：历史行按压替换 + 左滑按钮补边距
│   ├── HomePage.ets             # US3：订阅行按压替换；US4：左滑按钮补边距
│   ├── SourcePage.ets           # US3：剧集行按压替换
│   ├── LogPage.ets              # US3：日志行按压替换
│   └── AddSubscriptionSheet.ets # US3：4 处搜索结果行按压替换
└── resources/base+dark/element/color.json  # US3：item_pressed_background 资源移除（替换后成孤儿）
```

**Structure Decision**: 遵循既有项目架构（pages/service/model/component 分层、依赖单向契约不变），不引入 MVVM 迁移。唯一新文件 `component/PressShadow.ets` 为跨 8 文件复用的视效构建助手（13 处调用点收敛一处定义），归属 component/（UI 助手，无业务依赖）。

## Complexity Tracking

无宪法级违规。新增 1 个文件（PressShadow.ets）的合理性：13 处调用点若各自内联构建需 8 份重复 import + 24 行重复构建代码，助手收敛为「1 处定义 + 每调用点 1 行」。

## Research & Decisions

### D1 - US1 清空队列闪现：浮层内实例「标志直复位」方案

- **Decision**: `closeBothLayersNow()` 增加浮层态分支——`AS_SHOW_PLAYER_OVERLAY` 为 true 时（队列抽屉渲染于 PlayerOverlay 内）：**不调用**注册的滑出句柄、不起延时器，`AS_SHOW_QUEUE_SHEET` 与 `AS_SHOW_PLAYER_OVERLAY` 同帧直接置 false；浮层以既有 350ms 下滑转场退出（转场画面为播放页内容，即 R3 已批准的「退场画面保持最后一首歌」语义）。浮层为 false 时（首页层实例）：保持现状滑出句柄路径（含无句柄回退置 flag）。
- **Rationale**: 闪现根因是三条链路竞态：①浮层卸载清掉队列实例的 260ms 延时器 → `AS_SHOW_QUEUE_SHEET` 残留 true；②Index 渲染条件 `showQueueSheet && !showPlayerOverlay` 在浮层标志翻转后瞬时满足 → 底部二次挂载新 QueueDrawer 滑入（「突然出现一下」）；③后续路径置 flag false 时该实例无滑出动画直接卸载（「无动画消失」）。同帧直复位从源头消灭条件满足窗口，且浮层退出转场完整保留。清空确认后 400ms 延时清数据编排（`clearAllWithExitDelay`）不动。
- **Alternatives considered**: ①队列随浮层整体滑出（保留挂载至浮层卸载再复位标志）——需新增「浮层退场中」守卫标志阻断 Index 条件，复杂度高且引入新全局键；②错峰关闭（先队列滑出 260ms 再收浮层）——违背 R3「两层同帧无错峰」已批准编排。

### D2 - US2 胶囊时序：`onHidden` 定值延时复位

- **Decision**: SettingsPage 的 `AS_ON_SETTINGS_PAGE` 复位从 `onHidden` 同步执行改为**定值延时**（新常量 `Constants.NAV_EXIT_TRANSITION_MS = 400`， ponytail 注释标注天花板：系统导航退场转场无公开完成回调，定值略长于默认转场时长，胶囊上浮始于转场结束后）。配三处竞态消解：①`onWillAppear`/`onShown` 置位 true 时**先取消**未触发的复位定时器（快速往返设置页、从日志页返回设置页两条路径）；②`onShown` 补置位 true（修复从日志页 pop 回设置页后标志仍为 false、胶囊残留显示的既有缺口）；③组件销毁路径（`onWillDisappear`）清理定时器防泄漏。进入设置页的即时隐藏（onWillAppear 置位）保持不变；Index 侧 `onMiniVisibilityChanged` 动画逻辑零改动（标志变化时机后移即达成时序后移）。
- **Rationale**: R3 依赖「`onHidden` 在退场转场播完后触发」的假设在真机不成立（实际在退场开始即触发），修复无效。定值延时是项目内已验证的模式（QueueDrawer 滑出 260ms、清空队列 400ms 同款），改动面最小。`onShown` 补置位顺带修复日志页返回路径的既有缺口，属同一标志生命周期的完整化，非新需求。
- **Alternatives considered**: ①`navPathStack.setInterception` 拦截 pop 时机——拦截的是 pop 调用非转场结束，仍需定值；②Navigation 自定义转场回调（`customNavContentTransition`）——为全局导航行为引入自定义转场，影响面远超本 bug。

### D3 - US3 按压反馈：全量替换为系统「按压阴影」

- **Decision**: 新建 `component/PressShadow.ets` 导出无参构建函数（返回 `VisualEffect`：`hdsEffect.HdsEffectBuilder` 链 `pressShadow(PressShadowType.BLEND_WHITE)` 后 `buildEffect()`，每次调用新建实例避免跨组件共享不确定），内部 `import { hdsEffect } from '@kit.UIDesignKit'`。全库 13 处 `stateStyles({ pressed: pressedStyle })` 调用点替换为 `.visualEffect(pressShadowEffect())`，删除各文件 `pressedStyle` @Styles 定义；`item_pressed_background` 颜色资源（base+dark）随之成为孤儿，一并移除。
- **Rationale**: 现行 `stateStyles pressed` 为应用侧多态样式，真机设置页全体行点击即卡死（用户确认为设计级缺陷），且平台已知怪癖多（Grid 内延迟 FAQ 947、状态冒泡 FAQ 960）。系统「按压阴影」由渲染管线托管按压态生命周期（按下出现/松手消失/滚动取消），不经应用侧状态回调，机制上不存在卡死路径；`hdsEffect` 自 API 20 可用，本机 SDK `.d.ts` 已核实类型与 kit 导出，系统设置等系统应用即此效果。替换范围扩至全部 13 处（超出 spec 点名的设置页/首页/队列/历史，另含 AddSubscriptionSheet 4 处、SourcePage、LogPage）：同为按压反馈模式的机制统一，避免半数行系统视效、半数行坏 stateStyles 的割裂，与 spec「同款模式同步换用」精神一致。
- **Alternatives considered**: ①`attributeModifier` 自管触摸态状态机——仍为应用侧状态，等于换一种方式重写坏机制；②`HdsListItem` 整行换系统列表组件——改动行结构，影响远超按压反馈本身；③仅修设置页 3 处入口——治标不治本，其余 10 处同样会卡。

### D4 - US4 左滑删除按钮等距：容器补对称左内边距

- **Decision**: 三处左滑删除按钮容器（HomePage `subDeleteAction`、SettingsPage `historyDeleteAction`、QueueSheet `queueDeleteAction`）的 Column 内边距从 `{ right: TOKEN_SPACE_M }` 改为 `{ left: TOKEN_SPACE_M, right: TOKEN_SPACE_M }`，按钮居中于停留位，左右各 TOKEN_SPACE_M（16vp）等距；停留位总宽相应从 60vp 变为 76vp。触发交互（图标点击 + `onAction` 阈值 + 二次确认）零改动。
- **Rationale**: 现状容器仅右侧内边距，按钮左侧 0 间距贴行内容、右侧 16vp 距行缘，停留位不对称（首页圆角卡片下最显眼）。补对称左侧即达成「左右等距」，间距值复用既有令牌，无新常量。
- **Alternatives considered**: 按钮贴右对齐（用户未选）；抽取三处重复 builder 为共享组件——超出 bug 修复范围，三处各 1 行改动为最短 diff。

## Data Model

无新增/变更数据实体。涉及的全局状态键语义不变，仅写入时机变化：

- `AS_SHOW_QUEUE_SHEET`：清空场景（浮层内实例）由「260ms 延时复位」改为「同帧直复位」
- `AS_ON_SETTINGS_PAGE`：复位时机由 `onHidden` 同步改为延时 400ms；新增 `onShown` 置位路径
- `AS_SHOW_PLAYER_OVERLAY` / `AS_MINI_PLAYER_VISIBLE` / `AS_PLAYLIST_SELECT_MODE`：语义与写入路径不变

新增常量（Constants.ets，唯一真相源）：`NAV_EXIT_TRANSITION_MS = 400`（系统导航退场转场定值延时）。

移除资源：`item_pressed_background`（base/dark 两份 color.json，13 处替换后零引用；实施时先全库 grep 复核再删）。

## Contracts & Interfaces

### 内部契约变更

- **`BackHandler.closeBothLayersNow()`**（签名不变，行为契约变更）：
  - 浮层打开（`AS_SHOW_PLAYER_OVERLAY === true`）：两标志同帧直复位 false；不再调用 `registerQueueClose` 句柄；调用方（QueueSheet.clearQueue）无需感知实例宿主
  - 浮层关闭：现状保持——队列经注册句柄滑出（无句柄回退置 flag）
- **`component/PressShadow.ets`**（新导出）：`pressShadowEffect(): VisualEffect`——无参、每次调用新建效果实例、无状态无副作用；仅依赖 `@kit.UIDesignKit`，被 8 文件 13 调用点消费
- **SettingsPage 生命周期定时器契约**：复位定时器句柄为组件私有成员；`onWillAppear`/`onShown` 置位前必须先取消 pending 定时器；`onWillDisappear` 清理句柄

### 不变量（实施与验证对照）

- 清空队列「停声先行 + 400ms 延时清数据」编排（`clearAllWithExitDelay`）不变
- 三处左滑删除的二次确认链路与 `closeAllSwipeActions` 复位行为不变
- 首页层队列实例清空（无浮层）行为不回归
- 进入设置页胶囊即时隐藏、播放浮层展开胶囊隐藏两条既有路径不回归
- `hdsEffect` 属 HMS UIDesignKit（`SystemCapability.UIDesign.HDSComponent.Core`）：真机/系统应用同源能力可用；模拟器表现以构建+部署实测为准，不可用时按无人值守规则②上报

---

## R4 迭代修订（真机验收后，[turn_1ptr50] + [turn_1a6tx2]）

### D2 修订（US2）— 复位点从 onHidden 改 onWillDisappear

- **Decision**: `AS_ON_SETTINGS_PAGE` 复位定时器改由 **`onWillDisappear`** 排定（该回调在 pop 退场与被新页覆盖两路径必触发）；删除原 `onWillDisappear` 的取消逻辑与 `onHidden` 的排定逻辑；`onWillAppear`/`onShown` 置位 true 前取消 pending 的竞态消解与 `onShown` 补置位保留。`NAV_EXIT_TRANSITION_MS = 400` 常量沿用。
- **Rationale**: 真机回归根因——`onHidden` 排定定时器后被 `onWillDisappear` 取消，标志卡 true，胶囊永不出现。`onWillDisappear` 语义（页面即将消失/被覆盖）与复位意图（退场转场后胶囊上浮）匹配，且 pop 与推日志页两路径统一，不再依赖 onHidden 的触发时机。
- **Alternatives considered**: 仅移除 `onWillDisappear` 取消、保留 onHidden 排定——若 onHidden 在 pop 时不触发则仍卡死，不可靠；双回调都排定——冗余，cancel-before-set 虽能兜底但语义混乱。

### D3 修订（US3）— hdsEffect 作废，改手动触摸态背景加深

- **Decision**: ①删除 `component/PressShadow.ets` 与全部 10 处 `.visualEffect(pressShadowEffect())` 调用及对应 import；②恢复 `item_pressed_background`（base `#12000000` / dark `#14FFFFFF`）；③改手动触摸态驱动：组件行（SettingsRow）自持 `@Local isPressed: boolean` + 行容器 `onTouch`（Down 置 true，Up/Cancel 置 false）+ 条件 `backgroundColor(isPressed ? item_pressed_background : 原背景)`；builder 行（各列表）父组件持 `@Local pressedKey: string`（复用各 LazyForEach 行键，AddSubscriptionSheet 多列表用 `列表标签_行键` 复合键防跨列表误中），行 `onTouch` 置/清键 + 条件 backgroundColor 覆盖行原背景色。
- **Rationale**: 两套系统机制均不可用——stateStyles pressed 真机卡死（R3）、hdsEffect 白色混合浅色/深色均不可见（R4 实测，非模式问题）。手动触摸态由应用侧明确控制 Down/Up/Cancel 三终态，平台触摸事件可靠送达，机制上无卡死路径；按压色复用既有资源值，视觉与 R3 目标一致（可见的背景加深）。
- **Alternatives considered**: 继续找阴影形态系统效果——hdsEffect 白色混合原理决定浅色主题无解，其余阴影方案需自绘、复杂度高；attributeModifier——仍需自管触摸态，等价但样板更多；stateStyles 再尝试——已两轮实测失败。

### D4 状态（US4）— 等距保持，阴影撤销

- 等距修复真机验收通过，保持现状；「加阴影」需求用户撤销（[turn_1a6tx2]），无代码改动。

### D5 修订（US5 新增，[turn_1vf34w]）— 播放键切换光晕淡入缩短

- **Decision**: `PlayerOverlay.ets` 模块级常量 `GLOW_FADE_IN_MS` 由 3200 → **500**（ms）。播放/暂停切换时图标即时切换，封面光晕淡入从 3.2s 缩短至 0.5s，与封面亮度（400ms）/缩放（350ms）动画同量级，切换反馈干脆。其余光晕参数（GLOW_IDLE/GLOW_ACTIVE）与暂停侧 800ms 淡出不改。
- **Rationale**: 用户实测「切换播放暂停动画变长」——R3 把光晕从无限呼吸收敛为一次性过渡后淡入时长沿用 3200ms，点播后光晕需 3.2s 才到峰值，感知为切换动画拖长；v0.4.0 取色轮放大光晕后更显眼。500ms 与封面动画同量级、观感干脆。
- **Alternatives considered**: 恢复呼吸动画——与 R3「一次性过渡」已批准设计冲突；缩短至 300ms 以下——光晕淡入过快失去过渡质感。
- **注意**: `PlayerOverlay.ets` 含 v0.4.0 在途未提交改动（取色/光晕放大/顶栏骨架），本项只改该常量值一处，不触碰其他代码。

### 契约变更对照

- **移除**：`component/PressShadow.ets` 导出契约（`pressShadowEffect(): VisualEffect`）
- **新增**：SettingsRow `@Local isPressed` 触摸态契约；各列表父组件 `@Local pressedKey` 触摸态契约（含多列表复合键规则）
- **资源**：`item_pressed_background` 由「移除」改为「恢复」（base `#12000000` / dark `#14FFFFFF`）
- **SettingsPage 生命周期定时器契约**（修订）：`onWillDisappear` 排定复位定时器；`onWillAppear`/`onShown` 置位前取消 pending；无其他回调取消
