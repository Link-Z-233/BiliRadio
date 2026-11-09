# Feature Specification: 收藏夹功能调整（互动豁免/标记常显/入队交互修复）

**Status**: Draft
**Input**: v0.7-part4-special-marks 真机验证第二批反馈（收藏夹互动稿被拦无法播放、pill 半透明底叠封面发糊、批量入队确认后界面无响应且无过程提示、多选模式下标记不可见）

## Overview

对 part4 交付的特殊标记与互动拦截做四项真机反馈调整：

1. **收藏夹源互动稿豁免拦截**——收藏夹是用户策展内容（信任用户判断），单击/「+」/批量入队均照常放行走默认路线线性播放；浏览源（UP/合集）与 BV 解析入口保留拦截（收窄 part4 US3「无条件拦截」的收藏夹覆盖面）
2. **pill 底色不透明**——半透底叠封面图发糊，四类 pill 底色 alpha 提满
3. **特殊标记与队列状态标多选模式常显**——源页 pill 与队列/历史标题前缀、行尾 ✓/✗/! 状态标不因多选隐藏（用户拍板，推翻「与既有标记一致隐藏」解读）
4. **批量入队先退多选再异步补全**——修退出动画被详情拉取耗时吞掉；fav 补全期间弹过程提示并忽略重复确认（防重入）

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 收藏夹互动稿豁免拦截 (Priority: P1)

收藏夹源用户对互动稿件单击/「+」/多选批量入队时照常入队走默认路线线性播放（收藏夹是用户策展内容，信任用户判断）；浏览源（UP/合集）与 BV 解析入口（addSingleVideo）保留互动拦截；豁免仅随收藏夹源传入，不改变其他入口行为。

**Why this priority**: 用户真机反馈收藏夹里的互动稿无法播放——收藏夹是用户主动收藏的策展内容，无条件拦截误伤正常使用场景。

**Independent Test**: 收藏夹单击/批量入队一个互动稿，照常入队可播；同一稿从 UP 源入队仍被拦截。

**Acceptance Scenarios**:

1. **Given** 收藏夹源用户单击或「+」入队互动稿件，**When** 入队执行，**Then** 互动稿照常入队走默认路线线性播放（豁免随 `sub.type === TYPE_FAV` 传入）
2. **Given** 收藏夹源多选批量入队含互动稿件，**When** 详情链补全后入队，**Then** 互动稿照常入队（走默认路线线性播放），队列条目带互动标志
3. **Given** UP/合集源用户对互动视频执行点播或加入队列，**When** 拦截触发，**Then** 不入队、不发起播放，提示互动视频不支持播放类原因（part4 US3 行为保留）
4. **Given** BV 解析入口（addSingleVideo，HomePage/AddSubscriptionSheet 分享导入）添加互动稿，**When** 入队执行，**Then** 保留拦截（不传豁免参，默认 false）

---

### User Story 2 - 标记常显与 pill 不透明 (Priority: P2)

源页四类 pill 底色不透明（半透底叠封面图发糊）；源页 pill、队列/历史标题前缀标记与行尾 ✓/✗/! 状态标在多选模式下保持可见（用户拍板常显，推翻「与既有标记一致隐藏」解读）。

**Why this priority**: 观感与信息可见性——半透底在亮色封面上发糊不可读；多选模式下标记消失导致无法辨识选中条目属性。

**Independent Test**: 打开含特殊稿件列表的多选模式观察标记常显；对照亮色封面观察 pill 底色不透明可读。

**Acceptance Scenarios**:

1. **Given** 源页列表含特殊稿件，**When** pill 渲染，**Then** 四类 pill 底色不透明（`*_pill_bg` alpha FF），任意封面可读
2. **Given** 队列/历史处于多选模式，**When** 含特殊稿件行渲染，**Then** 标题前缀标记与行尾 ✓/✗/! 状态标照常显示，不因多选隐藏（QueueSheet 门控移除）
3. **Given** 非多选模式，**When** 渲染，**Then** 标记显示与 part4 交付一致（零回归）

---

### User Story 3 - 批量入队交互修复 (Priority: P1)

收藏夹多选批量入队确认后立即退出多选（动画即刻起播，对齐队列/历史「先退多选再操作」模式——详情拉取数秒，先入队再退会吞掉退出动画），fav 路径同时弹过程提示（正在补全标志）并在补全在途时忽略重复确认（防重入）。

**Why this priority**: 交互缺陷——批量入队确认后界面无响应数秒（详情补全耗时 + 多选未退），重复点击存在重复入队风险。

**Independent Test**: 收藏夹多选多条确认入队，观察退出动画立即播放、过程提示出现、快速重复确认被忽略。

**Acceptance Scenarios**:

1. **Given** 收藏夹多选批量入队，**When** 确认执行，**Then** 立即退出多选（动画即刻起播）并弹过程提示，选中条目经详情链并行补全标志再入队，队列条目带标志；补全在途时重复确认忽略（防重入）
2. **Given** 批量入队含单条详情失败，**When** 降级入队，**Then** 该条按原列表行入队（无标志、互动不拦），其余条目不受影响（part4 降级语义保留）

---

### Edge Cases

- 豁免仅随收藏夹源传入——UP/合集批量、BV 解析入口、分享导入不豁免
- 防重入标志（enqueueInFlight）仅在 fav 批量补全在途时生效，入队完成后复位
- 多选常显不改变选中态视觉（勾选框/背景），仅移除标记渲染门控

### Non-goals

- 不做入队结果回写源页列表、不做互动跳过 toast 追加提醒（沿 part4 Non-goals）
- 不改 PlayerOverlay（能播放即以既有队列提示呈现）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `loadPlaylistAndPlay` MUST 增 `allowInteractive` 可选参（默认 false 保持既有拦截）；收藏夹源两入队路径（单击/「+」、批量）MUST 按 `sub.type === TYPE_FAV` 传豁免参，豁免时互动稿照常入队走默认路线；`addSingleVideo`（BV 解析入口）与其他调用方不传参（默认拦截）
- **FR-002**: 四类 `*_pill_bg` color 资源 alpha MUST 提满（不透明），消除半透底叠封面图发糊
- **FR-003**: 队列/历史标题前缀标记与行尾 ✓/✗/! 状态标 MUST 在多选模式常显（QueueSheet `specialMarkPrefix` 与六处状态标 `selectMode` 门控移除，HistorySheet 状态标本无门控）
- **FR-004**: 收藏夹批量入队确认后 MUST 先退出多选再异步补全入队；fav 路径 MUST 弹过程提示（`TOAST_FAV_COMPLETING`）并在补全在途时忽略重复确认（防重入）
- **FR-005**: UP/合集批量与 BV 解析入口行为 MUST 与 part4 交付一致（零回归）

### Key Entities

- **`allowInteractive` 参数**（`loadPlaylistAndPlay` 第 4 参，默认 false）：豁免互动过滤的单点开关
- **`enqueueInFlight` 标志**（SourcePage）：fav 批量补全防重入
- **`TOAST_FAV_COMPLETING` 常量**（Constants）：fav 批量补全过程提示文案

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 收藏夹源互动稿单击/批量 100% 放行入队（走默认路线线性播放）；浏览源与 BV 入口 100% 保留拦截
- **SC-002**: 多选模式下标记与状态标 0 隐藏；pill 底色在任意封面可读（不透明）
- **SC-003**: fav 批量入队确认后退出动画立即播放、过程提示出现、重复确认 0 次重复入队

## Assumptions

- 收藏夹互动稿走默认路线线性播放为既定语义（B 站互动视频音频流即主视频音频）
- 豁免仅覆盖互动拦截，门禁码（87007/87008/87005）与大会员 -104 分类不受影响

## Open Questions

- 无——四项调整均真机反馈定稿，实现已落地
