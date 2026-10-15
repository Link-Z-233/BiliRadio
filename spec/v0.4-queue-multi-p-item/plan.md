# Implementation Plan: 队列多P 视频条目化重写

**Input**: Feature specification from `spec/v0.4-queue-multi-p-item/spec.md`

## Summary

把队列面板的渲染与交互模型从「扁平分P 条目 + 渲染期 index 派生组头」重写为「展示条目」：派生构建 `QueueEntry`（组条目/单条目）作为 LazyForEach 数据源，选择、计数、横划、按压、拖选全部以条目为单位；PlayerController 新增条目分组单一来源方法，随机播放抽取粒度升级为条目级（组内连播优先），清除已播计数改条目口径。队列存储、持久化格式、身份键、历史/续播/去重零变化。三个真机 bug（头行无按压反馈且长按不进多选、多选按分P 计数、横划只动组首 ListItem）由结构消除。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0，API 26）  
**Primary Dependencies**: ArkUI（LazyForEach/IDataSource/swipeAction/GestureGroup）、@kit.ArkUI（promptAction）  
**State Management**: 增量改造——QueueSheet 保持 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；PlayerController 保持零装饰器纯类（subscribe/emitUi 广播 + playlistVersion，消费方 syncFrom 拷贝）；不引入 V1 装饰器  
**Storage**: 零变化——AppStore 播放列表持久化文件、身份键 `BiliVideo.itemKeyOf(bvid, page)`、历史/续播/去重全部保持  
**Testing**: 无测试套件；验证 = 构建 + 部署（默认 build-only）  
**Target Platform**: HarmonyOS NEXT 单模块应用（entry）  
**Performance Goals**: 队列懒加载保持（LazyForEach 条目级）；删除路径保持增量通知避免封面闪烁；百级分P 单条目渲染流畅度留真机待验  
**Constraints**: 模块边界契约（`spec/v0.3-engineering-refactor/architecture-boundary.md`，依赖单向 service→model、pages/component→service/model）；令牌规范（色彩 `$r('app.color.*')`、数值 `Constants.TOKEN_*`，魔法数字进 Constants 或文件头局部常量）；ArkTS 严格模式禁 any/unknown/as 断言（SDK BusinessError 回退除外）  
**Scale/Scope**: 改动 2 文件（QueueSheet.ets 重写渲染与交互、PlayerController.ets 增量改播控），无新文件

## Project Structure

### Documentation (this feature)

```text
spec/v0.4-queue-multi-p-item/
├── spec.md               # 需求（第四轮 UX 反馈，独立目录）
├── plan.md               # 本文件
└── tasks.md              # 任务拆解（/spec-tasks 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── component/
│   └── QueueSheet.ets        # 重写：QueueEntry 模型 + 条目化数据源/渲染/选择/拖选/横划
└── service/
    └── PlayerController.ets  # 增量：条目分组方法、随机条目级抽取、组内连播、已播计数条目口径
```

**Structure Decision**: 沿用现有工程架构（单模块 pages/component/service/model 分层），不引入新目录与新文件。`QueueEntry` 为纯展示层模型且仅 QueueSheet 消费，置于 `QueueSheet.ets` 文件域（与现有 `PlaylistDataSource` 同级放置）；条目分组规则是播控与展示共用的单一来源，置于 `PlayerController`（队列语义的属主）。删除/清空/持久化链路全部复用既有方法，签名不变。

## Complexity Tracking

无宪法违规。新增复杂度集中在一处（QueueSheet 条目化重写），以此换取删除三组渲染期派生函数（`hasGroupHeader`/`isGroupedPart`/`groupStartIndex`/`groupKeys`/`isGroupFullySelected` 等约 10 个 index 数学函数）与其伴随的越界守卫负担。

## Research & Decisions

### D1: 展示条目模型 QueueEntry（取代渲染期 index 派生）

**Decision**: `playlistVersion` 变更时由扁平 `BiliVideo[]` 一次性派生 `QueueEntry[]`：相邻（≥2 条）同 bvid 且页号≥1 的条目构成组条目（`videos` 持全部分P、`startIndex` 持扁平起始下标、key 为 `g:{bvid}`），其余为单条目（`videos` 单元素、key 为 `s:{bvid}:{page}` 归一化）。组内分P 的扁平下标 = `startIndex + 组内偏移`，天然连续。
**Rationale**: 现有三个 bug 同根于「组头塞进组首分P 的 ListItem」——派生函数在渲染期做 index 数学，头行无独立交互面、横划只动一个 ListItem。实体化条目后组条目=一个 ListItem，三 bug 结构性消失；派生 O(n) 一次性完成，删除全部渲染期 index 数学与越界守卫面。
**Alternatives considered**: 保留扁平 ListItem 仅修补三症状（头行加手势、计数换算、头行拆独立行）——修补面分散且「头行独立行」无法实现整组滑动；ListItemGroup（不支持组级 swipeAction，整组横划无解）。

### D2: 条目级数据源与增量 diff（回退整表 reload）

**Decision**: `PlaylistDataSource` 持 `QueueEntry[]`。`syncFrom` 时重建条目数组并与旧条目按 key 序列 diff：新序列可由旧序列纯删除得到 → 逐项 `notifyDataDelete`（高到低）+ 从最低删除位到末尾 `notifyDataChange` 强制重绑（bugfix #1 机制保留，条目级）；否则（增长/重排/组分裂/组缩减/组消失中混有变更）整表 reload。
**Rationale**: 常见删除路径（多选移除、整组横删、单条左滑、清空）均为整条目删除 → 走增量不闪封面；组内单删（`unfavoriteCurrent` splice）与含当前条目的清除已播（组被裁剪）是少数路径 → 回退 reload，行为正确优先。
**Alternatives considered**: 全量 reload 一条路——每删一条闪一次封面（现状已优化的回归）；条目内容级 diff（组缩减时 onDataChange 局部刷新）——为罕见路径引入键变更复杂度，不值。

### D3: 选择单位条目化，移除时展开分P 键

**Decision**: 选中集从分P 复合键改为**条目键**（`g:{bvid}` / `s:{bvid}:{page}`），`selectedEntryKeys: string[]` 仅 QueueSheet 内部持有。多选徽标、全选、收敛判定全部按条目键。确认移除时在 QueueSheet 内把选中条目键展开为该条目全部分P 复合键，调用既有 `removeSelectedFromPlaylist(分P键[])`（removingCurrent/removedBeforeCurrent 索引修正、自动切播、持久化全套语义零改动）。
**Rationale**: 计数与选择单位天然一致（bug ② 消除）；PlayerController 移除链路保持分P 粒度，播控层不感知条目概念（除随机抽取）。
**Alternatives considered**: 选中集仍存分P 键、计数时换算条目数——两套粒度并存，收敛与全选判定复杂且易错。

### D4: 头行交互补全（按压反馈 + 长按多选）

**Decision**: 组条目的视频头行挂 `onTouch` 按压高亮（`pressedKey` 记条目键）与 `GestureGroup(LongPress + Pan)` 手势组：长按进多选并选中本组条目、Pan 拖选以条目为单位——与单条目整行手势组完全同构。非多选点头行保持两段判定续播（`latestHistoryOf` → 最新历史分P；无历史 → 条目内最小页），多选态点头行整组切换。头行 Checkbox 选中态 = 条目键 ∈ 选中集。
**Rationale**: bug ① 根因是头行无手势面；条目化后头行是 ListItem 内普通行，手势与按压直接挂载，与整行组件复用同一模式。
**Alternatives considered**: 仅加按压不加长按——多选入口缺位依旧。

### D5: 拖选按条目估算高度累积换算

**Decision**: 条目派生时同步维护每条目估算高度（单条目 ≈ 68；组条目 ≈ 头行估算 + 分P 数 × 分P 行估算，估算值来自现有 padding/字号常量，文件头局部常量）。拖选 Pan 的 offsetY 从起始条目起按累积估算高度换算目标条目下标，`selectRange` 对区间内条目整条目选中（组键或单键）。宽屏禁用拖选（现状保持）。
**Rationale**: 现有 ITEM_HEIGHT=68 定值换算对变高条目必然失准；累积估算 O(1) 维护、换算线性扫，精度足够（拖选偏保守只影响效率）。spec 边界「高度换算允许保守估算」落地。
**Alternatives considered**: 按实际布局高度（onAreaChange 逐条目回填）——精确但为辅助交互引入逐条目测量状态，不值。

### D6: 横删挂条目级 ListItem

**Decision**: `swipeAction` 挂条目 ListItem：单条目 → 既有单删确认弹窗（`DIALOG_DELETE_QUEUE_ITEM_*`）；组条目 → 既有整组移除弹窗（`DIALOG_REMOVE_QUEUE_GROUP_MSG`，N=分P 数）。多选态一律不挂（现状保持）。取消/外围点击经 `closeAllSwipeActions` 复位（现状保持）。
**Rationale**: 一个 ListItem 一个 swipeAction，整组一体滑动是条目化的直接结果（bug ③ 消除）；弹窗文案常量全部复用，无新增。

### D7: 计数面统一条目口径

**Decision**: 五处计数统一改为条目数：①标题「播放队列 (N)」= 条目数；②多选徽标 = 选中条目键数；③全选 = 全部条目键；④清空确认「全部 N 首」= 条目数；⑤清除已播确认计数 = `playedRemovableCount()` 改为**条目口径**（bvid 已播完且该条目不含当前播放条目的条目数）。`hasPlayedItems` 同步改判定。入队提示语（「已添加 N 首」）描述存储分P 数，不在计数面清单内，保持不变。
**Rationale**: 「视为一个条目」在计数层的完整落地（bug ②）；⑤中含当前条目的组会被裁剪但不清除，不计入「清除 N 首」避免歧义。
**Alternatives considered**: 仅改徽标——标题 (14) 与徽标 1 并存，口径割裂。

### D8: 随机播放条目级抽取 + 组内连播优先（PlayerController）

**Decision**: PlayerController 新增**条目分组单一来源**方法 `getQueueEntryGroups(): number[][]`（连续扁平下标游程：同 bvid 且页号≥1 的相邻条目游程合并，游程内 ≥2 为组、=1 为单条目；覆盖全部下标、有序连续）。随机抽取改用它：`next()` 随机分支在 forward 重放之后先判**组内连播**——当前条目页号≥1 且下一条目同 bvid 同页号≥1 → `playIndex(currentIndex+1)`；否则在「非当前条目」的条目集合中等概率抽取，抽中条目取其**最小页**条目下标起播；无可抽条目回退重播当前条目起点（与现状单条目行为一致）。`prev()` 随机回溯、shuffle/forward 轨迹键、分P 粒度历史全部不动。
**Rationale**: 分组规则与展示层同源（单一来源避免两处漂移）；组内连播优先保证专辑不拆散（US4 核心语义）；最小页起播与头行两段判定②段对齐；轨迹不动使上一曲回溯天然回到上一实际播放分P。
**Alternatives considered**: 随机仍按分P 抽取——与「条目化」心智矛盾（用户已定案视频级）；随机时重排队列数组——现状随机只影响播放轨迹不重排，引入重排是超范围行为变更。

### D9: 渲染结构（组条目构建方式）

**Decision**: LazyForEach 生成器按条目分发：组条目 → `Column{ 头行(带 Checkbox/按压/手势) + ForEach(分P 窄行) }`，分P 窄行点击 `playIndex(startIndex+偏移)`、当前播放高亮按扁平下标比对 `currentIndex`、已播 ✓ 保持 bvid 级口径；单条目 → 现有整行（`queueFullRow` 语义保留，选择/按压/手势改条目键）。外层 LazyForEach 键 = 条目键；组内 ForEach 键 = `bvid:page`。占位条目（页号<1）不成组、走单条目整行（现状保持）。
**Rationale**: 分P 行渲染逻辑基本平移（扁平下标经 startIndex+偏移恢复）；百级分P 组在条目被 LazyForEach 构建时一次性渲染内部 ForEach，规模上限留真机待验（spec 边界登记）。

### D10: 保持面清单（本轮不动）

**Decision**: 以下全部保持现状：`removeSelectedFromPlaylist`/`clearPlayedItems`/`clearAllWithExitDelay`/`unfavoriteCurrent` 的删除与切播链路及签名；`expandPlaceholderInPlace` 占位展开（展开后分P 相邻自动成组）；`playIndex` 续播决策与 Wi-Fi 拦截；`playDownloadedSong` 插播；BackHandler 对 `AS_PLAYLIST_SELECT_MODE` 的翻转与面板关闭自动退出多选；MediaSession；历史面板（HistorySheet）；MiniPlayer/PlayerOverlay；单P 全链路。
**Rationale**: FR-009/010/011 回归约束——纯展示层与随机抽取粒度两处改造，其余零触碰。

## Data Model

### QueueEntry（新增，`QueueSheet.ets` 文件域，纯展示层）

| 字段 | 类型 | 语义 |
|------|------|------|
| `isGroup` | boolean | true=组条目（多P 相邻 ≥2），false=单条目 |
| `videos` | BiliVideo[] | 组条目：全部分P（列表序）；单条目：恰 1 个 |
| `startIndex` | number | 扁平队列起始下标（条目内连续，组内偏移 i 对应 `startIndex+i`） |
| `key` | string | `g:{bvid}`（组）/ `s:{itemKeyOf(bvid,page)}`（单条目）——选择单位、按压高亮、LazyForEach 键共用 |

派生规则：`PlayerController.getQueueEntryGroups()` 的游程 ↔ 条目一一对应；每次 `playlistVersion` 变更整体重建（不可变使用，无观测装饰器）。估算高度随条目派生（单条目常量、组 = 头行常量 + 分P 数 × 分P 行常量）。

### 选中集（QueueSheet 内部）

`selectedEntryKeys: string[]`——条目键集合；全选 = 全部条目键；收敛 = 保留现存条目键；移除 = 展开为分P 复合键（条目 `videos` 逐个 `BiliVideo.itemKeyOf`）后走既有批量移除。

### 条目游程（PlayerController 内部派生，不落盘）

`number[][]`——扁平播放列表的连续下标游程（同 bvid 且页号≥1 相邻合并）；随机抽取、已播条目计数、QueueSheet 条目构建共用。

## Contracts & Interfaces

### PlayerController（公开面变化）

| 成员 | 变化 | 契约 |
|------|------|------|
| `getQueueEntryGroups(): number[][]` | 新增 | 纯只读派生：覆盖全部下标、游程有序连续、同 bvid 页号≥1 相邻合并；不广播无副作用 |
| `playedRemovableCount(): number` | 语义改 | 返回条目口径计数：bvid 已播完且条目不含当前播放条目的条目数 |
| `hasPlayedItems(): boolean` | 语义随行 | 与 `playedRemovableCount() > 0` 等价（条目口径） |
| `next()` 随机分支 | 语义改 | forward 重放 > 组内连播（下一条目同 bvid 且双方页号≥1）> 条目级随机（抽非当前条目、取最小页下标起播）> 回退重播当前条目起点 |
| `randomIndex()` | 内部重写 | 随机抽取单位 = 条目游程；返回抽中条目最小页下标 |
| `removeSelectedFromPlaylist(keys)` | 不变 | 入参仍为分P 复合键数组 |
| `prev()`/轨迹/`clearPlayedItems`/`clearAllWithExitDelay`/`playIndex`/`playDownloadedSong`/`latestHistoryOf`/`isPlayed` | 不变 | 现状契约 |

### QueueSheet（内部重构，公开面不变）

- `PlaylistDataSource`：数据源从 `BiliVideo[]` 改为 `QueueEntry[]`；`setItems`/`notifyDataDelete`/`notifyDataChange` 契约不变（条目级）
- 删除渲染期派生函数族：`hasGroupHeader`/`isGroupedPart`/`groupStartIndex`/`groupKeys`/`groupPartCount`/`isGroupFullySelected`/`toggleGroupSelect`/`minGroupPage`（由条目模型吸收）
- `syncFrom`：条目重建 + 条目键序列纯删除 diff（增量）+ 回退整表 reload + 选中集条目键收敛
- 弹窗常量复用：`DIALOG_REMOVE_QUEUE_GROUP_MSG`（N=组分P 数）、`DIALOG_DELETE_QUEUE_ITEM_*`、`DIALOG_CLEAR_PLAYED_COUNT_MSG`（N=条目数）
- 局部估算常量：单条目高度（沿用现 68）、组头行/分P 行估算高度（由现有 padding/字号推导，文件头常量）

### 回归不变量（验证锚点）

1. 单P 条目整行形态、左滑单删、点击切播、长按多选与改造前一致
2. 头行两段判定（历史续播/最小页）与第三轮 D13 一致
3. 移除含当前条目的组 → 自动切播（既有 removingCurrent 语义）
4. 旧持久化数据/占位展开/`?p=N` 孤立分P 路径零回归
5. 多选态面板关闭/系统返回自动复位（AS_PLAYLIST_SELECT_MODE 链路）
