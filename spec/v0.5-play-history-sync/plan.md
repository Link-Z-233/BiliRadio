# Implementation Plan: 播放进度云端同步（v0.5）

**Input**: Feature specification from `spec/v0.5-play-history-sync/spec.md`

## Summary

登录用户播放进度与 B 站云端双向同步：上行经 web heartbeat 端点周期上报（挂现有 5s 进度节拍），下行从既有取流响应解析 `last_play_time` 作为云端续播输入（零新增请求）。开关位于设置页登录状态条目下方（默认开，未登录隐藏）。未登录/关闭/失败全部静默降级为现状纯本地行为。

## Technical Context

**Language/Version**: ArkTS（API 26，`compatibleSdkVersion=26.0.0`，无低版本兼容设计）  
**Primary Dependencies**: `@ohos.net.http`（既有）、`@kit.RemoteCommunicationKit` rcp（既有，短链用）  
**State Management**: 既有架构——模型层 `@ObservedV2`+`@Trace`；`PlayerController` 零装饰器纯类（手动 `subscribe`/`emitUi` 广播，新公开状态沿用此模式，**勿加观测装饰器**）；页面 `@ComponentV2`  
**Storage**: `AppStore`（preferences，KEY_* 持久化）——开关键落此；`SecureStore`（cookie）既有  
**Testing**: 无测试套件（项目现状），验证走 `devecocli build` + 真机  
**Target Platform**: HarmonyOS NEXT（平板/手机）  
**Project Type**: 单模块 HarmonyOS 应用（增量特性，跟随既有架构）  
**Performance Goals**: 上报不阻塞播放主线程；起播云端续播零额外网络请求（复用取流响应）  
**Constraints**: 上报/读取 best-effort，失败静默；连续失败熔断防刷请求；未登录零同步行为  
**Scale/Scope**: 改动面——`BiliService`（心跳 API + 取流解析）、`PlayerController`（编排）、`SettingsPage`（开关行）、`Constants`（键/端点/阈值）；无新文件、无新模型

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-play-history-sync/
├── spec.md
└── plan.md              # This file
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── BiliService.ets      # [改] 新增 reportHeartbeat（web heartbeat POST）；
│   │                        #      fetchDashAudioTracks / fetchDurlCandidates 响应解析 last_play_time，
│   │                        #      经 resolveAudioTrack 汇聚进 ResolvedAudio 新字段
│   ├── PlayerController.ets # [改] 同步编排：5s 节拍上报挂点、暂停/切歌/完播补报、失败熔断、
│   │                        #      起播云端续播合并（零装饰器模式不变）
│   └── Constants.ets        # [改] KEY_HISTORY_SYNC、BILI_HEARTBEAT_URL、HEARTBEAT_FAIL_FUSE、
│                            #      HEARTBEAT_MIN_GAP_SEC
├── pages/
│   └── SettingsPage.ets     # [改] 登录状态条目下方新增「历史同步」开关行（SettingsRow，未登录隐藏）
└── model/
    └── AudioQuality.ets     # [改] ResolvedAudio 新增 lastPlayTimeMs 字段（默认 0）
```

**Structure Decision**: 跟随既有项目架构（service/pages/model 分层，依赖单向 service→model、pages→service/model）。增量特性不引入新目录/新文件/新模型；心跳 API 收敛在 BiliService（B 站 API 唯一集中地，与收藏夹 API 同模式），编排逻辑就近放 PlayerController（全部钩子——5s 节拍、完播、playIndex 决策——都在该文件内部，跨文件接线反而更长）。

## Research & Decisions

### R1 心跳端点与参数（上行）

- **Decision**: `POST /x/click-interface/web/heartbeat`，form-urlencoded：`bvid`、`cid`、`played_time`（秒）、`type=3`（UGC）、`csrf=bili_jct`；响应 `code=0` 即成功。完播上报 `played_time=-1`（B 站「-1=看完」语义）。请求头复用 `buildHeaders()`（cookie 自动携带）。
- **Rationale**: PiliPlus 同款（`VideoHttp.heartBeat`，`VideoType.ugc.type=3`）；web 端点与现有 cookie 登录态天然匹配，无需 APP 端点 access_key。
- **Alternatives considered**: APP 端点 `/x/v2/history/report`——被否：需 BiliDroid UA/appkey 体系，与 cookie 登录态混搭增加风控面。

### R2 上报挂点：复用 5s 进度节拍，不新增计时器

- **Decision**: 挂 `PlayerController.persistProgress()`（现有 `PROGRESS_SAVE_INTERVAL_MS` 5s 节拍，本地历史写盘点）同点：每次节拍且进度较上次上报前进 ≥5s 时上报 `played_time=floor(currentTime/1000)`。暂停/切歌/完播等状态变化即时补报（前进 ≥`HEARTBEAT_MIN_GAP_SEC`=2s 才发）。上报失败计数，连续 ≥`HEARTBEAT_FAIL_FUSE`=3 次熔断本集上报（切歌/重新起播复位）。
- **Rationale**: PiliPlus 节奏（播放中 ≥5s、状态变化 ≥2s）与现有节拍天然对齐；熔断防离线场景每 5s 一个失败请求刷日志。
- **Alternatives considered**: 独立心跳计时器——被否：多一份计时器状态与生命周期管理，节拍语义重复。

### R3 云端进度来源：取流响应解析，零新增请求

- **Decision**: `/x/player/playurl` 响应（带 cookie）解析 `last_play_time`（毫秒），经 `fetchDashAudioTracks`/`fetchDurlCandidates` 内部解析 → `resolveAudioTrack` 汇聚 → `ResolvedAudio.lastPlayTimeMs` 透出。**实施轮首任务实测**该端点是否返回字段；不返回则端点切换 `/x/player/wbi/playurl`（WbiSigner 签名，PiliPlus 同款）。
- **Rationale**: PiliPlus 佐证（`lastPlayTime = json['last_play_time']`，`defaultST = Duration(milliseconds: lastPlayTime)`）；复用既有取流请求 = 云端续播零额外网络成本、零起播延迟。
- **Alternatives considered**: 起播前单独查历史接口——被否：多一次请求+延迟，且历史列表接口已被 spec 排除（FR-009）。

### R4 续播决策：max 合并 + 完播防护

- **Decision**: `playIndex` 新起播（`seekMs<=0`）路径，取流完成拿到 `lastPlayTimeMs` 后合并续播起点：
  - 本地 `progress=-1`（已听完）→ 从头（现状语义，忽略云端）；
  - 否则起点 = `max(本地续播 ms, 云端 ms)`（不回退、不重听已听部分）；
  - 防护：`云端 ms ≥ duration×PLAY_COMPLETE_RATIO`（复用既有完播阈值）→ 视为云端已看完 → 从头（防 last_play_time 对已完播视频返回整段时长导致跳到结尾）；
  - 云端 0/缺失/解析失败 → 纯本地（现状）。
- **Rationale**: max 规则同时覆盖跨设备（云端>本地）与离线（本地>云端）两向，无需时间戳判新；完播防护对齐本地 95% 阈值语义。
- **Alternatives considered**: view_at 时间戳判新——被否：playurl 响应无该时间戳，max 规则以更弱前提达成同等效果。

### R5 开关与落位

- **Decision**: `KEY_HISTORY_SYNC`（AppStore，默认 1=开）。生效条件 = 已登录（BiliSession cookie 非空）且 开关开。UI：`SettingsPage` 登录状态条目正下方 `SettingsRow` 开关行；未登录时隐藏该行（同步依赖登录态，显示无意义）。
- **Rationale**: 用户指定落位（登录区块下方）；未登录隐藏避免死开关。
- **Alternatives considered**: 播放设置区——被否（用户已明确落位）。

### R6 失败与降级语义

- **Decision**: 上报失败静默 hilog + 熔断计数（R2）；云端读取失败 → 纯本地续播；登录失效（-101）→ 同熔断处理，不弹登录提示。全程无弹窗、无重试循环。
- **Rationale**: spec FR-006/FR-007 best-effort 要求。

### R7 HistoryMapper 保持预留不动

- **Decision**: 本轮 `HistoryMapper`/`BiliHistoryRecord` 零调用零改动。心跳参数（bvid/cid/played_time）直接来自播放态，无需条目级映射；云端进度（last_play_time 单值）亦不构成 BiliHistoryRecord。
- **Rationale**: mapper 服务的是「历史条目列表」同步（拉取合并），本轮范围已排除；保持预留边界注释不动。

### R8 实施轮实测验证项（open question 落地）

- **Decision**: 实施轮首任务执行三项实测：① `/x/player/playurl`（带 cookie）响应是否含 `last_play_time` → 决定 R3 是否切 `/x/player/wbi/playurl`（WbiSigner 现成）；② heartbeat 端点 `type=3` + cookie 响应，完播 `-1` 上报后云端历史显示「已看完」核对；③ 云端已看完视频的 `last_play_time` 返回值（0 / 整段时长 / -1）→ 确认 R4 防护阈值必要性。
- **Rationale**: spec 两个 open question 的收敛路径；实测优先于猜测，三项均不阻塞设计（各有既定降级路径）。

## Data Model

- **ResolvedAudio（model/AudioQuality.ets，微扩）**: 新增 `lastPlayTimeMs: number = 0`（取流响应 `last_play_time`，毫秒；0=无/未登录/未返回）。既有字段不动，既有调用方（换音质路径）不受影响。
- **同步开关（无新模型）**: `KEY_HISTORY_SYNC` 持久化偏好（0/1），读经 `AppStore.getNumber`。
- **PlayHistoryItem / BiliVideo / HistoryMapper**: 零改动。

## Contracts & Interfaces

- **BiliService.reportHeartbeat(bvid: string, cid: number, playedTimeSec: number): Promise<void>**（静态）：R1 端点 POST；内部失败抛错（调用方熔断计数）；成功静默。
- **BiliService.fetchDashAudioTracks / fetchDurlCandidates**（内部解析扩展）：响应增加 `last_play_time` 解析，经返回结构透出（签名微调限于 BiliService 内部 2 个调用点）。
- **BiliService.resolveAudioTrack(...): Promise<ResolvedAudio>**（既有签名不变）：`ResolvedAudio` 多携带 `lastPlayTimeMs`。
- **PlayerController 同步编排（私有）**: 节拍上报方法（gate：登录+开关+熔断+前进量）、状态变化补报、`playIndex` 云端续播合并（R4 规则）。零装饰器，不新增公开 UI 状态（无 UI 面展示同步态，无需 emitUi）。
- **SettingsPage 开关行**: 登录状态条目下方；`SettingsRow`（既有组件）开关形态；写 `KEY_HISTORY_SYNC`。
- **Constants 新增**: `KEY_HISTORY_SYNC`、`BILI_HEARTBEAT_URL`、`HEARTBEAT_FAIL_FUSE=3`、`HEARTBEAT_MIN_GAP_SEC=2`、上报前进阈值（复用 `PROGRESS_SAVE_INTERVAL_MS` 换算，不新增）。
