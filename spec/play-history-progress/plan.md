# Implementation Plan: 播放历史与进度记录（B 站历史同步预留）

**Input**: Feature specification from `spec/play-history-progress/spec.md`

## Summary

将 `PlayHistoryItem` 扩展为携带进度、时长、cid、秒级时间戳的记录（对齐 B 站历史条目格式），`PlayerController.recordOnPlaying` 由「删旧建新」改为「upsert 保留进度」，进度持久化搭现有 5 秒节拍（`persistProgress`）写入；再次播放同一内容时按「未听完续播 / 已听完（≥95% 或播完，progress=-1）从头」智能决定起点；历史面板增加进度展示与单条左滑删除；新增 `HistoryMapper` 作为本地条目 ↔ B 站历史格式的集中映射边界（本轮零网络调用）；旧数据经 `fromRecord` 容错平滑迁移。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 6.1.1(24) / targetSdkVersion 26）  
**Primary Dependencies**: ArkUI 声明式 UI、`@kit.AVSessionKit`（AVPlayer 媒体会话，既有）、hilog  
**State Management**: 沿用项目现有 State Management V1（`@State`/`@StorageLink`/`@Watch` + `PlayerController` 单例 `emitUi` 广播 + `playHistoryVersion` 版本号驱动面板刷新）；增量特性不引入 V2、不做迁移  
**Storage**: 沿用现有方案——`context.filesDir/play_history.json`（本地 JSON 文件，经 `AppStore.loadPlayHistoryFile/savePlayHistoryFile`）+ `preferences`（全局断点 KEY_LAST_INDEX/KEY_LAST_POS_MS，保持不动）  
**Testing**: 项目无自动化测试框架；验证方式为 `devecocli build` 编译验证 + 模拟器/实机手动用例（见 tasks.md Verification 阶段）  
**Target Platform**: HarmonyOS NEXT 手机/平板（API 24+）  
**Project Type**: mobile-app（现有工程增量特性）  
**Performance Goals**: 进度写盘搭现有 5s 节拍，历史文件全量 ≤200 条（约几十 KB）写盘耗时可忽略；UI 刷新沿用版本号+LazyForEach，无新增高频渲染  
**Constraints**: 本轮 MUST NOT 发起任何 B 站历史同步网络请求（FR-012）；异常退出进度回退 ≤ 一个节拍（5s，满足 FR-007 的 ≤30s）  
**Scale/Scope**: 改动 6 个既有文件 + 新增 1 个映射文件；涉及页面 1 个（SettingsPage 历史面板）、服务 2 个（PlayerController/AppStore）、模型 1 个、常量 1 个；回归点 1 个（SourcePage 已听标记）

## Project Structure

### Documentation (this feature)

```text
spec/play-history-progress/
├── spec.md              # 需求规格（Phase 1 产物）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产物）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── PlayHistoryItem.ets        # [修改] 扩展 viewAt(秒)/progress(秒,-1=看完)/duration(秒)/cid 四字段，
│                                   #        fromVideo 签名演进、toRecord/fromRecord 迁移兼容
├── service/
│   ├── Constants.ets              # [修改] 新增 PLAY_COMPLETE_RATIO = 0.95
│   ├── HistoryMapper.ets          # [新增] B 站历史条目格式镜像 + 本地条目双向映射纯函数（同步预留边界，FR-011）
│   ├── AppStore.ets               # [不变] load/savePlayHistoryFile 签名不变；迁移由 PlayHistoryItem.fromRecord 承担
│   └── PlayerController.ets       # [修改] recordOnPlaying 改 upsert、persistProgress 扩展进度写盘、
│                                   #        playIndex 续播起点、完播判定、removePlayHistoryItem 单条删除
└── pages/
    ├── SettingsPage.ets           # [修改] 历史面板：进度展示（剩余时长/已听完）、左滑单条删除、formatPlayedAt 适配秒
    └── SourcePage.ets             # [回归点] loadPlayedSet 读取历史文件——迁移后 bvid 仍在，行为不变，仅验证
```

**Structure Decision**: 遵循现有项目架构（`pages/`/`component/`/`service/`/`model/`，无 `viewmodel/`、无 `data/`）。本特性为存量工程增量迭代：UI 层改动收敛在既有 `SettingsPage` 面板，业务逻辑收敛在既有 `PlayerController` 单例，持久化沿用 `AppStore` 文件方案，仅新增一个纯函数映射文件 `HistoryMapper.ets` 落在 `service/`（项目惯例：跨模型转换/领域逻辑均在 service）。不触发 MVVM 条件（无新页面、无跨页复杂状态），不引入目录重构。

## Complexity Tracking

无 Constitution Check 违规，无需豁免条目。

## Research & Decisions

### R1 进度记录的承载：扩展 PlayHistoryItem，而非独立进度表

- **Decision**: 进度直接记在播放历史条目上（`progress`/`duration`/`cid` 字段），历史即进度。
- **Rationale**: ① 现有去重置顶逻辑（同 bvid 单条）天然就是「每集一条进度」；② B 站历史条目同样内含 progress，模型一比一对齐；③ 避免两份状态（历史文件 + 进度文件）互相同步与迁移拆分。
- **Alternatives considered**: 独立的 `bvid→progress` 映射文件——被否：双份持久化状态需要一致性维护，且未来同步时仍需按条目合并，等于把复杂度后置。

### R2 时间戳字段：`playedAt`(毫秒) → `viewAt`(秒)

- **Decision**: 模型字段改为 `viewAt`（秒级时间戳，对齐 B 站 `view_at`）；`fromRecord` 迁移：新字段缺失且旧字段 `playedAt` 存在时 `viewAt = floor(playedAt/1000)`；`toRecord` 不再写出 `playedAt`。
- **Rationale**: 单位与命名对齐 B 站，未来同步零换算歧义；文件为应用私有数据，无回滚旧版本的兼容义务。
- **Alternatives considered**: 保留 `playedAt` 毫秒、映射时换算——被否：换算散落在展示层（`formatPlayedAt`）与映射层两处，违背 FR-011「单位转换集中」的目标。

### R3 `recordOnPlaying` 改 upsert（本特性最关键的行为修正）

- **Decision**: `playing` 状态触发的记录写入改为：命中同 bvid 旧条目时**保留** progress/duration/cid，仅刷新 viewAt/title/cover/ownerName/sourceType 后置顶；未命中才新建（progress=0）。
- **Rationale**: 现实现是「删旧建新」——直接扩展字段后，每次续播都会把进度重置为 0，智能续播永远失效；upsert 是进度语义成立的前提。
- **Alternatives considered**: 保留删旧建新、在删除前拷贝 progress——被否：等价于 upsert 但逻辑绕，且遗漏字段风险高。

### R4 续播决策点：`playIndex` 内部、仅当 `seekMs === 0` 时查询

- **Decision**: 在 `playIndex(index, seekMs)` 中，当 `seekMs <= 0` 时查询该 bvid 的历史进度决定起点（`getResumeMsForBvid`）；`seekMs > 0` 时完全不查询，沿用调用方指定值。
- **Rationale**: 现有 4 类调用方已通过 `seekMs` 表达意图：全局断点恢复（启动续播）、换音质保进度（resumePos）、手动拖动后的重播；这些路径必须零干扰。只有「新起播」（seekMs=0，如点历史条目、点单集入队、切歌）才需要历史续播介入。
- **Alternatives considered**: 在各调用方（SettingsPage.replayHistory 等）各自查询——被否：调用点分散（切歌 next/prev、队列点击、历史点击），逐个改容易漏，且把领域规则泄到 UI 层。

### R5 完播判定：progress = -1 的写入时机

- **Decision**: 两处写入 `progress = -1`：① `onPlayerState('completed')`；② `onPlayerTime` 中 `duration > 0 && currentTime >= duration × PLAY_COMPLETE_RATIO(0.95)`。`duration` 未知（=0）时不做 ② 判定，仅记 progress。
- **Rationale**: completed 覆盖自然播完；阈值判定覆盖「拖到结尾附近停住/切走」的场景（B 站同语义）。duration 未知时无从计算比例，保守不判定，符合 spec Edge Case。
- **Alternatives considered**: 只在 completed 时标记——被否：听 97% 后手动切歌的场景会被判为未听完，重播时从 97% 续播，体验怪异。

### R6 进度持久化时机：搭 `persistProgress` 既有 5s 节拍

- **Decision**: 扩展现有 `persistProgress()`：在写全局断点（preferences）的同时，更新当前条目 `progress`（内存）并节流写历史文件（`savePlayHistoryFile`，沿用 `PROGRESS_SAVE_INTERVAL_MS = 5000` 节拍 + 既有 `setTimeout(0)` 异步写盘模式）。切歌（`playIndex` 进入时 flush 旧条目）、暂停（`paused` 分支既有 `persistProgress` 调用）、播放完成（completed）为即时写盘点。
- **Rationale**: 节拍/调用链全部复用，不新增定时器；异常退出最多丢 5s，满足 FR-007（≤30s）。200 条全量 JSON 写盘在异步线程可忽略。
- **Alternatives considered**: 每秒写盘——被否：无必要的 IO 放大；改用 preferences 存进度——被否：条目化数据放 JSON 文件与现架构一致。

### R7 cid 与 duration 的来源与回填

- **Decision**: `cid` 取 `currentCid`（流式路径 `video.cid` 已写入）或 `BiliVideo.cid`（`applyTrackMeta`/`enrichTrackMeta` 回填到队列条目）中可用者；`duration` 取 prepared 后 `player.duration`（毫秒→秒），`BiliVideo.duration`（已是秒）作冷启动兜底。记录时机（upsert 与节拍）二者择非零值写入。
- **Rationale**: 两处来源各有覆盖场景（本地缓存秒播走 enrich，流式走 currentCid），取可用者最稳。
- **Alternatives considered**: 只信 currentCid——被否：本地缓存路径 currentCid 复位为 0。

### R8 单条删除与数据源通知

- **Decision**: `PlayerController.removePlayHistoryItem(bvid: string)`：splice + `playHistoryVersion++` + 异步写盘；`SettingsPage` 面板 `ListItem.swipeAction({ end: 删除按钮 builder })`，点击执行（KI-3 交互约定：不做滑过阈值直删）；`HistoryDataSource` 删除时调用 `notifyDataDelete` 同步 LazyForEach。
- **Rationale**: 对齐 KI-3 登记的交互约定与现有「清空需二次确认」的谨慎风格；LazyForEach 数据源若不通知会出现残留渲染。
- **Alternatives considered**: 整表重设 `setItems`——可行但全量刷新，删除单条场景粒度不当。

### R9 同步预留边界：`HistoryMapper.ets` 纯映射层

- **Decision**: 新建 `service/HistoryMapper.ets`：定义 `BiliHistoryRecord`（B 站历史条目格式的本地镜像：bvid/cid/progress/duration/viewAt/title/showTitle/authorName/cover/business）与双向纯静态映射 `toBiliHistory(PlayHistoryItem)` / `fromBiliHistory(BiliHistoryRecord)`。本轮无网络调用方，`fromBiliHistory` 供未来拉取合并使用。
- **Rationale**: FR-011 要求映射集中独立；独立文件 + 纯函数让未来同步模块（心跳/拉取/合并）即插即用，也让「本地模型改动不得破坏 B 站对齐」有单点检查处。
- **Alternatives considered**: 映射方法挂在 PlayHistoryItem 上——被否：模型类将同时承担本地持久化格式与外部协议格式两种职责，违背预留边界的隔离意图。

### R10 面板进度展示格式

- **Decision**: 历史条目第二行展示：`progress === -1` → 「已听完」标识（text_secondary 样式徽标）；`progress > 0 && duration > 0` → 「剩 mm:ss」（duration-progress 秒格式化）；其余（progress=0 或 duration 未知）→ 沿用现有日期文本。`formatPlayedAt` 改为接收秒并可与剩余时长同行拼接。
- **Rationale**: 音频场景「还剩多久」比百分比更有决策价值；duration 未知时诚实降级为现状展示。
- **Alternatives considered**: 百分比——被否：音频进度百分比感知弱于剩余时长。

## Data Model

### PlayHistoryItem（扩展后，`model/PlayHistoryItem.ets`）

| 字段 | 类型 | 单位/语义 | 默认值 | 迁移规则（fromRecord） |
|------|------|-----------|--------|------------------------|
| bvid | string | 内容唯一标识（条目主键，全局单条） | '' | 沿用；缺失则条目丢弃（现有行为） |
| title | string | 标题 | '' | 沿用 |
| ownerName | string | UP 主名 | '' | 沿用 |
| cover | string | 封面 URL | '' | 沿用 |
| sourceType | number | 0=收藏夹 / 1=合集 / 2=本地（沿用） | 2 | 沿用 |
| viewAt | number | **秒级**时间戳（最后播放时间） | 0 | 新字段缺失且旧 `playedAt`(ms) 存在 → `floor(playedAt/1000)` |
| progress | number | **秒**；**-1 = 已看完**；0 = 未记录进度 | 0 | 缺失 → 0 |
| duration | number | **秒**；0 = 未知 | 0 | 缺失 → 0 |
| cid | number | 分P标识；0 = 未知 | 0 | 缺失 → 0 |

状态转移：`progress: 0 → (>0 播放中持续更新) → -1（completed 或 ≥95%）`；`-1 → 0`（重播时 upsert 重置）；条目置顶于每次真实出声（playing）。

### BiliHistoryRecord（新增，`service/HistoryMapper.ets`）

B 站历史接口条目格式的本地镜像（字段对照参照 PiliPlus `HistoryItemModel`/`History`）：

| 字段 | 对应 B 站字段 | 说明 |
|------|---------------|------|
| bvid | history.bvid / 项级 bvid | UGC 视频标识 |
| cid | history.cid | 分P标识 |
| progress | progress | 秒；-1 = 看完（单位/语义已对齐，映射直通） |
| duration | duration | 秒 |
| viewAt | view_at | 秒级时间戳 |
| title | title | 标题 |
| showTitle | show_title | 分P名（本轮本地无此数据，映射时置空，结构占位） |
| authorName | author_name | UP 主名 |
| cover | cover | 封面 |
| business | history.business | 固定 `'archive'`（UGC 视频） |

映射规则：`toBiliHistory`/`fromBiliHistory` 为字段一一对应 + 少量占位填充的纯函数，无 IO、无状态。

### 与全局断点的关系

`KEY_LAST_INDEX`/`KEY_LAST_POS_MS`（preferences，全局断点续播）**保持原样独立**：每集进度是历史条目上的新增能力层，两者数据不共享、写入点解耦（节拍同车但各写各的），互不干扰。

## Contracts & Interfaces

### PlayerController（`service/PlayerController.ets`）——新增/修改

| 成员 | 签名 | 行为契约 |
|------|------|----------|
| getResumeMsForBvid | `(bvid: string): number` | 查询续播起点（毫秒）：条目存在且 `progress > 0` 且 `progress !== -1` 且（`duration > 0` 时 `progress < duration × PLAY_COMPLETE_RATIO`）→ `progress × 1000`；否则 `0`。纯查询，无副作用 |
| removePlayHistoryItem | `(bvid: string): void` | 按 bvid 单条删除：命中则 splice、`playHistoryVersion++`、异步写盘；未命中静默。面板经版本号感知刷新 |
| recordOnPlaying（改） | `(video: BiliVideo): void` | upsert 语义：同 bvid 命中 → 保留 progress/duration/cid，刷新 viewAt(秒)/title/cover/ownerName/sourceType 后置顶；未命中 → 新建（progress=0）。仍仅在 `playing` 状态触发 |
| persistProgress（改） | `(): void` | 原有全局断点写入保持；新增：当前条目 `progress = floor(currentTime/1000)`（completed 路径外恒 ≥0）+ 沿 5s 节拍异步写历史文件 |
| playIndex（改） | `(index, seekMs, fromNav)` | 进入时若旧曲目有效则即时 flush 其进度；`seekMs <= 0` 时以 `getResumeMsForBvid(新条目.bvid)` 决定起点；`seekMs > 0` 路径零变化 |
| onPlayerState / onPlayerTime（改） | — | completed → 当前条目 `progress = -1` 并即时写盘；tick 中完播阈值判定（R5）→ `progress = -1` |

### HistoryMapper（`service/HistoryMapper.ets`）——新增

| 成员 | 签名 | 行为契约 |
|------|------|----------|
| toBiliHistory | `(item: PlayHistoryItem): BiliHistoryRecord` | 本地条目 → B 站历史条目格式；单位直通（秒/秒/秒级时间戳），showTitle 置空、business='archive' |
| fromBiliHistory | `(rec: BiliHistoryRecord): PlayHistoryItem` | B 站历史条目 → 本地条目（sourceType 置 SOURCE_LOCAL，进度语义原样保留含 -1）；本轮无调用方，为未来拉取合并预留 |

### AppStore（`service/AppStore.ets`）——签名不变

`loadPlayHistoryFile()/savePlayHistoryFile(items)` 签名与文件路径不变；旧数据兼容完全由 `PlayHistoryItem.fromRecord` 的字段默认值与迁移规则承担（FR-006）。

### SettingsPage 历史面板（`pages/SettingsPage.ets`）——UI 契约

| 交互 | 契约 |
|------|------|
| 条目展示 | 第二行：已听完徽标 / 「剩 mm:ss」 / 日期（降级），对应 FR-008 |
| 点击条目 | 走既有 `replayHistory` → `playFromLibraryResult`，续播由 playIndex 内部规则生效（FR-010） |
| 左滑条目 | `swipeAction` end 露出「删除」按钮（红色），点击调 `removePlayHistoryItem`，数据源 `notifyDataDelete`（FR-009） |
| LazyForEach key | 现有 `bvid_playedAt` 改为 `bvid_viewAt_progress`，保证进度变化与删除正确驱动刷新 |

### Constants（`service/Constants.ets`）——新增

| 常量 | 值 | 用途 |
|------|-----|------|
| PLAY_COMPLETE_RATIO | 0.95 | 完播阈值（FR-003/FR-004），不暴露为设置 |

### 不变式（实现与验证共同遵守）

1. `progress` 只取 `-1` 或 `≥0` 秒数；`-1` 仅由完播写入，重播 upsert 时重置为 0。
2. `viewAt` 恒为秒级；任何写入点不得传入毫秒。
3. 同一 bvid 在 `playHistory` 中至多一条（upsert 保证）。
4. 全局断点（KEY_LAST_INDEX/KEY_LAST_POS_MS）的读写路径零改动。
5. 本特性代码路径不得出现任何 B 站网络请求调用（FR-012，验证时以代码检索 + 运行期无新请求确认）。
