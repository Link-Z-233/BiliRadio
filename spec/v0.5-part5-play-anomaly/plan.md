# Implementation Plan: v0.5-part5 播放态数据源异常标记

**Input**: Feature specification from `spec/v0.5-part5-play-anomaly/spec.md`

## Summary

播放链路在 AVPlayer prepared 后比较实际流时长与条目元数据时长，显著偏短判定为数据源异常（充电视频试听流），per-bvid 持久化 X 标记（AppStore preferences 单键 JSON 数组，PlayerController 零装饰器广播模式持有）；按设置「异常源自动跳过」（默认开）toast 提醒 + 日志登记 + 线性推进下一首，关闭则照常播放试听流；完播自动写 ✓ 的路径对 X 条目设防（试听完成不产生 ✓）；重播拉到完整流自动摘 X。X 显示于源页剧集行、队列条目、历史条目三处。互动视频判定本轮不做。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: ArkUI（@ComponentV2 状态管理 V2）、media.AVPlayer、preferences（@kit.ArkData）
**State Management**: 增量沿用现状——已迁 V2 页面/组件继续 V2 装饰器；PlayerController 保持零装饰器纯类（字段 + emitUi 广播 + syncFrom 快照），新增公开 UI 状态沿用该模式，禁止加观测装饰器
**Storage**: AppStore preferences（设置项 KEY_ANOMALY_SKIP、X 标记集 KEY_ANOMALY_BVIDS）
**Testing**: 无测试套件；构建验证 + 真机验证（设备返回后）
**Target Platform**: HarmonyOS NEXT 单模块应用（entry）
**Project Type**: mobile-app（音频电台类 B 站客户端）
**Performance Goals**: 检测在 prepared 回调内完成（纯数值比较，零额外 IO 除首次持久化）；跳过推进无感衔接
**Constraints**: 不引入新文件（全部改动落入既有 6 文件）；不污染播放历史/云同步；Constants 唯一真相源（所有新 token 只在 Constants.ets 定义）
**Scale/Scope**: 检测点 1 处、设置行 1 行、显示点 3 处、持久化键 2 个

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part5-play-anomaly/
├── spec.md
├── plan.md              # This file
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── Constants.ets        # 新增 token：KEY_ANOMALY_SKIP / KEY_ANOMALY_BVIDS / ANOMALY_DURATION_RATIO / TOAST_ANOMALY_SKIP / TOAST_ANOMALY_TRIAL
│   └── PlayerController.ets # 检测与标 X（prepared 判定）/摘 X/线性跳过推进/完播 ✓ 防护/anomalySet 公开字段与广播/全链路日志
├── pages/
│   ├── SettingsPage.ets     # 「异常源自动跳过」设置行（SettingsRow showToggle，落播放分组）
│   └── SourcePage.ets       # 剧集行 X 标记（对齐 playedSet 加载机制）
└── component/
    ├── QueueSheet.ets       # 条目行尾 X（对齐 isPlayed 直查模式）
    └── HistorySheet.ets     # 历史行尾 X
```

**Structure Decision**: 沿用现有项目架构（pages/service/component/model 分层、零新文件）。本特性为播放链路增量改造：检测逻辑天然归属 PlayerController（播放态判定的唯一持有者），存储复用 AppStore，显示复用三个既有组件的行渲染。无 MVVM 迁移诉求，不引入 viewmodel/data 目录。

## Complexity Tracking

无宪法违规。

## Research & Decisions

### D1 检测点：AVPlayer prepared 后的 player.duration，不解析 playurl 响应字段

**Decision**: 检测放在 PlayerController 既有 prepared 处理（`this.duration = this.player.duration` 赋值点）之后，比较实际流时长（player.duration，毫秒）与条目元数据时长（item.duration 秒 × 1000）。
**Rationale**: player.duration 即「拉到的流时长」本义，数据现成、零新增解析；playurl 响应 timelength 在试听流下的口径未实证（试听时长还是完整时长不明），durl length 字段同理，解析它们要先解决口径问题。
**Alternatives considered**: playurl 响应预检（timelength/durl[0].length vs 元数据时长）——可更早拦截但口径未实证；AudioPlayer 层回调上抛——多一层转发无收益。

### D2 判定条件与阈值：只判「显著短于」，比值阈值 token 化

**Decision**: 元数据时长有效（item.duration > 0）且流时长有效（player.duration > 0）且 `player.duration < item.duration × 1000 × ANOMALY_DURATION_RATIO` 判定为异常；ANOMALY_DURATION_RATIO 初始 0.5（试听流与完整内容差距巨大，0.5 远离正常流的轻微偏差），真机实测后校准 token。
**Rationale**: 试听流只可能显著短于元数据；反向（流长于元数据）常源于列表元数据不可靠，判它会误伤，不判。阈值 0.5 预留巨大裕度，正常流（时长与元数据差 ±数秒）远不会触碰。
**Alternatives considered**: 绝对差阈值（秒）——对长短视频不对称，比值更稳；双向不等判定——反向误伤如上。

### D3 X 存储：preferences 单键 JSON 数组，PlayerController 持有

**Decision**: `KEY_ANOMALY_BVIDS`（字符串键，JSON 数组序列化的 bvid 集）。PlayerController init 时加载为 `Set<string>` 公开字段 `anomalySet`，变更即 putString 持久化 + emitUi 版本推进；消费方按 syncFrom/直查模式读取。无硬性条数上限：preferences 官方定位轻量存储（建议万条内），本特性增长极慢（同 bvid 只写一次、摘标即删），用户级几十到几百条封顶，不加 LRU 类裁剪。
**Rationale**: bvid 集合体量小，preferences 足够；与 KEY_* 设置项同载体，无新文件新存储形态；PlayerController 是播放态判定的唯一写入方，集中持有避免双写。
**Alternatives considered**: 独立文件（play_history.json 模式）——集合体量不需要；扩展 SubscriptionStore——X 是跨源全局标记，不属于订阅域。

### D4 跳过推进：线性推进不复用取模 next，toast 提醒 + 日志登记

**Decision**: 判定异常且设置=跳过时：标 X → toast 提醒（`TOAST_ANOMALY_SKIP`，复用 PLAYBACK_ERROR_DEDUP_MS 去重窗模式）→ 日志登记 → 若 `currentIndex + 1 < playlist.length` 则 `playIndex(currentIndex + 1)`，否则停在队尾（不取模回绕）。全链路日志以 `Logger.log('player', ...)` 登记：判定结果（流时长/元数据时长/bvid）、标 X、摘 X、跳过推进（目标 index）、照常续播、完播防护触发——跳过对用户可感知（toast），对排查可追溯（日志）。
**Rationale**: 既有 next() 取模循环会绕回队首，违反「队列线性推进、全异常逐个跳过到队尾即停」边界；连续异常条目逐个走同一判定路径，天然串行推进。跳过是静默改写播放顺序的行为，必须 toast + 日志双通道留痕。
**Alternatives considered**: 复用 next()（取模）——循环风险；收集队列中全部异常一次性弹窗——交互重、无必要；仅日志不 toast——用户无感，违背「给用户提醒」要求。

### D5 完播 ✓ 防护：自动写 -1 路径对 X 条目设防，手动标记不拦

**Decision**: 完播自动写 progress=-1 的两条路径（completed 态、进度 ≥ 时长×完播阈值）在当前条目 bvid 命中 anomalySet 时跳过写 -1；手动「标记已看完」不拦截（✓ 与 X 共存，用户主动行为优先）。防护触发写日志。
**Rationale**: 试听播完≠看完，写 -1 会产生假 ✓ 并污染云同步（-1 上行）；手动标记是用户明确意图，不该被拦。
**Alternatives considered**: 在时长回填处拦截——治标，完播判定仍会触发；X 条目禁止入历史——照常播放模式下试听有续播价值，历史条目保留。

### D6 摘标（FR-007）：prepared 时复检，匹配即清除

**Decision**: prepared 判定时若 bvid 已在 anomalySet 且本次流时长匹配元数据（非异常），移除该 bvid + 持久化 + emitUi + 日志登记。
**Rationale**: 用户充电后重播拉到完整流是唯一可信的恢复信号；prepared 是流时长的可信取值点。
**Alternatives considered**: 手动清除入口——多一套 UI 无必要；定期复检——没有独立于播放的检测手段。

### D7 设置项：0/1 toggle，默认开（=跳过），播放链路现读

**Decision**: `KEY_ANOMALY_SKIP`（number 0/1，默认 1），SettingsPage 播放分组新增 SettingsRow（showToggle，「异常源自动跳过」+ 描述文案）；播放链路在判定异常时现读设置，无缓存，切换即时生效。
**Rationale**: 对齐既有布尔设置范式（KEY_AUTO_PLAY_ON_START 等同构）；两态枚举用 toggle 比选择器少一层交互。
**Alternatives considered**: 三态选择（跳过/照常/询问）——spec 只定义两态。

### D8 显示：三处行尾 X，对齐 ✓ 视觉，✓/X 可共存

**Decision**: SourcePage 剧集行、QueueSheet 条目、HistorySheet 行尾在 bvid 命中异常集时显示 X 图标（sys.symbol.xmark，实施前在 sysResource.js 校验存在性），视觉对齐既有 ✓（sys.symbol.checkmark_circle）的行尾角标模式。SourcePage 侧 anomalySet 随 playedSet 同点加载进 @Local；QueueSheet/HistorySheet 走 controller 直查（对齐 isPlayed 模式）。✓ 与 X 并存时同时显示（手动标记场景）。
**Rationale**: 三处显示点已有 ✓/已听完 角标先例，X 复用同一位置与尺寸语义；加载机制各随其组件既有数据流，不引入新通道。
**Alternatives considered**: 仅队列显示——spec FR-002 明确三处；文字标签「试听」——历史行已有文字段，图标在三处更统一。

### D9 拉流失败天然不进判定路径（FR-006）

**Decision**: 异常判定只在 prepared 成功回调内执行；网络错误/风控在 openStream 阶段抛错走既有错误处理（toast/日志），不会到达判定点，无需额外防护代码。
**Rationale**: 判定点的位置本身即防护；无需在错误路径加「不标 X」的负逻辑。

### D10 真机校准口径与退化路径

**Decision**: AVPlayer 对 durl 试听流的 duration 可得性按「取到即判定、取不到（=0）则 D2 有效性条件天然跳过」实施；真机实测若确认取不到，功能退化为不标不跳（无副作用），届时切换 D1 备选（playurl 字段预检）另议。
**Rationale**: 先按零成本路径实施，实测失败再启用备选，避免为未证实的口径预写解析代码。
**Alternatives considered**: 直接实施 playurl 字段预检——口径未实证，预写风险大于收益。

### D11 X 图标带圆圈（追加）：对齐 ✓ 视觉档

**Decision**: 三处显示点（SourcePage 剧集行/QueueSheet 两处/HistorySheet）的 X 图标由 `sys.symbol.xmark` 改为 `sys.symbol.xmark_circle`（sysResource.js id 125831488，已确认存在），字号 `TOKEN_FONT_TITLE`、色 `danger_red`、边距对齐 ✓（`checkmark_circle`）既有视觉档。
**Rationale**: 裸 X 与带圈 ✓ 不同档，用户要求视觉一致；`xmark_circle` 与 `checkmark_circle` 同为空心圆圈轮廓系。
**Alternatives considered**: `xmark_circle_fill`（实心）——视觉过重，与空心 ✓ 不对齐。

### D12 「清除已播」纳入 X 条目（追加）：判定口径三处同步

**Decision**: `collectPlayedRemovable`（实际移除集合）与 `playedRemovableCount`（确认弹窗计数）的判定由 `isPlayed(bvid)` 扩展为 `isPlayed(bvid) || hasAnomaly(bvid)`；当前播放条目保留语义（currentKey 排除）不变。
**Rationale**: 队列中被 X 的条目对用户无收听价值（试听流），与已听完条目同属「可清」语义；判定、计数、移除三处必须同口径防歧义；当前条目保护是既有 FR 约束不动。
**Alternatives considered**: 独立「清除异常」入口——多一套交互无必要，用户明确要求并入「清除已播」。

## Data Model

### Constants.ets 新增 token

- `KEY_ANOMALY_SKIP`: number 0/1 偏好键（默认 1=跳过）
- `KEY_ANOMALY_BVIDS`: string 偏好键（JSON 数组，异常 bvid 集）
- `ANOMALY_DURATION_RATIO`: number = 0.5（流时长/元数据时长低于此值判异常，真机校准）
- `TOAST_ANOMALY_SKIP` / `TOAST_ANOMALY_TRIAL`: string 文案

### PlayerController 增量

- `anomalySet: Set<string>`（公开字段，init 加载，零装饰器广播模式）
- `hasAnomaly(bvid: string): boolean`（公开查询）
- 内部：判定流程（prepared 后）→ markAnomaly/clearAnomaly（持久化 + emitUi + 日志）→ 设置分流（跳过推进 / 照常续播）→ 完播写 -1 路径防护

### 状态流转

```text
playIndex → resolveAudioTrack → openStream → prepared
  → 判定（D2 条件）→ 日志登记判定结果
    ├─ 异常 → 标 X（D3）→ 跳过开：toast + 日志 + 线性推进（D4）/ 跳过关：toast + 日志 + 续播试听
    ├─ 匹配且已有 X → 摘 X（D6），正常播
    └─ 匹配无 X → 正常播
完播（completed / 95% 阈值）→ bvid 命中 X 集 → 不写 -1 + 日志（D5）
```

## Contracts & Interfaces

### PlayerController 公开接口增量（消费方契约）

- `anomalySet: Set<string>`：纳入 emitUi 版本推进；消费方 syncFrom 快照或直查 hasAnomaly
- `hasAnomaly(bvid: string): boolean`：三处显示点统一查询入口

### 设置契约

- 设置页「异常源自动跳过」toggle：读 `AppStore.getNumber(KEY_ANOMALY_SKIP, 1)`，写 putNumber；关闭即「照常播放试听流」

### 显示契约

- X 语义=数据源异常（拉到的流时长 ≠ 元数据时长，试听流）；✓ 语义=已听完（不变）；手动标记已看完时 ✓/X 共存
- 跳过的条目不写新历史条目（跳过发生在写史时机之前则不产生条目；既有历史条目保留原状仅显示 X）

### 日志契约（可观测性）

- 判定、标 X、摘 X、跳过推进、照常续播、完播防护六类事件全部 `Logger.log('player', ...)` 登记，含 bvid 与关键数值（流时长/元数据时长/目标 index）
