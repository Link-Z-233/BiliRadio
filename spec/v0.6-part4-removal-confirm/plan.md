# Plan: 移除前确认开关与识别链路收尾（v0.6-part4）

**Input**: spec.md (this directory)

**Tech Stack**: 既有单模块 ArkTS/ArkUI 工程（API 26），全部改动落在既有 5 源文件 + 3 登记文档，零新增文件、零新增依赖。

**Architecture Impact**: 无结构变化——Constants 加一键、LinkResolver 加规则与分型、AddSubscriptionSheet 加分发分支与回退方法、PlayerController 加一读取闸、SettingsPage 加一行改一样式。docs/architecture.md 无需同步（无文件增删、无边界变化）。

**Storage**: 既有 Preferences 经 `AppStore.getNumber/putNumber`（`KEY_UNFAVORITE_ASK`，1=开 0=关，缺省 1）

## Decisions

- **D1 询问闸位置：PlayerController（联动行为 owner）而非 Index 回调**
  - **Decision**: `removeSelectedFromPlaylist` 询问条件（`hits.length > 0 && confirmUnfavoriteRemoval !== undefined`）追加 `askEnabled` 读取项（`AppStore.getNumber(KEY_UNFAVORITE_ASK, 1) === 1`）；`targets` 为空时后续移除代码天然走纯移除——Index.ets 弹窗回调与「移除」按钮路径零改动。
  - **Alternatives considered**: 闸放 Index 回调内（仅改弹窗是否弹出，但联动语义分裂在两处、且关闭时仍需空跑回调链，弃）；开关关闭时跳过 hits 计算（微小优化但条件耦合，弃）。

- **D2 开关行与持久化：复刻「历史同步」行先例**
  - **Decision**: SettingsPage（@ComponentV2）`@Local unfavoriteAskOn` + aboutToAppear 读 `AppStore.getNumber(KEY_UNFAVORITE_ASK, 1) === 1` + toggleChange 写 `putNumber(key, isOn ? 1 : 0)`；行位置账号组登录态「历史同步」与「退出登录」之间，`showToggle/showDivider/subtitle` 照抄历史同步行；文案字面量（账号组惯例）。缺省 1（开）无迁移——老用户行为与现状一致。移除动作发生时实时读取，设置页改动即时生效、无缓存同步问题。
  - **Alternatives considered**: 默认关（老用户行为突变，弃）；AppStorage 瞬态键（重启丢状态，弃）。

- **D3 EP 识别：统一 `'ep'` 类型，消费方 toast**
  - **Decision**: `recognizeInput` 新增规则——URL 形态 `bilibili\.com/bangumi/play/(?:ep|ss)(\d+)`（置于 av URL 规则后）与纯文本 `^(?:ep|ss)(\d+)$`（置于 BV 全文扫描前、裸数字规则前），均产 type `'ep'`；`dispatchRecognized` 加 `case 'ep'` toast「暂不支持番剧/影视内容」（面板保持打开）。短链链路自通：resolveShortLink 逐跳 recognizeInput 对 `'ep'` 非空即返回目标，消费方再识别分发提示。`RecognizeResult.type` 为 string，无模型改动。
  - **Alternatives considered**: ep/ss 分两类型（消费方提示相同，无意义分支，弃）；短链解析内直接报错（破坏「解析器只管解析」分层，弃）。

- **D4 B3 回退链：新 `'lists'` 类型 + `subscribeListsById`（含 mid 锚点消歧）**
  - **Decision**: lists 规则内 type 判定由 `type=series ? 'series' : 'season'` 改为 `type=(season|series)` 显式定型、无参数返回 `'lists'`；`dispatchRecognized` 加 `case 'lists'` → 新方法 `subscribeListsById`：id 校验 + mainBusy 闸 → `fetchSeasonMeta` 成功且 mid 锚点匹配构造 TYPE_SEASON 订阅（含 cover，同 subscribeSeasonById）→ 报错、空 meta 桩或锚点不匹配转 `subscribeSeriesFallback`（`fetchSeriesMeta` 成功且锚点匹配构造 TYPE_SERIES 订阅，不含 cover，同 subscribeSeriesById）→ 双失败/不匹配 toast「合集/系列信息获取失败」。**消歧依据**：真机实测合集与系列 id 共用数字空间存在跨 UP 撞号——系列 302414 删 type 后 season 端点命中别 UP（mid=428192613）的真实合集；以 URL 自带 `{mid}`（资源所属 UP）为锚点，meta.mid 匹配才采纳；无锚点时 mid>0 识别空 meta 桩（BILI_NOTES §3.10）。
  - **Alternatives considered**: 识别时不分型仍默认 season、消费方 catch 内换 series（显式 type=season 的真失败也误试 series，语义含混，弃）；seasons_series_list 反查定型（多一次请求且该端点有 §3.1 不签名坑，弃）；桩名比对/`mid/total` 双零哨兵（拦不住撞号合集的真实 meta，弃）。

- **D5 B8 字符集：base58 加严**
  - **Decision**: `BV[0-9A-Za-z]{10}` → `BV[1-9A-HJ-NP-Za-km-z]{10}`，`recognizeInput` 全文扫描与 `shortLinkBvTarget` 短路两处同步。真实 BV 号由 base58 混淆表生成、不含 0/O/I/l，无误拦。存在性校验维持网络路径（view 失败提示已有）。
  - **Alternatives considered**: PiliPlus 式 `bv1[0-9a-zA-Z]{9}` 仅锚定第 3 位为 1（约束的是当前格式巧合而非字符集本质，且更宽松，弃）。

- **D6 statusMsg 收敛：三令牌改动**
  - **Decision**: fontSize `TOKEN_FONT_BODY`(13)→`TOKEN_FONT_BODY_S`(12)；margin `{top: TOKEN_SPACE_L, bottom: TOKEN_SPACE_XL}`→`{top: TOKEN_SPACE_S, bottom: TOKEN_SPACE_S}`；补 `.width('100%')` 配合既有 `textAlign(Center)` 实现整行居中。显示条件、文案、颜色一律不动。
  - **Alternatives considered**: 收敛为区块左对齐（既有 textAlign(Center) 语义是居中，仅补宽度令其真正生效，弃改动方向）。

- **D7 登记对账口径**
  - **Decision**: feature.json 指向本目录；PROJECT_NOTES KI-7 压缩为全销项状态（保留 B8 口径：形态校验已加严、存在性校验维持网络路径）、第三章删除「订阅源导出导入」（part3 已交付）；BILI_NOTES §3 追加 3.9（EP 形态登记与拒收决策）、3.10（lists 无 type 歧义与回退链、含未实测假设）、3.11（BV base58 字符集事实与 PiliPlus 旁证）。architecture.md/bugfix.md 不动（无结构变化、全走 SDD）。

## Technical Details

- **Constants.ets**: `KEY_UNFAVORITE_ASK = 'unfavoriteAsk'`，置于 KEY_HISTORY_SYNC 之后（Preferences 持久化键区）
- **LinkResolver.ets**: 文件头 ④ 与 RecognizeResult 注释的 type 枚举补 `'lists' | 'ep'`；EP URL 规则置 av URL 后、lists 规则前；纯文本 ep/ss 规则置 space 规则后、BV 全文扫描前；BV 两处正则同步替换
- **AddSubscriptionSheet.ets**: dispatchRecognized 加 `case 'ep'`（toast）与 `case 'lists'`（转 subscribeListsById）；subscribeListsById 置 subscribeSeriesById 之后
- **PlayerController.ets**: `removeSelectedFromPlaylist` 内 `askEnabled` 常量 + 条件追加；注释同步补「确认开关关 → 纯移除」
- **SettingsPage.ets**: `@Local unfavoriteAskOn` 声明置 historySyncOn 后；aboutToAppear 初始化；新 SettingsRow 置历史同步与退出登录之间；statusMsg 行三处样式替换

**Structure Decision**: 全部沿用既有分层（service→model、pages→service/model 单向依赖），不引入新目录/新文件。

**Performance Goals**: 回退链最坏两次串行 meta 请求（对齐既有订阅路径量级）；其余改动零运行时开销。

## Risks & Mitigations

| 风险 | 等级 | 缓解 |
|---|---|---|
| 合集/系列 id 跨 UP 撞号 → 误订撞号资源 | 中 | 真机实测命中（系列 302414 撞别 UP 合集）；URL mid 锚点消歧已排除跨 UP 撞号；同 UP 撞号不可消歧、概率极低，按合集命中（ponytail 标注） |
| BV 加严误拦未来新格式 | 低 | base58 表为生成算法本质约束；PiliPlus 宽松式差异已登记 BILI_NOTES 3.11 |
| V1/V2 状态代际混用 | 低 | 开关持久化完全复刻「历史同步」行先例（@Local + AppStore.getNumber/putNumber） |
| 回退链掩盖真实网络错误 | 低 | 双失败提示「合集/系列信息获取失败」已覆盖；错误详情在日志页可查 |
