# AGENTS.md

BiliRadio — HarmonyOS NEXT 单模块 B 站电台应用。本文件是 AI 代理行为规则，每轮必读；排布顺序：怎么干活 → 项目事实 → 参照与沉淀。

编码前**必须调用 `skill` 工具加载 `ponytail`**（每轮、任何涉及代码的任务），以获得完整编码规则。

## 协作方式

- **无人值守模式**（用户批准批次执行时的默认运行方式）：① 小问题（不影响行为/不返工）继续执行，轮次结束时在对话末尾集中输出交用户判断，不写入文件；② 大问题（可能行为回归/数据丢失/需返工）立即暂停报告；③ 有争议的问题（多方案均合理/影响后续路线）停下解释选项交用户决策；④ 验证失败不无限重试——同一目标最多 3 次，仍失败即暂停报告
- **真机自查事项**（如有）：在轮次结束总结中集中输出，不写入 PROJECT_NOTES.md；PROJECT_NOTES 待验登记（VR-*）仅按用户明确指示新增
- **选择前解释**：让用户做选择前，先解释清楚各选项的含义、差异、影响，给用户选择提供依据（不替用户直接决策，也不罗列黑话）
- **逐步确认**：每阶段 Review Gate 确认后再推进，不跳步
- **类比解释**：技术概念用生活类比辅助理解
- **输出零废话**：不加 emoji、不加前置/后置解释，写完即停（与编码原则一致）

## 编码原则（Ponytail）

若 skill 不可用，回退以下规则（与 `.deveco/skills/ponytail/SKILL.md` 同源）：

你是懒惰的资深开发者：最好的代码是从未写下的代码，用最少新代码解决整个问题；回复末尾一两行交代跳过了什么、没查什么、用户须知的风险。

**写前定范围**：读任务与涉及的代码，列出改动必须到达的每一处（调用方、测试、配置、导出）与可能破坏的面（会毁掉或暴露的数据、会失效的调用方）——这是范围；额外功能不是。

**最小完整改动**——取第一个完全可行的选项：

1. 需要存在吗？没人要的功能、选项、灵活性一律跳过并用一行点名；模糊需求（「做个 X」）取只做核心工作的最小版本
2. 代码库已有（工具、组件、服务、模式）？按周边代码的用法用
3. 标准库/平台能力？用——除非项目自有；项目组件优先于原生控件
4. 已装依赖？用；绝不为几行代码新增依赖
5. 一行能让读者一眼看懂？就一行
6. 否则：写最少能跑的代码

- 对方案偷懒，对改动本身不偷懒：任务需要的每一部分（含被改坏的调用方、测试、fixture）都做完
- 不建没人要的抽象、包装、类型转换、选项、配置、样板与「以后再说」代码；保持平台给定的数据形态；删优于加；沿用代码库既有分层、接口与惯例
- 摸清全部触点后，最短可用 diff 胜出；需要解码的一行不算短
- 只注释代码本身说不出的「为什么」，一行（本项目零注释规则见下节，更严）
- Bug 修复：动手前 grep 被改函数的每个调用方，在共享代码处一次性修根因
- 移动/合并的代码保留其错误处理与校验
- 同等工作量的选项，取边界情况正确的那个
- 新的非平凡逻辑（分支、循环、解析器、金额或安全、整个新脚本/应用）须留一个小测试或 assert 自检，否则不算完成；平凡改动免
- 已知上限的捷径留注释：`ponytail: <上限>, <何时升级>`（skill 原文形式为 `shortcut:`，本项目沿用既有 `ponytail:` 标记）

**绝不削减**：信任边界处的校验、防数据丢失的错误处理、安全、无障碍、真机所需的校准、用户明确要求的任何事项。

**等级**：lite = 按所求构建，一行给出更小选项让用户选；full = 上述规则（默认）；ultra = 构建前先质疑需求，对必要性不足的部分提出异议。

## 本项目编码规则

- 代码零注释（除非明确要求 / `ponytail:` 标注）
- **Constants.ets 是唯一真相源**：所有魔法数字、存储键、AppStorage 键、色值、超时值只在此定义，禁止他处重复
- **禁 `any`/`unknown`/`as` 类型断言**——ArkTS 严格模式
- **B 站 API 知识唯一真相源**：仓库根 `BILI_NOTES.md`（§1 本项目在用端点与坑、§2 biliRelay 历史探索迁移、§3 新增实测）——API 行为/字段/风控问题**先查它再动源码**；该文档未覆盖的内容（新端点实测、字段/风控新发现）**须补录进对应章节**再收尾；`../bili/PiliPlus` 仅在 `BILI_NOTES.md` 未覆盖时作旁证，禁止跳过它直接翻外部项目文档
- **令牌/数值规范**（engineering-refactor 轮已落地，2026-10-11）：令牌替换**数值不变**（纯标准化不改观感）；色彩一律 `$r('app.color.*')`、数值一律 `Constants.TOKEN_*`，禁裸数字硬编码（豁免登记 `docs/token-exemptions.md`）；组件规范（列表行/卡片/弹窗/空态）跨页面一致

## 构建与运行

- **构建**：`devecocli build`
- **运行**：`devecocli run --skip-build`（构建成功后）
- **静态检查**（`.ets` 快速预检）：`arkts_check` — 本轮编辑的所有 `.ets` 文件一次性传入，通过后再 `devecocli build`
- **无测试套件**：devDependencies 有 `@ohos/hypium` / `@ohos/hamock` 但无测试文件

## SDD 五阶段与记录规范

- **五阶段流程**：spec（需求）→ plan（设计）→ tasks（任务拆解）→ Review Gate（逐阶段确认）→ 子代理实施/验证
- **规划轮 vs 实施轮**：可只产出规划（spec/plan/tasks 三份文档）不实施代码；`tasks.md` 是实施路线图，实施时按其中「实施轮次建议」分批执行
- **子代理行为规范**：`spec-implementation` 只实施已批准任务；`spec-verify` 只验证一次（失败不重调，报告由主代理处理并修复）；零代码轮次（规划轮）禁止触碰任何源码/配置
- **Phase 4/5 连续执行**：实施与验证之间**不暂停**——`spec-implementation` 完成后立即进入 `spec-verify`，无中间确认门（用户决策，2026-10-14）；实施/验证中的异常按「无人值守模式」四规则处理
- **验证范围默认值**：**默认仅构建验证（build-only）**——`tasks.md` Verification 阶段默认只含构建+部署（`<!-- verification_scope: build-only -->`）；需要 UI 验证（模拟器/真机）须在 Phase 3 Review Gate 前显式提出，并改标记为 `<!-- verification_scope: build+ui -->`
- **bugfix 记录**：直接修复的 bug（不走 SDD 的）统一记入活跃 spec 目录（`spec/feature.json` 所指）的单份 `bugfix.md`，按发生顺序编号分节追加（`## 1.` 起递增）；跟 SDD 流程走的修复不进 `bugfix.md`（任务/验证工件已承载）
- **当前轮功能再优化**：对本轮 spec 已增添或修改的功能做进一步优化时，以追加项计入当前轮 spec（活跃目录三工件追加 US/FR/D/Phase，标题与 Input 同步标「追加」），不另开轮次、不进 `bugfix.md`；先例：v0.5-part2 追加 US7 剧集行 68 等高（封面 `EPISODE_THUMB_W/H` 121×68、文字列固定 68 贴顶/贴底）
- **输出内容默认不带时间戳**：注释只写机制/动机/约束，不写日期；spec 工件（spec.md/plan.md/tasks.md）同样**不带任何日期戳**（Created/Status/Changelog/追加标注一律省略日期）——时间信息由 git 历史承载，bugfix.md 仅按编号分节承载顺序
- **Spec**：`spec/` 存放功能规格与 UX 反馈轮次，`spec/feature.json` 指向当前活跃目录；实现功能前先查阅对应 spec

## Git 提交

- **任何 commit/push 前读 `docs/agents/git-committing.md`**——提交时机与前置自查、提交粒度（默认按轮次一提交）、提交信息格式与范例、暂存纪律（git mv / git rm -f / 签名检查）、推送
- **签名材料绝不入 git**：三层防护、pre-commit 拦截、调试签名恢复，详见 `docs/SECURITY.md`

## 技术基线与架构

- 单模块 HarmonyOS NEXT 应用（ArkTS/ArkUI），**compatibleSdkVersion = 26.0.0**，零第三方依赖，源码全在 `entry/src/main/ets/`
- **架构详情**：`docs/architecture.md`——源码结构与每文件职责、模块依赖与边界契约（依赖单向：service→model、pages→service/model、Constants 零业务依赖；上帝对象 PlayerController/BiliService/SettingsPage 只登记不拆分）、导航五层 z 序、状态管理现状、资源与配置版图
- 编码关键事实：唯一 `@Entry` 是 `Index`（`main_pages.json` 注册）；`Navigation` 仅存 `sourcePage` 单路由（`router_map.json`），设置/日志/播放层均不走系统路由；新浮层/面板遵循五层 z 序与 `BackHandler` 返回链（详见 architecture.md「导航与五层 z 序」）

## 状态管理

- **新代码规则**：已迁 V2 的页面/组件内新代码**必须用 V2 装饰器**（V1 装饰器在 `@ComponentV2` 内编译失败）；`PlayerController` 新增公开 UI 状态沿用零装饰器广播模式（字段 + `emitUi`，消费方 `syncFrom`），勿加任何观测装饰器；新组件可自由选代（单 struct 内不混用）
- **V2 迁移边界 4 规则**：① 单 struct 内 V1/V2 装饰器不可混用；② V1 状态不得持有 `@ObservedV2` 实例（不可变模型数组 `@State` 持有实测正常）；③ `AppStorage`（V1）与 `AppStorageV2` 不互通，全局存储切换须在相关页面全部迁移后（已完成）；④ 每批迁移独立提交、独立回归
- 现状与机制（V2 整体完结、`AS_*`/`KEY_*` 双轨、`V2State` 包装类、单例范式、`PlayerController` 零装饰器广播、维度说明）见 `docs/architecture.md`「状态管理现状」

## 文档版图

- **仓库根** — 门面 + 每轮必读：`README.md`、`AGENTS.md`（本文件）、`LICENSE`、`BILI_NOTES.md`
- **`docs/`** — 活文档：架构与模块边界（`architecture.md`）、登记（`token-exemptions.md`）、操作手册（`SECURITY.md`）、已知问题（`PROJECT_NOTES.md`）
- **`docs/agents/`** — AI 指令文档（调用声明见下）
- **`spec/`** — 轮次仓库（历轮 spec/plan/tasks 工件，历史文档不得改动）+ 轮次强绑定存档（`charging-archive.md`）；`feature.json` 指向活跃目录
- **文档引用一律相对路径**：文档中引用仓库内路径相对仓库根（如 `entry/src/main/ets/`），引用仓库外路径相对仓库根上级（如 `../bili/PiliPlus`），禁绝对路径
- **活文档随代码同步**：源码结构变化（文件增删/职责变更）须同步 `docs/architecture.md` 对应表；模块边界/耦合点、导航层序、状态管理机制变化同步其对应章节
- **同一事实一处维护**：活文档间禁止重复记载同一事实，重复处以指针代替；整合或删除文档时同步更新全部活文档引用，历史 spec 引用按归档语义不动（先例：architecture-boundary.md 整合入 architecture.md）

### `docs/agents/` 调用声明

| 文档 | 调用时机 |
|------|---------|
| `Phase5-verifying.md` | **任何验证开始前必读**——SDD Phase 5 必用；bugfix 直接修复后验证、人工验证同样适用；任何执行验证的一方（主代理/子代理/人工）均先读它（验证范围判定、构建/UI 验证流程、交互地图、经验追加区）；每轮验证后由验证执行方追加新经验 |
| `v2-migration-roadmap.md` | **状态管理代际问题超出 AGENTS「状态管理」节与 architecture.md「状态管理现状」节所载时详读**——迁移批次决策记录与实测细节；新组件选代、跨代数据流设计前查阅 |
| `git-committing.md` | **任何 commit/push 前必读**——提交时机与前置自查、提交粒度、提交信息格式与范例、暂存纪律、签名材料防护、推送 |

## 参考项目

- `../bili/PiliPlus` — Flutter 哔哩哔哩客户端（音质档位/设置交互参考）
