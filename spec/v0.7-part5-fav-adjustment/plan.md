# Implementation Plan: v0.7-part5-fav-adjustment（收藏夹功能调整）

**Input**: Feature specification from `spec/v0.7-part5-fav-adjustment/spec.md`

## Summary

对 part4 交付的四项真机反馈调整：收藏夹源互动稿豁免拦截（`loadPlaylistAndPlay` 加 `allowInteractive` 豁免参，单击/批量随源放行，浏览源与 BV 解析入口保留拦截）；pill 底色不透明（alpha 提满）；特殊标记与队列/历史状态标多选模式常显（门控移除）；fav 批量入队先退多选再异步补全 + 过程提示 + 防重入（修退出动画）。全部改动落在既有文件，零新增文件。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: 零第三方依赖（@kit.* 系）
**State Management**: 既有混合态——PlayerController 零装饰器广播（字段 + `emitUi`）；页面已迁 V2。本轮不引入新代际、不改观测模式
**Storage**: 无新持久化（`TOAST_FAV_COMPLETING` 为内存常量；color 资源为编译期资源）
**Testing**: 无测试套件；`devecocli check arkts` + `devecocli build` + 真机日志验证（项目惯例）
**Target Platform**: HarmonyOS NEXT 单模块应用
**Performance Goals**: 豁免/门控移除均为纯渲染与参数传递，零新增请求
**Constraints**: Constants.ets 唯一真相源；令牌化（色值 `$r('app.color.*')`、数值 `Constants.TOKEN_*`）；代码零注释（`ponytail:` 除外）；禁 `any`/`as` 断言
**Scale/Scope**: 改动 5 个既有文件（PlayerController/SourcePage/QueueSheet/Constants + color.json 资源 alpha 更新）

## Project Structure

### Documentation (this feature)

```text
spec/v0.7-part5-fav-adjustment/
├── spec.md
└── plan.md              # This file
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/PlayerController.ets  # loadPlaylistAndPlay 增 allowInteractive 豁免参
├── pages/SourcePage.ets          # enqueueSelected 先退多选+过程提示+防重入；两入队路径传豁免参
├── component/QueueSheet.ets      # specialMarkPrefix 与六处状态标 selectMode 门控移除
└── service/Constants.ets         # TOAST_FAV_COMPLETING 过程提示文案
entry/src/main/resources/base/element/color.json   # 四类 pill_bg alpha FF
```

**Structure Decision**: 沿用既有架构零新增文件——豁免是既有函数加可选参、常显是门控移除、不透明是资源 alpha 更新。

## Complexity Tracking

无宪法违规。全部为既有文件的增量修改。

## Research & Decisions

- **Decision**: 豁免收敛在 `loadPlaylistAndPlay` 单点可选参 `allowInteractive`（默认 false），SourcePage 两入队路径按 `sub.type === TYPE_FAV` 传入；`addSingleVideo` 不传参保留拦截
  **Rationale**: 该函数是点播/入队/分享导入唯一汇聚点，单点参数即全入口可控；默认 false 保证未传参调用方零改动零回归
  **Alternatives considered**: 各调用方各自过滤——多入口重复且易漏，弃；仅批量豁免（单击仍拦）——同页面单击/批量语义分裂，弃

- **Decision**: 批量入队先退多选再异步补全，对齐队列/历史「先退多选再操作」既有模式；fav 路径弹过程提示（`TOAST_FAV_COMPLETING`）+ `enqueueInFlight` 防重入
  **Rationale**: 详情拉取数秒，先入队再退会吞掉退出动画；fav 批量补全在途期间重复确认会重复入队，防重入标志兜底
  **Alternatives considered**: 保持先补全再退多选——动画缺陷保留，弃；过程提示复用 statusMsg——statusMsg 是入队结果通道，语义混用，弃

- **Decision**: 多选常显直接移除 QueueSheet 六处状态标与 `specialMarkPrefix` 的 `selectMode` 门控（最小 diff），HistorySheet 状态标本无门控不动
  **Rationale**: 门控移除即常显，无需新增渲染分支
  **Alternatives considered**: 加常显开关配置——无此需求，弃

- **Decision**: pill 不透明直接改四类 `*_pill_bg` 资源 alpha D9→FF，不新增资源
  **Rationale**: 半透明变体无其他消费方（pill 底色专用），就地更新即全部生效
  **Alternatives considered**: 新增不透明变体资源并存——旧变体无消费方，多一份死资源，弃

## Data Model

无模型改动。新增常量与参数：

- `Constants.TOAST_FAV_COMPLETING`：fav 批量补全过程提示文案（「正在补全标志…」）
- `PlayerController.loadPlaylistAndPlay` 第 4 参 `allowInteractive: boolean = false`
- `SourcePage.enqueueInFlight: boolean`：fav 批量补全防重入标志

## Contracts & Interfaces

### `PlayerController.loadPlaylistAndPlay(items, startIndex, insertAfterCurrent, allowInteractive) → EnqueueResult`

`allowInteractive`（默认 false）为 true 时跳过互动过滤（`!allowInteractive && items[i].isInteractive`），互动稿照常入队走默认路线；false 时行为与 part4 交付一致（全互动返 `INTERACTIVE`、混合场景过滤 + statusMsg 通报）。调用方：SourcePage `enqueueAndToast`/`enqueueSelected` 传 `sub.type === TYPE_FAV`；HomePage/AddSubscriptionSheet 经 `addSingleVideo` 不传参（默认拦截）。

### `SourcePage.enqueueSelected`（fav 源批量入队详情补全，part4 修订⑥基础上调整）

确认入队后：快照选中条目 → 立即 `exitSelectMode()`（动画即刻起播）→ fav 路径置 `enqueueInFlight` 并弹 `TOAST_FAV_COMPLETING` → 异步并行补全（并发上限 Constants 令牌）→ `loadPlaylistAndPlay(…, favPath)` → 结果 toast。`enqueueInFlight` 在途时重复确认直接忽略。单条详情失败降级原列表行入队（无标志、互动不拦）。UP 源/合集批量不拉详情（行自带标志）。

### `SourcePage.enqueueAndToast`

单击/「+」入队路径传 `allowInteractive = sub.type === TYPE_FAV`。

### Constants 新增

`TOAST_FAV_COMPLETING`（fav 批量入队过程提示文案），命名对齐既有 `TOAST_*` 系列。

### 渲染层

- `SourcePage` markPills：pill 底色资源 alpha FF（不透明），渲染逻辑零改动
- `QueueSheet`：`specialMarkPrefix` 去 `!selectMode` 门控；✓/✗/! 六处状态标（分P 行 isPartPlayed/hasInvalid/hasAnomaly + 条目组头行同三处）门控移除，多选模式常显
- `HistorySheet`：无门控，零改动

### 自检与验证口径

- 豁免与拦截分路径行为以真机样本验证（fav 互动稿放行/UP 源拦截），纳入 Verification 真机自查事项
- 门控移除为纯渲染 diff（删条件），构建通过即逻辑等价常显
