# Implementation Plan: UX 反馈第 7 轮（R7）

**Input**: Feature specification from `spec/ux-feedback-round7/spec.md`

## Summary

修复四项功能性缺陷：UP 主订阅触底加载静默失效（门槛放宽 + Web 翻页兜底 + 页号对齐）、订阅取流稀疏与翻页乱序（刷新双链合并 + 追加后重排）、首页未读徽标不消除（回写陈旧已读时间）、时间显示缺年份（三态格式化）；并将设置页与日志查询页整页重写为 HarmonyOS 系统风格（功能全保留），补齐播放历史面板与首页的过冲提示/关闭手势/背景一致性，回退已播图标为绿色圆圈对号。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 24，目标 API 26 接口须 `[API24-COMPAT]` 守卫）  
**Primary Dependencies**: ArkUI（V1 状态管理）、`@kit.AbilityKit`、`@kit.NetworkKit`（http）、`@kit.CoreFileKit`（picker/fileIo）、`@kit.RemoteCommunicationKit`（rcp）  
**State Management**: 保留项目既有 V1（`@State`/`@StorageLink`/`@StorageProp`/`@Watch`），不引入 V2  
**Storage**: AppStorage（瞬态 UI 键 `AS_*`）+ PersistenceV1 偏好（`KEY_*`）+ 沙箱文件（订阅剧集缓存、日志文件），键集中在 `Constants.ets`  
**Testing**: 无测试套件；验证 = `arkts_check` 静态预检 + `devecocli build` + 虚拟机（MatePad Pro 11 API 24 / Mate 90 Pro API 26）部署实测  
**Target Platform**: HarmonyOS NEXT 手机/平板  
**Project Type**: 单模块移动应用（entry）  
**Performance Goals**: 列表滚动 60fps；刷新后台静默不阻塞 UI；触底加载响应 ≤3s  
**Constraints**: ArkTS 严格模式（禁 any/unknown/as 断言、解构、对象字面量类型）；代码零注释（`ponytail:` 除外）；Constants.ets 唯一真相源；B 站 Web 端点须 WBI 签名、APP 端点须 BiliDroid UA  
**Scale/Scope**: 改动约 12 个既有文件 + 新增 2 个共用组件 + 重写 2 个页面文件；单一 feature 目录

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round7/
├── spec.md              # 需求规格（已评审）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── HomePage.ets          # 改：徽标回写修复、首页 EdgeHint（US4/US9）
│   ├── SourcePage.ets        # 改：触底门槛/页号对齐/追加重排/formatDate 三态/已播图标（US1/US2/US3/US7）
│   ├── SettingsPage.ets      # 重写：HarmonyOS 系统风格整页（US8），保留历史面板修复（US6）
│   ├── LogPage.ets           # 重写：独立整页（US5），LogSheet 退役
│   └── （Index/PlayerOverlay/AddSubscriptionSheet 不动）
├── component/
│   ├── EdgeHint.ets          # 复用（不改）：过冲提示
│   ├── SettingsGroup.ets     # 新增：分组卡片容器（设置页/日志页共用）
│   ├── SettingsRow.ets       # 新增：设置行（图标/标题/副题/控件/箭头，设置页/日志页共用）
│   └── （LogSheet.ets 删除：功能并入 LogPage）
├── service/
│   ├── BiliService.ets       # 改：新增 Web 链头页公开包装（US2 双链合并）
│   └── SubscriptionStore.ets # 改：UP 刷新双链合并去重排序（US2）
└── （model/Constants/Appearance 等不动）

entry/src/main/resources/base/element/color.json  # 不动（success_green #34C759 已存在）
```

**Structure Decision**: 遵循项目既有架构（pages/component/service/model 单模块结构，V1 状态管理），不引入 MVVM 目录。本轮以改写既有文件为主，仅新增 2 个可复用 UI 组件支撑设置页/日志页重写（两页共享设计语言，抽组件消除重复）。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 设置页整页重写（而非修补） | 用户明确要求弃用原项目风格；原文件 ~1500 行多轮演改积累结构混乱 | 修补只能治色差/过冲表象，无法达成 HarmonyOS 系统风格目标 |
| 删除 LogSheet.ets 并入 LogPage | 日志页升级为独立整页后该组件唯一使用方消失，保留即死代码 | 保留薄壳包裹违背「单标题/内容到底」需求（两行标题根因） |

## Research & Decisions

### D1: UP 触底加载门槛放宽与 Web 兜底页号对齐（US1 / FR-001~003）

- **Decision**: `SourcePage.loadFromCache` UP 分支门槛改为 `cached.length > 0`（与 FAV 对齐）；`fetchUpOlderPage` 无游标降级 `fetchUpVideosByPage` 时，页号按当前列表长度对齐 Web 链 ps=30 页界（从能覆盖首个未展示条目的页开始请求），去重逻辑兜底防重复。
- **Rationale**: 实测服务端对 APP 端点首页钳制 ps≈20，`cached>=30` 永不成立；游标为内存态，APP 链被风控后游标永缺 → 现门槛等价于永久禁用。Web 页号链已存在，只需页号对齐避免「缓存 20 条、Web pn=2 从第 31 条起跳过 21-30」。
- **Alternatives considered**: 持久化游标（治标：APP 链失败时仍无游标）；移除门槛直接每次触底请求（风险：到底后重复空请求，现有短页终止规则仍需要）。

### D2: UP 刷新双链合并治稀疏（US2 / FR-004）

- **Decision**: `SubscriptionStore.refreshSubscription` UP 分支：APP 链结果为主干，再尝试 Web 链第一页（稠密全量流，新增 `BiliService.fetchUpWebHead(mid)` 公开包装，内部调既有 `fetchUpVideosViaWeb(mid, 1)`）；两结果按 bvid 去重、按 pubdate 降序合并落盘。Web 补抓失败仅记日志、不阻断（结果退化为 APP 稀疏流，不劣于现状）。
- **Rationale**: 实测罗翔案例 APP 链首页 20 条缺 9-19、9-13 等约半数投稿，Web 链为空间页同源接口（稠密）。APP 链保留主干地位：快、无 WBI/buvid 风控依赖；Web 仅作头部补稠，失败可降级。
- **Alternatives considered**: Web 链改为主链（否决：Web 风控环境下每次刷新先三轮退避再降级，慢 5-10s；APP 优先是既有抗风控设计）；仅重排不治稀疏（否决：用户确认稀疏纳入本轮）。
- **Risk note**: Web 头页补抓使每次 UP 刷新多一次请求（+1~2s）——串行追加在 APP 主干完成后进行，不阻塞首屏缓存读取，静默后台刷新可接受；Web 被风控时行为退化为现状（不劣化）。

### D3: 触底追加后全列表重排（US2 / FR-005~006）

- **Decision**: `SourcePage.loadOlder` 追加去重后对 `episodes` 整体按 pubdate 降序重排再渲染。全重复页时既有逻辑（olderPage 无条件推进 + FAV/UP/SEASON 各自终止规则）已满足 FR-006，保留不动。
- **Rationale**: 游标链窗口漂移实测存在（9 月条目拼到 3 月之后）；客户端排序是唯一可靠不变量，与链路选择解耦。
- **Alternatives considered**: 按插入位置二分插入（过度工程：排序一次性 O(n log n) 足够）。

### D4: formatDate 三态年份（US3 / FR-007）

- **Decision**: 就地修改 `SourcePage.formatDate`：`d.getFullYear() !== now.getFullYear()` 时输出 `YYYY-M-d HH:mm`；当天/当年规则不变。全仓排查确认该函数仅源页列表一处调用，不抽公共模块。
- **Rationale**: 最小 diff；历史面板条目不显示时间戳，无第二调用点。
- **Alternatives considered**: 抽公共时间格式化工具（否决：单调用点，YAGNI）。

### D5: 首页徽标回写修复（US4 / FR-008~009）

- **Decision**: `HomePage.silentRefresh` 每订阅回调：先从 `SubscriptionStore.loadSubscriptions()` 重载（拿到最新 lastSeenAt）→ 过滤 `subExists` → 保存，不再直接保存内存 `this.subs` 陈旧副本。`addSubscription` 刷新回调同理：重载后仅以刷新完成的订阅对象替换同 id 项再保存。
- **Rationale**: 实测根因：markSeen 写入 store 的 lastSeenAt 被刷新回调回写的内存陈旧值覆盖；用户「打开 app → 见徽标 → 立即点进」必然落在后台刷新窗口内，属确定性缺陷。重载后保存彻底消除覆盖窗口。
- **Alternatives considered**: markSeen 改由 HomePage 统一处理（改动面大、跨页耦合）；保存时逐字段比对合并（复杂）。

### D6: 日志页独立重写、LogSheet 退役（US5 / FR-010~011）

- **Decision**: `LogPage.ets` 重写为独立整页：HarmonyOS 风格（大标题、操作按钮置标题栏右侧/工具行）、列表（LazyForEach 数据源整体迁入 LogPage）、导出（DocumentViewPicker 逻辑原样迁移）、清空（仅内存缓冲）、空态、miniPlayerVisible 底部避让全部保留。`component/LogSheet.ets` 删除（唯一使用方为 LogPage）。
- **Rationale**: 现状是 R3 半模态组件（自带标题行/按钮行）套 R6 导航薄壳，两行标题与底部留空是结构必然；修补不如按新设计语言整页实现。
- **Alternatives considered**: 保留 LogSheet 加参数隐藏标题行（仍留 sheet 布局包袱，且组件已无其他使用方）。

### D7: 历史面板下拉关闭拦截（US6 / FR-014）

- **Decision**: 播放历史 `bindSheet` 增加 `onWillDismiss` 回调：`reason === DismissReason.SLIDE_DOWN` 时不调用 `dismiss()`（拦截下拉关闭）；`TOUCH_OUTSIDE` / `PRESS_BACK` / `CLOSE_BUTTON` 时调用 `dismiss()`（保留蒙层点击与返回关闭）。
- **Rationale**: 本机 SDK 已核实：`SheetOptions.onWillDismiss?: Callback<DismissSheetAction>`（common.d.ts L11863，API 12+），`DismissSheetAction.reason: DismissReason`，`DismissReason.SLIDE_DOWN = 3`；不调用 dismiss 即拦截。基线 API 24 无兼容问题，无需 `[API24-COMPAT]` 守卫。
- **Alternatives considered**: 自定义全屏面板替代 bindSheet（重写量大且丢失半模态转场）。
- **Risk note**: 拦截后需保证可达的关闭路径——蒙层点击与返回键均放行，dragBar 视觉提示保留，不产生「无法关闭」死角。

### D8: 已播图标回退（US7 / FR-015）

- **Decision**: 源页列表已播标记由文字「✓ 已播」改为 `SymbolGlyph($r('sys.symbol.checkmark_circle'))`，颜色 `$r('app.color.success_green')`。sysResource.js 已核实 `checkmark_circle` 存在（id 125831133，轮廓版非 fill）。
- **Rationale**: 用户要求恢复第 6 轮前的圆圈对号样式、仅颜色改绿；色板已有 success_green（#34C759），不新增 token。
- **Alternatives considered**: 保留文字加图标（用户明确要求换回图标）。

### D9: 设置页整页重写（US8 / FR-016~019）

- **Decision**: `SettingsPage.ets` 按功能清单全量重写为 HarmonyOS 系统风格：大标题 + 分组卡片（新增 `SettingsGroup`/`SettingsRow` 共用组件：分组容器 + 行组件〔图标/标题/副题/Toggle/箭头〕）；根容器背景统一 `$r('app.color.page_background')` 且延伸安全区（治色差，深浅两模式同源）；滚动容器包 Stack + EdgeHint 顶/底（复用源页 onWillScroll/onScrollStop 模式）。功能清单保真（重写前逐项核对）：账号（扫码登录/Cookie 粘贴/退出登录）、播放设置（启动自动播放、后台打断续播、Wi-Fi/移动网络默认音质、无图模式、仅 Wi-Fi 播放）、外观（主题/强调色）、播放历史（入口行 + 面板 + 清空）、日志查询入口、关于（面板：版本/简介/核心功能）。音质选择/关于保留 bindSheet 半模态（样式随新语言微调），播放历史面板保留（承载 US6 修复）。路由键 `settingsPage`（param `playHistory` 直开面板语义）与 `logPage` 不变。
- **Rationale**: 用户明确要求弃用原项目风格重写且交互结构可重组；色差根因是 NavDestination 默认底色与 Index 背景层不同源，统一 page_background 即治。
- **Alternatives considered**: 原文件修补（无法达成风格目标）。
- **Risk note**: 重写功能回归风险最大——tasks 中列「重写前功能清单核对」任务，Phase 5 逐项验证（设置页全功能走查）。

### D10: 首页 EdgeHint（US9 / FR-020）

- **Decision**: `HomePage` 订阅列表外套 Stack + EdgeHint 顶/底，复用源页同款 onWillScroll/onScrollStop 过冲判定模式；列表行视觉与交互零改动。
- **Rationale**: 与源页/设置页过冲语言统一；EdgeHint 为纯展示组件直接复用。
- **Alternatives considered**: 无（需求明确）。

## Data Model

无新增实体，既有模型不变：

- **BiliVideo**: bvid/aid/title/cover/duration/pubdate/ownerMid/ownerName——pubdate（秒级 Unix 时间）为排序与三态格式化基准。
- **Subscription**: id/type/sourceId/ownerMid/title/cover/sortOrder/lastSeenAt/lastRefreshAt——lastSeenAt 为未读徽标基准，本轮修复其写入不被陈旧副本覆盖。
- **LogEntry**: time/category/summary/result——日志页重写后数据结构不变。
- **UI 新组件**: SettingsGroup（分组容器：标题+卡片+子内容槽）、SettingsRow（行：图标/标题/副题/右侧槽〔Toggle|箭头|值〕/点击回调）。

状态与键：AppStorage 键沿用 `Constants.ets` 既有 `AS_*`/`KEY_*`，不新增键；`success_green` 色值复用。

## Contracts & Interfaces

- **BiliService 新增**: `static fetchUpWebHead(mid: number): Promise<BiliVideo[]>`——Web 退避链第一页（ps=30 稠密流）公开包装，内部委托既有 `fetchUpVideosViaWeb(mid, 1)`；失败抛错，由调用方捕获降级。
- **SubscriptionStore 内部变更**: `refreshSubscription` UP 分支返回值语义不变（`Promise<BiliVideo[]>`），内部追加「APP 主干 + Web 头页 → bvid 去重 → pubdate 降序」合并，落盘与返回合并结果；其余类型分支不动。
- **SourcePage 内部变更**:
  - `loadFromCache` UP 门槛：`cached.length > 0`；
  - `fetchUpOlderPage` 无游标 Web 兜底页号：由 `episodes.length` 推算对齐 ps=30 页界的起始页号；
  - `loadOlder` 追加后：episodes 按 pubdate 降序整体重排；
  - `formatDate` 三态输出。
- **bindSheet（播放历史）**: `SheetOptions` 追加 `onWillDismiss`（`DismissSheetAction` → 按 `reason` 决定是否调用 `dismiss()`），既有 `height/dragBar/preferType` 保留。
- **设置页路由契约（不变）**: `router_map.json` 键 `settingsPage`/`logPage` 保留；`pushPathByName('settingsPage', 'playHistory'|'about')` 直开面板 param 语义保留；`pushPathByName('logPage')` 入口保留。
- **SettingsGroup / SettingsRow（新增组件契约）**: `SettingsGroup`（分组标题 + 卡片容器 + @Builder 子内容槽）；`SettingsRow`（title/subtitle/icon 可选 + 右侧 @Builder 槽 + 可选箭头 + 可选 onClick），供设置页与日志页共用。
- **LogPage（重写后契约）**: 对外仍为 `router_map.json` 的 `logPage` 目的页（`NavDestination` 根节点）；内部自持列表数据源、导出（DocumentViewPicker）、清空（Logger.clear）、空态；LogSheet 从导出面移除。
