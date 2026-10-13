# Implementation Plan: 浮层视觉重设计（播放队列 + 播放历史）

**Input**: Feature specification from `spec/v0.4-Part1-sheet-visual-redesign/spec.md`  
**Baseline**: `69d8c7f`（实施前基线提交，`git diff 69d8c7f` 对照全部改动）

## Summary

将 QueueDrawer 泛化为通用玻璃浮层容器 GlassSheet（遮罩 + 面板 + 动画 + 圆角/模糊/分隔线/投影/底部渐隐全部内聚），队列浮层与播放历史面板共用；历史面板从系统 bindSheet 迁移到该容器（FR-008 复用硬性要求）；全局文字色令牌对齐设计稿色阶；动画升级为 300ms 滑入+渐显；版本号升至 0.4.0/4000。纯视觉/容器重构，业务逻辑（列表数据源、删除/多选/回放/清空链路）零改动。

## Technical Context

**Language/Version**: ArkTS（API 26 基线，compatibleSdkVersion = 26.0.0）  
**Primary Dependencies**: ArkUI（@ComponentV2 状态管理、AppStorageV2 经 V2State 包装类）  
**State Management**: 增量改动——沿用现有 V2 体系（@Local/@Param/@Monitor + BoolState/StrState 包装类）；不引入 V1 装饰器  
**Storage**: 无新增持久化（仅颜色资源与偏好令牌调整）  
**Testing**: 无测试套件；验证 = arkts_check + devecocli build（Phase 3 按默认 build-only 走）  
**Target Platform**: HarmonyOS NEXT（真机/模拟器，API 26）  
**Project Type**: 单模块 HarmonyOS 应用（BiliRadio）  
**Constraints**: Constants.ets 唯一真相源（新魔法数字全部入 Constants）；代码零注释（仅 ponytail: 标注）；禁 any/unknown/as；既有交互回归无损  
**Scale/Scope**: 8 个文件改动，1 个组件改名重构，0 新增服务/模型

## Project Structure

### Documentation (this feature)

```text
spec/v0.4-Part1-sheet-visual-redesign/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/
├── ets/
│   ├── component/
│   │   ├── GlassSheet.ets        # 【改名自 QueueDrawer.ets】通用玻璃浮层容器
│   │   └── QueueSheet.ets        # 队列面板内容（业务不动，仅承接容器参数）
│   ├── pages/
│   │   ├── Index.ets             # 挂载点适配 GlassSheet
│   │   ├── PlayerOverlay.ets     # 挂载点适配 GlassSheet
│   │   └── SettingsPage.ets      # 历史面板：bindSheet → GlassSheet（改动最大）
│   └── service/
│       └── Constants.ets         # 新增/调整令牌
├── resources/
│   ├── base/element/color.json   # 面板底色/文字色调整 + 3 个新色资源
│   └── dark/element/color.json   # 同上（深色取值）
└── AppScope/app.json5            # 0.4.0 / 4000
```

**Structure Decision**: 沿用既有单模块架构（pages/component/service/model 分层，唯一 @Entry + Navigation 路由），不引入 MVVM 目录、不新建层级。组件改名（QueueDrawer→GlassSheet）是复用硬性要求（FR-008）的最小实现：历史面板与队列共用同一容器组件，而非复制平行代码。文件数净变化 0（改名）+0（新增）。

## Complexity Tracking

无宪法违规。

## Research & Decisions

### D1: 历史面板承载方式——bindSheet 迁移到 GlassSheet 容器

- **Decision**: 移除 SettingsPage 历史面板的 `bindSheet`，改为与队列同构的树内条件渲染 GlassSheet（Stack 根部条件挂载）。
- **Rationale**: 系统.bindSheet 的进出场动画由系统控制，无法实现"300ms 滑入+渐显"规格；且 bindSheet 无法自定义投影/顶部边缘分隔线/圆角 24px 的完整组合。FR-008 要求复用同一实现，共用容器后两面板视觉/动画天然一致。
- **Alternatives considered**: ① bindSheet 主题化（backgroundColor/maskColor 可设，但动画、圆角、分隔线、投影均不可达规格，否决）；② 复制一份 HistoryDrawer（违反 FR-008 复用硬性要求，否决）。
- **行为对齐注意**: 历史面板失去系统 dragBar 与 onWillDismiss 拦截（SLIDE_DOWN 不关闭）——与队列现状一致（用户已确认无拖拽关闭），遮罩点击/系统返回关闭路径保留。

### D2: 容器组件设计——QueueDrawer 泛化为 GlassSheet

- **Decision**: `QueueDrawer.ets` 改名 `GlassSheet.ets`，接口泛化：`@Param openState: BoolState`（宿主传入可见性状态）、`@Param panelHeight: string`（默认 '65%'，历史传 '62%'）、`@Param onRegisterClose`（沿用现有关闭句柄注册机制）、`@BuilderParam body`（面板内容）。原内部硬编码的 `AS_SHOW_QUEUE_SHEET` 连接与 `QueueSheet()` 直挂移除，交由宿主决定。
- **Rationale**: 现有 QueueDrawer 已内聚遮罩/面板/动画/关闭句柄机制，泛化四个参数即成通用容器，是最短路径；Index/PlayerOverlay/SettingsPage 三个宿主各自传入自己的 BoolState 与内容。
- **Alternatives considered**: ① 新建 GlassSheet 并保留 QueueDrawer 作为队列薄封装（多一层无意义转发，否决）；② 容器内部按键名 connectBool（@Param 初始化时序不可靠，否决——由宿主持有 BoolState 实例传入，Index/SettingsPage 均已持有）。

### D3: 弹出动画——300ms 滑入 + 渐显复合

- **Decision**: 沿用现有"挂载时 animateTo 驱动显式位移状态"机制（US1 历史结论：TransitionEffect.translate 在部分平台 zIndex 场景不可靠），增加第二个状态量面板透明度 0→1，与位移同帧同曲线驱动；时长 250ms→300ms；退出镜像反向后经延时卸载。
- **Rationale**: 在已验证可靠的机制上叠加一个状态量，避免重新引入曾出问题的 TransitionEffect 方案。
- **Alternatives considered**: ① TransitionEffect.translate + OPACITY 组合（既有平台兼容性风险，否决）；② 仅改时长不动透明度（不满足 FR-006 渐显要求，否决）。

### D4: 顶部边缘分隔线——面板顶边框实现

- **Decision**: 面板 Column 使用 `.border({ width: { top: 1 }, color: $r('app.color.sheet_top_separator') })`，随 24px 圆角自然弯曲。
- **Rationale**: 边框是实现"顶缘 1px 线"的最小手段，无需叠加额外节点。
- **Alternatives considered**: 叠加 1px 高度 Row（多一节点且需处理圆角对齐，否决）。

### D5: 投影——shadow 属性 + 专用色资源

- **Decision**: 面板使用 `.shadow({ radius, offsetY, color: $r('app.color.sheet_shadow') })`；浅色 radius 16/offsetY -4/黑 8%，深色 radius 24/offsetY -8/黑 50%。radius/offsetY 进 Constants（`SHEET_SHADOW_RADIUS_LIGHT/DARK`、`SHEET_SHADOW_OFFSET_LIGHT/DARK`），颜色走 base/dark 资源自适应。
- **Rationale**: ArkUI shadow 支持 radius/offsetY/color 三要素，与设计稿参数一一对应；数值型参数无法走资源目录，集中 Constants。
- **Alternatives considered**: 无（平台原生能力覆盖）。

### D6: 列表底部 80px 渐隐——容器统一承载

- **Decision**: 渐隐带放 GlassSheet 容器内（body 内容区底部叠加 80px 高渐变层，`linearGradient` 从 `sheet_fade_from`（透明版面板底色）到面板底色，`hitTestBehavior(HitTestMode.None)` 不拦截触摸），两面板零重复。
- **Rationale**: 渐隐是容器级装饰（贴合面板底缘），与面板内容无关；放容器内一处实现、两处生效，且天然满足 FR-007"不拦截列表交互"。
- **Alternatives considered**: 各面板自建渐隐层（重复代码，违反复用精神，否决）。
- **附带调整**: QueueSheet 现有 `linearGradientBlur` 顶缘渐晕保持不变（其 fractionStops 底部段本就是无模糊区，与新增渐隐带不冲突）。

### D7: 色彩资源与文字令牌

- **Decision**:
  - `queue_panel_background` 改名 `sheet_panel_background`（历史面板共用，名字去队列化）：浅 `#F2FFFFFF`→`#D9FFFFFF`（85% 白），深 `#F01E1E22`→`#E61C1C1E`（90% #1C1C1E）
  - 新增 `sheet_top_separator`：浅 `#14000000`（黑 8%），深 `#1AFFFFFF`（白 10%）
  - 新增 `sheet_shadow`：浅 `#14000000`（黑 8%），深 `#80000000`（黑 50%）
  - 新增 `sheet_fade_from`：浅 `#00FFFFFF`，深 `#001C1C1E`（面板底色的全透明版，避免黑透明插值产生灰染）
  - `text_primary`：浅 `#1A1A1A`→`#1D1D1F`，深 `#FFFFFF`→`#F5F5F7`
  - `text_secondary`：浅 `#666666`→`#6E6E73`，深 `#B3B3B8`→`#8E8E93`
- **Rationale**: 用户选定"改全局令牌"方案；资源改名同步容器改名，语义一致。渐隐起点用底色同 RGB 的全透明值，规避 Color.Transparent（透明黑）到白底插值中途的灰染。
- **Alternatives considered**: 保留 queue_panel_background 名（历史面板用队列名资源，语义错位，否决）。
- **非目标**: `fg_on_light*`、`BAR_CONTENT_LIGHT`、`text_disabled`、`placeholder_color` 等近似色不动（spec 未涉及，避免范围蔓延）。

### D8: 历史面板返回关闭动画

- **Decision**: SettingsPage 经 GlassSheet 的 `onRegisterClose` 拿到动画关闭句柄存为成员；`onBackPressed` 的 showPlayHistory 分支改为调用该句柄（未注册时回退直接置 false），与队列返回关闭行为对齐。
- **Rationale**: 直接置 false 是瞬时卸载，会丢掉滑出动画；复用容器既有注册机制零新增抽象。
- **Alternatives considered**: 维持直接置 false（行为不一致，动画缺失，否决）。

### D9: 动画/渐隐参数落 Constants

- **Decision**: 新增 `SHEET_SLIDE_MS = 300`（滑入+渐显时长）、`SHEET_FADE_HEIGHT = 80`（底部渐隐高度）；`DRAWER_CLOSE_DELAY_MS` 260→310（保持"略长于动画"关系）；删除 QueueDrawer 文件内局部 `DRAWER_SLIDE_MS`。
- **Rationale**: 新魔法数字全部入 Constants（AGENTS 约定）；关闭延时必须 ≥ 动画时长，否则滑出未完即卸载。
- **Alternatives considered**: 无。

## Data Model

无新增数据实体。改动仅涉及：

- **颜色资源**（base/dark color.json 双份）：`sheet_panel_background`（改名+新值）、`sheet_top_separator`（新增）、`sheet_shadow`（新增）、`sheet_fade_from`（新增）、`text_primary`/`text_secondary`（调值）
- **常量令牌**（Constants.ets）：`SHEET_SLIDE_MS`、`SHEET_FADE_HEIGHT`、`SHEET_SHADOW_RADIUS_LIGHT/DARK`、`SHEET_SHADOW_OFFSET_LIGHT/DARK`（新增）；`DRAWER_CLOSE_DELAY_MS`（调值）
- **版本**：versionName 0.3.0→0.4.0、versionCode 3000→4000（AppScope/app.json5）

## Contracts & Interfaces

### GlassSheet 组件契约（component/GlassSheet.ets，@ComponentV2）

| 成员 | 形态 | 语义 |
|---|---|---|
| `openState: BoolState` | `@Param` | 浮层可见性状态（宿主持有并传入；关闭时容器内部置 `.value = false`） |
| `panelHeight: string` | `@Param`，默认 `'65%'` | 面板高度百分比 |
| `onRegisterClose: (close: (() => void) \| undefined) => void` | `@Param`，默认空实现 | 关闭句柄注册回调（挂载上报动画关闭句柄、卸载上报 undefined 注销），沿用 QueueDrawer 既有机制 |
| `body: () => void` | `@BuilderParam` | 面板内容构建器（队列：QueueSheet；历史：playHistoryPanel） |

**容器内聚职责**：全屏遮罩（mask_heavy，点击→动画关闭）、面板壳（24px 顶圆角/`sheet_panel_background`+backdropBlur(20)/顶缘 1px 分隔线/向上投影/底部 80px 渐隐带）、进出场动画（300ms 位移+透明度，退出镜像+延时卸载）、关闭句柄注册。

**宿主适配契约**：

| 宿主 | 用法 |
|---|---|
| Index | `GlassSheet({ openState: 队列 BoolState, panelHeight: '65%', onRegisterClose: registerQueueClose })` + body 为 `QueueSheet()`；条件挂载逻辑不变（内容层/播放层互斥） |
| PlayerOverlay | 同 Index（播放层实例） |
| SettingsPage | 根部 Stack 条件挂载 `GlassSheet({ openState: showPlayHistory, panelHeight: '62%', onRegisterClose: 历史关闭句柄注册 })` + body 为 `playHistoryPanel()`；移除原 bindSheet 全部选项（height/dragBar/showClose/backgroundColor/preferType/onDisappear/onWillDismiss） |

**不变式**：QueueSheet/SettingsPage 的全部业务方法（数据源 diff、多选、删除确认、清空、回放）签名与行为不变；BackHandler/BackHandler.closeBothLayersNow 行为不变；QueueSheet 的 `@Monitor('showQueueSheet.value')` 多选复位机制依赖同键 BoolState 实例，迁移后保持同源。
