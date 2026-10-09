# Tasks: UX 反馈第 8 轮（R8）

**Input**: Design documents from `spec/ux-feedback-round8/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: 无测试套件，不生成测试任务。验证 = arkts_check + devecocli build + 部署（build-only 范围，无 UI 验证）。

**Organization**: 任务按用户故事分组，支持独立实现与独立验证。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1-US7）
- 描述含精确文件路径

## Path Conventions

- 单模块项目：源码在 `entry/src/main/ets/`（pages/component/service/model）
- 色板：`entry/src/main/resources/base/element/color.json`

---

## Phase 1: Setup

**Purpose**: 改动点基线核对

- [X] T001 通读 spec/plan 与 6 个目标源文件（Logger/Constants/SettingsPage/HomePage/SourcePage/SubscriptionStore），按 plan.md D1-D8 确认各改动点行号与现状（三连击挂点=关于面板图标、死 onPop 两处、refreshSource 回调、列表过冲链）

---

## Phase 2: Foundational

**Purpose**: 常量键（阻塞 US1-US3）

- [X] T002 [P] 新增 `KEY_DEBUG_MODE`（'debugMode'）与 `DEBUG_TAP_WINDOW_MS`（2000）`entry/src/main/ets/service/Constants.ets`

**Checkpoint**: 常量就绪，US1-US3 可开始

---

## Phase 3: User Story 1 - 三连击开启 Debug 模式 (Priority: P1)

**Goal**: 关于面板图标 2 秒窗三连击 → debug 模式开启 + toast + 持久化

**Independent Test**: 虚拟机设置页→关于→图标快速三连击→toast「已开启调试模式」；重启应用后开关仍开启

- [X] T003 [US1] Logger 新增 `static debugEnabled` + `static setDebugMode(on)`；`init(context)` 内 getPreferencesSync 读 `KEY_DEBUG_MODE` 恢复标志（Appearance.init 同款模式）`entry/src/main/ets/service/Logger.ets`
- [X] T004 [US1] 关于面板图标 `Image($r('app.media.startIcon'))` 挂 onClick，实现 `tapCount`/`lastTapTs` 2 秒窗计数（超窗重置）`entry/src/main/ets/pages/SettingsPage.ets`
- [X] T005 [US1] 三连击触发：`Logger.setDebugMode(true)` + `AppStore.putNumber(KEY_DEBUG_MODE, 1)` + toast「已开启调试模式」+ 计数清零；已开启时三连击仅 toast 提示不重复弹 `entry/src/main/ets/pages/SettingsPage.ets`

---

## Phase 4: User Story 2 - 调试开关与二次确认 (Priority: P1)

**Goal**: 开启后关于面板展示「调试模式」开关；关闭需二次确认

**Independent Test**: 开启 debug 后关于面板出现开关行；点开关→AlertDialog→确认→toast「已退出调试模式」；取消→保持开启

- [X] T006 [US2] 关于面板图标下方条件渲染 `SettingsRow`（title「调试模式」、showToggle、toggleOn=debugEnabled），仅 debug 开启时展示 `entry/src/main/ets/pages/SettingsPage.ets`
- [X] T007 [US2] Toggle 关闭时弹 `AlertDialog.show` 二次确认；确认→`Logger.setDebugMode(false)` + `putNumber(KEY_DEBUG_MODE, 0)` + toast「已退出调试模式」；取消→状态不变 `entry/src/main/ets/pages/SettingsPage.ets`

---

## Phase 5: User Story 3 - Logger 双写 hilog 门控 (Priority: P1)

**Goal**: debug 开启期间每条日志同步写 hilog；默认仅落盘+内存

**Independent Test**: 构建级验证（build-only）：代码核查 log() 末尾 debugEnabled 分支；UI 验证留后续轮次

- [X] T008 [US3] `log()` 末尾追加 `if (Logger.debugEnabled) hilog.debug(LOG_DOMAIN, LOG_TAG, '%{public}s', buildFileLine 产物)`，try/catch 静默；`warnFileFailOnce` 的 hilog.warn 保持无条件 `entry/src/main/ets/service/Logger.ets`

---

## Phase 6: User Story 4 - 连点订阅去重 (Priority: P2)

**Goal**: 会话内同一订阅不重复添加，幽灵行根治

**Independent Test**: 构建级验证（build-only）：代码核查 push 前判重分支与 toast 文案

- [X] T009 [US4] `addSubscription` push 前遍历 `this.subs` 按 id 判重：已存在→toast「已订阅该源」+ return（不 push/不 save/不刷新）`entry/src/main/ets/pages/HomePage.ets`

---

## Phase 7: User Story 5 - 手动刷新延长 TTL (Priority: P2)

**Goal**: 源页手动刷新成功后订阅元数据落盘，TTL 判定恢复

**Independent Test**: 构建级验证（build-only）：代码核查刷新回调落盘路径

- [X] T010 [US5] `SubscriptionStore` 新增 `persistRefreshedSub(sub: Subscription, ok: boolean)` 公共方法（重载磁盘列表→同 id 覆盖 lastRefreshAt/latestPubAt/cover/upperName→save；ok=false 时过滤已被删除的源）`entry/src/main/ets/service/SubscriptionStore.ets`
- [X] T011 [US5] `refreshSource` 成功回调中 `loadFromCache()` 前调用 `persistRefreshedSub(this.sub, true)`（依赖 T010）`entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 8: User Story 6 - 死 onPop 回调清理 (Priority: P2)

**Goal**: 两处死 onPop 回调删除，误导性注释清理

**Independent Test**: 构建级验证（build-only）：grep 确认无残留第三参 onPop 死回调

- [X] T012 [P] [US6] 删除 `subRowItem` 中 `pushPathByName('sourcePage', row.sub.id, (popInfo: PopInfo) => { this.rebuild(); })` 的第三参回调（首页已由 AppStorage tick 驱动 rebuild）`entry/src/main/ets/pages/HomePage.ets`
- [X] T013 [P] [US6] 删除 `openLogPage` 中 `pushPathByName('logPage', '', (popInfo) => { this.logCount = Logger.count(); })` 的第三参回调及误导注释（已由 `.onShown` 重读取代）`entry/src/main/ets/pages/SettingsPage.ets`

---

## Phase 9: User Story 7 - 源页过冲提示统一 (Priority: P2)

**Goal**: 源页顶部过冲提示由 reach 守卫驱动，与首页/历史面板一致

**Independent Test**: 构建级验证（build-only）：代码核查 onReachStart/dragging/alwaysEnabled 接线

- [X] T014 [US7] 源页列表对齐 HomePage 模式：新增 `@State dragging` 守卫 + `.onWillStartDragging` 置位 + `.onReachStart` 置顶部提示「已经到顶了」（仅拖拽中）+ `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`；`onScrollStop` 清顶部提示；底部「没有更多了」由既有常驻 footer/bottomHintText 承载不动 `entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T015 全仓 grep 清理：KEY_DEBUG_MODE 无重复定义、死 onPop 回调引用清零、未用 import（PopInfo 等）移除 `entry/src/main/ets/`

---

## Phase 11: Verification

<!-- verification_scope: build-only -->

**Purpose**: 构建与部署确认（本轮无 UI 验证）

- [X] T016 运行 `arkts_check` 预检全部改动 `.ets` 文件，随后 `devecocli build` 并修复编译错误（迭代修复→重建直至成功）
- [X] T017 部署到 API 24 平板虚拟机（`devecocli run --skip-build`，目标 127.0.0.1:5555）确认应用可启动运行

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup；阻塞 US1-US3（T003/T004 需 KEY_DEBUG_MODE）
- **User Stories (Phase 3-9)**: 按文件串行约束执行；T008 依赖 T003（debugEnabled 先行）；T011 依赖 T010
- **Polish (Phase 10)**: 依赖全部用户故事完成
- **Verification (Phase 11)**: 依赖 Polish 完成

### 文件串行约束（同文件任务必须按序执行）

- `SettingsPage.ets`: T004→T005→T006→T007→T013
- `Logger.ets`: T003→T008
- `HomePage.ets`: T009→T012
- `SourcePage.ets`: T011→T014
- `SubscriptionStore.ets`: T010（T011 依赖其完成）

### Parallel Opportunities

- T002/T003/T009/T010/T012/T013 互相不同文件、无相互依赖，可在各自文件约束内并行
- T012（HomePage）与 T013（SettingsPage）不同文件可并行

---

## Parallel Example

```text
并行批次 A（不同文件独立起点）:
Task: "T002 Constants 键 entry/src/main/ets/service/Constants.ets"
Task: "T003 Logger debugEnabled entry/src/main/ets/service/Logger.ets"
Task: "T009 addSubscription 去重 entry/src/main/ets/pages/HomePage.ets"
Task: "T010 persistRefreshedSub entry/src/main/ets/service/SubscriptionStore.ets"

并行批次 B（剩余独立文件）:
Task: "T012 死 onPop（HomePage）entry/src/main/ets/pages/HomePage.ets"
Task: "T013 死 onPop（SettingsPage）entry/src/main/ets/pages/SettingsPage.ets"
```

---

## Implementation Strategy

### MVP First（P1 三故事先行）

1. T001 基线核对 → T002 常量
2. T003→T008 Logger 门控基础（US3 能力线）；T004→T005 三连击（US1）；T006→T007 开关（US2）——P1 完成后 debug 模式全链可用
3. T009-T014 P2 工程债修复（按文件约束）
4. T015 清理 → T016-T017 验证

### Incremental Delivery

每个用户故事完成后到达独立可验证检查点；同文件任务严格串行；T011 依赖 T010 的公共方法抽成。

---

## Notes

- [P] 任务 = 不同文件、无未完成依赖
- [Story] 标签映射 spec.md 用户故事，保证可追溯
- 零测试任务（无测试套件）；本轮验证范围 build-only（无 UI 验证任务）
- 提交策略：沿用仓库惯例，本轮改动完成后由用户决定提交时机
- ArkTS 严格模式约束适用全部任务：禁 any/unknown/as 断言、解构、对象字面量类型；代码零注释（`ponytail:` 除外）；Constants.ets 唯一真相源（KEY_DEBUG_MODE/DEBUG_TAP_WINDOW_MS 只定义于此）
