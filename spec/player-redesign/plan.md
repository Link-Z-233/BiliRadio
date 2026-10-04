# Implementation Plan: 播放页重新设计（player-redesign）

**Input**: Feature specification from `spec/player-redesign/spec.md`

## Summary

参考 PiliPlus「听音频」页布局重组 BiliRadio 全屏播放页（PlayerOverlay）：顶栏仅剩收起按钮；信息区（16:9 封面+光晕、标题行+详情箭头、UP 行、新增播放量/发布时间统计行）独立滚动；进度条改为细条样式并把时间行下移分列；控制栏重组为传输五键（上一首/◀◀15s/播放暂停/15s▶▶/下一首）；底部操作行收纳倍速/播放模式/定时/队列按钮（沿用现有选择面板）；移除取消收藏入口与"正在播放"标题。服务层仅新增 `PlayerController.seekBy(offsetMs)` 辅助方法（±15s 微调用，含钳制与连按合并），其余接口语义零变更。全量保留鸿蒙特色（SymbolGlyph、bindSheet、毛玻璃、下拉关闭手势、深浅色资源）与现有动效（呼吸光晕、按压动画）。

## Technical Context

**Language/Version**: ArkTS（API 12+，DevEco Studio 工程）  
**Primary Dependencies**: @kit.AbilityKit（Want/上下文）、@kit.BasicServicesKit（BusinessError）、系统 ArkUI 组件（Slider/SymbolGlyph/bindSheet/Scroller 等）、既有服务层（PlayerController/AudioPlayer/MediaSession/SleepTimerController/AppStore/Constants）  
**State Management**: 保留项目现有 State Management V1（@State/@StorageLink/@StorageProp + 单例订阅回调同步）。本次为渐进式改版，不迁移 V2。  
**Storage**: 沿用 AppStore（Preferences + JSON 文件）持久化；本次不新增持久化键。  
**Testing**: 无自动化测试框架；验证依赖 `devecocli build` + 模拟器/真机手工验证（Phase 5）。  
**Target Platform**: HarmonyOS（phone），深浅色双模式，后台音频播放（backgroundModes: audioPlayback）。  
**Project Type**: 既有 HarmonyOS 应用（BiliRadio）的页面级重构。  
**Performance Goals**: 打开播放页 1 秒内完成首帧渲染；进度/时间刷新不丢帧（沿用现有秒级节流）。  
**Constraints**: 服务层既有接口语义不可变更；现有功能零回退（除取消收藏入口按用户决策移除）；深浅色资源双份覆盖。  
**Scale/Scope**: 单页面（PlayerOverlay.ets）重写 + PlayerController.ets 增量修改；约 1000 行 UI 代码。

## Project Structure

### Documentation (this feature)

```text
spec/player-redesign/
├── spec.md              # 需求规格（Phase 1 产出）
├── plan.md              # 本文件（Phase 2 产出）
└── tasks.md             # 任务拆分（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── PlayerOverlay.ets      # 【重写布局】播放页：顶栏精简/信息区/细进度条/传输五键/底部操作行
│   └── ...（Index/HomePage/SourcePage/SettingsPage/AddSubscriptionSheet 不动）
├── service/
│   ├── PlayerController.ets   # 【增量修改】新增 seekBy(offsetMs) 公开方法（钳制+连按合并）
│   └── ...（AudioPlayer/MediaSession/SleepTimerController/AppStore/Constants 不动）
├── component/
│   ├── QueueDrawer.ets        # 不动（原样复用）
│   ├── QueueSheet.ets         # 不动（原样复用）
│   └── ...（CoverThumb/MiniPlayer 不动）
└── model/
    └── BiliVideo.ets          # 不动（view/pubdate 字段已存在）

entry/src/main/resources/
├── base/element/color.json    # 【可能微调】如需新颜色资源（现有资源优先复用）
└── dark/element/color.json    # 同步双份
```

**Structure Decision**: 遵循项目既有架构——播放页为单文件大组件（pages/PlayerOverlay.ets，当前 1030 行），服务/组件/模型目录职责不变。本次不引入 MVVM 目录、不拆分新组件文件：改版为单页面布局重组，拆分会增加跨文件状态传递（V1 状态需 @Link/@Prop 链路）而无实际收益；选择面板 @Builder（speedPanel/modePanel/sleepTimerPanel/sleepTimerPicker）与 QueueDrawer 在文件内/既有组件原样复用。服务层仅做加法（seekBy），符合 spec 的 FR-011 约束。

## Complexity Tracking

无 Constitution 违规需要豁免。（单文件页面布局重组 + 单服务方法新增，复杂度可控。）

## Research & Decisions

### R1: 布局骨架——控制区固定 vs 全页滚动

- **Decision**: 采用「固定底栏」结构：`Column { 顶栏; Scroll(信息区).layoutWeight(1); 进度条行; 时间行; 控制栏; 底部操作行; statusMsg }`。信息区（封面/标题行/UP 行/统计行）独立滚动，进度与控制区常驻屏幕底部。
- **Rationale**: PiliPlus AudioPage 同样把进度/控制固定在底部（body: Column[Expanded(info), progress, duration, controls]）；小屏或大字号时控制键不因内容过长被滚出视口，播放控制始终可达。现有 `PLAYER_DISMISS_SWIPE` 下拉关闭手势依赖 `contentScroller` 是否在顶部——信息区独立滚动后该判定依然成立（且面板打开时仍纳入 `noOverlayOpen` 判断）。
- **Alternatives considered**: 保持现状全页单 Scroll——控制键可能滚出视口，不符合参考布局层级，弃用。

### R2: 空态分支

- **Decision**: 空态（trackIndex<0 && playlistCount===0）沿用现有空态引导文案，且隐藏全部固定底栏（进度/控制/操作行），仅显示顶栏收起按钮与空态内容。
- **Rationale**: 空态下控制键全部置灰无意义，参考布局的控件常驻仅对"有曲目"状态有意义。
- **Alternatives considered**: 保留置灰底栏——视觉噪音，弃用。

### R3: ±15s 微调的实现位置与连按合并策略

- **Decision**: 在 `PlayerController` 新增公开方法 `seekBy(offsetMs: number)`：目标位置 = clamp(currentTime + offsetMs, 0, duration)；立即更新 `currentTime`（乐观更新，UI 即时反馈），实际 `player.seek` 用约 250ms 防抖合并连续点击；防抖期间新点击基于已更新的 `currentTime` 继续叠加，防抖到期执行最终一次 seek。
- **Rationale**: 现有 `seek(ms)` 同步设置 `currentTime` 再调 `player.seek`（PlayerController.ets L665-668），乐观更新模式与现状一致；防抖避免连按造成 AVPlayer seek 风暴。UI 侧无需额外节流逻辑，滑块/时间行经现有 subscribe→syncFrom 链路自动刷新（currentTime 变化即时可见）。
- **Alternatives considered**: 每次点击直接 `player.seek`——连按 5 次触发 5 次 AVPlayer seek，可能产生音频卡顿，弃用；UI 侧累积再提交——状态分散到页面层、切页后丢失，弃用。

### R4: ±15s 按钮图标

- **Decision**: 优先使用 SymbolGlyph 系统符号（如 `sys.symbol.gobackward_15` / `sys.symbol.goforward_15`）；若当前 SDK 资源不存在该符号，降级为「文字+箭头」小胶囊按钮（如 `◀ 15s` / `15s ▶`）。
- **Rationale**: 鸿蒙 SymbolGlyph 符号库版本差异较大，实现阶段以编译/预览实际可用性为准；降级方案视觉上仍与毛玻璃胶囊风格统一。
- **Alternatives considered**: 强行引入自定义 SVG/图片资源——增加资源维护成本，无必要，弃用。

### R5: 细进度条样式落地

- **Decision**: 继续使用系统 `Slider`，通过 `.trackThickness(5)` + `.blockSize(12)` 达到「轨道高约 5vp、圆点直径约 12vp」的细条样式；配色沿用 `track_color`/`primary_color` 资源；受控值 + `isSeeking` 防回弹逻辑原样保留；时间行移到进度条下方独立 Row（左当前时间、Blank、右总时长，时长文案 13vp 次要色，拖拽中左侧实时显示拖拽位置）。
- **Rationale**: 系统 Slider 属性即可满足参考样式，无需自绘；防回弹是既有成熟逻辑（sliderValue 受控 + isSeeking 门控 syncFrom 更新），迁移零风险。
- **Alternatives considered**: 自绘进度条（Stack+Rect+PanGesture）——可定制性高但重造轮子，与"保留鸿蒙特色"相悖，弃用。

### R6: 倍速/模式/定时/队列入口迁移方式

- **Decision**: 底部操作行四个按钮直接复用现有实现：倍速按钮（显示 `倍速 x.xx`，非 1.0 时 accent 色）→ 现有 `speedPanel()` 浮层；模式按钮（显示当前模式名）→ 现有 `modePanel()`；定时按钮（未开启显"定时"，激活显剩余倒计时并 accent 色）→ 现有 `sleepTimerPanel()` + `sleepTimerPicker()`；队列按钮（SymbolGlyph list_bullet 圆形底）→ `AS_SHOW_QUEUE_SHEET` 打开 QueueDrawer。四个 `@StorageLink` 开关与浮层 @Builder 全部保留不动。
- **Rationale**: spec 明确"沿用现有选择面板，仅迁移按钮位置"；浮层与开关是成熟逻辑且属鸿蒙特色浮层交互，原样复用使回归风险最小。
- **Alternatives considered**: 新造 bindSheet 设置弹窗——已在需求讨论中由用户否决，弃用。

### R7: 取消收藏入口移除的落地方式

- **Decision**: 删除播放页"取消收藏"按钮及配套 `@State canUnfavorite` 状态与 `syncFrom` 中对它的赋值；`PlayerController.unfavoriteCurrent()/refavoriteFromHistory()/clearUnfavoriteHistory()` 等服务层能力原样保留。
- **Rationale**: 死状态不应留在页面；服务层保留使后续轮次回归零成本（FR-008/FR-010）。
- **Alternatives considered**: 保留状态仅隐藏按钮——残留无效同步代码，弃用。

### R8: 统计行数据来源

- **Decision**: 信息区新增统计行复用 `syncFrom` 已同步的 `trackView`/`trackPubdate` 与现有格式化方法 `formatCount()`/`formatPubDate()`，文案形如 `播放 1.2万 · 2026-09-30 14:00`（次要色 12vp）。
- **Rationale**: 数据与格式化逻辑均为现成能力，信息区展示是纯增量 UI。
- **Alternatives considered**: 不加统计行——已被 spec FR-003 明确要求，不适用。

### R9: 详情入口与标题行

- **Decision**: 标题行保留现有结构（标题 layoutWeight + 行尾 `▼` 小箭头，箭头随 showDetail 旋转 180°），整行点击打开现有 `bindSheet` 详情半模态（62% 高，内容不变）。去掉行高定值改为自适应，超长标题仍 2 行截断。
- **Rationale**: 与现有交互一致，仅视觉微调；详情 Sheet 内容零改动。
- **Alternatives considered**: 仅箭头可点——缩小热区无收益，弃用。

### R10: 状态提示与加载指示的落位

- **Decision**: `statusMsg` 固定显示在底部操作行下方（居中、13vp、最多 2 行）；`isPreparing` 时在同一行左侧或紧邻位置显示小号 `LoadingProgress`。二者常驻可见，不再随内容滚动。
- **Rationale**: 下载/解析进度提示（statusMsg）是纯听场景的核心反馈，固定底栏保证任何滚动位置都可见；与 R1 固定底栏结构一致。
- **Alternatives considered**: 保留在滚动区底部——内容长时提示不可见，弃用。

## Data Model

本次不新增/不修改任何持久化数据实体。涉及的既有运行时状态：

| 状态 | 来源 | 改版后用途 | 变化 |
|------|------|-----------|------|
| isPlaying/isPrepared/isPreparing/playWhenReady | PlayerController | 光晕呼吸、播放键图标/置灰、加载指示 | 不变 |
| currentTime/duration/sliderValue/isSeeking | PlayerController | 细进度条、时间行 | 不变（受控逻辑保留） |
| trackTitle/trackCover/ownerName/ownerFace/trackBvid/trackIndex/playlistCount | PlayerController 快照 | 信息区展示 | 不变 |
| trackView/trackPubdate | PlayerController 快照 | 新增统计行（原本仅详情 Sheet 用） | 展示位置新增 |
| playMode/playbackRate | PlayerController | 底部操作行按钮文案/浮层选中态 | 不变 |
| sleepTimerActive/sleepTimerRemaining | SleepTimerController | 底部操作行定时按钮文案 | 不变 |
| canUnfavorite | PlayerController 快照 | 无 UI 消费 | **页面内删除**（服务层保留） |
| showDetail | 页面本地 | bindSheet 详情 | 不变 |
| showSpeed/showMode/showSleepTimer/showSleepTimerPicker/showQueueSheet | AppStorage | 浮层/队列开关 | 不变 |
| glowStrength/playBtnScale/prevBtnScale/nextBtnScale | 页面本地 | 光晕呼吸、按压动画 | 不变（新增 ±15s 键如需按压反馈可复用同模式） |

新增常量（PlayerOverlay.ets 文件级）：`SEEK_STEP_MS = 15000`（±15s 微调步长，固定不可配置）。

## Contracts & Interfaces

### 服务层唯一新增接口

`PlayerController.seekBy(offsetMs: number): void`
- 行为：目标 = clamp(currentTime + offsetMs, 0, duration)；duration<=0 或未 prepared 时直接返回；立即更新 this.currentTime 并 refreshUi()；以约 250ms 防抖将最终目标提交 `player.seek`；防抖期间连续调用基于最新 currentTime 叠加。
- 约束：不改变既有 `seek(ms)` 语义；不新增持久化。

### 页面 UI 结构契约（PlayerOverlay.build 重组后）

```
Stack
├── Column
│   ├── 顶栏：仅 [▼收起]（statusBarHeight 内边距）
│   ├── if 空态: 空态引导（占满剩余空间，无底栏）
│   └── else:
│       ├── Scroll(contentScroller)  ← layoutWeight(1)，仅信息区滚动
│       │   └── Column(居中)
│       │       ├── 封面块：光晕 + 16:9 300×188 封面（含右下角"播放视频"按钮、缩放动画）
│       │       ├── 标题行：标题(layoutWeight) + ▼箭头（点击→详情Sheet）
│       │       ├── UP行：头像22 + UP名 + Blank + n/total
│       │       └── 统计行：播放 n · 发布时间（formatCount/formatPubDate）
│       ├── 细进度条行：Slider（trackThickness 5 / blockSize 12，受控+防回弹）
│       ├── 时间行：当前时间 | Blank | 总时长
│       ├── 控制栏（传输五键，居中）: [上一首] [◀◀15s] [播放/暂停72px主键] [15s▶▶] [下一首]
│       ├── 底部操作行（居中）: [倍速 x.xx] [模式] [定时/剩余] [☰队列]
│       └── 状态行：statusMsg（+isPreparing 时 LoadingProgress）
├── if showSpeed: speedPanel()（复用）
├── if showMode: modePanel()（复用）
├── if showSleepTimer: sleepTimerPanel()（复用）
├── if showSleepTimerPicker: sleepTimerPicker()（复用）
├── if showQueueSheet: QueueDrawer()（复用）
├── parallelGesture(PanGesture)  ← 下拉关闭（判定：信息区滚到顶 + 无浮层打开）
└── bindSheet(showDetail, detailSheet(), 62%)  ← 复用
```

### 交互契约

- ±15s 键：单击固定 ±15s（SEEK_STEP_MS）；`isPrepared === false` 时禁用置灰；连按叠加经 seekBy 防抖合并；到边界钳制。
- 切歌键：沿用 `controller.prev()/next()` 现有逻辑（含 isPreparing 门控与随机模式历史栈）。
- 播放键：沿用 `togglePlay()` 与 playWhenReady 意图切换；popPlay 按压动画保留。
- 倍速/模式/定时：浮层选择后即生效并持久化（现有逻辑），按钮文案/颜色随状态刷新。
- 下拉关闭：offsetY > 80vp 且信息区在顶部且无浮层/队列/详情打开。
- 深浅色：全部颜色走 `resources/base|dark/element/color.json` 既有资源键，不硬编码色值。
