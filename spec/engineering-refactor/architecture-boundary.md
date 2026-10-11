# 模块边界契约（architecture-boundary）

> engineering-refactor 实施轮 3 产出（T025-T027）。零行为变化约束：本轮只契约化与审计，不做文件拆分。

## 一、模块边界契约

| 模块 | 职责 | 允许依赖 | 禁止依赖 |
|---|---|---|---|
| `model/` | 纯数据类（无逻辑、无状态观测） | model/ 内部、内建类型 | service/、pages/、component/ |
| `service/` | 业务逻辑/B 站 API/存储/播控（单例范式 `X.getInstance()`） | model/、service/ 内部（含 `Constants`） | pages/（反向）、component/（反向） |
| `pages/` | 页面组装与交互 | service/、model/、component/、pages/ 内部 | — |
| `component/` | 可复用 UI | model/、`Constants`、service/ 单例（见 §三耦合点）、component/ 内部 | pages/ |
| `service/Constants.ets` | 唯一常量真相源（存储键/AppStorage 键/令牌/色值/超时/页大小） | 内建类型（零 import） | 任何业务模块（防循环） |

## 二、依赖方向审计结果（T026，2026-10-11）

全量 import 检索（21 service + 6 model + 7 pages + 7 component）：

- **反向依赖：零命中**——service 无一引用 pages/component，依赖方向单向成立。
- **`Constants` 零 import** ✅（零业务依赖，防循环达成）。
- **model/ 零外部依赖** ✅（仅 model 内部：`PlayHistoryItem`/`Subscription` → `BiliVideo`）。
- **pages/ 依赖面**：service（PlayerController/BiliService/AppStore 等）+ model + component，均合规。
- **T027 职责归位**：审计零违规，页大小与令牌常量统一引用已在轮 1（T010）/轮 2（T014-T021）完成，本轮无可归位项。

## 三、已知耦合点（登记，不拆分）

| 耦合点 | 现状 | 处理 |
|---|---|---|
| `MiniPlayer`/`QueueSheet` 直接持有 `PlayerController`/`AppStore` 单例 | V1 单例范式的组成部分（组件直调服务），非反向依赖、不属违规 | V2 迁移批次 2 拆解（见 v2-migration-roadmap.md） |
| `PlayerController`（播控+队列+订阅+收藏） | 上帝对象候选 | 登记不拆分；拆分方案列远期 |
| `BiliService`（全部 B 站 API，约 1800 行） | 职责单一（B 站 API 网关），体量大但内聚 | 登记不拆分；文件拆分列远期 |
| `SettingsPage`（1400+ 行） | 页面体量大（分组+多面板） | 登记不拆分；远期可按面板抽组件 |

## 四、契约执行约定

- 新代码必须落位正确模块：数据类 → `model/`、业务逻辑 → `service/`、可复用 UI → `component/`、页面组装 → `pages/`。
- 新增常量一律入 `Constants`（唯一真相源），禁止散落字面量。
- 审计脚本口径（供复查）：`service → pages|component` 命中即违规；`Constants.ets` 出现业务 import 即违规。
