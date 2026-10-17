# Feature Specification: v0.5 功能多P 适配（v0.5-part1-multi-part-adapt）

**Created**: 2026-10-14  
**Status**: Draft  
**Input**: User description: "v0.4版本做了对多p视频的适配，v0.5所有的功能准备适配一下"（经方案确认：以 master 多P 基线为底本移植 v0.5 增量；云端续播多P 语义取严格 cid 匹配；完成验证后合并进主分支；分P 功能第二轮修订后重新评估可行性——已确认纯展示层追加，零新增冲突面）

## Overview

master 已落地两轮多P 支持（复合键队列/历史、分P 展开、历史归并行、队列分组头），而 v0.5（Pre-update 分支：播放进度云端同步 + 订阅详情页重写）基于多P 适配之前的基线开发，其历史/队列实现停留在 bvid 粒度、云端续播无分P 归属校验。本轮把 v0.5 全部功能移植到 master 多P 基线上并完成多P 语义适配：身份体系一律保 master 复合键版，云端续播按「last_play_cid 严格匹配起播分P」合并，心跳/完播上报按发送时刻分P 归属，详情页剧集行视觉与分P 展开行为手工融合。验证通过后合并进主分支，Pre-update 归档。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 心跳上报按分P 归属正确 (Priority: P1)

登录用户收听多P 视频：心跳上报（5s 节拍 + 暂停/切分P 补报 + 连败熔断）的 cid 与进度始终属于「正在播放的那个分P」；切分P 即切换心跳语境（水位、熔断计数随分P 复位），不同分P 的上报互不串台。单P 视频行为与 v0.5 原实现一致。

**Why this priority**: 心跳是云端进度同步的上行根基；cid 归属错会让 B 站云端历史记错分P，后续所有续播功能随之失效。

**Independent Test**: 登录态连续收听同一视频 P1→P2，抓包/网页端历史核对：云端历史条目落在对应分P，P1 进度停在切走时刻、P2 从头累计。

**Acceptance Scenarios**:

1. **Given** 登录且历史同步开关开，**When** P1 播放中，**Then** 心跳以 P1 的 cid/进度上报
2. **Given** P1 播放中切到 P2，**When** 心跳节拍触发，**Then** 上报 cid 为 P2、进度从 0 起计，P1 水位与熔断计数不复用于 P2
3. **Given** 未登录或开关关，**When** 任意分P 播放，**Then** 零上报请求（总开关语义不变）
4. **Given** 单P 视频播放，**When** 心跳触发，**Then** 行为与 Pre-update 版一致（回归约束）

---

### User Story 2 - 云端续播严格匹配分P (Priority: P1)

登录用户起播一个分P 时，云端进度仅在「云端记录的分P 与起播分P 一致」时参与合并：起点 = max(本地断点, 云端进度)；不一致时忽略云端，回退纯本地续播。云端进度越过该分P 完播阈值（95%）时从头播；本地已听完（-1）时从头播。`last_play_cid` 无效（≤0/缺失）视为无云端数据。

**Why this priority**: v0.5 原实现无分P 归属校验——云端在 P3 的 300s 进度会把起播的 P1 直接拉到 300s，多P 场景续播起点错位是本轮最核心的行为缺口。

**Independent Test**: 云端（网页端）把某 4P 视频看到 P3 一半，App 点播该视频 P1：P1 从头/本地断点播（不跳 300s）；点播 P3：从云端进度续播。

**Acceptance Scenarios**:

1. **Given** 云端进度属于 P3（last_play_cid=P3），**When** App 起播 P1，**Then** 忽略云端进度，P1 从本地断点或从头播
2. **Given** 云端进度属于 P3，**When** App 起播 P3，**Then** 起点 = max(本地 P3 断点, 云端进度)
3. **Given** 云端进度 ≥ 分P 时长 95%，**When** 起播该分P，**Then** 从头播（云端完播防护保留）
4. **Given** 本地该分P 已听完（-1），**When** 起播，**Then** 从头播（本地完播优先语义保留）
5. **Given** `last_play_cid` ≤0 或缺失（匿名/旧数据），**When** 起播任意分P，**Then** 不合并云端进度，行为与无云端数据一致

---

### User Story 3 - 分P 完播同步 (Priority: P2)

分P 自然完播或达到 95% 阈值时，向云端上报该分P 的完播信号（played_time=-1，cid 为该分P）；重播该分P 从头播且水位复位（-1→0 语义保留），其他分P 不受影响。

**Why this priority**: 完播信号驱动 B 站云端「已看完」标记；多P 下若报错 cid 会让云端错误标记其他分P 已看完。

**Independent Test**: 听完 P1（自然完播），网页端历史显示 P1 为已看完；重新播放 P1 从头开始。

**Acceptance Scenarios**:

1. **Given** P1 播放至自然完播，**When** 完播事件触发，**Then** 以 P1 的 cid 上报 -1
2. **Given** P1 已上报完播，**When** 重新播放 P1，**Then** 从头播且心跳水位复位，P2/P3 等其他分P 状态不受影响
3. **Given** 未登录或开关关，**When** 完播，**Then** 零上报（仅本地完播语义）

---

### User Story 4 - 历史同步开关 (Priority: P2)

设置页「历史同步」开关行随 v0.5 移植：登录条目下方展示，未登录隐藏，默认开。开关关闭时心跳、完播上报、云端续播读取全部静默跳过；打开后恢复。

**Why this priority**: 用户对云端上报的控制入口，随移植自然落地，无多P 特有语义。

**Independent Test**: 关闭开关后播放多P 视频，无任何上报请求且续播纯本地；打开后恢复上报与云端合并。

**Acceptance Scenarios**:

1. **Given** 已登录，**When** 查看设置页，**Then** 「历史同步」开关行出现在登录条目下方
2. **Given** 未登录，**When** 查看设置页，**Then** 开关行隐藏
3. **Given** 开关关，**When** 播放/完播/起播，**Then** 零上报零云端合并（纯本地）

---

### User Story 5 - 详情页剧集行视觉与分P 展开融合 (Priority: P2)

订阅详情页剧集行取 Pre-update 的视觉结构（16:9 封面缩略 + 时长半透明角标 + 标题/日期/NEW/已播收敛文字区），点播/播放全部行为取 master 的分P 展开（点播多P 视频展开全部分P 入队不打断、播放全部按 detail.parts 展开）。列表行保持视频级展示，头部/路由/数据流零改动。

**Why this priority**: 两分支对 SourcePage 各自大改（视觉重排 vs 分P 展开），必须手工融合；视觉与行为都是用户已验收过的定案，融合不得引入回归。

**Independent Test**: 打开含多P 视频的订阅详情页：剧集行为新视觉形态；点播多P 视频行，队列展开全部分P 且不打断当前播放；播放全部行为与 master 版一致。

**Acceptance Scenarios**:

1. **Given** 订阅详情页含多P 视频，**When** 查看，**Then** 剧集行为 16:9 封面 + 时长角标新视觉（含 Pre-update 的边界处理：无封面占位、无时长不渲染角标）
2. **Given** 剧集行为多P 视频，**When** 点播，**Then** 全部分P 追加入队、不打断当前播放（master 行为）
3. **Given** 任意订阅源，**When** 播放全部，**Then** 按 master 版分P 展开语义执行
4. **Given** 页面头部（封面信息行）/路由/数据流，**When** 融合后，**Then** 与 master 版零差异（回归约束）

---

### User Story 6 - 单P 与旧数据全链路回归不变 (Priority: P1)

单P 视频在识别/入队/播放/心跳/续播/完播/历史/UI 全链路行为与移植前一致；改造前的旧持久化数据（无分P 字段的历史/队列条目）视为 P1，读取/续播/上报不崩溃不丢数据。

**Why this priority**: 回归红线——本轮是「移植 + 适配」，不是行为重定义；单P 视频占绝大多数使用场景。

**Independent Test**: 单P 视频完整走一遍播放/中断/续播/完播/重播流程，行为与 master（多P 版）一致；含旧数据的持久化文件升级后正常加载。

**Acceptance Scenarios**:

1. **Given** 单P 视频，**When** 完整收听流程（起播/续播/完播/重播），**Then** 行为与移植前 master 一致
2. **Given** 旧历史/队列持久化数据（无 page/cid 字段），**When** 加载与播放，**Then** 按 P1 处理，不崩溃不丢失
3. **Given** Pre-update 版历史实现（bvid 粒度 upsert），**When** 移植，**Then** 该实现不进入 master——历史存储/续播/已播判定/shuffle 轨迹一律保 master 复合键版

---

### Edge Cases

- **云端 last_play_cid 无效**（≤0、缺失、匿名态）：视为无云端数据，不合并，回退本地续播
- **云端 last_play_time 为 0**（未产生云端进度）：不合并（等价于无云端数据）
- **心跳网络失败**：连败熔断本集（本分P），成功清零，全程静默（v0.5 语义原样移植）
- **快速切分P**：心跳取发送时刻 bvid/cid/进度快照，慢响应不串台（v0.5 防串台设计保留）
- **分P 完播后自动连播下一分P**：完播上报按各自分P cid 独立执行，互不影响
- **开关关闭 + 多P**：零上报零云读，与单P 语义一致
- **SourcePage 融合边界**：无封面/无时长/超长标题按 Pre-update 边界处理；触底加载行/空态辅助行不套用新视觉

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 以 master 多P 基线为底本移植 v0.5 功能：历史存储/续播查询/已播判定/队列身份/shuffle 轨迹一律保持复合键（bvid+page）实现，Pre-update 的 bvid 粒度实现不得进入 master
- **FR-002**: 心跳/完播上报 MUST 按发送时刻分P 归属（cid 快照）：切分P 即复位水位与熔断计数，跨分P 不串台；总开关（已登录 + KEY_HISTORY_SYNC）覆盖全部上行
- **FR-003**: 云端续播 MUST 严格匹配分P：仅当云端 last_play_cid 与起播分P cid 一致时合并 max(本地断点, 云端进度)；不一致或云端 cid 无效时忽略云端；云端完播阈值防护与本地 -1 完播优先语义保留
- **FR-004**: 取流响应 MUST 同时解析 last_play_time 与 last_play_cid 并透出至音频解析结果（零新增请求），两条取流链路（DASH/DURL）均覆盖
- **FR-005**: 设置页 MUST 提供「历史同步」开关行（登录条目下方、未登录隐藏、默认开），关闭时上行与云端续播读取全部静默跳过
- **FR-006**: 订阅详情页剧集行 MUST 取 Pre-update 视觉结构（16:9 封面缩略 + 时长角标 + 收敛文字区），点播/播放全部分P 展开行为 MUST 与 master 版一致；页面头部/路由/数据流零改动
- **FR-007**: 单P 视频全链路与旧持久化数据行为 MUST 与移植前 master 一致（回归约束）
- **FR-008**: 本轮实施 MUST 在从 master 切出的新工作分支（复用 Pre-update 名字）上进行：实施前旧 Pre-update 改名 Pre-update-legacy 归档（移植源保留），实施期间 master 与 Pre-update-legacy 均不动；新 Pre-update 是否/何时合回 master 在验证完成后由用户拍板

### Key Entities

- **分P 进度快照（心跳语境）**: 当前分P 的 bvid/cid/已播秒数/连败计数/水位，随切分P 整体复位重建
- **云端续播数据**: last_play_time（秒）+ last_play_cid（分P 归属），随取流响应零成本获得，仅严格匹配时参与合并
- **历史同步开关**: 持久化偏好（KEY_HISTORY_SYNC，默认开），门控全部上行与云端读取

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 构建通过 + 模拟器部署启动成功 + UI 验证通过（验证范围 build+ui：本轮非登录交互 + 多P 第二轮 UI（历史归并行/队列分组头）顺带回归；登录态云端可见性不在本轮范围）
- **SC-002**: 代码级不变式自检通过：历史 upsert/续播/已播/shuffle 全部复合键；心跳 cid 为发送时刻分P 快照；Pre-update 的 bvid 粒度实现零残留
- **SC-003**: 云端续播合并仅在 last_play_cid 匹配时发生（代码审查可证），不匹配路径回退本地
- **SC-004**: 工作分支最终同时包含多P 全部能力与 v0.5 全部功能（进度云端同步 + 详情页新视觉），单P/旧数据回归不变；合回 master 时机验证后由用户定
- **SC-005**: 需用户后续真机自查的事项（如有）在轮次结束总结中集中输出，不写 PROJECT_NOTES（用户指示）

## Assumptions

- 基线为 master（多P 两轮已交付）；Pre-update 仅作移植源参考，其 bvid 粒度历史实现不采用
- 云端续播多P 语义取「严格 cid 匹配」为定案；last_play_cid=0/缺失视为无云端数据（匿名探测已证实字段存在，登录态语义登记真机验证）
- 心跳端点与参数沿用 v0.5 实测结论（web heartbeat，type=3，5s 节拍 + 补报 + 熔断）
- 实施在新工作分支 Pre-update（复用原分支名，自 master 多P 基线切出）进行：实施前旧 Pre-update 改名 Pre-update-legacy 归档（移植源保留）；master 实施期间不动；验证通过后是否/何时合回 master 由用户拍板
- 验证范围 build+ui（用户显式提出）：UI 验证覆盖本轮非登录交互，并顺带回归多P 第二轮 UI（历史归并行/队列分组头）；登录态云端可见性（心跳网页端显示等）不在本轮任务范围，需用户后续自查的事项在轮次结束总结集中输出（不登记 PROJECT_NOTES，用户指示）
- 不做：云端历史列表下行、URL t 参数、分组头计数/角标（各轮既有遗留）、版本号 bump

## Open Questions

- last_play_cid 在登录态的取值形态（是否恒等于云端最后播放分P 的 cid、单P 视频是否返回）需真机登录态抓包确认——匿名已证实字段存在（值 0），已按「无效即忽略」设计，不影响实施
- 多P 视频在 B 站网页端历史的展示粒度（分P 级 or 视频级归并）影响跨端体验核对口径，真机验证时一并确认
