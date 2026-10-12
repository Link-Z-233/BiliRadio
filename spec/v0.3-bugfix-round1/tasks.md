# Tasks: v0.3 Bug 修复第一轮（v0.3-bugfix-round1）

**Input**: Design documents from `spec/v0.3-bugfix-round1/`
**Prerequisites**: plan.md（决策 D1-D7）、spec.md（用户故事 US1-US7）

> **轮次性质**：纯修复轮——9 项真机反馈合并为 7 用户故事，全部为既有文件定向修改 + EdgeHint 组件删除。无新增文件、无数据模型变更。**验证范围：仅构建验证（build-only）**——用户已在 Phase 2 Review Gate 指定，AGENTS.md 已同步写入「默认仅构建验证」规则。

## Format

任务格式：`- [ ] [TaskID] [P?] [Story?] Description with exact file path`

- `[P]`：可并行（不同文件、无未完成依赖）
- `[Story]`：用户故事标签（`[US1]`~`[US7]`），仅用户故事阶段任务携带
- 每条任务以确切文件路径结尾

## Path Conventions

- 源码根：`entry/src/main/ets/`（pages/ 页面、service/ 服务、component/ 组件）
- 文档：仓库根 `AGENTS.md`、`PROJECT_NOTES.md`

**全局执行约束（实施轮适用）**：

- 遵循 AGENTS.md：`Constants` 唯一真相源、禁 any/unknown/as、代码零注释（`ponytail:` 除外）、V2 装饰器（已迁 V2 页面禁 V1）
- 每个用户故事完成即 `arkts_check`（该故事涉及 .ets）+ `devecocli build` 通过后再进入下一故事
- **同文件顺序约束**：`PlayerOverlay.ets` 涉及 US1/US3/US4/US5 四处修改、`PlayerController.ets` 涉及 US1/US6 两处修改——跨故事同文件任务**不得并行**，按故事顺序执行（US1→US5→US6 先改 PlayerController/PlayerOverlay，其余故事随后）
- 删除类任务先核对调用方（EdgeHint 全局仅 5 处 import，已核实）
- 本轮无 UI 验证任务（build-only）；真机验证由用户实测反馈

---

## Phase 1: Setup（前置核查）

**Purpose**: 确认基线绿色

- [X] T001 执行一次全量构建确认当前基线绿色（`devecocli build`；基线含 debt-cleanup 合并提交，构建约 30-60s）

**Checkpoint**: 基线绿色

---

## Phase 2: Foundational（阻塞前置）

无——7 个故事全部为既有文件独立修改，无共享阻塞前置，直接进入用户故事。

---

## Phase 3: User Story 1 - 播放按钮状态稳定 (Priority: P1) 🎯 MVP

**Goal**: 播放页播放按钮呼吸浮动消除（updateGlow 无限动画改一次性过渡）+ isPlaying 状态去抖（播放/暂停图标不再来回切换、MiniPlayer 周期变化同源修复）

**Independent Test**: 播放页点播放→图标稳定为暂停态无浮动；多次点按状态逐一切换；返回首页 MiniPlayer 按钮无周期变化

### Implementation for User Story 1

- [X] T002 [US1] `updateGlow()` 移除无限呼吸：`entry/src/main/ets/pages/PlayerOverlay.ets` L189-204——删除 `iterations: -1 + PlayMode.Alternate` 无限动画，改为 isPlaying 变化时一次性过渡（播放→glowStrength 淡入 GLOW_ACTIVE 后停止；暂停→淡出 GLOW_IDLE）
- [X] T003 [US1] isPlaying 状态去抖：`entry/src/main/ets/service/PlayerController.ets` `onPlayerState`（L353-385 playing/paused 分支）——状态翻转加 300ms 稳定窗口（翻转后重置计时器，窗口内再次翻转不写 `isPlaying`/不 `emitUi`；窗口期满才写入），消除 AVPlayer stateChange 链路瞬时抖动传播

**Checkpoint**: 播放按钮无呼吸浮动、图标切换稳定；MiniPlayer 同源同步无周期变化（构建验证）

---

## Phase 4: User Story 5 - 播放页内队列系统返回动画 (Priority: P1)

**Goal**: 播放页内打开播放列表，系统返回触发滑出动画再卸载（与首页实例一致）

**Independent Test**: 播放页打开队列→按系统返回→面板先滑出（250ms）再关闭

### Implementation for User Story 5

- [X] T004 [US5] 队列关闭句柄透传：`entry/src/main/ets/pages/PlayerOverlay.ets`——新增 `@Param onRegisterClose`（默认 no-op），透传给内部 `QueueDrawer` 的 `onRegisterClose`（L1324-1327）；`entry/src/main/ets/pages/Index.ets` L209-214 渲染 `PlayerOverlay` 时传入自身 `queueClose` 注册回调（与 Index 层 QueueDrawer 同款上报）；QueueDrawer 契约零改动

**Checkpoint**: 播放页内队列系统返回有滑出动画（构建验证）

---

## Phase 5: User Story 6 - 「仅在 Wi-Fi 环境播放」开关拦截非 Wi-Fi 播放 (Priority: P1)

**Goal**: 开关开启且非 Wi-Fi 时，播放（起播/切歌/切集）弹确认框；确认继续、取消中止（原 T005 误删已回退）

**Independent Test**: 流量环境播放中开启开关→切歌弹非 Wi-Fi 确认框；Wi-Fi 或开关关闭不拦截

### Implementation for User Story 6

- [X] T005 [US6] 回退误删、恢复播放拦截块并前移位置：`entry/src/main/ets/service/PlayerController.ets` `playIndex` 恢复 wifiOnly 确认拦截，且**置于任何状态改写之前**（index 校验后、`currentIndex` 改写/`emitUi` 前——真机反馈「阻断太晚」：拦截在 UI 切换后执行致音频/UI 不一致）；注释修正为「非 Wi-Fi 播放确认」真实语义——保留 `Constants.KEY_WIFI_ONLY_DOWNLOAD` 键与设置页开关、`confirmCellularDownload` 回调

**Checkpoint**: 开关正确拦截非 Wi-Fi 播放（构建验证；开关本身持久化/确认框表现待用户真机复测）

---

## Phase 6: User Story 7 - 队列多选退出完整 (Priority: P1)

**Goal**: 系统返回优先退出多选（面板保留）；关闭面板自动退出多选

**Independent Test**: 队列多选态按返回→仅退出多选面板保留；关闭队列再开→无多选残留

### Implementation for User Story 7

- [X] T006 [US7] 返回优先退多选：`entry/src/main/ets/pages/Index.ets` `onBackPress` L109-118 `showQueueSheet` 分支——先查 `selectMode.value`：为 true 时置 false 并清 `selectedBvids` 后 return true（面板保留）；否则走既有 `queueClose()` 滑出；L154-158 selectMode 兜底分支保留
- [X] T007 [US7] 关闭自动退多选：`entry/src/main/ets/component/QueueSheet.ets`——新增 `@Monitor('showQueueSheet.value')` 监听，value→false 时调既有 `exitSelectMode()`（L217-220），覆盖遮罩/返回/滑出全部关闭路径

**Checkpoint**: 多选退出完整无残留（构建验证）

---

## Phase 7: User Story 2 - 移除过冲文字提醒 (Priority: P2)

**Goal**: 全部页面「已经到顶了/已经到底了」文字移除；物理回弹保留

**Independent Test**: 逐页滚动到顶/底无文字提示；过冲回弹手感不变

### Implementation for User Story 2

- [X] T008 [P] [US2] 移除首页 EdgeHint：`entry/src/main/ets/pages/HomePage.ets`——删 import（L7）、L353-354 两处 `<EdgeHint>`、`topHint`/`bottomHint` 状态字段与 L374-393 赋值/触发逻辑
- [X] T009 [P] [US2] 移除源页 EdgeHint：`entry/src/main/ets/pages/SourcePage.ets`——删 import（L13）、L429-430 两处 `<EdgeHint>`、`topHint`/`bottomHint` 状态与 L514-526 赋值/触发逻辑
- [X] T010 [P] [US2] 移除设置页 EdgeHint：`entry/src/main/ets/pages/SettingsPage.ets`——删 import（L15）、历史面板 L1078-1079 与设置滚动 L1235-1236 共 4 处 `<EdgeHint>`、`historyTopHint`/`historyBottomHint`/`settingsTopHint`/`settingsBottomHint` 状态与 L1123-1142/L1408-1424 赋值/触发逻辑
- [X] T011 [P] [US2] 移除队列 EdgeHint：`entry/src/main/ets/component/QueueSheet.ets`——删 import（L8）、L487-488 两处 `<EdgeHint>`、`queueTopHint`/`queueBottomHint` 状态与 L583-609 赋值/触发逻辑（注意保留 alwaysEnabled 过冲物理回弹）
- [X] T012 [US2] 删除组件文件：`entry/src/main/ets/component/EdgeHint.ets` 整体删除（依赖 T008-T011 完成、全局 `EdgeHint` 零引用后）

**Checkpoint**: 全局检索 `EdgeHint`/「已经到顶了」/「已经到底了」零命中（构建验证）

---

## Phase 8: User Story 3 - 移除播放页状态行 (Priority: P2)

**Goal**: 播放页底部常驻 statusMsg 状态行整行移除

**Independent Test**: 播放页无底部状态文字行

### Implementation for User Story 3

- [X] T013 [US3] 移除状态行 UI：`entry/src/main/ets/pages/PlayerOverlay.ets` L1272-1281 常驻底栏整段删除（statusMsg Text + isPreparing 行首 LoadingProgress 分支）；`statusMsg` 业务赋值（controller 侧）保留不动

**Checkpoint**: 播放页底部无状态行（构建验证）

---

## Phase 9: User Story 4 - 倒序播放图标旋转 180° (Priority: P2)

**Goal**: 倒序模式图标 = 顺序播放图标旋转 180°

**Independent Test**: 切到倒序模式观察图标为旋转 180° 的顺序图标；其余模式不变

### Implementation for User Story 4

- [X] T014 [US4] 图标与旋转：`entry/src/main/ets/pages/PlayerOverlay.ets`——`playModeIcon()`（L394-405）REVERSE 分支改返回 `sys.symbol.order_play`；新增 `playModeRotate(): number`（REVERSE=180，其余=0）；L1204 `SymbolGlyph(this.playModeIcon())` 挂 `.rotate({ angle: this.playModeRotate() })`

**Checkpoint**: 倒序图标语义正确（构建验证）

---

## Phase 10: Polish（跨故事收尾）

**Purpose**: 验证范围规则文档化（已完成）

- [X] T015 AGENTS.md「工作方式」节已写入「验证范围默认值」规则（2026-10-11，用户 Phase 2 Review Gate 指令）——`AGENTS.md`：默认仅构建验证（build-only），需 UI 验证须在 Phase 3 前显式提出

---

## Phase 11: Verification

<!-- verification_scope: build-only -->

**Purpose**: 构建验证全部修复（用户指定仅构建验证；真机行为由用户实测反馈）

- [X] T016 构建验证：对 T002-T014 涉及的全部 `.ets` 执行 `arkts_check` 零诊断 + `devecocli build` 通过（迭代修复至绿）——**PASS**（8 文件 0 诊断；BUILD SUCCESSFUL，1/10 次尝试）
- [X] T017 部署验证：`devecocli run --skip-build` 部署到可用设备（模拟器验证已终止、当前无活动设备时记录「待用户真机部署」并跳过——不阻塞收尾）——**SKIPPED**（仅 2 台已停止模拟器，无活动设备；待用户真机部署）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖（T001 基线构建为实施前置）
- **Foundational (Phase 2)**: 无任务
- **User Stories (Phase 3-9)**: 全部仅依赖 T001；故事间文件交叉约束见下
- **Polish (Phase 10)**: 已完成（T015 [X]）
- **Verification (Phase 11)**: 依赖 T002-T014 全部完成

### User Story Dependencies

- **US1 (P1)**: 依赖 Setup；PlayerController.ets 改动（T003）与 US6（T005）**同文件须顺序**（US1 先）
- **US5 (P1)**: 依赖 Setup；PlayerOverlay.ets 改动（T004）与 US1（T002）/US3（T013）/US4（T014）**同文件须顺序**
- **US6 (P1)**: 依赖 Setup；PlayerController.ets 与 US1 同文件顺序（US1 后）
- **US7 (P1)**: 依赖 Setup；Index.ets（T006）+ QueueSheet.ets（T007）不同文件可并行
- **US2 (P2)**: 依赖 Setup；T008-T011 四文件并行，T012 组件删除依赖四者完成
- **US3 (P2)**: 依赖 Setup；PlayerOverlay.ets 与 US1/US5/US4 同文件顺序
- **US4 (P2)**: 依赖 Setup；PlayerOverlay.ets 与 US1/US5/US3 同文件顺序

### Within Each User Story

- 修改前核对调用方（plan.md D1-D7 已核实）
- 故事内任务完成 → `arkts_check` + `devecocli build` → Checkpoint → 下一故事

### Parallel Opportunities

- US7 的 T006/T007（Index.ets + QueueSheet.ets）可并行
- US2 的 T008-T011（四文件）可并行；T012 依赖其后
- **不可并行**：PlayerOverlay.ets 全部改动（US1/US5/US3/US4）与 PlayerController.ets 改动（US1/US6）——同文件顺序执行，避免冲突

---

## Parallel Example

```text
# 建议顺序（同文件约束）：
Task: T001 基线构建 → T002/T003 [US1 PlayerOverlay+Controller] → T004 [US5 PlayerOverlay]
      → T005 [US6 Controller] → T006/T007 [US7 Index+QueueSheet 并行] → T008-T011 [US2 四文件并行]
      → T012 [US2 删组件] → T013 [US3 PlayerOverlay] → T014 [US4 PlayerOverlay]

# 并行窗口（不同文件）：
Task: T006 [US7] Index.ets onBackPress 多选优先
Task: T007 [US7] QueueSheet.ets @Monitor 自动退多选
Task: T008 [US2] HomePage.ets 移除 EdgeHint
Task: T009 [US2] SourcePage.ets 移除 EdgeHint
Task: T010 [US2] SettingsPage.ets 移除 EdgeHint
Task: T011 [US2] QueueSheet.ets 移除 EdgeHint
```

## Implementation Strategy

### MVP First（最小可交付）

1. 完成 Setup（T001）
2. 完成 US1（T002-T003）+ 构建——播放按钮稳定性独立交付
3. **STOP and VALIDATE**：构建绿 + 用户真机复测

### Incremental Delivery

1. Setup → US1（MVP）→ US5 → US6 → US7（P1 全清）→ US2 → US3 → US4（P2）
2. 同文件约束贯穿：PlayerOverlay/PlayerController 改动集中在前段顺序完成
3. 验证阶段（T016-T017）：arkts_check + build；部署待设备

### 本轮执行策略（用户已批准全范围）

- **实施轮**：T001-T014 一次推进（同文件顺序 + 并行窗口），每故事构建验证
- **验证轮**：T016-T017 build-only（无 UI 验证任务）；真机由用户实测反馈
- 无人值守规则适用（小问题记录继续、大问题暂停报告、争议交用户决策）

---

## Notes

- **总任务数**：17（Setup 1 / US1 2 / US5 1 / US6 1 / US7 2 / US2 5 / US3 1 / US4 1 / Polish 1 / 验证 2）
- **每故事任务数**：US1=2、US2=5、US3=1、US4=1、US5=1、US6=1、US7=2
- **[P] 标注基准**：不同文件且无未完成依赖
- **验证范围**：build-only（用户指定 + AGENTS.md 默认值）；无 UI 验证任务
- **同文件顺序约束**：PlayerOverlay.ets（US1→US5→US3→US4）与 PlayerController.ets（US1→US6）严格顺序
- **提交策略**：实施轮独立提交（沿用「批次独立提交」惯例）；AGENTS.md 变更随本轮提交
