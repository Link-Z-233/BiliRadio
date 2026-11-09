# Tasks: v0.7-part5-fav-adjustment（收藏夹功能调整）

**Input**: Design documents from `spec/v0.7-part5-fav-adjustment/`
**Prerequisites**: plan.md（已就绪）、spec.md（已就绪）

**Tests**: 无测试套件，不生成测试任务；自检面 = 构建验证 + 真机交互验证（plan「自检与验证口径」节）

**Organization**: 按用户故事分组（US1 互动豁免 → US2 标记常显与 pill 不透明 → US3 批量入队交互修复）。

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

- [X] T001 [US1] `loadPlaylistAndPlay` 增第 4 参 `allowInteractive: boolean = false`，过滤条件改 `!allowInteractive && items[i].isInteractive`，豁免时互动稿照常入队走默认路线；未传参调用方零改动 `entry/src/main/ets/service/PlayerController.ets`
- [X] T002 [US1] `enqueueAndToast` 与 `enqueueSelected` 传豁免参 `sub.type === Subscription.TYPE_FAV`；`addSingleVideo` 不传参保留拦截 `entry/src/main/ets/pages/SourcePage.ets`
- [X] T003 [P] [US2] QueueSheet `specialMarkPrefix` 去 `!selectMode` 门控；✓/✗/! 六处状态标门控移除（分P 行 isPartPlayed/hasInvalid/hasAnomaly + 条目组头行同三处），多选常显 `entry/src/main/ets/component/QueueSheet.ets`
- [X] T004 [P] [US2] 四类 `*_pill_bg` color 资源 alpha D9→FF（不透明）`entry/src/main/resources/base/element/color.json`
- [X] T005 [US3] `enqueueSelected` 重排：快照 → 立即 `exitSelectMode()` → fav 路径置 `enqueueInFlight` + 弹 `TOAST_FAV_COMPLETING`（Constants 新增）→ 异步补全 → 入队 → 结果 toast；在途重复确认忽略 `entry/src/main/ets/service/Constants.ets` + `entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 3: Verification

<!-- verification_scope: build-only -->

**Purpose**: 构建验证通过即收尾（默认停到真机前，不执行真机部署/运行/UI 验证）

- [X] T006 对本轮全部改动 `.ets` 文件（PlayerController/SourcePage/QueueSheet/Constants）执行 `devecocli check arkts`，随后 `devecocli build`，编译错误修复后重建直至通过（构建即收尾停点）
- [X] T007 汇总真机自查事项输出到轮次总结（fav 豁免放行、浏览源拦截保留、队列/历史多选常显、fav 批量退出动画与过程提示、防重入、pill 不透明观感），验证结论待用户真机回填 BILI_NOTES §3

---

## Dependencies & Execution Order

- T001 先行（T002/T005 依赖其新参数）
- T003/T004 与 T001/T002/T005 不同文件可并行
- T005 依赖 T001（豁免参）与既有 fav 批量补全（part4 修订⑥）
- Verification（T006→T007）依赖全部实施任务

---

## Parallel Example

```text
# 不同文件可并行（Implementation 阶段内）：
Task: T003 QueueSheet 门控移除 (component/QueueSheet.ets)
Task: T004 pill_bg alpha FF (resources/base/element/color.json)

# 同文件顺序执行：
Task: T001 → T002 → T005（PlayerController.ets → SourcePage.ets → Constants.ets + SourcePage.ets）
```

---

## Implementation Strategy

### Single Batch Delivery

1. T001 豁免参先行（全路径依赖）
2. T002/T003/T004 并行（不同文件）
3. T005 交互重排收尾（依赖 T001/T002 落位）
4. Verification（T006/T007）构建收尾 + 真机自查清单输出

---

## Notes

- 豁免仅随收藏夹源传入，勿扩散到 UP/合集批量与 BV 解析入口
- 门控移除为纯渲染 diff（删条件），不加常显开关
- 代码零注释（`ponytail:` 除外）；色值/数值令牌化，禁裸硬编码
