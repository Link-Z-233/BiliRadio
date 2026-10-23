# Feature Specification: 构建告警技术债清理（v0.6-part2）

**Status**: Draft（仅登记未启动——v0.6-part1 收尾完成后由用户另行启动轮次）
**Input**: v0.6-part1 验证轮全量构建日志告警清点（用户指示「将这些技术债记录到 part2 的 spec」「仅记录，不执行」）

## Overview

v0.6-part1 验证轮对构建日志 WARN 全量清点，分两类：**可执行债项 3 项**（废弃 toast API 迁移、oh-package 版本号 SemVer 告警、Appearance 设备可用性告警查证）与**设计内存档项**（SaveButton 权限误报、@throws 例行提示、syscap 提示——维持不处理，在本 spec 存档说明防复发误判）。轮次启动时清偿可执行项、复核存档结论，目标为构建告警噪音显著收敛且行为零回归。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 废弃 toast API 迁移 (Priority: P1)

`PlayerController.showAnomalyToast`（:301，v0.5-part5 引入的异常 toast 通道）使用已废弃的全局 `promptAction.showToast`。迁移到非废弃通道（候选：经 UIContext 作用域 `getPromptAction()`，或并入 Index.ets 既有 errorTick/unfavToastTick 订阅式 toast 广播），行为零变化：异常去重窗（PLAYBACK_ERROR_DEDUP_MS 窗内只弹一次）、日志恒记。

**Why this priority**: 唯一处于播放关键链路的功能性技术债——废弃 API 在未来 SDK 版本可能移除，越晚迁移编译断裂风险越大。

**Independent Test**: 触发播放异常（断网/失效源）观察 toast 照常弹出且去重生效；构建日志中该行 deprecated 告警消失。

**Acceptance Scenarios**:

1. **Given** 播放中发生流异常, **When** 异常触发, **Then** toast 弹出，去重窗内连续异常只弹一次（现状语义）
2. **Given** 迁移后构建, **When** 检查告警输出, **Then** `PlayerController:301 'showToast' has been deprecated` 告警消失
3. **Given** 全代码检索, **When** 查全局 `promptAction` 直接调用, **Then** 项目内无残留废弃调用（如有必要残留则登记豁免）

---

### User Story 2 - oh-package 版本号 SemVer 告警修复 (Priority: P2)

构建恒报 `The version number of the 'entry' module does not comply with the SemVer specification`。事实核查：`entry/oh-package.json5` version 为 `"0.1.0"`（形式合规）、根 `oh-package.json5` 无 version 字段——真实触发源待实测定位（候选：根缺失 version，或 hvigor 对 0.x 主版本的判定）。定位后最小改动消除（补根 version 或升 entry 版本号），不影响包名、安装与升级。

**Why this priority**: 纯构建卫生项，无运行时影响，排功能债之后。

**Independent Test**: 修改后构建，检查 SemVer 告警消失。

**Acceptance Scenarios**:

1. **Given** 触发源定位并修改, **When** 构建, **Then** SemVer 告警消失
2. **Given** 版本号调整, **When** 部署安装, **Then** 安装与覆盖升级正常（versionCode 在 AppScope/app.json5 维度，不受影响）

---

### User Story 3 - Appearance 设备可用性告警查证 (Priority: P3)

`Appearance.ets:148`（`win.setWindowBackgroundColor`）报 `This API is unavailable to phone, tablet`，但窗口背景/系统栏配色真机已验证正常——疑似 SDK d.ts 设备标注与 lint 判定问题。查证：读本机 SDK `window.d.ts` 对该 API 的设备标注，定性误报或可规避；误报则登记结论维持现状，有最小规避写法（如等价 API 替代）则调整。

**Why this priority**: 功能正常、疑似误报，仅清噪音，排最后。

**Independent Test**: 查证结论登记（本 spec 追加或 PROJECT_NOTES）；若调整写法，构建告警消失且深浅色行为零回归。

**Acceptance Scenarios**:

1. **Given** SDK 标注查证完成, **When** 下结论, **Then** 误报定性登记在案，或等价写法调整后告警消失
2. **Given** 深浅色切换, **When** 观察窗口背景与系统栏配色, **Then** 行为零回归

---

### 设计内存档项（不处理，防复发误判） *(mandatory)*

以下告警为设计内误报或例行提示，**维持不处理**，存档说明防后续轮次误判：

- **SettingsPage:432 WRITE_IMAGEVIDEO 告警**：`createAsset` 在安全控件 SaveButton 的点击回调内执行（点击时系统临时授权写相册，无需静态权限声明），静态检查器识别不了安全控件上下文——设计内误报
- **"Function may throw exceptions" 例行提示**（QueueSheet 237/498/641、HistorySheet 164/236/477 及 service 层散布多处）：SDK d.ts `@throws` 标注的例行提醒，调用点均在 try/catch 内或失败无实质影响
- **syscap 提示**（WbiSigner/AppSigner crypto createMd/update/digest、AudioPlayer media/audio、GripDetector motion 全套）：应用目标为 HarmonyOS NEXT 华为真机，设备能力齐备，deviceTypes（phone/tablet）下行为正常

### Edge Cases

- toast 通道迁移不得改变去重窗时长与日志记录点（v0.5-part5 FR-008 语义）
- Index.ets 订阅式 toast 若作为迁移目标，需评估异常 toast 与既有 errorTick/unfavToastTick 的合并方式（去重窗语义独立，不共用窗）
- 根 oh-package.json5 补 version 需与 entry 版本策略一致（单一真相源原则，两处版本号关系在实施时定）
- Appearance 若调整写法，须确认新写法在 API 26 真机与模拟器行为一致

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `showAnomalyToast` MUST 迁移至非废弃 toast 通道；异常 toast 触发、去重窗、日志行为零变化
- **FR-002**: oh-package SemVer 告警触发源 MUST 实测定位并以最小改动消除；安装与升级行为不受影响
- **FR-003**: Appearance:148 告警 MUST 查证定性（误报登记在案，或等价写法调整）；深浅色窗口配色零回归
- **FR-004**: 设计内存档项（SaveButton 权限误报/@throws 提示/syscap 提示）MUST 维持不处理，仅以本 spec 存档

### Key Entities

不涉及新数据实体。涉及修订：

- **showAnomalyToast（PlayerController）**: 调用通道迁移，语义不变
- **oh-package.json5（根/entry）**: version 字段补全或修正
- **Appearance 窗口配色链**: 至多写法规避，无行为改动

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 全量构建输出中三项可执行债项对应告警全部消失
- **SC-002**: 异常 toast 行为（触发/去重/日志）与现状逐项一致
- **SC-003**: 深浅色窗口背景与系统栏配色零回归
- **SC-004**: 存档项维持不改，构建仍出现同款提示（预期内，非回归）

## Assumptions

- 本 spec 为记录性质，实施排期由用户另行指示（v0.6-part1 收尾后启动）
- toast 迁移沿用项目既有 UIContext 广播/订阅模式，不引入新依赖
- 版本号调整不影响已安装用户升级（升级判定走 AppScope versionCode）
- 存档项结论若被后续 SDK/设备变化推翻（如废弃 API 移除、syscap 变化），按新事实重开条目

## Open Questions

- SemVer 告警真实触发源（根缺 version vs hvigor 对 0.x 判定）——启动轮实测定位
- Appearance 告警的 SDK 标注性质——启动轮读本机 SDK window.d.ts 查证
