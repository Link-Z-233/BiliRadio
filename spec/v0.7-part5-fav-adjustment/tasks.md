# Tasks: v0.7-part5-fav-adjustment（收藏夹功能调整与交互补充）

**Input**: Design documents from `spec/v0.7-part5-fav-adjustment/`
**Prerequisites**: plan.md（已就绪）、spec.md（已就绪）

**Tests**: 无测试套件，不生成测试任务；自检面 = 构建验证 + 真机交互验证（plan「自检与验证口径」节）

**Organization**: 按用户故事分组（US1 互动豁免 → US2 标记常显与 pill 不透明 → US3 批量入队交互修复 → US4 默认获取顺序与排序开关 → US5 队列点击当前条目无操作 → US6 类型四色标识）。原四项（US1-3，T001-T007）与增补三项（US4-6，T008-T015）均已实施完成；真机反馈修正两项（T016-T019）为本次执行批次。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事
- 描述含精确文件路径

## Path Conventions

- 单模块既有项目，源码根：`entry/src/main/ets/`
- 本轮零新增文件，全部为既有文件增量修改

## Phase 1: Setup

既有单模块项目，无初始化任务。

---

## Phase 2: Implementation

### 原四项（已实施，保留记录）

- [X] T001 [US1] `loadPlaylistAndPlay` 增第 4 参 `allowInteractive: boolean = false`，过滤条件改 `!allowInteractive && items[i].isInteractive`，豁免时互动稿照常入队走默认路线；未传参调用方零改动 `entry/src/main/ets/service/PlayerController.ets`
- [X] T002 [US1] `enqueueAndToast` 与 `enqueueSelected` 传豁免参 `sub.type === Subscription.TYPE_FAV`；`addSingleVideo` 不传参保留拦截 `entry/src/main/ets/pages/SourcePage.ets`
- [X] T003 [P] [US2] QueueSheet `specialMarkPrefix` 去 `!selectMode` 门控；✓/✗/! 六处状态标门控移除（分P 行 isPartPlayed/hasInvalid/hasAnomaly + 条目组头行同三处），多选常显 `entry/src/main/ets/component/QueueSheet.ets`
- [X] T004 [P] [US2] 四类 `*_pill_bg` color 资源 alpha D9→FF（不透明）`entry/src/main/resources/base/element/color.json`
- [X] T005 [US3] `enqueueSelected` 重排：快照 → 立即 `exitSelectMode()` → fav 路径置 `enqueueInFlight` + 弹 `TOAST_FAV_COMPLETING`（Constants 新增）→ 异步补全 → 入队 → 结果 toast；在途重复确认忽略 `entry/src/main/ets/service/Constants.ets` + `entry/src/main/ets/pages/SourcePage.ets`

### 增补三项（已实施）

- [X] T008 [P] [US4] `refreshSubscription` 排序收窄：统一发布时间降序重排仅保留 UP 分支（APP+Web 合并后排序）；FAV/SEASON/SERIES 保留接口返回顺序直接 `saveEpisodes`；`latestPubAt` 改遍历 items 取 pubdate 最大值（>0 才更新），不再取排序后首条 `entry/src/main/ets/service/SubscriptionStore.ets`
- [X] T009 [US4] SourcePage 排序状态与行序基准：`@Local sortByTime: boolean = false`（会话级）；`fetchOrder: string[]`（private，bvid 序列——`loadFromCache` 初始化、`loadOlder` 追加 fresh 时同步记录）；`loadOlder` 追加后仅 UP 或 `sortByTime` 开启时按 pubdate 降序重排，否则直接追加尾部；开关开启=episodes 按 pubdate 降序重排、关闭=按 fetchOrder 键索引还原（均纯内存 0 请求）`entry/src/main/ets/pages/SourcePage.ets`
- [X] T010 [US4] 「更多」菜单排序开关：`moreMenuBuilder` 增「按时间排序」MenuItem（`selected(this.sortByTime)` + `selectIcon(true)` + `onChange` 翻转并触发 T009 重排/还原），仅 fav/season/series 显示（UP 不显示）；Constants 新增 `MENU_LABEL_SORT_BY_TIME` `entry/src/main/ets/service/Constants.ets` + `entry/src/main/ets/pages/SourcePage.ets`
- [X] T011 [P] [US5] QueueSheet 三处非多选点击路径加当前条目守卫：目标复合键（`BiliVideo.itemKeyOf`）=== `currentKey` 即返回（`queueFullRow` 目标=entry.videos[0]、`queuePartRow` 目标=part、`onGroupHeaderClick` 两段判定算出目标分P 后比对）；多选分支与长按进多选前置逻辑不动 `entry/src/main/ets/component/QueueSheet.ets`
- [X] T012 [P] [US6] 色点令牌：color.json 新增 `sub_type_up`（#007AFF）/`sub_type_fav`（#FFB027）/`sub_type_season`（#AF52DE）/`sub_type_series`（#34C759）；Constants 新增 `SUB_TYPE_DOT_SIZE: number = 8` `entry/src/main/resources/base/element/color.json` + `entry/src/main/ets/service/Constants.ets`
- [X] T013 [US6] HomePage `subRowCore` 标题行前置类型色点：按 `row.sub.type` 映射四色圆点（`SUB_TYPE_DOT_SIZE` 尺寸）+ 间距令牌，标题文本放色点后（截断行为不变）；纯展示元素，行交互零改动 `entry/src/main/ets/pages/HomePage.ets`

### 真机反馈修正（增补批次交付后，本次执行批次）

- [X] T016 [US4] `moreMenuBuilder` 排序开关勾选标记右移：去 `.selected()`/`.selectIcon(true)`/`.onChange`，改 `symbolEndIcon`（开启态经成员方法语句式构造 `new SymbolGlyphModifier($r('sys.symbol.checkmark'))` + `fontColor([accent])`，关闭态 undefined）+ `.onClick` 翻转 `applySortByTime(!this.sortByTime)`；仅 fav/season/series 显示不变；文件顶部增 `import { SymbolGlyphModifier } from '@kit.ArkUI'` `entry/src/main/ets/pages/SourcePage.ets`
- [X] T017 [US6] 源页 `headerRow` 类型胶囊四色：typeLabel Text `.fontColor` 改按类型映射 `$r('app.color.sub_type_up'/'sub_type_fav'/'sub_type_season'/'sub_type_series')`、`.backgroundColor` 改对应 `sub_type_*_tint` 资源（color.json base 新增四条：#1F007AFF / #1FFFB027 / #1FAF52DE / #1F34C759，12% 淡底）；去该处 `accentColor`/`hexWithAlpha` 用法 `entry/src/main/ets/pages/SourcePage.ets` + `entry/src/main/resources/base/element/color.json`

---

## Phase 3: Verification

<!-- verification_scope: build-only -->

**Purpose**: 构建验证通过即收尾（默认停到真机前，不执行真机部署/运行/UI 验证）

### 原四项验证（已完成）

- [X] T006 对本轮全部改动 `.ets` 文件（PlayerController/SourcePage/QueueSheet/Constants）执行 `devecocli check arkts`，随后 `devecocli build`，编译错误修复后重建直至通过（构建即收尾停点）
- [X] T007 汇总真机自查事项输出到轮次总结（fav 豁免放行、浏览源拦截保留、队列/历史多选常显、fav 批量退出动画与过程提示、防重入、pill 不透明观感），验证结论待用户真机回填 BILI_NOTES §3

### 增补三项验证

- [X] T014 对增补改动 `.ets` 文件（SubscriptionStore/SourcePage/QueueSheet/HomePage/Constants）执行 `devecocli check arkts`，随后 `devecocli build`，编译错误修复后重建直至通过（构建即收尾停点）
- [X] T015 汇总增补真机自查事项输出到轮次总结（fav/合集/系列默认获取顺序、开关开/关/重进三态、UP 顺序零变化、latestTitle 随获取顺序变化、队列点击当前条目不打断、点击非当前条目切播、四类色点颜色对应、新增订阅色点），验证结论待用户真机回填

### 真机反馈修正验证

- [X] T018 对反馈修正改动 `.ets` 文件（SourcePage）执行 `devecocli check arkts`，随后 `devecocli build`（构建即收尾停点）
- [X] T019 汇总反馈修正真机自查事项输出到轮次总结（开关开启态右侧对号且文字与刷新/取消订阅左对齐、关闭态无图标、fav/合集/系列/UP 四类源页胶囊颜色与首页色点一致），验证结论待用户真机回填

---

## Dependencies & Execution Order

### 原四项

- T001 先行（T002/T005 依赖其新参数）
- T003/T004 与 T001/T002/T005 不同文件可并行
- T005 依赖 T001（豁免参）与既有 fav 批量补全（part4 修订⑥）
- Verification（T006→T007）依赖全部实施任务

### 增补三项

- T008/T011/T012 互相独立（不同文件）可并行
- T009 依赖 T008 落位后语义成立（缓存顺序=获取顺序），同文件内先行于 T010
- T010 依赖 T009（开关读写 `sortByTime`、触发重排/还原）
- T013 依赖 T012（色点令牌与尺寸令牌）
- Verification（T014→T015）依赖全部增补实施任务

### 真机反馈修正

- T016 → T017 同文件（SourcePage.ets）顺序执行
- Verification（T018→T019）依赖 T016/T017

---

## Parallel Example

```text
# 增补批次不同文件可并行（Implementation 阶段内）：
Task: T008 SubscriptionStore 排序收窄 (service/SubscriptionStore.ets)
Task: T011 QueueSheet 点击守卫 (component/QueueSheet.ets)
Task: T012 色点令牌 (resources color.json + service/Constants.ets)

# 同文件顺序执行：
Task: T008 → T009 → T010（SubscriptionStore.ets → SourcePage.ets → Constants.ets + SourcePage.ets）
Task: T012 → T013（令牌 → HomePage 色点消费）
```

---

## Implementation Strategy

### Single Batch Delivery（增补批次）

1. T008/T011/T012 并行（不同文件）
2. T009 → T010 顺序（SourcePage 排序状态 → 菜单开关）
3. T013 收尾（消费 T012 令牌）
4. Verification（T014/T015）构建收尾 + 真机自查清单输出

### 反馈修正批次交付

1. T016 → T017（同文件顺序）
2. Verification（T018/T019）构建收尾 + 真机自查清单输出

---

## Notes

- 豁免仅随收藏夹源传入，勿扩散到 UP/合集批量与 BV 解析入口
- 门控移除为纯渲染 diff（删条件），不加常显开关
- 排序开关仅 fav/season/series 显示；UP 时间序即获取语义，勿加开关
- fetchOrder 与 episodes 追加必须同步（漏记导致关闭开关无法还原获取顺序）
- 队列守卫仅非多选切播路径；勿在 playIndex 加同索引守卫（影响切音质/重播/断点恢复内部路径）
- 色点为纯展示元素，勿绑定任何交互事件
- 代码零注释（`ponytail:` 除外）；色值/数值令牌化，禁裸硬编码
- SymbolGlyphModifier 链式 fontColor 返回基类 SymbolGlyphAttribute（禁 as 断言），须成员方法内语句式构造再返回；@Builder 体内禁局部声明
- sys.symbol.checkmark 已在本机 sysResource.js 核实存在
