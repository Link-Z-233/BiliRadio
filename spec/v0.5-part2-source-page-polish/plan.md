# Implementation Plan: 订阅详情页布局调整轮（7 项 + 追加剧集行等高）+ biliAPI 探索文档

**Input**: Feature specification from `spec/v0.5-part2-source-page-polish/spec.md`

## Summary

两部分：**A. `SourcePage` 布局调整 7 项**——顶栏收纳（系统标题栏 `.menus(CustomBuilder)` 承载 ··· 下拉菜单，刷新/退订迁入）、页头迁入列表滚动区（首个 ListItem）、页头内嵌多选入口（行内勾选框+底部操作条，批量入队复用 `loadPlaylistAndPlay`）、页头等高与留白收窄（既有令牌降档+新等高令牌）、充电专属标记（`BiliVideo` 增字段，实施时实测四类接口定夺）、去除播放全部。**B. 新建根目录 `BILI_API.md`**——三段式（本项目探索汇总/biliRelay API 探索迁移/本轮充电实测结论），作为 B 站 API 探索唯一沉淀点。另含目录改名后的源码注释旧名同步（3 处）。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0）
**Primary Dependencies**: ArkUI（NavDestination/Menu/List）、`@ohos.net.http`
**State Management**: 既有 V2 代际不变——`SourcePage` 为 `@ComponentV2`（`@Local`）；`BiliVideo` 为 `@ObservedV2`+`@Trace`；`PlayerController` 零装饰器广播模式不动
**Storage**: `SubscriptionStore`（订阅剧集缓存文件）走 `BiliVideo.toRecord/fromRecord` 持久化——新字段须同步进 record
**Testing**: 无测试套件；验证=构建验证 + 真机自查（默认 build-only）
**Target Platform**: HarmonyOS NEXT 平板/手机
**Project Type**: 单模块 ArkTS 应用（BiliRadio）
**Performance Goals**: 长列表滚动流畅不变差（100+ 集）
**Constraints**: 令牌规范（数值/色彩一律 Constants）、代码零注释（机制注释除外）、禁 `any`/`unknown`/`as` 断言、文档内路径一律相对
**Scale/Scope**: 单页面改动为主 + 一份根级文档，波及 5 个源文件 + 1 个新文档

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part2-source-page-polish/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
BILI_API.md                      # 新建：B 站 API 探索唯一沉淀点（三段式）
entry/src/main/ets/
├── pages/SourcePage.ets        # 主改动：顶栏菜单/页头入列/多选/等高/留白/角标渲染/删播放全部
├── model/BiliVideo.ets         # +isUpowerExclusive 字段（@Trace + record 序列化）
├── service/BiliService.ets     # 三个列表解析点探测充电标记字段
├── service/Constants.ets       # +SOURCE_HEADER_H 令牌；注释旧目录名同步
├── component/CoverThumb.ets    # 注释旧目录名同步
└── pages/SettingsPage.ets      # 注释旧目录名同步
```

**Structure Decision**: 沿用现有项目架构与目录约定（pages/service/model/component 边界契约不变），零新代码文件、零新目录——代码改动落在既有 5 文件内；新增交付物仅根级文档 `BILI_API.md`（与其他根级文档并列，不建 docs/ 目录）。不引入 MVVM 迁移（依赖方向满足 `spec/v0.3-engineering-refactor/architecture-boundary.md`）。

## Complexity Tracking

（无宪法违例——不新增项目/目录/抽象层。）

## Research & Decisions

**D1 顶栏菜单载体**
- **Decision**: 保留 `NavDestination` 系统标题栏（`.title()` 字符串形式，自带返回+标题），右侧操作经 `.menus(CustomBuilder)` 挂载：CustomBuilder 内渲染 `SymbolGlyph(sys.symbol.ellipsis)`，用 `bindMenu` 绑定系统下拉菜单（「刷新」「取消订阅」两项）；`refreshing` 为真时 CustomBuilder 内改渲染 `LoadingProgress`（转圈替代 ···，菜单不可再点，天然防重复触发）。
- **Rationale**: 系统标题栏自带返回与标题截断，零自绘成本；CustomBuilder 形态（相对 `NavigationMenuItem` 数组）是嵌入 loading 动画与 `bindMenu` 的唯一途径。
- **Alternatives considered**: 自绘顶栏 Row（放弃——需自管返回/安全区/标题滚动行为）；`NavigationMenuItem` 数组（放弃——无法嵌入动画与下拉菜单）。

**D2 页头入滚动区**
- **Decision**: 页头（封面+订阅信息+多选按钮）改为 `List` 的首个 `ListItem`（唯一 header 项），随列表滚动离屏、回顶再现；不使用 sticky/吸顶。
- **Rationale**: 标准 List 滚动语义即「下拉收起、拉到顶展现」，零新机制；`scroller.scrollToIndex(0)` 刷新回顶语义不变（0=页头）。
- **Alternatives considered**: Scroll 折叠吸顶（放弃，过度工程）；`Refresh` 组件包 header（放弃——项目下拉刷新已全局禁用，DIS-1 同因）。

**D3 多选状态与更新范式**
- **Decision**: `SourcePage` 内 `@Local selectMode: boolean` + `@Local selectedKeys: Set<string>`；一切集合变更整体重新赋值新 `Set`（不可变更新，触发 V2 赋值观测）。行点击分派：`selectMode` 为真切换选中、为假走原 `playEpisode`。多选会话仅存页面生命周期，不持久化。
- **Rationale**: V2 `@Local` 观测赋值不观测 Set 内部变更，整体换引用是最简可靠范式。
- **Alternatives considered**: `@ObservedV2` 包装选择类（放弃——页面瞬态不值得建类）。

**D4 批量入队链路**
- **Decision**: 「加入队列」按列表序取选中剧集，整体调 `PlayerController.loadPlaylistAndPlay(items, 0)`——既有语义完备：空队列起播、非空追加不打断、按复合键去重、`EnqueueResult` 分型 toast。零服务层改动。
- **Rationale**: 唯一满足 FR-005 的既有接口，无新抽象。
- **Alternatives considered**: 新增专用 appendOnly API（放弃——语义已覆盖）。

**D5 全选与退出**
- **Decision**: 底部操作条三项：「全选/取消全选」（全选=当前 `episodes` 全部 bvid 入集合，文案随 `selectedKeys.size === episodes.length` 切换）、「加入队列 (N)」（N=选中数，N=0 禁用）、「取消」（退出多选清空集合）。系统返回经 `onBackPressed` 先查 `selectMode`：为真则退出多选并拦截返回，为假走既有 `dismissOverlaysForBack`。
- **Rationale**: FR-004/005/006 直接落地；返回优先级与既有浮层返回链一致。
- **Alternatives considered**: 页头内放退出按钮（放弃——页头会滚出视口，退出入口不可达）。

**D6 充电专属标记（实测定夺，含 biliRelay 前证）**
- **Decision**: `BiliVideo` 新增 `isUpowerExclusive: boolean`（`@Trace`，默认 false），`toRecord/fromRecord` 同步增字段。三个列表解析点（`parseArchiveRecords`/`parseVlistRecords`/`parseFolderMedias`）各自探测原始条目充电标记字段。**实施第一步先实测**：用真实订阅数据打本项目四类链路接口（含 APP 签名链——与 biliRelay 匿名 Web 链端点不同），确认返回是否携带标记字段；携带的链解析生效、列表行显示「充电」角标（样式与 NEW 徽标同档）；不携带的链不标不补偿；全部不携带则移除解析代码与字段，该需求降级为「接口不支持，不实施」。实测结论（各链带/不带+字段名）写入 `BILI_API.md`（D11）。
- **既有前证**（biliRelay `docs/B站API试错记录.md` 实验 21，迁移后入 `BILI_API.md`）：UP 投稿列表 `is_charging_arc`/`elec_arc_type`/`elec_arc_badge`/`is_pay` 实测 150 条全 False 且充电专属视频可能不公开出现在投稿列表；fav 列表无 rights 判不出；season/series 有 `ugc_pay`/`state`；详情接口 `is_upower_exclusive` 可靠——前证降低「列表可标」的预期，但本项目 APP 签名链端点未实测过，仍须独立验证。
- **Rationale**: 官方客户端列表带充电角标 vs biliRelay 实测列表字段全 False 存在矛盾，唯一裁断方式=对本项目实际链路实测（SC-004）。
- **Alternatives considered**: 直接按 biliRelay 前证判定不做（放弃——端点链路不同，未实测不算数）；批量拉详情补偿（用户已否决）。

**D7 留白收窄档位**
- **Decision**: 页头与剧集列表外边距统一收窄为 `TOKEN_SPACE_S`（8vp）：List 左右 padding `TOKEN_SPACE_M`→`TOKEN_SPACE_S`，页头容器左右 `TOKEN_SPACE_L`→`TOKEN_SPACE_S`；行内 padding 不动（卡片内文字边距维持，仅卡片整体变宽）。
- **Rationale**: 「少一点」= 一档语义（12/16→8），全用既有令牌，零新令牌零裸数字。
- **Alternatives considered**: 收到 `TOKEN_SPACE_XS`（4vp，放弃——卡片几乎贴边）。

**D8 页头等高**
- **Decision**: `Constants` 新增 `SOURCE_HEADER_H = 56` 令牌，页头封面与右侧文字列统一 `.height(SOURCE_HEADER_H)`（文字列内容两行内垂直居中分布，超长省略号截断）。顺带收敛现页头 `thumbSize: 56` 裸数字为该令牌。
- **Rationale**: 等高=两侧显式同高令牌；56 现为裸数字违令牌规范，一并收敛。
- **Alternatives considered**: `constraintSize` 最小高度（放弃——非严格等高）。

**D9 底部操作条挂载**
- **Decision**: `Stack` 包裹 `List`，`selectMode` 为真时在 Stack 底部对齐渲染操作条（卡片底色 `Row`，`alignContent(Alignment.Bottom)`）；操作条 bottom 避让沿用列表既有 `MINI_PLAYER_CLEARANCE + navBarHeight` 语义。
- **Rationale**: 复用「列表+底部浮层」Stack 模式，无新容器机制。
- **Alternatives considered**: 系统底栏 `bindSheet`（放弃，KI-5 浮层管线风险；且需常驻非模态）。

**D10 刷新中状态位**
- **Decision**: 刷新转圈在顶栏 `menus` CustomBuilder 内呈现（D1）；刷新完成后列表回 `scrollToIndex(0)`，页头随回顶完整展现（US3 验收 4 机制来源）。
- **Rationale**: 刷新入口从页头迁走后，刷新态就近展示在触发点。
- **Alternatives considered**: 页头内保留转圈（放弃——页头可滚出视口，状态不可见）。

**D11 BILI_API.md 文档设计**
- **Decision**: 新建根目录 `BILI_API.md`，三段式结构：**§1 本项目（BiliRadio）API 探索汇总**——在用端点清单（视频详情/UP 列表 APP+Web 双链/收藏夹/合集/系列/播放取流/登录二维码，含各自鉴权与签名要求：APP 端点 BiliDroid UA、Web 端点 WBI 签名、短链 rcp 解析）+ 已知坑与对策（风控冷却、`maxRedirects: 0` 语义、UA 分端点要求等，素材取自 AGENTS.md「B 站 API 坑」、`Constants.ets` 机制注释、既有 spec 探索结论）；**§2 biliRelay API 探索迁移**——`../bili/biliRelay/docs/B站API试错记录.md` 中 API 相关内容（实验 1-14、16-21、状态码速查、排查手册）按原文迁移不做面向本项目的改写（Python/服务端语境保留，标注来源与迁移说明），剔除非 API 内容（实验 15 Docker 部署）；**§3 本轮及后续新增实测**——本轮充电标记四类链路实测结论（D6 产出）起头，作为后续 API 实测的唯一追加点。文档内路径引用一律相对（仓库内相对仓库根、仓库外相对仓库根上级）；AGENTS.md 既有摘要保留不动。
- **Rationale**: 三段式让「本项目在用知识」与「外部前证」与「新增实测」边界清晰；biliRelay 原文按原样迁移保语义不失真（其结论的推理过程是价值所在）；根目录与其他根级文档并列符合仓库惯例。
- **Alternatives considered**: docs/ 目录（放弃——单文件不建目录）；迁移时改写为本项目视角（放弃——有语义失真风险，且 biliRelay 语境的排查手册对全局仍有效）。

**D12 剧集行 68 等高（追加）**
- **Decision**: 剧集行封面 `EPISODE_THUMB_W/H` 由 140×79 收为 121×68（≈16:9）；文字列 `.height(EPISODE_THUMB_H)` + `justifyContent(FlexAlign.SpaceBetween)`——标题贴顶、日期/NEW/已播行贴底（删附属行 `margin-top`）；单行标题行中间留白为预期形态。缩略请求档 `EPISODE_THUMB_REQ_*`（480×270）不变。
- **Rationale**: 封面固定高 vs 文字自适应高先天不等（79 > ≤63），垂直居中无法弥补——等高必须两侧显式同高。形态对齐 B 站/PiliPlus 横版卡（`video_card_h.dart`：标题 Expanded 贴顶、统计贴底、文字列撑满行高）；尺寸取用户决策「68 等高」（封面小一号、行更紧凑）。
- **Alternatives considered**: 封面缩至 112×63 匹配文字自适应高度（放弃——单行标题行仍 63>42 不对齐，治标不治本）；`constraintSize` 最小高度（放弃——非严格等高）。

## Data Model

**BiliVideo（既有 @ObservedV2 类，增量）**
- `isUpowerExclusive: boolean = false`（`@Trace`）：充电专属标记；来源=列表接口解析（D6 实测定夺），持久化进订阅剧集缓存（`toRecord`/`fromRecord` 增 `'isUpowerExclusive'` 键，`fromRecord` 缺省 false 兼容旧缓存）

**多选会话（SourcePage 页面瞬态，不建模文件）**
- `selectMode: boolean`（`@Local`）：多选模式开关
- `selectedKeys: Set<string>`（`@Local`）：已选 bvid 集合，不可变整体换引用更新（D3）
- 派生态：选中数 N=`selectedKeys.size`、全选态=`N === episodes.length && N > 0`

**BILI_API.md（文档实体，D11）**
- §1 本项目探索汇总（端点清单+坑）/ §2 biliRelay 迁移（API 实验原文）/ §3 新增实测（充电实测起头）

## Contracts & Interfaces

**对外接口（零改动复用）**
- `PlayerController.loadPlaylistAndPlay(items: BiliVideo[], startIndex: number): Promise<EnqueueResult>`——批量入队唯一入口（D4）
- `SubscriptionStore.refreshSubscription/persistRefreshedSub/loadEpisodes`——刷新与缓存链不变
- `dismissOverlaysForBack(): boolean`——系统返回链不变，多选拦截叠加在其前

**UI 契约（SourcePage 内）**
- 顶栏：`.title(navTitle)` + `.menus(更多Builder)`；菜单项=「刷新」（refreshing 时锚点转圈）、「取消订阅」（AlertDialog 二次确认，文案与流程沿用现状）
- 页头 ListItem：封面（`SOURCE_HEADER_H` 方形圆角）+ 右侧文字列（副标题/集数，`.height(SOURCE_HEADER_H)`）+ 多选按钮；外边距 `TOKEN_SPACE_S`
- 剧集行（追加，D12）：封面 121×68（`EPISODE_THUMB_W/H`），文字列固定 68、标题贴顶/日期/NEW/已播行贴底（SpaceBetween）
- 剧集行：多选模式行首渲染勾选框（`checkmark_circle`/空心圈），点击行切换选中；常规态行为与现状逐项一致
- 底部操作条（`selectMode` 时）：全选/取消全选、加入队列 (N)（N=0 禁用）、取消

**Constants 增量**
- `SOURCE_HEADER_H = 56`（页头等高令牌，D8）
- `EPISODE_THUMB_W/H` 调整为 121/68（剧集行等高，D12；原 140/79）

**文档契约（BILI_API.md）**
- 位置：仓库根 `BILI_API.md`；三段式结构见 D11；路径引用相对化；充电实测结论为 §3 首条

**注释旧名同步（目录改名善后）**
- `Constants.ets`/`CoverThumb.ets`：`v0.5-source-page-redesign` → `v0.5-part1-source-page-redesign`
- `SettingsPage.ets`：`v0.5-play-history-sync` → `v0.5-part1-play-history-sync`
