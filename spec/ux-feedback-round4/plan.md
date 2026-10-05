# Implementation Plan: UX 反馈修复第 4 轮（播放与订阅体验批次）

**Input**: Feature specification from `spec/ux-feedback-round4/spec.md`

## Summary

修复 8 个用户反馈问题并增强问题定位能力：播放详情页队列抽屉层级置顶（US1）、非首次切剧进度条冻结（US2，顺带修复 KI-1 监听器累积与切剧状态残留）、未登录查询 UP 投稿 352（US3，参考 PiliPlus 采用 APP 端点优先策略）、播放页加载指示器以系统 LoadingProgress 重做（US4）、添加订阅搜索收起键盘（US5）、按钮文案改"载入"（US6）、设置页隐藏播放胶囊（US7）、胶囊左右留边（US8）、日志异步落盘（硬上限）并为播放关键路径补充结构化诊断日志（US9，支撑 US2 类偶现问题的事后定位）。全部为存量代码修复，不新增页面、不改变导航与状态管理框架（V1 装饰器 + AppStorage 瞬态键体系保持不变）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，API 24/26 均需表现一致）
**Primary Dependencies**: ArkUI（V1 状态装饰器）、@kit.MediaKit（AVPlayer）、@kit.NetworkKit（http）、@kit.ArkUI（inputMethod）
**State Management**: 沿用项目现状 —— State Management V1（@State/@StorageLink/@StorageProp）+ AppStorage 瞬态键 + PlayerController 单例手写订阅广播
**Storage**: AppStore（Preferences）+ 文件持久化（不变）
**Testing**: devecocli build 编译验证 + 真机/模拟器部署验证（Phase 5 按用户选择）
**Target Platform**: HarmonyOS 手机/平板（BiliRadio 单 HAP entry 模块）
**Project Type**: 移动应用（存量项目增量修复）
**Performance Goals**: 进度条秒级刷新不冻结；切剧 2 秒内进度恢复走动
**Constraints**: 不回退登录态查询、全屏播放层、睡眠定时、播放模式等既有功能（FR-012）
**Scale/Scope**: 13 个存量 .ets 文件修改，0 个新文件

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round4/
├── spec.md              # 需求规格（已确认）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── Index.ets              # US7 胶囊可见性条件 + US8 胶囊容器水平留边
│   ├── PlayerOverlay.ets      # US1 抽屉置顶 + US2 isSeeking 重置 + US4 加载指示重做 + US2 订阅退订
│   ├── AddSubscriptionSheet.ets  # US5 收键盘 + US6 文案 + US3 风控提示文案
│   └── SettingsPage.ets       # US7 页面在置标志 + US2 订阅退订
├── component/
│   ├── MiniPlayer.ets         # US8 布局调整 + US2 订阅退订
│   ├── QueueDrawer.ets        # US1 进场动画方式加固
│   └── QueueSheet.ets         # US2 订阅退订
└── service/
    ├── PlayerController.ets   # US2 订阅/广播/切剧状态重置（核心）+ US9 诊断日志埋点
    ├── AudioPlayer.ets        # US2 重建实例代际令牌加固
    ├── BiliService.ets        # US3 APP 端点 + dm_img 参数 + ExClimbWuzhi 激活
    ├── BiliSession.ets        # US3 b_nut 等被动 cookie 字段
    ├── Logger.ets             # US9 落盘持久化 + 上限滚动淘汰 + 'player' 诊断类目
    └── Constants.ets          # US7 新增 AppStorage 键；US4 清理弧线常量；US9 日志文件上限常量
```

**Structure Decision**: 完全遵循项目现有架构（单 entry 模块，pages/component/service/model 分层，无 MVVM 迁移）。本批为纯缺陷修复，不新增文件、不新增目录层级；所有改动落在既有职责边界内的文件中（服务层 bug 修服务层、组件 bug 修组件）。

## Complexity Tracking

无 Constitution Check 违规需豁免项。

## Research & Decisions

### D1 — US1 队列抽屉层级置顶（PlayerOverlay 内）

- **Decision**: 双重加固。(a) 在 PlayerOverlay 根 Stack 的 `if (this.showQueueSheet)` 分支上显式加最高层 zIndex，确保抽屉在浮层内绝对置顶（高于倍速/模式/睡眠定时面板与主内容层）；(b) QueueDrawer 面板的进场不再依赖 `TransitionEffect.translate({x:'100%'})` 首帧动画，改为挂载时由 animateTo 驱动的显式位移状态（from 100% → to 0），规避 KI-5 描述的浮层渲染停滞场景下 TransitionEffect 首帧不播放导致面板滞留屏外。
- **Rationale**: 用户已确认按钮与状态开关实际生效、抽屉有挂载，是层级/渲染问题，且**仅在 API 24 平板复现**（其余设备正常），属平台相关渲染行为差异。Stack 末位子节点默认置顶但该平台实测未置顶，显式 zIndex 是最小且确定的修复；TransitionEffect 在 bindContentCover 子树内的进场可靠性存疑（叠加平台差异），animateTo 显式状态驱动的可达性更高。修复需全平台一致生效，且不回退 API 26 等现有正常平台的表现。
- **Alternatives considered**: ① 把 QueueDrawer 改为浮层内独立 bindContentCover（否决：嵌套 cover 与主浮层手势/返回键冲突风险大）；② 仅加 zIndex 不动动画（保留：作为 (a) 已覆盖，但 (b) 一并加固成本低、覆盖另一类失效模式）。

### D2 — US2 切剧后进度条冻结（多层修复，含 KI-1）

- **Decision**: 五项修复，覆盖全部已识别的失效机制：
  1. **订阅可退订**：`PlayerController.subscribe(fn)` 改为返回退订句柄（闭包）；MiniPlayer、QueueSheet、PlayerOverlay、SettingsPage 四处调用方在 `aboutToDisappear` 中退订（消除 KI-1 监听器无限累积——现状每次打开队列抽屉/浮层都会追加一个永不移除的闭包，且 indexOf 去重因闭包身份不同永不命中）。
  2. **广播异常隔离**：`emitUi()` 对每个监听器调用单独 try/catch（异常记 hilog 警告），单个陈旧监听器抛异常不再中断循环、不阻断后续活组件刷新（PROJECT_NOTES KI-5 观测"MiniPlayer 数据新鲜、浮层不更新"与该机制吻合：陈旧监听器在数组前段抛异常会截断后段 PlayerOverlay 的更新）。
  3. **切剧状态重置**：`playIndex()` 中重置 `lastEmittedSec = -1`（避免新曲目首秒不广播）并取消挂起的 seekBy 防抖定时器（clearTimeout + 句柄复位，避免旧曲目 ±15s 目标 seek 到新曲目）。
  4. **拖拽态重置**：PlayerOverlay.syncFrom 中，当 controller 进入 preparing（切剧中）时强制复位 `isSeeking = false`，避免切剧瞬间正在拖动进度条导致 sliderValue 永久停更。
  5. **播放器代际令牌**：AudioPlayer.recreatePlayer 每次重建递增代际号，setupCallbacks 捕获当代代际，回调先比对代际再更新共享状态字段，杜绝快速连续切剧时旧实例残余事件污染 `playerState`/`currentTime` 等共享字段（waitForState 轮询共享字段的串扰窗口）。
- **Rationale**: 真机上无法预先区分哪一层是确切触发点（无崩溃日志可复现分析），但五项均为独立成立的结构性缺陷，任一修复都独立可验证、互相不冲突；全部修复后"切剧后进度冻结"的所有已识别路径均被覆盖。
- **Alternatives considered**: ① 只修订阅退订（不足：emitUi 无隔离时单异常仍可截断；切剧状态残留独立成病）；② 定时器轮询进度兜底（否决：掩盖根因、引入额外唤醒）；③ AudioPlayer.waitForState 改事件驱动（改动面大，代际令牌已消除串扰，暂不动）。

### D3 — US3 未登录 352（PiliPlus 参考策略）

- **Decision**: 三层递进。
  1. **主路径换 APP 端点**：新增 `app.bilibili.com/x/v2/space/archive/cursor`（PiliPlus 同款，参数含 vmid/ps/pn/build/mobi_app=android/platform 等，BiliDroid UA，无需 cookie/WBI），登录与未登录一律优先走该端点；响应 `data.archives[]` 解析为 BiliVideo（bvid/title/pic/duration(秒,数值)/pubdate/owner.mid/owner.name/owner.face/stat.view）。APP 端点无 Web 风控，未登录天然可用。
  2. **Web 端点降级保留**：APP 端点失败时回退现有 Web 降级链（直连 → WBI 签名），并按 PiliPlus 配方为 WBI 请求补齐风控参数：`dm_img_list='[]'`、`dm_img_str`=随机 base64（16-64 随机字节，字符域避开 `%`）、`dm_cover_img_str`=随机 base64（32-128 字节）、`dm_img_inter` 固定 JSON 串、`web_location='333.1387'`、`order_avoided='true'`、`tid='0'`。
  3. **buvid 激活**：`ensureBuvid` 获取 buvid3/buvid4 后，按 PiliPlus 的最小伪装 payload POST `x/internal/gaia-gateway/ExClimbWuzhi` 激活一次（每进程一次），并从该响应 Set-Cookie 被动收集 `b_nut` 存入 BiliSession，后续请求 Cookie 拼接时附带（buildHeaders/buildSpaceHeaders 同步扩展）。
  4. **兜底提示**：Web 链最终仍失败且判定风控时，AddSubscriptionSheet 现有"疑似风控"toast 文案补"建议登录"引导（FR-006）。
- **Rationale**: 用户指定参考 PiliPlus。其主路径（APP 端点）从根源绕开 Web 风控，是未登录可用的最可靠方式；Web 配方与激活仅在降级路径生效，属"尽力修复"；仍失败则友好提示，符合已确认的"尽力修复+兜底提示"方向。登录态走 APP 端点同样可用（PiliPlus 即如此），不构成回退。
- **Alternatives considered**: ① 仅补 dm_img 参数保留 Web 端点为主（否决：未登录成功率不可控，用户已指定参考 APP 端点方案）；② 移植 PiliPlus 的 GeeTest v_voucher 验证流（否决：超出本批范围，APP 端点已覆盖主场景）。

### D4 — US4 加载指示器重做（系统 LoadingProgress 替换播放键图标）

- **Decision**: 播放键同心容器内，`isPreparing && playWhenReady` 时以 `LoadingProgress`（主题色、尺寸按播放键直径派生）替换播放/暂停 SymbolGlyph；彻底删除自绘 270° Path 旋转弧线与常驻低透明装饰 Circle、`arcAngle` 状态、`updateArcSpin()`、`wasSpinning` 标志、`playArcCommands()/playArcRadius()/playArcSize()` 派生方法；Constants 清理 `PLAY_ARC_GAP/PLAY_ARC_STROKE/PLAY_RING_STROKE`（保留 `PLAY_BTN_DIAMETER`）；播放键外层同心 Stack 尺寸收敛为按钮本体尺寸。用户点按播放键中断缓冲（pauseRequest）时 LoadingProgress 随状态自然消失。
- **Rationale**: 自绘 Path + rotate 动画在 API 24 不渲染、API 26 圆心错位，属平台渲染差异，弃用是最稳妥路径；系统 LoadingProgress 各 API 版本表现一致（用户已确认此方案）。缓冲态下播放键图标位显示加载圈，语义清晰（键位即"正在准备播放"）。
- **Alternatives considered**: ① Progress 环形组件环绕播放键（用户未选）；② 保留 Path 弧线修圆心（否决：跨版本渲染差异不可控，用户明确要求重做）。

### D5 — US5 搜索提交自动收起键盘

- **Decision**: 主输入 TextInput 增加 `enterKeyType(Search)` 与 `onSubmit`（触发 handleMainInput）；`handleMainInput()` 入口处先统一收起软键盘（`getUIContext().getInputMethodController().stopInputSession()`），覆盖按钮点击与输入法提交两条路径，且在输入非法/短链解析等全部分支下键盘均收起。
- **Rationale**: 收键盘动作与查询发起强绑定，入口统一处理最不易遗漏；项目内 QueueSheet 已有 onSubmit 先例，风格一致。
- **Alternatives considered**: 仅 onSubmit 收键盘（不足：点按钮路径仍漏）。

### D6 — US6 按钮文案"添加"→"载入"

- **Decision**: 主输入行操作按钮文案字面量改为"载入"，行为（recognizeInput 识别 → 查询/订阅分发）完全不变。
- **Rationale**: 该按钮实际语义是"载入输入内容并识别"，最终订阅动作在结果区完成，文案对齐行为。
- **Alternatives considered**: 无（纯文案修改）。

### D7 — US7 设置页隐藏播放胶囊

- **Decision**: 新增 AppStorage 瞬态键 `AS_ON_SETTINGS_PAGE`；SettingsPage 在 `aboutToAppear` 置 true、`aboutToDisappear` 置 false；Index.ets 胶囊容器的 visibility 条件由"仅 showPlayerOverlay 隐藏"扩展为"showPlayerOverlay 或 onSettingsPage 时隐藏"。设置页内列表底部避让留白（MINI_PLAYER_CLEARANCE）行为保持不变，仅隐藏胶囊本体。
- **Rationale**: SettingsPage 是导航叶子页（无更深推入），生命周期标志法最简单可靠；返回手势/返回键 pop 时 aboutToDisappear 必然触发，胶囊可见性自动恢复。胶囊常驻挂载（Visibility 切换而非卸载）的既有设计保持，不引入 MiniPlayer 重复 mount。
- **Alternatives considered**: ① navPathStack.setInterception 按路由名驱动（否决：返回首页不触发 destination didShow，需额外处理，复杂度高）；② 设置页内叠一层遮挡（否决：脏且胶囊 backdropBlur 仍在渲染）。

### D8 — US8 播放胶囊左右留边

- **Decision**: 留边职责上移：Index.ets 中 MiniPlayer 的宿主 Column 增加水平 padding 16；MiniPlayer 两个分支（内容态/空态）的 Row 移除 margin 的 left/right 分量（保留 bottom 分量），`width('100%')` 相对收缩后的宿主内容区解析，不再溢出。
- **Rationale**: 现状 `width('100%')` + 水平 margin 叠加导致横向溢出、Stack 居中后两侧被裁，视觉贴边。百分比宽度按父容器内容区解析，把留边放到宿主 padding 是最小且两分支统一生效的修法。
- **Alternatives considered**: ① Row 去掉 width('100%')（否决：空态 Row 会收缩成内容宽，布局回归风险）；② 改用 constraintSize 百分比减法（脆弱）。

### D9 — 日志落盘（硬上限）+ 播放路径诊断日志（US2 定位支撑）

- **Decision**:
  1. **落盘机制**：Logger 在内存环形缓冲（现状不变，LogSheet 面板行为不回退）之外，将每条日志异步追加写入应用沙箱日志文件（追加写、失败静默）。**上限控制**：Constants 新增日志文件上限常量（字节级，量级 512KB）；每次落盘前检查文件大小，超限则滚动淘汰——保留最新一半内容重写文件（或等价的轮转策略），文件占用恒定有界。写入策略为异步 fire-and-forget（不阻塞、不 await 主流程）；日志行格式为可读的单行文本（时间戳 + category + summary + result），内容延续现有脱敏约束（host+path，无 query string、无 cookie/token）。
  2. **诊断日志（FR-014）**：在 D2 修复的各关键路径埋点结构化日志条目（沿用 LogEntry 三段式结构，category 扩展 'player' 类）：切剧（playIndex 进入：目标 bvid、token；prepared/playing/paused/completed/error 状态迁移）、切剧状态重置（节流基准复位、防抖取消）、emitUi 异常隔离（监听器序号 + 异常摘要）、订阅/退订（调用方标识）、seekBy 防抖到期/取消。hilog 与 Logger 双通道记录（hilog 供实时调试，落盘供事后分析）。
  3. **生命周期**：日志文件位于应用沙箱（随应用卸载清除），启动时不回读入内存缓冲（内存缓冲仍从空开始，沙箱文件仅供事后取证）。
- **Rationale**: 用户明确要求 US2 定位与日志系统结合、日志落盘且限制最大值。US2 类缺陷偶现且无法实时附着调试器，事后日志是唯一可行定位手段；异步追加 + 滚动淘汰实现简单、IO 开销低、上限确定。
- **Alternatives considered**: ① 仅增大内存缓冲（否决：重启即失，无法事后分析）；② hilog 落盘方案（否决：依赖设备侧工具，用户自用场景不可行）；③ 全量落盘不设限（否决：用户明确要求限制最大值）；④ 启动回读日志文件（否决：无消费场景，徒增启动开销）。

### D10 — 范围界定

- **Decision**: SleepTimerController 同型订阅累积（PROJECT_NOTES KI-2）本批不修（无用户反馈指向）；AudioPlayer.release() 未先 stop 的释放策略、KI-5 浮层渲染停滞的底层归因（如 backdropBlur/无限动画）保持观察，D1/D2 的加固已从应用层消除其可观测影响。
- **Rationale**: 严格按本批 8 个反馈修复，控制改动面与回归风险；已知问题记录在案，待后续批次。
- **Alternatives considered**: 顺手重构 SleepTimerController（否决：与本批反馈无关联，扩大验证面）。

## Data Model

**无新增持久化实体。** 涉及的数据形态变化：

- **BiliVideo（既有，扩展解析来源）**: 新增 APP 端点 `data.archives[]` 原始记录 → BiliVideo 的映射：`bvid`(string, 必填跳过空值)、`aid`(number)、`title`(string, 经 cleanTitle)、`cover`(pic 字段规范化)、`duration`(number, 秒，与 Web 端 'm:ss' 字符串解析后的单位一致)、`pubdate`(number)、`ownerMid/ownerName/ownerFace`(owner 子对象)、`view`(stat.view)。字段集合与既有 BiliVideo 完全一致，仅新增解析入口。
- **订阅句柄**: `subscribe` 返回 `() => void` 退订闭包，四个调用方以私有字段持有。
- **落盘日志行**: 单行可读文本（时间戳 + category + summary + result，分隔符固定），category 在 'net'/'error' 基础上扩展 'player'；内容延续脱敏约束（host+path，无 query string、无 cookie/token）；文件位于应用沙箱，大小以 `LOG_FILE_MAX_BYTES` 为硬上限滚动淘汰。
- **BiliSession（既有，扩展字段）**: 新增 `bNut`（及响应 Set-Cookie 中可得的被动 cookie 值），由 ExClimbWuzhi 激活响应收集；`buildHeaders`/`buildSpaceHeaders` 拼接 Cookie 时附带；`resetBuvid` 一并清空。

## Contracts & Interfaces

**模块内接口（无外部 API 变化，存量调用方全部同步更新）**:

1. `PlayerController.subscribe(fn: () => void): () => void` — 返回退订句柄（签名破坏性变更，MiniPlayer/QueueSheet/PlayerOverlay/SettingsPage 四处调用方必须持句柄并在 aboutToDisappear 调用）。`emitUi` 行为契约变更：单监听器异常被隔离并记日志，不阻断其余监听器。
2. `PlayerController.playIndex(index, seekMs, fromNav)` — 外部签名不变；新增内部契约：进入时重置秒级节流基准并取消挂起的 seekBy 防抖定时器。
3. `BiliService.fetchUpVideos(mid: number): Promise<BiliVideo[]>` — 外部签名与语义（最新投稿一页 30 条）不变；内部策略变为「APP 端点 → Web 直连 → Web WBI(带 dm_img 参数)」降级链；抛出的最终错误仍含原始错误码供上层分类。
4. `BiliService.ensureBuvid(): Promise<void>` — 签名不变；新增副作用：成功获取 buvid 后执行一次 ExClimbWuzhi 激活并收集 b_nut（失败静默，不阻塞主流程）。
5. `BiliSession` — 新增 `bNut` 字段与被动收集入口；`buildHeaders`/`buildSpaceHeaders`（BiliService 内部函数）Cookie 拼接包含 b_nut。
6. `Constants` — 新增 `AS_ON_SETTINGS_PAGE`；移除 `PLAY_ARC_GAP`、`PLAY_ARC_STROKE`、`PLAY_RING_STROKE`（全库唯一引用点在 PlayerOverlay，同步删除）；新增 ExClimbWuzhi 网关路径常量；新增日志文件名与 `LOG_FILE_MAX_BYTES`（字节级上限）常量。
7. `Logger` — 内存环形缓冲 API（log/snapshot/count/clear）签名不变，LogSheet 面板行为不回退；新增异步落盘副作用与超限滚动淘汰；`log()` 的 category 契约扩展 'player' 类目（播放状态迁移/切剧重置/广播异常隔离/订阅生命周期）。
8. `QueueDrawer` — 对外用法不变；内部进场机制由 TransitionEffect 改为挂载时 animateTo 显式状态驱动。
9. UI 契约：PlayerOverlay 根 Stack 内 `showQueueSheet` 分支显式 zIndex 最高；Index 胶囊容器 visibility 由 `showPlayerOverlay || onSettingsPage` 决定；MiniPlayer 宿主 Column 水平 padding 16、Row 移除水平 margin。

**外部网络接口（B 站公开接口，参数为公开事实性配置）**:

- APP 投稿游标：`GET app.bilibili.com/x/v2/space/archive/cursor`，参数 vmid/ps/pn/build/mobi_app/platform 等，Header 为 BiliDroid UA，无 Cookie/WBI。
- buvid 激活：`POST api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi`，JSON body `{payload: <json字符串>}`，携带 buvid3 Cookie；响应 Set-Cookie 收集 b_nut。
- 既有 Web 降级链端点不变，WBI 请求参数新增 dm_img 系列/web_location/order_avoided/tid。
