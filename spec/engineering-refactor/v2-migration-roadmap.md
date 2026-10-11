# V2 渐进迁移路线图（v2-migration-roadmap）

> engineering-refactor 实施轮 3 产出（T029-T031，US4）。**本期不实施迁移**——本文档为远期执行路线图。
> 总则：按「模型层 → 组件 → 页面 → 全局状态」分块迁移，每单元独立提交、独立验收、可回滚（`git revert` 该单元提交），全程应用可用。

> **批次 1 实施记录（2026-10-11）**：1.1/1.3/1.4/1.5/1.6 全字段 `@Trace` 落地；1.2 修正——`AudioQuality.ets` 实为纯静态工具类（`AudioQuality` 无实例字段）+ enum（`QualityTier`）+ 瞬态解析结果（`ResolvedAudio`，service 层局部消费不挂 UI），均无可观察实体不迁；**仅 `AudioTrack` 迁移**（`PlayerOverlay` `@State availableTracks` UI 消费）。验收：`arkts_check` 零错误、build 绿、Mate 90 Pro（API 26）模拟器回归通过（启动/UID 识别/订阅写入/首页列表渲染）——**风险②实测解除：V1 页面 `@State` 持有 `@ObservedV2` 模型数组的列表渲染运行时正常**。既有行为确认：订阅成功仅 toast 不自动关闭面板，非回归。

> **批次 3+4 实施记录（2026-10-11，联动合并执行）**：批次 3（7 页面）与批次 4（4.1 全局键 + 4.2-4.4 挂键组件）**合并为一次联动变更**——V2 页面内 `@StorageLink`/`@StorageProp` 不可用，页面先迁必然触碰全局键，中间态不可编译，无法独立提交。落地内容：① 新建 `service/V2State.ets`（`BoolState`/`NumState`/`StrState` 包装类 `@ObservedV2`+`@Trace value`，无参构造适配 TypeConstructorWithArgs；`connectBool`/`connectNum`/`connectStr` helpers，connect 失败兜底 `new`）；② 写入方迁移：EntryAbility（statusBarHeight/navBarHeight）、Appearance（accentColor/colorModeSetting/colorModeResolved）、GripDetector（gripOnRight）；③ 4.2-4.4 组件 + 批次 3 七页面全部 `@ComponentV2`（`@Watch`→`@Monitor`、`bindSheet($$)`→传值+onDisappear 回写）；④ `AS_*` 全部改 `AppStorageV2.connect` 包装类（`.value` 读写、同 key 共享实例天然双向，替代 `@StorageLink` 语义）；`KEY_*`（AppStore preferences）**保留不动**；`AS_IS_WIDE_SCREEN` 保持全局键（QueueSheet 实际消费，原审计矩阵遗漏修正）；⑤ 4.5 PlayerController 未迁（按 roadmap 仍为独立最后单元）。`@ComponentV2` 约束实测：普通成员（非装饰器）禁止父组件初始化（错误码 10905324），回调与对象句柄改 `@Param`；`@Monitor` 方法须公开、支持 `'x.value'` 嵌套路径。验收：`arkts_check` 15 文件零错误、build 绿、Mate 90 Pro 模拟器回归通过（启动/首页/设置页/主题色切换/返回/添加订阅面板/BV 播放入队/播放浮层开合/队列面板/设置往返）；顺带修复既有 crash `PlayerOverlay.ets:1336`（`currentOffset()` 浮层刚挂载时运行时返回 undefined，防御判空，批次 1 部署时已复现同源 crash）。

> **批次 4.5 关闭记录（2026-10-11，V2 路线图整体完结）**：迁移前提纠错——原记载「PlayerController 仍 V1 观测（`@Observed`+`@Track`）」有误，git 全历史 `-S` 检索零命中，该文件实为**零装饰器纯类**：手动 `subscribe`/`emitUi` 广播 + `playlistVersion`/`playHistoryVersion` 版本计数，四个消费方（MiniPlayer/QueueSheet/PlayerOverlay/SettingsPage）一律 `subscribe → syncFrom` 拷贝进 `@Local`，**与状态代际无关**；批次 3+4 消费方全部 `@ComponentV2` 后构建绿 + 播放链路模拟器回归通过即为实证。给其加 `@ObservedV2`+`@Trace` 重写观测换不来任何可见收益（UI 从不直接观测其字段），徒增上帝对象改写风险，按 YAGNI 经用户确认关闭为无需迁移。风险③（上帝对象）就此销项；4.5 的前置基线要求（全量回归）由批次 3+4 回归代偿。

## 一、迁移单元逐文件清单（T029）

### 批次 1：模型层（6 单元）

| # | 文件 | 目标范式 | 迁移要点 |
|---|---|---|---|
| 1.1 | `model/BiliVideo.ets` | `@ObservedV2` + `@Trace` | 字段全 `@Trace`；纯数据载体，无行为变化 |
| 1.2 | `model/AudioQuality.ets` | `@ObservedV2` + `@Trace` | 枚举型档位类 |
| 1.3 | `model/PlayHistoryItem.ets` | `@ObservedV2` + `@Trace` | 引用 BiliVideo（同批 1.1） |
| 1.4 | `model/Subscription.ets` | `@ObservedV2` + `@Trace` | 引用 BiliVideo；静态常量（TYPE_*）不动 |
| 1.5 | `model/Season.ets` | `@ObservedV2` + `@Trace` | 纯数据 |
| 1.6 | `model/FavFolder.ets` | `@ObservedV2` + `@Trace` | 纯数据 |

### 批次 2：组件

| # | 文件 | 处置 | 理由 |
|---|---|---|---|
| 2.1 | `component/CoverThumb.ets` | **免迁** | @Prop-only 无状态观测 |
| 2.2 | `component/SettingsGroup.ets` | **免迁** | @Prop + @BuilderParam 无状态观测 |
| 2.3 | `component/EdgeHint.ets` | **免迁** | @Prop-only |
| 2.4 | `component/SettingsRow.ets` | **并入批次 3 SettingsPage 单元** | 含 `@StorageProp('accentColor')`（真 V1 存储观测），须与全局键策略联动 |
| 2.5 | `component/MiniPlayer.ets` | **移至批次 4**（挂键组件） | `@StorageProp`×2（accentColor/navBarHeight），V1/V2 存储不互通 |
| 2.6 | `component/QueueSheet.ets` | **移至批次 4**（挂键组件） | `@StorageLink`×2 + `@StorageProp`×2 + `@State`×11（最重组件） |
| 2.7 | `component/QueueDrawer.ets` | **移至批次 4**（挂键组件） | `@StorageLink('showQueueSheet')`（双向绑定） |

> **批次修正（T031 风险标注①）**：plan.md 批次 2 原含 MiniPlayer/QueueSheet/QueueDrawer。三组件均挂 V1 全局键（`@StorageLink`/`@StorageProp`），而全局键切 AppStorageV2 在原批次 4——`@StorageProp`/`@StorageLink` 为 V1 专属装饰器，`@ComponentV2` 内不可用；若组件先迁而键仍为 V1 存储，组件读取失联。**修正：三组件移至批次 4，与全局键切换同批联动。**

### 批次 3：页面（依赖度升序，6 单元 + Index 壳）

| # | 文件 | 迁移要点 |
|---|---|---|
| 3.1 | `pages/LogPage.ets` | 独立路由页，依赖面最小，试点单元 |
| 3.2 | `pages/AddSubscriptionSheet.ets` | 条件渲染面板 |
| 3.3 | `pages/SettingsPage.ets` | **含 SettingsRow 组件联动**（2.4）：accentColor 键读写点 |
| 3.4 | `pages/SourcePage.ets` | 订阅源详情 |
| 3.5 | `pages/HomePage.ets` | 首页列表 |
| 3.6 | `pages/PlayerOverlay.ets` | 播放层（体量大、状态多） |
| 3.7 | `pages/Index.ets` | **@Entry 壳，最后迁**：挂全部 AS_* 键读写，是批次 4 的前置 |

### 批次 4：挂键组件 + 全局状态（联动批，风险最高）

| # | 单元 | 迁移要点 |
|---|---|---|
| 4.1 | 全局键切换：`AS_*`（瞬态 UI）→ `AppStorageV2`；`KEY_*`（持久化）→ `PersistenceV2`；键清单见 `Constants.ets` | **前置依赖 3.7 Index 迁移完成**（Index 是多数键的读写方） |
| 4.2 | `component/MiniPlayer.ets` → `@ComponentV2` | `@StorageProp` → `AppStorageV2.connect` 或 `@Provider`/`@Consumer` |
| 4.3 | `component/QueueSheet.ets` → `@ComponentV2` | 同上；`@State` → `@Local` |
| 4.4 | `component/QueueDrawer.ets` → `@ComponentV2` | `@StorageLink`（双向）→ AppStorageV2 引用（天然双向） |
| 4.5 | `service/PlayerController.ets` | **已关闭（无需迁移，2026-10-11）**：审计纠错——该文件从未使用 `@Observed`+`@Track`（git 全历史 `-S` 检索零命中），实为零装饰器纯类（手动 `subscribe`/`emitUi` 广播 + 版本计数，消费方 `syncFrom` 拷贝 `@Local`），代际无关；加 `@ObservedV2`+`@Trace` 重写无可见收益（UI 不直接观测其字段），按 YAGNI 经用户确认关闭 |

## 二、子阶段任务拆解（T030）

每单元统一模板（独立执行 / 独立验收 / 独立回滚）：

1. **执行**：单 struct 内装饰器整体换代（V1→V2 对照：`@State`→`@Local`、`@Prop`→`@Param`、`@Watch`→`@Monitor`、`@Provide`/`@Consume`→`@Provider`/`@Consumer`）；单 struct 内 V1/V2 装饰器不可混用。
2. **验收**：`arkts_check` 零错误 → `devecocli build` 成功 → 该单元功能回归（页面/组件走查）→ 未迁移部分不受影响（构建即证）。
3. **回滚**：该单元独立 `git revert`；跨单元耦合出现时（禁止）以最后通过单元为基线。

批次内串行（1.1→1.6、3.1→3.7），批间顺序不可调换（模型→页面→全局状态）；批次 4 内 4.1 先行、4.5 最后。

## 三、边界规则与风险标注（T031）

### 迁移边界 4 规则（AGENTS.md 已固化）

1. 单 struct 内 V1/V2 装饰器不可混用。
2. V1 状态不得持有 `@ObservedV2` 实例。
3. `AppStorage`（V1）与 `AppStorageV2` 不互通，全局存储切换须在相关页面全部迁移后。
4. 每批迁移独立提交、独立回归。

### 风险标注

| # | 风险 | 说明 | 缓解 |
|---|---|---|---|
| ① | 批次 2 挂键组件与批次 4 全局键的依赖冲突 | 见批次修正（§一）：三组件已移至批次 4 | 顺序修正后消除 |
| ② | 规则②与批次 1 的表面冲突：V1 页面 `@State` 持有 `@ObservedV2` 模型数组 | 本项目模型均为不可变数据载体（API 解析后字段不变），列表刷新走数组级替换（`@State` 第一层仍观察），**无字段级观察需求**（无 `@ObjectLink` 用例） | 批次 1 各单元验收时确认无字段级观察依赖；发现 `@ObjectLink`/字段监听用例即回滚该单元 |
| ③ | PlayerController（4.5） | 上帝对象：播控+队列+订阅+收藏，与 AudioPlayer/MediaSession/AVSession 深度交织 | 置最后；单元前先跑全量回归基线；失败即回滚 |
| ④ | 全局键切换（4.1） | 键面广（AS_* 瞬态 + KEY_* 持久化），读写点分散在 Index/PlayerController/SettingsPage | 前置 3.7 完成；按 `Constants.ets` 键清单逐键核对读写点；瞬态键与持久键分两个子提交 |
| ⑤ | V2 迁移与真机验证 | KI-6 前车之鉴（睡眠定时未真机验证） | 每批完成后真机走查再进下一批 |

### 迁移前后置条件

- 前置：轮 1-3 全部合入（API 26 基线、令牌化、边界契约）。
- 迁移前新代码保持 V1 一致（AGENTS.md 已约定）。
- 最终批次（4.5）完成后执行收尾轮（tasks.md T032-T036）。
