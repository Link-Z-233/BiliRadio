# Feature Specification: UX 反馈轮 R10 —— 小白条沉浸 / 隐藏胶囊穿透 / 日志页空白修复

**Created**: 2026-10-10  
**Status**: Draft  
**Input**: 用户实测 R9 签名包后反馈三项：①设置页小白条未沉浸（内容停在导航条上方，条区裸露背景色）；②设置页上已隐藏的迷你播放条仍可点击、挡住下方按钮；③日志页底部大块空白

## Overview

修复导航目的地内容与系统小白条的关系（沉浸式：内容延伸绘制至小白条后方，页面自行补偿避让）；消除隐藏迷你播放条的触摸穿透（整棵子树不参与命中测试）；迷你播放条可见性标志改为反映真实显隐，消除日志页/设置页为不可见胶囊预留的避让空白。

**根因定位（本轮已核实，SDK `enums.d.ts` + 源码验证）**：
- F1 沉浸：`Index.ets:181` Navigation 包裹层 `.padding({ top: statusBarHeight, bottom: navBarHeight })` 把全部 NavDestination 内容整体提离小白条，导航条区域只剩 Index 背景条，内容不延伸
- F2 穿透：`Index.ets:194` `hitTestBehavior(HitTestMode.None)`——SDK 文档明确 None =「自身不响应，但不阻止**子节点**参与命中测试」，包裹层不响应但 MiniPlayer 子树照常响应并拦截下层触摸
- F3 空白：`AS_MINI_PLAYER_VISIBLE` 由 MiniPlayer 恒上报 true（`MiniPlayer.ets:41-43`；`aboutToDisappear` 写 false 但永不触发）→ `LogPage:236` / `SettingsPage:1396` 为已隐藏的胶囊预留 88px 避让

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 设置页/日志页内容沉浸至小白条后方 (Priority: P1)

用户打开设置页或日志页，页面内容延伸绘制到屏幕底部（小白条后方滚动），导航条区域不再裸露背景色条；末行内容滚动可达、不被小白条遮挡。

**Why this priority**: 用户直接反馈的视觉缺陷，且是另两项同一批避让 padding 的载体，先重构基础布局。

**Independent Test**: 打开设置页滚到底，观察内容是否延伸到小白条后方、「关于」等末行是否完整可达；日志页同理。

**Acceptance Scenarios**:

1. **Given** 设置页打开, **When** 滚动到底部, **Then** 内容延伸绘制至小白条后方，导航条区域无裸露背景条，「关于」行完整可见可达
2. **Given** 日志页打开, **When** 查看页面底部, **Then** 日志列表延伸至小白条后方，底部无整块空白
3. **Given** 首页/订阅页, **When** 列表滚动到底, **Then** 视觉与现状一致（末行避让迷你播放条，不被小白条遮挡）

---

### User Story 2 - 隐藏的迷你播放条不可交互、不挡下层按钮 (Priority: P1)

播放浮层展开或设置页在台时，迷你播放条已淡出；此期间其占据的屏幕区域 MUST 不响应触摸、不拦截下层组件——设置页原胶囊区域的按钮可正常点按。

**Why this priority**: 交互缺陷直接挡住设置页底部操作，可用性问题最严重。

**Independent Test**: 进入设置页（胶囊已淡出），点按底部原胶囊覆盖区域的设置项，验证正常响应；无任何误触唤起播放浮层。

**Acceptance Scenarios**:

1. **Given** 设置页在台（胶囊已隐藏）, **When** 点按原胶囊覆盖区域的设置项, **Then** 设置项正常响应，胶囊不拦截
2. **Given** 胶囊隐藏期间, **When** 在原胶囊区域任意触摸, **Then** 不唤起播放浮层、无其他误触
3. **Given** 返回首页（胶囊重新显示）, **When** 点按胶囊, **Then** 正常唤起播放浮层（显示时行为不变）

---

### User Story 3 - 日志页底部空白消除（可见性标志反映真实显隐） (Priority: P1)

迷你播放条可见性标志改为由页面壳层依据真实显隐状态维护；日志页/设置页上胶囊已隐藏，避让 padding 取真实小值，底部不再出现 88px 整块空白。

**Why this priority**: 用户直接反馈的视觉缺陷，与 US1 修改同一批 padding 行，同轮完成。

**Independent Test**: 从设置页进入日志页，观察底部空白是否消除；返回首页确认列表避让仍正常（胶囊可见时 88px）。

**Acceptance Scenarios**:

1. **Given** 日志页打开（胶囊隐藏）, **When** 页面渲染, **Then** 底部避让为小白条高度（而非 88px 胶囊避让），无大块空白
2. **Given** 设置页打开（胶囊隐藏）, **When** 滚动到底, **Then** 末行下方仅留正常间距 + 小白条避让
3. **Given** 首页（胶囊可见）, **When** 列表渲染, **Then** 底部仍预留 88px 胶囊避让（现状不变）

---

### Edge Cases

- 三键导航设备（避让高度大于手势导航小白条）：补偿按实际 navBarHeight 缩放，末行仍可达
- 淡出动画进行中（250ms）触摸原胶囊区域：隐藏条件翻转即整棵子树退出命中测试，动画仅为视觉余像，不响应触摸（可接受）
- 播放浮层展开期间首页列表避让取小值：首页被浮层全屏覆盖不可见，无碍
- 队列面板打开时胶囊仍可见（flag 保持 true），避让现状不变
- 隐私空间/分屏等 avoid area 动态变化场景：navBarHeight 经 @StorageProp 自动跟随，补偿同步生效

## Requirements *(mandatory)*

### Functional Requirements

- **FR-101**: Index Navigation 包裹层 MUST 移除底部避让 padding（`top: statusBarHeight` 状态栏避让保持不变）；各 NavDestination 页面内容 MUST 延伸绘制至屏幕底部（沉浸式）
- **FR-102**: 受影响页面 MUST 自行补偿底部内容避让，保证末行滚动可达——设置页滚动内容底部为正常间距 + navBarHeight；日志页为 navBarHeight；首页/订阅页列表为 MINI_PLAYER_CLEARANCE + navBarHeight
- **FR-103**: 迷你播放条隐藏时（播放浮层展开或设置页在台），其整棵子树 MUST 不响应命中测试且不阻挡下层组件接收触摸；显示时行为不变（点按唤起播放浮层）；淡出动画（opacity/translate 属性动画）保留
- **FR-104**: `AS_MINI_PLAYER_VISIBLE` MUST 反映迷你播放条真实可见性——由 Index 依据显隐状态维护（初始化为可见，显隐条件翻转时同步更新）；MiniPlayer MUST 移除自身上报逻辑；消费方（首页/订阅页/设置页/日志页避让 padding）随真实值变化
- **FR-105（回归约束）**: 既有布局 MUST 无回归——MiniPlayer 底部 margin（navBarHeight+8）、PlayerOverlay 独立避让、队列面板（Index Stack 内，不受包裹层 padding 影响）均零改动

### Key Entities

不涉及新数据实体；AppStorage 键 `AS_MINI_PLAYER_VISIBLE` 语义修订：恒为 true → 反映真实显隐。沿用 `AS_NAV_BAR_HEIGHT`（navBarHeight）与 `MINI_PLAYER_CLEARANCE`。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 设置页/日志页内容延伸绘制至小白条后方，导航条区域无裸露背景条，末行滚动可达
- **SC-002**: 胶囊隐藏期间原覆盖区域触摸全部落到下层，设置页按钮正常响应，无误触唤起浮层
- **SC-003**: 日志页底部无 88px 大块空白；设置页末行下方仅正常间距 + 小白条避让
- **SC-004**: 首页/订阅页/播放层/队列面板视觉与交互无回归
- **SC-005**: `devecocli build` 通过（build-only 既定决议，UI 实测由用户真机执行）

## Assumptions

- `HitTestMode.BLOCK_DESCENDANTS`（API 20+，项目 minSdk 24）可用于整棵子树退出命中测试
- 手势导航设备小白条避让约 16-32px；三键导航设备更大，补偿按实际 navBarHeight 缩放
- 首页/订阅页列表随包裹层 padding 移除延伸至小白条后方滚动，同色背景无视觉违和（用户已确认三项全修含此重构）
- 状态栏避让（顶部）保持现状，本轮不动
- 设置页/日志页需补 `@StorageProp navBarHeight`（当前未持有）

## Open Questions

- （无——三项反馈均已定位根因并确认方案）
