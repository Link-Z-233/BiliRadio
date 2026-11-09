# Tasks: v0.7-part4-special-marks（特殊视频标记）

**Input**: Design documents from `spec/v0.7-part4-special-marks/`
**Prerequisites**: plan.md（已就绪）、spec.md（已就绪）

**Tests**: 无测试套件，不生成测试任务；自检面 = 解析命中 debug 日志 + 真机日志验证（plan「自检与验证口径」节）

**Organization**: 按用户故事分组（US1 门禁码修复 → US2 源页角标 → US3 互动拦截 → US4 队列/历史角标），每个故事独立可测可交付。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事
- 描述含精确文件路径

## Path Conventions

- 单模块既有项目，源码根：`entry/src/main/ets/`
- 分层：`model/`（数据模型）、`service/`（服务/常量）、`pages/`（页面）、`component/`（复用组件）
- 本轮零新增文件，全部为既有文件增量修改

## Phase 1: Setup

既有单模块项目，无初始化任务。

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 全部故事依赖的模型字段与文案常量，必须先完成

- [X] T001 BiliVideo 新增 `isInteractive`/`isPaid`/`isVipExclusive` 三个 `@Trace` 布尔字段，并补齐 `toRecord`/`fromRecord` 序列化（字段缺失置 false，对齐既有 `isUpowerExclusive` 写法）`entry/src/main/ets/model/BiliVideo.ets`
- [X] T002 [P] Constants 新增门禁与拦截 toast 文案常量：充电跳过、付费跳过、互动拦截三条（命名对齐既有 `TOAST_*` 系列；`enqueueToast` 的互动文案归 US3 任务接）`entry/src/main/ets/service/Constants.ets`

**Checkpoint**: 模型字段与文案就绪，各故事可开工

---

## Phase 3: User Story 1 - 播放门禁码明确分类与直报 (Priority: P1) 🎯 MVP

**Goal**: 87007/87008（充电）/87005（付费）从瞬时失败重分类为确定性异常，toast 直报原因，标异常并跳下一条
**Independent Test**: 真机播放充电/付费稿件（未充电/未购买账号），观察 toast 直报原因、异常标记、自动跳过，无停等重试

- [X] T003 [US1] `PlayErrorKind` 枚举新增 `UPOWER`/`PAID` 两档；`classifyPlayError` 在 -404/-104 匹配后、风控判断前新增精确匹配：`Bili API error 87007`/`87008` → UPOWER、`87005` → PAID；其余分支（含 OTHER 兜底）零改动 `entry/src/main/ets/service/PlayerController.ets`
- [X] T004 [US1] `playIndex` 取流失败 catch 的确定性分支从两档扩为四档：INVALID 标失效、VIP/UPOWER/PAID 标异常（`markAnomaly`），toast 各取专属文案（UPOWER/PAID 取 T002 新常量），跳下一条/队列尾停逻辑对齐既有 VIP 分支 `entry/src/main/ets/service/PlayerController.ets`

**Checkpoint**: US1 独立可用——门禁稿播放失败直报原因并跳过，时长判定与兜底行为不变

---

## Phase 4: User Story 2 - 源页列表四类文字角标 (Priority: P1)

**Goal**: 源页列表行显示「充电」「互动」「付费」「大会员」文字角标，有数据就标、无数据不标、零新增请求
**Independent Test**: 刷新含充电稿订阅（小约翰可汗），源页对应行显示「充电」角标；普通稿件无角标

- [X] T005 [US2] `parseVlistRecords` 恢复既有注释的充电/付费解析（is_charging_arc/elec_arc_type/ugc_pay/is_ugcpay 族），并新增：`badges[*].text` 含「充电专属」（充电，APP cursor 链唯一信号）、`is_steins`/`is_steins_gate`/`attribute` bit29（互动）、`is_pay`（付费）、`is_pugv`/`is_pgc`（大会员，仅 APP cursor 链）；判定只认明确真值，字段缺失跳过；命中时打 debug 日志（bvid + 命中标志）`entry/src/main/ets/service/BiliService.ets`
- [X] T006 [US2] `parseArchiveRecords` 新增 `interactive_video`（互动）、`ugc_pay`>0（付费）解析，充电/大会员无字段不标（天然盲区）`entry/src/main/ets/service/BiliService.ets`
- [X] T007 [US2] `parseVideoDetail`（APP view 详情链）新增 `charging_pay`/`charging_plus`（充电）、`interaction` 对象存在（互动）解析——详情链是跨源点播的互动拦截数据来源 `entry/src/main/ets/service/BiliService.ets`
- [X] T008 [US2] `SourcePage` 列表行恢复被注释的充电角标渲染，并按同构样式新增「互动」「付费」「大会员」文字角标：多标志并排互不覆盖，样式对齐既有 NEW/角标令牌体系（充电沿用 `gold_accent`，其余色值从既有 palette 取，需新增则登记 color 资源），角标间 `TOKEN_SPACE_XS` 间距 `entry/src/main/ets/pages/SourcePage.ets`

**Checkpoint**: US2 独立可用——源页角标随刷新数据呈现

---

## Phase 5: User Story 3 - 互动视频入队拦截 (Priority: P1)

**Goal**: 点播/入队入口无条件拦截互动视频并提示，其余三类不拦
**Independent Test**: 对互动视频点播/入队 → 拦截 + toast「互动视频不支持播放」；对充电稿点播 → 正常入队

- [X] T009 [US3] `EnqueueResult` 枚举新增 `INTERACTIVE`；`enqueueToast` 映射该值到 T002 的互动拦截文案 `entry/src/main/ets/service/PlayerController.ets`
- [X] T010 [US3] `loadPlaylistAndPlay` 去重循环内同步过滤 `isInteractive === true` 条目：全部为互动 → 返回 `INTERACTIVE`、歌单零改动；混合场景过滤后正常入队，`statusMsg` 附「已跳过 N 个互动视频」；调用方（SourcePage/HomePage/AddSubscriptionSheet）经 `enqueueToast` 自然消费新值，零改动 `entry/src/main/ets/service/PlayerController.ets`

**Checkpoint**: US3 独立可用——全入口（点播/入队/分享导入/订阅页添加）拦截生效

---

## Phase 6: User Story 4 - 播放队列/历史图标角标 (Priority: P2)

**Goal**: 队列与历史行用图标（不带文字）显示四类标记，与源页共用标志数据
**Independent Test**: 含特殊稿件的队列/历史列表渲染后行上出现对应图标角标；无标志稿件无图标

- [X] T011 [US4] 先在 `sysResource.js`（本机 SDK 路径见 AGENTS/paths 规则）确认候选符号存在（充电 `bolt` 类/付费 `creditcard` 类/大会员 `crown` 类/互动取现有符号），不虚构符号名；`QueueSheet` 两处行渲染点（分P 行 + 条目组行，既有 invalid/anomaly 标记旁）追加四类 `SymbolGlyph` 图标角标，选中模式下隐藏（对齐既有标记行为）`entry/src/main/ets/component/QueueSheet.ets`
- [X] T012 [P] [US4] `HistorySheet` 行渲染点（既有 invalid/anomaly 标记旁）追加同套四类图标角标，符号与 QueueSheet 取齐 `entry/src/main/ets/component/HistorySheet.ets`

**Checkpoint**: US4 独立可用——队列/历史图标角标呈现

---

## Phase 7: Verification

<!-- verification_scope: build-only -->

**Purpose**: 构建验证通过即收尾（默认停到真机前，不执行真机部署/运行/UI 验证）

- [X] T013 对本轮全部改动的 `.ets` 文件执行 `devecocli check arkts`，随后 `devecocli build`，编译错误修复后重建直至通过（构建即收尾停点，真机部署/验证不在本轮范围）
- [X] T014 汇总真机自查事项输出到轮次总结（充电角标渲染、门禁 toast、互动拦截、图标角标、刷新请求数持平），验证结论待用户真机回填 BILI_NOTES §3

---

## Phase 8: 真机反馈修订（R2 批次）

**Input**: 真机反馈排查定稿（spec Overview 修订段 ①-⑥）；T001-T014 已实施勾选，本批为既有实现就地修正与补全，零新增文件
**Independent Test**: 各任务独立可构建验证（构建即收尾，真机自查清单见 Verification）

- [X] T015 [US2] `parseVideoFromViewData`（web view 详情链）解析修复（修订①）：补 `rights.pay`>0 → isVipExclusive（判定加非充电互斥防双标）、`rights.ugc_pay`>0 → isPaid、`rights.is_stein_gate` → isInteractive；充电字段位置修正——顶层 `is_upower_exclusive` 为准、`rights` 同名兜底；解析命中日志按四类标志分类输出（bvid + 命中标志 + 链名）`entry/src/main/ets/service/BiliService.ets`
- [X] T016 [US2] 课程归类修正（修订②）：`parseVlistRecords` 中 `is_pugv` 从 isVipExclusive 判定挪入 isPaid 判定（B 站课堂课程是付费购买内容）`entry/src/main/ets/service/BiliService.ets`
- [X] T017 [US2] 源页角标重做为封面右上角 pill（修订③）：行尾文字角标渲染迁移至封面 Stack 右上角——类型色底 pill（充电⚡/互动岔路/付费卡符号+文字；大会员无符号、加粗大字即标识），pill 底色为类型色低饱和/半透明变体并新登记 color 资源（充电金/互动紫/付费橙/大会员粉系），多标志并排，多选模式下隐藏 `entry/src/main/ets/pages/SourcePage.ets` + `entry/src/main/resources/base/element/color.json`
- [X] T018 [P] [US4] 队列/历史标记重定位（修订④）：行尾图标挪标题前缀（充电/互动/付费图标、大会员「大」单字 `primary_color`，类型色区分），与行尾 ✓/✗/! 状态标分位，选中模式下隐藏保持（对齐既有标记行为）；QueueSheet 两处渲染点（分P 行 + 条目组行）与 HistorySheet 行渲染点同步迁移 `entry/src/main/ets/component/QueueSheet.ets` + `entry/src/main/ets/component/HistorySheet.ets`
- [X] T019 [US2/US3] 收藏夹批量入队详情链补全（修订⑥）：Constants 新增并发上限令牌（`TOKEN_*` 系列，保守初值 3）；仅 fav 源多选确认入队时并行调 `fetchVideoDetail`（有界并发），详情成功按详情条目入队（标志/互动拦截/多P 语义与单击一致），单条失败降级用原列表行入队（无标志、互动不拦）；UP 源/合集批量不拉详情（行自带标志，互动保留过滤）`entry/src/main/ets/service/Constants.ets` + `entry/src/main/ets/pages/SourcePage.ets`

**Checkpoint**: 修订批次完成——入队标志保真、fav 批量覆盖、角标形态定稿

---

## Phase 9: Verification (R2)

<!-- verification_scope: build-only -->

**Purpose**: 修订批次构建验证通过即收尾（默认停到真机前，不执行真机部署/运行/UI 验证）

- [X] T020 对 R2 批次全部改动 `.ets` 文件（BiliService/SourcePage/QueueSheet/HistorySheet/Constants）执行 `devecocli check arkts`，随后 `devecocli build`，编译错误修复后重建直至通过（构建即收尾停点）
- [X] T021 汇总 R2 真机自查事项输出到轮次总结（封面 pill 渲染、队列/历史标题前缀与「大」字、fav 批量入队标志与拦截、入队保真、降级行为），验证结论待用户真机回填 BILI_NOTES §3

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational（T001/T002）**: 阻塞全部故事——T001 是所有标志读写的载体，T002 是 US1/US3 的文案依赖
- **US1（T003→T004）**: 仅依赖 T002；文件内顺序执行
- **US2（T005→T006→T007→T008）**: T005-T007 同文件（BiliService.ets）顺序执行；T008 依赖 T001 + T005（角标数据就绪）
- **US3（T009→T010）**: 依赖 T001/T002/T007（详情链互动标志是跨源拦截的数据来源）；文件内顺序执行
- **US4（T011→T012）**: 依赖 T001；T011 先定符号集，T012 取齐（不同文件可并行，但符号集须先定）
- **Verification（T013→T014）**: 依赖全部实施任务
- **R2（T015→T016→T017→T019）**: T015/T016 同文件（BiliService.ets）顺序执行；T017/T019 同文件（SourcePage.ets）顺序执行；T018 不同文件可并行
- **Verification R2（T020→T021）**: 依赖 R2 全部任务

### Parallel Opportunities

| Phase | Tasks | Required Files | Execution Notes |
|-------|-------|----------------|-----------------|
| Foundational | T001 ∥ T002 | BiliVideo.ets ∥ Constants.ets | 不同文件，可并行 |
| US1 ∥ US2 头部 | T003/T004 ∥ T005 | PlayerController.ets ∥ BiliService.ets | 不同文件，故事间可并行 |
| US4 | T011 → T012 | QueueSheet.ets → HistorySheet.ets | 符号集先定再并行取齐 |

### MVP Scope

US1 单独交付即 MVP：门禁码修复独立可测，不依赖任何角标/拦截实现。

---

## Parallel Example

```text
# Foundational 并行（不同文件）：
Task: T001 BiliVideo 字段扩展 (model/BiliVideo.ets)
Task: T002 Constants 文案常量 (service/Constants.ets)

# 故事间并行（不同文件，Foundational 完成后）：
Task: T003/T004 US1 门禁分类 (service/PlayerController.ets)
Task: T005-T007 US2 解析 (service/BiliService.ets)

# US4 符号定稿后并行（不同文件）：
Task: T011 QueueSheet 图标角标 (component/QueueSheet.ets)
Task: T012 HistorySheet 图标角标 (component/HistorySheet.ets)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. 完成 Foundational（T001/T002）
2. 完成 US1（T003/T004）
3. **STOP and VALIDATE**: 真机播放充电稿验证门禁直报（独立可测）
4. 构建（T013）收尾

### Incremental Delivery

1. Foundational → 基础就绪
2. +US1 → 门禁修复可交付（MVP）
3. +US2 → 源页角标可交付
4. +US3 → 互动拦截可交付
5. +US4 → 队列/历史角标可交付
6. Verification（T013/T014）构建收尾 + 真机自查清单输出

---

## Notes

- 同文件任务顺序执行（T003→T004、T005→T006→T007、T009→T010），不并行
- 充电判定「充电专属」文案精确匹配为有意设计（改文案→漏标不误标），勿放宽为模糊匹配
- 图标引用前必须确认 `sysResource.js` 存在对应符号（paths.md 规则）
- 代码零注释（`ponytail:` 除外）；色值/数值令牌化，禁裸硬编码
