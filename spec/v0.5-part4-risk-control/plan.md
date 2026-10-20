# Implementation Plan: v0.5-part4（风控对抗：刷新止血 + 过墙实验 + 刷新反馈）

**Input**: Feature specification from `spec/v0.5-part4-risk-control/spec.md`

## Summary

三条线：①止血——首页冷启动静默刷新加跨启动持久化 CD（AppStore 时间戳）；Web 补稠链被风控拦截后进程级冷却（单轮 WBI+plain 双风控失败即置位，冷却期只走 APP 签名链）；移除重试轮 `resetBuvid` 调用（失败不换身份，空 buvid 缺陷随之消失，另加入口保底）。②反馈——手动刷新补成功 toast（失败 toast 已在）；首页静默刷新失败聚合 toast+去重窗。③过墙——前置检查 rcp 与 `@ohos.net.http` TLS 栈异同，异构则 `fetchUpVideosOnce` 换 rcp 真机实验；终态判定 build-only（hilog WBI 轮结果）。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0）
**Primary Dependencies**: ArkUI、`@ohos.net.http`、`@kit.RemoteCommunicationKit`（rcp）、`@kit.ArkData`（preferences）
**State Management**: 存量 V2 体系（页面 `@ComponentV2`，PlayerController 零装饰器广播）；本轮改动均为服务层纯类与页面小改，不新增观测装饰器
**Storage**: preferences（AppStore.getNumber/putNumber 现成接口承载 CD 时间戳）
**Testing**: 无测试套件；验证 build-only（真机部署 + hilog 判定 + 用户目检）
**Target Platform**: HarmonyOS NEXT 真机（API 26）
**Project Type**: 单模块移动应用
**Constraints**: FR-009 APP 签名链无行为回归（红线）；B 站端点风控敏感——失败请求次数只减不增；同目标最多 3 次验证
**Scale/Scope**: 6 文件小改（Constants/BiliService/BiliSession/HomePage/SourcePage/AppStore 零改动确认），零新增文件

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part4-risk-control/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── Constants.ets        # 新令牌：CD/冷却时长、toast 文案、dedup 窗口、持久键
│   ├── BiliService.ets      # Web 冷却门禁与置位、isRiskControlError、fetchUpVideosViaWeb 重构、
│   │                        # 去 resetBuvid 调用、空 buvid 入口保底、rcp 传输实验（fetchUpVideosOnce）
│   └── BiliSession.ets      # resetBuvid 方法删除（移除调用后零引用则删）
├── pages/
│   ├── HomePage.ets         # silentRefresh CD 门 + 失败聚合 toast（去重窗）
│   └── SourcePage.ets       # refreshSource 成功 toast
└── （SubscriptionStore/AppStore/模型层零改动）
```

**Structure Decision**: 跟随现有项目架构（pages/component/service/model 分层），零新增文件、零目录调整，不引入 MVVM 迁移。改动集中于 service 层两个文件与两个页面的小切口。

## Complexity Tracking

无 Constitution Check 违规——全部改动落在既有文件既有职责内。

## Research & Decisions

- **D1 CD 持久化方式**：AppStore preferences 现成 `getNumber`/`putNumber` 承载「上次静默刷新时间戳」。
  **Rationale**: 跨启动持久化是 FR-001 硬要求（进程级挡不住杀进程重开）；preferences 是项目既有持久化通道。
  **Alternatives considered**: 文件存储（重）；AppStorageV2/PersistenceV2（`KEY_*` 持久化偏好按项目惯例走 AppStore，不混通道）。

- **D2 Web 冷却粒度：进程级**（BiliService 模块字段），杀进程即失效。
  **Rationale**: 被拦后的重试价值随进程存活期递减；杀进程重开场景由首页 CD（持久化）兜底防风暴；进程级实现最简（一个模块级时间戳）。
  **Alternatives considered**: 持久化冷却（会在风控解除后仍长时间禁用 Web 补稠，恢复变慢）。

- **D3 Web 冷却置位条件：单轮 WBI+plain 双风控失败即置位**，不等 3 轮全败。
  **Rationale**: WBI -403 + plain -799 已是明确被拦信号（实测同款信号），继续第 2/3 轮只徒增 4 次失败请求（当前自我放大源）；风控类失败与网络抖动分类处理——网络类仍走 3 轮退避（去掉换身份）。
  **Alternatives considered**: 3 轮全败再置位（多打 4 次失败请求，放大）。

- **D4 `resetBuvid` 调用移除**（`fetchUpVideosViaWeb` L893、`fetchUpInfo` L1040 两处），方法零引用后删除。
  **Rationale**: 判别实验佐证被拦后换新身份反效果（每次换 buvid = 零信任新客户端+爬虫特征）；空 buvid 重试轮缺陷（reset 后无人补取）随移除自然消失；另加 Web 链入口空 buvid 保底（`hasBuvid()` 为假先 `ensureBuvid()`）。
  **Alternatives considered**: 保留轮换但 reset 后立即补取（保留换身份行为——与判别实验结论冲突）。

- **D5 rcp 实验切口：仅 `fetchUpVideosOnce`**（WBI arc/search + plain 空间投稿两端口）；mixinKey/nav 维持现栈。
  **Rationale**: 被拦的是投稿两端点（实测 -403/-799）；nav/mixinKey 实测可过且有按日缓存；最小切口控制实验面，符合单方案决策。
  **Alternatives considered**: 全 Web 链换 rcp（面大、变量多，失败时难归因）。

- **D6 通知复用既有 toast 模式**：页面直接 `promptAction.showToast`（项目通用模式）；失败聚合去重窗复用 US6 `PLAYBACK_ERROR_DEDUP_MS` 的时间窗思路但独立令牌。
  **Rationale**: 手动失败 toast 已在（SourcePage:442，零改动）；刷新通知与播放错误是不同事件流，不共用 PlayerController 的 playbackError 入口；文案与去重窗口进 Constants。
  **Alternatives considered**: 复用 playbackError 入口（职责混淆——那是播放错误专用）。

- **D7 风控错误分类新函数**：`isRiskControlError`（-352/-412/-403/-799 及非 JSON 风控页特征），与既有 `isUpQueryFatal`（-404/-400/-101 业务错误即败）互补。
  **Rationale**: 置位/重试分流需要「风控类 vs 网络类 vs 业务类」三分类；现有 fatal 判定只覆盖业务类。
  **Alternatives considered**: 扩展 isUpQueryFatal 返回枚举（改动面大，调用点多）。

- **D8 rcp 前置检查途径**：本机 SDK `.d.ts`（`sdk/default/openharmony/ets/`）与 rcp 官方说明查底层栈线索；结论「同栈无差异可试」→ US4 失败分支收尾（登记 BILI_API.md §3）。
  **Rationale**: FR-007 前置要求；rcp 在项目内已有用法先例（LinkResolver 短链解析），API 形态已知，剩余未知是底层 TLS 栈。

- **D9 CD 时钟回拨防护**：`now - last` 为负视为 CD 过期放行。
  **Rationale**: 回拨后负差若按 `< CD` 处理会永久 CD（spec Edge Case 已列）；放行代价只是多刷一次，方向安全。

- **D10 静默失败聚合位置：HomePage 层**（onOneDone 回调已有 `ok` 参数，silentRefresh 内计数）。
  **Rationale**: `SubscriptionStore.refreshAll` 零改动；聚合、去重、toast 全在既有事件流内完成，改动最小。
  **Alternatives considered**: refreshAll 返回聚合结果（改公共签名，波及手动路径）。

## Data Model

**新增持久化键**（Constants 定义，AppStore 承载）：

- `KEY_LAST_SILENT_REFRESH_AT`（number，毫秒时间戳）：上次首页静默刷新完成时刻；CD 判定基准（D9 规则）

**新增进程级状态**（BiliService 模块字段）：

- Web 链冷却截止时间戳：置位后 `fetchUpVideosViaWeb` 入口直接抛错（调用方既有 catch 兜底），到期自动恢复

**新增令牌**（Constants，数值唯一真相源）：

- `HOME_SILENT_REFRESH_CD_MS`（首页 CD 时长，15min 档）
- `WEB_CHAIN_COOLDOWN_MS`（Web 链进程冷却时长，10min 档）
- `TOAST_REFRESHED`（手动刷新成功文案）
- `TOAST_SILENT_REFRESH_FAIL`（静默刷新失败文案，含 N 占位）
- `SILENT_REFRESH_FAIL_DEDUP_MS`（静默失败 toast 去重窗）

**行为语义**：

- 首页 CD：`aboutToAppear → silentRefresh` 入口判定；CD 内跳过整轮 `refreshAll`（不写时间戳，CD 从上次实际刷新起算）；刷新完成写时间戳；手动刷新不经此门（FR-002）
- Web 冷却：`fetchUpVideosViaWeb` 单轮内 WBI 风控败 + plain 风控败 → 置位 + 立即抛错（单源单轮失败请求封顶 2 次）；冷却期内该函数入口直接抛错；网络类失败仍 3 轮退避（不换身份）
- 与 per-sub TTL 的关系：CD 是全局门（进程外持久），TTL 是源级门（既有），两层互补——CD 过期后 refreshAll 内部仍按 TTL 跳过新鲜源

## Contracts & Interfaces

**`fetchUpVideosViaWeb` 行为契约**（内部私有，影响以下公共路径：`fetchUpWebHead`（US2 双链补稠）、`fetchUpVideosByPage`（翻页））：

- 冷却中调用：立即抛错（不发起任何网络请求）；调用方兜底链不变——`refreshSubscription` 的 Web 补稠 catch 退化为 APP 结果、SourcePage 翻页 toast 报错
- 风控被拦：单轮双端点风控败即置位冷却并抛当轮真实错误；UP 主链（APP 签名链）供数不受影响（FR-009）
- buvid：入口 `hasBuvid()` 为假先 `ensureBuvid()`；全程不再出现 reset/轮换（FR-004）

**`fetchUpInfo` 行为契约**：3 轮降级结构不变，仅移除重试轮 `resetBuvid`（不换身份）；acc/info 失败仍走 card 兜底

**`silentRefresh`（HomePage）行为契约**：CD 门（D9 规则）→ `refreshAll` → 完成写 `KEY_LAST_SILENT_REFRESH_AT`；失败源计数 >0 时 toast（去重窗内只弹一次）；CD 跳过零提示（FR-006）

**`refreshSource`（SourcePage）行为契约**：成功路径补 toast（FR-005）；失败 toast 既有不动；`refreshing` 并发防抖不动

**rcp 传输（US4 实验段）**：`fetchUpVideosOnce` 由 `httpGet` 切换为 rcp 会话请求（复用 LinkResolver 的 `rcp.Session`/`rcp.Request`/`rcp.Configuration` 模式，`autoRedirect` 默认、超时取现令牌）；请求头与参数零变化（实验变量唯一=传输栈）；前置检查结论「同栈」则此段不实施

**验证契约**：build-only——真机部署后 hilog 判定（`第N轮WBI成功`=过墙 / `-403`=仍拦截）；失败补录 `BILI_API.md` §3

**文档补录契约**（收尾门）：本轮新实测（rcp 结论、冷却后风控状态变化）补录 `BILI_API.md` §3 对应小节后方可收尾
