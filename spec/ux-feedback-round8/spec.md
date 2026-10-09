# Feature Specification: UX 反馈第 8 轮（R8）——Debug 模式门控 Logger 双写与工程债修复

**Created**: 2026-10-09  
**Status**: Draft  
**Input**: User description: 关于页点击三下图标开启 debug 模式，debug 模式开启时开启 Logger（hilog 双写）；在项目笔记文档中写强调。附带 R7 验证期发现的四项工程债。

## Overview

R7 验证中发现应用日志无法被外部 CLI 读取（沙箱隔离 + 不走 hilog 总线），验证取证只能翻 UI 日志页。本轮引入 **debug 模式**：关于页图标三连击开启（持久化），开启后展示开关、关闭需二次确认；**debug 模式开启期间** `Logger.log` 才双写 hilog，默认关闭仅落盘+内存，避免无条件刷系统日志总线。同时修复 R7 验证期发现的四项工程债：连点订阅重复记录、手动刷新不延长 TTL、两处死 onPop 回调、源页过冲提示未统一。

## User Scenarios & Testing

### User Story 1 - 三连击开启 Debug 模式 (Priority: P1)

用户进入「关于」面板，在应用图标上快速连击三次，应用开启 debug 模式并给出 toast 反馈；该状态持久化，重启后仍保持开启。

**Why this priority**: debug 模式是其他能力（Logger 双写）的开关基础，也是本轮核心诉求。

**Independent Test**: 打开设置页→关于面板→对图标快速点击三次→toast 提示；重启应用后再次进入关于面板，开关仍显示开启状态。

**Acceptance Scenarios**:

1. **Given** debug 模式未开启，**When** 用户在关于面板图标上 2 秒内连击三次，**Then** debug 模式开启，toast 提示「已开启调试模式」，持久化生效
2. **Given** debug 模式已开启，**When** 用户杀掉应用进程并重新启动，**Then** debug 模式保持开启（状态持久化）

---

### User Story 2 - Debug 开关展示与二次确认关闭 (Priority: P1)

debug 模式开启后，关于面板展示「调试模式」开关（开启状态）；用户尝试关闭时需二次确认，确认后退出 debug 模式并清除持久化状态。

**Why this priority**: 提供可逆出口，避免 debug 模式成为不可关闭的状态；二次确认防误触。

**Independent Test**: 开启 debug 模式后，关于面板出现开关；点开关→弹确认框→确认→toast 提示关闭，重启后不再开启；点取消→保持开启。

**Acceptance Scenarios**:

1. **Given** debug 模式已开启，**When** 用户查看关于面板，**Then** 显示「调试模式」开关且处于开启态
2. **Given** 开关开启态，**When** 用户点击开关尝试关闭，**Then** 弹出二次确认对话框
3. **Given** 确认对话框，**When** 用户点击「确认关闭」，**Then** debug 模式关闭、持久化状态清除、toast 提示「已退出调试模式」
4. **Given** 确认对话框，**When** 用户点击「取消」，**Then** 对话框关闭、debug 模式保持开启

---

### User Story 3 - Logger 双写 hilog 门控 (Priority: P1)

debug 模式开启期间，应用日志在保留原有内存+落盘的基础上同步写入 hilog 总线（外部 CLI 可实时读取）；debug 模式关闭（默认）时仅内存+落盘，不写 hilog。

**Why this priority**: 解决 R7 验证取证的根源问题——日志内容主动出沙箱进总线，验证/调试无需翻 UI。

**Independent Test**: debug 模式开启→产生若干日志（如触发一次网络请求）→`devecocli log | grep BiliRadio` 能实时看到；关闭 debug 模式后同样操作，CLI 看不到新业务日志。

**Acceptance Scenarios**:

1. **Given** debug 模式开启，**When** 应用产生一条日志（网络/错误/播放链路），**Then** 该条日志同步写入 hilog 总线，外部 CLI 可读
2. **Given** debug 模式关闭，**When** 应用产生一条日志，**Then** 仅内存+落盘，hilog 总线无该业务日志
3. **Given** hilog 写入失败，**When** 任意一次日志写入，**Then** 静默降级，不影响内存/落盘主链路

---

### User Story 4 - 连点订阅去重（幽灵行根治） (Priority: P2)

在添加订阅面板重复点击「订阅」按钮不再产生重复记录；首页订阅列表不会因 LazyForEach 重复键出现点击无响应的幽灵行。

**Why this priority**: 用户可见缺陷，R7 验证期发现，连点即复现。

**Independent Test**: 添加订阅面板点一次订阅成功后，在面板关闭前再次点订阅（或快速重复整个流程），首页订阅卡片唯一、可正常点击。

**Acceptance Scenarios**:

1. **Given** 某订阅已添加成功，**When** 用户在同一会话内再次添加同一 sourceId，**Then** 不新增重复记录（内存与持久化一致）
2. **Given** 首页订阅列表，**When** 列表渲染完成，**Then** 无重复键幽灵行，每行均可点击响应

---

### User Story 5 - 手动刷新延长订阅 TTL (Priority: P2)

订阅源详情页手动刷新成功后，订阅元数据（含最后刷新时间）同步落盘，TTL 判定恢复正确。

**Why this priority**: 工程债，避免订阅因元数据陈旧被误判过期。

**Independent Test**: 记录订阅刷新前 lastRefreshAt→在源页执行手动刷新→查看持久化订阅数据，lastRefreshAt 已更新为刷新时刻。

**Acceptance Scenarios**:

1. **Given** 某订阅存在，**When** 用户在源页手动刷新成功，**Then** 订阅持久化数据中的 lastRefreshAt 等元数据字段同步更新
2. **Given** 手动刷新完成，**When** 随后检查 TTL 判定，**Then** 判定基于新的刷新时间而非陈旧值

---

### User Story 6 - 死 onPop 回调清理 (Priority: P2)

删除已被 onHidden/onShown 机制取代的两处死 onPop 回调，消除误导性代码。

**Why this priority**: 代码卫生，R7 验证期确认其已失效（onPop 仅 pop(result) 触发）。

**Independent Test**: 全仓 grep 无残留的 HomePage/SettingsPage onPop 死回调引用；构建通过。

**Acceptance Scenarios**:

1. **Given** HomePage 与 SettingsPage，**When** 检索 onPop 回调，**Then** 死回调已删除，无其他引用

---

### User Story 7 - 源页过冲提示统一 (Priority: P2)

源页顶部过冲提示改由与首页/历史面板一致的守卫机制驱动（onReachStart/onScrollEdge），纯边界过冲时也能出现提示；底部「没有更多了」仍由常驻 footer 承载。

**Why this priority**: R7 修复了首页/历史面板的过冲失效，源页同病未治，行为不一致。

**Independent Test**: 源页 fling 到顶出现过冲提示；到底仍显示常驻 footer「没有更多了」。

**Acceptance Scenarios**:

1. **Given** 源页列表，**When** 用户 fling 到顶（含纯边界过冲），**Then** 顶部过冲提示出现
2. **Given** 源页列表到底，**When** 触底加载完成且无更多内容，**Then** 常驻 footer 显示「没有更多了」

---

### Edge Cases

- 三连击计数窗口：2 秒内第 3 击才触发；窗口外第一次点击重新计时，不误触发
- 关闭确认框点「取消」：不改变状态，无残留副作用
- 应用进程被杀：debug 状态持久化保留，重启按持久化值恢复
- hilog 写入失败：try/catch 静默，不抛异常、不影响落盘/内存
- 非 debug 状态：Logger 内存+落盘行为与 R7 完全一致，无回归
- 开关仅显示当前状态：未开启时不展示开关行

## Requirements

### Functional Requirements

- **FR-001**: 关于面板应用图标支持 2 秒窗口内三连击识别，触发 debug 模式开启并 toast 提示
- **FR-002**: debug 模式状态持久化（Preferences），跨重启保留；默认关闭
- **FR-003**: debug 模式开启后，关于面板展示「调试模式」开关（开启态）；关闭操作必须二次确认；确认后状态清除并 toast 提示
- **FR-004**: debug 模式开启期间，`Logger.log` 每条日志同步写入 hilog 总线（复用既有 LOG_DOMAIN/LOG_TAG，debug 级别）
- **FR-005**: debug 模式关闭（默认）时，`Logger.log` 仅内存+落盘，不写 hilog
- **FR-006**: 添加订阅流程在同一会话内对同一 sourceId 去重，不产生重复记录（内存与持久化一致）
- **FR-007**: 源页手动刷新成功后，订阅元数据（lastRefreshAt 等）同步落盘
- **FR-008**: 删除 HomePage 与 SettingsPage 中的死 onPop 回调及其残留引用
- **FR-009**: 源页顶部过冲提示由 onReachStart/onScrollEdge 守卫驱动，与首页/历史面板行为一致；底部「没有更多了」由常驻 footer 承载

### Key Entities

- **DebugModeState**: 布尔开关，持久化于 Preferences（键在 Constants 登记）；默认 false；控制 Logger hilog 双写开关
- **Subscription**（既有）: 元数据字段 lastRefreshAt 等，US5 修复其手动刷新落盘
- **LogEntry**（既有）: 内存环形缓冲条目，US3 增加 hilog 输出路径但数据模型不变

## Success Criteria

### Measurable Outcomes

- **SC-001**: 三连击在 2 秒窗口内稳定触发 debug 模式，跨重启状态保持（10 次操作成功率 100%）
- **SC-002**: 关闭确认流程完整：确认→状态清除并 toast；取消→状态保持；无残留
- **SC-003**: debug 开启时 `devecocli log` 可实时检索到应用业务日志；关闭后检索不到新增业务日志
- **SC-004**: 同一会话内对同一订阅连点添加，持久化记录数不增长（无重复）
- **SC-005**: 手动刷新后订阅 lastRefreshAt 更新为刷新时刻
- **SC-006**: 全仓 grep 确认死 onPop 回调引用清零
- **SC-007**: 源页纯边界过冲到顶时顶部提示出现，与首页/历史面板一致

## Assumptions

- 三连击窗口采用 2 秒（行业通用快速连击阈值）；开启动作本身不需要二次确认（只有关闭需要）
- 开关行仅展示于关于面板内（图标下方），因三连击入口在关于页；不额外在设置主页增加常驻入口
- debug 模式仅门控 Logger 双写，不引入其他行为（无额外日志级别/无性能跟踪）
- hilog 写入失败静默降级，不向用户暴露错误
- hilog 双写内容与落盘文件一致（含已截 query string 的请求路径，`%{public}s` 格式符）

## Open Questions

- 无（关键歧义已通过澄清确认；实现细节交 Phase 2 裁决）
