# Implementation Plan: v0.6-part1 收藏夹归属显示与队列联动取消收藏

**Input**: Feature specification from `spec/v0.6-part1-fav-unfavorite/spec.md`

## Summary

三条主线：① 修复 `folderIds` 死数据缺口——在 SourcePage 收藏夹订阅入队漏斗 stamp 来源夹标识与归属 mid（借鉴初始版 FoldersPage 的 stamp 模式，改到订阅流），随队列持久化；② 五条队列移除路径全部汇入 `removeSelectedFromPlaylist` 单点，在该点拦截：命中「登录账号本人收藏夹来源」条目时经确认回调（复用 `confirmCellularDownload` 模式）聚合询问，确认后逐条调既有 `BiliService.unfavorite`，失败不阻塞本地移除；③ 收藏夹详情页按归属差异化显示（归属数据来自 `fav/resource/list` 的 `info.mid`/`info.upper`，PiliPlus 模型旁证，实测后补录 BILI_NOTES），设置页登录状态行移到账号组下方。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0），ArkUI
**Primary Dependencies**: 零第三方依赖；`@kit.NetworkKit` http、hilog
**State Management**: 增量改动——沿用现状 V2（`@ComponentV2`/`@Local`/`@Trace`/`V2State` 包装）；`PlayerController` 新增公开状态沿用零装饰器广播模式（字段 + `emitUi`）
**Storage**: AppStore preferences（订阅/队列/历史既有持久化，无新存储）
**Testing**: 无测试套件；`arkts_check` + `devecocli build` 静态验证
**Target Platform**: HarmonyOS NEXT（手机/平板）
**Project Type**: 单模块移动应用
**Performance Goals**: 归属信息一次拉取永久持久化（夹主人 mid 不变）；移除拦截路径零额外网络请求（纯本地比对）
**Constraints**: B 站风控（-412）——unfavorite 逐条串行、失败聚合提示不重试轰炸；`info` 字段实测未做，解析须防御式（字段缺失降级，功能不崩）
**Scale/Scope**: 改动约 9 个既有文件，无新文件

## Project Structure

### Documentation (this feature)

```text
spec/v0.6-part1-fav-unfavorite/
├── spec.md
├── plan.md              # 本文件
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   ├── BiliVideo.ets          # +folderOwnerMid 字段（@Trace + 序列化）
│   └── Subscription.ets       # +folderOwnerMid/folderOwnerName（@Trace + 序列化）
├── service/
│   ├── BiliService.ets        # +fetchFolderInfo（info.mid/upper.name 防御式解析）；partFromVideo 透传 folderOwnerMid
│   ├── PlayerController.ets   # removeSelectedFromPlaylist 拦截 + unfavorite 执行 + unfavoriteCurrent 归属门禁
│   └── Constants.ets          # 弹窗/toast 文案令牌
├── pages/
│   ├── SourcePage.ets         # 入队 stamp 漏斗 + 归属回填 + 页头/剧集行归属化显示
│   ├── SettingsPage.ets       # statusMsg 状态行移位（底部 → 账号组下方）
│   └── Index.ets              # confirmUnfavoriteRemoval 回调接线（AlertDialog）
└──（QueueSheet 零改动——拦截在控制器单点）
```

**Structure Decision**: 沿用既有架构（service/model/pages 分层、依赖单向、无 MVVM 迁移、无新文件）。拦截点选 `PlayerController.removeSelectedFromPlaylist` 而非 QueueSheet 五个调用方：五条移除路径（多选/左滑单条/左滑组/清除已播/清空队列）已全部汇入该单点，控制器级拦截使 UI 调用方零改动且未来新移除路径天然覆盖。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 确认回调跨层（controller→Index 弹窗） | 控制器无 UIContext，移除拦截需用户选择 | QueueSheet 侧拦截需改 5 个调用方且「清除已播」键集计算是控制器私有内部，暴露即泄漏内部结构 |
| BiliVideo/Subscription 各加 1 个序列化字段 | 队列条目须自洽携带归属（跨重启、跨订阅存续、换账号比对） | 移除时反查 Subscription：订阅可能已删而队列条目仍在；条目自洽无反查 |

## Research & Decisions

### R1: folderIds 源头缺失的根因与 stamp 模式来源

- **Decision**: 在 SourcePage 入队漏斗 stamp：`sub.type === TYPE_FAV` 时对每个入队条目 `folderIds = [sub.sourceId]`、`folderOwnerMid = sub.folderOwnerMid`
- **Rationale**: git 考古（e0a1f53 初始版）证实 `folderIds` 原生填充点是 FoldersPage 合并歌单流程（`v.folderIds.push(folder.mediaId)`），FoldersPage 在 2050b84 重构中删除后字段成死数据，`unfavoriteCurrent` 判定随之不可达。订阅流的等价填充点是入队漏斗；`loadPlaylistAndPlay` 按复合键去重，同一视频从不同夹入队首个 stamp 生效，不累积
- **Alternatives considered**: fetch 阶段 stamp（SubscriptionStore 刷新时写入剧集缓存）——缓存条目与入队条目分离，`playEpisode` 走 fetchVideoDetail 生成全新对象不经过剧集缓存，覆盖不全；入队漏斗 stamp 两处（enqueueSelected/enqueueAndToast）全覆盖
- **不复活**: UnfavoriteRecord 取消收藏历史/恢复功能（52d102e 已明确移除，不回锅）

### R2: 移除拦截点与确认交互

- **Decision**: 拦截在 `removeSelectedFromPlaylist` 内部：映射 keys→条目 → 过滤「folderIds 非空 && folderOwnerMid === session.mid && 已登录」→ 命中则 `await confirmUnfavoriteRemoval(count)`（count 为去重 aid 数）→ 确认后先移除再逐条 `BiliService.unfavorite(item.aid, item.folderIds)`（串行，失败聚合）→ 结果经 toast tick 广播；拒绝或无命中则纯移除（现状语义）
- **Rationale**: 五条移除路径已全部汇入该单点（清空队列经 `clearAllWithExitDelay`、清除已播经 `clearPlayedItems` 最终均到此处）；确认回调复用 `confirmCellularDownload` 既有模式（controller 字段 + Index.ets 接线 AlertDialog），结果 toast 复用 `errorTick` 模式（tick 版本比对 + Index toast）
- **Alternatives considered**: QueueSheet 侧拦截——五调用方重复且「清除已播」键集计算是控制器私有；合并进既有五个确认弹窗（三按钮/复选）——交互侵入大、五处弹窗结构各异

### R3: 归属数据路径

- **Decision**: 新增 `BiliService.fetchFolderInfo(mediaId)`（`fav/resource/list` pn=1 ps=1，解析 `info.mid`/`info.upper.name`，防御式：字段缺失返回空值）；SourcePage 进入 fav 订阅且 `sub.folderOwnerMid === 0` 时调用并持久化到 Subscription（夹主人 mid 恒定，一夹一次永久生效）；`upper.name` 缺失时降级 `fetchUpInfo(info.mid)`（acc/info→card 既有降级链）
- **Rationale**: PiliPlus `FavFolderInfo` 模型旁证 `info` 含 `mid`/`upper`（Owner: mid/name/face）；夹主人 mid 是收藏夹内禀属性不变，持久化后零重复请求。BILI_NOTES 未覆盖 info 字段，实测后补录 §3
- **Alternatives considered**: `fetchMyFolders` 列表比对——仅能判「本人夹」，非本人夹的主人名（页头显示需要）拿不到；`info` 路径一次请求同时解决归属判定与主人名

### R4: 页头/剧集行显示规则实现

- **Decision**: SourcePage `headerRow`：fav 订阅且 `folderOwnerMid !== session.mid` 且 `folderOwnerName !== ''` 时页头标签行追加主人名 Text（样式同合集/系列 upperName 位）；`episodeRow`：fav 订阅且归属本人时，日期 Text 后追加「· 来源UP名」（`item.ownerName`，text_secondary，空则不渲染）
- **Rationale**: 数据零新增请求——主人名来自 R3 持久化字段，剧集 ownerName 已在剧集缓存链路（`parseFolderMedias` 填充、`BiliVideo` 序列化）；显示位沿用既有标签行/日期行样式令牌
- **Alternatives considered**: UP 名独立成行——剧集行高已固化（EPISODE_THUMB_H 68 贴顶/贴底契约），追加行破坏行高契约

### R5: unfavoriteCurrent 归属门禁

- **Decision**: 播放层既有「取消收藏当前条目」在 `folderIds` 非空判定后追加归属检查：`folderOwnerMid !== session.mid` 时置 statusMsg「该收藏夹不属于当前账号」并返回，不发请求
- **Rationale**: stamp 后非本人夹条目也携带 folderIds，按钮对非本人夹变为可达但必然失败（deal 无权限），提前门禁优于报错；已登录判定维持现状

### R6: 设置页状态行移位

- **Decision**: `SettingsPage` statusMsg 渲染块从列表底部（通用组之后）移到账号设置组末尾；覆盖式更新逻辑不动
- **Rationale**: 状态发生在账号区，移位后即时可见；无清空逻辑按 Phase 1 结论不补

### R7: 清除已播含当前在播已完成条目（追加）

- **Decision**: `collectPlayedRemovable` 去除 `currentKey` 排除（已看完/异常命中即收，含当前条目）；`playedRemovableCount` 同步去除 `containsCurrent` 跳过（计数与实际清除口径一致）；`removeSelectedFromPlaylist`/`removingCurrent` 链路零改动（停播+自动切播+空队列重置语义既有）
- **Rationale**: 修正 v0.3「当前条目永远保留」口径——已看完的当前条目保留无意义；移除当前条目链路已有多选移除先例，直接复用
- **Alternatives considered**: 仅 isPlayed 放行、异常当前条目仍保留——同为可清标记却区别对待，口径分裂，一行 diff 得不偿失

## Data Model

**BiliVideo**（model/BiliVideo.ets，@ObservedV2）:
- `+ folderOwnerMid: number = 0`（@Trace；toRecord/fromRecord 序列化）——入队 stamp 的来源夹归属 mid，0 = 未知
- 既有 `folderIds: number[]` 语义不变（来源夹 ID 列表，现状恒 `[sub.sourceId]` 单元素）

**Subscription**（model/Subscription.ets，@ObservedV2）:
- `+ folderOwnerMid: number = 0`（@Trace + toRecord/fromRecord）——fav 订阅的夹主人 mid，0 = 未回填
- `+ folderOwnerName: string = ''`（@Trace + toRecord/fromRecord）——夹主人昵称，非本人夹页头显示用

**FolderInfo**（service/BiliService.ets 内部返回结构）:
- `mediaId: number`、`ownerMid: number`、`ownerName: string`、`title: string`、`mediaCount: number`——`fetchFolderInfo` 解析产物，字段缺失置默认值

**PlayerController 新增公开成员**（零装饰器广播模式）:
- `confirmUnfavoriteRemoval: ((count: number) => Promise<boolean>) | null = null`——UI 确认回调
- `unfavToastTick: number = 0` + `unfavToastMsg: string = ''`——取消收藏结果 toast 广播（Index.ets tick 比对 toast）

## Contracts & Interfaces

**BiliService.fetchFolderInfo(mediaId: number): Promise<FolderInfo>**
- GET `x/v3/fav/resource/list?media_id={mediaId}&pn=1&ps=1`；解析 `info.mid`/`info.upper.name`/`info.title`/`info.media_count`，全防御式（undefined/null 跳过置默认）；`info.mid` 缺失视为获取失败（返回 ownerMid=0，调用方不持久化）

**PlayerController.removeSelectedFromPlaylist(keys: string[]): Promise<void>**（签名不变，行为扩展）
- 移除前：keys→playlist 条目映射 → 命中集 = `folderIds.length > 0 && folderOwnerMid === session.mid && isLogged()` 的条目（aid 去重计数）→ 非空且回调已设 → `await confirmUnfavoriteRemoval(count)`；true → 移除执行后按命中条目串行 `BiliService.unfavorite(aid, folderIds)`，全成/部分败聚合写入 `unfavToastMsg` + tick++；false/无命中/回调未设 → 纯移除（现状）
- 拦截 await 期间队列可能变化：确认后重新按 bvid+page 校验条目仍在队列再取消收藏（已不在则跳过该条）

**SourcePage 入队 stamp 契约**
- `enqueueSelected`/`enqueueAndToast` 在调用 `loadPlaylistAndPlay` 前：`sub.type === TYPE_FAV` → 每条 `folderIds = [sub.sourceId]`（仅当原为空）、`folderOwnerMid = sub.folderOwnerMid`
- `BiliService.partFromVideo` 透传 `folderOwnerMid`（占位条目就地展开链路不丢归属）

**显示规则（SourcePage 渲染时判定，纯本地）**
- 页头：fav && `folderOwnerMid !== session.mid` && `folderOwnerName !== ''` → 标签行显示主人名
- 剧集行：fav && `folderOwnerMid === session.mid` → 日期后追加「· ownerName」（空不渲染）
- 未登录（session.mid = 0）：`folderOwnerMid !== 0` 恒真 → 按非本人显示（符合 spec）

**unfavoriteCurrent 门禁**
- 顺序：条目存在 → `folderIds` 非空 → **新增**：已登录 && `folderOwnerMid === session.mid`（0 视为未知放行，保持向后兼容旧数据）→ 执行

**文档同步契约**
- `BILI_NOTES.md` §3 补录：`fav/resource/list` `info` 字段实测结论（mid/upper.name 存在性；真机验证后补录，注明 PiliPlus 旁证）
- `docs/architecture.md`：BiliVideo/Subscription 字段职责、PlayerController 拦截职责、SourcePage stamp 职责同步对应表

**Constants 新增令牌**
- 弹窗标题/文案、结果 toast 文案（成功 N 首/部分失败）、门禁 statusMsg——一律 `Constants.TOKEN/DIALOG_*` 命名，禁裸字符串
