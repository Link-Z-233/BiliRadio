# Implementation Plan: v0.5-part3（订阅详情交互打磨 + 反馈完善与登记）

**Input**: Feature specification from `spec/v0.5-part3-registry/spec.md`

## Summary

两线合并轮：交互打磨线（US1 历史/订阅源整行拖选双向推广、US2 悬浮按钮左右进退与透明度动画、US3 页头信息改造、US4 合集·前缀剥除、US5 角标加大）+ 登记清账线（US6 播放出错提醒与日志、US7 历史容量 300 与尾注、US8 充电视频探针门控组）。技术路径：零新增文件——拖选逻辑并入既有 `SelectLogic.ets`（RowDragSession + EdgeAutoScroller 尽头检测），页头/按钮/角标为 `SourcePage.ets` 局部改动，错误提醒走 PlayerController 既有广播模式 + Index toast 消费，US8 为探针门控默认搁置组（放行才按 `charging-archive.md` 还原）。

## Technical Context

**Language/Version**: ArkTS（compatibleSdkVersion 26.0.0，API 26）
**Primary Dependencies**: ArkUI（@ComponentV2、TransitionEffect、GestureGroup、Scroller）、@kit.PerformanceAnalysisKit（hilog）
**State Management**: 既有 V2——@ObservedV2+@Trace 模型、@ComponentV2 页面；PlayerController 零装饰器广播（字段 + emitUi + syncFrom），本轮沿用不加观测装饰器
**Storage**: AppStore preferences（播放历史持久化；容量上限 300）
**Testing**: 无自动化测试套件；arkts_check 静态预检 + devecocli build；真机目检由用户执行（验证范围默认 build-only）
**Target Platform**: HarmonyOS NEXT（手机为主；平板宽屏随 FR-020 回归）
**Performance Goals**: 拖选/边缘滚动不掉帧；行索引 O(n) 查表（n≤数百）可接受
**Constraints**: Constants 唯一真相源（数值禁裸写）；禁 any/unknown/as；B 站风控红线（禁列表逐条拉详情补偿）；令牌替换数值不变观感
**Scale/Scope**: 订阅剧集数百行、播放历史 300 条上限

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part3-registry/
├── spec.md               # 需求规格
├── plan.md               # 本文件
├── charging-archive.md   # 充电问题集存档（US8 恢复唯一来源）
└── tasks.md              # Phase 3 产出
```

### Source Code (repository root)

全部为既有文件修改，**零新增文件**：

```text
entry/src/main/ets/
├── service/SelectLogic.ets          # US1：RowDragSession（双向画笔+拖前快照）；EdgeAutoScroller 尽头检测回调
├── component/HistorySheet.ets       # US1：整行 Sequence 拖选接入；US7：列表尾容量提示行
├── pages/SourcePage.ets             # US1：剧集行拖选接入；US2：按钮进退改 START/END；US3：页头重排；US5：角标字号
├── component/QueueSheet.ets         # FR-020：宽屏门禁审查（isWideScreen 残骸摘除）
├── service/Constants.ets            # US6：去重窗口令牌与 toast 文案；US7：HISTORY_MAX 300；US2 若需距离令牌
├── service/PlayerController.ets     # US6：playbackError 统一入口（hilog + 去重 + 广播）
├── service/AudioPlayer.ets          # US6：错误回调接线
├── service/BiliService.ets          # US6：取流错误路径上报；US8（条件）：充电判定还原
├── pages/Index.ets                  # US6：错误广播消费 → promptAction.showToast
├── model/Subscription.ets           # US4：displayTitle()（合集·剥除，展示层规范化）
├── model/BiliVideo.ets              # US8（条件）：isUpowerExclusive 还原
├── pages/AddSubscriptionSheet.ets   # US4：条目标题展示改调 displayTitle
entry/src/main/resources/base|dark/element/color.json  # US8（条件）：gold_accent
```

**Structure Decision**: 沿用既有工程架构（pages/component/service/model 分层、单模块、V2 状态管理），不引入新层、不做 MVVM 迁移。US1 选择逻辑并入 part2 已立的 SelectLogic.ets（选择逻辑唯一宿主），页头/按钮为 SourcePage 局部改动，零新增文件保证最小 diff。

## Complexity Tracking

无 Constitution 违规——零新文件、零新依赖、零架构变更，无需豁免登记。

## Research & Decisions

### D1 拖选双向语义 = 画笔模型 + 拖前快照

- **Decision**: SelectLogic 新增 RowDragSession：长按完成时切换起点行，按其翻转后状态锁定画笔方向（原未选→加扫，原已选→减扫）；拖动中按起点至当前行区间涂刷，脱离区间的行恢复拖前快照状态（拖回即取消）
- **Rationale**: 用户需求「拖回可取消」；快照恢复天然支持来回拖；与复选框区扫选「按下锁定方向」语义一致
- **Alternatives considered**: 队列式只增模型（不满足双向需求）；每次事件全量重算（快照恢复更简且幂等）

### D2 拖选与列表滚动共存 = Sequence(长按→拖) 常挂两态

- **Decision**: 整行 GestureGroup(Sequence, LongPressGesture, PanGesture) 常挂（常态与多选态均可触发）：长按完成进入多选（常态）或切换该行（多选态）并锁定画笔，随后拖动涂刷；未长按的普通竖滑永远归列表滚动
- **Rationale**: 长按门槛天然区分滚动与拖选；多选态内从已选行长按起拖才能实现减扫（双向的另一半）
- **Alternatives considered**: 多选态禁用行拖保滚动（队列现状，无法双向）；区域划分（整行拖选无区域可言）

### D3 行定位 = 队列 estHeight 累积法复用

- **Decision**: pan Y→目标行索引沿用队列已验证的行高累积估算；历史/订阅源行高统一（68 逻辑行高），实施时可退化为常数除法，取简者
- **Rationale**: 队列 targetEntryIndex 模式已真机验证；统一行高场景计算更简
- **Alternatives considered**: componentUtils.getRectangleById 逐行查询（行多时开销大）

### D4 边缘滚动尽头检测 = 宿主注入边界查询回调

- **Decision**: EdgeAutoScroller 增加可选尽头查询回调（宿主以滚动偏移或边界事件实现），tick 前检查，到顶/到底即停滚并清理
- **Rationale**: FR-003 到尽头即止；滚轮保持纯类边界，不感知列表结构
- **Alternatives considered**: 滚轮内持 Scroller（破坏 SelectLogic 纯类/UI 依赖泄漏）

### D5 按钮左右进退 = TransitionEffect.move(START/END)

- **Decision**: 左「标记已看完」`move(TransitionEdge.START)`、右「加入队列」`move(TransitionEdge.END)`，各 combine(OPACITY)，沿用 TOKEN_SELECT_ANIM_MS 同一 animateTo 驱动
- **Rationale**: 现为 `move(TransitionEdge.BOTTOM)`（SourcePage 563/587 行），单属性改边即可，move 按容器边缘滑入左右语义天然，无需距离令牌
- **Alternatives considered**: translate 自定义位移（手算距离，多余令牌）

### D6 透明度动画 = 状态切换包 animateTo

- **Decision**: 按钮 opacity 0.4↔1.0（TOKEN_DISABLED_OPACITY）随 selectedKeys.size 变化处包 animateTo（TOKEN_SELECT_ANIM_MS）
- **Rationale**: transition 只管组件进出场，属性值变化需显式动画；令牌均现成
- **Alternatives considered**: 维持瞬跳（用户明确要动画）

### D7 页头改造 = 同 padding 令牌对齐 + 名称大字 + 内联标签胶囊

- **Decision**: 页头容器与剧集行容器统一水平 padding 令牌（封面左缘自然对齐）；页头右列重排——名称大字（sub.title 经 displayTitle，字号取令牌阶梯 20/22 档实施定）+ 标签行（类型胶囊 + upperName + N 集）；收藏夹不渲染 upperName 行；胶囊在 SourcePage 内联实现不抽组件
- **Rationale**: 对齐靠同一令牌最稳；upperName/ownerMid 模型已有零改动；类型标签仅页头一处，抽组件 YAGNI
- **Alternatives considered**: 硬编码对齐偏移（违令牌化）；独立 TypeTag 组件（单使用点过度）

### D8 合集·剥除 = 展示层规范化 Subscription.displayTitle()

- **Decision**: Subscription 增实例方法 displayTitle()：合集类型且 title 以「合集·」起头剥去前缀，剥后为空返回原 title；展示位（SourcePage 导航标题与页头、AddSubscriptionSheet 条目）改调此方法，存储不动
- **Rationale**: 旧订阅免迁移；存储保留 B 站原始命名可回溯
- **Alternatives considered**: 订阅/解析时清洗写入（需迁移旧数据，破坏原始数据）

### D9 出错提醒 = toast + 会话内去重 + hilog + 广播消费

- **Decision**: PlayerController 增 playbackError 统一入口：hilog 记录（stage/bvid/错误码）→ 按 bvid+stage 时间窗去重 → 经既有广播发出错误事件（errorTick 版本计数）；Index syncFrom 消费 tick 变化调 promptAction.showToast；吞错点全量梳理接线（AudioPlayer 错误回调、取流 catch、播控切换 catch）
- **Rationale**: service 层无 UIContext 不能直接 toast，广播 + Index 是既有模式；后台播放（浮层未开）场景同样覆盖；toast 轻且不动播放层 UI
- **Alternatives considered**: 播放层错误态 UI（重、不覆盖后台场景）；PlayerController 直接 toast（无 UIContext）

### D10 历史容量 = 单常量升至 300 不拆分

- **Decision**: Constants.HISTORY_MAX 200→300；随机/快进跳转栈与播放历史共用该常量一升俱升，不拆分；尾注文案动态引用常量（数字同源）
- **Rationale**: 共用无功能影响（跳转栈历史本就该同容量）；拆分徒增常量违省事原则
- **Alternatives considered**: 拆 PLAY_HISTORY_MAX / JUMP_STACK_MAX（无实际差异）

### D11 US8 充电 = 探针门控默认搁置组

- **Decision**: US8 全组任务标记探针门控：探针（真机打开任一 UP 订阅详情刷新，观察 WBI 是否放行/有无 -403 降级日志）由用户执行；放行才按 charging-archive.md §7 逐字还原并验证，未执行/未放行整组跳过不阻塞轮次
- **Rationale**: 探针需登录态真机环境，构建验证无法覆盖；风控未放行时代码还原无意义
- **Alternatives considered**: 无条件还原（-403 下角标永不出现）；删除登记（用户要求保留条件项）

### D12 FR-020 = 宽屏残骸摘除，滚动保护语义保留

- **Decision**: QueueSheet 行拖门禁 `!selectMode || isWideScreen` 审查：isWideScreen 分支属 lanes 布局遗骸则改为 `!selectMode`（保留多选态滚动保护），手机端行为不变，平板宽屏随轮回归
- **Rationale**: .lanes 布局已不存在，宽屏分支无对应布局支撑
- **Alternatives considered**: 保留原样（死逻辑永驻）；整门禁移除（破坏滚动保护）

## Data Model

- **RowDragSession（SelectLogic.ets 新内部类）**: startKey/startIndex（起点行）、paintMode（画笔方向：起点行翻转后选中与否）、snapshot（拖前选中集 Set<string> 拷贝）、lastLo/lastHi（已涂区间）；行为 applyAt(currentIndex) 恢复脱离区间行的快照态并涂刷新覆盖区间，end() 清理。宿主注入行键查询与选中集写回。
- **EdgeAutoScroller 扩展**: 可选尽头查询回调，tick 前检查，到边界停滚（FR-003）。
- **Subscription.displayTitle()**: 实例方法，合集·前缀展示层剥除（FR-011）；模型零字段变更。
- **播放错误事件（PlayerController 广播快照新增字段）**: stage（取流/准备/播放等阶段标识）、bvid、code、errorTick（版本计数）；瞬态不持久化。
- **HISTORY_MAX**: 200→300（Constants:85，共享常量不拆，D10）。
- **BiliVideo.isUpowerExclusive（条件，US8）**: @Trace 字段 + toRecord/fromRecord 键（charging-archive.md §7.1 逐字还原）。

## Contracts & Interfaces

- **SelectLogic.ets**: RowDragSession 构造依赖宿主回调（行键查询、选中集写回）；EdgeAutoScroller 尽头检测为可选注入参数，缺省行为不变（队列/既有扫选不受影响）。
- **PlayerController**: 新增 playbackError(stage, code, bvid) 统一入口——hilog 记录 + bvid+stage 时间窗去重 + 广播；广播快照新增错误字段供 syncFrom 消费；去重窗口与 toast 文案入 Constants。
- **Index**: syncFrom 检测 errorTick 变化 → promptAction.showToast（Constants 文案）。
- **HistorySheet**: 列表尾提示行——列表非空才渲染、不可交互、居中、文案数字动态引用 HISTORY_MAX、位于面板底部渐隐带之上。
- **SourcePage**: 页头与剧集行同水平 padding 令牌（FR-008 对齐契约）；按钮 transition 边 START/END（FR-006）；角标字号 TOKEN_FONT_BODY（13，FR-012）；页头名称字号入令牌阶梯（FR-009）。
- **Constants 新增/变更**: HISTORY_MAX=300（改）；TOKEN_FONT_BODY 复用（US5）；US6 去重窗口令牌 + 错误 toast 文案组；US3 页头名称字号取现有 20/22 档或新增档（实施定，值只入 Constants）。
