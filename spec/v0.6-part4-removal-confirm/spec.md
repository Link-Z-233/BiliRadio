# Spec: 移除前确认开关与识别链路收尾（v0.6-part4）

**Input**: User requests: ① 设置页增加「移除前确认」开关——关闭后从歌单移除收藏来源视频不再弹「同时取消收藏？」确认弹窗，移除纯本地（云端收藏保留）；② 登录状态提醒行（statusMsg）观感收敛；③ 番剧/影视（EP）链接从「无法识别」改为明确「暂不支持」提示（不做 PGC 功能）；④ KI-7 B3（lists 无 type 参数合集/系列歧义）与 B8（BV 形态校验加严）修复；⑤ 登记对账（feature.json 活跃目录切换、PROJECT_NOTES 待销项清理、BILI_NOTES §3 补录）。①②为插入功能项，③④⑤为原小收尾轮内容，经批准合并单轮交付。

**Output**: 单轮六项全部交付：新设置开关（含 PlayerController 询问闸）、EP 明确提示、lists 回退链、BV 校验加严、statusMsg 收敛、三处登记对账完成。

**Context**: v0.6-part3（订阅源管理三件套）40 任务已全部完成且真机复测通过；PROJECT_NOTES 第三章「订阅源导出导入」为 part3 交付前登记的待决项，本轮销项。feature.json 仍指向 v0.6-part2-debt-cleanup，本轮切至本目录。

## User Stories

### US1 移除前确认开关 (Priority: P1) 🎯 MVP

设置页账号组（登录态）新增「删除前询问」开关行（默认开，与现状弹窗行为一致）；关闭后，从歌单移除命中本人收藏的条目时跳过「同时取消收藏？」弹窗，直接纯移除——云端收藏不变、不联动取消。

**Why this priority**: 用户明确要求的功能项，且是本轮唯一新增交互入口。

**Independent Test**: 开关默认开时移除收藏来源条目弹窗行为与现状一致；关闭后同操作不弹窗、B 站收藏夹内该视频仍在；重新打开后弹窗恢复。

1. **Given** 开关默认开, **When** 从歌单移除命中本人收藏的条目, **Then** 弹「同时取消收藏？」确认框（现状行为零变化）
2. **Given** 开关关闭, **When** 同上操作, **Then** 不弹窗、条目直接移除、云端收藏保留
3. **Given** 开关关闭, **When** 从歌单移除非收藏来源条目, **Then** 行为与现状一致（本就不弹窗）
4. **Given** 开关任一状态重启应用, **When** 再次进入设置页, **Then** 开关状态与退出前一致

### US2 EP 链接明确提示 (Priority: P2)

添加订阅面板输入番剧/影视链接（`bilibili.com/bangumi/play/ep|ss{数字}` URL、纯文本 `ep|ss{数字}` 号、经 b23.tv 短链跳转的上述页面）时，明确提示「暂不支持番剧/影视内容」，不再报「未识别到有效链接」。

**Why this priority**: 现状「无法识别」提示误导用户以为链接坏了；明确提示是零成本体验修复。PGC（ep/ss/bangumi）订阅为完整功能轮量级，本轮不做。

**Independent Test**: 粘贴番剧分享链接（含 b23.tv 短链形态）提交，toast 提示「暂不支持番剧/影视内容」，面板保持打开。

1. **Given** bangumi/play/ep 或 ss URL, **When** 提交识别, **Then** toast「暂不支持番剧/影视内容」
2. **Given** 纯文本 ep474556 或 ss444417, **When** 提交识别, **Then** 同上
3. **Given** b23.tv 短链 302 至番剧页, **When** 提交解析, **Then** 同上（短链链路先返回目标再识别，提示一致）

### US3 KI-7 B3 lists 歧义回退 (Priority: P2)

`space.bilibili.com/{mid}/lists/{id}` 无 `type` 参数时不再默认按合集处理，改为回退链自动判定：先按合集（season）取 meta，未命中（接口报错、空 meta 桩，或 meta 所属 UP 与 URL `{mid}` 不符——合集/系列 id 共用数字空间存在跨 UP 撞号，真机实测系列 id 302414 同号命中别 UP 的真实合集）再按系列（series），双失败明确报错「合集/系列信息获取失败」。带 `type=season|series` 参数的 URL 行为不变。

**Why this priority**: KI-7 登记遗留问题，现状对系列链接（无 type 参数形态）必订阅错类型。

**Independent Test**: 粘贴无 type 参数的系列 lists 链接，订阅成功且类型为系列；粘贴无 type 参数的合集 lists 链接，订阅成功且类型为合集。

1. **Given** 无 type 参数的系列 lists URL, **When** 提交识别订阅, **Then** series meta 命中、订阅类型为系列
2. **Given** 无 type 参数的合集 lists URL, **When** 提交识别订阅, **Then** season meta 命中、订阅类型为合集
3. **Given** 无 type 参数且 id 双类型均无效, **When** 提交识别订阅, **Then** toast「合集/系列信息获取失败」
4. **Given** 带 type=season 或 type=series 参数的 lists URL, **When** 提交识别订阅, **Then** 行为与现状一致（显式定型，不走回退）

### US4 KI-7 B8 BV 校验加严 (Priority: P3)

BV 号形态校验从 `[0-9A-Za-z]{10}` 加严为 base58 字符集 `[1-9A-HJ-NP-Za-km-z]{10}`（排除 0/O/I/l，真实 BV 号生成算法不含这些字符），伪 BV 号在本地识别阶段拦截。存在性校验维持网络路径（view 接口失败已有提示）。

**Why this priority**: KI-7 登记遗留问题；形态加严是唯一免网络的校验手段，成本两处正则。

**Independent Test**: 输入含被排除字符的伪 BV（如 `BV0000000000`），提示未识别到有效链接而非进入网络请求后失败；真实 BV 正常识别。

1. **Given** 伪 BV 含 0/O/I/l 字符, **When** 提交识别, **Then** 不命中 bv 分支，按未识别处理
2. **Given** 真实 BV 号, **When** 提交识别, **Then** 正常命中（无误拦）

### US5 statusMsg 行收敛 (Priority: P3)

设置页账号组登录状态提醒行（statusMsg，五类文案：验证中/成功/失败/已退出/Cookie 缺 SESSDATA）观感收敛：字号 13→12、上下边距由 L/XL 收紧为 S/S、补整行宽度铺满实现居中。显示条件、文案、颜色不变（「已退出」等未登录态仍需展示）。

**Why this priority**: 用户要求的观感调整，纯样式零逻辑。

**Independent Test**: 触发登录状态变化（如退出登录），提醒行字号变小、间距收紧、文本水平居中于分组内。

1. **Given** 任一登录状态提醒文案非空, **When** 账号组渲染, **Then** 字号 12、上下 TOKEN_SPACE_S 边距、水平居中
2. **Given** statusMsg 为空, **When** 账号组渲染, **Then** 行不渲染（现状不变）

## Functional Requirements

- **FR-001**: 系统 MUST 在设置页账号组登录态「历史同步」与「退出登录」之间提供「取消收藏提醒」开关行（Toggle 样式，subtitle「删除来自个人收藏夹的歌单视频时，询问取消B站上的收藏」），仅登录时展示
- **FR-002**: 开关状态 MUST 持久化（`Constants.KEY_UNFAVORITE_ASK`，1=开 0=关，缺省 1 无迁移）
- **FR-003**: 开关关闭时 `removeSelectedFromPlaylist` MUST 跳过 `confirmUnfavoriteRemoval` 询问，直接纯移除（云端收藏不变）；开启时询问行为与现状完全一致
- **FR-004**: EP 形态（bangumi/play/ep|ss URL、纯文本 ep|ss 号）MUST 识别为统一 `'ep'` 类型并提示「暂不支持番剧/影视内容」；短链解析链路对 `'ep'` 目标按成功返回目标、由消费方提示
- **FR-005**: lists URL 带 `type=season|series` 参数时 MUST 显式定型（现状语义）；无 type 参数时 MUST 返回 `'lists'` 类型，由消费方回退链判定（先 season 后 series；以 URL `{mid}` 为锚点消歧——meta.mid 与锚点匹配才采纳，排除跨 UP 撞号；双失败明确报错）
- **FR-006**: BV 形态校验 MUST 加严为 base58 字符集（`BV[1-9A-HJ-NP-Za-km-z]{10}`，recognizeInput 全文扫描与短链路径短路两处同步）
- **FR-007**: statusMsg 行 MUST 收敛样式：`TOKEN_FONT_BODY_S` 字号、`{top: TOKEN_SPACE_S, bottom: TOKEN_SPACE_S}` 边距、`width('100%')`，且置于账号 SettingsGroup 之外（落在 `page_background` 非卡片底上，与卡片视觉分离）；显示条件与文案不变

## Success Criteria

- **SC-001**: US1 验收四场景全部通过（默认开弹窗/关不弹窗/非收藏来源不弹窗/状态持久）
- **SC-002**: US2 三形态（URL/纯文本/短链）均明确提示且面板保持打开
- **SC-003**: US3 无 type 参数合集与系列链接均订阅正确类型
- **SC-004**: US4 伪 BV 本地拦截、真实 BV 零误拦
- **SC-005**: 现有六类识别（bv/av/up/fav/season/series）与短链解析零回归

## Edge Cases & Design Considerations

- 开关关闭后移除的条目：云端收藏保留（用户决策——「不联动、纯移除」而非「自动取消收藏」）
- `unfavoriteCurrent`（播放页手动取消收藏）不在询问弹窗链路上，不受开关影响
- 回退链正确性依赖「合集/系列 id 无同 UP 撞号」——真机实测确认跨 UP 撞号存在（系列 302414 撞别 UP 合集）且已被 URL mid 锚点排除；同 UP 撞号不可消歧（按合集命中），概率极低未处理
- BV 加严误拦风险：真实 BV 由 base58 混淆表生成、天然不含 0/O/I/l，无误拦；PiliPlus 旁证用宽松式 `bv1[0-9a-zA-Z]{9}`（仅锚定前缀），本项目取字符集级更严一级
- 网络失败场景回退链多一次 series 请求后仍得到错误提示，可接受
