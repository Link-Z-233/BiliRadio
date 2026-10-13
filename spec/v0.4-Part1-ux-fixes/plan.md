# Implementation Plan: v0.4-Part1 UX 修复轮

**Input**: Feature specification from `spec/v0.4-Part1-ux-fixes/spec.md`

## Summary

对 12 项体验问题集中修复：3 项功能 bug（chevron 收起失效、MiniPlayer 返回闪现、按压态方角溢出）、音质档位体系（nav 补解析 vipStatus/face + 档位过滤 + 分场景提示 + 头像）、浮层视觉对齐（详情/关于 bindSheet 换 GlassSheet 玻璃公式、展开指示换系统图标）、历史面板多选（复制队列交互、移除清空按钮、多选态禁左滑）、关于页内容重写（用户提供确切文案 + 四链接二次确认跳浏览器）、debug 启动提醒（含启动恢复链路前移）。全部为既有文件修改，零新增文件。

## Technical Context

**Language/Version**: ArkTS（API 26 基线，compatibleSdkVersion=26.0.0，不考虑 API<26 兼容）
**Primary Dependencies**: ArkUI（State Management V2 已整体迁移）、@kit.ArkUI / @kit.BasicServicesKit
**State Management**: 增量改动跟随现状——页面/挂键组件全 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；模型层 `@ObservedV2`+`@Trace`；`PlayerController` 零装饰器广播模式不动；新代码一律 V2 装饰器
**Storage**: AppStore（preferences，KEY_* 持久化）；AppStorageV2（AS_* 瞬态，经 V2State 包装）
**Testing**: 无测试套件；验证=构建 + 模拟器 UI 验证（深浅双模式）
**Target Platform**: HarmonyOS NEXT（模拟器/平板）
**Project Type**: 单模块移动应用（音频播客）
**Performance Goals**: 不回归（播放帧率、浮层动画 250ms 基准）
**Constraints**: 代码零注释（ponytail: 标注除外）；Constants 唯一真相源；禁 any/unknown/as 断言；B 站 API 零新增请求
**Scale/Scope**: 11 个既有文件修改，10 用户故事，15 FR

## Project Structure

### Documentation (this feature)

```text
spec/v0.4-Part1-ux-fixes/
├── spec.md              # 需求（已确认）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── Index.ets                # US3 MiniPlayer 闪现修复；US10 debug 启动恢复前移+toast
│   ├── PlayerOverlay.ets        # US1 chevron 容器重构；US6 详情 sheet 玻璃公式+指示图标
│   ├── SettingsPage.ets         # US4/5 历史多选；US7 关于页重做；US2 音质过滤；US9 头像
│   └── LogPage.ets              # US8 按压方角同修
├── component/
│   ├── SettingsGroup.ets        # US8 卡片容器 .clip(true)
│   └── QueueSheet.ets           # US5 swipeAction 条件挂载（历史同模式参照）
├── service/
│   ├── BiliService.ets          # US2/9 fetchNav 补解析 vipStatus/face
│   ├── BiliSession.ets          # US2/9 会话扩展字段
│   └── Constants.ets            # 链接常量、新状态键（如需）
└── model/
    └── AudioQuality.ets         # US2 档位可用性逻辑（若放模型）
```

**Structure Decision**: 跟随现有项目架构（service/model/pages/component 分层，依赖单向契约不变）。零新增文件，全部为既有文件修改；不引入 MVVM 迁移或目录重构。GlassSheet 为对齐目标组件本身不改。

## Complexity Tracking

（无宪法违规——全部为既有模式内修改）

## Research & Decisions

### D1 - chevron 收起按钮修复（FR-001 / US1）

**Decision**: 最小容器重构——chevron 裸 `SymbolGlyph.onClick` 外包一层可点击容器（对齐同 Scroll 内已知可用的 ▶播放按钮「外包 Row、识别器参战」结构模式）。
**Rationale**: hilog 铁证：点击命中链止于 Scroll，glyph 自身识别器从未参战；▶按钮同环境正常，结构差异即根因。容器重构改动最小（单组件局部）。
**Alternatives considered**: ① 顶栏移出滚动区（放弃：放弃 v0.4.0 US5 骨架修正收益、布局回归风险大，作为容器重构不生效时的二级方案）；② 换 Button 组件（未试：容器方案更贴近已验证可用的对照样本）。

### D2 - 详情/关于 sheet 视觉对齐（FR-002/008 / US6/US7）

**Decision**: 保留系统 bindSheet（detents/dragBar/下滑关闭不变），仅对齐视觉：内容根容器背景 `sheet_background` → GlassSheet 玻璃公式（`sheet_panel_background` + backdropBlur(20) + 顶 1px `sheet_top_separator` 边框）。
**Rationale**: GlassSheet 实测公式已在队列/历史面板落地，令牌深浅色资源齐备，换令牌零新增设计。
**Alternatives considered**: bindSheet 换自绘 GlassSheet（放弃：丢系统拖拽条/手势、改动量数倍，用户已确认只对齐视觉）。

### D3 - 展开指示按钮（FR-003 / US6）

**Decision**: 「▼」Text 字符换 `sys.symbol.chevron_down` SymbolGlyph（sysResource ID 125832666，已确认存在），打开/关闭 180° 旋转动画保留。
**Rationale**: 全应用图标语言统一为 SymbolGlyph；系统图标随字体缩放与深浅色着色。
**Alternatives considered**: 保留文字字符加字体图标（放弃：着色/缩放行为不一致）。

### D4 - 历史面板多选（FR-004/005 / US4）

**Decision**: 交互完整复制 QueueSheet 现实现：长按进入、点行勾选、操作行（全选 / 删除所选(计数) / 返回）、批量删除二次确认、面板关闭自动复位。头部新增 36×36 玻璃图标按钮（btn_glass + blur + border，队列同款），移除「清空」文字按钮。多选状态用 SettingsPage 内 `@Local`（面板级），不建全局 AS_* 键。
**Rationale**: 队列多选已完整落地且经过验证，复制语义零设计成本；历史面板单一挂载点（SettingsPage），无跨页面共享需求，`@Local` 随面板卸载天然复位（对比队列因跨 Index/PlayerOverlay 挂载点才用全局键）。
**Alternatives considered**: 沿用 AS_PLAYLIST_SELECT_MODE 全局键（放弃：跨页面共享是队列的需求而非历史的，多余耦合）。

### D5 - 多选态禁左滑（FR-006 / US5）

**Decision**: 队列与历史的 `swipeAction` 改为条件挂载（仅非多选态挂载删除动作）。
**Rationale**: 手势互斥的直接表达；对比「挂载但内部禁用」少一层状态穿透。
**Alternatives considered**: swipeAction 内部按 selectMode 返回空（放弃：条件挂载更直白，行为等价）。

### D6 - MiniPlayer 返回闪现（FR-007 / US3）

**Decision**: 实施轮先加日志定位闪现精确帧序列（当前链路：SettingsPage onWillDisappear 设 NAV_EXIT_TRANSITION_MS 定时器 → 翻 onSettingsPage=false → Index Monitor → animateTo 250ms），按定位结果在定时器时序或动画作用域上做最小修复。
**Rationale**: 闪现=「消失-突现」两段不连续动画，疑似定时器窗口与重现动画未衔接；盲改风险大，先定位后修。
**Alternatives considered**: 直接去掉定时器（放弃：T021/R4 竞态修复成果，快速往返场景依赖它）。
**约束**: 修复不得回归快速往返竞态（T021/R4 逻辑保留）。

### D7 - 按压态方角（FR-012 / US8）

**Decision**: SettingsGroup 卡片容器加 `.clip(true)`（ArkUI 父容器 borderRadius 不裁剪子内容，首尾行方形按压背景溢出圆角）；LogPage 列表同模式同修。
**Rationale**: 单属性修复；分组内容均无溢出卡片外的元素，裁剪零副作用。
**Alternatives considered**: 按压背景按行位逐行配圆角（放弃：需感知首/中/尾行位，六处分支复杂度远超一行 clip）。

### D8 - 音质档位一致性（FR-013/014 / US2）

**Decision**: fetchNav（BiliService，现仅解析 isLogin/mid/uname）补解析 `vipStatus`/`face`（同一响应，零新增请求）→ BiliSession 扩内存字段 → 音质选择页按矩阵过滤：64K=全员 / 132K=登录 / 192K=大会员 / 「最高」=语义档；提示分场景（未登录=「登录后可用更高音质」沿用现有；非会员=192K 需大会员）；已存不可用档位显示收敛至可用档。nav 失败按非会员处理。
**Rationale**: biliRelay 实测 192K（30280）需大会员；fetchNav 已在调，补字段零成本；保守过滤（失败按非会员）宁可少给不产生「显示≠实际」。
**Alternatives considered**: 用 playurl 响应兜底检测（放弃：每次播放才能修正档位列表，设置页场景拿不到）。

### D9 - 账号行头像（FR-015 / US9）

**Decision**: 账号行已登录且 face 非空 → Image(URL) 圆形裁切替代 `sys.symbol.person`；加载失败/URL 空 → 回退原图标；未登录不变。
**Rationale**: face 与 vipStatus 同链路获取，无额外请求；Image onError 回退保证不空白。

### D10 - 关于页内容与链接（FR-009/010 / US7）

**Decision**: 内容采用 spec FR-009 确切文案；结构=简介段 → 五条核心功能 → 关于本项目声明段（BiliMusic/PiliPlus 项目名可点击）→ 项目地址两行（GitCode/GitHub）。四个链接统一交互：点击 → AlertDialog 二次确认 → 确认后 openLink 拉起系统浏览器（appLinkingOnly=false），取消不跳转，拉起失败 toast。链接常量收 Constants（唯一真相源）。
**Rationale**: 文案用户逐字提供；声明段内项目名用 Text+Span 点击（Span.onClick），项目地址独立行组件；二次确认与项目地址交互统一（用户要求）。
**Alternatives considered**: 声明段整体不可点、参考项目单独列行（放弃：用户明确要求参考项目名也带跳转）。

### D11 - debug 启动提醒（FR-011 / US10）

**Decision**: debug 恢复链路前移：Index aboutToAppear 读 `KEY_DEBUG_MODE` → `Logger.setDebugMode`（现状仅 SettingsPage aboutToAppear 恢复，启动不进设置页则 debug 实际未生效——顺带修复）；恢复后若开启 → toast「调试模式运行中」。SettingsPage 的 setDebugMode 重复恢复移除（读取 AppStore 供开关显示的逻辑保留）。
**Rationale**: 启动提醒的前提是启动时状态真实生效；Index 是唯一 @Entry，启动必经。
**Alternatives considered**: EntryAbility onCreate 恢复（放弃：toast 需 UI 上下文，恢复与提醒同点最简）。

### D12 - 深浅双模式验证

**Decision**: 全部视觉改动（详情/关于/指示图标/按压圆角/头像）纳入深浅双模式验证；行为改动（chevron/多选/闪现）单模式验证 + 关键路径双模式抽查。
**Rationale**: v0.4.0 轮验证标准沿用。

## Data Model

### BiliSession（扩展）

| 字段 | 类型 | 生命周期 | 说明 |
|---|---|---|---|
| vipStatus | number | 内存态 | 0=非会员 1=大会员；启动+登录刷新，clear() 清零 |
| face | string | 内存态 | 头像 URL；同上 |

刷新链路沿用现有 fetchNav 调用点（启动恢复 cookie 后 + 登录保存后 + 懒触发兜底），不落盘。

### 音质档位可用矩阵

| 档位 | 未登录 | 非会员 | 大会员 |
|---|---|---|---|
| 最高（语义档） | ✓ | ✓ | ✓ |
| 192K | ✗ | ✗ | ✓ |
| 132K | ✗ | ✓ | ✓ |
| 64K | ✓ | ✓ | ✓ |

可用性判定输入：isLogged（BiliSession）+ vipStatus；输出：可选档位数组（qualityOptions 过滤源）。已存档位不在可选集 → 显示收敛至可用档。

### 历史多选状态（SettingsPage 内 @Local）

| 字段 | 类型 | 说明 |
|---|---|---|
| historySelectMode | boolean | 多选开关；长按进入、返回/面板关闭退出 |
| selectedHistoryIds | Set\<string\> | 勾选集合；操作行计数/全选/删除所选消费 |

## Contracts & Interfaces

### 内部接口（本次扩展）

- **fetchNav 解析扩展**（BiliService）：nav 响应 `data.vipStatus: number`、`data.face: string` 写入 BiliSession；解析失败字段容错（缺省 0/''，不抛错）
- **档位可用性判定**（AudioQuality 静态方法或 SettingsPage 私有）：输入 isLogged + vipStatus → 输出可用 `AudioQuality[]`；供 qualityOptions 与档位收敛共用
- **外链跳转**（SettingsPage 私有）：输入 URL → AlertDialog 二次确认 → openLink（appLinkingOnly=false）→ 失败 toast；四个链接复用同一实现

### UI 契约

- chevron 收起：点击关闭播放层（AS_SHOW_PLAYER_OVERLAY=false），命中链须含新容器识别器
- 历史多选操作行：全选 / 删除所选(计数) / 返回，语义与队列逐项对齐
- 关于页链接：点击 → 确认框（「跳转到外部浏览器？」语义）→ 浏览器拉起

### 不变契约

- 玻璃公式令牌族（sheet_panel_background / sheet_top_separator / sheet_shadow 深浅分档）沿用，零新令牌
- 队列多选现行为零回归（AS_PLAYLIST_SELECT_MODE 及操作行不动）
- 系统路由表 / Navigation 结构 / main_pages.json 不动
