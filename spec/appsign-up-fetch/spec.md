# Feature Specification: UP 投稿 APP 端点 AppSign 签名接入（游客身份）

**Created**: 2026-10-08  
**Status**: Draft  
**Input**: 用户确认执行调研结论（§7.1 主线 + §7.2 前置部分）："将推荐项目做了吧"。三项已拍板决策：游客签名先行（无 access_key）、仅覆盖 UP 投稿端点、endArmed 本轮保留。

## Overview

UP 投稿取链的 APP 端点（app.bilibili.com 投稿 cursor 端点）目前无签名裸调恒 -400，实际取数全靠 Web 三轮 buvid 退避链——一页最多 6 个请求，风控期极脆弱。本功能给 APP 端点补 AppSign 客户端签名（游客身份，不引入登录流），使其单请求即可取一页；翻页适配该端点原生的 cursor 语义；任何失败自动降级回现有 Web 退避链。触底触发机制（endArmed）本轮不动。另有一项遗留验证并入本轮真机验证：US9 日志落盘修复（已提交 `5e4ee5a`）的生效确认。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 进页/刷新经 APP 签名链取到投稿列表 (Priority: P1)

用户打开 UP 订阅源详情页（或冷启动订阅刷新），该 UP 的投稿列表经 APP 签名链一次请求返回并正常显示。

**Why this priority**: 这是"签名修复 -400"的最小验证切片，也是全部收益（一页一请求、抗风控）的载体；不依赖翻页改造即可独立交付价值。

**Independent Test**: 真机打开一个已订阅 UP 的源页，网络日志显示 APP 签名链一次请求成功、Web 退避链未触发。

**Acceptance Scenarios**:

1. **Given** 已订阅某 UP，**When** 进入其源页或触发刷新，**Then** 投稿列表正常显示，网络日志显示 APP 签名链一次请求成功（无 -400）
2. **Given** 未登录状态（游客），**When** 同上，**Then** 同样成功——签名链不依赖登录态

---

### User Story 2 - 触底翻旧页经 cursor 语义连续翻页 (Priority: P2)

用户在源页触底加载更早投稿，APP 链以 cursor 锚点（末条 aid + 服务端游标）翻页，页间无重叠、无跳空。

**Why this priority**: cursor 是该端点的原生分页方式，不做则 APP 链只能取首页；同时天然消除 pn 翻页的排序漂移与去重负担。

**Independent Test**: 真机源页连续触底 3 次以上，追加条目按 bvid 无重复、时间序连续。

**Acceptance Scenarios**:

1. **Given** 源页已显示近期列表（APP 链取得），**When** 触底加载，**Then** 追加更早投稿且无重复条目
2. **Given** 连续多次触底，**Then** 每次衔接连续（上一页末条与下一页首条无重叠无跳空）

---

### User Story 3 - APP 链失败自动降级 Web 链 (Priority: P2)

游客签名被风控（如 -352/-412）或网络异常时，自动落回现有 Web 三轮退避链，用户无感知。

**Why this priority**: 降级保底是敢切新链的前提；游客身份未经验证，Web 链是本轮的保险丝。

**Independent Test**: 构造 APP 链失败（断网重连/风控期），刷新与翻页仍能经 Web 链取数成功。

**Acceptance Scenarios**:

1. **Given** APP 签名链失败，**When** 刷新或触底翻页，**Then** Web 退避链接管并取数成功，界面无错误提示
2. **Given** APP 链失败后继续触底，**Then** 翻页仍按现有 Web 链行为工作（现状不回退）

---

### Edge Cases

- 游客签名返回风控码（-352/-412 等）→ 记日志后降级 Web 链（Web 链已有 buvid 重置退避）
- APP 端点返回业务致命码（-404 UP 不存在等）→ 与现状语义一致：仍降级 Web 链，由 Web 链给出最终错误
- cursor 响应形态异常（缺游标/缺 aid）→ 当页数据可用则用；翻页终止按"无更多"处理并记日志
- APP 链返回短页（不足一页）→ **以 `has_next` 为主信号**：`has_next==false` 或空页才判到底（收回继续加载资格）；`has_next==true` 的短页正常续翻——防服务端钳制 ps（如上限 20）导致每页假到底（Phase 2 D6 修订，2026-10-08 确认）。Web 链保持现状短页语义
- 游客签名与 Web 链全败 → 按现有错误提示路径呈现（不新增错误形态）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 提供 AppSign 签名能力：参数按 key 排序、附加 appkey 与实时 ts、拼接 appsec 后取 md5 得 sign；TV 端 appkey/appsec 常量 MUST 定义于 Constants（唯一真相源，禁止散落）
- **FR-002**: UP 投稿 APP 端点的所有请求 MUST 携带签名参数（游客身份，不携带 access_key）；签名 MUST 按请求实时生成、不缓存
- **FR-003**: 系统 MUST 支持 APP 端点的 cursor 分页语义：首页无锚点，后续页携带上一页末条 aid 与服务端返回的游标；上层翻页状态 MUST 统一管理 cursor（APP 链）与页号（Web 降级链）两套语义，页面层不感知链路差异
- **FR-004**: APP 签名链任何失败（网络/风控/业务码/解析）MUST 记日志后自动降级现有 Web 三轮退避链；Web 链行为与现状完全一致，不做任何修改
- **FR-005**: 触底触发机制（endArmed 手势触发权、canLoadOlder 初始准入、loadingOlder 并发护栏）MUST 保持现状不动。**后续安排**：若本轮真机验证证实游客签名链可靠可用，endArmed 及"失败不归还"惩罚在**下一轮**删除（§7.2 连带简化，回退 loadingOlder + canLoadOlder 两道门槛）；验证不通过则无限期保留——Web 降级链仍是保命路径，endArmed 是该路径防 onReachEnd 每帧重触发×6 请求退避链的 403 风暴刚需
- **FR-006**: APP 签名链的成功/降级 MUST 记录网络日志（现有 Logger），日志条目足以区分"APP 签名链成功 / 降级 Web 链"
- **FR-007**: 合集/系列、收藏夹取链 MUST 不受任何影响

### Key Entities *(include if feature involves data)*

- **AppSign 签名参数组**: appkey、ts、sign——随请求生成，不持久化
- **翻页游标状态**: 末条视频 aid + 服务端游标（APP 链）；页号（Web 降级链）——两者在取链层统一为对上层透明的翻页状态

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 真机对至少一个已订阅 UP 验证：进页/刷新经 APP 签名链返回业务成功（code=0），-400 消失
- **SC-002**: APP 签名链成功时，取一页的网络请求数恰好 1 个（日志可数）
- **SC-003**: APP 链被人为致失败时，100% 自动降级 Web 链且最终取数成功，无用户可见错误
- **SC-004**: 连续触底翻页 3 次以上，追加条目按 bvid 无重复
- **SC-005**: 真机验证顺带确认 US9 日志落盘修复生效：日志文件非 0 字节、hilog 无落盘失败告警（修复已提交 `5e4ee5a`，验证并入本轮）

## Assumptions

- **游客身份可通过 TV appkey 签名调用该端点**——未证实假设，正是本轮真机验证的目标；失败则降级链兜底，登录流（TV QR）明确不在本轮范围
- 仅覆盖 UP 投稿端点（已确认）；合集/系列继续走 Web 链
- endArmed 保留（已确认），其简化推迟至 APP 链验证可用后的下一轮
- 订阅刷新与源页触底翻页共用取链实现，签名链对两者同时生效，无需分别接入
- 参考实现（PiliPlus `lib/utils/app_sign.dart` 与 `spaceArchive` 调用形态）的签名算法与参数形态可直接移植
- SC-005 的 US9 验证若发现落盘仍不生效（存在未知第三根因），倾向本轮顺路返修，以实际发现为准

## Open Questions

- cursor 端点的确切请求/响应字段形态（翻旧页锚点参数名、has_next/游标字段位置）需在 Phase 2 对照参考实现确定，必要时以真机首次请求的响应实测为准
- 游客签名若被持续风控（非偶发），本轮结论如何记录与提示（降级链已兜底功能，但"AppSign 可用"的验证结论会推迟）——以真机验证结果为准
