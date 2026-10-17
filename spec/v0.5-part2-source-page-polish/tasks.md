# Tasks: 订阅详情页布局调整轮（7 项 + 追加剧集行等高）+ biliAPI 探索文档

**Input**: Design documents from `spec/v0.5-part2-source-page-polish/`  
**Prerequisites**: plan.md（required）、spec.md（required）

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1-US6，映射 spec.md）
- 所有路径相对仓库根

## Path Conventions

- 单项目仓库：`entry/src/main/ets/` 为源码根，`spec/` 为 SDD 工件根
- 本轮新增交付物：仓库根 `BILI_API.md`
- 代码路径均相对仓库根书写

---

## Phase 1: Setup

- [X] T001 建立根目录文档骨架 `BILI_API.md`（仅标题与三段占位：§1 本项目探索汇总 / §2 biliRelay 迁移 / §3 新增实测），本轮后续任务向三段填充
- [X] T002 [P] 注释旧目录名同步：`entry/src/main/ets/service/Constants.ets`、`entry/src/main/ets/component/CoverThumb.ets` 中 `v0.5-source-page-redesign` → `v0.5-part1-source-page-redesign`
- [X] T003 [P] 注释旧目录名同步：`entry/src/main/ets/pages/SettingsPage.ets` 中 `v0.5-play-history-sync` → `v0.5-part1-play-history-sync`

---

## Phase 2: Foundational（阻塞前置）

- [X] T004 `Constants` 新增 `SOURCE_HEADER_H = 56` 令牌（页头等高基准，收敛现有 56 裸数字），落在 `entry/src/main/ets/service/Constants.ets`
- [X] T005 `BiliVideo` 新增 `isUpowerExclusive: boolean = false` 字段（`@Trace`），`toRecord`/`fromRecord` 同步增 `'isUpowerExclusive'` 键（`fromRecord` 缺省 false 兼容旧缓存），落在 `entry/src/main/ets/model/BiliVideo.ets`

---

## Phase 3: User Story 1 - 顶栏收纳与播放全部移除 (Priority: P1) 🎯 MVP

**Goal**: 顶栏=返回+标题+···；刷新/退订进下拉菜单；去除播放全部
**Independent Test**: 打开任一订阅详情页核对顶栏结构与菜单行为；「播放全部」消失

- [X] T006 [US1] `SourcePage` 移除「播放全部」按钮及其 `playAll()` 死代码（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T007 [US1] `NavDestination` 挂载 `.menus(CustomBuilder)`：··· 图标 + `bindMenu` 系统下拉菜单（「刷新」「取消订阅」两项），`refreshing` 为真时锚点渲染 `LoadingProgress`；页头原刷新/删除图标移除；菜单内刷新走既有 `refreshSource()`、取消订阅走既有 `unsubscribe()` 二次确认流程（`entry/src/main/ets/pages/SourcePage.ets`）

**Checkpoint**: 顶栏三元素齐备，刷新/退订行为与旧入口一致，页面无播放全部

---

## Phase 4: User Story 2 - 多选批量加入队列 (Priority: P1)

**Goal**: 页头多选按钮 → 行内勾选 + 底部操作条 → 批量入队
**Independent Test**: 进入多选、勾选/全选、加入队列后核对队列与 toast、取消/返回退出

- [X] T008 [US2] `SourcePage` 增 `@Local selectMode: boolean` 与 `@Local selectedKeys: Set<string>`（不可变整体换引用更新范式），页头多选按钮进入多选，行点击按 `selectMode` 分派（选中切换 vs `playEpisode`）（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T009 [US2] 剧集行多选态渲染：行首勾选框（选中 `checkmark_circle`/未选空心圈），选中行视觉可辨，与 NEW/已播标记并存布局稳定；空列表（episodeCount=0）不渲染多选入口（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T010 [US2] 底部操作条：Stack 包裹 List 底部对齐（`selectMode` 时渲染），三项「全选/取消全选」（文案随全选态切换）、「加入队列 (N)」（N=0 禁用）、「取消」；bottom 避让沿用 `MINI_PLAYER_CLEARANCE + navBarHeight` 语义（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T011 [US2] 「加入队列」按列表序取选中剧集调 `controller.loadPlaylistAndPlay(items, 0)`，toast 复用 `PlayerController.enqueueToast(result)` 分型，完成后退出多选清空集合（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T012 [US2] `onBackPressed` 先查 `selectMode`：为真退出多选并拦截返回，为假走既有 `dismissOverlaysForBack()`（`entry/src/main/ets/pages/SourcePage.ets`）

**Checkpoint**: 多选全链路可用：进入→勾选→全选→入队→toast→退出；返回键先退多选

---

## Phase 5: User Story 3 - 页头随滚动收起 (Priority: P2)

**Goal**: 页头迁入列表滚动区，随滚动离屏/回顶再现
**Independent Test**: 长列表上下滚动观察页头离屏与回顶完整再现

- [X] T013 [US3] 页头（封面+订阅信息+多选按钮）改为 `List` 首个 `ListItem`，从 Column 固定区迁入滚动区；原 Column 固定头删除，`scrollToIndex(0)` 回顶语义核对（0=页头）（`entry/src/main/ets/pages/SourcePage.ets`）

**Checkpoint**: 页头随列表滚动，回顶完整再现，刷新回顶后页头可见

---

## Phase 6: User Story 4 - 充电视频标记（实测定夺） (Priority: P2)

**Goal**: 实测四类链路接口 → 带标记字段则解析+角标，不带则降级不实施
**Independent Test**: 实测结论留档 `BILI_API.md` §3；携带链路列表显示「充电」角标

- [X] T014 [US4] 充电标记实测：用真实订阅数据（覆盖 UP APP 签名链/UP Web 链/收藏夹/合集/系列）请求列表接口，记录各链返回是否携带充电标记字段（候选：`rights.is_upower_exclusive`、`is_charging_arc`、`ugc_pay` 等）及字段名，结论写入 `BILI_API.md` §3（首条记录）
- [X] T015 [US4] 按实测结论分叉：携带标记的链在对应解析点（`parseArchiveRecords`/`parseVlistRecords`/`parseFolderMedias`，`entry/src/main/ets/service/BiliService.ets`）解析字段写入 `isUpowerExclusive`，`SourcePage` 剧集行渲染「充电」角标（样式与 NEW 徽标同档）；**若全部链实测不携带**：移除 T005 增量字段与解析代码，在 `BILI_API.md` §3 记录「列表接口不支持，需求降级不实施」

**Checkpoint**: 带/不带角标与实测结论一一对应，无猜测性实现，结论留档

---

## Phase 7: User Story 5 - 页头等高与留白收窄 (Priority: P3)

**Goal**: 封面与文字等高（`SOURCE_HEADER_H`）；左右留白降一档
**Independent Test**: 页头两侧上下边缘对齐；页面左右边距较此前收窄

- [X] T016 [US5] 页头封面与文字列统一 `.height(Constants.SOURCE_HEADER_H)`（文字超长省略号截断），封面尺寸引用该令牌替代 56 裸数字（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T017 [US5] 留白收窄：List 与页头外边距统一 `TOKEN_SPACE_S`（List 左右 padding `TOKEN_SPACE_M`→`TOKEN_SPACE_S`，页头容器左右 `TOKEN_SPACE_L`→`TOKEN_SPACE_S`），行内 padding 不动（`entry/src/main/ets/pages/SourcePage.ets`）

**Checkpoint**: 页头等高对齐，留白收窄且全部走令牌

---

## Phase 8: User Story 6 - biliAPI 探索文档 (Priority: P1，与 US1-2 并行推进)

**Goal**: `BILI_API.md` 三段齐全（本项目汇总/biliRelay 迁移/充电实测）
**Independent Test**: 三部分内容齐全，路径引用相对化，biliRelay API 内容无遗漏

- [X] T018 [US6] 填充 §1 本项目探索汇总：在用端点清单（视频详情、UP 列表 APP+Web 双链、收藏夹、合集、系列、播放取流、登录二维码）+ 各端点鉴权/签名要求（APP 端点 BiliDroid UA、Web 端点 WBI 签名、短链 rcp 解析）+ 已知坑与对策（风控冷却、`maxRedirects: 0` 语义等）；素材取自 `AGENTS.md`、`entry/src/main/ets/service/Constants.ets` 机制注释与既有 spec 工件（`BILI_API.md`）
- [X] T019 [US6] 迁移 §2 biliRelay API 探索内容：源 `../bili/biliRelay/docs/B站API试错记录.md`，迁入实验 1-14、16-21、状态码速查、排查手册（按原文迁移不改写，标注来源与迁移说明），剔除非 API 内容（实验 15 Docker 部署等）（`BILI_API.md`）
- [X] T020 [US6] 核验 §3 首条（T014 产出）在档 + 全文路径引用相对化自查（仓库内相对仓库根、仓库外相对仓库根上级）（`BILI_API.md`）

**Checkpoint**: 文档三段齐全可独立交付，AGENTS.md 既有摘要不动

---

## Phase 9: Polish

- [X] T021 全量回归自查：FR-011 清单逐项核对（NEW 徽标/已播标记/触底加载更早四类链路/退订二次确认/空态/按压态/行封面时长角标）+ 多选与加载更早并存（新载入默认未选中）+ 刷新中禁止重复触发（`entry/src/main/ets/pages/SourcePage.ets`）
- [X] T022 规范自查：本轮改动无裸数字/裸色值（新增数值走 `Constants` 令牌）、无 `any`/`unknown`/`as` 断言、零注释规范（机制注释除外）（`entry/src/main/ets/pages/SourcePage.ets` 等本轮全部涉改文件）

---

## Phase 10: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建、部署与 UI 验证（用户已选 build+ui 范围）

- [X] T023 构建项目并修复编译错误：对本轮涉改 `.ets` 文件先跑 `arkts_check` 预检，通过后 `devecocli build`，迭代修复直至成功
- [X] T024 部署应用到设备/模拟器：`devecocli run --skip-build`
- [X] T025 UI 验证：对已部署应用按用户故事逐条走查（verify_ui），覆盖顶栏菜单、多选批量入队、页头滚动收起、等高与留白、充电角标（如实施）

---

## Phase 11: User Story 7 - 剧集行封面与文字等高（追加） (Priority: P3)

**Goal**: 封面 121×68 与文字列固定 68 严格等高，标题贴顶/附属行贴底
**Independent Test**: 两行标题行上下边缘对齐；单行标题行标题贴顶、附属行贴底；多选勾选框垂直居中

- [X] T026 [US7] `Constants` 调整 `EPISODE_THUMB_W/H` 140×79 → 121×68（≈16:9；请求档 `EPISODE_THUMB_REQ_*` 480×270 不变）（`entry/src/main/ets/service/Constants.ets`）
- [X] T027 [US7] 剧集行文字列追加 `.height(Constants.EPISODE_THUMB_H)` + `justifyContent(FlexAlign.SpaceBetween)`（标题贴顶、日期/NEW/已播行贴底），删附属行 `margin({ top: TOKEN_SPACE_XS })`（`entry/src/main/ets/pages/SourcePage.ets`）
- [ ] T028 [US7] 真机（Mate 70 Pro+）部署 + UI 目检：封面 121×68 与时长角标、两行/单行标题对齐形态、多选勾选框居中（`devecocli run --skip-build`，设备连接后执行）

**Checkpoint**: 剧集行等高形态落地（T026/T027 已随追加轮完成，arkts_check 零诊断 + `devecocli build` 通过）；T028 待真机连接

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**: 无依赖，立即开始
- **Foundational（Phase 2）**: 依赖 Setup，阻塞全部用户故事
- **User Stories（Phase 3-8）**: 依赖 Foundational 完成
  - 页面线（US1→US2→US3→US5）同文件须严格按序
  - 文档线（US6）与页面线并行，仅 T020 需 T014/T018/T019 齐备
  - US4 实测（T014）可与页面线并行，T015 依赖 T005+T014
- **Polish（Phase 9）**: 依赖全部用户故事完成
- **Verification（Phase 10）**: 依赖 Polish 完成

### User Story Dependencies

- **US1（P1）**: Foundational 后即开始——页面骨架，阻塞 US2/US3/US5（同文件）
- **US2（P2→P1）**: 依赖 US1 顶栏结构
- **US3（P2）**: 依赖 US1；页头迁位后 US5 在其上叠加
- **US4（P2）**: 仅依赖 T005 字段与 T014 实测，可与页面线并行
- **US5（P3）**: 依赖 US3 页头迁位完成
- **US6（P1）**: 独立文档线，与页面线并行；T020 收口需 T014 结论

### Within Each User Story

- 模型/令牌先行（T004/T005），UI 挂载随后
- 同文件任务按 Task ID 顺序执行，不并行

### Parallel Opportunities

- T002/T003（三文件互不相交）可与 T001 并行
- 文档线 T018/T019 与页面线全程并行
- T014 网络实测与页面线并行

## Parallel Example

```text
# 文档线与页面线并行：
Task: T018 填充 §1 本项目探索汇总（BILI_API.md）
Task: T006 移除播放全部（SourcePage.ets）

# Setup 三任务并行：
Task: T001 文档骨架（BILI_API.md）
Task: T002 注释同步 A（Constants.ets / CoverThumb.ets）
Task: T003 注释同步 B（SettingsPage.ets）
```

## Implementation Strategy

### MVP First（US1+US2）

1. Setup + Foundational（T001-T005）
2. US1 顶栏收纳（T006-T007）→ 独立验证
3. US2 多选批量入队（T008-T012）→ 独立验证 → MVP 达成

### Incremental Delivery

1. Setup + Foundational → 基础就绪
2. US1 → US2 → MVP 验证
3. US3 页头滚动 → US4 充电实测分叉 → US5 等高留白 → 逐项验证
4. US6 文档线全程穿插（T018/T019 随时可做，T020 收口）
5. Polish 自查（T021/T022）→ Verification（T023-T025）

### 实施轮次建议

- **单轮执行**（推荐）：任务量小（25 项，代码集中于单页面），T001-T025 顺序一轮完成；文档线与页面线交错推进
- 零代码轮次不适用（用户已批准实施）

---

## Notes

- [P] 任务 = 不同文件、无依赖；同文件任务一律按序
- T014 实测请求注意风控冷却（间隔 ≥3s，勿密集打点；对照 biliRelay 排查手册 §4）
- T015 是条件分叉任务：实测结论决定「解析+角标」或「降级移除」，两分支互斥
- Verification 范围为 build+ui（用户在本轮显式指定），UI 验证按用户故事逐条走查
