# AGENTS.md

## 构建与运行

- **构建**：`devecocli build`
- **运行**：`devecocli run --skip-build`（构建成功后）
- **静态检查**（`.ets` 快速预检）：`arkts_check` — 本轮编辑的所有 `.ets` 文件一次性传入，通过后再 `devecocli build`
- **无测试套件**：devDependencies 有 `@ohos/hypium` / `@ohos/hamock` 但无测试文件

## 架构

单模块 HarmonyOS NEXT 应用（ArkTS/ArkUI），源码全在 `entry/src/main/ets/`：

- **pages/** — `Index.ets`（唯一 `@Entry`、单页壳）、`HomePage`、`PlayerOverlay`、`SourcePage`、`SettingsPage`、`AddSubscriptionSheet`
- **service/** — 业务单例：`PlayerController`（播控）、`BiliService`（B 站 API）、`BiliSession`（登录）、`MediaSession`（锁屏/控中心）、`AudioPlayer`、`LinkResolver`、`WbiSigner`、`SleepTimerController`、`AppStore`（持久化）、`SecureStore`、`SubscriptionStore`、`Constants`
- **model/** — 数据类：`BiliVideo`、`AudioQuality`（音质档位）、`PlayHistoryItem`、`Subscription`、`Season`、`FavFolder`
- **component/** — 共用 UI：`MiniPlayer`、`GlassSheet`（通用玻璃浮层容器，队列/历史共用）、`QueueSheet`、`HistorySheet`、`CoverThumb`、`SettingsRow`、`SettingsGroup`、`EdgeHint`
- **模块边界契约**：`spec/v0.3-engineering-refactor/architecture-boundary.md`（依赖单向：service→model、pages→service/model、Constants 零业务依赖；上帝对象 PlayerController/BiliService/SettingsPage 只登记不拆分）

### 导航

- **唯一 `@Entry`**：`Index`（`main_pages.json` 注册）
- **五层 z 序**（v0.4-Part2 层序契约 + 历史面板独立层修订）：L1 导航+胶囊 → L2 设置层+日志层（去路由，Stack 条件渲染层级）→ L3 播放浮层 → L4 历史面板（Index 单一挂载 GlassSheet，入口在设置页）→ L5 队列面板；高层物理覆盖低层，返回链统一 `BackHandler.dismissOverlaysForBack` 逐层关闭
- `Navigation` + `NavPathStack` 仅存 `sourcePage` 一条路由（`router_map.json`）；设置/日志不再走系统路由
- 播放层是 **Stack 条件渲染**（非 `bindContentCover`——KI-5：ModalPage 渲染管线在 API 24 平板断裂）
- 队列是底部弹出面板（Index 单一挂载的 GlassSheet，非系统 sheet）

### 状态管理

- **现状（V2 迁移已整体完结，2026-10-11）**：模型层 `@ObservedV2`+`@Trace`（6 类）；7 页面 + 4 挂键组件（SettingsRow/MiniPlayer/QueueDrawer/QueueSheet）全部 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；CoverThumb/SettingsGroup/EdgeHint 免迁（`@Prop`-only）；`service/PlayerController.ets` **零装饰器纯类**（手动 `subscribe`/`emitUi` 广播 + 版本计数，消费方 `syncFrom` 拷贝进 `@Local`），代际无关，4.5 已关闭为无需迁移（审计纠错：`@Observed`+`@Track` 记载有误，git 全历史零命中）
- `AS_*` 瞬态键经 `service/V2State.ets` 包装类（BoolState/NumState/StrState）走 `AppStorageV2.connect`，读写一律 `.value`，同 key 共享实例天然双向；`KEY_*` 持久化仍走 `AppStore`（preferences）
- AppStorage 键集中在 `Constants.ets`（`AS_*` 瞬态 UI，`KEY_*` 持久化偏好）
- 单例统一范式：`X.getInstance()`（见 `Constants.ets` 文件头注释）
- **新代码规则**：已迁 V2 的页面/组件内新代码**必须用 V2 装饰器**（V1 装饰器在 `@ComponentV2` 内编译失败）；`PlayerController` 新增公开 UI 状态沿用零装饰器广播模式（字段 + `emitUi`，消费方 `syncFrom`），勿加任何观测装饰器；新组件可自由选代（单 struct 内不混用）
- **维度说明**：V2 仅覆盖「状态管理」一个维度，不等于整体重构。路由重构/服务拆分与 V1/V2 **正交**（可独立推进）
- **V2 迁移边界 4 规则**（详述见 `v2-migration-roadmap.md`）：① 单 struct 内 V1/V2 装饰器不可混用；② V1 状态不得持有 `@ObservedV2` 实例（批次 1 实测：不可变模型数组 `@State` 持有正常）；③ `AppStorage`（V1）与 `AppStorageV2` 不互通，全局存储切换须在相关页面全部迁移后（已完成）；④ 每批迁移独立提交、独立回归

## 版本基线（API 26 前提）

- **compatibleSdkVersion = 26.0.0**

## 编码原则（Ponytail）

编码前**必须调用 `skill` 工具加载 `ponytail`**（每轮、任何涉及代码的任务），以获得完整梯子与规则。
若 skill 不可用，回退以下精简原则：

- 动笔前逐级自问：要不要做？库里有？标准库/平台/依赖覆盖？一行够？以上不行才写最少能跑的代码
- Bug 修根因不修表象；不建没人要的抽象；删优于加，无聊优于聪明；最短可用 diff 胜出
- 刻意简化确知天花板时留 `ponytail:` 注释标注天花板与升级路径
- 不可偷懒：理解问题、输入校验、防数据丢失、安全、无障碍、真机校准、明确要求的事项
- **本项目追加**：代码零注释（除非明确要求 / `ponytail:` 标注）、输出零废话、不加 emoji、不加前置/后置解释；写完即停
- **Constants.ets 是唯一真相源**：所有魔法数字、存储键、AppStorage 键、色值、超时值只在此定义，禁止他处重复
- **禁 `any`/`unknown`/`as` 类型断言**——ArkTS 严格模式
- **B 站 API 坑**：APP 端点（`BILI_APP_ARCHIVE_URL`）须 BiliDroid UA（在 `Constants`），非浏览器 cookie；Web 端点须 WBI 签名（`WbiSigner`）；`@ohos.net.http` 的 `maxRedirects: 0` 是「零配额」而非「禁重定向」——短链解析用 `@kit.RemoteCommunicationKit` rcp + `autoRedirect`
- **令牌/数值规范**（engineering-refactor 轮已落地，2026-10-11）：令牌替换**数值不变**（纯标准化不改观感）；色彩一律 `$r('app.color.*')`、数值一律 `Constants.TOKEN_*`，禁裸数字硬编码（豁免登记 `spec/v0.3-engineering-refactor/token-exemptions.md`）；组件规范（列表行/卡片/弹窗/空态）跨页面一致
- **文档引用一律相对路径**：文档中引用仓库内路径相对仓库根（如 `entry/src/main/ets/`），引用仓库外路径相对仓库根上级（如 `../bili/PiliPlus`），禁绝对路径

## 已知问题（PROJECT_NOTES.md）

- **KI-7**：链接识别边缘情况（B3/B7/B8/C2 维持登记）——裸数字一律当 UID
- **DIS-1**：首页下拉刷新已禁用（代码以注释保留，标记 `[DISABLED 2026-10]`）

## 工作方式

- **无人值守模式**（用户批准批次执行时的默认运行方式）：① 小问题（不影响行为/不返工）继续执行，轮次结束时在对话末尾集中输出交用户判断，不写入文件；② 大问题（可能行为回归/数据丢失/需返工）立即暂停报告；③ 有争议的问题（多方案均合理/影响后续路线）停下解释选项交用户决策；④ 验证失败不无限重试——同一目标最多 3 次，仍失败即暂停报告
- **真机自查事项**（如有）：在轮次结束总结中集中输出，不写入 PROJECT_NOTES.md；PROJECT_NOTES 待验登记（VR-*）仅按用户明确指示新增
- **bugfix 记录**：直接修复的 bug（不走 SDD 的）统一记入活跃 spec 目录（`spec/feature.json` 所指）的单份 `bugfix.md`，按发生顺序编号分节追加（`## 1.` 起递增）；跟 SDD 流程走的修复不进 `bugfix.md`（任务/验证工件已承载）
- **当前轮功能再优化**：对本轮 spec 已增添或修改的功能做进一步优化时，以追加项计入当前轮 spec（活跃目录三工件追加 US/FR/D/Phase，标题与 Input 同步标「追加」），不另开轮次、不进 `bugfix.md`；先例：v0.5-part2 追加 US7 剧集行 68 等高（封面 `EPISODE_THUMB_W/H` 121×68、文字列固定 68 贴顶/贴底）
- **输出内容默认不带时间戳**：注释只写机制/动机/约束，不写日期；spec 工件（spec.md/plan.md/tasks.md）同样**不带任何日期戳**（Created/Status/Changelog/追加标注一律省略日期）——时间信息由 git 历史承载，bugfix.md 仅按编号分节承载顺序

### SDD 五阶段

- **五阶段流程**：spec（需求）→ plan（设计）→ tasks（任务拆解）→ Review Gate（逐阶段确认）→ 子代理实施/验证
- **规划轮 vs 实施轮**：可只产出规划（spec/plan/tasks 三份文档）不实施代码；`tasks.md` 是实施路线图，实施时按其中「实施轮次建议」分批执行
- **子代理行为规范**：`spec-implementation` 只实施已批准任务；`spec-verify` 只验证一次（失败不重调，报告由主代理处理并修复）；零代码轮次（规划轮）禁止触碰任何源码/配置
- **Phase 4/5 连续执行**：实施与验证之间**不暂停**——`spec-implementation` 完成后立即进入 `spec-verify`，无中间确认门（用户决策，2026-10-14）；实施/验证中的异常按「无人值守模式」四规则处理
- **验证范围默认值**：**默认仅构建验证（build-only）**——`tasks.md` Verification 阶段默认只含构建+部署（`<!-- verification_scope: build-only -->`）；需要 UI 验证（模拟器/真机）须在 Phase 3 Review Gate 前显式提出，并改标记为 `<!-- verification_scope: build+ui -->`
- **Spec**：`spec/` 存放功能规格与 UX 反馈轮次，`spec/feature.json` 指向当前活跃目录；实现功能前先查阅对应 spec

## Git 提交

- **标题行**：`<type>: <版本-轮次>（<主题>）`，如 `feat: v0.4.0-Part1（浮层视觉重设计 + UX 修复轮）`
- **正文**：要点列表，每块改动一行，写清「做了什么 + 关键机制/根因」，不罗列文件路径清单；同类小项合并一行以「等」收尾
- **不入提交信息**：验证结论与待验登记、文件级明细（git diff 自查）
- **范例**（v0.4.0-Part1 提交信息）：

```
feat: v0.4.0-Part1（浮层视觉重设计 + UX 修复轮）

- QueueDrawer 泛化为 GlassSheet 通用玻璃浮层容器，队列/历史共用，历史面板迁离系统 bindSheet
- UX 修复 12 项：收起键命中区、MiniPlayer 返回闪现、音质三档矩阵、历史多选、账号头像、关于页重写（含内容截断修复）等
- debug 冷启动恢复前移 Index；spec 目录归档重命名，附 Part1 工件与 Part2 双轮规划
```

## 参考项目

- `../bili/PiliPlus` — Flutter 哔哩哔哩客户端（音质档位/设置交互参考）
- `../bili/biliRelay` — B 站 API 取流参考（QUALITY_MAP / fnval）

## 沟通偏好

- **选择前解释**：让用户做选择前，先解释清楚各选项的含义、差异、影响，给用户选择提供依据（不替用户直接决策，也不罗列黑话）
- **逐步确认**：每阶段 Review Gate 确认后再推进，不跳步
- **类比解释**：技术概念用生活类比辅助理解
- **输出零废话**：不加 emoji、不加前置/后置解释，写完即停（与编码原则一致）

## 签名

签名材料**绝不入 git**：三层防护、pre-commit 拦截、调试签名恢复，详见 `SECURITY.md`。
