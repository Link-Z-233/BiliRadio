# Tasks: appsign-up-fetch（AppSign 游客签名接入 UP 投稿取链）

**Input**: Design documents from `spec/appsign-up-fetch/`
**Prerequisites**: plan.md（D1–D7 已锁定）, spec.md（US1–US3, FR-001~007, SC-001~005）

**Tests**: 本项目无测试套件，验证走 arkts_check + devecocli build + 实机 UI 验证。

**Organization**: 任务按用户故事分组；全部改动集中于 `entry/src/main/ets/` 下 4 个文件（Constants / AppSigner / BiliService / SourcePage），同文件任务串行。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: 归属用户故事
- 路径均相对项目根

---

## Phase 1: Setup（共享基础设施）

现有项目，无需脚手架。Setup 阶段仅一项：

- [x] T001 加载 `ponytail` 与 `hmos-arkui-develop-skill` skill，通读 `entry/src/main/ets/service/BiliService.ets` 现有 UP 取链（`fetchUpVideosViaApp` ~L696、`fetchUpVideosPaged` ~L839）与 `SourcePage.ets` loadOlder UP 分支，确认改动面

---

## Phase 2: Foundational（阻塞性前置）

**⚠️ CRITICAL**: T002/T003 完成前不得开始任何用户故事实现

- [x] T002 `entry/src/main/ets/service/Constants.ets`：新增 `TV_APP_KEY = 'dfca71928277209b'`、`TV_APP_SEC = 'b5475a8825547a4fc26c7d518eaaa02e'`（D7；置于既有 `BILI_APP_ARCHIVE_URL`/`BILI_APP_USER_AGENT` 附近，遵守「零注释、Constants 唯一真相源」）
- [x] T003 新建 `entry/src/main/ets/service/AppSigner.ets`：实现 `signQuery(params: Record<string, string>): string`——MD5 走 cryptoFramework（复用 WbiSigner 的摘要范式），键名 ASCII 升序拼接 `k=v&`，尾接 `appsec` 后取摘要；**不做** `!'()*` 过滤（D5）。单例或纯静态函数，与 WbiSigner 风格一致（depends T002）

---

## Phase 3: User Story 1 — 签名头页接入刷新链（Priority: P1）🎯 MVP

**Goal**: 刷新进 UP 源时走 AppSign 签名头页，-400 消失、一页一请求（SC-001）。
**Independent Test**: 真机打开任一 UP 订阅源，日志确认 APP 签名链 200 且无 -400、无 Web 三轮退避。

- [x] T004 [US1] `entry/src/main/ets/service/BiliService.ets`：改造 `fetchUpVideosViaApp` 为签名头页请求——撤 `pn`、`ps=30`（D2）、参数追加 `appkey/ts/sign`（AppSigner 签名）、**头页不传** `aid/next`；解析 `data.list.vlist` + `data.next` + `data.has_next`（D6 到底语义：`has_next==false` 或空列表即到底）；UA 沿用 `BILI_APP_USER_AGENT`（depends T003）
- [x] T005 [US1] `entry/src/main/ets/service/BiliService.ets`：cursor 缓存——模块级 `Map<number, UpAppCursor>`（`UpAppCursor` 内部类：`nextOffset: number`，session 内存、不导出）；写入/失效规则：APP 头页成功写、Web 头页成功删、`has_next==false` 删、链路失败删（D3）；`fetchUpVideos` 公开签名不变，头页改为「APP 签名链优先 → 失败落 Web 退避链（现状原样）」（depends T004）
- [x] T006 [US1] `entry/src/main/ets/service/BiliService.ets`：US1 日志契约——APP 链成功与降级均落 Logger 日志（net 域），明确区分链路，供 SC-001 实机核对（depends T005）

**Checkpoint**: 刷新链签名化完成，可独立上真机验证。

---

## Phase 4: User Story 2 — cursor 翻旧页（Priority: P2）

**Goal**: 触底加载走 APP cursor 链（`aid=<末条 aid>` + `next=<上次 data.next>`），不重复不跳空（SC-002/SC-004）。
**Independent Test**: 真机连续触底 3 次，列表无重复条目、无跳空、请求计数一页一请求。

- [x] T007 [US2] `entry/src/main/ets/service/BiliService.ets`：新增 `fetchUpVideosOlder(mid: number, lastAid: number): Promise<BiliVideo[]>`——cursor 命中则发 `aid+next` 签名请求；成功更新 cursor（`has_next==false` 删）；失败删 cursor 并抛错（交由调用方降级）（depends T006）
- [x] T008 [US2] [P] `entry/src/main/ets/service/BiliService.ets`：`fetchUpVideosByPage`（pn>1）撤恒败的裸 APP 预检，改纯 Web 链（D4；与 T007 同文件但改动点独立，可并行编写）
- [x] T009 [US2] `entry/src/main/ets/pages/SourcePage.ets`：loadOlder UP 分支重接——cursor 可用先走 `fetchUpVideosOlder`（成功 `olderPage++`）；失败落 Web 同页号（`olderPage+1`）；`olderPage` 两链统一记账（D4）；**endArmed 机制原样保留**（depends T007, T008）

**Checkpoint**: 翻页链 cursor 化完成，可与 US1 一同真机验证。

---

## Phase 5: User Story 3 — 降级保底无感（Priority: P2）

**Goal**: APP 签名链任一环节失败时无感落 Web 链，界面不空转不报错（SC-003）。
**Independent Test**: 构造 APP 链失败（如断网重连瞬间/风控拦截），刷新与触底仍出数据，日志可见降级记录。

- [x] T010 [US3] `entry/src/main/ets/pages/SourcePage.ets`：降级路径完整衔接——APP 失败后本会话粘性落 Web（头页与触底两处）、endArmed 失败消费不回补现状保持；降级与回切均有 Logger 日志（与 T006 契约对齐）（depends T009）

**Checkpoint**: 三故事全通，进入收尾。

---

## Phase 6: Polish（跨故事收尾）

- [x] T011 [P] `entry/src/main/ets/service/BiliService.ets`：清理过时注释与死代码——撤「APP 端点裸 UA 恒 -400」旧注释、`fetchUpVideosPaged` 遗留死路径；确认无 `any/unknown/as` 断言、无魔法数字外泄
- [x] T012 [P] `arkts_check` 三个改动文件（BiliService.ets / AppSigner.ets / SourcePage.ets）通过（depends T011）

---

## Phase 7: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 构建 + 部署实机（MatePad Pro 11）+ 逐故事 UI 验证

- [x] T013 `devecocli build` 直至编译通过（失败修复重试计入）——全程 4 次构建零失败
- [x] T014 `devecocli run --skip-build` 部署实机（验证前用户须已连设备，`devecocli device list` 可见）
- [x] T015 UI 验证 US1（SC-001）：真机打开 UP 订阅源刷新，日志确认签名链 200、无 -400、一页一请求——PASS（2/3 次，修复 data.item[] 解析分支）
- [x] T016 UI 验证 US2（SC-002/SC-004）：触底连续翻页 ≥3 次，无重复、无跳空、到底语义正确（最后一页正确停止）——PASS（2/3 次，20→39→60→81 恰合全集、到底正确停止）
- [x] T017 UI 验证 US3（SC-003）：构造 APP 链失败，Web 降级接管无感，日志可见降级记录——PASS（1/3 次，破坏包验证降级、恢复包确认回切）
- [x] T018 UI 验证 SC-005（US9 遗留）：日志文件非 0 字节、无一次性 hilog 告警——PASS（导出铁证 11653 字符 + 全会话零落盘失败告警）

---

## Dependencies & Execution Order

```
T001 → T002 → T003 → T004 → T005 → T006 ─┬→ T007 ─┬→ T009 → T010 → T011 → T012 → T013 → T014
                                          └→ T008 ─┘                                    ↓
                                                                                    T015 → T016 → T017 → T018
```

- **Foundational（T002/T003）阻塞全部故事**；故事内同文件任务严格串行
- T008 与 T007 改动点独立可并行，但同文件建议顺序执行避免冲突
- 实机验证（T015–T018）按故事顺序逐个执行
- 全部完成后：单次提交打包（staged 的 Logger/EntryAbility/housekeeping + 本特性实现 + spec 工件）

## Path Conventions

- 单项目结构，源码根 `entry/src/main/ets/`
- `service/`（业务单例）、`pages/`（页面）、`model/`（数据类）、`component/`（共用 UI）

---

## Parallel Example

```bash
# 无真正并行窗口：T007 与 T008 理论可并行（同文件不同改动点），
# 但 BiliService.ets 全程单线编辑更安全，实际执行全部串行
Task: "T007 fetchUpVideosOlder cursor 翻旧页"
Task: "T008 fetchUpVideosByPage 撤 APP 预检"
```

---

## Implementation Strategy

### MVP First（User Story 1 Only）

1. T001–T006 完成后即得 MVP：刷新链签名化，可独立真机验证 SC-001
2. US2/US3 增量叠加，各自有独立验证点
3. 全故事通过后进入 Verification 阶段统一实机验证

---

## Notes

- 改动面仅 4 文件：Constants.ets、AppSigner.ets（新建）、BiliService.ets、SourcePage.ets
- 硬约束：`fetchUpVideos` 公开签名不变、SubscriptionStore 不动、endArmed 本轮不删、`[API24-COMPAT]` 守卫不动
- FR-005（endArmed 删除）为下轮任务，仅在 T015–T018 全过后启动
