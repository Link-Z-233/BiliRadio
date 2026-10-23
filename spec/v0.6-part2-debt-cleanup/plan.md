# Implementation Plan: 构建告警技术债清理（v0.6-part2）

**Input**: Feature specification from `spec/v0.6-part2-debt-cleanup/spec.md`

## Summary

清偿 v0.6-part1 清点的三项可执行构建告警债：① `PlayerController.showAnomalyToast` 废弃 `promptAction.showToast` 迁移到零装饰器广播（anomalyToastMsg/anomalyToastTick + Index 订阅消费），行为零变化；② oh-package SemVer 告警触发源实测定位后最小改动消除；③ Appearance:148 设备可用性告警查证（已完成：d.ts 无设备限制标注，定性误报，维持现状登记在案）。存档项维持不处理。

## Technical Context

**Language/Version**: ArkTS（ArkUI），compatibleSdkVersion 26.0.0，单模块
**Primary Dependencies**: 零第三方依赖
**State Management**: 沿用项目现状——PlayerController 零装饰器广播（字段 + emitUi，消费方订阅比对 tick）；涉及页面 Index.ets 已迁 V2
**Storage**: 不涉及新存储；anomalySet 持久化链路不动
**Testing**: 无测试套件（devDependencies 有 hypium 但无测试文件）；自检 = arkts_check + devecocli build + 构建日志告警清点
**Target Platform**: HarmonyOS NEXT（phone/tablet），华为真机
**Project Type**: 单模块移动应用
**Performance Goals**: toast 广播经既有 emitUi 节流链路，tick 比对恒假零开销（与 errorTick 同构）
**Constraints**: 异常 toast 去重窗（PLAYBACK_ERROR_DEDUP_MS）语义、日志记录点、深浅色窗口配色零回归；不改包名与 AppScope versionCode
**Scale/Scope**: 改动约 4 文件（PlayerController.ets、Index.ets、根或 entry oh-package.json5、登记文档），低复杂度卫生轮

## Project Structure

### Documentation (this feature)

```text
spec/v0.6-part2-debt-cleanup/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/Index.ets                  # 订阅回调加 anomalyToastTick 比对（既有订阅块内）
└── service/PlayerController.ets     # 删 promptAction import；anomaly toast 改广播
oh-package.json5                     # version 修正（实验定位后，根或 entry）
entry/oh-package.json5               # 同上，与根版本策略联动
```

**Structure Decision**: 沿用既有项目架构（service/pages 分层），不引入 MVVM 迁移，不新增文件。

## Complexity Tracking

无 Constitution 违规。

## Research & Decisions

### R1: US1 toast 迁移通道选型

- **Decision**: 零装饰器广播——PlayerController 新增公开快照字段 `anomalyToastMsg: string` + `anomalyToastTick: number`（紧邻既有 anomaly 块，anomalyToastLastAt 旁）；`showAnomalyToast` 改为：去重窗内 return（现状不变）→ 通过则更新水位、写 msg、tick++、emitUi()；Index.ets 既有订阅回调加第三组 tick 比对，经 `this.getUIContext().getPromptAction().showToast({ message: controller.anomalyToastMsg })` 弹出
- **Rationale**: 与 errorTick（v0.5-part3 US6）/unfavToastTick（v0.6-part1 US1）既有模式逐字同构；AGENTS 明文「PlayerController 新增公开 UI 状态沿用零装饰器广播模式」；Index 已有 getPromptAction 用法，零新依赖
- **Alternatives considered**: ① UIContext 作用域 `getPromptAction()` 在 PlayerController 内直调——拒：service 层无 UIContext 引用，注入引用引入 service→UI 耦合与生命周期风险；② 并入 errorTick 通道——拒：spec Edge 明确异常 toast 去重窗语义独立，不共用窗与通道

### R2: US1 行为零变化保障点

- **Decision**: 迁移不改动的清单——`anomalyToastLastAt` 水位机制与 PLAYBACK_ERROR_DEDUP_MS 窗时长；`handleAnomalyOnPrepared` 内 3 处调用点（:325/:331/:338）签名不变零改动；Logger 日志行位置不动；Index 订阅回调在 `controller.init()` 之前捕获 tick 初值（与 lastErrorTick 同位置，冷启动续播早期异常不漏）
- **Rationale**: FR-001/SC-002 要求行为逐项一致；改动收敛在 showAnomalyToast 函数体 + Index 订阅块两处

### R3: US2 SemVer 告警触发源实验矩阵

- **Decision**: 实施轮按序实验定位：① 基线构建确认告警在 → ② 候选 A：根 oh-package.json5 补 `"version"`（值与 entry 策略一致）→ 构建，消失即定位 → ③ 候选 B（A 不中）：entry version 0.1.0 → 非 0.x 主版本（如 1.0.0）→ 构建，判定 hvigor 对 0.x 的判定 → ④ 以最小改动固化，回滚不必要的实验改动
- **Rationale**: spec Open Question 明示「启动轮实测定位」；构建是唯一可信判据；两次实验上限内必然定位（触发源只有根/entry 两处 version 字段）
- **Alternatives considered**: 直接猜一处改掉——拒：无构建证据即无 SC-001 验收依据

### R4: US3 Appearance:148 告警查证（已完成的 Phase 0 研究）

- **Decision**: 定性误报，代码维持现状，查证证据登记于此
- **Rationale**: 本机 SDK `@ohos.window.d.ts:6427`（`setWindowBackgroundColor(color: string | ColorMetrics): void`）标注为 `@syscap SystemCapability.WindowManager.WindowManager.Core`、`@crossplatform [since 10]`、`@atomicservice [since 11]`、`@since 9`——**无任何设备类型限制标注**，不支撑「unavailable to phone, tablet」判定；真机窗口背景/系统栏配色已验证正常（v0.6-part1 轮）；等价替代 API `setBackgroundColor` 为 since 6 / deprecated 9 的更老接口，无可迁移目标。告警疑为 lint 工具对 API 数据库的误判
- **Alternatives considered**: 换用其他窗口背景 API——拒：d.ts 证据 + 真机行为双确认无设备限制，无必要改动；深挖 lint 工具内部数据源——拒：证据已足，收益不成比例（ponytail）

### R5: 存档项维持（FR-004）

- **Decision**: SaveButton 权限误报、@throws 例行提示、syscap 提示三项维持不处理，spec 存档说明即为登记处，不再重复登记
- **Rationale**: spec「设计内存档项」节已完整记载定性理由；SC-004 要求构建仍出现同款提示（预期内非回归）

## Data Model

不涉及新数据实体。修订：

- **PlayerController 公开快照字段（新增 2）**: `anomalyToastMsg: string`（弹出的消息文本）、`anomalyToastTick: number`（版本计数，去重通过才递增）——与 errorTick/unfavToastTick 同构，随 emitUi 广播
- **oh-package.json5 version 字段（补全或修正）**: 根/entry 关系在实施实验后定，两处版本策略保持一致（单一真相源原则）

## Contracts & Interfaces

- **showAnomalyToast(message: string): void（PlayerController，私有）**: 签名不变；实现从「直调废弃 promptAction.showToast」改为「去重通过 → 快照字段 + tick++ + emitUi」；调用方 3 处零改动
- **Index.ets 订阅回调（既有 controller.subscribe 块）**: 新增 anomalyToastTick 比对分支；弹出通道 `this.getUIContext().getPromptAction().showToast(...)` 与既有 errorTick/unfavToastTick 分支同款
- **oh-package.json5（根/entry）**: 仅 version 字段；包名（name）、AppScope versionCode 不动，安装升级行为不受影响
