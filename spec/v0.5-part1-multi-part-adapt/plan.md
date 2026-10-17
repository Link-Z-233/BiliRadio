# Implementation Plan: v0.5 功能多P 适配（v0.5-part1-multi-part-adapt）

**Input**: Feature specification from `spec/v0.5-part1-multi-part-adapt/spec.md`

## Summary

以 master 多P 基线（9c62bd8，两轮多P 已交付）为底本，在新工作分支 `Pre-update`（复用原分支名）上移植 Pre-update-legacy（1b06f14）的 v0.5 四块功能（心跳上报、云端续播、完播上报 + 历史同步开关、详情页剧集行视觉）并完成多P 语义适配。核心原则：身份体系一律保 master 复合键（bvid+page）实现；云端续播按 last_play_cid 严格匹配；心跳/完播按发送时刻分P 快照；SourcePage 视觉与行为手工融合。零新增文件，全部改动落在既有文件。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0，API 26 基线）  
**Primary Dependencies**: 既有依赖零变化（@ohos.net.http/rcp、preferences 等）  
**State Management**: 增量工作，保留现状——模型层 @ObservedV2+@Trace、页面/挂键组件 @ComponentV2、PlayerController 零装饰器纯类（手动 subscribe/emitUi 广播 + 版本计数），心跳语境字段沿用该模式（普通字段 + emitUi）  
**Storage**: AppStore preferences（KEY_HISTORY_SYNC 开关）；持久化队列/历史文件格式零变化（master 多P 版 schema 为准）  
**Testing**: 无测试套件——arkts_check 静态预检 + devecocli build + 模拟器部署 + UI 验证（build+ui），代码级不变式自检；需用户后续真机自查的事项在轮次结束总结集中输出（不登记 PROJECT_NOTES，用户指示）  
**Target Platform**: HarmonyOS NEXT 单模块应用（Mate 90 Pro 模拟器部署）  
**Project Type**: mobile-app（单模块 ArkTS/ArkUI）  
**Performance Goals**: 上报 best-effort 不阻塞播放主线程；取流零新增请求  
**Constraints**: 复合键体系红线（FR-001）；上报/云读全程 best-effort 静默（熔断 HEARTBEAT_FAIL_FUSE=3）；代码零注释（ponytail: 标注除外）；色值/数值令牌规范；B 站 API 坑（web 端点 csrf、UA、rcp autoRedirect）  
**Scale/Scope**: 融合移植约 10 个既有文件，零新增文件/页面/路由

**Branch strategy**: 实施前旧 Pre-update（1b06f14，v0.5 移植源）改名 `Pre-update-legacy` 归档；自 master（9c62bd8）切出新工作分支 `Pre-update`（复用原分支名），实施/验证均在新的 Pre-update 上进行；master 与 Pre-update-legacy 实施期间不动；新 Pre-update 是否/何时合回 master 验证后由用户拍板。

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part1-multi-part-adapt/
├── spec.md               # 需求规格（Phase 1 已定案）
├── plan.md               # 本文件
└── tasks.md              # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── AudioQuality.ets          # ResolvedAudio 扩展（lastPlayTimeMs/lastPlayCid）
├── service/
│   ├── Constants.ets             # 心跳域键/端点/阈值 + 详情页缩略 token（追加式）
│   ├── BiliService.ets           # reportHeartbeat + 取流 last_play 双字段解析
│   └── PlayerController.ets      # 心跳挂点/熔断/复位 + 云续播严格匹配合并 + 完播 + recordOnPlaying 嫁接
├── pages/
│   ├── SettingsPage.ets          # 历史同步开关行（干净套用）
│   └── SourcePage.ets            # 剧集行视觉 × 分P 展开行为 手工融合
└── component/
    └── CoverThumb.ets            # 宽高分离扩展（干净套用）
entry/src/main/resources/base/element/color.json   # duration_badge_scrim
```

**Structure Decision**: 遵循现有项目架构（pages/service/model/component 分层 + 既有单例范式），零新增文件、零新增目录、零路由变化。本轮为既有功能融合移植，不触发任何结构升级；模块边界契约（service→model、pages→service/model）不变。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| PlayerController 持续增重（心跳语境字段 + 上报方法入该类） | 心跳需访问播放进度/cid/登录态/历史写点，与既有 5s 节拍、完播判定点同源，拆独立服务需跨类订阅进度流，复杂度反升 | 独立 HistorySyncService——进度高频广播接线成本高，且 PlayerController 零装饰器广播模式已提供挂点，沿用最短可用路径 |

## Research & Decisions

### 移植决策（D1-D8）

- **Decision D1 实施方式**：master 地基重放（工作分支上逐块移植 v0.5 增量），不走 git merge  
  **Rationale**: 同文件对撞面大（PlayerController/BiliService/SourcePage 两边各自大改），merge 硬拼的冲突仲裁工作量与重放相当，但历史可审性差、行为适配混入合并提交  
  **Alternatives considered**: git merge Pre-update→master 保留双分支历史（弃）；先机械合并再二次适配（两步走，弃）

- **Decision D2 云端续播多P 语义**：严格 cid 匹配（用户定案）——云端 last_play_cid 与起播分P cid 一致才合并 max(本地断点, 云端进度)；不一致/云端 cid 无效（≤0/缺失）忽略云端回退本地；云端 ≥ 分P 时长 95% 从头；本地 -1 已听完从头  
  **Rationale**: 行为可预期、改动最小；匿名态 last_play_cid=0 天然落入「无效即忽略」安全路径  
  **Alternatives considered**: 云端分P 跳转（B 站官方「继续观看」形态，改变点播交互且需处理队列展开连带逻辑，复杂度高一档，弃）

- **Decision D3 last_play_cid 事实核验**：匿名 HTTP 探测（多P 实测视频 BV1tEbj6KEB5，4P）证实 playurl 响应含 last_play_time 与 last_play_cid 字段（匿名值均 0）；字段存在性无需登录态确认，登录态取值形态（是否恒等于云端最后播放分P cid）登记真机 VR  
  **Rationale**: 零新增请求即可获得分P 归属，D2 严格匹配具备数据基础  
  **Alternatives considered**: 切 wbi 端点取历史进度（多一次请求 + 签名依赖，v0.5 轮已证旧端点可用，弃）

- **Decision D4 身份体系取 master 复合键**：历史 upsert/续播查询/已播判定/队列身份/shuffle 轨迹/多选删除全保 master 版（itemKeyOf(bvid,page) 复合键族）；v0.5 的 bvid 粒度实现（bvid-splice upsert、getResumeMsForBvid、bvid-only isPlayed/collectPlayedRemovable/removeSelectedFromPlaylist、bvid 键栈）一律不进入  
  **Rationale**: bvid 粒度在多P 下吞并分P 历史/误删/误判（G2/G5/G6）；master 版是两轮已交付验证过的地基  
  **Alternatives considered**: 取 v0.5 版再补救（重复造复合键轮子，弃）

- **Decision D5 心跳 cid 归属机制**：沿用 v0.5 发送时刻快照设计（上报前取当前 bvid/cid/进度快照，异步响应不回写状态）；master 的 playIndex 在取流前已赋 currentCid，5s 节拍/补报/完播天然携带正确分P cid（调研 G10 证实无缺口）  
  **Rationale**: 既有设计已防快切串台，与多P 语义正交，无需新机制

- **Decision D6 SourcePage 融合策略**：剧集行视觉块取 Pre-update-legacy 结构（Row + Stack(BottomEnd) 16:9 封面 + 时长角标 + 收敛文字区）；点播/播放全部/翻页链路行为函数全取 master（fetchVideoDetail 分P 展开、addSingleVideo、四类触底链路）；头部 56vp 封面行/路由/数据流零改动；触底加载行/空态辅助行不套用新视觉  
  **Rationale**: 视觉与行为都是各自分支已验收的定案，融合=取并集，不引入第三方案  
  **Alternatives considered**: 以 Pre-update-legacy 版为底回填 master 行为（SourcePage 两版改动量相当，以含多P 逻辑的 master 版为底回填视觉更安全，弃）

- **Decision D7 CoverThumb/SettingsPage 干净套用**：master 多P 两轮均未触碰 CoverThumb 与 SettingsPage，Pre-update-legacy 的宽高分离扩展与开关行改动直接套用；套用后复核全部调用点（master 侧调用点集合可能与 Pre-update-legacy 侧有差异）  
  **Rationale**: 单侧改动文件无需融合  
  **Alternatives considered**: 无（唯一路径）

- **Decision D8 Constants/色资源追加式合并**：master 多P 轮未改 Constants 与色资源，心跳域四键 + 详情页缩略 token + duration_badge_scrim 直接追加；实施时核对 master 版 Constants 现状确认无重名  
  **Rationale**: 追加式零冲突  
  **Alternatives considered**: 无

### 融合点处置总表（调研 G1-G10 落点）

| 缺口 | 处置 | 落点 |
|---|---|---|
| G1 云续播分P 错位 | 解析 last_play_cid + 严格匹配合并（D2/D3） | BiliService 解析 + playIndex 合并点 |
| G2 历史条目吞并 | 保 master 复合键 upsert，嫁接 -1→0 重置 + 水位归零（D4） | recordOnPlaying |
| G3 心跳复位位置 | 复位块挂 master playIndex 起播复位区（音质复位邻域） | playIndex |
| G4 续播查询粒度 | 本地断点用 master 分P 粒度查询；云合并插懒展开取流之后（D2） | playIndex |
| G5/G6 bvid 粒度回退 | isPlayed/清除已播/队列删除/shuffle 栈全保 master 版，v0.5 版零进入（D4） | 零改动（不移植） |
| G7 ResolvedAudio 分叉 | 末位默认参数扩展（lastPlayTimeMs/lastPlayCid），master 取流带 cid 直接嫁接解析 | AudioQuality + BiliService |
| G8 SourcePage 双大改 | 视觉取 Pre-update-legacy、行为取 master 手工融合（D6） | SourcePage |
| G9 HistoryMapper 下行 | 本轮无云端历史下行，预留不动 | 零改动 |
| G10 心跳 cid 天然正确 | 无需处理（D5 佐证） | 零改动 |

### Risks

- playIndex 主流程融合复杂（master 形态分叉 A/B + 懒展开与 v0.5 心跳/云合并交织）——实施顺序先服务层后播放层，合并点单一化（只在一处做云合并）
- 心跳挂点位置错导致跨分P 串台——不变式自检覆盖（切分P 必复位；快照必含 cid）
- SourcePage 融合回归——复用 A 轮八项回归核对清单复检
- 登录态 last_play_cid 取值形态未证实——按「无效即忽略」设计兜底，真机 VR 项验证

## Data Model

### ResolvedAudio（entry/src/main/ets/model/AudioQuality.ets）

既有解析结果类，扩展两个末位默认参数字段（既有调用点零改动）：

| 字段 | 类型/默认 | 语义 |
|---|---|---|
| lastPlayTimeMs | number = 0 | 云端最后播放进度（毫秒）；0/缺失 = 无云端数据 |
| lastPlayCid | number = 0 | 云端进度归属分P 标识；0/缺失 = 无效（匿名态/旧数据） |

### Constants 新增（entry/src/main/ets/service/Constants.ets）

| 键/常量 | 值 | 语义 |
|---|---|---|
| KEY_HISTORY_SYNC | 'history_sync'（默认开） | 历史同步开关（preferences 持久化） |
| BILI_HEARTBEAT_URL | web heartbeat 端点 | 心跳上报端点 |
| HEARTBEAT_FAIL_FUSE | 3 | 连败熔断阈值（本分P） |
| HEARTBEAT_MIN_GAP_SEC | 2 | 补报最小间隔（秒） |
| EPISODE_THUMB_W/H | 140/79（vp） | 剧集行 16:9 封面显示尺寸（真机校准占位） |
| EPISODE_THUMB_REQ_W/H | 480/270 | 剧集行封面请求像素档（16:9 CDN 档） |

### 色资源（entry/src/main/resources/base/element/color.json）

duration_badge_scrim = #99000000（时长角标半透明黑底）；角标字色复用既有 fg_on_dark。

### 心跳语境（PlayerController 运行时态，非持久化）

沿用 v0.5 字段设计：当前分P 心跳水位（heartbeatLastSentSec）、连败计数、熔断标志；语义扩展为**随切分P 整体复位重建**（playIndex 起播复位块统一复位，与音质复位同域）。

## Contracts & Interfaces

### BiliService（既有单例，扩展）

- reportHeartbeat(bvid: string, cid: number, playedTimeSec: number): Promise<boolean> —— form POST web heartbeat（type=3 + csrf + 端点要求的 UA），成功/失败布尔返回，调用方熔断计数
- 取流解析契约：DASH/DURL 两条链路的响应解析同时提取 last_play_time 与 last_play_cid，汇聚进 ResolvedAudio 对应字段；零新增请求

### PlayerController（零装饰器纯类，扩展）

- reportHeartbeatIfAdvanced(minGapSec: number): void —— 心跳上行入口（gate: isHistorySyncEnabled；发送时刻快照；熔断短路）；挂点沿用三处（5s 进度节拍 / paused 补报 / 切分P flush）
- reportHeartbeatCompleted(): void —— 完播上行（played_time=-1，当前分P cid）；挂 markCurrentHistoryCompleted（自然完播 + 95% 阈值判定点）
- isHistorySyncEnabled(): boolean —— 已登录 AND KEY_HISTORY_SYNC 开
- playIndex 云端续播合并点（融合位置）：master 懒展开/形态分叉取流完成后、起播 seek 前——本地断点取 master 分P 粒度查询；云端参与条件：lastPlayCid === 起播分P cid 且 lastPlayTimeMs > 0；合并 = max(本地, 云端)，完播阈值防护与本地 -1 优先语义保留
- recordOnPlaying（嫁接）：master 复合键 upsert 原样保留，嫁接 v0.5 的 -1→0 重播重置与心跳水位归零
- 心跳复位：playIndex 起播复位块统一复位水位/连败计数/熔断标志（切分P = 新心跳语境）

### CoverThumb（既有组件，扩展）

thumbWidth/thumbHeight 普通成员：双 >0 走 16:9 档（定尺寸 + sized 缩略请求），否则回退 thumbSize 方形；既有全部调用点零改动。

### SettingsPage（既有页面，追加）

「历史同步」开关行：登录条目下方、未登录隐藏、SettingsRow + KEY_HISTORY_SYNC。

### SourcePage（融合契约）

视觉契约 = Pre-update-legacy 剧集行结构（16:9 CoverThumb + duration_badge 角标 + 标题≤2行/日期/NEW/已播）；行为契约 = master（点播 fetchVideoDetail 分P 展开、播放全部 parts 展开、四类触底翻页、退订/空态/按压态）；头部/路由/数据流零改动。
