# Tasks: UX 反馈第 7 轮（R7）

**Input**: Design documents from `spec/ux-feedback-round7/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: 无测试套件，不生成测试任务。验证 = arkts_check + devecocli build + 虚拟机 UI 实测（见 Verification 阶段）。

**Organization**: 任务按用户故事分组，支持独立实现与独立验证。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1-US9）
- 描述含精确文件路径

## Path Conventions

- 单模块项目：源码在 `entry/src/main/ets/`（pages/component/service/model）
- 路由表：`entry/src/main/resources/base/profile/router_map.json`
- 色板：`entry/src/main/resources/base/element/color.json`

---

## Phase 1: Setup

**Purpose**: 重写前基线核对（D9 风险缓解）

- [X] T001 通读 spec/plan 与 7 个目标源文件，按 plan.md D9 功能清单逐项核对 `entry/src/main/ets/pages/SettingsPage.ets` 现有功能（账号/播放设置/外观/历史/日志/关于），确认重写基线无遗漏

---

## Phase 2: Foundational

**Purpose**: 设置页/日志页共用组件（阻塞 US5/US8）

- [X] T002 [P] 新增分组卡片容器组件（分组标题 + 卡片 + 子内容槽）`entry/src/main/ets/component/SettingsGroup.ets`
- [X] T003 [P] 新增设置行组件（图标/标题/副题可选 + 右侧槽〔Toggle|箭头|值〕+ 可选 onClick）`entry/src/main/ets/component/SettingsRow.ets`

**Checkpoint**: 共用组件就绪，US5/US8 可开始

---

## Phase 3: User Story 1 - UP 触底加载永不静默 (Priority: P1) 🎯 MVP

**Goal**: UP 订阅列表触底时必然触发加载或有明确反馈，不再静默不动

**Independent Test**: 虚拟机打开 UP（罗翔）订阅源，fling 触底 → 出现加载行或「没有更多」，列表增长或明确终止

- [X] T004 [US1] `loadFromCache` UP 分支触底门槛由 `cached>=30||hasUpAppCursor` 放宽为 `cached.length > 0`（与 FAV 对齐）`entry/src/main/ets/pages/SourcePage.ets`
- [X] T005 [US1] 无游标降级 Web 链时页号按当前列表长度对齐 ps=30 页界推算起始页（去重兜底防跳条重复）`entry/src/main/ets/pages/SourcePage.ets`
- [X] T006 [US1] 触底反馈链路核查：加载中行（loadingOlder）与失败 3 秒冷却已有，确认短页/全重复页终止时有可见反馈、无静默路径 `entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 4: User Story 2 - 列表完整且时序正确 (Priority: P1)

**Goal**: UP 刷新结果双链合并治稀疏；触底追加后全列表按发布时间降序

**Independent Test**: 虚拟机刷新罗翔源 → 列表含 9-19、9-13 等 APP 链缺失条目且按时间降序；触底加载后仍降序

- [X] T007 [P] [US2] 新增 `fetchUpWebHead(mid)` 公开静态方法（委托既有 `fetchUpVideosViaWeb(mid, 1)`，失败抛错由调用方降级）`entry/src/main/ets/service/BiliService.ets`
- [X] T008 [US2] `refreshSubscription` UP 分支双链合并：APP 主干 + Web 头页补稠，bvid 去重、pubdate 降序落盘；Web 失败仅记日志退化为 APP 结果 `entry/src/main/ets/service/SubscriptionStore.ets`
- [X] T009 [US2] `loadOlder` 追加去重后对 episodes 整体按 pubdate 降序重排再渲染 `entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 5: User Story 3 - 时间显示往年带年份 (Priority: P1)

**Goal**: 源页列表时间三态：当天 HH:mm / 当年 M-d HH:mm / 往年 YYYY-M-d HH:mm

**Independent Test**: 虚拟机查看含 2025 年及更早视频的列表，往年条目显示完整年份

- [X] T010 [US3] `formatDate` 三态改造（跨年时输出 YYYY-M-d HH:mm；全仓仅此一处调用，就地改）`entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 6: User Story 4 - 首页徽标可靠清除 (Priority: P1)

**Goal**: 打开 app→见徽标→立即点进源页后返回，徽标确定消除，不再被后台刷新回写覆盖

**Independent Test**: 虚拟机冷启动→立即点进有新内容的订阅→返回首页，徽标消失；等待超过后台刷新窗口再验证一次

- [X] T011 [US4] `silentRefresh` 每订阅回调：先 `SubscriptionStore.loadSubscriptions()` 重载拿最新 lastSeenAt，过滤 subExists 后保存，不再直接保存内存 `this.subs` 陈旧副本 `entry/src/main/ets/pages/HomePage.ets`
- [X] T012 [US4] `addSubscription` 刷新回调同理：重载后仅以刷新完成的订阅对象替换同 id 项再保存 `entry/src/main/ets/pages/HomePage.ets`

---

## Phase 7: User Story 5 - 日志页整页重写 (Priority: P2)

**Goal**: 日志查询升级为 HarmonyOS 风格独立整页（单标题、内容到底），LogSheet 退役

**Independent Test**: 虚拟机设置页→日志查询→单行大标题、列表满页、导出/清空/空态可用、底部为 miniPlayer 避让而非留空

- [X] T013 [P] [US5] 重写 `LogPage` 为独立整页：大标题+操作按钮、LazyForEach 数据源迁入、导出（DocumentViewPicker）原样迁移、清空（仅内存）、空态、miniPlayerVisible 底部避让 `entry/src/main/ets/pages/LogPage.ets`
- [X] T014 [US5] 删除 `entry/src/main/ets/component/LogSheet.ets` 并 grep 清理全部残留引用（LogDataSource 等随迁成员）

---

## Phase 8: User Story 7 - 已播图标绿色圆圈对号 (Priority: P2)

**Goal**: 已播标记由文字「✓ 已播」恢复为圆圈对号图标，颜色 success_green

**Independent Test**: 虚拟机播放过的视频列表项显示绿色圆圈对号图标

- [X] T015 [US7] 已播标记改 `SymbolGlyph($r('sys.symbol.checkmark_circle'))` + `$r('app.color.success_green')`（sysResource 已核实存在）`entry/src/main/ets/pages/SourcePage.ets`

---

## Phase 9: User Story 8 - 设置页整页重写 (Priority: P2)

**Goal**: 设置页弃用原项目风格，整页重写为 HarmonyOS 系统风格（大标题+分组卡片），功能全保留

**Independent Test**: 虚拟机逐项走查：登录（扫码/Cookie）、退出、六个播放设置开关、音质 sheet、外观、历史入口+清空、日志入口、关于面板、深浅色背景一致、过冲提示顶/底

- [X] T016 [US8] 重写页面骨架：NavDestination 根 + 大标题 + 分组卡片结构（SettingsGroup/SettingsRow）+ 根容器背景统一 `page_background` 延伸安全区 + 滚动容器 Stack+EdgeHint 顶/底（复用源页 onWillScroll/onScrollStop 模式）`entry/src/main/ets/pages/SettingsPage.ets`
- [X] T017 [US8] 账号功能区迁移：扫码登录、手动粘贴 Cookie（SESSDATA+bili_jct）、退出登录 AlertDialog `entry/src/main/ets/pages/SettingsPage.ets`
- [X] T018 [US8] 播放设置功能区迁移：启动自动播放、后台打断续播、默认音质（Wi-Fi/移动网络入口→音质 sheet）、无图模式、仅 Wi-Fi 播放 `entry/src/main/ets/pages/SettingsPage.ets`
- [X] T019 [US8] 外观（主题/强调色）、播放历史（入口行+清空 AlertDialog+62% 面板整体保留）、日志查询入口、关于面板迁移 `entry/src/main/ets/pages/SettingsPage.ets`
- [X] T020 [US8] 路由契约核对：`router_map.json` 键 `settingsPage`/`logPage` 不变，`pushPathByName('settingsPage', 'playHistory'|'about')` 直开面板 param 语义保留 `entry/src/main/resources/base/profile/router_map.json`

---

## Phase 10: User Story 6 - 播放历史面板修复 (Priority: P2)

**Goal**: 历史面板移除下拉关闭（只留蒙层点击/返回）、补顶部到顶提醒、背景与新设置页一致

**Independent Test**: 虚拟机设置页→播放历史：面板内下拉不关闭、点蒙层/返回键关闭、fling 到顶出现顶部提醒、面板背景无色差

**⚠️ 依赖**: 须在 T016-T020（US8 重写）完成后在新结构上实施

- [X] T021 [US6] 历史 `bindSheet` 增加 `onWillDismiss`：`reason === DismissReason.SLIDE_DOWN` 不调用 dismiss（拦截），TOUCH_OUTSIDE/PRESS_BACK/CLOSE_BUTTON 放行 `entry/src/main/ets/pages/SettingsPage.ets`
- [X] T022 [US6] 历史面板滚动容器补顶部 EdgeHint（现状仅底部）+ 面板背景 token 与设置页统一 `entry/src/main/ets/pages/SettingsPage.ets`

---

## Phase 11: User Story 9 - 首页过冲提醒 (Priority: P2)

**Goal**: 首页订阅列表过冲时显示顶/底提示，列表行视觉与交互零改动

**Independent Test**: 虚拟机首页 fling 到顶/底出现提示，松手回弹后消失，行布局与 R6 一致

- [X] T023 [US9] 订阅列表外套 Stack + EdgeHint 顶/底 + onWillScroll/onScrollStop 过冲判定 `entry/src/main/ets/pages/HomePage.ets`

---

## Phase 12: Polish & Cross-Cutting Concerns

- [X] T024 死代码与残留清理：grep 全仓 LogSheet/旧样式残留引用、未用 import，确认 Constants.ets 无新增重复键 `entry/src/main/ets/`

---

## Phase 13: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建、部署到 API 24 虚拟机并逐用户故事 UI 实测

- [X] T025 运行 `arkts_check` 预检全部改动 `.ets` 文件，随后 `devecocli build` 并修复编译错误（迭代修复→重建直至成功）
- [X] T026 部署到 API 24 平板虚拟机（`devecocli run --skip-build`，目标 127.0.0.1:5555）
- [X] T027 逐用户故事 UI 验证（US1-US9，每故事最多 3 次验证尝试：初验+2 轮修复复验；全部通过后终验一轮不再修复）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup；阻塞 US5/US8
- **User Stories (Phase 3-11)**: 服务层（US2）与页面层按文件串行；US6 必须在 US8 完成后实施
- **Polish (Phase 12)**: 依赖全部用户故事完成
- **Verification (Phase 13)**: 依赖 Polish 完成

### 文件串行约束（同文件任务必须按序执行）

- `SourcePage.ets`: T004→T005→T006→T009→T010→T015
- `HomePage.ets`: T011→T012→T023
- `SettingsPage.ets`: T016→T017→T018→T019→T020→T021→T022
- `BiliService.ets`→`SubscriptionStore.ets`: T007→T008（T008 依赖 T007）
- `LogPage.ets`→`LogSheet.ets`: T013→T014

### Parallel Opportunities

- T002/T003（两个新组件文件）可并行
- T007（BiliService）、T011（HomePage）、T013（LogPage）互相不同文件，可与 SourcePage 线并行

---

## Parallel Example

```text
并行批次 A（Foundational）:
Task: "T002 SettingsGroup 组件 entry/src/main/ets/component/SettingsGroup.ets"
Task: "T003 SettingsRow 组件 entry/src/main/ets/component/SettingsRow.ets"

并行批次 B（不同文件的独立起点）:
Task: "T007 [US2] fetchUpWebHead entry/src/main/ets/service/BiliService.ets"
Task: "T011 [US4] silentRefresh 回调修复 entry/src/main/ets/pages/HomePage.ets"
Task: "T013 [US5] LogPage 重写 entry/src/main/ets/pages/LogPage.ets"
```

---

## Implementation Strategy

### MVP First（P1 缺陷修复先行）

1. T001 Setup 基线核对
2. T002-T003 共用组件
3. T004-T012 四个 P1 故事（触底/完整时序/年份/徽标）→ 可独立验证的 MVP
4. T013-T023 P2 故事（日志页→图标→设置页→历史面板→首页）
5. T024 清理 → T025-T027 验证

### Incremental Delivery

每个用户故事完成后即到达独立可验证检查点；US8→US6 有硬依赖（重写后在新结构上修面板），其余故事按文件串行约束依次交付。

---

## Notes

- [P] 任务 = 不同文件、无未完成依赖
- [Story] 标签映射 spec.md 用户故事，保证可追溯
- 零测试任务（无测试套件）；验证在 Phase 13 虚拟机实测
- 提交策略：沿用仓库惯例，本轮改动完成后由用户决定提交时机（R6 改动亦未提交）
- ArkTS 严格模式约束适用全部任务：禁 any/unknown/as 断言、解构、对象字面量类型；代码零注释（`ponytail:` 除外）；API 26 接口须 `[API24-COMPAT]` 守卫（本轮 onWillDismiss 为 API 12+，无需守卫）
