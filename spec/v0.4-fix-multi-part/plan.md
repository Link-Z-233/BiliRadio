# Implementation Plan: 多分P 视频播放支持（v0.4-fix-multi-part）

**Input**: Feature specification from `spec/v0.4-fix-multi-part/spec.md`（含第二轮 UX 反馈轮 US6/US7）

## Summary

分P 升为一等公民：多P 视频按分P 展开为独立队列条目（身份键从 `bvid` 扩为 `bvid + 页号`），入队展开（粘贴/订阅点播）与起播惰性展开（播放全部/旧占位条目）双时机覆盖全部入口，零额外请求成本；历史/续播/去重/随机轨迹全部精确到分P；全 UI 显示分P 合成标题。单P 视频与旧持久化数据全链路行为不变。（第一轮，已交付）

**第二轮（UX 反馈轮）**：两处面板展示形态归组，**纯展示层改造**——历史面板对齐 B 站形态：同视频分P 历史按 bvid 归并为一行（主行 `videoTitle`，副行「时间 · 看到Pn · 剩余」，时间最前），点行续播最新分P，删除以视频为单位；队列面板同视频相邻分P 条目渲染视频级分组头（可点击播放续播点：有历史播最新分P、无历史播 P1，队列内跳播、队外插播）。存储、身份键、续播逻辑、`PlayerController` 接口面零变化（仅新增一个只读查询）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 26.0.0）  
**Primary Dependencies**: ArkUI、`@ohos.net.http`（B 站 Web API）、`@kit.RemoteCommunicationKit` rcp（短链）  
**State Management**: 沿用现状——模型层 `@ObservedV2`+`@Trace`，页面 `@ComponentV2`，`PlayerController` 零装饰器广播（`subscribe`/`emitUi`）  
**Storage**: AppStore（preferences）+ JSON 文件（队列/历史持久化，格式向后兼容扩展）  
**Testing**: 无测试套件；验证 = `arkts_check` + `devecocli build`（build-only）  
**Target Platform**: HarmonyOS NEXT（手机/平板）  
**Project Type**: 单模块 HarmonyOS 应用（既有项目增量改造）  
**Performance Goals**: 展开入队零额外网络请求（第一轮）；第二轮归并/分组派生计算 O(n) 一次遍历，千级条目列表滚动不回退  
**Constraints**: 归并/分组均为展示层派生视图，不入持久化（FR-015）；B 站 view 接口 `pages` 字段为分P 数据唯一来源（第一轮约束沿用）  
**Scale/Scope**: 第一轮约 10 文件（已交付）；第二轮约 6 文件（2 model、1 service、1 controller 查询、2 component）  
**基线**: master（v0.4.0，含第一轮交付 `4a81983`）；Pre-update 分支（v0.5 云同步）后续手动合并

## Project Structure

### Documentation (this feature)

```text
spec/v0.4-fix-multi-part/
├── spec.md
├── plan.md              # This file
├── tasks.md
└── bugfix.md            # （按需）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   ├── BiliVideo.ets          # R1: +page/partTitle、composePartTitle、itemKeyOf
│   │                          # R2: +videoTitle（视频级标题独立承载）
│   └── PlayHistoryItem.ets    # R1: +page；R2: +videoTitle/partTitle
├── service/
│   ├── BiliService.ets        # R1: fetchVideoDetail + pages[] 解析
│   │                          # R2: parts 条目填充 videoTitle
│   ├── LinkResolver.ets       # R1: RecognizeResult +page；p 参数抽取（R2 无改动）
│   └── PlayerController.ets   # R1: 身份键重构、双展开、playIndex 分叉
│                              # R2: +latestHistoryOf(bvid) 只读查询（唯一新增）
├── pages/
│   ├── AddSubscriptionSheet.ets  # R1: page 透传（R2 无改动）
│   └── SourcePage.ets            # R1: 单视频点播展开（R2 无改动）
└── component/
    ├── QueueSheet.ets         # R1: 多选/删除复合键；R2: 分组头派生+渲染+点击
    └── HistorySheet.ets       # R1: 点播透传/多选复合键；R2: bvid 归并视图+副行文案+bvid 级多选删除
```

**Structure Decision**: 沿用既有项目架构（无 MVVM 迁移、无新目录、无新文件）。第二轮是第一轮展示链路的横向扩展，改动全部落在既有 model/service/component 职责边界内；`MiniPlayer`/`PlayerOverlay`/`MediaSession`/`AddSubscriptionSheet`/`SourcePage` 第二轮零改动。

## Complexity Tracking

无 Constitution 违规，不需要。

## Research & Decisions

### 第一轮（已交付，D1~D8）

#### D1: 条目身份键选 `bvid + 页号(page)`，cid 保留为取流/云端对齐字段

- **Decision**: 队列条目、历史条目、去重、随机轨迹的统一身份键 = `bvid + page`；`cid` 只作取流参数与云端同步对齐字段，不参与本地身份判定。
- **Rationale**: 旧持久化数据（队列文件/历史文件）中历史条目的 `cid` 大量为 0 或缺失（惰性回填），但「P1」语义恒可通过 `page≤0 → 1` 归一恢复——页号键对旧数据无损，cid 键会制造孤儿条目（旧 `(bvid,0)` 与新 `(bvid,P1cid)` 不匹配，续播进度丢失，违反 SC-005）。B 站官方历史条目同样携带 `page`（`history.page`），语义同源。
- **Alternatives considered**: `bvid + cid`（对齐 B 站数据主键，但旧数据兼容性差）；纯 `bvid`（现状，无法区分分P，第一轮要解决的问题）。

#### D2: 队列条目三形态 + 展开/解析双时机，全入口零额外请求

- **Decision**: 
  - **形态 A（分P 条目）**: `page≥1, cid>0`，标题已合成，元数据自足——起播时**跳过 view 拉取**直接取流；
  - **形态 B（视频级条目/占位）**: `page=0, cid=0`——起播时拉 view：单P 按现状直通（回填后等价形态 A）；多P **就地展开**（本条目原位替换为 P1 分P 条目 + 其后插入 P2..Pn，跳过队列中已存在的同页条目）后播放 P1；
  - **形态 C（旧数据）**: 加载时归一——`page≤0 && cid>0` 升格为形态 A（page=1，旧回填条目实为 P1）；`page≤0 && cid=0` 保持形态 B（未播占位，起播时解析）。
  - 展开/解析发生在两处：**入队时展开**（粘贴链接 `addSingleVideo`、订阅详情页单视频点播——这两处本来就要拉 view，展开零额外请求）；**起播时惰性展开**（播放全部入队的视频级条目、旧占位条目——`playIndex` 本来就拉 view，展开零额外请求）。
- **Rationale**: 分P 数据唯一来源是 view 接口；任何展开都必须伴随一次 view 响应。把展开时机绑定在「本来就发生 view 请求」的节点上，是零成本覆盖全部入口的唯一方案。
- **Alternatives considered**: 全部入队时展开（N 次 view 请求，否决）；全部起播时惰性展开（粘贴后队列只见 1 条目，违反 US1 验收）。

#### D3: `playIndex` 按条目形态分叉取流

- **Decision**: 形态 A（cid>0）跳过 `fetchVideoInfo`，直接 `resolveAudioTrack(bvid, item.cid)`；形态 B 拉取 view 详情后单P 直通（现状路径）或多P 就地展开（D2）。展开产生的新 P1 条目复用同一份 view 响应，不重复请求。
- **Rationale**: 现状 `playIndex` 无条件拉 view 并用 `video.cid`（恒 P1）覆盖条目 cid——这是「永远只播 P1」的直接根因。分P 条目自足后跳过拉取，既修根因又省一次冗余请求。
- **Alternatives considered**: 保留无条件拉 view、仅改为「按条目 page 从响应 pages 中选 cid」（多一次冗余请求，分叉不可避免，不如让形态 A 直接短路）。

#### D4: 分P 标题合成规则——同视频分P 条目间恒可区分

- **Decision**: 单P 视频条目标题 = 视频标题（不缀）。多P 视频分P 条目：分P 名非空且 ≠ 视频标题 → `「视频标题 · Pn 分P名」`；分P 名为空或与视频标题相同 → `「视频标题 · Pn」`。
- **Rationale**: spec FR-008 字面规则在「10 个分P 名都等于视频标题」的边界下产生 10 个同名队列条目，直接违反 US5 验收。本规则是对 FR-008 意图（可辨识）的收敛。
- **Alternatives considered**: spec 字面规则（可产生同名条目，否决）；恒显示完整合成（P1 且分P 名=标题时冗长）。

#### D5: `BiliService` 新增 `fetchVideoDetail`，`fetchVideoInfo` 降为薄包装

- **Decision**: 新增返回类型 `VideoDetail`（视频级元数据 + 分P 数组，单P 视频的分P 数组恰含 P1 一条）；`fetchVideoInfo` 保留原签名返回 `VideoDetail.video`。view 响应的 `pages[]` 解析集中在新方法。
- **Rationale**: 分P 数据与视频元数据来自同一 view 响应，拆两个接口必致重复请求；薄包装保住 `PlayerOverlay` desc 回填等「只要视频级」的调用方。
- **Alternatives considered**: `fetchVideoInfo` 直接改返回类型（所有调用方连带改）；BiliVideo 上挂 pages 子数组（模型职责混杂）。

#### D6: 复合键字符串形态 `bvid:page`，既有 string 轨迹结构零改造

- **Decision**: 随机轨迹、队列多选删除、历史多选删除、清空已播等既有 `string[]` 结构全部改存复合键 `bvid:page`（page 归一化后参与拼接）。提供唯一合成/解析帮助函数（`BiliVideo.itemKeyOf`），禁各处手拼。
- **Rationale**: 这些结构现状存裸 bvid；改存复合键是键语义升级的最小 diff 路径。
- **Alternatives considered**: 引入结构化键类型（数组结构连锁改造，无对应收益）。

#### D7: 已听标记维持 `bvid` 宽松口径（本轮不动）

- **Decision**: `isPlayed(bvid)`、SourcePage `playedSet` 语义与实现均不变。
- **Rationale**: spec Assumptions 已定案（分P 数感知需逐视频 view 请求，成本否决）。
- **Alternatives considered**: 分P 粒度已听标记（需分P 总数，数据不可得）。

#### D8: 就地展开的队列操作契约

- **Decision**: 形态 B 条目起播展开时：P1 分P 条目**原位替换**本条目（currentIndex 不变）；P2..Pn **插入其后**，插入前按复合键跳过队列中已存在的同页条目；展开后 `playlistVersion++` 并持久化，再以已持有的 view 数据继续 P1 的取流。
- **Rationale**: 原位替换保证 `currentIndex` 指向连续；跳过已有页避免重复插入。占位条目比较时 `page 0 ≡ 1`（归一化访问）。
- **Alternatives considered**: 展开条目全部追加到队尾（打乱「播放全部」顺序语义，否决）。

### 第二轮（UX 反馈轮，D9~D14）🆕

#### D9: 归并/分组为纯展示层派生视图，存储与控制器语义零变化

- **Decision**: 历史面板与队列面板在渲染层各自派生「展示视图」——HistorySheet 从分P 粒度 `playHistory` 派生「归并行数组」；QueueSheet 从 `playlist` 派生「条目 + 组头标志」。`PlayerController` 的存储结构（分P 粒度）、身份键、持久化格式、播放/删除逻辑全部不变；controller 侧唯一新增是一个只读查询（D13）。
- **Rationale**: FR-015 回归约束——第一轮刚交付的复合键/独立进度/续播链路是本轮地基，动存储层必引入回归面；归并是纯函数式派生（分P 数组进、视频级行数组出），风险隔离在 UI 层。历史面板与云同步（视频级去重）的形态对齐在展示层完成，存储保持分P 粒度两头不误。
- **Alternatives considered**: 历史存储直接改视频级（丢分P 进度粒度，违反 SC-003/FR-015，否决）；controller 维护归并视图（上帝对象再膨胀，否决）。

#### D10: `videoTitle`/`partTitle` 数据链补齐（B 站式主行的数据前提）

- **Decision**: `BiliVideo` 新增 `videoTitle` 字段（视频级标题；分P 条目由 `fetchVideoDetail` 填充为视频标题，视频级/占位条目 = `title` 自身；持久化）。`PlayHistoryItem` 新增 `videoTitle`/`partTitle` 字段（持久化，`fromVideo` 透传）。历史归并行主行用 `videoTitle`（加载缺省回退 `title`——旧数据兼容降级）；副行「看到Pn」段只显示页号，`partTitle` 供历史点播回放构造队列条目的显示名。
- **Rationale**: 现状历史条目 `title` 存的是合成标题（「视频标题 · Pn 分P名」），US6 主行要纯视频标题、副行要纯分P 名——从合成标题反解析不可靠（分隔符可出现在分P 名中）。第一轮 `BiliVideo.partTitle` 已承载分P 名，缺的只是视频标题的独立承载与历史透传。
- **Alternatives considered**: 合成标题字符串剥离（脆，分P 名可含「 · 」等字符，否决）；历史主行沿用合成标题（用户已选 B 站式，否决）。

#### D11: 历史归并行的派生规则与交互映射

- **Decision**: HistorySheet 在 `syncFrom` 后派生归并行数组：按 bvid 聚合，行内取 `viewAt` 最新的分P 条目为「看到」状态源；行排序 = 该 bvid 最新 `viewAt` 倒序（与现状时间序感知一致）。交互全部映射到既有能力：点行 → 以「看到」分P 条目走既有 `replayHistory` 路径（`playDownloadedSong` 插播 + 分P 历史进度续播）；左滑单删/多选批删 → UI 层把 bvid 展开为该视频全部分P 复合键，调既有 `removeSelectedHistory(keys)`；多选 ID/全选/计数全部 bvid 级。LazyForEach 数据源从分P 数组换归并行数组（键 `bvid_最新viewAt`）。
- **Rationale**: 删除与点播全部落在第一轮已交付的复合键接口上，controller 零改动；UI 展开 bvid→pages 为 O(n) 一次遍历。
- **Alternatives considered**: controller 新增视频级删除接口（扩散改动面，UI 展开已足够，否决）。

#### D12: 队列分组头的派生与渲染

- **Decision**: QueueSheet 在 `syncFrom` 拷贝队列后对副本派生组头标志：仅「分P 条目（page≥1）且前一条目同 bvid 且同为分P 条目」的**组首条目**置位（相邻 ≥2 条成组；随机打散后不相邻自然无头；占位条目不成组）。渲染：组首条目 `ListItem` 顶部条件渲染组头块（`videoTitle`，弱化样式，按既有列表头组件规范）。组头块独立 `onClick`，不参与条目按压高亮/多选/左滑。
- **Rationale**: 头与组首条目绑定渲染，避免 LazyForEach 头/条目双类型数据源的大改；组头标志是纯派生值，随 `playlistVersion` 重算，头下条目删至不成组时自动消失（SC 边界）。
- **Alternatives considered**: 渲染单元数组（头单元+条目单元交替的 DataSource，改动大，否决）；头独立 ListItem（数据源与全部下标逻辑连锁改，否决）。

#### D13: 组头点击 = 播放续播点，两段判定

- **Decision**: 点击组头时确定目标分P：① 该 bvid 存在播放历史 → 目标 = 最新 `viewAt` 的分P（续播其历史进度）；② 无历史 → 目标 = 组内最小 page 的条目（通常 P1，从头播）。定位执行：目标分P 条目在队列内（复合键匹配，占位 `0≡1`）→ 复用队列条目点击的既有跳播入口；不在队列（仅①场景可能）→ 以该历史条目元数据构造分P 条目走 `playDownloadedSong` 插播。为①提供查询，`PlayerController` 新增只读方法 `latestHistoryOf(bvid): PlayHistoryItem | null`（零装饰器纯类，无状态写入）。
- **Rationale**: 「有历史播历史、无历史播 P1」为用户定案；队列内跳播是最短路径（目标条目就在组内）；插播回退仅覆盖「历史指向队列外分P」的边缘（如 P1 已从队列删除但历史在 P1）。
- **Alternatives considered**: 恒插播构造（队列内明明有目标条目还新建，引入重复风险，否决）；恒跳组首（有历史场景丢失续播点，否决）。

#### D14: 历史副行文案三段组装（时间最前）

- **Decision**: 副行 =「相对时间 · 看到Pn · 剩余/已听完」三段拼接：相对时间恒最前（用户定案）；中段插入条件 = 归并代表分P 的 `page > 1`，显示「看到Pn」（分P 名不展示——第三轮用户定案修订，原为「看到Pn 分P名」）；尾段沿用既有规则（`progress===-1` →「已听完」；有进度且时长已知 →「剩 mm:ss」；降级省略）。
- **Rationale**: 三段全部复用既有格式化函数，新增的只是中段插入与排序。中段以 `page>1` 判定而非分P 计数：仅听过 P2 的多P 视频（该 bvid 历史计数为 1）也能正确显示「看到P2」；多P 视频仅有 P1 历史时与单P 不可区分（B 站总页数未知，不为副行引入额外存储），按单P 形态显示可接受。
- **Alternatives considered**: 无（格式为用户定案）。

#### D15: 队列两级呈现与组级交互（修订 D12 形态）

- **Decision**: 组首条目渲染升级为「视频头行 + 分P 窄行」两级：头行 = 封面（CoverThumb，无高亮）+ `videoTitle`（Medium 字重）+ 右侧「共 nP」，独占一行；组内条目行体换窄行（无封面，`Pn partTitle` + 时长，左缩进 `QUEUE_PART_INDENT` 对齐头行标题）；单P/孤立条目保持原有整行（新 `isGroupedPart` 派生：前或后相邻同 bvid 分P 条目）。组级交互三项：①头行点击非多选仍走 D13；②多选态头行前置换 Checkbox 整组切换（`groupKeys`/`isGroupFullySelected`/`toggleGroupSelect`，Checkbox 无半选态——部分选中显示未选）；③组首 ListItem 左滑 = 整组移除（`confirmRemoveGroup`，确认弹窗标注分P 数，走既有 `removeSelectedFromPlaylist` 链路），其余条目保持单条左滑。
- **Rationale**: 头行与组首分P 同属一个 ListItem，swipeAction 只能挂 ListItem——组首左滑语义定为整组移除（头行左滑的用户直觉即「移除这个视频」），组首分P 的单删走多选兜底。窄行左缩进与头行标题起点对齐（`TOKEN_SPACE_L + 封面 44 + TOKEN_SPACE_10 = 70`，入 `Constants.QUEUE_PART_INDENT`）。崩溃修复（bugfix.md ## 1.）与本改造同轮：分组派生函数守卫越界 + 删除后 `onDataChange` 强制重绑（FR-019）。
- **Alternatives considered**: 渲染单元数组数据源（头/条目/整行三类型混排，diff 与删除动画连锁改造，否决）；头行独立 ListItem（同上）；头行左滑不实现（组级移除只剩多选路径，用户明确要，否决）。
- **已知取舍**: 多选滑动范围选的 `ITEM_HEIGHT`（68）对窄行（约 36）偏高，计数偏保守——仅影响多选效率，`ponytail:` 注释标注，不引入双高度模型。
- **Trim（用户定案，图示确认后追加）**: 组内管理收敛头行——分P 窄行删勾选框/左滑/单键长按，多选点击与长按改整组语义（`groupStartIndex` 回溯组首后走 `groupKeys`/`toggleGroupSelect`），`selectRange` 组感知（区间碰组补全组键，孤立/单P 按单键）；组为最小管理粒度（单分P 不可单独删/勾）。副产物不变式：组勾选恒全选/全不选，「部分选中显示未选」歧义态消失。

## Data Model

### BiliVideo（`model/BiliVideo.ets`）

| 字段 | 类型 | 语义 | 轮次 |
|------|------|------|------|
| `page` | number | 页号：≥1 分P 条目；0 视频级占位（形态 B）。`@Trace`，持久化，加载归一见 D2 形态 C | R1 已交付 |
| `partTitle` | string | 分P 名（B 站 `part` 字段）；视频级条目为空。`@Trace`，持久化 | R1 已交付 |
| `videoTitle` | string | 视频级标题：分P 条目 = 所属视频标题；视频级/占位条目 = `title` 自身。`@Trace`，持久化；旧数据加载缺省回退 `title`。组头与历史归并主行的数据源 | R2 🆕 |

静态方法：`composePartTitle`（D4）、`itemKeyOf`（D6）——R1 已交付，R2 不变。

不变式：形态 A 条目 `page≥1 && cid>0 && title 已合成`；形态 B 条目 `page===0 && cid===0`。

### PlayHistoryItem（`model/PlayHistoryItem.ets`）

| 字段 | 类型 | 语义 | 轮次 |
|------|------|------|------|
| `page` | number | 页号；加载归一 `≤0 → 1`。`@Trace`，持久化 | R1 已交付 |
| `videoTitle` | string | 视频级标题（归并行主行）。`@Trace`，持久化；旧数据缺省回退 `title` | R2 🆕 |
| `partTitle` | string | 分P 名（历史点播回放构造队列条目的显示名；副行「看到Pn」段不展示）。`@Trace`，持久化 | R2 🆕 |

身份键：`bvid + page`（D1，不变）。`fromVideo` 透传 page/videoTitle/partTitle。

### VideoDetail（`service/BiliService.ets`，R1 已交付）

`video` + `parts[]`；R2 增量：parts 条目填充 `videoTitle`（= 视频级 title），其余不变。

### 展示视图模型（纯 UI 层，不入持久化，R2 🆕）

- **历史归并行**（HistorySheet 内部类）：`bvid`、`latest`（viewAt 最新的分P `PlayHistoryItem`，行状态源）、`partCount`（该视频分P 历史计数，中段「多P」判定用）
- **队列组头标志**（QueueSheet 内部派生）：组首条目 `showGroupHeader` 布尔（D12 规则）

## Contracts & Interfaces

### BiliService（`service/BiliService.ets`）

- `fetchVideoDetail(bvid: string): Promise<VideoDetail>`——R1 已交付；R2：parts 条目 `videoTitle` 填充
- `fetchVideoInfo(bvid: string): Promise<BiliVideo>`——薄包装，不变
- `fetchVideoInfoByAid(aid: number): Promise<BiliVideo>`——不变

### LinkResolver（`service/LinkResolver.ets`）

- `recognizeInput(input): RecognizeResult`——R2 零改动

### PlayerController（`service/PlayerController.ets`）

- `latestHistoryOf(bvid: string): PlayHistoryItem | null`——**R2 唯一新增**：该 bvid 全部分P 历史中 `viewAt` 最新的一条；无历史返回 null。只读，不写状态不发广播
- 其余全部复用 R1 已交付接口：`removeSelectedHistory(keys: string[])`（复合键数组，UI 展开调用）、`playDownloadedSong`、`playIndex`/队列跳播入口、`removePlayHistoryItem(bvid, page)`、`replayHistory` 消费链——签名与语义零变化

### HistorySheet（`component/HistorySheet.ets`，R2 🆕）

- `syncFrom` 后派生归并行数组（D11）；DataSource 数据源换归并行
- 行渲染：主行 `videoTitle`（回退 `title`）、副行三段文案（D14）、封面/时间沿用
- 多选 bvid 级：ID、全选、计数、删除展开（bvid → 全部分P 复合键 → `removeSelectedHistory`）
- 左滑单删：同展开路径（该 bvid 全部分P）
- 点行：`replayHistory(latest)` 既有路径

### QueueSheet（`component/QueueSheet.ets`，R2 🆕 / R3 🆕🆕）

- `syncFrom` 后派生组头标志（D12）；R3：组首升级为视频头行两级呈现（D15），组内条目换分P 窄行，单P 保持整行
- 组头点击：D13 两段判定（`latestHistoryOf` → 队列内跳播 / `playDownloadedSong` 插播 / 组内最小 page 跳播）
- R3 组级交互：头行多选 Checkbox 整组切换；组首 ListItem 左滑 = 整组移除（确认弹窗标注分P 数，走既有批量移除链路）；组身分P 管理收敛头行（无左滑/勾选框，长按与多选点击整组语义，范围选组感知）
- R3 崩溃修复（bugfix.md ## 1.）：分组派生函数守卫 index 越界；数据源增 `notifyDataChange`，增量删除后从最低删除位到末尾强制重绑 LazyForEach 缓存条目闭包 index（FR-019）
- 条目级操作（点击跳播/左滑/多选）与 R1 复合键机制零变化

### 持久化兼容契约（R2 扩展）

- 队列文件新增 `videoTitle` 字段、历史文件新增 `videoTitle`/`partTitle` 字段：旧文件缺字段 → 默认空 + 加载回退（`videoTitle` 空 → 回退 `title`；`partTitle` 空 → 副行省略中段），读取/续播/展示零丢失（SC-005 沿用）
- 归并行/组头标志均为运行时派生，不落盘——降级安装旧版本后自动回到第一轮形态

## Changelog

- **2026-10-15 第三轮（崩溃修复 + 两级呈现）**：Research & Decisions 增 D15（队列两级呈现与组级交互，修订 D12 形态；含用户定案的管理收敛头行 Trim——分P 无左滑/勾选，范围选组感知）；Contracts 队列面板契约升 R3；spec.md 增 US8 / FR-016~FR-020 / SC-011 / 边界三条；新增 bugfix.md（## 1. 移除多P 条目 jscrash 根因与修复）。理由：真机复现移除多P 条目 jscrash（LazyForEach 过期 index），修复同轮叠加用户定案的两级呈现改造（视频头行 + 分P 窄行 + 头行整组多选 + 组首左滑整组移除）。
- **2026-10-14 第二轮（UX 反馈轮）**：Summary 增第二轮段落；Research & Decisions 增 D9~D14（纯展示层总纲 / videoTitle 数据链 / 归并派生与交互映射 / 组头派生渲染 / 组头点击两段判定 / 副行三段文案）；Data Model 增 `videoTitle`/`partTitle` 与两个展示视图模型；Contracts 增 `latestHistoryOf` 与两面板展示层契约、持久化兼容扩展；Project Structure 标注 R1/R2 轮次改动。理由：spec.md 第二轮 US6（历史 B 站式归并）+ US7（队列分组头）用户逐项定案（B 站式主行、时间最前、组头点击按历史续播无则 P1），FR-015 约束纯展示层改造。
