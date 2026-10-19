# 充电视频问题集存档（v0.5-part3 恢复唯一来源）

**状态**：代码已按 §7 附录还原（构建通过）；功能性验证待应用侧 WBI 放行，存档暂不删除（见 §5 终态登记）。

充电相关内容已从 `BILI_API.md`、`PROJECT_NOTES.md`、源码中移除；充电代码的加入与移除全程未提交 git，本存档（§7 代码附录）是恢复时的唯一代码来源。`BILI_API.md` 充电 API 结论待实施时后补。

---

## 1. 问题定义

- UP 订阅列表缺**充电专属稿件**（首个样本：小约翰可汗 mid=23947287，真序列第 3 位），网页投稿页有且带「充电专属」标记，App 无。**探针修正**：不是「54 与伊朗篇终之间夹一条」——伊朗篇终本身（BV12RYx6TE9r「告别伊玛目 伊朗篇（终）」）就是充电稿。
- 期望：列表补入充电条目并显示「充电」角标（`BiliVideo.isUpowerExclusive`），角标仅提示不拦截点击。

## 2. 证据链（按时间）

### 2.1 前证：biliRelay 实验 21（2026-09-22）

原文：`../bili/biliRelay/docs/B站API试错记录.md` 实验 21（已从 `BILI_API.md` §2 迁出，原文以 biliRelay 仓库为准）。要点：

- 登录态打各源列表接口看字段取值分布：`up`（space vlist）`is_charging_arc`/`elec_arc_type`/`elec_arc_badge`/`is_pay`——5 UP × 30 条 = 150 条全 False/0（证明是逐条目标记非「UP 开了充电计划」）；`watchlater` 自带完整 `rights` dict 全 0；`season`/`series` 有 `ugc_pay`/`state`；`fav` 无 `rights` 判不出；`bv` 详情 `view.data.is_upower_exclusive`（普通视频 False）。
- 当时结论：拿不到正向样本，判据按「名字 + 分布」反推，只认明确 True/非 0。
- **后轮修正**（见 2.3）：「充电视频不公开出现在投稿列表」结论只对 plain 端点与 APP cursor 链成立，WBI 端点实含充电条目。

### 2.2 本项目四类链实测（2026-10 轮，v0.5-part2 US4/T014）

（原文自 `BILI_API.md` §3.1 迁入；工件：`spec/v0.5-part2-source-page-polish/`）

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

（原文自 `BILI_API.md` §3.3 迁入）

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

- `BILI_API.md`：§1.1 端点表充电短语、§1 充电标记要点、§2 实验 21 迁移原文、§3.1/§3.3（即本存档 2.2/2.3 前身）
- `PROJECT_NOTES.md` DIS-3（内容已被本存档取代）
- `spec/v0.5-part2-source-page-polish/bugfix.md`：#2 充电局限条删除；#4 充电表述重写为端点顺序中性描述（WBI-first 交换记录保留）；#1 `BILI_API.md` §3.2 引用随重编号改 §3.1

**未动**：`spec/v0.5-part2-source-page-polish/` 其余工件（US4/T014/T015 等活跃 spec 工件保留原样）。

## 5. 恢复路线图（重启时执行）

1. **前提观察**：WBI 端点（`x/space/wbi/arc/search`）风控是否放行——任一登录设备打一发看是否仍 `-403`；放行则继续，未放行继续搁置。
2. **代码还原**（按 §7 附录逐字存档还原——**唯一来源**，充电代码从未入 git）：模型字段（§7.1）→ 判定管线（§7.2/§7.3，判据见 §2.2）→ 角标渲染与 margin（§7.4）→ 色彩资源（§7.5）。
3. **验证**：小约翰可汗刷新后列表补入真序列第 3 位充电稿、「充电」角标显示；非充电视频无角标。
4. **可选优化**（当时评估）：`special_type: 'charging'` 单发取充电列表（§2.3），省去依赖整页 vlist 放行——探针已实测可行（§2.4），本轮未采用，按存档判据走整页 vlist。
5. **收尾**：删除本存档或在其中登记终态。

**终态登记**：步骤 2 代码还原已完成——模型字段/判定管线/角标渲染/色彩资源按 §7 附录还原，arkts_check 预检与构建均通过；步骤 3 功能性验证悬置——探针仅覆盖浏览器侧，应用侧 WBI 放行未验证，待放行后按步骤 3 验收；验收未闭环前存档不删除。应用侧真机探针（还原后验证轮）：WBI 3 轮仍 `-403` 未放行，plain 端点真机 `-799`（较模拟器轮「第 1 轮即 200」为新变化，UP Web 双链真机全断、APP 签名链供数）——详见 `BILI_API.md` §3.3；充电角标维持失效安全未显示，验收继续悬置。

## 6. 参考

- 活跃 spec 工件：`spec/v0.5-part2-source-page-polish/`（US4/FR-009/SC-004、bugfix.md #2/#4）
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
