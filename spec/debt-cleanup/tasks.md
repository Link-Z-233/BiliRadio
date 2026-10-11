# Tasks: 欠账集中清理轮（debt-cleanup）

**Input**: Design documents from `spec/debt-cleanup/`
**Prerequisites**: plan.md（设计决策 D1-D7）、spec.md（用户故事 US1-US9）

> **轮次性质**：合并清理轮——三项代码改动（删无图/首页左滑/识别修复）+ 全部在册验证欠账一次清偿。验证全在模拟器执行，过即销项，测完关模拟器（用户既定指令）。

## Format

任务格式：`- [ ] [TaskID] [P?] [Story?] Description with exact file path`

- `[P]`：可并行（不同文件、无未完成依赖）
- `[Story]`：用户故事标签（`[US1]`~`[US9]`），仅用户故事阶段任务携带
- 每条任务以确切文件路径结尾

## Path Conventions

- 源码根：`entry/src/main/ets/`（pages/ 页面、service/ 服务、component/ 组件）
- 工程配置：仓库根 `build-profile.json5`、`AppScope/app.json5`
- 文档：仓库根 `PROJECT_NOTES.md`；规划文档 `spec/debt-cleanup/`
- 他轮任务清单（销项勾选对象）：`spec/queue-redesign/tasks.md`、`spec/engineering-refactor/tasks.md`

**全局执行约束（实施轮适用）**：

- 遵循 AGENTS.md：`Constants` 唯一真相源、禁 any/unknown/as、代码零注释（`ponytail:` 除外）
- 每个用户故事完成即 `arkts_check`（该故事涉及 .ets）+ `devecocli build` 通过后再进入下一故事
- 删除类任务先核对调用方再删：`refreshMediaSessionMetadata` 唯一调用方为设置页开关回调（已核实）；`refreshUi()` 方法与 MediaSession 空封面守卫**保留不删**
- 验证阶段逐故事顺序执行（同一模拟器会话，避免状态污染）；每故事最多 1 初验 + 2 修复复验
- 全部验证完成后才执行销项（T024）与关模拟器（T025）

---

## Phase 1: Setup（前置核查）

**Purpose**: 确认基线绿色与模拟器就绪

- [X] T001 执行一次全量构建确认当前基线绿色（`devecocli build`）
- [X] T002 [P] 确认模拟器可用（`devecocli devices` / 模拟器管理，Mate 90 Pro 实例）

**Checkpoint**: 基线绿色 + 模拟器就绪

---

## Phase 2: Foundational（阻塞前置）

无——三项改动故事（US1/US2/US3）相互独立、不同文件、无共享前置，直接进入用户故事。

---

## Phase 3: User Story 1 - 删除无图模式开关 (Priority: P1) 🎯 MVP

**Goal**: 无图模式开关全链移除（6 文件 8 处），尺寸分档与网络态降档零回退

**Independent Test**: 设置页开关缺席 + 封面正常渲染 + 全局检索 `KEY_DATA_SAVER`/`dataSaver` 零命中

### Implementation for User Story 1

- [X] T003 [P] [US1] 删键定义：`entry/src/main/ets/service/Constants.ets` L33 `KEY_DATA_SAVER`
- [X] T004 [P] [US1] 删开关行与状态：`entry/src/main/ets/pages/SettingsPage.ets` L172 `dataSaver` 状态声明、L1310-1323「无图模式」SettingsRow 整块（`refreshUi()`/`refreshMediaSessionMetadata()` 调用随行移除，方法本体保留）
- [X] T005 [P] [US1] 删播控重发方法与读取点：`entry/src/main/ets/service/PlayerController.ets` L186-195 `refreshMediaSessionMetadata()` 整方法、L349-351 与 L694-697 的 `dataSaver ? '' : item.cover` 改为直传 `item.cover`
- [X] T006 [P] [US1] 删播放层置空分支：`entry/src/main/ets/pages/PlayerOverlay.ets` L288/294/296——`trackCover` 改为 `CoverUrl.sized(item.cover, coverW, coverH)`、`ownerFace` 改为直传 `item.ownerFace`；**L290-292 网络态分档（wifi 取档）保留不动**
- [X] T007 [P] [US1] 删迷你条分支：`entry/src/main/ets/component/MiniPlayer.ets` L38-40 `dataSaver` 读取与封面置空条件
- [X] T008 [P] [US1] 删队列分支：`entry/src/main/ets/component/QueueSheet.ets` L96 `dataSaverOn` 状态、L171 读取、L512 渲染分支（`CoverThumb` 直传 `item.cover`）
- [X] T009 [US1] 残留检索：全局检索 `KEY_DATA_SAVER`/`dataSaver`/「无图模式」注释零命中（依赖 T003-T008）

**Checkpoint**: 无图模式全链零残留，构建绿色

---

## Phase 4: User Story 2 - 首页订阅列表左滑删除（KI-3 收尾） (Priority: P1)

**Goal**: 首页订阅行左滑露「删除」按钮、点击退订，KI-3 三处清单全部完成

**Independent Test**: 首页左滑任一订阅行露删除按钮，点击后该订阅从列表消失且不再出现

### Implementation for User Story 2

- [X] T010 [US2] 左滑删除挂载：`entry/src/main/ets/pages/HomePage.ets`——新增 `@Builder subDeleteAction(row: SubRow)`（红色删除按钮，样式逐字段对齐 `SettingsPage.historyDeleteAction`：`danger_red` 背景、`fg_on_dark` 文字、`height('100%')`、左右 padding 18、`borderRadius(0)`，点击调既有 `removeSub(row)`）；`LazyForEach` 内 `ListItem` 挂 `.swipeAction({ end: this.subDeleteAction(row) })`；键值生成器与长按菜单（`bindContextMenu`）不动

**Checkpoint**: 首页左滑删除可用，KI-3 实现侧闭环

---

## Phase 5: User Story 3 - 链接识别修复 B4+B5（KI-7 部分） (Priority: P2)

**Goal**: 复合 URL 不再被 BV 全文扫描遮蔽；fav 判定收紧至 path 级特征，不再误判

**Independent Test**: 五组识别输入（复合链接/纯 BV/合法收藏夹/含 fav 字样非收藏夹/既有输入回归）分类全部正确

### Implementation for User Story 3

- [X] T011 [US3] B4 调序：`entry/src/main/ets/service/LinkResolver.ets` `recognizeInput` 内全文 BV 扫描（`BV[0-9A-Za-z]{10}`）从首位移至全部 URL 形态规则之后、裸数字规则之前（新序：av 纯文本 → av URL → lists → seriesdetail → collectiondetail → fav → space 移动端 → space 桌面 → BV 全文 → 裸数字）
- [X] T012 [US3] B5 收紧：`entry/src/main/ets/service/LinkResolver.ets` `recognizeInput` fav 规则由「`(?:fid|media_id)=(\d+)` 且文本含 fav/collection/favlist」改为「URL path 含 `favlist` 或 `medialist` 特征，且含 `fid=`/`media_id=` 参数」；收紧前按真实收藏夹 URL 形态核对（网页版 `space.bilibili.com/{mid}/favlist?fid=`、移动端 `m.bilibili.com/space/{mid}/favlist`、播放页 `medialist/play`），合法形态不得漏判（依赖 T011，同函数区域顺序修改）

**Checkpoint**: B4/B5 修复，既有识别零回归

---

## Phase 6: Polish（跨故事文档登记）

**Purpose**: 删除链路登记先行（销项待验证后）

- [X] T013 [P] 删除登记：`PROJECT_NOTES.md`「已移除与禁用功能」新增无图模式 REM 条目——移除内容（开关全链 6 文件清单）、原因（边际收益可忽略 + 覆盖不全不一致，2026-10-11 用户决策）、恢复线索（git 定位删除提交，恢复须重接设置页开关与 6 处生效分支）

---

## Phase 7: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建、部署模拟器、逐故事 UI 验证（本轮新改动 US1-US3 + 欠账验收 US4-US8），全部通过后销项收尾

- [X] T014 构建验证：对 T003-T012 涉及的全部 `.ets` 执行 `arkts_check` 零诊断，`devecocli build` 通过（迭代修复至绿）
- [X] T015 部署模拟器：`devecocli run --skip-build` 部署到 Mate 90 Pro 模拟器（销 queue-redesign T031 部署欠账；依赖 T014、T002）
- [ ] T016 UI 验证（US1）：**部分完成**（开关缺席+代码零残留已确认；播放层大封面自动化存疑，转真机复测清单 §4 US1-2）——设置页「省流」分组无「无图模式」开关行；缩略图/播放层大封面（网络态分档）/系统播控封面正常渲染；对照 spec US1 验收场景逐条
- [X] T017 UI 验证（US2）：首页左滑露删除按钮、点击退订（列表即时移除、重进不复活）、未点击滚走复位、点击进源页与新集徽标无回归；对照 spec US2 验收场景
- [X] T018 UI 验证（US3）：经添加订阅面板逐组验证识别——含 BV 参数复合链接判合集/收藏夹、纯 BV 文本判视频、合法收藏夹 URL 判收藏夹、含 fav 字样非收藏夹文本不误判、短链/av/UID 回归；对照 spec US3 验收场景（8 场景全过）
- [X] T019 UI 验证（US4 队列全量）：R9 US1-4（底部弹出/近实底/双向过冲/时长未知无 00:00）+ T032 US2（左滑删除/手势共存）+ T032 US4（清除已播两态/toast/确认框）+ T032 US6（追加不打断/toast 三型/常驻说明行）；对照 spec US4 验收场景 7 条逐条（销 R9 欠账；T032 的 US1/US5 按 R9 修订后行为覆盖、US7 版本号项过时关闭；verify_ui 3 次用尽后转 `devecocli ui` 手动验证全过）
- [ ] T020 UI 验证（US5 睡眠定时）：**部分完成**（倒计时归零/播完暂停/互斥/取消全过；切后台校准环境受限未验，转真机复测清单 §4 US5-2）——KI-6 全量——倒计时归零暂停、切后台节流后切回校准、播完暂停三步（停原条目/暂停/手动解除）、两模式互斥、触发不弹结束弹窗（T032 US3 一并覆盖）；对照 spec US5 验收场景 5 条
- [X] T021 UI 验证（US6 R10 三项）：设置页/日志页沉浸至小白条后方且末行可达、胶囊隐藏期间原区域触摸落到下层、日志页无大块空白、返回首页胶囊正常唤起浮层；对照 spec US6 验收场景 5 条（销 R10 欠账；五场景全过）
- [ ] T022 UI 验证（US7 降级衔接走查）：**SKIPPED——模拟器卡死中断**（刚定位订阅卡片坐标准备进源页时实例无响应）；且降级触发手段 devecocli 无对应命令（纯断网会同时杀死 Web 链）；转真机复测清单 §4 US7，T013/KI-9 欠账保留
- [ ] T023 UI 验证（US8 深浅色/主题色走查）：**未执行**（模拟器卡死）；转真机复测清单 §4 US8——7 页面（首页/设置页/源页/播放层/队列面板/添加面板/日志页）× 浅/深 × 默认/切换主题色逐页截图走查——对比度可读、无旧色残留、强调色全量生效；小问题记录在案，大问题暂停报告（对照 spec US8 验收场景 3 条）
- [ ] T024 收尾销项：**未执行——待用户真机复测反馈后按结果销项**（2026-10-11 用户决策：不再模拟器验证，改真机实测）；依验证结果执行——`PROJECT_NOTES.md` 销项（KI-3 关闭/KI-6 关闭并移除 `entry/src/main/ets/service/SleepTimerController.ets` 文件头 `[UNVERIFIED 2026-10]` 标注/KI-7 标记 B4/B5 已修复/KI-9 关闭/R9 与 R10 规划条目更新/「无图模式覆盖面扩展」欠账销项）；勾选 `spec/queue-redesign/tasks.md` T031/T032、`spec/engineering-refactor/tasks.md` T013（依赖 T016-T023 全部出结论、T013 登记）
- [ ] T025 关闭模拟器实例：**未执行**（模拟器已卡死，用户决定不再进行模拟器验证）

> **验证轮结论（2026-10-11）**：总状态 **INCOMPLETE**——T022/US7 验证即将开始时模拟器卡死，用户决策改为真机实测。已完成验证结果与 37 条真机复测清单见 `spec/debt-cleanup/verification-report.md`；未完成项（US1 播放层大封面/US5 切后台校准/US7 降级走查/US8 深浅色走查/T024 销项/T025 关机）在真机复测通过前不销项。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即可启（T001 基线构建为实施前置，T002 为部署前置）
- **Foundational (Phase 2)**: 无任务
- **User Stories (Phase 3-5)**: US1 依赖 T001；US2/US3 仅依赖 T001（基线绿）；三故事相互独立
- **Polish (Phase 6)**: 依赖 T003-T008 完成（登记内容引用删除清单），可与其余故事并行
- **Verification (Phase 7)**: 依赖全部代码任务（T003-T012）完成；部署依赖 T002
- **收尾 (T024/T025)**: 依赖 T016-T023 全部出结论与 T013

### User Story Dependencies

- **US1 (P1)**: 依赖 Setup；六文件删除任务（T003-T008）内部并行，T009 汇总
- **US2 (P1)**: 依赖 Setup；与 US1 零交叉（HomePage 独占）
- **US3 (P2)**: 依赖 Setup；与 US1/US2 零交叉（LinkResolver 独占）；T011→T012 内部顺序

### Within Each User Story

- 删除/修改前核对调用方（plan.md D1 已核实清单）
- 故事内任务完成 → `arkts_check` + `devecocli build` → Checkpoint 验证独立可测 → 下一故事

### Parallel Opportunities

- US1 的 T003-T008（6 个不同源文件）可全部并行
- US1 / US2 / US3 / Polish 四线可并行（文件无交叉）
- 验证阶段 T016-T023 必须顺序（同一模拟器会话状态）

---

## Parallel Example

```text
# US1 六文件删除并行启动：
Task: T003 [P] [US1] 删键定义（Constants.ets）
Task: T004 [P] [US1] 删开关行与状态（SettingsPage.ets）
Task: T005 [P] [US1] 删播控方法与读取点（PlayerController.ets）
Task: T006 [P] [US1] 删播放层分支（PlayerOverlay.ets）
Task: T007 [P] [US1] 删迷你条分支（MiniPlayer.ets）
Task: T008 [P] [US1] 删队列分支（QueueSheet.ets）

# 同时启动其余故事（文件无交叉）：
Task: T010 [US2] 左滑删除挂载（HomePage.ets）
Task: T011 [US3] B4 调序（LinkResolver.ets）
Task: T013 [P] REM 删除登记（PROJECT_NOTES.md）
```

## Implementation Strategy

### MVP First（最小可交付）

1. 完成 Setup（T001）
2. 完成 US1（T003-T009）+ 构建（T014 前置预检）——删无图模式独立交付
3. **STOP and VALIDATE**：检索零残留 + 构建绿

### Incremental Delivery

1. Setup → US1（MVP）→ US2 → US3 → Polish，每故事独立构建验证
2. 验证阶段（T014-T023）：构建 → 部署 → 逐故事顺序 UI 验证
3. 收尾（T024-T025）：销项 → 关模拟器

### 本轮执行策略（用户已批准全范围）

- **实施轮**：T001-T014 一次推进（四线并行 + 逐故事构建），不停顿
- **验证轮**：T015-T025 顺序推进（单模拟器会话），测完即关
- 中间无 Review Gate 停顿；无人值守规则适用（小问题记录在案、大问题暂停报告、争议停下交用户决策）

---

## Notes

- **总任务数**：25（Setup 2 / US1 7 / US2 1 / US3 2 / Polish 1 / 验证 12）
- **验证任务覆盖映射**：T016-T018=本轮新改动（US1/US2/US3）；T019=R9 全量+queue-redesign T032 US2/US4/US6+T031；T020=KI-6+T032 US3；T021=R10；T022=engineering-refactor T013/KI-9；T023=令牌化走查欠账
- **[P] 标注基准**：不同文件且无未完成依赖
- **验证上限**：每故事最多 1 初验 + 2 修复复验（3 次尝试），仍失败暂停报告；构建验证修复循环同目标最多 3 次
- **销项诚实原则**：环境受限（如降级无法触发）时保留欠账登记，不假 PASS
- **提交策略**：实施轮与验证轮各自独立提交（沿用项目「每批次完成即构建验证、批次独立提交」惯例）
