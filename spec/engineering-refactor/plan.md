# Implementation Plan: 工程重构总规划（Engineering Refactor）

**Input**: Feature specification from `spec/engineering-refactor/spec.md`

## Summary

BiliRadio 工程重构总规划（规划轮，不实施代码）。以 **API 26 为全局既定前提**（`compatibleSdkVersion` 升 26.0.0、移除唯一 `[API24-COMPAT]` 守卫、版本 0.3.0/3000、活跃文档同步——前置落地项，FR-A）。规划四个实施阶段：

- **Phase B · KI-9 页界统一**（US1/P1）：修复 UP 投稿翻页双链页界不对齐漏条。
- **Phase C · 界面风格统一**（US2/P1）：数字令牌 + 色彩补漏 + 组件规范。
- **Phase D · 架构边界重构**（US3/P2）：等级 1 边界契约，零行为变化。
- **Phase E · V2 渐进迁移路线图**（US4/P3）：分块迁移规划，本期不实施。

## Technical Context

**Language/Version**: ArkTS / ArkUI（HarmonyOS NEXT，API 26 既定基线）
**Primary Dependencies**: 无新增依赖；`@kit.ArkUI`、`@kit.BasicServicesKit` 等既有 Kit
**State Management**: 既有 V1（`@Component`/`@State`/`@StorageLink`/`@Watch`）——Phase D 保持 V1；Phase E 仅规划 V2 迁移路线图（本期不实施）
**Storage**: Preferences（`biliradio_store`）+ 文件（`play_history.json`、`biliradio_log.txt`）+ SecureStore
**Testing**: 无测试套件；构建验证 `devecocli build` + 真机/模拟器 UI 走查（`spec/ui-testing-playbook.md`）
**Target Platform**: HarmonyOS NEXT 手机/平板（phone/tablet），API 26+
**Project Type**: 既有移动应用（单 entry 模块）——重构规划轮
**Performance Goals**: 不涉及新增性能目标；翻页请求数不因 KI-9 修复显著增加
**Constraints**: 只规划不实施；API<26 不兼容；历史 spec 文档不动；`Constants` 唯一真相源；零行为变化（Phase D）；代码零注释原则（实施轮）
**Scale/Scope**: 7 页面 / 7 组件 / 21 服务 / 6 模型；规划覆盖全工程

## Project Structure

### Documentation (this feature)

```text
spec/engineering-refactor/
├── spec.md              # 需求规格（Phase 1 产物）
├── plan.md              # 本文件（Phase 2 产物）
└── tasks.md             # 任务拆解（Phase 3 产物）
```

### Source Code (repository root)

本规划遵循既有工程架构，**不引入 MVVM 迁移、不新增目录层级**。既有结构（实施轮改动点以 `→` 标注）：

```text
entry/src/main/ets/
|-- entryability/EntryAbility.ets
|-- pages/               # Index(壳)/HomePage/PlayerOverlay/SourcePage/SettingsPage/AddSubscriptionSheet/LogPage
|   |-- SourcePage.ets   # Phase B：翻页记账调整
|   |-- SettingsPage.ets # Phase C：令牌替换（体量最大）
|   `-- ...              # Phase C：全部页面令牌替换
|-- component/           # MiniPlayer/QueueDrawer/QueueSheet/CoverThumb/SettingsRow/SettingsGroup/EdgeHint
|   `-- ...              # Phase C：组件规范归一
|-- model/               # BiliVideo/AudioQuality/PlayHistoryItem/Subscription/Season/FavFolder
|-- service/
|   |-- BiliService.ets  # Phase B：Web 链 ps 对齐
|   |-- Constants.ets    # Phase B/C：页大小常量、令牌常量（唯一真相源）
|   |-- MediaSession.ets # Phase A：守卫移除（删标记保留 try/catch）
|   `-- ...
|-- resources/           # 资源归属 resources/ 下，不落入 ets/
|   |-- base/element/color.json   # 色彩令牌（既有，Phase C 补漏）
|   |-- dark/element/color.json   # 深色色彩令牌（既有）
|   `-- base/element/float.json   # Phase C：可选字号令牌（见 Research）
```

**Structure Decision**: 本规划**遵循既有工程架构**，不选择新层级、不引入 MVVM——理由：① 既有 `pages/service/model/component + Constants` 边界清晰且运行稳定；② 用户未要求 MVVM 迁移，Phase D 为等级 1 边界重构（契约化而非目录重组）；③ 规划轮不产生任何代码。Phase C 的令牌与组件规范在既有目录内落地（常量进 `Constants`、规范抽 `component/` 或 `@Builder`），Phase E 迁移不改变目录结构。

## Complexity Tracking

> 无宪法违规项。Phase E 迁移单元数量（约 15+）属路线图规划而非本轮实施文件，不构成复杂度违规。

## Research & Decisions

### R1 · KI-9 实施方案（Phase B）

- **Decision**: **双管齐下（推荐）**——① Web 链页大小 `ps` 由 30 降为 20，与 APP 签名链服务端钳制（20 条/页）对齐；② 保留并强化翻页记账：`upWebLastPage`（Web 链最大已翻页号）+ bvid 去重兜底，降级衔接的 Web 起始页推算基准统一改为页大小 20。页大小常量收进 `Constants`（`UP_PAGE_SIZE`），`SourcePage.olderPageSize()` 不再硬编码 30。
- **Rationale**: 根因是两条链路页大小不一致（20 vs 30）叠加排序/内容漂移，`floor(len/30)+1` 推算 Web 起始页在 APP 链稀疏（每页不足 20）时发生区间错位。页大小对齐使推算基准唯一；记账 + 去重吸收残余漂移。改动集中（`BiliService.ets` 约 2 处、`SourcePage.ets` 1 处、`Constants.ets` 1 处），风险低，不动翻页端点语义。
- **Alternatives considered**:
  - 翻页记账按链路分别校准（PROJECT_NOTES 候选 B）：维护 per-link 游标/页号双轨并跨链衔接，改动大、涉及状态机，超出等级 1 风险偏好。
  - 仅依赖既有 bvid 去重：不能修复「两条链路数据差异导致区间错位」的漏条，去重只防重复不防漏。

### R2 · 令牌形式（Phase C）

- **Decision**: **双轨**——色彩沿用既有资源 `$r('app.color.*')`（base/dark 自动匹配，已覆盖 40+ 语义色）；**字号/圆角/间距用 `Constants` 数字常量**（vp 数值），新增命名分组（`TOKEN_RADIUS_*`/`TOKEN_FONT_*`/`TOKEN_SPACE_*`）。`float.json` 仅保留既有 `page_text_font_size`，不扩展。
- **Rationale**: 圆角/间距/字号是纯数值且不随深浅色变化，放 `Constants` 符合「唯一真相源」原则、类型安全（number 直接用于 `fontSize`/`borderRadius`/`margin`）、零 Resource↔number 转换成本；色彩必须随外观切换，资源方式是既有正确选择。字号暂不引入 fp 缩放语义（现状即固定 vp，保持行为不变，FR-C-003）。
- **Alternatives considered**:
  - 字号/圆角/间距全部入 `float.json`（`$r('app.float.*')`）：统一资源入口，但 Resource 类型在需要 number 的场合（计算/约束尺寸）需 `getFloatSync` 转换，且与「Constants 唯一真相源」冲突，弃。
  - 引入独立 `DesignTokens.ets`：新增文件与既有原则不符，令牌归 `Constants`。

### R3 · 组件规范范围（Phase C 第二层）

- **Decision**: 四类部件归一：**列表行**（高度/内边距/封面尺寸/两行文本字号与色阶）、**卡片**（`card_background` + `TOKEN_RADIUS_M`/`L` + 间距）、**弹窗/面板**（背景/圆角/内边距/遮罩）、**空态**（占位图/文案/间距）。以既有页面实现为基准抽 `@Builder` 或公共组件，**数值不变只统一来源**。
- **Rationale**: 四类部件是跨页面出现频率最高的重复样式，归一后观感一致且为 Phase E 组件化铺路；以现状为基准避免观感突变（FR-C-003/005）。
- **Alternatives considered**: 覆盖全部组件类型（含按钮/输入框）——超出本轮范围，按钮/输入框已有统一形态，列远期。

### R4 · V2 迁移边界规则（Phase E 路线图）

- **Decision**: 迁移顺序「模型层 → 独立组件 → 页面 → 全局状态」；页面按依赖度升序（LogPage → AddSubscriptionSheet → SettingsPage → SourcePage → HomePage → PlayerOverlay → Index 壳）；全局状态（AppStorage→AppStorageV2/PersistenceV2）与播放器核心（PlayerController）置于最后。每个迁移单元独立提交、独立回归。
- **Rationale**: V1/V2 可在同一应用共存（每 struct 独立选择范式），模型层无 UI 依赖风险最低；全局状态切换须等依赖页面全部迁完，否则观察断裂（V1 `AppStorage` 不观察 V2 对象）。
- **Alternatives considered**: 一次性全量迁移——大爆炸风险，违背渐进原则，弃。

### R5 · 架构边界裁剪（Phase D）

- **Decision**: 产出**模块边界契约文档**（每模块职责/允许依赖/禁止依赖）+ 低风险职责归位。已知职责混杂点：`PlayerController`（播控+队列+订阅+收藏，上帝对象候选）、`BiliService`（1783 行，全部 B 站 API）、`SettingsPage`（1400+ 行）。**本轮（规划）只登记不拆分**；拆分方案列远期，避免零行为变化约束下的高风险动作。
- **Rationale**: 等级 1 以「理清并契约化」为主，文件拆分在无测试覆盖（无测试套件）下风险高；边界契约 + 依赖方向审计（单向：service→model、pages→service/model、component 独立）即达成 FR-D-002。
- **Alternatives considered**: 立即拆分 PlayerController/BiliService——行为变化风险高，无测试兜底，弃（登记为远期）。

## Data Model

### 设计令牌表（Phase C，落 `Constants`）

| 分组 | 令牌名 | 档位（vp） | 说明 |
|---|---|---|---|
| 圆角 | `TOKEN_RADIUS_S/M/L/XL` | 8 / 12 / 16 / 20 | 收敛现状 7 种值（4/10/12/14/16/18/20） |
| 字号 | `TOKEN_FONT_CAPTION/AUX/BODY/BODY_M/TITLE/TITLE_L` | 10 / 11 / 13 / 14 / 16 / 22 | 收敛现状 11 种值（10-42） |
| 间距 | `TOKEN_SPACE_XS/S/M/L/XL` | 4 / 8 / 12 / 16 / 24 | 页面内边距/部件间距 |

> 收敛策略：替换时**数值不变**（如 14 归 `TOKEN_FONT_BODY_M`、18 归 `TOKEN_RADIUS_XL`），档位表仅作统一来源；观感收敛（14/15/16 合并）列远期可选，需用户确认后另行执行。

> **档位外实值处理**（实施轮 T014/T024）：实测存在的档位外值（如圆角 24、字号 17/18/20/24、间距 2 等）在「数值不变」原则下**扩展档位表**（新增 `TOKEN_RADIUS_XXL=24` 等）或登记豁免，由 T014 定档、T024 复查；档位表为基线而非硬上限，禁止观感突变。

### 色彩补漏清单（Phase C）

- 现状：base/dark `color.json` 已覆盖 40+ 语义色；页面硬编码残余主要为 `Color.White`/`Color.Transparent` 及个别场景字面量。
- 处理：可语义化的残余（如 `Color.White` → `fg_on_dark` 语境）归入 `color.json`；必须字面量的场景（Canvas/窗口层受限色，已在 `Constants`）登记豁免。

### 模块边界契约（Phase D）

| 模块 | 职责 | 允许依赖 | 禁止依赖 |
|---|---|---|---|
| model/ | 纯数据类 | 无（内建类型） | service/pages/component |
| service/ | 业务逻辑/API/存储/播控 | model/、`Constants` | pages/（反向） |
| pages/ | 页面组装与交互 | service/、model/、component/ | — |
| component/ | 可复用 UI | model/、`Constants` | pages/ |
| `Constants` | 唯一常量源 | 内建类型 | 任何业务模块（防循环） |

### V2 迁移单元映射（Phase E 路线图，本期不实施）

| 批次 | 迁移单元 | 目标范式 | 验收 |
|---|---|---|---|
| 1 模型层 | 6 个 model 类 | `@ObservedV2`+`@Trace` | 编译通过、UI 行为不变 |
| 2 组件 | MiniPlayer/QueueSheet/QueueDrawer 迁移；CoverThumb/SettingsGroup/EdgeHint 为 @Prop-only/无状态免迁；SettingsRow 含 `@StorageProp`（真 V1 存储观测）并入批次 3 SettingsPage 迁移 | `@ComponentV2` | 各组件功能回归 |
| 3 页面 | LogPage → AddSubscriptionSheet → SettingsPage → SourcePage → HomePage → PlayerOverlay → Index | `@ComponentV2` | 每页功能回归 |
| 4 全局状态 | AppStorage（AS_*/KEY_*）→ AppStorageV2/PersistenceV2；PlayerController 最后 | V2 存储 | 全功能回归 |

### 页大小常量（Phase B，落 `Constants`）

| 常量 | 值 | 说明 |
|---|---|---|
| `UP_PAGE_SIZE` | 20 | UP 投稿双链统一页大小（Web ps 对齐 APP 钳制值） |
| `SEASON_PAGE_SIZE` | 20 | 合集/系列页大小（现状不变） |
| `FAV_PAGE_SIZE` | 20 | 收藏夹页大小（现状不变） |

## Contracts & Interfaces

### BiliService 翻页接口（Phase B 改动约束）

- `fetchUpVideosViaWeb(mid: number, pn: number): Promise<BiliVideo[]>`：`ps` 参数 30 → `UP_PAGE_SIZE`(20)。**公开签名不变**，仅请求参数与返回条数上限变化（每页至多 20）。
- `fetchUpVideosOlder(mid, lastAid)` / `fetchUpVideosByPage(mid, pn)`：签名不变，行为不变（APP cursor 链与 Web pn 链语义保持）。
- `SourcePage.olderPageSize()`：UP 分支返回值 30 → `UP_PAGE_SIZE`(20)；`fetchUpWebOlder` 的 `pn` 推算基准随之统一（`floor(len/20)+1`，`upWebLastPage` 兜底保留）。

### 令牌引用约定（Phase C）

- 色彩：一律 `$r('app.color.<name>')`，禁止页面级色值字面量（豁免：窗口层/Canvas 受限色，仅 `Constants`）。
- 圆角/字号/间距：一律 `Constants.TOKEN_*` 常量，禁止裸数字（豁免：尺寸派生计算如 `PLAY_BTN_DIAMETER` 相关，登记于实施轮）。

### V2 迁移边界规则（Phase E 实施轮约束）

1. 单个 struct 内 V1/V2 装饰器不可混用。
2. V1 状态（`@State`/`@StorageLink`）不得持有 `@ObservedV2` 实例；V2 `@Local` 不得被父组件直接初始化（用 `@Param`）。
3. `AppStorage`（V1）与 `AppStorageV2` 不互通——全局存储切换必须在相关页面全部迁移后进行（批次 4）。
4. 每批迁移独立提交、构建通过、功能回归通过后方可进入下一批。
