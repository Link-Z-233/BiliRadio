# Implementation Plan: 欠账集中清理轮（debt-cleanup）

**Input**: Feature specification from `spec/v0.3-debt-cleanup/spec.md`

## Summary

三项代码改动 + 五项模拟器验证。代码：①删除无图模式开关全链（6 个源文件，保留图片尺寸分档与网络态降档）；②首页订阅列表补左滑删除（KI-3 最后一处，复用既有 removeSub 退订语义）；③链接识别修 B4（URL 规则优先于全文 BV 扫描）与 B5（fav 判定收紧至 path 级特征）。验证：模拟器上执行队列全量验收（R9/T032）、睡眠定时（KI-6/T032 US3）、R10 三项、降级衔接走查（T013/KI-9）、深浅色/主题色全页走查，以及本轮三项新改动的验收；通过即销项，测完关模拟器。

## Technical Context

**Language/Version**: ArkTS（API 26 基线，compatibleSdkVersion 26.0.0，targetSdkVersion 26.0.0）  
**Primary Dependencies**: ArkUI（@ComponentV2 体系）、AVSession（系统播控）、rcp（短链解析）  
**State Management**: V2 迁移已整体完结——页面/挂键组件 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`），`AS_*` 键经 V2State 包装类走 AppStorageV2；`PlayerController` 零装饰器纯类（手动 subscribe/emitUi 广播 + 版本计数，消费方 syncFrom 拷贝进 @Local）。本轮改动沿用现状，不引入新状态代际。  
**Storage**: AppStore（preferences 持久化，`KEY_*`）；本轮删除 `KEY_DATA_SAVER` 键定义与全部读写点，旧持久化值残留不清理  
**Testing**: 无测试套件；验证链 = `arkts_check`（改动 .ets 静态检查）→ `devecocli build` → 模拟器 `devecocli run --skip-build` 部署 + 逐故事 UI 验证  
**Target Platform**: HarmonyOS NEXT 单模块应用（Mate 90 Pro 模拟器验证）  
**Project Type**: mobile-app  
**Performance Goals**: 无新增性能目标；删除分支不引入回归  
**Constraints**: 代码零注释（除 `ponytail:` 标注）；Constants.ets 唯一真相源；禁 `any`/`unknown`/`as` 类型断言（ArkTS 严格模式）；PlayerController 新增公开状态沿用零装饰器广播模式  
**Scale/Scope**: 源码 8 文件改动（6 删 + 1 增交互 + 1 识别修订）+ 文档销项；验证矩阵 9 组用户故事

## Project Structure

### Documentation (this feature)

```text
spec/v0.3-debt-cleanup/
├── spec.md              # 需求规格（已批准）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── SettingsPage.ets        # US1: 删「无图模式」开关行(L1310-1323)与 dataSaver 状态(L172)
│   ├── HomePage.ets            # US2: LazyForEach 内 ListItem 挂 swipeAction；新增 subDeleteAction builder
│   └── PlayerOverlay.ets       # US1: 删 dataSaver 分支(L288/294/296)，保留网络态分档(L290-292)
├── component/
│   ├── MiniPlayer.ets          # US1: 删 dataSaver 分支(L38-40)
│   └── QueueSheet.ets          # US1: 删 dataSaverOn 状态(L96)/读取(L171)/渲染分支(L512)
├── service/
│   ├── PlayerController.ets    # US1: 删 refreshMediaSessionMetadata 方法(L186-195)与 2 处 dataSaver 读取(L349/L695)
│   ├── Constants.ets           # US1: 删 KEY_DATA_SAVER(L33)
│   ├── LinkResolver.ets        # US3: recognizeInput 规则调序 + fav 启发式收紧
│   ├── SleepTimerController.ets # US5 验证通过后: 删文件头 [UNVERIFIED] 标注
│   └── MediaSession.ets        # US1: 空封面守卫保留（服务无封面条目），注释按需更新
PROJECT_NOTES.md                 # US9: KI-3/KI-6/KI-7/KI-9 销项、R9/R10 更新、无图模式 REM 登记
spec/v0.0-queue-redesign/tasks.md     # US9: T031/T032 勾选
spec/v0.3-engineering-refactor/tasks.md # US9: T013 勾选
```

**Structure Decision**: 遵循现有项目架构（pages/service/component/model 分层 + `@ComponentV2` 状态体系 + 模块边界契约 `spec/v0.3-engineering-refactor/architecture-boundary.md`），不引入新目录、新层级、新状态代际。改动全部落在既有文件内；依赖方向不变（pages→service/model、service→model）。

## Complexity Tracking

无宪法违规——本轮为既有架构内的删除/修补，无新增抽象。

## Research & Decisions

### D1: 删无图模式——删除清单与保留边界

**Decision**: 移除范围——`Constants.KEY_DATA_SAVER` 键定义；SettingsPage 开关行与 `dataSaver` 状态；PlayerController.`refreshMediaSessionMetadata()` 方法（唯一调用方为开关回调，已核实）；PlayerController 3 处 `dataSaver ? '' : cover` 读取点（改为直传 `item.cover`）；PlayerOverlay 的 `trackCover`/`ownerFace` 置空分支（保留网络态分档取图 L290-292 与 `CoverUrl.sized` 调用）；MiniPlayer 封面置空分支；QueueSheet 的 `dataSaverOn` 状态、读取与渲染分支（`CoverThumb` 直传 `item.cover`）。**保留**：MediaSession.updateTrack 的空封面守卫（`coverUrl !== ''` 才设 `mediaImage`）——该守卫同时服务「无封面条目」（如收藏夹订阅无封面场景），非无图模式专属；`PlayerController.refreshUi()` 方法保留（本轮仅移除开关行的调用点）。

**Rationale**: 边际收益分析（图片占总流量 <2-5%，音频流主导；尺寸分档 + 网络态降档已在）确认开关价值不足；当前覆盖不全（首页/源页不接开关）造成「无图模式」名不副实；删除是销项「无图模式覆盖面扩展」欠账的最短路径。

**Alternatives considered**: 保留并补全覆盖（拒绝：每处新 UI 持续接开关的维护税）；非 Wi-Fi 自动无图（拒绝：用户选择直接删除）。

### D2: 首页左滑删除——挂载点与样式

**Decision**: HomePage `LazyForEach` 内 `ListItem` 挂 `.swipeAction({ end: this.subDeleteAction(row) })`；新增 `@Builder subDeleteAction(row: SubRow)`——红色「删除」按钮，样式逐字段对齐 SettingsPage.`historyDeleteAction`（`danger_red` 背景、`fg_on_dark` 文字、`height('100%')`、左右 padding 18、`borderRadius(0)`），点击调既有 `removeSub(row)`。

**Rationale**: KI-3 登记的交互约定（左滑露出、点击执行、不滑删）与播放历史/播放队列一致；`removeSub` 已含退订全语义（splice + `removeEpisodes` + `saveSubscriptions` + `rebuild`），零新逻辑；订阅行数少（通常 <20），`rebuild()` 全量重建成本可忽略，无需 LazyForEach 增量同步；键值生成器（`${sub.id}_${latestTitle}_${newCount}_${cover}`）不变。既有长按上下文菜单（置顶/删除订阅）保留，`swipeAction`（横向）与 `bindContextMenu`（长按）不同手势轴共存。

**Alternatives considered**: `provider.notifyDataDelete` 增量刷新（拒绝：首页 provider 为全量 reload 模式，行数少，增量收益为负复杂度）；仅靠长按菜单删除（拒绝：KI-3 登记的就是左滑缺口）。

### D3: KI-7 B4——识别规则调序

**Decision**: `recognizeInput` 内全文 BV 扫描（`BV[0-9A-Za-z]{10}`，无锚定）从首位移至全部 URL 形态规则之后、裸数字规则之前。新规则序：av 纯文本（锚定）→ av URL → lists → seriesdetail → collectiondetail → fav → space 移动端 → space 桌面 → **BV 全文** → 裸数字。纯 BV 文本不命中任何 URL 规则，落到 BV 分支行为不变；含 BV 参数的合集/收藏夹复合 URL 由更具体的 URL 规则先命中，正确分类。

**Rationale**: B4 缺陷根因是「无锚定的全文 BV 扫描置于最前，遮蔽更具体的 URL 规则」；调序是最小修复，不引入新正则。短链路径含 BV 的零网络短路（`shortLinkBvTarget`）位于 `resolveShortLink` 内，与 `recognizeInput` 调序无关，零影响。

**Alternatives considered**: 两段式（锚定 `^BV…$` 严格匹配放最前 + 宽松全文扫描放最后）（拒绝：双份规则复杂度高，单次调序已覆盖目标场景）；BV 加 base58 合法性校验（B8，用户决策本轮不修）。

### D4: KI-7 B5——fav 判定收紧

**Decision**: fav 判定从「`(?:fid|media_id)=(\d+)` 且文本任意位置含 fav/collection/favlist」收紧为「URL path 含 `favlist` 或 `medialist` 特征，且 query 含 `fid=` 或 `media_id=` 参数」。实施时以真实收藏夹 URL 形态核对：网页版 `space.bilibili.com/{mid}/favlist?fid={fid}`、移动端 `m.bilibili.com/space/{mid}/favlist?fid=...`、收藏夹播放页 `www.bilibili.com/medialist/play/...`；参考项目 PiliPlus（favlist 路径形态）与 biliRelay 实测形态，合法形态不得漏判。

**Rationale**: path 级特征（favlist/medialist）是收藏夹 URL 的结构性标志，误判面远小于「文本含 fav 字样」；原 `collection` 字样条件连带删除（收藏夹 URL 不依赖该词）。收紧后非收藏夹页面即使含 `fid=123` 参数与 fav 字样也不再误判。

**Alternatives considered**: host 白名单（仅 space.bilibili.com）（拒绝：过严，漏移动端与播放页形态）；维持现状（用户已决策修）。

### D5: 实施与验证分离架构

**Decision**: Phase 4（spec-implementation）只做代码改动（US1-3）+ `arkts_check` + `devecocli build`，不动模拟器；Phase 5（spec-verify）部署模拟器一次跑完整个验证矩阵——本轮新改动验收（US1 开关缺席与封面正常、US2 左滑删除、US3 识别场景）+ 欠账验收（US4 队列、US5 睡眠定时、US6 R10、US7 降级走查、US8 深浅色走查），逐故事顺序执行（每故事最多 1 初验 + 2 修复复验），全过后销项文档（US9）、关闭模拟器。

**Rationale**: 代码先稳定再验证，避免边改边测返工；模拟器只开一次，验证完关闭（用户要求「测完关掉」）；文档销项依赖验证结论，必须排在验证之后。

**Alternatives considered**: 每个故事改完即测（拒绝：模拟器反复部署，总时长更长且与 SDD 阶段划分冲突）。

### D6: 降级走查触发手段（T013 环境决策）

**Decision**: 降级触发首选模拟器网络代理/hosts 级屏蔽 APP 端点（使 AppSign 签名链失败而 Web 链可达）；若模拟器环境无 host 级控制手段，则「断网→恢复」只能验证网络失败态而非降级衔接，此时按 spec US7 场景 4 诚实保留 T013 欠账，不假 PASS。验证子代理现场判断手段可行性并记录所用手段。

**Rationale**: 降级=「APP 端点失败但网络可用」（AppSign 故障→Web 退避链），纯断网会同时杀死 Web 链，无法演练衔接；风控触发的 -799 不可人为稳定复现。诚实登记优于环境不允许下的假验证。

**Alternatives considered**: 代码注入临时故障开关（拒绝：为验证改产品代码得不偿失）；跳过 T013（拒绝：在册欠账，至少要给出环境受限结论）。

### D7: 深浅色走查范围

**Decision**: 走查页面清单：HomePage（订阅列表+空态）、SettingsPage（设置项+播放历史面板）、SourcePage（头部+剧集列表）、PlayerOverlay（播放层）、QueueSheet（队列面板）、AddSubscriptionSheet（添加面板）、LogPage（日志页）；维度：浅色/深色 × 默认主题色/切换主题色；方式：逐页操作 + 截图比对（对比度可读、无旧色残留、强调色全量生效），不做像素断言。发现问题分级：小问题记录在案继续，大问题暂停报告。

**Rationale**: engineering-refactor US2 令牌化收尾欠账；7 页面覆盖应用全部可导航界面；截图走查与真机目测等效性足够。

## Data Model

不新增数据实体。修订/删除：

- **`KEY_DATA_SAVER`（删除）**: AppStore preferences 键 `'dataSaver'`；定义（Constants L33）与全部读写点（6 文件 8 处）移除；旧持久化值残留不清理不读取（先例：`unfavorite_history.json`）
- **`RecognizeResult`（不变）**: type/id/ownerMid 字段与取值域不变；`recognizeInput` 签名不变，仅内部规则序修订与 fav 规则收紧
- **`SubRow`（不变）**: sub/latestTitle/newCount；左滑删除复用既有 `removeSub(row)`，无字段变化
- **`SleepTimerController`（代码不变）**: 仅验证通过后移除文件头 `[UNVERIFIED 2026-10]` 标注

## Contracts & Interfaces

- **`PlayerController.refreshMediaSessionMetadata(): void`（删除）**: 公开方法；删除前已核实唯一调用方为 SettingsPage 无图开关回调（L1321）；删除后无悬空调用
- **`recognizeInput(input: string): RecognizeResult`（签名不变，行为修订）**: 消费方 AddSubscriptionSheet（编排层）零改动；`resolveShortLink` 内部调用同样零改动；行为变化仅限 B4/B5 目标场景（复合 URL 分类、非收藏夹误判），既有输入分类回归由验收场景 5 保证
- **`MediaSession.updateTrack(assetId, title, durationMs, coverUrl, artist, force)`（签名不变）**: 空串 coverUrl 语义保留（无封面条目跳过 `mediaImage`），无图模式分支移除后该守卫仍服务无封面场景
- **`CoverUrl.sized(url, w, h)` / `CoverThumb`（不变）**: 尺寸分档（缩略 240 档 / 大图 672×378 / 省流 480×270）与 raw 直通语义零改动
- **`ListItem.swipeAction` 契约（HomePage 新增挂载）**: `end` 为删除按钮 builder；与既有 `bindContextMenu`（长按）手势共存，参照 QueueSheet/SettingsPage 已验证模式
