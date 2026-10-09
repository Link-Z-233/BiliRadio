# Tasks: UX 反馈第 6 轮修复（15 项反馈＋1 项补录 bug＋文档调整）

**Input**: Design documents from `spec/ux-feedback-round6/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: 无自动化测试套件（项目无测试文件）；验收依赖构建通过＋各任务验收标准自查，实机验收由用户在交付后手动执行。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **单模块项目**：源码根为 `entry/src/main/ets/`，下文 `pages/`、`service/`、`component/` 均相对此目录
- 资源文件以 `entry/src/main/resources/` 为根（任务中显式标注）
- 常量/键名/色值一律取自 `service/Constants.ets`（唯一真相源），禁止散落字面量；代码零注释（`ponytail:` 标注除外）；ArkTS 严格模式；既有 `[API24-COMPAT]` 守卫保留

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 本轮共享常量与色彩资源，供后续故事引用

- [X] T001 [Setup] `service/Constants.ets` 新增常量：`LOAD_OLDER_FAIL_COOLDOWN_MS = 3000`、`COVER_THUMB_W/H = 240`、`COVER_BIG_W/H = 672/378`、`COVER_SAVER_W/H = 480/270`
- [X] T002 [P] [Setup] 新增色彩资源 `success_green`：`entry/src/main/resources/base/element/color.json` 与 `entry/src/main/resources/dark/element/color.json` 各一套（取值见 plan D7）

**Checkpoint**: 常量与资源就绪，后续故事可引用

---

## Phase 2: User Story 1 - 首页订阅列表同步 (Priority: P1) 🎯 MVP

**Goal**: 删除订阅后回到首页列表即时同步；刷新不复活已删源；行内容随磁盘态刷新
**Independent Test**: 删除任一订阅 → 返回首页该源消失；下拉刷新后仍消失

- [X] T003 [US1] `service/SubscriptionStore.ets` 新增实例方法 `subExists(id: string): boolean`（按当前磁盘态判断）
- [X] T004 [US1] `pages/HomePage.ets` `rebuild()` 起点改为 `SubscriptionStore.loadSubscriptions()` 重载，不再复用 aboutToAppear 时的陈旧 `this.subs`（depends on T003）
- [X] T005 [US1] `pages/HomePage.ets` `silentRefresh`（L90 附近）发起前逐源 `subExists` 校验、回调落盘前过滤已删订阅（depends on T004）
- [X] T006 [US1] `pages/HomePage.ets` LazyForEach 行键值由 `id_latestTitle_newCount` 扩为 `id_latestTitle_newCount_cover`（depends on T004）

**Checkpoint**: 首页订阅列表与磁盘态一致，删除/刷新链路可靠

---

## Phase 3: User Story 2 - 触底加载连发修复 (Priority: P1)

**Goal**: 删除 endArmed 手势武装机制，单次滚动最多加载一页，失败进入 3 秒冷却
**Independent Test**: 弱网/失败场景下快速滚动触底，仅发起一次加载请求；3 秒后可再次触发

- [X] T007 [US2] `pages/SourcePage.ets` 删除 `endArmed` 字段（L51）、武装赋值（L93、L427）、注释块（L153）与门槛项（L157、L160）；`loadOlder` 门槛回退为 `loadingOlder || !canLoadOlder`
- [X] T008 [US2] `pages/SourcePage.ets` 加载失败后 3 秒内（`LOAD_OLDER_FAIL_COOLDOWN_MS`）不重复发起 `loadOlder`，冷却期满恢复（depends on T007）

**Checkpoint**: 触底加载行为稳定，无连发请求

---

## Phase 4: User Story 9 - 系统播控进度条为空修复 (Priority: P1)

**Goal**: 历史重播曲目在锁屏/控制中心进度条正常显示（总时长正确、随播放走动）；订阅链路不回归
**Independent Test**: 播放历史中点任意条目重播 → 锁屏查看进度条出现且总时长正确

- [X] T009 [P] [US9] `pages/SettingsPage.ets` `replayHistory`（L278-283）重建 BiliVideo 时以 `item.duration` 替换硬编码 0（历史条目已存秒数）
- [X] T010 [US9] `service/MediaSession.ets` `updateTrack`（L63 附近）缓存时长字段（毫秒）；`updateState`（L87 附近）的 AVPlaybackState 增加 `duration` 字段随每次状态上报（SDK since API 11，基线 API 24 可用，无需兼容守卫）
- [X] T011 [US9] `service/PlayerController.ets` prepared 处理器取得 `this.player.duration`（L307 附近）后，若该曲目此前推送系统会话的时长为 0，以 `force=true` 重推 `mediaSession.updateTrack`（绕过 `lastAssetId` 同曲去重）（depends on T010）

**Checkpoint**: 历史重播与零时长兜底链路的系统播控进度条全链路可用（SC-007）

---

## Phase 5: User Story 3 - 源页行展示重排 (Priority: P2)

**Goal**: 标题独占整行；时间到分钟；已播标识仅听完条目显示且为绿色
**Independent Test**: 打开任一订阅源列表查看行布局、时间格式与已播/NEW 角标

- [X] T012 [US3] `pages/SourcePage.ets` `loadPlayedSet` 仅收 `progress === -1`（哨兵＝听完），排除进度>0 的中途条目
- [X] T013 [US3] `pages/SourcePage.ets` 行布局重排：标题独占整行（最多两行省略）；时间行左端 `M-d HH:mm`、右端先 NEW（主题色）后已播（`success_green`「✓ 已播」，仅听完条目）（depends on T012）
- [X] T014 [US3] `pages/SourcePage.ets` `formatDate` 由 `YYYY-MM-DD` 改为 `M-d HH:mm`（当天条目仅 `HH:mm`）（depends on T013）

**Checkpoint**: 源页行展示符合 SC-006

---

## Phase 6: User Story 4 - 返回层级修复 (Priority: P2)

**Goal**: 历史发起播放后：第一次返回仅关历史面板（浮层保持、播放不中断），第二次返回收起浮层回到设置页
**Independent Test**: 播放历史点条目播放 → 按系统返回 → 浮层仍在播放；再按返回 → 浮层收起回到设置页

- [X] T015 [P] [US4] `pages/Index.ets` `onBackPress`（L126 附近）实现优先级：`浮层开 && 历史面板开 → 仅关面板`；`浮层开 && 面板关 → 关浮层`；否则走既有分支。禁止返回事件穿透弹回首页（plan D3 风险项）
- [X] T016 [US4] `pages/SettingsPage.ets` `onBackPressed` 实现与 Index 相同优先级；删除 `shouldDismiss` 拦截逻辑（与 T015 保持同构）
- [X] T017 [US4] `pages/SettingsPage.ets` 删除历史面板底部渲染 statusMsg；`replayHistory` 加 try/catch，失败 toast（depends on T016）

**Checkpoint**: 系统返回与页面内返回行为一致、层级正确

---

## Phase 7: User Story 5 - 回弹过冲提示 (Priority: P2)

**Goal**: 列表到顶/到底后继续拉，空隙显示灰字提示（顶「已经到顶了」/底「已经到底了」/源页底部三态），松手回弹消失
**Independent Test**: 首页、源页、历史面板三处列表分别拉顶/拉底观察提示文字

- [X] T018 [US5] 新建 `component/EdgeHint.ets`：纯展示组件，`@Prop text: string` 空串不渲染；灰色文字居中，无背景无计时器，可见性由宿主过冲状态驱动
- [X] T019 [US5] `pages/HomePage.ets` 接入：宿主 Stack 中 List 之前放 EdgeHint（z 序更低、List 背景透明）；过冲状态由 onScrollEdge 触发、回弹归位隐藏，onWillScroll 兜底（depends on T018）
- [X] T020 [US5] `pages/SourcePage.ets` 接入底部三态：加载中…／没有更多了／可加载时不显示；顶部同 HomePage 逻辑；失败冷却期不误显示「没有更多了」（depends on T018、T007、T008）
- [X] T021 [US5] `pages/SettingsPage.ets` 历史面板列表底部过冲显示「已经到底了」（depends on T018）

**Checkpoint**: 三列表过冲提示可用；短列表天然不触发；刷新按钮不触发

---

## Phase 8: User Story 6 - 封面按档取图 (Priority: P2)

**Goal**: 大封面与系统播控封面按显示尺寸取图：Wi-Fi 用 672×378、非 Wi-Fi 用 480×270；列表缩略图 240 档不变
**Independent Test**: Wi-Fi 打开播放页看大封面清晰度；蜂窝网络下锁屏封面为小档

- [X] T022 [P] [US6] 新建 `service/CoverUrl.ets`：静态方法 `sized(url, w, h)`——raw 场景（无 `@` 分隔）原样返回；常规场景拼 `@{w}_{h}.imgsize` 后缀。不可回归 AddSubscriptionSheet L459/649/685 现有 raw 拼接行为
- [X] T023 [P] [US6] `service/PlayerController.ets` 公开 `isWifiNow(): boolean`，复用既有 `watchStableNetworkType` 订阅结果（勿新建监听）
- [X] T024 [US6] `component/CoverThumb.ets` 改用 `CoverUrl.sized(url, COVER_THUMB_W, COVER_THUMB_H)`，240 档视觉不变（depends on T022）
- [X] T025 [US6] `pages/PlayerOverlay.ets` 大封面（L846 附近）改 `CoverUrl.sized`：Wi-Fi 用 `COVER_BIG_W/H`、非 Wi-Fi 用 `COVER_SAVER_W/H`（depends on T022、T023）
- [X] T026 [US6] `service/MediaSession.ets` `updateTrack` 封面（L78 附近 `meta.mediaImage`）改 `CoverUrl.sized`：Wi-Fi 用 `COVER_BIG_W/H`、非 Wi-Fi 用 `COVER_SAVER_W/H`；网络态查询失败按省流档（depends on T022、T023）

**Checkpoint**: 三处封面取图档位正确（SC-005），raw 场景无回归

---

## Phase 9: User Story 7 - 设置页调整 (Priority: P2)

**Goal**: 日志改二级页；登出二次确认；文案更名×3 与历史入口挪位；移除面板底部状态文案
**Independent Test**: 设置页逐项检查：日志进出与角标、登出弹窗、文案与顺序

- [X] T027 [US7] 新建 `pages/LogPage.ets`（NavDestination 薄壳，复用 LogSheet）＋ `entry/src/main/resources/base/profile/router_map.json` 注册 `logPage`
- [X] T028 [US7] `component/LogSheet.ets` 微调适配页面形态（去除 sheet 专属交互），保留内存环形缓冲语义（depends on T027）
- [X] T029 [US7] `pages/SettingsPage.ets` 日志入口由 bindSheet 改路由跳转 `logPage`；删除 bindSheet 分支；onPop 刷新未读角标（depends on T028）
- [X] T030 [P] [US7] `pages/SettingsPage.ets` 登出入口加确认弹窗；确认后先停止轮询中的登录流程再执行登出
- [X] T031 [US7] `pages/SettingsPage.ets` 三处文案更名（按 spec US7 清单）＋「播放历史」入口挪到登录状态区正下方＋设置项按 spec 新顺序排列（depends on T029）

**Checkpoint**: 设置页全部调整到位，日志数据不丢失

---

## Phase 10: User Story 8 - 文档调整与登记 (Priority: P3)

**Goal**: README 引用 PiliPlus 并硬删除版本信息；PROJECT_NOTES 登记三条规划
**Independent Test**: README 检索无版本号信息；PROJECT_NOTES 三条登记齐全
- [X] T032 [P] [US8] `README.md`：① 参考项目节引用 PiliPlus——项目 URL 必须从本地 `D:/UsersFiles/Link_Z/Desktop/Code/PiliPlus` 的 git remote 读取，禁止凭记忆编写；② 硬删除「版本」小节与「版本号从 0.1.0 重新起版」行，原位置不补任何替代文案（FR-024）

- [X] T033 [P] [US8] `PROJECT_NOTES.md`：登记三条规划（订阅源导出导入、关于页文案优化、版本号更新待播放列表重做完后统一执行）；「播放队列左滑删除（KI-3）」标注暂缓

**Checkpoint**: 文档与登记完成；AppScope/app.json5 未被改动（versionName 0.1.0/versionCode 1000）

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: 跨故事全局自查

- [X] T034 全局自查：① 全局检索 `endArmed`、`shouldDismiss` 引用清零；② `AppScope/app.json5` 未被改动；③ QueueDrawer/队列相关文件未动（本轮明确不动）；④ 既有 `[API24-COMPAT]` 守卫全部保留；⑤ 新增常量全部集中在 Constants

---

## Phase 12: Verification

<!-- verification_scope: build-only -->

**Purpose**: Build and deploy the implemented feature

- [x] T035 Build project and fix any compilation errors (invoke `devecocli build`; iterate fix → build until success) — BUILD SUCCESSFUL（1 次通过，零修复）
- [x] T036 Deploy application to device/emulator (invoke `devecocli run --skip-build`) — 跳过，用户手动安装

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **User Stories (Phase 2-10)**: 引用 Phase 1 常量/资源；按优先级 P1 → P2 → P3 顺序执行（US1 → US2 → US9 → US3 → US4 → US5 → US6 → US7 → US8）
- **Polish (Phase 11)**: Depends on all user stories being complete
- **Verification (Phase 12)**: Depends on Phase 11

### User Story Dependencies

- **US1 (P1)**: 依赖 Phase 1；无跨故事依赖
- **US2 (P1)**: 依赖 Phase 1；无跨故事依赖
- **US9 (P1)**: 依赖 Phase 1；与 US7 同改 SettingsPage（T009 与 T017/T029-T031 同文件，须顺序执行）
- **US3 (P2)**: 依赖 Phase 1；与 US2/US5 同改 SourcePage，须按 Phase 顺序
- **US4 (P2)**: 依赖 Phase 1；与 US5/US7/US9 同改 SettingsPage，须按 Phase 顺序
- **US5 (P2)**: 依赖 Phase 1 的色彩资源与 EdgeHint（T018）；T020 依赖 US2 的 T007/T008
- **US6 (P2)**: 依赖 Phase 1；T026 与 US9 的 T010 同改 MediaSession，须顺序执行
- **US7 (P2)**: 依赖 Phase 1；与 US4/US5/US9 同改 SettingsPage，须按 Phase 顺序
- **US8 (P3)**: 无代码依赖，可与任何故事并行

### Within Each User Story

- 服务/工具类先于页面接入（如 T022/T023 先于 T024-T026；T018 先于 T019-T021）
- 同文件任务按编号顺序执行

### Parallel Opportunities

- Phase 1: T001 与 T002 并行
- US9: T009 与 T010 并行（不同文件）
- US6: T022 与 T023 并行；T024/T025/T026 三者并行（不同文件，均只依赖 T022+T023）
- US4: T015 与 US9 的 T009 并行（不同文件）
- US8: T032、T033 与任何代码故事并行

---

## Parallel Example: User Story 6

```bash
# Launch independent tool tasks together:
Task: T022 "新建 service/CoverUrl.ets sized 工具"
Task: T023 "service/PlayerController.ets 公开 isWifiNow"

# Then launch consumers together (all depend on T022+T023, different files):
Task: T024 "component/CoverThumb.ets 改走 CoverUrl"
Task: T025 "pages/PlayerOverlay.ets 大封面档位"
Task: T026 "service/MediaSession.ets 封面档位"
```

---

## Implementation Strategy

### MVP First (P1 Stories Only)

1. Complete Phase 1: Setup（常量＋色彩资源）
2. Complete US1/US2/US9（三个 P1：首页同步、触底加载、系统播控进度条）
3. **STOP and VALIDATE**: 构建通过，三个 P1 故事独立可验
4. Deploy/demo if ready

### Incremental Delivery

1. Setup → US1 → US2 → US9（P1 全部）
2. US3 → US4 → US5 → US6 → US7（P2，按序）
3. US8 文档（P3，可随时并行）
4. Polish 自查 → Verification 构建部署

### Sequential Constraint

本项目多个故事共用文件（SettingsPage×4、SourcePage×3、HomePage×2、PlayerController×2、MediaSession×2），**强烈建议单人按 Phase 顺序串行执行**，仅利用任务级 [P] 并行点。

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- 每个故事完成后可独立构建验证（checkpoint）
- 版本号本轮不动：`AppScope/app.json5` 保持 0.1.0/1000
- 播放队列（QueueDrawer 等）本轮明确不动——US5 仅接入三列表（HomePage/SourcePage/历史面板）
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
