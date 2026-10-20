# Feature Specification: v0.5-part4（风控对抗：刷新止血 + 过墙实验 + 刷新反馈）

**Status**: Draft
**Input**: User description: "应用侧 WBI 被风控拦截（-403/-799）+ 客户端行为自我放大；给首页刷新加cd；刷新结果要通知告诉用户；过墙单方案实验"

## Overview

应用侧 Web 补稠链（WBI+plain）被 B 站风控拦截；且客户端刷新行为存在自我放大：每次冷启动静默全刷、被拦时 6 连失败、每轮重试换新 buvid（零信任+爬虫特征）。本轮三条线：①止血——刷新行为去放大（首页刷新 CD、Web 失败冷却、buvid 身份稳定、空 buvid 修复）+ 刷新结果用户可感知；②过墙——WBI 传输栈单方案实验（rcp）验证客户端层拦截假设；③验证——真机终态判定与登记。

**已核实事实**（代码读证，本轮事实基础）：

- 空 buvid 重试轮：`resetBuvid()` 清空后无人补取（`ensureBuvid()` 只挂 `fetchMixinKeyUncached()`/启动 init/登录动作三处；mixinKey 按日缓存命中即跳过）——第 2/3 轮重试空 buvid 裸打
- 失败不续 TTL：`persistRefreshedSub(ok=false)` 不写 `lastRefreshAt`——失败源永远 stale，每轮冷启动重新进刷新名单
- 冷启动全刷链路：`HomePage.aboutToAppear → silentRefresh() → refreshAll()`（各源 15min TTL 内跳过）

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 首页刷新冷却 (Priority: P1) 🎯 MVP

首页冷启动静默刷新加跨启动持久化冷却（CD）：CD 时间内启动 app 直接读缓存，不触发任何订阅网络刷新；CD 过期恢复正常静默刷新。

**Why this priority**: 反复开关 app 是失败风暴放大器（实测：每次冷启动全量重试）；进程级冷却挡不住杀进程重开，必须跨启动持久化。

**Independent Test**: 刷新成功后立刻杀进程重开，CD 内启动零订阅刷新请求、页面正常出缓存数据。

**Acceptance Scenarios**:

1. **Given** 订阅刚刷新成功，**When** CD 内冷启动 app，**Then** 直接读缓存渲染，零网络刷新请求
2. **Given** 距上次刷新超过 CD，**When** 冷启动，**Then** 正常触发静默刷新
3. **Given** CD 生效中，**When** 用户手动刷新某订阅，**Then** 不受 CD 限制照常执行

---

### User Story 2 - Web 链失败止血 (Priority: P1)

Web 补稠链被风控拦截后进入冷却：冷却期内刷新只走 APP 签名链，不再每次 6 连失败；重试不再每轮换 buvid、不再空 buvid 裸打。

**Why this priority**: 当前被拦时每次刷新 6 次失败请求（间隔 ~46ms）+ 每轮换新 buvid，是恶化风控的自我放大源。

**Independent Test**: 被拦状态下连续刷新数次，失败请求从 6 次/轮降为 0 次/轮，数据仍正常出（APP 链）。

**Acceptance Scenarios**:

1. **Given** WBI/plain 均被拦（-403/-799），**When** 刷新订阅，**Then** 本轮走 APP 链后 Web 链进入冷却，不再连续重试
2. **Given** Web 链冷却中，**When** 再次刷新，**Then** 跳过 Web 补稠只走 APP 链
3. **Given** 重试发生，**When** 观察请求，**Then** buvid 全程非空且身份不变（不换新）

---

### User Story 3 - 刷新结果通知 (Priority: P2)

刷新结果用户可感知：手动刷新结束 toast 结果（成功/失败+原因）；首页静默刷新失败也 toast；CD 跳过刷新不提示。

**Why this priority**: 刷新结果当前完全无感知，被拦期用户不知道「数据没更新」；复用既有 toast 通路成本低。

**Independent Test**: 手动刷新一次看成功/失败 toast；断网时冷启动看静默刷新失败 toast。

**Acceptance Scenarios**:

1. **Given** 手动刷新成功，**When** 刷新完成，**Then** toast 提示已更新
2. **Given** 手动/静默刷新失败（网络错误/被拦截），**When** 刷新结束，**Then** toast 带失败原因
3. **Given** CD 内启动跳过刷新，**When** 冷启动完成，**Then** 无任何提示（无感是设计意图）
4. **Given** 多源连续失败，**When** 刷新结束，**Then** 不弹一串 toast（复用时间窗去重）

---

### User Story 4 - 过墙实验（单方案） (Priority: P2)（已移出：见 spec/charging-archive.md）

### Edge Cases

- 时钟回拨/跨天：CD 判定不得因系统时间篡改导致永久生效或永久失效
- Web 冷却（进程级）与首页 CD（持久化）叠加：杀进程重开后 Web 冷却丢失，由首页 CD 兜底防风暴
- APP 链也失败（断网）：通知报网络错误，缓存数据保持可用（失效安全）
- 手动刷新进行中再次点击：维持既有 refreshing 并发防抖，不叠加请求

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 首页冷启动静默刷新 MUST 有跨启动持久化冷却；冷却期内启动 MUST NOT 触发订阅网络刷新（读缓存渲染）
- **FR-002**: 手动刷新（订阅详情 ···→刷新）MUST NOT 受 CD 限制（用户主动意图，维持现有并发防抖）
- **FR-003**: Web 补稠链（WBI+plain）被风控拦截后 MUST 进入冷却；冷却期内刷新 MUST 跳过 Web 补稠只走 APP 签名链
- **FR-004**: Web 链失败重试 MUST NOT 重置/轮换 buvid；所有请求 MUST NOT 出现空 buvid（含重试轮——当前第 2/3 轮空 buvid 裸打为已核实缺陷）
- **FR-005**: 手动刷新结束 MUST toast 结果（成功提示已更新 / 失败带原因）
- **FR-006**: 首页静默刷新失败 MUST toast（复用时间窗去重）；CD 跳过 MUST NOT 提示
- **FR-007**: 过墙实验 MUST 先做前置检查（rcp 与 `@ohos.net.http` TLS 栈异同）；同栈无差异可试则登记后按失败分支收尾
- **FR-008**:（已移出：见 spec/charging-archive.md）
- **FR-009**: 全程 APP 签名链供数 MUST 无行为回归（红线——四类源数据可用性不因本轮改动受损）

### Key Entities *(include if feature involves data)*

- **刷新冷却状态**：首页静默刷新最近执行时间戳（持久化，跨启动判定 CD）
- **Web 链冷却状态**：Web 补稠冷却截止（进程级，被拦后置位）
- **刷新结果事件**：刷新来源（手动/静默）、结果（成功/失败+原因），供通知消费

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: CD 内（同 TTL 档时长）重复冷启动，订阅刷新网络请求为零
- **SC-002**: 被拦状态下单次刷新失败请求 6→0（Web 冷却生效后）
- **SC-003**: 重试全程 buvid 非空且身份不变
- **SC-004**: 手动刷新 100% 有结果 toast；CD 跳过零 toast；连续失败不弹串
- **SC-005**:（已移出：见 spec/charging-archive.md）

## Assumptions

- 冷却时长与订阅 TTL 同档（15min 量级，具体数值 Constants 统一令牌）
- Web 链冷却为进程级；杀进程场景由首页 CD（持久化）兜底
- buvid 保身份策略：被拦后换新身份反效果（判别实验佐证——IP/账号/手机已排除，嫌疑在客户端层）
- rcp 实验范围仅 WBI/plain Web 链，不动 APP 签名链与取流链（项目已有 rcp 用法：`LinkResolver` 短链解析）
- 刷新通知复用 part3 US6 已有 toast 通路与时间窗去重模式
- 冷却可逆性观察项：-403/-799 是否随止血自然恢复，后续单发验证（登记不阻塞本轮）

## Open Questions

无——scope 决策已全部确认：CD 只限首页刷新（手动不加）；过墙单方案实验（失败登记收尾）；通知覆盖手动+静默失败（CD 跳过不提示）。
