# Implementation Plan: v0.3-bugfix-round3（播放意图先行重写 + 八项真机反馈修复）

**Input**: Feature specification from `spec/v0.3-bugfix-round3/spec.md`（2026-10-12 修订版：US5 光晕截断移出范围，播放页重设计另开轮次）

## Summary

八项 R3 反馈：核心是播放/暂停按钮状态机「意图先行」重写——引入统一意图字段 `playIntent`（由现有 `playWhenReady` 泛化公开），播放页按钮/MiniPlayer/光晕与封面明暗全部改读意图（点击瞬间切图标），AVPlayer 事件仅做校准（出错/打断/停止复位意图），删除 300ms 去抖基建；订阅删除健壮化（id 匹配 + 数据源删除通知 + 保存后校验）；清空队列改「先关层后清数据」编排；胶囊退场时序改 `onHidden`；圆形左滑删除钮、8 个删除弹窗执行钮改红、全列表行按压反馈、三处音符占位换耳机。US5（光晕截断）已移出，PlayerOverlay 骨架不动。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0，禁 API<26 兼容设计）
**Primary Dependencies**: ArkUI 声明式范式、`@ohos.net.http`、AVPlayer（经 `service/AudioPlayer` 封装）
**State Management**: 维持现状——页面/挂键组件 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；CoverThumb 保持 V1 `@Component`（`@Prop`-only）；`PlayerController` 零装饰器纯类（手动 `subscribe`/`emitUi` 广播 + 消费方 `syncFrom` 拷贝进 `@Local`）
**Storage**: AppStore（preferences，`KEY_*`）、subscriptions.json/sub_cache_*.json（SubscriptionStore 文件持久化）
**Testing**: 无测试套件；验证走 `arkts_check` + `devecocli build` + 模拟器部署冒烟（build-only）
**Target Platform**: HarmonyOS NEXT 手机
**Constraints**: Constants.ets 唯一真相源；禁 `any`/`unknown`/`as` 类型断言；代码零注释（`ponytail:` 除外）；V2 文件内新代码必须 V2 装饰器
**Scale/Scope**: 修改 14 个源文件 + 双份 color.json；新增 0 个文件（BackHandler 已存在，本轮加函数）；PlayerOverlay 只动 US1/US4 相关，骨架不动（US5 已移出）

## Project Structure

### Documentation (this feature)

```text
spec/v0.3-bugfix-round3/
├── spec.md               # 本轮需求（修订版：US1-US4、US6-US9 在范围，US5 移出）
├── plan.md               # 本文件
└── tasks.md              # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── PlayerController.ets    # US1 意图先行重写核心；US4 clearAllWithExitDelay
│   ├── BackHandler.ets         # US4 closeBothLayersNow
│   ├── Constants.ets           # 新常量 CLEAR_QUEUE_DATA_DELAY_MS；删 PLAY_STATE_DEBOUNCE_MS；圆钮尺寸/图标字号
│   └── SubscriptionStore.ets   # US2 保存后校验辅助（subExists 已有，复用）
├── pages/
│   ├── PlayerOverlay.ets       # US1 按钮/光晕强度/明暗改意图；US4 空态分支删除；骨架不动
│   ├── HomePage.ets            # US2 订阅删除健壮化；US6 圆钮；US7 红钮；US8 行按压；US9 空态耳机
│   ├── SettingsPage.ets        # US3 onHidden 时序；US6 圆钮；US7 红钮；US8 历史行按压
│   ├── SourcePage.ets          # US7 取消订阅红钮；US8 剧集行按压
│   ├── LogPage.ets             # US8 日志行按压
│   └── AddSubscriptionSheet.ets # US8 三列表行按压（搜索结果/收藏夹/合集系列）
├── component/
│   ├── MiniPlayer.ets          # US1 图标改意图；US4 空态点按禁用
│   ├── QueueSheet.ets          # US4 清空编排改；US6 圆钮；US7 红钮；US8 队列行按压
│   ├── CoverThumb.ets          # US9 ♪→耳机
│   └── SettingsRow.ets         # US8 设置行按压（组件级一处）
entry/src/main/resources/
├── base/element/color.json     # US8 item_pressed_background（浅色）
└── dark/element/color.json     # US8 item_pressed_background（深色）
```

**Structure Decision**: 沿用现有项目架构（单模块、pages/service/component/model 分层、零装饰器广播播控）。不引入新文件、不做 MVVM 迁移；本轮全部为存量文件内修改与两个函数级新增。播放页重设计（含光晕截断修复）为独立后续轮次，本轮不触碰 PlayerOverlay 布局骨架。

## Complexity Tracking

无宪法级违规。US5 移出后本轮无结构性骨架改动，全部为存量结构内修改。

## Research & Decisions

### D1 — US1 意图先行：统一意图字段 `playIntent`

**Decision**: 将现有 `playWhenReady`（准备期自动播意图，私有）泛化为公开广播字段 `playIntent`（默认 `false`），作为播放控制图标与播放页视觉的第一显示来源：
- **UI 派生**（播放页大按钮 / MiniPlayer）：`isPreparing && playIntent` → 加载动画；`playIntent` → 暂停键；`!playIntent` → 播放键。播放页光晕强度（updateGlow/glowStrength）、封面 brightness/scale 改由 `playIntent` 驱动（只改数据来源，不动布局骨架）
- **意图维护**：`togglePlay`（准备期内外统一翻转）、`playRequest`（置 true）、`pauseRequest`（置 false）、`playIndex`（置 true）即时翻转并 `emitUi`
- **校准复位**（事件侧）：`onError`、`idle/stopped`、`completed` 停止分支（handleCompleted 的「播完暂停/播放结束」路径）、音频 `INTERRUPT` 打断——显式置 `false`；`END_INTERRUPT` 续播经 `playRequest` 置回 `true`；REPEAT_ONE/自动切歌经 `playIndex` 保持 `true`
- **删除去抖基建**：`schedulePlaying`/`playStateTimerId`/`cancelPlayStateDebounce`/`Constants.PLAY_STATE_DEBOUNCE_MS` 全部删除；`setPlaying` 简化为双字段直写（`playingNow`/`isPlaying` 同步即时）；`isPlaying` 保留为即时实际态（内部逻辑与状态行使用），不再有 300ms 窗口
- **锁屏/控制中心（MediaSession）**：保持实际态（`playingNow`）不变——锁屏显示真实状态是平台惯例，不受意图先行影响

**Rationale**: UI 跟随去抖落定值是「慢一拍+竞态卡死」的根因；意图先行是媒体播放器标准做法（图标表达用户意愿，事件校准边界态）。去抖窗口在意图模型下失去存在意义（UI 不再消费事件翻转），删除后竞态源整体消失。

**Alternatives considered**: ①只修卡死保留事件驱动（用户已否决，治标）；②UI 层本地乐观翻转+事件回滚（每处 UI 重复实现回滚逻辑，MiniPlayer/播放页两份，易再出不一致）——统一到控制器单一意图字段最短且两处消费自动一致。

### D2 — US2 订阅删除健壮化（含根因结论）

**Decision**: 静态审查结论：数据层无复活路径（`persistRefreshedSub` 的 alive 过滤经 `subExists` 读盘校验，删除后不写回；`refreshAll` 每源迭代前 `subExists` 守卫跳过已删源）。嫌疑集中在 UI 层两处坏味道，做健壮化重写：
1. **id 匹配替代引用匹配**：`removeSub` 按 `sub.id` 在 `this.subs` 中定位（替代 `indexOf(row.sub)` 引用身份匹配，消除闭包陈旧引用导致 `idx<0` 静默早退——「点了没反应」的最可能根因）
2. **数据源删除通知**：`SubDataSource` 新增 `delete(index)`（`onDataDelete(index)` 通知），`removeSub` 改为 `animateTo` 闭包内 `provider.delete + subs.splice + saveSubscriptions + removeEpisodes`，**闭包内不再调 `rebuild()`**（现状「splice 后全量 reload」自相矛盾：既无补位又重排数组）
3. **保存后校验**：`saveSubscriptions` 后调 `SubscriptionStore.subExists(id)`，仍存在则 `hilog.error`（真机复现时日志直指持久化环节）

**Rationale**: 三个候选薄弱点（引用匹配/闭包内 rebuild/持久化）一并加固，任一为真根因都被覆盖；校验日志兜底设备特异性场景。

**Alternatives considered**: 仅加日志等真机复现再修（拖一轮，用户已明确要修）；全量重写订阅管理（过度工程）。

### D3 — US3 胶囊退场时序：复位移至 `onHidden`

**Decision**: `SettingsPage` 中 `AS_ON_SETTINGS_PAGE` 的复位从 `onWillDisappear`（退场转场开始）移至 `onHidden`（页面真正隐藏，转场播完；本机 SDK `nav_destination.d.ts` L703 确认存在，`Callback<VisibilityChangeReason>`）。置位（`onWillAppear`）不动；推入 LogPage 时 `onHidden` 触发使胶囊在 LogPage 显示（现状行为，仅延后到转场后）。

**Rationale**: `onWillDisappear` 在退场开始即复位，胶囊 250ms 上浮动画压在还在退场的设置页上；`onHidden` 在转场结束后触发，胶囊出现在已回到台前的首页上。项目已有先例（SourcePage `onHidden` 同语义）。

**Alternatives considered**: Index 侧延时显示（在正确层修错误层的时序，且要魔法延时）。

### D4 — US4 清空队列：先关层后清数据 + 空态移除

**Decision**（用户已拍板路线）:
1. **`BackHandler.closeBothLayersNow()`**（新函数）：队列走注册句柄滑出 + `AS_SHOW_PLAYER_OVERLAY` 立即置 false（两层同时退出，去掉 260ms 错峰；`closeQueueAndOverlay` 保留给其他调用方——无其他调用方则直接改造本函数）
2. **`PlayerController.clearAllWithExitDelay()`**（新方法）：立即停声（`player.pause()`，准备期同时 `playIntent=false`）；`setTimeout(CLEAR_QUEUE_DATA_DELAY_MS=400)`（> 浮层 350ms translate 转场，见 Index L195-196）后执行清数据：`removeSelectedFromPlaylist(全部 bvid)` 复用现有清空/停播/持久化链路
3. **QueueSheet.clearQueue 确认动作**改为：`closeBothLayersNow()` + `controller.clearAllWithExitDelay()`（数据变更时序整体后移，退出全程画面保持最后一首歌，不闪空态）
4. **MiniPlayer 空态**：移除空态占位条的 `onClick`（点按无动作）
5. **PlayerOverlay 空态分支删除**：`if (this.trackIndex < 0 || this.playlistCount === 0)` 的「暂无播放内容」引导块整体移除（空态胶囊限制后不可达；万一意外打开，else 分支自然渲染耳机占位与空文案，不会白屏）

**Rationale**: 空态闪现根因是清数据先于关层（round2 顺序）；先关层后清数据让退出动画全程渲染最后一首歌。400ms 延时大于浮层 350ms 转场保证清数据时浮层已卸载。

**Alternatives considered**: ①同步关两层+删空态但不延时数据（清数据瞬间浮层还在转场中会重渲染空态，仍闪）——必须配合延时；②保留 260ms 错峰（拖长退出节奏，用户要干脆）。

### D5 — US5 封面光晕截断修复（已移出本轮）

**范围变更**（2026-10-12 Phase 2 评审用户拍板）：光晕被顶栏截断的修复随 US5 整体移出 R3——用户计划对播放页做整体重新设计，骨架重构方案已评审（光晕移出 Scroll 垫底 + 背景搬家 + onDidScroll 滚动跟随）但不在本轮实施，留给重设计轮次一并解决。本轮 PlayerOverlay 骨架零改动。

### D6 — US6 左滑删除改圆形小按钮

**Decision**: 三处左滑删除 builder（`SettingsPage.historyDeleteAction`、`QueueSheet` 队列条目删除、`HomePage.subDeleteAction`）视觉从整块红色背景改为：44vp 圆形按钮（`borderRadius` 22、`danger_red` 底、垂直居中于行高、右侧留 `TOKEN_SPACE_M` 内边距），垃圾桶图标 `sys.symbol.trash` 白色、`fontWeight(FontWeight.Bold)` 加粗（本机 SDK `symbolglyph.d.ts` L695 确认 `fontWeight` 属性存在；round2 已验证 trash 符号存在）。图标字号与圆钮尺寸入 Constants。触发结构（builder 点击 + `onAction` 滑过阈值 + 确认弹窗）不变。

**Rationale**: 用户明确要小圆钮与加粗图标；触发交互 round2 已验收不动。

**Alternatives considered**: 方形小钮/胶囊（用户说「圆形小按钮」）。

### D7 — US7 删除类确认弹窗执行钮改红

**Decision**: 8 个删除/清空类弹窗的执行钮（`primaryButton.fontColor = $r('app.color.danger_red')`，本机 SDK `alert_dialog.d.ts` L246 确认 `ButtonOptions.fontColor` 存在）：
1. HomePage 删除订阅；2. SourcePage 取消订阅；3. SettingsPage 删除单条历史；4. SettingsPage 清空播放历史；5. QueueSheet 移除所选；6. QueueSheet 删除队列条目；7. QueueSheet 清除已播；8. QueueSheet 清空队列。
4 个非删除弹窗不动：Index 非 Wi-Fi 网络确认、Index 定时关闭、SettingsPage 退出调试模式、退出登录。取消钮保持默认色。

**Rationale**: 破坏性操作用危险色是平台语义惯例；退出登录/调试不是删除。

**Alternatives considered**: 全部弹窗执行钮改红（非破坏弹窗红色误导）。

### D8 — US8 全列表行按压反馈

**Decision**: 用 `stateStyles` 多态样式（`.stateStyles({ pressed: this.pressedStyle })` + `@Styles pressedStyle` 设 `backgroundColor($r('app.color.item_pressed_background'))`）为以下列表行加按压背景加深、松手恢复：
HomePage 订阅行、SettingsPage 历史行、QueueSheet 队列行、SourcePage 剧集行、AddSubscriptionSheet 三个列表（搜索结果/收藏夹/合集系列）、LogPage 日志行、SettingsRow（设置菜单行，组件级一处覆盖全部设置组）。
新色 `item_pressed_background`：浅色 `#12000000`（7% 黑，白卡上压出浅灰）、深色 `#14FFFFFF`（8% 白）——半透明叠加，适配各列表不同底色。`@Styles`/`stateStyles` 为通用语法，V1/V2 struct 均可用；backgroundColor 属通用属性满足多态样式限制（官方文档确认）。

**Rationale**: 背景加深与系统列表行为一致、半透明单色适配全部列表底色；`stateStyles` 是平台多态样式标准路径，零状态变量、零手动 touch 处理。

**Alternatives considered**: ①onTouch + `@Local` pressed 翻转（每行一个状态变量，样板代码 ×N）；②按压缩放（用户未选）。

### D9 — US9 音符占位统一换耳机

**Decision**: `CoverThumb.ets` 无封面分支 `Text('♪')` → `SymbolGlyph($r('sys.symbol.headphones'))`（字号按 thumbSize 比例，色 `text_secondary`；MiniPlayer 空态与队列/历史无封面行经组件一处生效）；`HomePage.emptyView` 的 `Text('♪')` 42px → 同款 `SymbolGlyph` 耳机（色 `placeholder_color`）。播放页大封面占位 round2 已是耳机不动；CoverThumb/首页其余注释同步修正。

**Rationale**: 用户指定三处全部换耳机，组件级改动一处覆盖两处消费点。

**Alternatives considered**: 无（用户明确范围）。

### D10 — 常量与色值登记

**Decision**: Constants 新增：`CLEAR_QUEUE_DATA_DELAY_MS = 400`、圆钮尺寸/垃圾桶图标字号常量；Constants 删除：`PLAY_STATE_DEBOUNCE_MS`；color.json（base+dark）新增 `item_pressed_background`（浅 `#12000000` / 深 `#14FFFFFF`）。

**Rationale**: Constants 唯一真相源；去抖常量随基建删除，防僵尸常量。

### D11 — US2 关联：SourcePage 取消订阅入口不动

**Decision**: SourcePage 的取消订阅弹窗只改执行钮红色（D7），其删除逻辑本轮不动（用户仅报首页入口无效；两入口数据路径不同，SourcePage 走 `SubscriptionStore` 直接读写）。

**Rationale**: 最小改动边界；若真机复现 SourcePage 入口也有问题，另开轮次。

## Data Model

**PlayerController 字段变更**（零装饰器广播模式不变）：
- 新增公开字段 `playIntent: boolean = false`（意图第一来源，`emitUi` 广播；消费方 `syncFrom` 拷贝）
- `isPlaying` 语义收窄为「即时实际播放态」（去抖删除后与 `playingNow` 同步直写）
- 删除：`playStateTimerId`、`schedulePlaying()`、`cancelPlayStateDebounce()`
- `playWhenReady` 更名/并入 `playIntent`（保留 prepared 分支与恢复路径语义，L994/L1056 的 `wasPlaying` 赋值目标改为 `playIntent`）
- 新增方法 `clearAllWithExitDelay(): void`（停声立即 + 延时清数据）

**SubDataSource**（HomePage 内）：
- 新增 `delete(index: number): void`（rows.splice + `onDataDelete(index)` 通知）

**BackHandler**：
- 新增 `closeBothLayersNow(): void`（队列句柄滑出 + 浮层立即收起）

**无持久化实体变更**；播放意图不落盘（冷启动意图恒 false，自动续播经 `playIndex` 重新置 true）。

## Contracts & Interfaces

**UI 派生契约（播放控制图标，播放页与 MiniPlayer 同规则）**：

| 条件（按序判定） | 显示 |
|---|---|
| `isPreparing && playIntent` | 加载动画（播放页 LoadingProgress / MiniPlayer 暂停键） |
| `playIntent` | 暂停键 |
| 其余 | 播放键 |

**播放页视觉随意图**：光晕 `glowStrength`、封面 `brightness/scale` 以 `playIntent` 翻转为动画触发（替代原 `isPlaying` 边沿检测）；布局骨架不动（US5 已移出，光晕仍留在封面 Stack 内，截断问题留给重设计轮）。

**意图校准清单（事件侧复位 `playIntent=false`）**：`onError`、`onPlayerState('idle'/'stopped')`、`handleCompleted` 停止分支（播完暂停/播放结束/顺序到端）、`onAudioInterrupt('INTERRUPT')`；`END_INTERRUPT` 续播经 `playRequest` 置回。

**`clearAllWithExitDelay()` 行为契约**：调用即停声（`player.pause()` + 准备期 `playIntent=false`）；`CLEAR_QUEUE_DATA_DELAY_MS` 后经 `removeSelectedFromPlaylist(全量 bvid)` 清数据并持久化；期间播放页/MiniPlayer 画面保持最后一首歌。

**`SubDataSource.delete(index)`**：越界静默返回；通知后 `totalCount`/`getData` 反映删除结果。

**`BackHandler.closeBothLayersNow()`**：队列面板经注册句柄滑出（无句柄回退置 flag）；`AS_SHOW_PLAYER_OVERLAY` 无条件立即置 false。

**按压反馈契约**：按压时行背景为 `item_pressed_background`，松手恢复原背景；不改变任何行的点击/左滑/长按行为。

**验收对照**：spec FR-001~FR-012（除 FR-008）与 SC-001~SC-006（除 SC-005）逐条可溯至 D1-D4、D6-D11。
