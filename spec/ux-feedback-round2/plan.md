# Implementation Plan: 第二轮体验反馈批次（ux-feedback-round2）

**Input**: Feature specification from `spec/ux-feedback-round2/spec.md`

## Summary

本轮包含四个层面：(1) **订阅可靠性修复**——查询 UP 主接口增加风控重试/降级链并透出真实错误码（最先实现）；(2) **音频流式边下边播**——AVPlayer 以带 Referer/UA 请求头的 MediaSource 直播 CDN 直链，本地缓存优先（用户要求最后实现）；(3) **播放页视觉完整性**——主题色全量接入（衍生色运行时计算）、留白铺满、全部文字按钮图标化、缓冲弧线动画→常驻装饰圆环、展开箭头加大与即时反转、详情简介懒加载、队列「完成」按钮移除；(4) **全局收尾**——独立"更多"页直达、播放历史背景与详情一致、自动播放默认关闭、恢复进度文案移除。执行顺序：修订阅 bug → 其他故事 → git 基线提交 → 流式压轴。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，compatibleSdkVersion 6.1.1(24) / targetSdkVersion 26.0.0）
**Primary Dependencies**: @kit.MediaKit（media.AVPlayer / createMediaSourceWithUrl / setMediaSource，API 12+ 已确认支持自定义 HTTP 请求头与 PlaybackStrategy 缓冲策略）、@kit.NetworkKit（http）、bindSheet shouldDismiss（API 12+）
**State Management**: 既有 State Management V1 全套保留（@StorageLink/@StorageProp/@State/@Builder），增量改动不迁移 V2
**Storage**: Preferences（biliradio_store，复用 autoPlayOnStart/accentColor 键）+ 既有音频缓存文件目录（只读复用，不再新增写入）
**Testing**: 无自动化测试；验证 = devecocli build + arkts_check（Phase 3 与用户确认范围）
**Target Platform**: HarmonyOS 手机
**Project Type**: 移动应用（既有工程增量改动）
**Performance Goals**: 未缓存曲目点播出声 ≤10s；已缓存 ≤2s；弧线动画 60fps 无卡顿
**Constraints**: 服务层既有公开方法语义不变（新增方法为纯增量）；不新增持久化键（复用既有）；深浅色双模式均正确；上一轮全部功能零回退
**Scale/Scope**: 涉及 8 个既有文件 + 2 个新文件；9 个用户故事

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round2/
├── spec.md              # 需求规格（19+1 个 FR、9 个用户故事）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 生成
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── PlayerOverlay.ets      # 主题色/留白/图标化/箭头/弧线/简介懒加载（US3/4/5/6）
│   ├── HomePage.ets           # 右上角按钮加大直达更多页，删除弹菜单（US7）
│   ├── MorePage.ets           # 【新建】独立"更多"页（US7）
│   └── SettingsPage.ets       # 播放历史 bindSheet 化、自动播放默认值（US8/9）
├── component/
│   └── QueueSheet.ets         # 移除「完成」按钮（US4/FR-020）
├── service/
│   ├── BiliService.ets        # fetchUpInfo 风控重试降级、lastError 修复、resolveAudioUrl（US1/2）
│   ├── AudioPlayer.ets        # 流式数据源（setMediaSource+headers）（US2）
│   ├── PlayerController.ets   # playIndex 缓存优先/流式分支、默认值、文案移除（US2/9）
│   └── Appearance.ets         # 主题色衍生色计算工具（US3）
└── resources/base/profile/
    └── router_map.json        # morePage 路由注册（US7）
```

**Structure Decision**: 遵循既有工程架构（pages/component/service/model 分层），纯增量改动，不引入 MVVM 目录、不迁移 State Management V2。新建文件仅 2 个：MorePage.ets（独立路由页必须单独文件）与 router_map.json 条目（若工程已有路由表则追加条目，实现时确认）；衍生色工具并入现有 Appearance.ets 不新建文件。

## Complexity Tracking

无 Constitution Check 违规，无需豁免说明。

## Research & Decisions

### R1: 订阅失败根因与修复策略（US1）

**Decision**: 将 `fetchUpVideos` 已验证有效的多轮降级模式移植到 `fetchUpInfo`：N 轮循环（建议 3 轮），每轮先 WBI 签名的 acc/info、失败后 card 兜底；错误分类为可重试（-352/-412/非 JSON 风控页）与不可重试（-404/-400/-101）；可重试错误触发"重置 buvid + 指数退避"后进入下一轮；全部失败时抛出**最后一轮的真实错误**（含错误码）。
**Rationale**: 用户报错文案为"查询UP主失败，请稍后重试"，定位到 acc/info 是风控重灾区且当前无重试；fetchUpVideos 的同型策略已在生产验证有效。同时修复两个掩盖根因的缺陷：fetchUpVideos 的 `lastError` 初始化后永不赋值（恒报 unknown）；checkJsonBody 抛出的风控页错误不进降级链。
**Alternatives considered**: 仅加大超时（无效，风控非超时问题）；接入 gRPC app 接口（改动过大，超出本轮范围）。

### R2: 音频流式边下边播架构（US2，用户要求最后实现）

**Decision**: 三层改造：
- **AudioPlayer**：保留本地 fdSrc 路径签名不变，新增远程流式数据源方法——用 `media.createMediaSourceWithUrl(url, { 'Referer': 'https://www.bilibili.com', 'User-Agent': <桌面UA> })` 构造 MediaSource，`setMediaSource(mediaSource, { preferredBufferDuration: 3~5s })` 开播；AVPlayer 原生按 Range 分段拉取，seek 由内核处理。
- **BiliService**：新增 `resolveAudioUrl(bvid)`——复用 fetchVideoInfo 取 cid + fetchDashAudioCandidates 的 URL 收集与 mcdn 过滤逻辑，仅返回直链+备选列表不做下载；整段下载方法（downloadToFile/downloadFirstSuccess）从播放链路退役。dash 兜底逻辑保留：dash 失败时返回 durl 候选。
- **PlayerController.playIndex**：缓存优先——`cacheDir/{bvid}.m4a` 存在即走本地播放（现状路径保留）；否则 resolveAudioUrl → 流式开播；网络失败自动重试（先同 URL 重试一次，再轮换 backupUrl），彻底失败时状态行提示且队列与播放列表状态不破坏。
**Rationale**: PiliPlus 调研确认流式+播放器级自定义头是成熟方案；鸿蒙官方文档确认 AVPlayer API 12+ 支持 HTTP 请求头与缓冲策略，无需本地代理。切歌/重播即取新 URL 规避 expires，与 PiliPlus 一致。既有缓存文件只读复用，兑现"缓存优先秒播"承诺。
**Alternatives considered**: 本地 HTTP 代理（PiliPlus 证明非必须，增加复杂度）；边播边后台整段下载做新缓存（用户已接受"无新磁盘缓存"取舍）。

### R3: 主题色接入与衍生色运行时计算（US3）

**Decision**: PlayerOverlay 增加 `@StorageProp('accentColor')`（string，默认 ACCENT_DEFAULT）；在 Appearance.ets 增加纯函数工具"hex 色 + alpha → 8 位 ARGB 字符串"；播放页全部着色点改为运行时取色——进度条 selected/block、播放键底色（material_tint 对应 alpha）、激活态文字、面板选中态、光晕梯度（halo_0..3 的 alpha 序列）、播放键阴影（shadow alpha）、弧线与装饰圆环。alpha 值沿用现有资源键的取值（base/dark 相同），仅色相由固定粉改为运行时主题色。
**Rationale**: 主题色系统是 AppStorage 字符串驱动（六色板），$r 编译期资源无法运行时替换，必须运行时计算；沿用既有 alpha 保证深浅色观感连续性，避免重新设计色彩系统。
**Alternatives considered**: 为六色板各生成全套资源键（36+ 键，维护成本高且色板扩展即爆炸）；仅改主色不改衍生色（光晕/阴影残留粉色，用户明确要求全量）。

### R4: 播放页留白铺满（US3）

**Decision**: 信息区 Scroll 内的根 Column 增加 `constraintSize({ minHeight: '100%' })` + `justifyContent(FlexAlign.SpaceBetween)`，内容不足一屏时自动拉开分布；内容超出时 Scroll 滚动能力保留（minHeight 不影响内容溢出）。封面固定 top margin 32 改由分布逻辑接管（移除大固定间距，保留小基础间距）。
**Rationale**: 用户选择"拉开内容间距铺满"方案；SpaceBetween 在首尾贴边的同时最大化中间间距，与底栏衔接自然。
**Alternatives considered**: 内容垂直居中（用户未选）；放大封面（用户未选）。

### R5: 全部文字按钮图标化（US4）

**Decision**: 逐一映射（SymbolGlyph 优先，SDK 缺资源时降级文字胶囊，沿用 ±15s 按钮的既有降级模式）：上一首/下一首 → backward_end/forward_end 类系统符号；播放/暂停主键 → play/pause 填充符号（替换文字 Button，保留 72×72、底色、阴影、缩放动画）；倍速 → 仪表类符号+速率短文字（如 "1.5x"，速率值必须可见）；播放模式 → 四模式映射符号（随机=shuffle 类、单曲循环=repeat_1 类、倒序与顺序取循环箭头类符号，实现时按 SDK 符号表最终确认）；定时 → 时钟类符号，激活态旁挂剩余时间短文字；封面角"播放视频" → 播放矩形类符号+短文字"视频"。全部保留按压动画、置灰门控、点击行为与激活态 accent 着色。
**Rationale**: 全图标化统一视觉语言；速率/剩余时间属于动态数值信息，纯图标无法表达，采用"图标+极简文字"组合（spec 已允许）。
**Alternatives considered**: 纯图标不带文字（速率与倒计时信息丢失）。

### R6: 详情箭头加大与即时反转（US4）

**Decision**: 箭头图标 fontSize 12→16，外包裹点击热区扩大至约 40×40vp（padding 扩大），整行点击打开行为保留；箭头旋转角度改绑独立 @State（不再直接绑 showDetail），bindSheet 增加 shouldDismiss 回调（API 12+）——手势下滑判定通过时立即翻转箭头状态并调用 dismiss 关闭；点遮罩/关闭路径同样即时。
**Rationale**: 现状绑 `$$showDetail` 要等退场动画结束才回写导致观感延迟；shouldDismiss 在手势确认关闭的最早期触发，是官方推荐挂载点（SDK 版本满足）。
**Alternatives considered**: onDisappear 回调（时序上晚于 shouldDismiss，仍有可感延迟）。

### R7: 详情简介懒加载（US6）

**Decision**: 打开详情入口处（置 showDetail=true 的同时）检查：trackDesc 为空且 trackBvid 非空 → 调用既有 `BiliService.fetchVideoInfo(bvid)` 取 desc 回填 trackDesc（该 @State 已驱动详情简介区刷新）；加成员标志防并发重复拉取；失败静默（保留"暂无简介"占位，无 toast）。已有简介不发起请求。
**Rationale**: fetchVideoInfo 是播放链路已在用的公开方法，语义不变仅复用；desc 字段链路（模型/序列化/UI 绑定）已完整，只缺"未播放曲目的填充时机"。
**Alternatives considered**: 入队时批量预取 desc（订阅列表接口不含 desc，需逐集请求，配额浪费）。

### R8: 缓冲弧线动画与常驻装饰圆环（US5）

**Decision**: 播放键外扩一个约 88×88vp 的 Stack 区域：缓冲中（isPreparing && playWhenReady）渲染弧线组件（ProgressType.Arc 或 Path 弧）+ 持续旋转动画（360° 循环），弧线颜色 = 主题色；缓冲结束弧线淡出、同位置淡入低透明度（约 0.15~0.25 alpha）完整圆环常驻装饰；再次缓冲时弧线重现。旋转与淡入淡出均用 animateTo 过渡，颜色走 R3 主题色链路。
**Rationale**: 用户确认"缓冲指示弧线（不确定旋转）+ 常驻装饰圆环"方案；围绕核心操作按钮的加载指示同时提供进度感知与视觉品质。
**Alternatives considered**: 弧度=下载百分比（流式模式下无整段百分比，已被用户否决）。

### R9: 独立"更多"页与首页直达（US7）

**Decision**: 新建 MorePage.ets 作为 NavDestination 目标页（系统路由表注册：router_map.json 追加 morePage 条目 + 页面文件导出 @Builder 构建函数）；页内列表三项：设置/播放历史/关于，复用既有 `pushPathByName('settingsPage', param)` 参数直开机制；HomePage 右上角按钮 34×34→40×40（SymbolGlyph 18→22），onClick 改为直接 pushPathByName('morePage')，删除 morePopupContent 与 bindPopup 弹菜单。左上角 + 按钮同步加大到 40×40 保持对称。
**Rationale**: "更多页"为后续功能扩展提供挂载点；系统路由表是工程规范优先方案；两个顶栏按钮对称加大避免大小不一。
**Alternatives considered**: 保留弹菜单仅加大按钮（用户明确要"直接打开更多页"）。

### R10: 播放历史背景与详情一致（US8）

**Decision**: SettingsPage 的 playHistoryPanel 从全屏 Stack 覆盖层改为 bindSheet 呈现（height '62%' 与详情一致、backgroundColor sheet_background、dragBar、preferType BOTTOM），面板内容与既有逻辑（列表/清空/状态行）原样迁移；参数直开机制（'playHistory'）保留，收到参数时置 sheet 开关为真。取消收藏历史面板（historyPanel）不在本轮范围，保持现状。
**Rationale**: bindSheet 的"双层背景+系统遮罩"正是详情页观感的来源，覆盖层无法等效复刻遮罩层级；62% 高度与详情完全对齐达成"一致"验收标准。
**Alternatives considered**: 覆盖层加 backdropBlur 微调（遮罩层级观感仍不一致）。

### R11: 自动播放默认关闭与文案移除（US9）

**Decision**: 两处默认值 1→0（PlayerController.init 的 getNumber 与 SettingsPage 读取处），已持久化用户不受影响；删除 PlayerController 恢复进度时的 statusMsg 赋值（"已恢复上次进度，点击播放继续"），恢复能力（lastIndex/lastPosMs）与自动播放开启时的"自动继续播放上次进度"文案保留。
**Rationale**: 纯默认值翻转与一处赋值删除，风险极低；其余恢复逻辑不动。
**Alternatives considered**: 无（用户指令明确）。

### R12: git 基线提交（流程约束）

**Decision**: Phase 4 实现子代理在完成 US1 订阅修复与全部其余故事（US3-US9）之后、开始 US2 流式改造之前，执行 git 提交：提交当前工作区全部改动（上一轮 player-redesign 的源码改动 + spec/ 文档 + 本轮订阅修复与全部 UI/UX 改动）。提交后才开始流式播放相关代码修改。
**Rationale**: 用户明确要求的执行顺序（修 bug → 其他故事 → git 基线 → 流式压轴）；git 提交作为分水岭，将非流式改动整体入库，为流式播放这一最大架构改动提供干净的可回退基线。

## Data Model

无新增持久化实体。运行期新增概念：

- **音频播放源（联合形态，无新类文件）**: `本地缓存文件路径` 或 `远程直链 + 请求头(Referer/User-Agent) + 缓冲策略(preferredBufferDuration)`；由 PlayerController.playIndex 按缓存存在性择一，AudioPlayer 透明消费。直链不持久化（每次点播现取）。
- **主题色衍生色**: 纯函数计算结果——输入 hex 主题色 + alpha 序列（沿用现有资源键 alpha），输出 8 位 ARGB 字符串；无状态、不缓存。
- **订阅查询重试上下文**: fetchUpInfo 内部局部状态（轮次计数、可重试标记、累积错误），不跨调用持久化。

## Contracts & Interfaces

**BiliService（既有类，公开面增量）**
- `fetchUpInfo(mid: number): Promise<BiliUpInfo>`——签名不变，内部增强为多轮风控重试+card 降级，失败时抛出含真实错误码的 Error。
- `resolveAudioUrl(bvid: string): Promise<string[]>`——【新增】返回直链+备选列表（dash 优先，durl 兜底，已过滤 mcdn）；不做下载。
- `fetchVideoInfo(bvid: string): Promise<BiliVideo>`——签名与语义完全不变（R7 复用取 desc）。
- `fetchUpVideos`——签名不变，修复 lastError 透出真实错误；checkJsonBody 风控错误纳入其降级链。

**AudioPlayer（既有类，公开面增量）**
- 本地播放路径签名不变（fdSrc）。
- 【新增】远程流式数据源设置：入参为直链 + 请求头映射；内部走 createMediaSourceWithUrl + setMediaSource（含缓冲策略）；prepared/error 等回调链路复用既有订阅机制。

**PlayerController（既有类）**
- `playIndex` 行为契约升级：缓存文件存在 → 本地播放；否则流式。对外方法签名全部不变。
- 状态行文本：解析/缓冲期间显示缓冲态文案；"正在加载音频... x%"下载百分比消息退役。

**Appearance（既有类，增量）**
- 【新增】hexWithAlpha(hex: string, alpha: number): string 纯函数（或同级静态方法）——主题色衍生色计算唯一入口。

**UI 契约**
- PlayerOverlay：@StorageProp('accentColor') 接入；所有着色点经衍生色工具取色；箭头角度独立 @State；详情打开时触发 R7 懒加载。
- QueueSheet：顶栏「完成」按钮删除，遮罩关闭链路不动。
- HomePage：右上角 onClick → pushPathByName('morePage')；morePopupContent/bindPopup 删除。
- MorePage【新页面】：NavDestination 根节点；三项入口 → settingsPage + 参数直开（复用既有 onReady param 机制）。
- SettingsPage：playHistoryPanel 改 bindSheet 呈现；自动播放 Toggle 默认值同步改 0。
- router_map.json：追加 morePage 条目（若工程尚无路由表文件则新建并在 module.json5 挂载）。

**执行顺序约束（用户要求，强约束）**: ① US1 订阅修复最先实现；② 其余故事（US3-US9）按依赖顺序实现；③ 全部非流式改动完成后执行 R12 git 基线提交；④ US2 流式播放相关任务（R2）最后实现，作为实现阶段的收官批次。
