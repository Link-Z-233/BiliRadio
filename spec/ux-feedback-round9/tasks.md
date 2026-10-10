# Tasks: UX 反馈轮 R9 —— 队列底部弹出与显示修复

**Input**: Design documents from `spec/ux-feedback-round9/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4，见 spec.md)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: 工程根 `entry/src/main/ets/`（component/、service/、pages/）与 `entry/src/main/resources/`
- 修改文件均在既有路径，零新增文件

---

## Phase 1: 修复实现（按故事分组）

**Purpose**: 四项反馈的最小 diff 修复，无 Setup/Foundational 阶段（既有工程零结构变更）

### Implementation for User Story 1 & 2（队列底部弹出 + 近实底，P1）

- [x] T001 [US1] `entry/src/main/ets/component/QueueDrawer.ets` 底部弹出改造：外层 Stack `alignContent: Alignment.End`→`Alignment.Bottom`；面板 `.width('100%')`、`.height('65%')`、`.borderRadius({ topLeft: 16, topRight: 16 })`、`.clip(true)`；`panelOffsetX` 改名 `panelOffsetY` 并挂 `.translate({ y: this.panelOffsetY })`（'100%'↔'0%' 机制不变）；删 statusBarHeight 顶部留白与 `@StorageProp('statusBarHeight')`；文件头注释更新为底部弹出描述。遮罩、动画时长常量、closeWithSlide、onRegisterClose 句柄、生命周期回调全部不动（FR-101，plan D1）
- [x] T002 [P] [US2] 颜色资源提不透明度：`entry/src/main/resources/base/element/color.json` 的 `queue_panel_background` 值 `#66FFFFFF`→`#F2FFFFFF`；`entry/src/main/resources/dark/element/color.json` 同名值 `#A61E1E22`→`#F01E1E22`（FR-102，plan D2）

**Checkpoint**: 队列以底部弹出呈现，封面不再穿透面板（真机自测）

### Implementation for User Story 3（未铺满可拖动 + 双向过冲提示，P2）

- [x] T003 [US3] `entry/src/main/ets/component/QueueSheet.ets` 列表 List 补 `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`，写法对齐 SettingsPage 历史面板（约 1109 行）（FR-103 前半，plan D3）
- [x] T004 [US3] QueueSheet 双向 EdgeHint：新增 `@State queueTopHint: string = ''`；外层 Stack 增 `EdgeHint({ text: this.queueTopHint, edge: 'top' })`（声明于 List 之前，与既有 bottom EdgeHint 并列）；驱动逐行对齐 SettingsPage 历史面板——`onWillStartDragging` 置 `queueDragging`、`onReachStart` 拖拽中守卫置「已经到顶了」、`onWillScroll` 按 yOffset 方向清对侧词+置本侧词（保留既有 queueEndY 到底判定）、`onScrollStop` 双词全清 + `queueDragging = false`（FR-103 后半，plan D3；T003/T004 同文件顺序执行）

**Checkpoint**: 1-2 条队列可拖出「已经到顶了/已经到底了」，回弹消失（真机自测）

### Implementation for User Story 4（时长未知不显示 00:00，P2）

- [x] T005 [P] [US4] `entry/src/main/ets/component/QueueSheet.ets` 条目第二行改条件渲染：`item.duration > 0` 显示 `${item.ownerName} · ${formatTime(item.duration * 1000)}`，否则只显示 `item.ownerName`；不改 formatTime 与任何数据链路（FR-104，plan D4）

**Checkpoint**: duration=0 条目第二行仅 UP 主名（真机自测）

---

## Phase 2: 静态检查

**Purpose**: 构建前的快速预检

- [x] T006 [P] 对本轮改动的 `QueueDrawer.ets`、`QueueSheet.ets` 跑 `arkts_check`，零错误后进入构建

---

## Phase 3: Verification

<!-- verification_scope: build-only -->

**Purpose**: Build the implemented feature（UI 验证跳过——用户既定决议，四条故事由用户真机自测）

- [x] T007 [P] `devecocli build` 通过（BUILD SUCCESSFUL）；失败则修复后重建（源码修复计入报告）
- [x] T008 [P] 记录签名包路径（hvigor hook 自动注入 signing.local.json5，产物 `entry/build/default/outputs/default/entry-default-signed.hap`）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: 无 Setup/Foundational 前置，T001/T002 与 T003/T004/T005 可并行（不同文件）
- **Phase 2**: 依赖 Phase 1 全部完成
- **Phase 3**: 依赖 Phase 2 零错误

### User Story Dependencies

- US1（容器形态）与 US3/US4（列表内部）互不依赖；T003→T004 同文件须顺序执行
- US2（颜色资源）独立，随时可做

### Within Each User Story

- 容器几何（T001）先于真机形态确认；列表属性（T003/T004/T005）不受 T001 影响

### Parallel Opportunities

- T002（资源文件）与 T001/T003-T005（ets 文件）不同文件可并行
- 单会话顺序执行即可，无需并行编排

---

## Parallel Example: 本轮无跨文件并行需求

```bash
# 单会话顺序执行：
Task: T001 QueueDrawer 底部弹出改造
Task: T002 颜色资源提不透明度
Task: T003 → T004 QueueSheet alwaysEnabled + 双向 EdgeHint（同文件顺序）
Task: T005 条目时长兜底
Task: T006 arkts_check → T007 build
```

---

## Implementation Strategy

### MVP First

1. T001+T002（形态+可读性，P1）→ 构建通过即交付用户真机确认底部弹出效果
2. T003-T005（交互一致性+显示兜底，P2）→ 构建
3. 全部完成 → 用户真机自测四条故事

---

## Notes

- **UI 验证跳过（用户既定决议）**：模拟器此前可用，本次 GPU 版本告警为系统偶发；用户确认 R9 仍不做 UI 验证。
- [P] 标记仅 T002/T005/T006/T007/T008；T003/T004 同文件必须顺序。
- 队列内容层（多选/左滑/清除已播/头部操作行）零行为改动。
- Index.ets / PlayerOverlay.ets 两处宿主零改动（QueueDrawer 对外契约不变）。
- 顺带欠账提醒：queue-redesign 的 T031/T032（模拟器 UI 验证）仍挂账，待模拟器恢复后补做。
