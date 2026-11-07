# Implementation Plan: v0.7-part3 队列失效视频识别与播放失败处理

**Input**: Feature specification from `spec/v0.7-part3-invalid-video/spec.md`

## Summary

播放链路取流失败按错误码三分处理：失效（-404，X 标记必跳过）/ 异常（-104 或时长异常，橙感叹号异常标记跳过）/ 瞬时（风控网络，停等人工分型提示）。标记体系双集：新增 invalidSet（KEY_INVALID_BVIDS）承载 X；既有 anomalySet 保留为异常标记集（存量 v0.5-part5 时长判定条目语义正确，零迁移）。修复状态一致性 bug 群：playIndex 失败路径复位 playIntent、失败条目统一持久化为当前条目（含队尾无法跳过场景）、切换取流失败显式停旧声。废止「异常源处理」开关；添加入口失效 BV 分型提示不入队。错误分类采用消息提取形态（复用既有 `BiliService.isRiskControlError` + `Bili API error -NNN` 模板前缀匹配），不改 BiliService 抛错结构。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: 零第三方依赖（AVPlayer/media、preferences、SymbolGlyph 系统图标）
**State Management**: 沿用现状——PlayerController 零装饰器广播（字段 + emitUi，消费方 syncFrom）；页面组件 V2；不引入新代际
**Storage**: AppStore（preferences 封装）+ savePlaylistFile 队列快照文件；标记集 JSON 序列化 putString
**Testing**: 无测试套件；新非平凡逻辑（错误分类函数）以日志自检 + 真机验证覆盖；静态检查 `devecocli check arkts`
**Target Platform**: HarmonyOS NEXT 单模块应用
**Project Type**: mobile-app（存量增量改造）
**Performance Goals**: 失败分类零额外网络请求；跳过链不阻塞 UI（playIndex 既有 async 链）
**Constraints**: 不自动重试瞬时失败（风控升级，BILI_NOTES 实验 8）；toast 不外露原始错误码；异常标记不区分两路原因呈现
**Scale/Scope**: 存量代码改造，触点 10 文件（4 渲染 + 1 设置 + 4 服务/常量/资源 + 1 页面 toast 消费）

## Project Structure

### Documentation (this feature)

```text
spec/v0.7-part3-invalid-video/
├── spec.md
├── plan.md              # This file
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── Constants.ets        # 新增 KEY_INVALID_BVIDS/分型文案常量；删 KEY_ANOMALY_SKIP/TOAST_ANOMALY_TRIAL；改 TOAST_ANOMALY_SKIP 值
│   ├── PlayerController.ets # invalidSet 生命周期；playIndex catch 重写（分类/标记/跳停/FR-008/14/15）；handleAnomalyOnPrepared 开关分支删+队尾停口补持久化；init 恢复抑制；collect/count 增补 hasInvalid；addSingleVideo 分类
│   └── BiliService.ets      # 不改（isRiskControlError 复用）
├── pages/
│   ├── SettingsPage.ets     # 删「异常源处理」开关行三处（字段/同步/行 UI）
│   ├── SourcePage.ets       # X 渲染条件改 hasInvalid + 新增异常标记渲染（:1128 一处）
│   └── Index.ets            # errorTick toast 由硬编码常量改为显示 errorMsg（:105 一处）
├── component/
│   ├── QueueSheet.ets       # X 渲染条件改 hasInvalid + 异常标记渲染（:919/:1053 两处）
│   └── HistorySheet.ets     # 同上（:807 一处）
entry/src/main/resources/base/element/color.json  # 新增 warning_amber
```

**Structure Decision**: 沿用既有项目架构（service/pages/component 分层 + Constants 唯一真相源 + 零装饰器广播），不引入 MVVM 迁移；新增能力全部落在既有文件职责内，无新文件。

## Complexity Tracking

无宪法违规——全部为存量文件内最小改造，无新目录、无新抽象层。

## Research & Decisions

### D1 — 错误码分类实现形态：消息提取

**Decision**: PlayerController 内新增私有分类函数，从 `error.message` 提取分类：前缀精确匹配 `Bili API error -404` → 失效；`Bili API error -104` → 大会员专限；`BiliService.isRiskControlError(message)` → 风控瞬时；前缀 `HTTP request failed` → 网络瞬时；其余 → 其他瞬时（好友文案透传：非模板前缀的消息如 `-101 登录已失效` 原样作 statusMsg，无则通用兜底）。

**Rationale**: `Bili API error ${code}` 模板仅 3 处抛点、格式统一（BiliService :370/:790/:980，项目自控）；风控判定 `isRiskControlError`（-352/-412/-403/-799/风控页特征）v0.5-part4 已建可直接复用；分类只需正向识别两个确定性码，其余全归瞬时。只动 PlayerController 一个文件。

**Alternatives considered**: BiliService 抛结构化错误对象（BiliApiError extends Error 携 code 字段）——类型更强，但须改 3 抛点 + 新导出类，而消费端只需两个码的正向识别，收益不抵改动面。

### D2 — 标记集物理存储映射：invalidSet 新增，anomalySet 保留

**Decision**: 新增 invalidSet（per-bvid，`KEY_INVALID_BVIDS`，JSON 数组 putString，加载/持久化/mark/has 镜像 anomalySet 既有模式）承载 X；既有 anomalySet（KEY_ANOMALY_BVIDS）原样保留为异常标记集——存量条目全部为 v0.5-part5 时长判定，语义即异常标记，零数据迁移。X 不建 clear（bvid 不复用不可恢复）；失效判定优先经「标 X + clearAnomaly」实现（既有 clearAnomaly 复用）。

**Rationale**: 存量条目语义天然正确（失效视频到不了 prepared，从未入集）；反向搬迁（anomalySet 改 X 语义 + 全量迁移至新异常集）要求逐条迁移且视觉切两步，纯增加风险。

**Alternatives considered**: 单集 + 附加类型字段（Record<bvid, kind>）——迁移既有存储格式，读写路径全改，无对应收益。

### D3 — FR-014 写盘时机：catch 内统一写

**Decision**: playIndex catch 进门即 `savePlaylistFile(playlist, currentIndex, 0, currentQualityCode)`——每个失败条目立即持久化为当前条目（所有分支：确定性跳过、队尾停口、瞬时停等）；后续跳过成功由既有成功路径 :1049 覆盖写。持久化字段取 catch 时刻值（音质已复位为 0，与「未播成」语义一致）。

**Rationale**: 单调用点无分支；「只在停口写」方案存在跳过链中途被杀的持久化空洞（失败条目从未落盘）且需维护双写盘分支；额外 IO 为每失败条目一次小 JSON 写，可忽略。

**Alternatives considered**: 仅停等/队尾停口写盘——少 IO 但引入 kill 窗口空洞与分支复杂度；playIndex 进门统一写（含成功路径）——成功路径写盘时机后移，改变既有成功语义，无必要。

### D4 — toast 通道分工：确定性走 showAnomalyToast，瞬时走 playbackError 扩展

**Decision**: 确定性失败（失效/大会员/时长异常）toast 走既有 `showAnomalyToast`（动态文案 + PLAYBACK_ERROR_DEDUP_MS 去重窗，FR-010 沿用）；瞬时失败 toast 走既有 `playbackError`，为其扩展公开 `errorMsg` 字段承载分型文案，Index :105 由硬编码 `TOAST_PLAYBACK_ERROR` 改为显示 `errorMsg`（常量保留作兜底文案）。确定性失败不触发 playbackError toast（标记日志经 markInvalid/markAnomaly 既有 Logger 承载，catch 补一条分类日志）。

**Rationale**: 两条通道均已存在且各有合适去重语义（playbackError 按 stage+bvid 键去重，showAnomalyToast 按时间窗去重）；确定性跳过与瞬时停等的用户语义不同（「已跳过」告知 vs「请重试」求助），分通道呈现自然。

**Alternatives considered**: 全部并到 showAnomalyToast——丢失 playbackError 的 errorCode 快照/日志链路；全部并到 playbackError——去重键不含分类语义，连续跳过去重行为变化。

### D5 — FR-015 旧声停播：停口镜像 onError 处理

**Decision**: playIndex catch 停止路径（队尾停 + 瞬时停等）统一执行：`player.pause()`（AudioPlayer.pause 对未播放态为安全 no-op）+ `setPlaying(false)` + `mediaSession.updateState(false, currentTime)` + `mediaSession.stopBackground()`——与既有 onError（:436-446）处理对齐。跳过路径不停声（后续 playIndex 成功重建播放器，中间无声窗口由新流衔接；失败则由其自身 catch 停口接管）。时长异常路径（handleAnomalyOnPrepared）无旧声问题（prepared 阶段旧播放器已被 setStreamSource→recreatePlayer 释放）。

**Rationale**: 手动切换撞 404 时旧 AVPlayer 仍在出声（setPlaying 只改标志、重建点在 openStream 成功后），停口必须显式停；镜像 onError 保证「暂停/停止」语义三处（onError/catch/队尾）一致。

**Alternatives considered**: playIndex 进门先停旧声——改变成功切换的既有听感（旧声陪伴取流至新流衔接），为修复失败路径而牺牲成功路径，不取。

### D6 — 恢复自动续播抑制：init :479 增加标记检查

**Decision**: init 恢复自动续播条件（:479）追加：恢复目标条目已标记（hasInvalid || hasAnomaly）时不自动 playIndex——恢复显示态（currentIndex/进度/封面照常恢复，标记可见），等用户操作；未标记瞬时失败条目恢复后可自动重试（KEY_AUTO_PLAY_ON_START 开关默认关，此分支只影响开启自动续播的用户）。

**Rationale**: 已标记条目重播结果已知（确定性失败），自动重试徒增一次失败请求与 toast；恢复显示态让用户看到标记自行决策。

**Alternatives considered**: 恢复后照常自动重播——幂等无害但每次启动多一次注定失败的取流请求，与「不自动重试确定性失败」原则矛盾。

### D7 — US5 拦截点：addSingleVideo catch 单点分类

**Decision**: 添加入口分类落在 `addSingleVideo` catch（:1542-1547）单点——HomePage 剪贴板识别（:288）与 AddSubscriptionSheet（:209）两入口共用。分类映射：-404 → 「视频不存在或已失效」不入队；isRiskControlError → 「请求被拦截，请稍后重试」；HTTP 前缀 → 「网络异常，请检查网络后重试」；好友文案（-101 登录失效）透传；无则「解析失败，请稍后重试」兜底。

**Rationale**: 两入口已统一走 addSingleVideo，单点拦截天然覆盖；改 statusMsg 文案映射即可，不动调用方。

**Alternatives considered**: 两入口各自分类——重复逻辑；在 BiliService 层拦——addSingleVideo 之外还有合法 -404 消费方（源页刷新等），层内拦截越权。

### D8 — 「异常源处理」开关废止

**Decision**: handleAnomalyOnPrepared :330-334 试听分支（KEY_ANOMALY_SKIP !== 1 路径）删除，行为恒为跳过；SettingsPage 开关行三处（字段/同步/行 UI）删除；Constants 删 KEY_ANOMALY_SKIP 与 TOAST_ANOMALY_TRIAL，TOAST_ANOMALY_SKIP 值改为「音源异常，已跳过」。KEY_ANOMALY_SKIP preferences 存量值不读不迁（留在本地无害）。

**Rationale**: 用户拍板（取代 v0.5-part5 两档语义）；「照常播放」1 分钟试听对照 20 分钟正片价值低；分支删除后函数仅保留判定/标记/摘标记/跳过四段。

**Alternatives considered**: 保留开关默认跳过——分支复杂度来源无对应价值，用户已明确废止。

### D9 — 异常标记渲染与色值

**Decision**: 新增 `app.color.warning_amber`（#FF9500，与 danger_red #D9534F / success_green #34C759 同 iOS 系色族）。四个渲染点（QueueSheet :919/:1053、HistorySheet :807、SourcePage :1128）：现有 X 渲染条件由 hasAnomaly 改为 hasInvalid（sys.symbol.xmark_circle + danger_red 不变）；同位置新增异常标记渲染（条件 hasAnomaly：sys.symbol.exclamationmark_circle + warning_amber，尺寸/边距沿用 X 既有 token）。防御性共存时 X 优先（hasInvalid 分支在前，else-if 呈现异常）。

**Rationale**: exclamationmark_circle 已在本机 sysResource.js 验证存在（id 125832650）；橙感叹（可恢复）与红叉（不可恢复）色彩+形状双重区分；沿用既有 SymbolGlyph 链路与 token，渲染改动为条件替换+同构新增。

**Alternatives considered**: 区分两路原因呈现（锁+感叹）——须给标记集加判定来源字段，且常驻暗示充电嫌疑稿，违背「不说明是充电视频」定稿，用户已否。

### D10 — -104 实测先行（实施第一步）

**Decision**: 实施第一步真机验证：收藏夹拉取会员专限 UGC（确认 fav 源下发会员稿）、playurl 对会员稿回 -104、view 对会员稿的返回形态（正常元数据 or 也回 -104）。若 view 即回 -104，则 -104 分类落点前移至 fetchVideoDetail 失败（playIndex catch 分类逻辑不变，仅触发层变化）；若 fav 源实测不下发会员稿，US2 判定路径仍保留（收藏夹可收藏会员稿是官方能力，下发时机不受控）。实测结论补录 BILI_NOTES §1/§3 后继续实施。

**Rationale**: spec 假设「-104 经 playurl 返回、view 正常返回元数据」未实测；分类逻辑对触发层不敏感（都进同一 catch），实测只决定断言文案与 BILI_NOTES 事实，不阻塞架构。

## Data Model

### invalidSet（X 标记集，新增）

- 形态：`Set<string>`（bvid 粒度），成员=「视频不存在（-404），重试无意义」
- 持久化：`AppStore.putString(KEY_INVALID_BVIDS, JSON.stringify(Array.from(invalidSet)))`，加载镜像 loadAnomalySet 模式（JSON 数组解析、容错空/坏值）
- 生命周期：init 加载；markInvalid 幂等写入+persist+Logger+emitUi；无 clear（bvid 不复用不可恢复）；失败判定优先转换时配 clearAnomaly 摘异常标记
- 不可变约束：仅 playIndex catch 失效分支写入

### anomalySet（异常标记集，既有转语义）

- 形态/持久化/生命周期不变（KEY_ANOMALY_BVIDS、markAnomaly/clearAnomaly/loadAnomalySet/persistAnomalySet）
- 语义变更为「视频存在但未获完整流」：两路写入——playIndex catch -104 分支（markAnomaly）+ handleAnomalyOnPrepared 时长判定分支（既有）；摘除——prepared 时长恢复正常（既有 :325-327，开通大会员/获得完整流共用）
- 存量条目（v0.5-part5 时长判定）语义正确，零迁移

### 播放失败分类（新增，playIndex catch 内）

- 失效 INVALID：message === `Bili API error -404` → 标 X + 「视频已失效，已跳过」+ 跳过
- 大会员 VIP：message === `Bili API error -104` → 标异常 + 「需要大会员，已跳过」+ 跳过
- 时长异常（非 catch 路径）：既有 prepared 判定 → 标异常 + 「音源异常，已跳过」+ 跳过
- 瞬时（RISK/NETWORK/OTHER）：不标不跳不自动重试 → 停等人工 + 分型 toast/statusMsg

### 持久化快照（既有，语义补全）

- savePlaylistFile(playlist, lastIndex, lastPosMs, lastQualityCode) 调用点新增：playIndex catch（失败条目为当前）+ handleAnomalyOnPrepared 队尾停口（既有缺口）
- 恢复读取（KEY_LAST_INDEX/KEY_LAST_POS_MS/KEY_LAST_QUALITY）不变；init 自动续播条件追加标记检查（D6）

## Contracts & Interfaces

### PlayerController 公开成员变更

- 新增 `hasInvalid(bvid: string): boolean`——四渲染点 X 条件、collectPlayedRemovable、playedRemovableCount、init 恢复抑制消费
- `playbackError` 新增公开快照字段 `errorMsg: string`（分型文案）——Index toast 消费；既有 errorCode/errorTick 不变
- 既有 hasAnomaly/anomalyToastMsg/anomalyToastTick 语义不变（消费方换渲染形态）

### playIndex catch 行为契约（重写）

按序执行：token 校验 → 失败条目持久化（FR-014）→ 分类 → 分支：
- INVALID/VIP：markInvalid（INVALID 附 clearAnomaly）→ showAnomalyToast(分型文案) → 有下一条则 playIndex(next) 跳过，无则停口（playIntent=false + setPlaying(false) + player.pause() + mediaSession 停更/停后台 + statusMsg 分型短语）
- 瞬时：playIntent=false（FR-008）→ 停声三件套（FR-015，同上停口）→ statusMsg 分型文案（不外露 raw code，FR-012）→ playbackError(stage, code, bvid, 分型文案) → 不跳过不标记

### handleAnomalyOnPrepared 行为契约（开关废止后）

判定（时长阈值既有 ANOMALY_DURATION_RATIO）→ 标记/摘标记（既有）→ 恒跳过：无开关分支；有下一条 playIndex(next)，队尾则停口补 savePlaylistFile（FR-014 既有缺口）+ 既有结束态字段处置

### addSingleVideo catch 行为契约（US5）

分类同 D1 映射 → statusMsg 分型文案（-404 → 「视频不存在或已失效」）→ EnqueueResult.FAILED 不入队（既有返回值不变）

### Constants 变更清单

- 新增：KEY_INVALID_BVIDS、TOAST_INVALID_SKIP（视频已失效，已跳过）、TOAST_VIP_SKIP（需要大会员，已跳过）、TOAST_NETWORK_RETRY（网络异常，请检查网络后重试）、TOAST_RISK_RETRY（请求被拦截，请稍后重试）
- 改值：TOAST_ANOMALY_SKIP → 「音源异常，已跳过」
- 删除：KEY_ANOMALY_SKIP、TOAST_ANOMALY_TRIAL
- 保留：TOAST_PLAYBACK_ERROR（瞬时 OTHER 兜底）、ANOMALY_DURATION_RATIO、PLAYBACK_ERROR_DEDUP_MS、KEY_ANOMALY_BVIDS

### 渲染契约（四渲染点统一）

- X：hasInvalid(bvid) → SymbolGlyph(sys.symbol.xmark_circle) + danger_red（既有形态）
- 异常标记：hasAnomaly(bvid) → SymbolGlyph(sys.symbol.exclamationmark_circle) + warning_amber（新增资源）
- 共存防御：hasInvalid 优先（else-if），正常流转不发生

### 文档同步契约

- BILI_NOTES：实施后补录 fav 源下发大会员专限 UGC（attr 不含会员标记）、-104 经 playurl/view 的实测形态至 §1/§3
- docs/architecture.md：若触点文件职责描述受影响（SettingsPage 开关移除、PlayerController 标记集新增），同步对应条目
