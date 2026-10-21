# 充电视频功能档案

**状态**：功能处待定态——源码注释保留，功能性验证待应用侧 WBI 放行（见 §5 状态登记）。

充电相关内容已从 `BILI_NOTES.md`、`PROJECT_NOTES.md`、源码与 spec 各轮工件中移出，统一收档本文件：§1-§7 迁自原 `spec/v0.5-part3-registry/charging-archive.md`（问题定义、证据链、恢复路线图、代码附录），§8 为历轮 spec 工件移出内容原文（part2/part3/part4 的 US/FR/SC/D/T，原位留 ID 存根指向本档）。当前源码中充电判定管线与角标渲染以注释态保留，恢复=取消注释三处，注释代码与 §7 附录互为校验。

---

## 1. 问题定义

- UP 订阅列表缺**充电专属稿件**（首个样本：小约翰可汗 mid=23947287，真序列第 3 位），网页投稿页有且带「充电专属」标记，App 无。**探针修正**：不是「54 与伊朗篇终之间夹一条」——伊朗篇终本身（BV12RYx6TE9r「告别伊玛目 伊朗篇（终）」）就是充电稿。
- 期望：列表补入充电条目并显示「充电」角标（`BiliVideo.isUpowerExclusive`），角标仅提示不拦截点击。

## 2. 证据链（按时间）

### 2.1 前证：biliRelay 实验 21（2026-09-22）

原文：`../bili/biliRelay/docs/B站API试错记录.md` 实验 21（已从 `BILI_NOTES.md` §2 迁出，原文以 biliRelay 仓库为准）。要点：

- 登录态打各源列表接口看字段取值分布：`up`（space vlist）`is_charging_arc`/`elec_arc_type`/`elec_arc_badge`/`is_pay`——5 UP × 30 条 = 150 条全 False/0（证明是逐条目标记非「UP 开了充电计划」）；`watchlater` 自带完整 `rights` dict 全 0；`season`/`series` 有 `ugc_pay`/`state`；`fav` 无 `rights` 判不出；`bv` 详情 `view.data.is_upower_exclusive`（普通视频 False）。
- 当时结论：拿不到正向样本，判据按「名字 + 分布」反推，只认明确 True/非 0。
- **后轮修正**（见 2.3）：「充电视频不公开出现在投稿列表」结论只对 plain 端点与 APP cursor 链成立，WBI 端点实含充电条目。

### 2.2 本项目四类链实测（2026-10 轮，v0.5-part2 US4/T014）

（原文自 `BILI_NOTES.md` §3.1 迁入；工件：`spec/v0.5-part2-source-page-polish/`）

目的：订阅剧集列表接口能否逐条携带「充电专属」标记。实测覆盖四类订阅链路，请求间隔 ≥3s。

| 链路 | 端点 | 实测条目 | 充电/付费候选字段 | 实测值 |
| --- | --- | --- | --- | --- |
| UP APP 签名链 | `app.bilibili.com/x/v2/space/archive/cursor`（TV appkey 签名 + BiliDroid UA） | 老番茄(mid=546195) 20 条 + 真实订阅 UP(mid=3690981392124599) 全量 259 条 | `ugc_pay`(int) / `is_ugcpay`(bool) / `is_pugv`(bool)；**无** upower/rights/elec 字段 | 全部 0/false |
| UP Web 链 | `x/space/wbi/arc/search`（WBI 签名 + buvid cookie + space Referer/Origin） | 老番茄 5 条 | `is_charging_arc`(bool) / `elec_arc_type`(int) / `elec_arc_badge`(str) / `is_pay`(int) | 全部 false/0/空 |
| 收藏夹 | `x/v3/fav/resource/list`（公开收藏夹匿名可测） | 绵羊料理公开夹 10 条 | **无任何** rights/upower/elec/ugc_pay 字段，仅 `attr`(int) | attr 全 0 |
| 合集 | `x/polymer/web-space/seasons_archives_list`（匿名） | 老番茄合集 1903592 全 23 条 | `ugc_pay`(int) / `state`(int) | 全部 0 |
| 系列 | `x/series/archives`（匿名） | mid=11684621 系列 1873879 前 10 条 | `ugc_pay`(int) / `state`(int) | 全部 0 |

**正向样本第三证**（小约翰可汗，PowerShell 复刻 APP 签名链探针）：`data.count=265` 与投稿总数一致（含充电专属稿），但 `data.item` 前 6 条无任何充电条目、`is_ugcpay`/`ugc_pay` 全 false/0——**APP cursor 链 count 计入、列表不下发**。计数口径以 `data.count` 为准（页头「N 集」总数含充电视频，为既定行为，bugfix.md #2 totalCount 修复口径）。

**判定采纳**（与 biliRelay 生产判据同源）：只认明确 True/非 0——UP 双链（`parseVlistRecords`）：`is_charging_arc===true || elec_arc_type>0 || ugc_pay>0 || is_ugcpay===true`；合集/系列（`parseArchiveRecords`）：`ugc_pay>0`；收藏夹无字段不判。FR-009：禁止列表逐条拉 `view` 详情补偿（必吃风控）。

### 2.3 plain 与 WBI 端点数据差异（2026-10-16）

（原文自 `BILI_NOTES.md` §3.3 迁入）

- **PiliPlus 佐证**（`../bili/PiliPlus`，Flutter 生产客户端）：用户投稿页唯一端点即 `x/space/wbi/arc/search`（`lib/http/api.dart` `searchArchive`），vlist 模型（`lib/models_new/member/search_archive/vlist.dart`）生产解析 `is_charging_arc === true` → 渲染「充电专属」角标——**WBI 端点 vlist 包含充电条目**，网页标记同源。附带：`searchArchive` 支持 `special_type: 'charging'` 参数（`lib/http/member.dart` L349-375：`specialType` 形参 → query `'special_type': ?specialType`；网页空间页「充电专属」筛选即它），可单发一请求只拉某 UP 的充电视频列表（探针实测可行，见 §2.4）。
- **plain 端点漏发实测**（本项目，模拟器登录态）：`x/space/arc/search`（非 WBI）登录态第 1 轮即成功（HTTP 200 + code=0），但 vlist **不含**充电条目（补稠合并零新增可证）——plain 数据被过滤，非风控问题。
- **WBI 端点风控现状**：模拟器 3 轮刷新全部 `-403`（带登录 cookie 仍拦）；网页端可过的差异在浏览器级指纹评分，非登录态。请求形状已与 PiliPlus 逐项对齐（PC UA、space Referer/Origin、WBI 签名、dm_img 四件套、`platform=web`、`web_location=333.1387`、`order_avoided`），代码层面无差距可补。
- 结论：充电视频实体与标记**只在 WBI 端点 vlist 下发**；出现与否取决于该端点风控放行，无客户端侧补偿手段。

### 2.4 探针新证与字段分布修正（WBI 放行轮）

（探针报告：`../wbi-charging-probe-report.md`，仓库外，浏览器侧）

- **样本规模**：WBI vlist 首页 40 条含 16 条充电专属（`is_charging_arc === true`）。
- **字段分布修正**：WBI vlist 充电条目**无** `ugc_pay`/`is_ugcpay` 字段（缺失非 0）——存档四字段判据仍安全（undefined 不计入），实际起作用的是 `is_charging_arc`(true) + `elec_arc_type`(1)；服务端另下发 `elec_arc_badge: "充电专属"`（本项目角标文案按存档设计用「充电」，不取该字段全文）。
- **旁路实测确认**：`special_type=charging` 可行——16/16 全 true、`page.count=16`，单页拉全（§2.3 PiliPlus 佐证落地）。

## 3. 已实施且保留的改动（不随本问题搁置回退）

- **`fetchUpVideosViaWeb` 端点顺序交换为 WBI 优先、plain 降级兜底**（`BiliService.ets`，登记 `spec/v0.5-part2-source-page-polish/bugfix.md` #4）：WBI 是网页/PiliPlus 同源的完整数据端点；被风控时 plain 兜底保数据可得性。恢复识别后此顺序即为取数前提，无需再动。

## 4. 已移除清单（恢复时按 §5 路线图还原）

**代码**（原以 `[DISABLED 2026-10]` 注释保留，后连注释一并删除）：

- `BiliService.ets` `parseArchiveRecords`：`ugc_pay` 判定块
- `BiliService.ets` `parseVlistRecords`：四字段判定块（`is_charging_arc`/`elec_arc_type`/`ugc_pay`/`is_ugcpay`）
- `BiliVideo.ets`：`@Trace isUpowerExclusive` 字段、`toRecord`/`fromRecord` 对应键
- `SourcePage.ets`：「充电」角标块、NEW/已播标记 margin 中的 `isUpowerExclusive` 让位逻辑
- 色彩资源 `gold_accent`（`resources/base|dark/element/color.json`，仅充电角标使用）

**文档**：

- `BILI_NOTES.md`：§1.1 端点表充电短语、§1 充电标记要点、§2 实验 21 迁移原文、§3.1/§3.3（即本存档 2.2/2.3 前身）
- `PROJECT_NOTES.md` DIS-3（内容已被本存档取代）
- `spec/v0.5-part2-source-page-polish/bugfix.md`：#2 充电局限条删除；#4 充电表述重写为端点顺序中性描述（WBI-first 交换记录保留）；#1 `BILI_NOTES.md` §3.2 引用随重编号改 §3.1

**spec 工件移出手术**：part2/part3/part4 九工件中的充电条目（US/FR/SC/D/T）移出至本档 §8，原位留 ID 存根；原 `spec/v0.5-part3-registry/charging-archive.md`（本档 §1-§7 前身）删除。

**未动**：`spec/v0.5-part2-source-page-polish/` 其余工件（US4/T014/T015 等活跃 spec 工件保留原样）。

## 5. 恢复路线图（重启时执行）

1. **前提观察**：WBI 端点（`x/space/wbi/arc/search`）风控是否放行——任一登录设备打一发看是否仍 `-403`；放行则继续，未放行继续搁置。
2. **代码还原**（按 §7 附录逐字存档还原——**唯一来源**，充电代码从未入 git）：模型字段（§7.1）→ 判定管线（§7.2/§7.3，判据见 §2.2）→ 角标渲染与 margin（§7.4）→ 色彩资源（§7.5）。
3. **验证**：小约翰可汗刷新后列表补入真序列第 3 位充电稿、「充电」角标显示；非充电视频无角标。
4. **可选优化**（当时评估）：`special_type: 'charging'` 单发取充电列表（§2.3），省去依赖整页 vlist 放行——探针已实测可行（§2.4），本轮未采用，按存档判据走整页 vlist。
5. **收尾**：删除本存档或在其中登记终态。

**状态登记**：功能处**待定态**（用户决策——WBI 出口级风控未放行，应用侧无充电数据，功能无法测试验证；网络级实证见 `BILI_NOTES.md` §3.4。风控解决前维持注释态，不作下线定论）。判定管线两处（`BiliService.ets` 合集 ugc_pay 块、vlist 四字段块）与「充电」角标渲染块（`SourcePage.ets`）已注释保留，恢复=取消注释三处；模型字段与序列化（`BiliVideo.ets`）、`gold_accent` 色彩资源保留未动。历史脉络：代码按 §7 附录还原后，应用侧 WBI 恒 `-403`（真机历轮验证）、plain 真机 `-799`（模拟器登录态曾 200），UP Web 双链真机全断、APP 签名链供数；判据与实测详见本存档 §2.2-§2.4。恢复时按 §5 路线图执行（前提观察：WBI 放行），注释代码与 §7 附录互为校验。

## 6. 参考

- 历轮 spec 工件充电条目原文：本档 §8（part2 US4/FR-009/SC-004、part3 US8/FR-018/FR-019/SC-005、part4 US4/FR-008/SC-005 等，原位存根指向此）
- bugfix 记录：`spec/v0.5-part2-source-page-polish/bugfix.md` #2/#4
- PiliPlus：`../bili/PiliPlus`（`lib/http/member.dart` searchArchive、`lib/http/api.dart` searchArchive 端点、`lib/models_new/member/search_archive/vlist.dart` 角标判定）
- biliRelay：`../bili/biliRelay/docs/B站API试错记录.md`（实验 21 原文、状态码速查、排查手册）

## 7. 附录：移除代码存档（逐字，恢复时直接还原）

### 7.1 `BiliVideo.ets`

```ts
  @Trace isUpowerExclusive: boolean = false;
```

`toRecord()` 内 `'videoTitle'` 键后：

```ts
      'isUpowerExclusive': this.isUpowerExclusive,
```

`fromRecord()` 内 `videoTitle` 块后：

```ts
    if (rec['isUpowerExclusive'] !== undefined) {
      v.isUpowerExclusive = rec['isUpowerExclusive'] as boolean;
    }
```

### 7.2 `BiliService.ets` `parseArchiveRecords`（`items.push(item)` 前）

```ts
      // 充电/付费标记（US4）：合集/系列 archives 仅 ugc_pay 可判，只认明确非 0
      const ugcPayRaw: Object = rec['ugc_pay'];
      item.isUpowerExclusive = ugcPayRaw !== undefined && ugcPayRaw !== null && Number(ugcPayRaw) > 0;
```

### 7.3 `BiliService.ets` `parseVlistRecords`（`items.push(item)` 前）

```ts
      // 充电/付费标记（US4）：只认明确 True/非 0——
      // Web 链 is_charging_arc/elec_arc_type，APP 链 ugc_pay/is_ugcpay，两种 vlist 形态共用此解析
      const chargingArcRaw: Object = rec['is_charging_arc'];
      const elecTypeRaw: Object = rec['elec_arc_type'];
      const ugcPayRaw: Object = rec['ugc_pay'];
      const ugcPayFlagRaw: Object = rec['is_ugcpay'];
      item.isUpowerExclusive =
        (chargingArcRaw !== undefined && chargingArcRaw !== null && Boolean(chargingArcRaw)) ||
        (elecTypeRaw !== undefined && elecTypeRaw !== null && Number(elecTypeRaw) > 0) ||
        (ugcPayRaw !== undefined && ugcPayRaw !== null && Number(ugcPayRaw) > 0) ||
        (ugcPayFlagRaw !== undefined && ugcPayFlagRaw !== null && Boolean(ugcPayFlagRaw));
```

### 7.4 `SourcePage.ets` 剧集行（`Blank()` 与 NEW 徽标之间）

```ts
                      if (item.isUpowerExclusive) {
                        Text('充电')
                          .fontSize(Constants.TOKEN_FONT_AUX)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.gold_accent'))
                      }
```

NEW 徽标 `.fontColor(...)` 后：

```ts
                          .margin({ left: item.isUpowerExclusive ? Constants.TOKEN_SPACE_S : 0 })
```

已播标记 `.fontColor(...)` 后（现为 `this.isNew(item)` 单条件）：

```ts
                          .margin({ left: this.isNew(item) || item.isUpowerExclusive ? Constants.TOKEN_SPACE_S : 0 })
```

### 7.5 色彩资源 `gold_accent`

`resources/base/element/color.json`（`placeholder_color` 与 `danger_red` 之间）：

```json
    { "name": "gold_accent", "value": "#B8860B" },
```

`resources/dark/element/color.json`（同位置）：

```json
    { "name": "gold_accent", "value": "#C8A24A" },
```

## 8. 历轮 spec 工件移出内容

充电功能文字自 part2/part3/part4 九工件移出至本档，原位留 ID 存根（「已移出：见 spec/charging-archive.md」）保编号连续。以下为移出条目原文（按轮次与文件分组）。各轮文件中保留不动：Input 逐字引用与历史输入记录、US6/FR-012（BILI_API.md 文档故事）中的充电实测提及、纯 ID 引用（依赖图/任务统计）。

### 8.1 v0.5-part2-source-page-polish

#### spec.md

**Overview 充电子句**：

> 剧集行标明充电专属视频（数据来源以接口实测为准）

**User Story 4 - 充电视频标记 (Priority: P2)**（整节移出）：

> 剧集列表中充电专属视频显示「充电」角标，帮助用户提前避雷（充电视频无权限时取不到流）。数据来源以**接口实测为准**：实施时先用真实数据实测四类订阅的列表接口返回，若携带充电专属标记字段则解析并显示角标；实测不携带的类型不显示角标，不做逐条拉详情的补偿。**既有前证**（biliRelay 实验 21，2026-09-22）：UP 投稿列表 `is_charging_arc` 等字段实测全 False 且充电专属视频可能不公开出现在投稿列表；fav 列表无 rights 判不出；season/series 有 `ugc_pay`；详情接口 `is_upower_exclusive` 可靠——本项目 APP 签名链端点与 biliRelay 匿名 Web 链不同，仍须独立实测。实测结论沉淀至 `BILI_API.md`（US6）。
>
> **Why this priority**: 有价值的避雷信息，但受制于 B 站接口数据可得性，按实测结果落地。
>
> **Independent Test**: 实施时实测各类型接口返回是否含充电标记字段；对携带的类型用真实订阅核对角标显示。
>
> **Acceptance Scenarios**:
>
> 1. **Given** 实测确认某类订阅接口携带充电标记字段，**When** 列表含充电视频，**Then** 该行显示「充电」角标
> 2. **Given** 实测确认接口不携带标记，**When** 列表渲染，**Then** 该类型不显示角标（不引入额外请求），结论记录在 `BILI_API.md`
> 3. **Given** 非充电视频，**When** 列表渲染，**Then** 不显示「充电」角标

**Edge Cases 条目**：

> - **充电视频播放失败**：点开充电视频仍走原播放链路，失败反馈沿用现状，角标仅作提示不拦截点击

**FR-009**：

> - **FR-009**: 剧集行 MUST 按接口实测结果标明充电专属视频（「充电」角标）；接口不携带标记的类型 MUST NOT 引入额外网络请求补偿

**Key Entities 条目**：

> - **充电专属标记（BiliVideo 扩展字段）**：布尔值，来自列表接口解析（实测确定字段名后落地），随剧集数据流转与持久化

**SC-004**：

> - **SC-004**: 充电标记数据来源经实测留档（结论写入 `BILI_API.md`），无猜测性实现

**Assumptions 条目**：

> - 充电角标样式与 NEW/已播标记同档（小号角标文字），不新增图标资源

**Open Questions 充电子句**：

> 充电视频=接口实测后决定

#### plan.md

**Summary 充电子句**：

> 充电专属标记（`BiliVideo` 增字段，实施时实测四类接口定夺）

**Project Structure 条目**：

> ├── model/BiliVideo.ets         # +isUpowerExclusive 字段（@Trace + record 序列化）
> ├── service/BiliService.ets     # 三个列表解析点探测充电标记字段

（另：SourcePage.ets 行内「角标渲染」注记随移出。）

**D6 充电专属标记（实测定夺，含 biliRelay 前证）**（整条移出）：

> - **Decision**: `BiliVideo` 新增 `isUpowerExclusive: boolean`（`@Trace`，默认 false），`toRecord/fromRecord` 同步增字段。三个列表解析点（`parseArchiveRecords`/`parseVlistRecords`/`parseFolderMedias`）各自探测原始条目充电标记字段。**实施第一步先实测**：用真实订阅数据打本项目四类链路接口（含 APP 签名链——与 biliRelay 匿名 Web 链端点不同），确认返回是否携带标记字段；携带的链解析生效、列表行显示「充电」角标（样式与 NEW 徽标同档）；不携带的链不标不补偿；全部不携带则移除解析代码与字段，该需求降级为「接口不支持，不实施」。实测结论（各链带/不带+字段名）写入 `BILI_API.md`（D11）。
> - **既有前证**（biliRelay `docs/B站API试错记录.md` 实验 21，迁移后入 `BILI_API.md`）：UP 投稿列表 `is_charging_arc`/`elec_arc_type`/`elec_arc_badge`/`is_pay` 实测 150 条全 False 且充电专属视频可能不公开出现在投稿列表；fav 列表无 rights 判不出；season/series 有 `ugc_pay`/`state`；详情接口 `is_upower_exclusive` 可靠——前证降低「列表可标」的预期，但本项目 APP 签名链端点未实测过，仍须独立验证。
> - **Rationale**: 官方客户端列表带充电角标 vs biliRelay 实测列表字段全 False 存在矛盾，唯一裁断方式=对本项目实际链路实测（SC-004）。
> - **Alternatives considered**: 直接按 biliRelay 前证判定不做（放弃——端点链路不同，未实测不算数）；批量拉详情补偿（用户已否决）。

**Data Model 条目**：

> **BiliVideo（既有 @ObservedV2 类，增量）**
> - `isUpowerExclusive: boolean = false`（`@Trace`）：充电专属标记；来源=列表接口解析（D6 实测定夺），持久化进订阅剧集缓存（`toRecord`/`fromRecord` 增 `'isUpowerExclusive'` 键，`fromRecord` 缺省 false 兼容旧缓存）

#### tasks.md

**T005**：

> - [X] T005 `BiliVideo` 新增 `isUpowerExclusive: boolean = false` 字段（`@Trace`），`toRecord`/`fromRecord` 同步增 `'isUpowerExclusive'` 键（`fromRecord` 缺省 false 兼容旧缓存），落在 `entry/src/main/ets/model/BiliVideo.ets`

**Phase 6: User Story 4 - 充电视频标记（实测定夺） (Priority: P2)**（整段移出）：

> **Goal**: 实测四类链路接口 → 带标记字段则解析+角标，不带则降级不实施
> **Independent Test**: 实测结论留档 `BILI_API.md` §3；携带链路列表显示「充电」角标
>
> - [X] T014 [US4] 充电标记实测：用真实订阅数据（覆盖 UP APP 签名链/UP Web 链/收藏夹/合集/系列）请求列表接口，记录各链返回是否携带充电标记字段（候选：`rights.is_upower_exclusive`、`is_charging_arc`、`ugc_pay` 等）及字段名，结论写入 `BILI_API.md` §3（首条记录）
> - [X] T015 [US4] 按实测结论分叉：携带标记的链在对应解析点（`parseArchiveRecords`/`parseVlistRecords`/`parseFolderMedias`，`entry/src/main/ets/service/BiliService.ets`）解析字段写入 `isUpowerExclusive`，`SourcePage` 剧集行渲染「充电」角标（样式与 NEW 徽标同档）；**若全部链实测不携带**：移除 T005 增量字段与解析代码，在 `BILI_API.md` §3 记录「列表接口不支持，需求降级不实施」
>
> **Checkpoint**: 带/不带角标与实测结论一一对应，无猜测性实现，结论留档

**T025 充电子句**：

> 充电角标（如实施）

**依赖与 Notes 条目**：

> - US4 实测（T014）可与页面线并行，T015 依赖 T005+T014
> - **US4（P2）**: 仅依赖 T005 字段与 T014 实测，可与页面线并行
> - T014 网络实测与页面线并行
> - US3 页头滚动 → US4 充电实测分叉 → US5 等高留白 → 逐项验证
> - T014 实测请求注意风控冷却（间隔 ≥3s，勿密集打点；对照 biliRelay 排查手册 §4）
> - T015 是条件分叉任务：实测结论决定「解析+角标」或「降级移除」，两分支互斥

### 8.2 v0.5-part3-registry

#### spec.md

**Overview 充电子句**：

> ②part3 登记集清账——播放出错提醒与日志、历史容量 300 与列表尾提示、充电视频（条件项，开工探针 WBI 风控放行才做，未放行搁置不阻塞轮次）。充电问题集调查证据链与代码存档见本目录 `charging-archive.md`（恢复唯一来源）。

**User Story 8 - 充电视频（条件项） (Priority: P3)**（整节移出）：

> 开工先探测 WBI 投稿端点风控是否放行（此前恒 -403）。放行：订阅列表补入充电专属稿件并显示「充电」角标（仅提示不拦截点击），按 `charging-archive.md` 存档逐字还原代码并验证；未放行：本项继续搁置，不阻塞轮次其余功能。
>
> **Why this priority**: 外部风控条件决定可行性，自带开关，不影响轮次主体。
>
> **Independent Test**: 探针请求 WBI 端点；放行则验证小约翰可汗（mid=23947287）真序列第 3 位充电稿入列且带角标。
>
> **Acceptance Scenarios**:
>
> 1. **Given** 探针放行, **When** 刷新该 UP 订阅, **Then** 充电稿入列且显示「充电」角标
> 2. **Given** 探针仍 -403, **When** 本轮收尾, **Then** 其余功能全部交付不受影响，充电项登记搁置

**Edge Cases 条目**：

> - 充电探针只读，失败不产生任何残留改动

**FR-018 / FR-019**：

> - **FR-018**: 本轮开工 MUST 先探测 WBI 投稿端点风控；放行则补入充电专属稿件并显示「充电」角标（仅提示不拦截）；未放行本项搁置且 MUST NOT 阻塞轮次其余功能
> - **FR-019**: 充电角标判据 MUST 只认明确 True/非 0；MUST NOT 列表逐条拉视频详情补偿（风控红线）

**Key Entities 条目**：

> - **充电专属标记（BiliVideo 充电字段）**: 仅 WBI 端点下发，US8 条件项的数据基础（存档见 `charging-archive.md`）

**SC-005**：

> - **SC-005**: 充电探针放行时充电稿入列带角标；未放行时轮次其余功能全部交付

**Assumptions 条目**：

> - WBI-first 端点顺序已在前轮落地并保留，充电恢复前提成立

（保留不动：Input 中「充电视频条件项」为历史输入记录。）

#### plan.md

**Summary 充电子句**：

> + 登记清账线（US6 播放出错提醒与日志、US7 历史容量 300 与尾注、US8 充电视频探针门控组）……US8 为探针门控默认搁置组（放行才按 `charging-archive.md` 还原）

**Project Structure 条目**：

> ├── charging-archive.md   # 充电问题集存档（US8 恢复唯一来源）
> ├── model/BiliVideo.ets              # US8（条件）：isUpowerExclusive 还原
> entry/src/main/resources/base|dark/element/color.json  # US8（条件）：gold_accent

（另：BiliService.ets 行内「US8（条件）：充电判定还原」注记随移出。）

**Constraints 充电子句**：

> B 站风控红线（禁列表逐条拉详情补偿）

**D11 US8 充电 = 探针门控默认搁置组**（整条移出）：

> - **Decision**: US8 全组任务标记探针门控：探针（真机打开任一 UP 订阅详情刷新，观察 WBI 是否放行/有无 -403 降级日志）由用户执行；放行才按 charging-archive.md §7 逐字还原并验证，未执行/未放行整组跳过不阻塞轮次
> - **Rationale**: 探针需登录态真机环境，构建验证无法覆盖；风控未放行时代码还原无意义
> - **Alternatives considered**: 无条件还原（-403 下角标永不出现）；删除登记（用户要求保留条件项）

**Data Model 条目**：

> - **BiliVideo.isUpowerExclusive（条件，US8）**: @Trace 字段 + toRecord/fromRecord 键（charging-archive.md §7.1 逐字还原）。

#### tasks.md

**Phase 8: US8 - 充电视频 (Priority: P3，探针门控组)**（整段移出）：

> **Goal**: WBI 放行则充电稿入列带角标；未放行整组跳过不阻塞
> **Independent Test**: 探针放行时验证小约翰可汗真序列第 3 位充电稿带角标
>
> - [X] T016 [US8] 探针门控判定：仅当实施前用户明确提供「WBI 已放行」探针结果才执行 T017-T018（探针方法与恢复路线见 spec/v0.5-part3-registry/charging-archive.md §5）
>   - 判定：首轮无探针结果 → T017/T018 跳过；后续探针报告（浏览器侧 WBI 数据面放行，应用侧未验证，见 charging-archive.md §2.4）经用户决策「直接启动还原」→ T017/T018 已执行勾选（还原失效安全：WBI 未放行时 plain 兜底无充电条目，无行为回归）
> - [X] T017 [US8] 模型与解析还原（BiliVideo isUpowerExclusive 字段与 toRecord/fromRecord 键、BiliService 双判定块，逐字还原 charging-archive.md §7.1-§7.3）— entry/src/main/ets/model/BiliVideo.ets、entry/src/main/ets/service/BiliService.ets
> - [X] T018 [US8] 角标渲染与色彩还原（SourcePage「充电」角标块与 margin 让位 §7.4、gold_accent 资源 §7.5）— entry/src/main/ets/pages/SourcePage.ets、entry/src/main/resources/base/element/color.json、entry/src/main/resources/dark/element/color.json

**其余移出条目**（依赖表/并行表/Notes）：

> | US8 门控组 | T016→T017→T018 | 存档还原 | 默认跳过；放行才执行 |
> - **US8（Phase 8）**: 探针门控默认跳过，放行才执行还原组
> - **US8**: 探针门控，独立于全部故事
> - US8 探针门控组默认跳过，不阻塞任何故事
> - US8 组任务未获探针结果时保持未勾选并在实施报告登记跳过原因

（另：依赖图 mermaid 中 T016→T017→T018 两条边随移出；Input 文档清单中 charging-archive.md 引用改指本档。）

### 8.3 v0.5-part4-risk-control

#### spec.md

**Overview 充电子句**：

> 应用侧 Web 补稠链（WBI+plain）被 B 站风控拦截，US8 充电角标处休眠态

**User Story 4 - 过墙实验（单方案） (Priority: P2)**（整节移出——充电激活实验，实验技术结论见 `BILI_API.md` §3.3）：

> WBI 请求传输栈由 `@ohos.net.http` 换 rcp（`@kit.RemoteCommunicationKit`），前置检查两者 TLS 栈异同，真机实测是否放行。成功：充电角标验收闭环（回写 part3 存档终态）；失败：登记实验结果、保留止血成果、本轮收尾。
>
> **Why this priority**: 充电角标功能已交付休眠，过墙即激活；单方案实验（用户决策）控制范围与周期，失败不无限尝试（同目标最多 3 次验证）。
>
> **Independent Test**: 换栈后真机打开含充电稿的 UP 订阅刷新，看充电稿入列带角标。
>
> **Acceptance Scenarios**:
>
> 1. **Given** rcp 与现传输栈 TLS 异构，**When** 换栈真机刷新，**Then** WBI 放行→充电稿带「充电」角标，回写 `spec/v0.5-part3-registry/charging-archive.md` 终态
> 2. **Given** 前置检查发现 rcp 与现栈同栈（无传输层差异可试），**When** 登记，**Then** 按失败分支收尾，不实施换栈
> 3. **Given** 换栈后仍被拦，**When** 实验验证，**Then** 结果补录 `BILI_API.md` §3，止血成果保留，行为无回归

**FR-008**：

> - **FR-008**: 过墙成功 MUST 真机验收充电角标并回写 part3 `charging-archive.md` 终态；失败 MUST 补录 `BILI_API.md` §3 后收尾；MUST NOT 无限重试（同目标最多 3 次验证）

**SC-005**：

> - **SC-005**: 过墙实验有明确终态：成功=充电角标真机可见+存档回写；失败=实验结果在档+无行为回归

#### plan.md

**Summary 充电子句**：

> 终态判定 build-only（hilog WBI 轮结果）+ 用户目检充电角标，回写 part3 存档

**验证契约充电子句**：

> 过墙成功后用户目检充电角标，回写 `spec/v0.5-part3-registry/charging-archive.md` 终态

#### tasks.md

**Phase 6 Goal 充电子句**：

> 成功闭环充电角标（回写 part3 存档），失败登记收尾

**T012 充电子句**：

> 成功→回写 spec/v0.5-part3-registry/charging-archive.md 终态并在报告提示用户目检充电角标
