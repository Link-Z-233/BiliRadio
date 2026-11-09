# Implementation Plan: v0.7-part4-special-marks（特殊视频标记）

**Input**: Feature specification from `spec/v0.7-part4-special-marks/spec.md`

## Summary

四类特殊视频（充电专属/互动视频/付费内容/大会员）列表级角标 + playurl 门禁码（87007/87008/87005）误分类修复。列表预标记从各数据链现有字段解析（有数据就标、无数据不标），播放门禁码在取流失败分类中新增两档确定性分类直报原因；互动视频在入队/点播入口无条件拦截。

真机反馈修订（spec Overview ①-⑥）：详情链解析修复保入队标志（补 rights.pay/ugc_pay、充电字段位置改顶层）；is_pugv 课程归付费类；源页角标改封面右上角类型色底 pill（符号+文字，大会员大字）；队列/历史标记改标题前缀（大会员「大」单字）与状态标分位；收藏夹批量入队经详情链补全（仅 fav 源、并发上限令牌、失败降级原行）。回写源页、入队跳过 toast 追加、PlayerOverlay 标记均不做（spec Non-goals）。全部改动落在既有文件，零新增文件。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: 零第三方依赖（@kit.* 系）
**State Management**: 既有混合态——BiliVideo 为 `@ObservedV2`+`@Trace`（新字段沿用）；PlayerController 零装饰器广播（字段 + `emitUi`，消费方 `syncFrom`）；页面已迁 V2。本轮不引入新代际、不改观测模式
**Storage**: 既有 AppStore（Preferences + 文件持久化）；BiliVideo 新标志随 `toRecord`/`fromRecord` 序列化
**Testing**: 无测试套件；`devecocli check arkts` + `devecocli build` + 真机日志验证（项目惯例）
**Target Platform**: HarmonyOS NEXT 单模块应用
**Performance Goals**: 刷新源页不因标志解析新增任何逐条网络请求（SC-004）
**Constraints**: Constants.ets 唯一真相源；令牌化（色值 `$r('app.color.*')`、数值 `Constants.TOKEN_*`）；代码零注释（`ponytail:` 除外）；禁 `any`/`as` 断言（既有 `as Record` 模式除外，按周边代码惯例）
**Scale/Scope**: 改动 7 个既有文件（BiliVideo/BiliService/PlayerController/Constants/SourcePage/QueueSheet/HistorySheet）+ color.json 资源登记（pill 底色变体）

## Project Structure

### Documentation (this feature)

```text
spec/v0.7-part4-special-marks/
├── spec.md
└── plan.md              # This file
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/BiliVideo.ets           # 新增 3 个标志字段 + 序列化
├── service/BiliService.ets       # parseVlistRecords/parseArchiveRecords/parseVideoDetail 字段解析；
│                                 #   parseVideoFromViewData 详情链修复（rights.pay/ugc_pay/顶层 is_upower_exclusive/is_stein_gate）；
│                                 #   parseVlistRecords is_pugv 归付费类
├── service/PlayerController.ets  # classifyPlayError 新增两档；loadPlaylistAndPlay 互动拦截
├── service/Constants.ets         # toast 文案常量 + fav 批量详情补全并发上限令牌
├── pages/SourcePage.ets          # 封面右上角 pill 角标（符号+文字，大会员大字）；
│                                 #   enqueueSelected fav 源批量入队详情链补全
└── component/
    ├── QueueSheet.ets            # 标题前缀标记（充电/互动/付费图标、大会员「大」单字）
    └── HistorySheet.ets          # 标题前缀标记（同上）
entry/src/main/resources/base/element/color.json   # pill 类型色低饱和/半透明底色变体登记
```

**Structure Decision**: 沿用既有项目架构（分层：model/service/pages/component），零新增文件——四类标志是既有模型的字段扩展、既有解析函数的字段补齐、既有渲染点的条件分支，无新抽象诉求。

## Complexity Tracking

无宪法违规。全部为既有文件的增量修改。

## Research & Decisions

- **Decision**: 数据源按「APP cursor 主链 + Web vlist 副链 + APP view 详情链 + 合集/系列链」四链各自解析，字段缺失自然跳过
  **Rationale**: 各链字段族不同（BILI_NOTES §3.12 实测）；`parseVlistRecords` 本就是 APP/Web 共用，两族字段在同一函数内各自判在即可；「有数据就标、无数据不标」由字段缺失跳过天然满足
  **Alternatives considered**: 统一先归一化各链为中间格式再解析——多一层无谓抽象，且各链字段互不冲突，弃

- **Decision**: APP cursor 链充电判定用 `badges` 数组文案精确匹配「充电专属」（无充电布尔字段，§3.12 实测）
  **Rationale**: 该链唯一充电信号；精确匹配保证 B 站未来改文案时漏标而非误标
  **Alternatives considered**: 匹配 `bg_color` 色值——色值更易改版且语义间接，弃

- **Decision**: 大会员类来源为 APP cursor 链 `is_pgc`（PGC 引用）与详情链 `rights.pay>0`；课程 `is_pugv` 归付费类（B 站课堂课程是付费购买内容，非大会员权益，真机反馈修订②）
  **Rationale**: §3.12 实测 Web vlist 字段族无会员标志；大会员专享 UGC 的权威信号在详情链 rights.pay（官方 web view 文档）；课程归类修正使角标语义与 B 站商业模式一致
  **Alternatives considered**: 用 attribute 位图猜测会员位——未实证位定义，误标风险，弃；课程留大会员类——付费购买≠会员权益，弃

- **Decision**: 详情链（web view）解析修复是入队标志保真的根因修法——补 `rights.pay`（大会员，与充电互斥防双标）、`rights.ugc_pay`（付费）、充电字段位置由 `rights.is_upower_exclusive` 改为顶层 `is_upower_exclusive`（rights 兜底）、`rights.is_stein_gate`（互动，位置正确沿用）；isVipExclusive 判定加「非充电」互斥条件
  **Rationale**: 入队统一经 `fetchVideoDetail`→`parseVideoFromViewData` 重建条目，该函数不解析 pay/ugc_pay 且充电字段读错位置（官方文档 web view 顶层），致入队后标志丢失；修解析侧一处即覆盖全部入队路径（源页单击/「+」添加/分享导入/fav 批量），修入队处合并源条目标志则需逐入口改且 fav 行本身无标志
  **Alternatives considered**: 入队时合并源列表行标志——fav 行无标志字段、多入口逐改，覆盖不全，弃

- **Decision**: 门禁码在 `classifyPlayError` 新增两档确定性分类：`UPOWER`（87007/87008）与 `PAID`（87005），走既有确定性分支（标异常 + 专属 toast + 跳下一条），与 VIP（-104）同构
  **Rationale**: 现有确定性分支（INVALID/VIP）已实现「标记+跳过+toast」全套行为，新增枚举值复用该分支改动最小；官方码语义由官方客户端逆向确认（`接口调用学习笔记.md` §7.5）
  **Alternatives considered**: 归入 VIP 档共用大会员文案——原因混淆（充电≠大会员），弃

- **Decision**: 未知错误兜底与时长异常判定完全不动——`OTHER` 档通用 toast + 停等人工重试保留；`handleAnomalyOnPrepared`（试听流时长判定）保留并在 plan 中明确双路径共存关系
  **Rationale**: 门禁码直报只覆盖「playurl 返回错误码」形态；「试听流可取」形态仍由时长判定捕获（§3.6），其「不说明充电原因」语义是上轮 spec 定稿；两路径互斥互补，兜底保证未知码行为零变化

- **Decision**: 互动拦截收敛在 `loadPlaylistAndPlay` 单点——`toAdd` 过滤 `isInteractive` 条目；全滤空返回新 `EnqueueResult.INTERACTIVE`（新枚举值 + toast 文案），混合场景过滤后正常入队并在状态消息中提及
  **Rationale**: 该函数是点播/入队/分享导入的唯一汇聚点（SourcePage/HomePage/AddSubscriptionSheet 全走它），单点过滤即全入口拦截；详情链（APP view `interaction` 字段）保证跨源点播也能拦
  **Alternatives considered**: 各调用方各自判断——多入口重复且易漏，弃

- **Decision**: QueueSheet/HistorySheet 图标用 `SymbolGlyph` 系统符号，具体符号名实施时先在 `sysResource.js` 确认存在（候选：充电 `bolt`、付费 `creditcard`、互动岔路类），不虚构符号名；大会员弃符号改「大」单字（`primary_color` #FB7299）
  **Rationale**: paths.md 规则：引用 `sys.symbol.*` 前必须确认存在；会员皇冠类符号语义重、辨识成本高，单字直读（真机反馈修订④）

- **Decision**: 源页角标形态定稿为封面右上角类型色底 pill（充电⚡/互动岔路/付费卡符号 +「充电」「互动」「付费」文字；大会员无符号、加粗大字即标识），pill 底色为类型色低饱和/半透明变体、新登记 color 资源（真机反馈修订③）
  **Rationale**: 行尾角标与时长/NEW 等既有角标争位且易与状态标混淆；封面右上角是官方客户端角标惯例位置；类型色底保证角标在任意封面可读
  **Alternatives considered**: 行尾纯文字角标（原实现）——争位，弃；封面左下——与官方时长角标位置冲突，弃

- **Decision**: 队列/历史标记放标题前缀（充电/互动/付费图标、大会员「大」单字，类型色区分），与行尾 ✓/✗/! 状态标分位（真机反馈修订④）
  **Rationale**: 队列/历史行无封面，封面 pill 方案不可用；行尾已由状态标占用，标题前缀既醒目又不争位
  **Alternatives considered**: 行尾双排——分P 窄行高度受限，弃

- **Decision**: 收藏夹多选批量入队走详情链补全——仅 fav 源（UP 源/合集行自带标志不拉）；选中条目并行拉详情（并发上限走 Constants 令牌，保守初值 3）；单条详情失败降级用原列表行入队（该条无标志、互动不拦）（真机反馈修订⑥）
  **Rationale**: fav 行数据源（新旧 API）无任何标志字段（§3.12 实测），批量直入队列致互动稿漏拦且无标识；fav 批量是罕见入口+低频操作，不为它做队列化基础设施，有界并发即够；降级语义与「有数据就标、无数据不拦」一致
  **Alternatives considered**: 接受 fav 批量盲区——用户实际使用收藏夹含互动稿，漏拦不可接受，弃；顺带回写源页列表——刷新即覆盖、收益一次性，用户决策不做

## Data Model

### BiliVideo 新增字段（`@ObservedV2` 类，`@Trace` 装饰，随 toRecord/fromRecord 序列化）

| 字段 | 类型 | 语义 | 来源字段（按链） |
|------|------|------|----------------|
| `isInteractive` | boolean | 互动视频 | Web vlist：`is_steins_gate`/`attribute` bit29；APP cursor：`is_steins`；合集/系列：`interactive_video`；APP view 详情：`interaction` 存在；web view 详情：`rights.is_stein_gate` |
| `isPaid` | boolean | 付费内容（含课程） | Web vlist：`is_pay`；APP cursor：`ugc_pay`>0、`is_ugcpay` 或 `is_pugv`（课程，归付费类）；合集/系列：`ugc_pay`>0；web view 详情：`rights.ugc_pay`>0 |
| `isVipExclusive` | boolean | 大会员专享 | APP cursor：`is_pgc`；web view 详情：`rights.pay`>0 且非充电（互斥防双标） |
| `isUpowerExclusive` | boolean | 充电专属（已有） | Web vlist：`is_charging_arc`/`elec_arc_type`>0；APP cursor：`badges[*].text` 含「充电专属」；APP view 详情：`charging_pay`/`charging_plus`；web view 详情：顶层 `is_upower_exclusive`（`rights` 同名兜底） |

判定规则统一：**只认明确真值**（布尔为 true / 数值 > 0 / 数组含目标文案 / 对象存在），字段缺失或 null 一律置 false——「有数据就标、无数据不标」。

### PlayErrorKind 枚举扩展（PlayerController）

新增 `UPOWER = 5`、`PAID = 6` 两档；`classifyPlayError` 在既有匹配后、风控判断前新增：

- 消息 `Bili API error 87007` / `Bili API error 87008` → `UPOWER`（确定性）
- 消息 `Bili API error 87005` → `PAID`（确定性）

确定性分支（原 INVALID/VIP 判断）扩为四档：INVALID 标失效、VIP/UPOWER/PAID 标异常，各取专属跳过 toast；`OTHER` 兜底与瞬时路径不变。

### EnqueueResult 枚举扩展（PlayerController）

新增 `INTERACTIVE = 4`：`loadPlaylistAndPlay` 过滤后无可入队条目且存在互动条目时返回；`enqueueToast` 映射新文案「互动视频不支持播放」。

### 双路径共存关系（充电/付费稿失败形态，验收对照表）

分界点 = **playurl 有没有给出可播放的流**：响应 `code≠0` → 异常抛出，流从未存在，走取流失败分类（A）；`code=0` 拿到流（完整或试听）→ prepared 后走时长判定（B）。同一次取流二选一，互斥不重叠；B 站对门禁稿的行为只有「API 拒绝（A 覆盖）」与「给试听流（B 覆盖）」两种。87007 形态下 DASH 与 durl 请求返回同码，不存在「DASH 拒绝但 durl 给试听」的混合形态（门禁在 API 层不在格式层）。两条路径最终收敛到同一 `markAnomaly`（感叹号标记），仅首触发 toast 不同——A 转述官方码直报原因，B 症状推断不说明原因（上轮定稿语义）。

| 形态 | 触发路径 | 标记 | toast |
|------|---------|------|-------|
| playurl 返回 87007/87008（充电）/87005（付费） | 取流失败分类（本轮新增档） | 异常标（感叹号） | 直报「需要充电/需要付费，已跳过」 |
| playurl 返回试听流（code=0，DASH 无数据降级 durl） | 时长判定 `handleAnomalyOnPrepared`（不动） | 异常标（感叹号） | 时长异常文案，不说明原因（上轮语义） |
| 未知错误码 | OTHER 兜底（不动） | 无 | 通用播放失败 toast + 停等人工重试 |

## Contracts & Interfaces

### `PlayerController.loadPlaylistAndPlay(items, startIndex, insertAfterCurrent) → EnqueueResult`

新前置行为：`toAdd` 过滤 `isInteractive === true` 条目（去重循环内一并过滤）；全部条目为互动 → 返回 `INTERACTIVE`，歌单零改动；混合场景过滤后按既有逻辑入队，`statusMsg` 附「已跳过 N 个互动视频」。调用方（SourcePage/HomePage/AddSubscriptionSheet）经 `enqueueToast` 消费新枚举值，无需各自改动判断逻辑。

### `PlayerController.classifyPlayError(message) → PlayErrorInfo`

新增两条精确匹配（87007/87008 → UPOWER、87005 → PAID），匹配顺序置于既有 -404/-104 匹配之后、风控判断之前；其余分支与返回契约不变。

### 解析函数（BiliService）

- `parseVlistRecords`：恢复既有注释的充电解析（is_charging_arc/elec_arc_type/ugc_pay/is_ugcpay 族）并新增 badges 文案匹配与 is_steins/is_steins_gate/is_pay/is_pugv/is_pgc/attribute bit29 解析，全部按上表判定规则；`is_pugv` 归入 `isPaid`（课程归付费，真机反馈修订②）
- `parseArchiveRecords`：新增 `interactive_video`/`ugc_pay` 解析
- `parseVideoDetail`（APP view 详情链）：新增 `charging_pay`/`charging_plus`（充电）、`interaction`（互动）解析——详情链是互动拦截跨源兜底的数据来源
- `parseVideoFromViewData`（web view 详情链，真机反馈修订①）：补 `rights.pay`（isVipExclusive，判定加非充电互斥防双标）、`rights.ugc_pay`（isPaid）、`rights.is_stein_gate`（isInteractive）；充电字段位置修正——顶层 `is_upower_exclusive` 为准（官方文档），`rights` 同名兜底；解析命中日志按四类标志分类输出（bvid + 命中标志 + 链名）

### `SourcePage.enqueueSelected`（fav 源批量入队详情补全，真机反馈修订⑥）

仅收藏夹源且多选确认入队时：选中条目并行调 `fetchVideoDetail`（并发上限 `Constants` 令牌，保守初值 3），详情成功则 parts 展开后按详情条目入队（标志/互动拦截/多P 语义与单击一致）；单条失败降级用原列表行入队（无标志、互动不拦）。UP 源/合集批量与现状一致（行自带标志，不拉详情）。`loadPlaylistAndPlay` 的互动过滤与 `INTERACTIVE` 返回契约不变，作为详情条目的兜底过滤层。

### Constants 新增

门禁与拦截 toast 文案常量（充电跳过/付费跳过/互动拦截），命名与既有 `TOAST_*` 系列对齐；fav 批量详情补全并发上限令牌（数值型 `TOKEN_*` 系列，保守初值 3）；具体文案实施时定稿，语义以 spec FR-001/US3 验收场景为准。

### 渲染层

- `SourcePage`：封面右上角类型色底 pill 角标——充电⚡/互动岔路/付费卡符号+文字、大会员加粗大字（无符号），pill 底色为类型色低饱和/半透明变体（新登记 color 资源：充电金/互动紫/付费橙/大会员粉系），多标志并排，无标志不显示；多选模式下与其他标记一致隐藏
- `QueueSheet`/`HistorySheet`：标题前缀标记——充电/互动/付费 `SymbolGlyph` 图标、大会员「大」单字（`primary_color`），类型色区分；与行尾 ✓/✗/! 状态标分位；选中模式下隐藏（对齐既有标记行为）

### 自检与验证口径

- 标志解析为新的非平凡分支逻辑：解析命中时打 debug 日志（链名 + bvid + 命中标志），真机日志即自检面（对齐项目「日志页验证」惯例）
- 刷新请求数与上轮持平（SC-004）：解析纯读响应字段，零新增请求，构建后真机刷新观察日志请求条数
- 互动拦截/门禁分类的逻辑正确性以真机样本验证（充电稿 BV12RYx6TE9r 等，§3.12 样本清单），纳入 Verification 阶段真机自查事项
