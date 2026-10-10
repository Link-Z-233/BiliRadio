# Tasks: UX 反馈轮 R10 —— 小白条沉浸 / 隐藏胶囊穿透 / 日志页空白修复

**Input**: Design documents from `spec/ux-feedback-round10/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US3，见 spec.md)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: 工程根 `entry/src/main/ets/`（pages/、component/）
- 修改文件均在既有路径，零新增文件、零新依赖

---

## Phase 1: 修复实现（按故事分组）

**Purpose**: 三项反馈的最小 diff 修复，无 Setup/Foundational 阶段（既有工程零结构变更）

### Implementation for User Story 1（小白条沉浸，P1）

- [X] T001 [US1] `entry/src/main/ets/pages/Index.ets` 第 181 行 Navigation 包裹层 `.padding({ top: this.statusBarHeight, bottom: this.navBarHeight })` 改为 `.padding({ top: this.statusBarHeight })`（仅保留状态栏顶部避让；`navBarHeight` 成员仍被 MiniPlayer 等消费，勿删）——FR-101，plan D1
- [X] T002 [P] [US1] `entry/src/main/ets/pages/SettingsPage.ets` 成员声明区补 `@StorageProp('navBarHeight') navBarHeight: number = 0;`；第 1396 行滚动内容底部 padding 改 `bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 24) + this.navBarHeight`（显隐标志修正后本页取 24，叠加小白条避让）——FR-102，plan D4
- [X] T003 [P] [US1] `entry/src/main/ets/pages/LogPage.ets` 成员声明区补 `@StorageProp('navBarHeight') navBarHeight: number = 0;`；第 236 行 `.padding({ bottom: this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 0 })` 改为 `.padding({ bottom: this.navBarHeight })`（本页胶囊恒隐藏，直接取小白条避让，消除 88px 空白）——FR-102/104，plan D4
- [X] T004 [P] [US1] `entry/src/main/ets/pages/HomePage.ets` 成员声明区补 `@StorageProp('navBarHeight') navBarHeight: number = 0;`；第 345 行列表底部 padding 改 `bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12) + this.navBarHeight`——FR-102，plan D4
- [X] T005 [P] [US1] `entry/src/main/ets/pages/SourcePage.ets` 成员声明区补 `@StorageProp('navBarHeight') navBarHeight: number = 0;`；第 497 行列表底部 padding 改 `bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12) + this.navBarHeight`——FR-102，plan D4

**Checkpoint**: 设置页/日志页内容延伸绘制至小白条后方，导航条区域无裸露背景条；首页/订阅页视觉不变（真机自测）

### Implementation for User Story 2（隐藏胶囊不可交互，P1）

- [X] T006 [US2] `entry/src/main/ets/pages/Index.ets` 第 194 行 `.hitTestBehavior(this.miniHidden ? HitTestMode.None : HitTestMode.Default)` 改为 `HitTestMode.BLOCK_DESCENDANTS`（SDK `enums.d.ts` 实测拼写，since API 20）；第 186 行注释「透明时不响应点击」同步更新为「BLOCK_DESCENDANTS：自身+全部子孙退出命中测试，触摸落回下层」——FR-103，plan D2（与 T001/T007 同文件，顺序执行）

**Checkpoint**: 设置页上点按原胶囊覆盖区域，下层设置项正常响应，无误触（真机自测）

### Implementation for User Story 3（可见性上报移交，P1）

- [X] T007 [US3] `entry/src/main/ets/pages/Index.ets`：`aboutToAppear` 增 `AppStorage.setOrCreate<boolean>(Constants.AS_MINI_PLAYER_VISIBLE, true);`（初始胶囊可见）；`onMiniVisibilityChanged` 计算 hidden 后增 `AppStorage.setOrCreate<boolean>(Constants.AS_MINI_PLAYER_VISIBLE, !hidden);`——FR-104，plan D3（写此键不触发自身 @Watch，无循环；与 T001/T006 同文件顺序执行）
- [X] T008 [P] [US3] `entry/src/main/ets/component/MiniPlayer.ets` 删除 `aboutToDisappear` 第 31 行 `AppStorage.setOrCreate(AS_MINI_PLAYER_VISIBLE, false)`；删除 `syncFromPlayer` 第 39-44 行恒 true 上报块（prevVisible 判断）——FR-104，plan D3

**Checkpoint**: 日志页底部无 88px 空白；首页胶囊可见时避让 88px 不变（真机自测）

---

## Phase 2: 静态检查

**Purpose**: 构建前的快速预检

- [X] T009 [P] 对本轮改动的 `Index.ets`、`MiniPlayer.ets`、`SettingsPage.ets`、`LogPage.ets`、`HomePage.ets`、`SourcePage.ets` 跑 `arkts_check`，零错误后进入构建

---

## Phase 3: Verification

<!-- verification_scope: build-only -->

**Purpose**: Build the implemented feature（UI 验证跳过——用户既定决议，三条故事由用户真机自测）

- [x] T010 [P] `devecocli build` 通过（BUILD SUCCESSFUL）；失败则修复后重建（源码修复计入报告）
- [x] T011 [P] 记录签名包路径（hvigor hook 自动注入 signing.local.json5，产物 `entry/build/default/outputs/default/entry-default-signed.hap`）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: 无 Setup/Foundational 前置；T001→T006→T007 同文件（Index.ets）顺序执行；T002-T005、T008 不同文件可并行
- **Phase 2**: 依赖 Phase 1 全部完成
- **Phase 3**: 依赖 Phase 2 零错误

### User Story Dependencies

- US1（T001-T005）是布局基础；US2（T006）与 US3（T007/T008）逻辑独立但 T006/T007 落在同一 Index.ets，须在 T001 之后顺序执行
- T002-T005（四页避让补偿）依赖 T001 移除包裹层 bottom padding，但不依赖彼此

### Within Each User Story

- Index.ets 三处改动（T001 沉浸 → T006 命中测试 → T007 上报）同文件须顺序，避免编辑冲突
- MiniPlayer.ets（T008）独立于 Index，随时可做

### Parallel Opportunities

- T002/T003/T004/T005/T008（五个不同文件）与 Index 系列可并行
- 单会话顺序执行即可，无需并行编排

---

## Parallel Example: 本轮除 Index.ets 系列外均为跨文件独立

```bash
# 单会话顺序执行：
Task: T001 Index 包裹层 padding 去除 bottom
Task: T002-T005 四页避让补偿（各自独立文件）
Task: T006 Index 命中测试 BLOCK_DESCENDANTS
Task: T007 Index 可见性上报移交
Task: T008 MiniPlayer 删除自身上报
Task: T009 arkts_check → T010 build
```

---

## Implementation Strategy

### MVP First

1. T001-T005（沉浸基础，P1）→ 构建通过即交付用户真机确认沉浸效果
2. T006（穿透，P1）+ T007/T008（空白，P1）→ 构建
3. 全部完成 → 用户真机自测三条故事

---

## Notes

- **UI 验证跳过（用户既定决议）**：R9 起确认后续反馈轮仍不做 UI 验证，三条故事由用户真机自测。
- [P] 标记：T002-T005/T008/T009/T010/T011；T001/T006/T007 同文件必须顺序。
- 回归约束（FR-105）：MiniPlayer margin（navBarHeight+8）、PlayerOverlay 独立避让、队列面板（Index Stack 内）零改动；状态栏顶部避让不动。
- 设置页/日志页当前未持有 `navBarHeight`，T002/T003 需补 `@StorageProp` 声明。
- `HitTestMode.BLOCK_DESCENDANTS` 拼写须严格按 SDK（`enums.d.ts` line 3363）书写。
- 顺带欠账提醒：queue-redesign 的 T031/T032（模拟器 UI 验证）仍挂账，待模拟器恢复后补做。
