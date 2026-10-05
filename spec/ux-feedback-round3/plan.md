# Implementation Plan: 第三轮实机反馈批次（ux-feedback-round3）

**Input**: Feature specification from `spec/ux-feedback-round3/spec.md`

## Summary

落地用户实机验证后的 11 个故事：1 个视觉 bug（圆弧贴合）+ 6 项 UI/UX 调整（空态占位、下拉刷新禁用、MorePage 回退、队列标题两行、封面下移与完整标题、单击单条入队）+ 3 项功能（播完即停、播控中心 ±15 秒微调、应用内日志页）+ 1 项文档治理（KNOWN_ISSUES.md → PROJECT_NOTES.md 三章重构）。技术路径：全部为既有架构内的增量修改；唯一新服务是内存环形日志 Logger；播控微调依赖 API 26 `setMediaCenterControlType`（项目 targetSdkVersion 26.0.0 满足，API 24 设备 try/catch 降级）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS ArkTS 方言，strict 模式）
**Primary Dependencies**: ArkUI、@kit.AVSessionKit（播控）、@kit.MediaKit（AVPlayer）、@kit.NetworkKit（http）
**SDK**: targetSdkVersion **26.0.0** / compatibleSdkVersion **6.1.1(24)** —— API 26 新接口需运行时守卫
**State Management**: 既有项目为 State Management **V1**（@State/@StorageLink/@StorageProp/@Link），增量改动**保持 V1**，不迁移 V2
**Storage**: 日志**仅内存**（环形淘汰，不落盘）；其余沿用既有 AppStore/Preferences/文件存储，不新增持久化键
**Testing**: `devecocli build` + `arkts_check` 严格模式零诊断（验证范围并入本轮 Phase 5，build-only）
**Target Platform**: HarmonyOS 手机/平板
**Performance Goals**: 日志缓冲内存占用有界（≤500 条）；日志写入不阻塞播放主流程；列表 60fps（LazyForEach 既有模式）
**Constraints**: 服务层既有公开方法语义不变（`loadPlaylistAndPlay`/`seekBy`/`next`/`prev` 签名不动）；`next()` 的手动回绕行为保留；ArkTS 红线（禁 any/非空断言/index signature、build() 内无逻辑）
**Scale/Scope**: 改动 11 个源文件 + 2 个资源/配置文件，新增 2 个源文件，删除 1 个源文件，改名 1 个文档

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round3/
├── spec.md              # 需求规格（已确认）
├── plan.md              # 本文件
└── tasks.md             # 任务清单（Phase 3 生成）
```

### Source Code (repository root)

```text
KNOWN_ISSUES.md
└── (git mv) → PROJECT_NOTES.md            # US11：改名+三章重构

entry/src/main/ets/
├── service/
│   ├── Logger.ets                          # 【新增】US9：内存环形日志服务
│   ├── BiliService.ets                     # US9：3 个 HTTP helper + checkJsonBody 挂日志钩子（URL 脱敏）
│   ├── PlayerController.ets                # US7：handleCompleted 播完即停；常量迁出
│   ├── MediaSession.ets                    # US8：fastForward/rewind 监听 + setMediaCenterControlType
│   └── Constants.ets                       # US8/US9：SEEK_STEP_MS/SEEK_BY_DEBOUNCE_MS 迁入 + LOG_BUFFER_MAX
├── pages/
│   ├── PlayerOverlay.ets                   # US1：圆弧尺寸同源；US2：空态判定统一；US10：封面下移+完整标题
│   ├── SourcePage.ets                      # US6：playEpisode 改单条入队
│   ├── HomePage.ets                        # US3：下拉刷新注释禁用；US4：更多按钮改跳设置页
│   ├── SettingsPage.ets                    # US9：日志查询入口 + bindSheet
│   └── MorePage.ets                        # 【删除】US4
├── component/
│   ├── MiniPlayer.ets                      # US2：空态占位条 else 分支
│   ├── QueueSheet.ets                      # US5：头部两行结构
│   └── LogSheet.ets                        # 【新增】US9：日志面板组件（SettingsPage bindSheet 承载）
└── resources/base/profile/
    └── router_map.json                     # US4：移除 morePage 条目
```

**Structure Decision**: 遵循既有项目架构（pages/components/service/model 分层 + State Management V1），不引入 MVVM 迁移、不新增目录层级。新增 2 个源文件均有明确单一职责：Logger.ets 是跨页面共享的领域服务（不能塞进某个 page）；LogSheet.ets 独立成组件避免 SettingsPage（已 1423 行）继续膨胀，与 QueueSheet 同级复用同一模式。日志面板不建独立路由页，复用 SettingsPage 既有 bindSheet 面板模式（与播放历史面板同构）。

## Complexity Tracking

> 无 Constitution Check 违规，无需填表。

## Research & Decisions

### D1 播控中心 ±15 秒微调（US8，关键查证结论）

- **Decision**: 在 MediaSession 注册 `on('fastForward')` / `on('rewind')` 监听（回调走 PlayerController 既有 `seekBy(±SEEK_STEP_MS)` 防抖路径）；随后调用 `session.setMediaCenterControlType(['playPrevious', 'playNext', 'fastForward', 'rewind'])` 自定义按钮布局。效果（API 26+ 设备）：播控中心**二级界面（五元组）默认展示** 上一首/播放暂停/下一首/快退/快进——4 号位快退、5 号位快进即微调按钮；一级界面（三元组，audio 类型）因系统优先级（上一首 > 快退）保持 上一首/播放暂停/下一首。
- **Rationale**: 官方文档「自定义播控中心控制按钮显示布局」：API 26.0.0 起支持 setMediaCenterControlType；五元组 4/5 号位优先级 快退 > 循环模式 > 收藏 / 快进 > 收藏 > 倍速，本项目未注册循环/收藏/倍速，快进快退自动占位；项目 targetSdkVersion 恰为 26.0.0，无需升级 SDK。步长与播放页内 ±15s 按钮共用同一常量，复用 seekBy 防抖保证误差 ≤1 秒。
- **Alternatives considered**: ①改用 video 类型会话骗出快进快退按钮——会改变系统对应用的处理类别，否决；②仅注册监听不设布局——audio 类型下系统默认不展示快进快退（faqs-avsession-4：audio 控制元素固定为收藏/上一首/播放暂停/下一首/循环模式），不满足需求；③等待系统开放三元组自定义——audio 三元组优先级为系统硬规则，无法把一级界面也换成微调按钮，属已知限制。
- **降级方案**: compatibleSdkVersion 为 6.1.1(24)，API 24/25 设备上 `setMediaCenterControlType` 不存在：调用包裹 try/catch（TypeError 静默吞掉），fastForward/rewind 监听照常注册（对语音/投播等控制面仍有效），按钮不展示。**兼容守卫代码处加显式注释标记 `[API24-COMPAT]`**；在 PROJECT_NOTES.md「规划与预告」登记：**API 26 将作为未来兼容基线标准，届时全局检索 `[API24-COMPAT]` 标记统一移除兼容守卫**。

### D2 圆弧贴合播放按钮（US1）

- **Decision**: 播放按钮直径、加载弧线半径、常驻圆环半径**尺寸同源**：以单一常量（按钮直径 D）派生三者（弧线圆心 D/2、半径 D/2+2，Path 命令按常量计算生成，不再散落 88/72/36/44 等字面量）；弧线与按钮置于同一 Stack 且显式 `alignContent(Alignment.Center)` 保证同心；弧线与按钮边缘保留 ~2px 均匀呼吸间隙，消除"悬浮感"。
- **Rationale**: 现状弧线（88×88、半径 36）与按钮（72×72）各自硬编码，视觉间隙依赖数值巧合；同源后任何一者调整都不会脱节。
- **Alternatives considered**: 用 Progress 组件环形进度——前轮已证实 ProgressType.Arc 在当前 SDK 不可用（T013 偏差记录），继续用 Path。

### D3 空态占位（US2）

- **Decision**: 统一空态判定为「无当前曲目」：`trackIndex < 0 || playlistCount === 0`（现状为 `&&`，重启恢复歌单但未开播时会落入"显示残缺控件"的中间态）。PlayerOverlay 空态分支改为占位提示（"暂无播放内容"+引导文案，替换现"BiliRadio/未在播放"文案）；MiniPlayer 补 else 分支渲染占位条（占位封面 + "暂无播放内容"，点击唤起播放层），`AS_MINI_PLAYER_VISIBLE` 上报逻辑同步为占位条也可见（列表避让高度一致）。
- **Rationale**: 用户选择"显示占位提示"而非隐藏；两处展示位（迷你条+播放层）口径必须一致，否则一个显示残影一个显示占位。
- **Alternatives considered**: 无任务时彻底隐藏迷你条——用户明确否决（选择占位方案）。

### D4 下拉刷新禁用（US3）

- **Decision**: HomePage 的 Refresh 包裹层（L297-311）与 `manualRefresh()`、`refreshing` 状态整块**注释保留**，注释块头部加标记 `// [DISABLED 2026-10] 首页下拉刷新暂时禁用，恢复方式见 PROJECT_NOTES.md「已移除与禁用功能」`；List 本体照常渲染（去掉 Refresh 包装直接挂 layoutWeight(1)）。
- **Rationale**: 用户要求"注释掉"而非删除；显式恢复指引防止遗忘。`silentRefresh()`（aboutToAppear 静默刷新）**保留不动**——用户仅要求禁用"下拉"刷新。
- **Alternatives considered**: 用开关持久化控制——过度设计，用户只要临时禁用。

### D5 MorePage 删除（US4）

- **Decision**: 删除 `pages/MorePage.ets`；移除 `router_map.json` 中 morePage 条目；HomePage 右上角按钮（L276-289）onClick 改为 `pushPathByName('settingsPage', '')`。设置页已独立含播放历史（L1293）与关于（L1343）入口，功能零丢失。
- **Rationale**: 全局检索确认 morePage 引用仅 router_map + HomePage 两处，删除闭环；MorePage 本身只是三个转发条目，无自有业务。
- **Alternatives considered**: 保留文件不挂入口——留死代码违背用户"删除"决策。

### D6 队列标题两行（US5）

- **Decision**: QueueSheet 头部拆为两个 Row：标题行（"播放队列" + "共 N 首"）与操作行（定位/搜索/多选/清空）；多选模式行独立如旧。头部高度依赖既有 `onAreaChange → headerHeight` 动态测量 + 列表 `contentStartOffset(headerHeight)` 自动跟随，顶部渐变模糊 fractionStops 已按 headerHeight 比例计算，无需额外适配。
- **Rationale**: 纯布局改动；高度自适应机制已存在（前轮 US 留白改造引入），风险极低。
- **Alternatives considered**: 标题行与操作行合并为 Column+wrap——ArkUI Row 不自动换行，显式两行更可控。

### D7 单击条目仅入队单条（US6）

- **Decision**: SourcePage.`playEpisode(index)` 改为 `loadPlaylistAndPlay([this.episodes[index]], 0)`——队列空时该条成为队列并立即播放；队列非空时**追加到队尾不打断当前播放**（与既有"添加歌曲"语义一致）。"播放全部"按钮行为不变。同时在 PROJECT_NOTES.md「规划与预告」登记用户预告：列表添加逻辑后续还会改。
- **Rationale**: 复用既有方法零签名变更；单元素数组天然表达"仅此一条"；追加不打断与 QueueSheet 添加歌曲、playFromLibraryResult 的既有语义对齐。
- **Alternatives considered**: 新增 `playSingle(video)` 立即插播——改变"不打断当前播放"的既有语义，且用户预告列表逻辑还会重构，先不引入新 API。

### D8 播完列表即停（US7）

- **Decision**: 在 `handleCompleted` 内按模式拦截：SEQUENTIAL 且 `currentIndex >= len-1` → 停止（statusMsg='播放结束'，不回绕）；REVERSE 且 `currentIndex <= 0` → 停止；REPEAT_ONE 与 RANDOM 走原逻辑。`next()` 方法**完全不动**——手动点"下一首"仍取模回绕（用户主动行为）。停止时停留在 completed 状态（进度停在该曲末尾）。
- **Rationale**: 自动播完与手动切换是两个语义入口，只改自动入口，手动回绕是 spec 认可的预期行为；改动集中在 handleCompleted 一处，流式错误重试链路（onError 路径）不受影响。
- **Alternatives considered**: 给 next() 加 auto 参数区分来源——侵入两处调用点，收益相同，否决。

### D9 日志服务与钩子（US9）

- **Decision**: 新增 `service/Logger.ets`：内存环形缓冲（上限 `Constants.LOG_BUFFER_MAX = 500`），`LogEntry { time, category('net'|'error'), summary, result }`；静态方法 `log/snapshot/clear`。钩子挂在 BiliService 的 3 个 HTTP helper（httpGet/httpGetWithCookies/httpPostForm）+ resolveShortUrl + checkJsonBody 风控转换点：记录请求 URL（**截掉 query string 脱敏**，仅 host+path）、HTTP 状态码或异常摘要、风控命中事件；fetchUpInfo/fetchUpVideos 的 3 轮降级每轮成败也记一条（403 排查需要看轮次上下文）。日志写入全程 try/catch 静默（失败不影响主流程）。
- **Rationale**: 4 个请求入口覆盖全部网络流量；403 在 helper 的 `HTTP ${code}` 抛错点与风控页检测点集中转换，钩子点位最少而覆盖最全；query string 含 cookie/Token 必须脱敏。
- **Alternatives considered**: ①落盘文件日志——用户选择应用内日志页，且落盘涉及权限与清理策略，本轮不做；②挂 hilog 用 hdc 看——用户明确要应用内查询，否决。

### D10 日志页 UI（US9）

- **Decision**: SettingsPage 在「播放历史」条目之后新增「日志查询」条目（同款 Row 卡片，可带条数角标）；bindSheet（62%，与播放历史面板同构）承载新建组件 `LogSheet.ets`：顶部标题+计数+清空按钮，LazyForEach 列表逐条显示 时间/类别标签/摘要/结果码；`onBackPressed` 同步加关闭分支。
- **Rationale**: 完全复用 SettingsPage 既有面板模式（播放历史 bindSheet 62% 的成熟样板），新组件独立文件避免 SettingsPage 膨胀；LazyForEach 与 HistoryDataSource 同模式，条目轻量（纯文本）无封面解码压力。
- **Alternatives considered**: 独立路由页——导航层级加深一层，查询是低频动作，半模态足够。

### D11 封面下移与完整标题（US10）

- **Decision**: 封面容器 `margin({ top: 8 })` 调整为约 24（±8 视觉目测定值），其余布局不动；详情 sheet 标题去掉 `maxLines(2) + Ellipsis` 限制，允许完整换行显示（保留宽度 100% 居中样式），超长标题依赖 sheet 高度（62%）内自然滚动。
- **Rationale**: "下移一点"以视觉呼吸感为准；完整标题是 spec FR-012 的字面要求，收起态主标题仍保持单行省略不动。
- **Alternatives considered**: 标题加 marquee 跑马灯——动态效果干扰阅读，完整换行更符合"显示完整标题"。

### D12 常量收敛（顺带）

- **Decision**: `SEEK_STEP_MS`（PlayerOverlay L23）、`SEEK_BY_DEBOUNCE_MS`（PlayerController L33）迁入 Constants.ets 魔法数字区（MediaSession 微调与播放页按钮共用同一 SEEK_STEP_MS）；新增 `LOG_BUFFER_MAX = 500`。
- **Rationale**: Constants.ets 头注释明确约定全库魔法数字集中管理；±15 秒步长将被两处引用，必须单一来源。
- **Alternatives considered**: 各文件保留本地常量——违反项目既有约定，且步长会两处漂移。

### D13 PROJECT_NOTES.md 重构（US11）

- **Decision**: `git mv KNOWN_ISSUES.md PROJECT_NOTES.md` 保留历史；重构三章：**①已知问题**（KI-1~KI-4 原样迁移）**②已移除与禁用功能**（下载页三文件 @6d403dd、folders 页/列表同步/封面染色 @2050b84、首页下拉刷新 @本轮禁用——每条含位置/原因/恢复线索）**③规划与预告**（列表添加逻辑重构预告、403 首次添加根因修复（本轮仅日志观察）、音质选择/默认音质、点赞/投币/收藏、历史云端同步、播控中心 API<26 无自定义布局限制、audio 三元组优先级限制、**API 26 基线化后移除 `[API24-COMPAT]` 守卫**）。本轮各故事的禁用/降级项（US3/US8）实现时同步登记。
- **Rationale**: git mv 保留 blame 历史；三章结构覆盖"问题-移除-规划"三类登记需求，用户点名要求。
- **Alternatives considered**: 保留原名单加章节——用户明确要求改名。

## Data Model

```text
LogEntry（日志条目，仅内存，不持久化）
├── time: number          // 毫秒时间戳
├── category: string      // 'net'（网络请求）| 'error'（错误/风控）
├── summary: string       // host+path 摘要（已截掉 query string）或事件名
└── result: string        // 'HTTP 200' / 'HTTP 403' / 错误摘要 / '风控页' 等

Logger（service/Logger.ets，静态方法，全库单点）
├── entries: LogEntry[]   // 环形缓冲，超限淘汰最旧（上限 Constants.LOG_BUFFER_MAX=500）
├── log(category, summary, result): void     // 追加+淘汰；内部 try/catch 静默
├── snapshot(): LogEntry[]                   // 返回拷贝（UI 渲染源）
├── count(): number
└── clear(): void

EmptyPlayerState（空态判定，无新实体——统一口径）
└── 无播放任务 := trackIndex < 0 || playlistCount === 0（PlayerOverlay 与 MiniPlayer 共用）
```

## Contracts & Interfaces

```text
【新增】service/Logger.ets
  Logger.log(category: string, summary: string, result: string): void
  Logger.snapshot(): LogEntry[]            // LogEntry 为 exported class/interface
  Logger.count(): number
  Logger.clear(): void
  约束：纯内存、无 IO、写入失败静默；被 BiliService / SettingsPage(LogSheet) 引用

【修改】service/MediaSession.ets（init 签名扩展）
  init(context, callbacks): 新增两个回调槽位 onFastForward: () => void、onRewind: () => void
  init 内部：session.on('fastForward', onFastForward) / session.on('rewind', onRewind)
            try { session.setMediaCenterControlType(['playPrevious','playNext','fastForward','rewind']) } catch { /* API<26 静默降级 */ }
  既有 updateTrack/updateState/startBackground/stopBackground 语义不变

【修改】service/PlayerController.ets
  handleCompleted(): internal 行为变更（SEQUENTIAL/REVERSE 到末尾即停）；公开签名不变
  init 时向 MediaSession 传入 seekBy(+SEEK_STEP_MS) / seekBy(-SEEK_STEP_MS) 作为微调回调
  既有公开方法（loadPlaylistAndPlay/next/prev/seekBy/playIndex...）签名与语义全部不变

【修改】pages/SourcePage.ets
  playEpisode(index): 调用 loadPlaylistAndPlay([episodes[index]], 0)（单条入队）

【修改】service/BiliService.ets
  httpGet/httpGetWithCookies/httpPostForm/resolveShortUrl/checkJsonBody: 内部追加 Logger.log 调用；签名与抛错语义不变

【修改】service/Constants.ets
  +SEEK_STEP_MS = 15000（自 PlayerOverlay 迁入）
  +SEEK_BY_DEBOUNCE_MS = 250（自 PlayerController 迁入）
  +LOG_BUFFER_MAX = 500

【新增】component/LogSheet.ets
  @Component LogSheet：无入参 props，内部 aboutToAppear 读 Logger.snapshot() 订阅刷新；
  对外仅被 SettingsPage 的 bindSheet builder 引用

【删除】pages/MorePage.ets + router_map.json morePage 条目 + HomePage 跳转改 settingsPage

【文档】KNOWN_ISSUES.md → PROJECT_NOTES.md（git mv + 三章重构，见 D13）
```
