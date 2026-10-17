# Implementation Plan: 订阅详情页重写——B 站风格剧集行（v0.5）

**Input**: Feature specification from `spec/v0.5-part1-source-page-redesign/spec.md`

## Summary

`SourcePage` 剧集列表行参照 B 站客户端横版列表行重排：行左侧新增 16:9 封面缩略图（CoverThumb 宽高分离扩展，向后兼容），时长以半透明角标叠于封面右下角，右侧文字区收敛为「标题（≤2 行）+ 日期 + NEW/已播」。纯视觉重排：全部功能、路由、数据流、状态管理零改动。

## Technical Context

**Language/Version**: ArkTS（API 26，无低版本兼容设计）  
**Primary Dependencies**: 既有组件 `CoverThumb`（V1 `@Component`+`@Prop`，免迁名单）、`CoverUrl.sized`（缩略档取图）  
**State Management**: 既有架构——`SourcePage` 已是 `@ComponentV2`（`@Local`/`connectBool` 等），重排沿用；CoverThumb 维持 V1 `@Prop` 形态（免迁名单内，单 struct 不混代即可）  
**Storage**: 无新增持久化（纯 UI 重排）  
**Testing**: 无测试套件，验证走 `devecocli build` + 真机/模拟器 UI 检视  
**Target Platform**: HarmonyOS NEXT（平板/手机）  
**Project Type**: 单模块 HarmonyOS 应用（增量特性）  
**Performance Goals**: 100+ 集列表快速滚动无可感知卡顿（封面小图缩略档加载）  
**Constraints**: 令牌规范——色值一律 `$r('app.color.*')`、数值一律 `Constants.TOKEN_*`，禁裸数字硬编码  
**Scale/Scope**: 改动面——`SourcePage`（行布局）、`CoverThumb`（宽高分离扩展）、`Constants`（尺寸/角标 token）、color 资源（角标底色）；无新文件、无新模型、无路由改动

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part1-source-page-redesign/
├── spec.md
└── plan.md              # This file
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   └── SourcePage.ets        # [改] 剧集列表行重排：Row{ Stack{16:9 CoverThumb + 时长角标} + 文字区 }；
│                             #      meta 行移除时长；触底行/到底行/空态/头部不动
├── component/
│   └── CoverThumb.ets        # [改] 宽高分离扩展：新增可选 thumbWidth/thumbHeight（默认 0 →
│                             #      回退 thumbSize 方形，既有 4 处调用点零改动）；16:9 缩略请求档
├── service/
│   └── Constants.ets         # [改] 剧集缩略图尺寸 token（vp 显示档 + px 请求档）
└── resources/base/element/
    └── color.json            # [改] 新增角标底色资源（半透明深色 scrim）
```

**Structure Decision**: 跟随既有项目架构（pages/component/service 分层）。增量 UI 特性，不引入新目录/新文件；复用 `CoverThumb`（耳机占位单一事实源）而非在 SourcePage 复制占位逻辑。

## Research & Decisions

### R1 CoverThumb 宽高分离扩展（向后兼容）

- **Decision**: `CoverThumb` 新增普通成员 `thumbWidth: number = 0`、`thumbHeight: number = 0`；两者均 >0 时 `Image`/占位 `Column` 以 `thumbWidth × thumbHeight` 定尺寸，否则维持 `thumbSize` 方形（既有 4 处调用点——`SourcePage` 头部、`HomePage`、`SettingsPage`、`AddSubscriptionSheet`——零改动）。宽高分离时缩略请求档改用 16:9 档 token。
- **Rationale**: 单一占位事实源（耳机占位/边框/高亮逻辑不复制）；普通成员即可（外部传入仅初始化一次，剧集行 cover 随 ForEach 数据项重建）。
- **Alternatives considered**: SourcePage 行内直接 `Image` + 自写占位——被否：复制 ~20 行占位逻辑，双份维护。

### R2 行布局（B 站横版列表行形态）

- **Decision**: `Row { Stack { CoverThumb(16:9) ; 时长角标 } + Column { 标题(≤2行,截断) ; Row{ 日期, NEW, 已播 } } }`。封面左侧、文字区 `layoutWeight(1)` 右侧；行内边距/间距/按压态沿用现状 token 与 `pressedKey` 机制；行背景卡片态不变。
- **Rationale**: B 站历史记录/收藏夹列表的标准形态；文字区三要素（日期/NEW/已播）语义与现状一一对应。
- **Alternatives considered**: 封面右置——被否：与 B 站参照及阅读动线（左图右文）相反。

### R3 时长角标

- **Decision**: `Text(formatDuration(item.duration))` 叠于 `Stack` 底右（`alignContent: Alignment.BottomEnd` + 小边距）：半透明深色底（新增 color 资源）、白字、小圆角、`TOKEN_FONT_AUX` 字号。`duration<=0` 不渲染角标；`formatDuration` 复用 SourcePage 既有函数。
- **Rationale**: 用户已定「封面右下角角标」（B 站标志性位置）；时长归属封面附属信息，文字行只留日期与状态标记。
- **Alternatives considered**: 时长留文字行——被否（用户已排除）。

### R4 列表渲染策略：ForEach 沿用

- **Decision**: 剧集列表维持 `ForEach`（现状），不升级 `LazyForEach`。封面为 ~120vp 宽小图（缩略档请求），ArkUI `Image` 内存缓存 + List 行复用下性能可接受。
- **Rationale**: `ponytail:` 最短可用——LazyForEach 需 `IDataSource` 适配（历史面板已有 HistoryDataSource 先例，升级路径现成）；SC-003 滚动流畅性验收兜底，实测卡顿再升级，避免预先支付复杂度。天花板：100+ 集快速滚动掉帧 → 引入 DataSource + LazyForEach。

### R5 不动清单（重排红线）

- **Decision**: 页面头部（56vp 封面 + 副标题 + 集数 + 刷新/删除）、「播放全部」、空态、触底加载行/「没有更多了」行、退订二次确认、`onReady`/`onHidden` 生命周期、四类翻页链路（`loadOlder`）——全部零改动；辅助行（加载中/没有更多了）不套用新行布局。
- **Rationale**: spec FR-004/FR-005 功能与头部现状红线；纯视觉重排边界。

## Data Model

- **零新增/零改动**: `BiliVideo`（cover/duration 现有字段直用）、`Subscription`、缓存序、`SubscriptionStore` 读写路径全部不变。无新持久化、无新 AppStorage 键（布局常量全部进 `Constants` 静态 token）。

## Contracts & Interfaces

- **CoverThumb 组件签名（扩展后）**: 既有 `{ cover, thumbSize, radius, highlight, accent, raw }` 全保留；新增可选 `thumbWidth`、`thumbHeight`（默认 0=方形回退）。缩略请求档：方形沿用 `COVER_THUMB_W/H`，宽高分离用新增 16:9 档 token。
- **SourcePage 剧集行 UI 契约**: 封面 `EPISODE_THUMB_W × EPISODE_THUMB_H`（16:9，vp token）、圆角 `TOKEN_RADIUS_M` 级、时长角标（R3）、文字区（标题 `TOKEN_FONT_BODY_L` ≤2 行 + meta 行 `TOKEN_FONT_BODY_S`）；行按压态/点击播放行为与现状一致。
- **Constants 新增 token**: `EPISODE_THUMB_W/H`（显示尺寸）、`EPISODE_THUMB_REQ_W/H`（缩略请求像素档，16:9 比例约 2 倍显示尺寸起步）；具体数值实施轮按真机视觉校准，token 先行占位。
- **color 资源新增**: 时长角标底色（如 `duration_badge_scrim`，半透明黑）、角标字色（白，若无可复用 token 则新增）。
