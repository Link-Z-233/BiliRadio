# Feature Specification: 订阅源管理三件套（v0.6-part3）

**Status**: Draft
**Input**: User description: "支持功能为1.首页排序，2.订阅源导入与导出，3.跨设备分享同步订阅源"（歧义经用户多轮确认：排序为长按进入列表编辑态拖拽调序、导出走系统分享面板 + JSON + 去重合并、跨设备为文件分享式、WebDAV 同步登记为后续候选需求）；真机实测反馈迭代——长按行改弹菜单（置顶/排序/删除三项，按压达成即弹、行缩放强调、浮起阴影、菜单从行上方展开，文件管理风格）；置顶为移动语义（onDataMove 官方为交换语义，修复为相邻交换冒泡通知，置顶数量不限）且带列表补位动画；进退排序编辑态动画与源详情页多选进出动画完全一致（animateTo 驱动同构）；编辑态行内容平滑让位给恒挂载拖拽把手（单 List 复刻多选机制）；编辑态整行可拖放（单 List 合并后行级长按手势阻塞系统拖拽的回归修复——编辑态禁行级交互、按压反馈移至 ListItem.onTouch）；拖拽把手加大且左右留白对称；拖拽落子即时刷新 bug 修复与编辑态转场可见性修正（TransitionEffect 无 animation 参数根因）；编辑态拖拽把手即按即拖（把手挂 PanGesture 自定义手动拖拽，按下移动立即拖动免长按等待；把手长按被空 LongPressGesture 认领阻断、不触发系统拖拽——把手 pan-only）

## Overview

v0.6-part3 围绕订阅源管理补齐三块能力：**首页排序**（长按订阅行弹出菜单——置顶/排序/删除三项；「排序」进入整页列表编辑态，行拖拽调序、松手落盘；置顶带补位动画；原失效 `bindContextMenu` 菜单废弃，新菜单以 LongPressGesture + 受控 bindMenu 重新实现）；**导入导出**（订阅列表全量导出为 JSON 经系统分享面板发出，文档选择器选入 JSON 按源 id 去重合并）；**跨设备分享同步**（文件分享式——导出→华为分享/微信等通道发送→对端导入，串联导入导出两端用法，不引入服务器）。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 列表编辑态拖拽排序 (Priority: P1)

用户经长按菜单「排序」项（US5）进入整页排序编辑态：行浮起可拖拽至任意位置，松手落盘；退出通道双轨——标题栏「完成」按钮、系统返回（侧滑/返回键，接入 BackHandler 链由编辑态优先消费）。原 `bindContextMenu` 长按菜单真机失效，随新菜单实现废弃。

**Why this priority**: 排序是用户高频诉求且是本轮唯一的首页交互改造。

**Independent Test**: 真机长按订阅行弹菜单点「排序」进入编辑态；拖某行至新位置松手；杀进程重启顺序保持；点完成回正常态。

**Acceptance Scenarios**:

1. **Given** 真机首页, **When** 长按任意订阅行并在菜单点「排序」, **Then** 整页进入排序编辑态
2. **Given** 编辑态, **When** 拖拽某行至新位置松手, **Then** 列表顺序即时调整并落盘
3. **Given** 拖拽落盘后, **When** 杀进程重启应用, **Then** 顺序与拖拽后一致
4. **Given** 编辑态, **When** 点标题栏「完成」或系统返回（侧滑/返回键）, **Then** 退出编辑态回正常态，列表按调整后顺序展示
5. **Given** 编辑态, **When** 系统返回, **Then** 返回优先退出编辑态而非离开页面/应用
6. **Given** 正常态, **When** 左滑删除订阅 / 点击进源详情, **Then** 既有行为零回归（删除导航交互地图不变）

---

### User Story 2 - 订阅列表导出 (Priority: P2)

设置页新增订阅管理入口，用户点「导出订阅」后系统将全部订阅源（四类源统一模型，含排序与归属字段）序列化为 JSON 文件，拉起系统分享面板，可发送至微信/QQ、保存到文件管理器、或经华为分享直发附近 HarmonyOS 设备。

**Why this priority**: 导出是跨设备链路的发送端，也是订阅数据备份手段；不依赖 US1。

**Independent Test**: 设置页点导出，分享面板拉起，选任一目标后文件送达；JSON 内容可被 `Subscription.fromRecord` 语义解析。

**Acceptance Scenarios**:

1. **Given** 已有若干订阅, **When** 设置页点「导出订阅」, **Then** 拉起系统分享面板并携带 JSON 文件
2. **Given** 分享面板, **When** 选择任一分享目标（应用/保存/华为分享）, **Then** 文件成功送达目标
3. **Given** 空订阅列表, **When** 点「导出订阅」, **Then** 给出无订阅提示（明确行为，不发空文件）

---

### User Story 3 - 订阅列表导入（去重合并） (Priority: P3)

设置页新增「导入订阅」入口，拉起系统文档选择器，用户选中 US2 导出的 JSON 文件后：校验格式（非法文件明确报错且现有数据零改动）；按源 id 去重——已订阅的源跳过，仅增量添加新源（追加到列表末尾）；导入完成提示「新增 N 个，跳过 M 个」；新增源自动触发一次刷新拉取封面与剧集。

**Why this priority**: 导入是跨设备链路的接收端，依赖 US2 的文件格式，排导出之后。

**Independent Test**: 导出 A 设备订阅 → B 设备导入 → B 首页出现全部源且可正常进源详情刷新剧集；同一文件二次导入全部跳过。

**Acceptance Scenarios**:

1. **Given** 本机已有订阅 X, **When** 导入含 X 与新源 Y 的文件, **Then** 仅 Y 被添加至列表末尾，提示「新增 1 个，跳过 1 个」
2. **Given** 选中文件, **When** 文件非 JSON/缺 items/条目字段非法, **Then** 明确报错提示，现有订阅数据零改动
3. **Given** 导入新增源 Y, **When** 导入完成, **Then** Y 自动刷新（封面/剧集拉取，复用现有新订阅刷新模式）
4. **Given** 同一文件第二次导入, **When** 全部源已存在, **Then** 提示「新增 0 个，跳过 N 个」，列表零变化

---

### User Story 4 - 跨设备分享同步串联验收 (Priority: P3)

两台 HarmonyOS 设备（或一台设备 + 任意接收端）完整走通：A 设备导出 → 分享面板经华为分享/微信发送 → B 设备接收文件 → B 设备导入 → B 设备订阅列表与 A 对齐，各源可正常刷新与播放。

**Why this priority**: 端到端验收故事，本身几乎零新增代码（US2+US3 串联），价值在验证真实跨设备链路。

**Independent Test**: 双设备往返实测，对齐后 B 设备逐源进入详情页可拉取剧集并播放。

**Acceptance Scenarios**:

1. **Given** A 设备 10 个订阅, **When** 导出并经华为分享发送至 B 设备, **Then** B 设备收到 JSON 文件
2. **Given** B 设备收到文件, **When** 经「导入订阅」选入, **Then** B 首页出现 10 个源，顺序与 A 一致（sortOrder 字段随文件携带）
3. **Given** B 设备已登录 B 站账号（登录态与 A 不同）, **When** 进入各源详情, **Then** 公开源（up/season/series）正常拉取；fav 源按既有刷新失败路径处理（toast，不阻塞其余源）

---

### User Story 5 - 长按行弹菜单（置顶/排序/删除） (Priority: P1)

长按订阅行弹出菜单，含三项——「置顶」（该源移至列表首位并落盘，幂等）、「排序」（进入 US1 既有整页排序编辑态）、「删除」（弹既有删除确认弹窗，与左滑删除同链路）。同时修复拖拽落子不即时刷新 bug 与补进出编辑态转场动画。

**Why this priority**: 真机实测反馈的交互调整与 bug 修复，直接影响 US1 核心体验。

**Independent Test**: 真机长按行弹菜单；点「排序」进编辑态拖拽落子即时更新且可继续拖拽；点「置顶」行到首位；点「删除」弹确认。

**Acceptance Scenarios**:

1. **Given** 真机正常态, **When** 长按任意订阅行并抬手, **Then** 弹出菜单（置顶/排序/删除）
2. **Given** 菜单, **When** 点「排序」, **Then** 进入排序编辑态（后续拖拽/退出同 US1）
3. **Given** 菜单, **When** 点「置顶」, **Then** 该行移至列表首位并落盘（已在首位则无变化）
4. **Given** 菜单, **When** 点「删除」, **Then** 弹既有删除确认弹窗，确认后删除（与左滑删除同链路）
5. **Given** 编辑态内拖拽落子, **Then** 列表即时显示新顺序且可继续拖拽（FR-014 修复）
6. **Given** 进/出编辑态, **Then** 列表区与标题区带淡入淡出转场（FR-015）

---

### User Story 6 - 长按即时菜单与编辑态动画修正 (Priority: P1)

真机实测反馈：①长按菜单为系统文件管理风格——**按压达成即触发**（不待抬手），长按行同步视觉强调（缩放），菜单从**行上方**展开（非左上角）；②进出排序编辑态转场（FR-015 实施初版真机无感知，根因：TransitionEffect 无 animation 参数且状态翻转不在 animateTo 内时组件直接出现/消失，官方文档明示，FR-017 修正）；③编辑态拖拽把手加大。

**Why this priority**: 真机实测反馈，US5 三处实施的体验修正。

**Independent Test**: 真机长按行（按住不放）菜单即弹出且行缩放强调、菜单从上方展开；进出编辑态可见淡入淡出；编辑态把手明显大于正文图标。

**Acceptance Scenarios**:

1. **Given** 真机正常态, **When** 按压订阅行至长按达成（手指未抬）, **Then** 行缩放强调且菜单即刻弹出（FR-016）
2. **Given** 菜单弹出, **Then** 菜单从行上方展开（首行上方空间不足时系统自动调整，FR-019）
3. **Given** 进/出排序编辑态, **Then** 标题/按钮/列表区可见淡入淡出转场（FR-017 修正）
4. **Given** 编辑态, **Then** 拖拽把手视觉尺寸明显大于上一版（FR-018）

---

### User Story 7 - 置顶动画与编辑态动画对齐多选 (Priority: P1)

真机实测反馈：①置顶无动画——点「置顶」行瞬间跳到首位；②进退排序编辑态动画改用与源详情页多选进出**一致**的动画（animateTo 统一驱动 + transition 交叉淡化，时长曲线与多选完全相同：TOKEN_SELECT_ANIM_MS 300ms + EaseOut）。

**Why this priority**: 真机实测反馈，动画质感对齐。

**Independent Test**: 真机点置顶行平滑飞至首位、其余行补位；进退编辑态动画节奏/时长/曲线与源详情页多选进出一致。

**Acceptance Scenarios**:

1. **Given** 菜单点「置顶」, **Then** 该行动画移至首位、其余行补位让位（FR-020）
2. **Given** 进/出排序编辑态, **Then** 动画与源详情页多选进出动画一致（300ms EaseOut，animateTo 驱动 transition 交叉淡化，FR-021）
3. **Given** 编辑态退出且存在挂起 rebuild, **Then** 补跑 rebuild 不打断退出动画

---

### User Story 8 - 置顶移动语义修复与编辑态行让位动画 (Priority: P1)

真机实测反馈：①置顶表现为「与当前首位行互换位置」而非移动到首位（数据层正确——落盘为移动语义，视觉层错——onDataMove 通知被框架按官方交换语义渲染，两层脱节）；②编辑态进出行内容无让位动画——要求与源详情页多选勾选框同款机制：行内容被平滑挤压给拖拽把手让位（恒挂载组件宽度/透明度动画），把手位置保持在行首。

**Why this priority**: 真机实测反馈，置顶语义正确性（核心数据操作）与编辑态动画质感。

**Independent Test**: 真机连续置顶多条：每条均平滑飞至首位、原首位及途经行依次下移一位（非互换，置顶数量不限）；进编辑态把手从行首平滑长出、行内容平滑右移让位，退出反向；退出编辑态或重启后顺序与置顶/拖拽操作一致。

**Acceptance Scenarios**:

1. **Given** 列表 [A,B,C,D], **When** 置顶 C, **Then** 视觉为 C 飞至首位、A/B 依次下移一位（终序 [C,A,B,D]），非 C 与 A 互换（FR-022）
2. **Given** 已置顶 C 的列表, **When** 再置顶 D, **Then** D 飞至首位、C 及其余行依次下移（终序 [D,C,A,B]，置顶无数量限制）
3. **Given** 进编辑态, **Then** 把手从行首平滑长出（宽度/透明度动画），行内容被平滑挤压让位（FR-023，机制与多选勾选框恒挂载同构）
4. **Given** 出编辑态, **Then** 把手平滑缩回、行内容平滑回位
5. **Given** 正常态行为, **Then** 长按弹菜单/左滑删除/点击导航零回归（onMove 恒绑后正常态长按可能伴随拖拽浮起，真机验证观感）

---

### User Story 9 - 编辑态整行可拖放修复、把手留白对称与把手即按即拖 (Priority: P1)

真机实测反馈：①单 List 合并（US8）后编辑态无法拖动——合并前编辑行（editRowItem）不携带任何行级手势，合并后行级长按手势（长按菜单 LongPressGesture）与 LazyForEach.onMove 系统拖拽同为长按识别、竞争阻塞，拖拽失效；②拖拽把手左右两侧空白要求对称；③拖拽把手要求按下直接进拖拽（免长按等待）——onMove 系统拖拽长按阈值内建不可配（FAQ faqs-arkui-310 明示不支持修改），把手改挂 PanGesture 自定义手动拖拽；④真机复测左缘长按残留误触（根因与修复见 bugfix.md §1），并按用户要求去除把手长按触发——把手挂空 LongPressGesture 认领阻断，把手 pan-only（按住不动无反应；并行仲裁下按住后再移动仍入手写拖拽，无死区）。

**Why this priority**: 真机实测反馈，编辑态拖拽是 US1 核心功能回归，P1 最高优先。

**Independent Test**: 真机进编辑态后长按行任意位置（不限于把手区）即可拖动整行调序；按下把手并移动立即跟手拖拽（无长按等待）；把手图标左右留白视觉对称；正常态长按弹菜单/左滑/导航零回归。

**Acceptance Scenarios**:

1. **Given** 编辑态, **When** 长按行任意位置并拖动, **Then** 整行浮起跟随、可拖至任意位置松手落盘（不限于把手区域）(FR-024)
2. **Given** 编辑态, **Then** 行级正常态交互全部禁用——不弹菜单、不导航、无按压反馈、不可侧滑（触摸穿透给系统拖拽）
3. **Given** 正常态, **Then** 长按弹菜单/左滑删除/点击导航全部照旧（FR-024 闸不影响正常态）
4. **Given** 编辑态, **Then** 拖拽把手图标左右两侧留白对称（FR-025）
5. **Given** 编辑态, **When** 按下把手并移动, **Then** 立即进入拖拽跟随移动（无长按等待），跨行阈值换位带补位动画，松手归位落盘（FR-026）
6. **Given** 编辑态, **When** 按住把手不动, **Then** 无反应不触发系统拖拽（空 LongPressGesture 认领阻断，把手 pan-only）；按住后再移动仍进拖拽跟随，无死区（并行仲裁，FR-026）

---

### Edge Cases

- 原 `bindContextMenu` 长按菜单真机失效根因未查证（候选：与 `swipeAction`/`onTouch` 事件竞争，或 API 26 真机行为差异）——已废弃，新入口 LongPressGesture + 受控 bindMenu 真机验证可用
- 编辑态与懒加载列表共存：拖拽调序需与现有 LazyForEach/IDataSource 数据源协作（数据移动通知正确性）
- 编辑态期间发生静默刷新（rebuild 触发列表重建）：与拖拽中状态冲突时的行为须确定（候选：编辑态期间挂起静默刷新，退出后恢复）
- 拖至顶部即置顶（原菜单置顶废弃），拖至底部同理；单行列表拖拽为无效操作不报错
- 导入文件中 sortOrder 与本机 sortOrder 冲突：新源一律追加本机末尾（max+1），不沿用文件内 sortOrder 绝对值（避免与既有顺序穿插错乱）
- 导入文件为旧版本/字段缺失的合法 JSON：`fromRecord` 逐字段容错语义（undefined 跳过）生效，缺关键字段（id/type）的条目跳过且计入提示
- fav 源跨设备导入后的归属字段（folderOwnerMid/folderOwnerName）随文件携带，对端刷新时无需重新归属回填
- 分享面板在设备无可用分享目标时的系统降级行为（面板为空/仅保存），不属本应用处理范围
- 导出文件与本机 `subscriptions.json` 同构但为独立副本：导出不改动本机数据，导入不删除文件

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 经长按菜单「排序」项 MUST 进入整页列表排序编辑态（真机可用）；原 `bindContextMenu` 长按菜单废弃
- **FR-002**: 编辑态内行 MUST 可拖拽调序，拖动松手即时落盘；退出通道双轨——标题栏「完成」按钮与系统返回（经 BackHandler 链，编辑态优先消费返回）均回正常态
- **FR-003**: 排序落盘后应用重启顺序 MUST 保持一致
- **FR-004**: 正常态既有交互（左滑删除、点击进源详情、新集徽标）MUST 零回归
- **FR-005**: 系统 MUST 支持将全部订阅导出为 JSON 文件并经系统分享面板发出；文件内容与内部订阅存储同构（`Subscription` 全字段）
- **FR-006**: 系统 MUST 支持经文档选择器选入 JSON 文件导入订阅，按源 id 去重合并（已存在跳过），结果提示新增/跳过数量
- **FR-007**: 导入 MUST 校验文件合法性（JSON 可解析、含 items、条目含 id/type）；非法文件明确报错且现有订阅数据零改动
- **FR-008**: 导入新增的源 MUST 自动触发一次刷新（拉取封面与剧集），刷新失败不阻塞导入结果
- **FR-009**: 导入的新源 sortOrder MUST 追加至本机列表末尾，不破坏本机既有顺序
- **FR-010**: 跨设备链路（导出→分享→对端导入）MUST 端到端可用；sortOrder 随文件携带使对端顺序与源设备一致
- **FR-011**: 空订阅列表导出 MUST 给出明确提示而非发送空文件
- **FR-012**: 长按订阅行 MUST 弹出菜单，含「置顶」「排序」「删除」三项；菜单项点击后菜单关闭
- **FR-013**: 置顶 MUST 将该源移至列表首位（sortOrder 归一化落盘，幂等——已在首位无变化）
- **FR-014（bug 修复）**: 编辑态拖拽落子后列表 MUST 即时反映新顺序且可继续拖拽——`LazyForEach.onMove` 场景修改数据源不得经 `DataChangeListener.onDataMove` 通知（官方文档：onMove 回调内修改数据源无需通知，额外通知致框架缓存二次移动）
- **FR-015**: 进出排序编辑态 MUST 带转场动画（淡入淡出，含列表区与标题区）
- **FR-016**: 长按达成（按压中，不待抬手）MUST 即刻弹出菜单，长按行同步缩放强调，行为对齐系统文件管理；按压行（pressedKey 态）带浮起阴影（复用悬浮件阴影令牌 TOKEN_FLOATING_SHADOW_* + shadow_ball 色），松开消失
- **FR-017（修正 FR-015）**: 编辑态进出转场 MUST 可见——TransitionEffect 须显式携带 animation 时长参数（官方文档：无 animateTo 触发且无 animation 参数时组件直接出现/消失，即无动画）
- **FR-018**: 编辑态拖拽把手 MUST 视觉尺寸加大（字号与占位区域均大于上一版）
- **FR-019**: 长按菜单 MUST 从行上方展开（placement: Top），非左上角
- **FR-020**: 置顶 MUST 带列表补位动画——行动画移至首位、其余行让位补位（animateTo 包数据变化 + DataChangeListener.onDataMove 通知驱动），非瞬间跳位
- **FR-021**: 进退排序编辑态动画 MUST 与源详情页多选进出动画一致——enterEditMode/exitEditMode 以 animateTo({ duration: TOKEN_SELECT_ANIM_MS, curve: EaseOut }) 驱动 editMode 翻转，7 处 transition 交叉淡化不带自带 animation 参数（参数统一由 animateTo 供给，与 SourcePage 多选实现同构）
- **FR-022**: 置顶 MUST 表现为移动语义——被置顶行飞至首位、原首位及途经行依次下移一位，非与首位互换（根因：onDataMove 官方注释为 swap 语义「swapped between the from and to positions」，FR-020 实施误作移动语义致视觉与数据脱节）；修复为相邻交换冒泡通知序列（onDataMove(idx, idx-1)…onDataMove(1, 0)，同一 animateTo 内），数据层 unshift 不变，置顶数量不限
- **FR-023**: 编辑态行内容 MUST 平滑让位给拖拽把手——编辑/正常双 List 分支合并为单 List（onMove 恒绑），拖拽把手恒挂载行首（宽度 0↔把手宽 + 透明度 0↔1 随 editMode 联动，机制与 SelectCheckbox 完全同构），行内容 layoutWeight 真实让位（非位移遮盖），动画由 enterEditMode/exitEditMode 既有 animateTo 驱动
- **FR-024**: 编辑态整行 MUST 可拖放且带按压反馈——行级长按手势与 LazyForEach.onMove 系统拖拽同为长按识别、竞争阻塞拖拽（US8 单 List 合并引入的回归）；修复路径迭代：第一版 `.enabled(!editMode)` 全禁（拖拽修复、按压反馈被连带禁掉）；第二版 parallelGesture 并行挂载（按压反馈恢复、拖拽回归，真机验证失败已回退）；第三版（当前）：`.enabled(!editMode)` 恢复 + LongPressGesture 恢复 `.gesture()` + onTouch 按压链移至 ListItem 恒挂——编辑态触摸穿透行落到父级 ListItem 驱动 pressedKey（按压背景+阴影照常），onTouch 纯监听不参与手势仲裁不阻塞拖拽；onClick 闸 `editMode || menuKey !== ''` 保留（二版副作用补丁，回退后无害）。正常态交互全保留。回退条件：编辑态 ListItem.onTouch 收不到穿透触摸或拖拽仍回归 → 纯回退第一版（编辑态按压反馈放弃）
- **FR-025**: 拖拽把手图标左右两侧留白 MUST 对称（视觉一致性微调）
- **FR-026**: 编辑态拖拽把手 MUST 支持按下即拖（免长按等待）——把手挂 PanGesture（Vertical）自定义手动拖拽：按下移动即进入拖拽（被拖行 translate 跟手，累积位移跨换位阈值即与相邻行交换——subs splice 相邻互换 + 单发 onDataMove 补位动画），松手 settle 归位动画 + sortOrder 归一化落盘；触把手按住不动无反应（空 LongPressGesture 认领阻断 List 内建长按，把手 pan-only），并行仲裁下按住后再移动仍 MUST 进拖拽跟随（无死区）；把手手动拖拽进行中系统 onMove 落子 MUST 被闸拒（双路径互斥）；换位阈值入 Constants（行高统一前提下的常量）

### Key Entities

- **导出文件（JSON）**: 与 `subscriptions.json` 同构——`{ items: [Subscription 记录] }`；四类源（up/fav/season/series）统一承载，含 folderOwner 归属字段与 sortOrder
- **Subscription（既有，无结构变更）**: 排序仅操作既有 sortOrder 字段；导入导出复用既有 toRecord/fromRecord 序列化语义

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 真机长按订阅行进入编辑态触发率 100%（新入口真机验证）
- **SC-002**: 拖拽排序落盘后杀进程重启，顺序 100% 保持
- **SC-003**: 双设备端到端：A 导出 → 分享 → B 导入，B 订阅列表与 A 完全对齐（数量、顺序一致）
- **SC-004**: 同一导出文件重复导入幂等：第二次导入新增 0，现有列表零变化
- **SC-005**: 非法文件导入尝试后，现有订阅数据 100% 完好

## Assumptions

- 导入导出入口设于设置页新增「订阅管理」分组（具体交互布局 plan 轮定）
- 导出格式与内部存储同构（全字段直出），不引入 OPML 等外部格式（用户已确认）
- 跨设备为文件分享式；WebDAV 同步登记为后续轮次候选需求（用户已确认），本轮出范围
- 分享面板拉起经系统分享能力，具体 Kit 选型 plan 轮查证
- 对端设备各有各的 B 站登录态；fav 源刷新依赖对端自身登录，失败走既有失败路径
- 本轮为规划轮：产出 spec/plan/tasks 三工件，不实施代码

## Open Questions

（全部闭合）

- 原长按菜单真机失效根因（`bindContextMenu` 事件竞争 vs 真机 API 26 行为差异）——已绕开：`bindContextMenu` 废弃，新入口 LongPressGesture + 受控 bindMenu 真机验证可用（失效根因未深究，不再阻塞）
- 系统分享面板的文件分享通道在 API 26 的可用形态——已定：`@kit.ShareKit` systemShare（plan D6），真机分享面板拉起验证通过
- 拖拽排序与 LazyForEach/IDataSource 的协作机制——已定：`LazyForEach.onMove` 恒绑 + editMode 闸（plan D21），落子静默重排（plan D12）
