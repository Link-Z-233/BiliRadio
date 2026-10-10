# Feature Specification: UX 反馈轮 R9 —— 队列底部弹出与显示修复

**Created**: 2026-10-10  
**Status**: Approved  
**Input**: 用户实测签名包 0.2.0 后反馈：①队列改底部弹出（用户主动提议并确认）；②面板透明度太高被播放页封面影响；③触顶/触底提示在列表未铺满时无法拖动触发；④条目 UP 主名旁显示 00:00

## Overview

修订 queue-redesign 已定稿设计（US1 抽屉形态、US5/FR-008 单向过冲提示）并补显示兜底：播放队列由右侧窄条抽屉改为全宽底部弹出面板，面板背景近实底解决封面穿透；队列列表补 `alwaysEnabled` 过冲拖动与触顶提示，对齐其余三页既有模式；时长未知条目不再渲染 00:00。

**根因定位（本轮已核实）**：
- F2：`queue_panel_background` 浅色值 `#66FFFFFF`（40% 不透明），封面穿透
- F3：QueueSheet 的 List 缺 `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`（首页/设置页/源页均有）；且 FR-008 只实现底部提示
- F4：合集/收藏夹列表接口条目无 duration 字段，入队即 0，`UP主名 · formatTime(0)` 渲染 "00:00"，持久化如实存 0，重进依旧

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 队列底部弹出 (Priority: P1)

用户在播放页或首页打开播放队列，面板从底部滑入（全宽、约 65% 屏高、顶部圆角），点遮罩或返回键滑出关闭。

**Why this priority**: 形态是其余三项的载体，先定形态避免在旧抽屉上返工。

**Independent Test**: 打开队列验证滑入方向、宽度、关闭路径；播放层（PlayerOverlay 内）与内容层（Index 内）两处挂载行为一致。

**Acceptance Scenarios**:

1. **Given** 播放页已打开, **When** 点队列按钮, **Then** 底部弹出全宽面板，封面被大面积遮罩压暗
2. **Given** 队列面板打开, **When** 点遮罩或按返回键, **Then** 面板向下滑出后卸载，原 underneath 页面不受影响
3. **Given** 首页（播放层收起）, **When** 打开队列, **Then** 同一底部弹出行为

---

### User Story 2 - 面板近实底可读性 (Priority: P1)

队列面板背景近实底（≥90% 不透明度），封面颜色不再穿透影响列表文字对比度。

**Why this priority**: 可读性缺陷直接影响队列可用性，与形态同轮修复。

**Independent Test**: 在高饱和度封面的播放页打开队列，观察文字对比度。

**Acceptance Scenarios**:

1. **Given** 播放页封面高饱和, **When** 打开队列, **Then** 条目标题/UP主名/操作图标清晰可读，无封面色穿透

---

### User Story 3 - 未铺满队列可拖动 + 双向过冲提示 (Priority: P2)

短队列（条目未铺满面板高度）也能拖动过冲：触顶露「已经到顶了」、触底露「已经到底了」，回弹消失。

**Why this priority**: 反馈一致性——其余三个列表页均有此交互，队列缺失显得「坏了」。

**Independent Test**: 队列只放 1-2 条，按住上/下拖动出现过冲提示；回弹后提示消失；长队列滚动到顶/底同样触发。

**Acceptance Scenarios**:

1. **Given** 队列仅 1 条（未铺满）, **When** 按住列表向上拖, **Then** 顶部露出「已经到顶了」
2. **Given** 队列仅 1 条, **When** 按住列表向下拖, **Then** 底部露出「已经到底了」
3. **Given** 提示已露出, **When** 松手回弹, **Then** 提示消失

---

### User Story 4 - 时长未知条目不显示 00:00 (Priority: P2)

通过合集/收藏夹批量入队、尚未播放过的条目（duration=0），第二行只显示 UP 主名；播过后回填机制补上真实时长再显示 mm:ss。

**Why this priority**: 00:00 是误导性占位，廉价修复（显示层兜底）。

**Independent Test**: 入队若干合集条目不播放，打开队列检查第二行。

**Acceptance Scenarios**:

1. **Given** 条目 duration=0, **When** 队列渲染, **Then** 第二行只显示 UP 主名
2. **Given** 条目已播过（duration 已回填 >0）, **When** 队列渲染, **Then** 显示「UP主名 · mm:ss」

---

### Edge Cases

- 多选模式下的长按滑动多选（PanGesture Vertical）与列表拖动并存——保持既有手势优先级不变，仅补 edgeEffect，不引入新手势
- onReachStart 初始化误触发一次——沿用拖拽中守卫（onWillStartDragging 置标志），与设置页历史面板同款
- 队列为空时：无列表无提示，仅空态文案（现状保留）
- 宽屏（isWideScreen）下底部弹出的全宽形态同样适用（平板上仍全宽 65% 高）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-101（修订 queue-redesign US1）**: 播放队列容器 MUST 为底部弹出面板——全宽、约 65% 屏高、顶部圆角、底部安全区留白；进出场 MUST 沿用既有状态驱动位移动画机制（改为 Y 轴）；遮罩点击关闭、返回键关闭、两处挂载点（Index/PlayerOverlay）语义不变
- **FR-102**: 队列面板背景不透明度 MUST ≥90%（浅色/深色双份资源同步调整），封面不得穿透影响可读性
- **FR-103（修订 queue-redesign US5/FR-008）**: 队列列表 MUST 补 `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })` 使未铺满时可拖动；过冲提示 MUST 双向（触顶+触底），驱动模式 MUST 对齐 SettingsPage 历史面板（onWillStartDragging 置拖拽标志、onReachStart/onReachEnd 拖拽中守卫置词、onWillScroll 反向滚动清词、onScrollStop 全清）
- **FR-104**: 队列条目第二行时长 MUST 按 duration 兜底——duration>0 显示「UP主名 · mm:ss」，duration≤0 只显示 UP 主名

### Key Entities

不涉及新数据实体；沿用 BiliVideo（duration 字段语义不变，0=未知）与既有颜色资源 `queue_panel_background`。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 队列在播放层内外两处均以底部弹出打开/关闭，动画无残影无白屏
- **SC-002**: 任意封面下队列文字对比度可读（面板底 ≥90% 不透明度）
- **SC-003**: 1 条队列即可拖出双向过冲提示，与首页/设置页/源页交互一致
- **SC-004**: duration=0 条目全链路（入队→持久化→重进）不出现 00:00
- **SC-005**: `devecocli build` 通过（build-only，模拟器 GPU 版本过低不可用为既定决议，UI 实测由用户真机执行）

## Assumptions

- 底部弹出沿用 Stack + 状态驱动位移（规避 KI-5：bindContentCover/bindSheet 半模态在 API 24 平板渲染管线断裂），不引入系统半模态
- 65% 屏高为经验值，实现时不做用户可配置
- 不做入队时逐条拉详情补时长（网络成本不值；播过的条目已有播放器回填）
- 队列内容层（多选/左滑/清除已播）零行为改动
- `translate` 百分比相对面板自身高度，Y 轴滑入复用现有 panelOffset 状态方案

## Open Questions

- （无——四项反馈均已定位根因并确认方案）
