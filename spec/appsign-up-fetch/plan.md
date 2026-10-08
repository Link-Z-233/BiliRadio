# Implementation Plan: appsign-up-fetch

**Input**: Feature specification from `spec/appsign-up-fetch/spec.md`

## Summary

给 UP 投稿 APP 端点（`app.bilibili.com/x/v2/space/archive/cursor`）接入 AppSign 游客签名（TV appkey，无 access_key），替换现状"裸调恒 -400 的预检"；APP 链按该端点原生 cursor 语义翻旧页（首页 aid/next 缺省 → 翻旧传末条 aid + 上页 `data.next`）；任何失败自动降级现有 Web 三轮 buvid 退避链（Web 链零修改）。cursor 续传状态收敛在 BiliService 模块级 per-mid 缓存，`fetchUpVideos` 公开签名不变，SubscriptionStore 零改动。

## Technical Context

**Language/Version**: ArkTS（ArkUI 状态管理 V1，既有项目增量改造，保留 V1）  
**Primary Dependencies**: `@kit.CryptoArchitectureKit`（cryptoFramework MD5，与 WbiSigner 同模式）、`@ohos.net.http`（既有 httpGet）  
**State Management**: 既有全局 V1 `@Component` + `@State`；cursor 缓存为 service 层模块级内存态（非 UI 状态，不进 AppStorage）  
**Storage**: 无新增持久化——签名实时生成，cursor 会话内存态，退出即失  
**Testing**: 无测试套件（项目现状）；验证 = `arkts_check` + `devecocli build` + 真机实机验证（SC-001~005）  
**Target Platform**: HarmonyOS NEXT，compatibleSdkVersion 6.1.1(24) / targetSdkVersion 26  
**Constraints**: 游客身份（不携带 access_key）；签名按请求实时生成不缓存；Web 退避链行为与现状完全一致；endArmed/canLoadOlder/loadingOlder 触发机制不动  
**Scale/Scope**: 1 个新文件、3 个修改文件、1 个内部类

## Project Structure

### Documentation (this feature)

```text
spec/appsign-up-fetch/
├── spec.md              # 需求规格
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── AppSigner.ets        # [新增] AppSign 签名工具（镜像 WbiSigner 范式）
│   ├── BiliService.ets      # [修改] UP 取链重构：签名头页 / cursor 翻页 / 纯 Web 翻页链 / cursor 缓存
│   ├── Constants.ets        # [修改] 新增 TV_APP_KEY / TV_APP_SEC
│   └── SubscriptionStore.ets  # 不动（fetchUpVideos 签名不变）
└── pages/
    └── SourcePage.ets       # [修改] loadOlder UP 分支 app 优先 + 页记账统一（olderPage 两链通用）
```

**Structure Decision**: 遵循现有单模块架构（service/model/pages 分层，全局 V1 状态），不引入新目录或 MVVM 迁移。新增仅 `AppSigner.ets` 一个文件——签名工具独立成文件对齐既有 `WbiSigner.ets` 范式（一个签名器一个文件，常量归 Constants）；cursor 缓存与 UpAppCursor 类型收敛在 BiliService 文件内（内部实现细节，不导出、不建 model 文件）。

## Complexity Tracking

无宪法违例需要豁免。

## Research & Decisions

### D1: 游客签名，不做登录流（Phase 1 已拍板）

- **Decision**: 仅补 appkey+ts+sign 签名，不带 access_key；TV QR 登录流不在本轮范围
- **Rationale**: -400 根因是缺签名而非缺登录；投稿为公开内容，游客大概率可用；TV appkey 本就以"设备常不登录"为设计场景。验证失败有 Web 降级链兜底，损失仅一轮验证
- **Alternatives considered**: TV QR 登录流（改造量翻数倍，为未证实风险预付成本，否决）

### D2: cursor 参数形态对齐 PiliPlus `spaceArchive`（`lib/http/member.dart:119-167` + `lib/pages/member_video/controller.dart`）

- **Decision**: 首页 `aid`/`next` 缺省；翻旧页传 `aid=当前列表末条 aid` + `next=上一页响应的 data.next`；video 链**不带 pn**（PiliPlus `pn: type == .charging ? page : null`，video 恒 null）；`ps=30`
- **Rationale**: 这是唯一被大规模验证过的调用形态。ps 取 30（非 PiliPlus 的 20）：与 Web 链页大小一致，跨链页记账才能对齐（见 D4），且 UP 初始准入门槛（缓存≥30）不用改
- **Alternatives considered**: ps=20（照抄 PiliPlus）——需同步改准入门槛与页记账，且 D4 的 Web 降级续页号立即错位，否决；aid-only 不带 next（服务端是否接受未经验证，不冒险）

### D3: cursor 状态归属 BiliService 模块级 per-mid 缓存

- **Decision**: BiliService 内部维护 `Map<number, UpAppCursor>`（会话内存态，不导出）。失效规则：app 头页成功→写入；Web 头页成功→删除（本会话该源翻页走 Web）；app 翻页成功→更新；`has_next=false` 或 app 翻页失败→删除（粘性降级，下次刷新重建）
- **Rationale**: cursor 是 APP 链的服务端续传状态，与链同生命周期，天然归链的属主持有。冷启动 `HomePage.silentRefresh → refreshAll → fetchUpVideos` 产生的 cursor 只有留在 service 层才能被之后进入的 SourcePage 用上——若经返回值透传，silentRefresh 路径的 cursor 会丢，"进页直接触底"场景享受不到 app 链
- **Alternatives considered**: UpFetchResult 结果对象经 `fetchUpVideos → refreshSubscription → SourcePage` 全链透传——改 4 层签名、5 个调用点，且解不了 silentRefresh 丢弃问题，否决

### D4: 页记账统一，Web 降级按页号无缝续接

- **Decision**: `SourcePage.olderPage` 对 app/web 两种链的每次成功翻页都 +1；app 翻页失败降级时，Web 链请求 `olderPage+1` 页号。`fetchUpVideosByPage`（pn>1）撤掉现状恒败的 APP 裸调预检，改纯 Web 三轮退避链
- **Rationale**: 两侧 ps 同为 30（D2），页界对齐，app 加载了 k 页后 Web 降级请求 pn=k+1 恰好衔接，无重叠无跳空；撤掉恒 -400 的预检每次翻页省一个必败请求
- **Alternatives considered**: app 失败即终止本源翻页能力（不降级）——违背 US3 降级保底，否决

### D5: MD5 与参数编码

- **Decision**: MD5 用 `cryptoFramework.createMd('MD5')`（复用 WbiSigner 既有模式）；AppSign 参数编码 = `encodeURIComponent` 按 key 排序拼接 + appsec 后取 md5——**不做** WbiSigner 的 `!'()*` 字符过滤（两套签名的服务端校验口径不同，AppSign 对齐 PiliPlus `Uri.encodeComponent` 形态）
- **Rationale**: 同一 md5 实现路径降低引入成本；编码差异是两套签名算法的固有区别，混用会算错 sign
- **Alternatives considered**: 抽公共 md5 工具类——WbiSigner.md5 仅 14 行且已稳定，为两处调用抽公共层属过度抽象，暂不抽（若第三处出现再抽）

### D6: APP 链到底判定以 `has_next` 为主信号（**spec 偏离项，待 Gate 确认**）

- **Decision**: APP 链到底 = `has_next==false` 或返回空列表；**短页（<30）但 `has_next==true` 不判到底**，正常翻页。Web 链保持现状（空页/整页重复判到底）
- **Rationale**: 若服务端钳制 ps（如上限 20），每页都成"短页"，按短页判到底会立即假到底、功能整个失效。`has_next` 是服务端的明确续传信号，比条数推断可靠
- **Alternatives considered**: 按 spec 边缘用例原文"短页即收回加载资格"——存在上述假到底风险，且该边缘用例撰写时未预见 ps 钳制场景，**建议修订 spec 该条**（Phase 2 Gate 请确认）
- **Spec 影响**: `spec.md` Edge Cases 第 4 条（"APP 链返回短页 → 按现有短页语义判定到底"）建议改为"APP 链短页且 `has_next==false` 才判到底；`has_next==true` 的短页正常续翻（防服务端 ps 钳制）"

### D7: 签名常量与请求参数形态

- **Decision**: `Constants.TV_APP_KEY = 'dfca71928277209b'`、`Constants.TV_APP_SEC = 'b5475a8825547a4fc26c7d518eaaa02e'`（公开 TV 端 pair，PiliPlus `lib/common/constants.dart:7` 同源；初稿 `dfca71928209b` 为截断笔误，实现阶段已核实修正）；请求参数沿用现有 `fetchUpVideosViaApp` 的 BiliDroid 形态（build/version/c_locale/channel/mobi_app/platform/s_locale/qn/statistics），该形态本身已对齐 PiliPlus，仅撤掉 `pn`、补 `aid`/`next`/`appkey`/`ts`/`sign`
- **Rationale**: 常量入 Constants 是本项目唯一真相源铁律；参数形态已在上轮（T018）对齐过，最小改动
- **Alternatives considered**: 无（常量散落违反项目铁律）

## Data Model

- **UpAppCursor**（BiliService 文件内、不导出）: `next: number`——APP 链服务端续传游标；生命周期见 D3 失效规则
- **cursor 缓存**: `Map<number, UpAppCursor>`，key 为 UP 主 mid，模块级会话内存态（进程序即活、退出即失、不落盘）
- **AppSign 签名参数组**: `appkey`/`ts`/`sign`——随请求实时生成拼入 query，无实体化、无缓存

## Contracts & Interfaces

- **AppSigner.signQuery(params: Record\<string, string\>): Promise\<string\>**（新增，`service/AppSigner.ets`）
  注入 `appkey` 与实时 `ts` → 参数按 key 排序 `encodeURIComponent` 拼接 → 追加 appsec 取 MD5 → 返回完整签名 query（含 `appkey`/`ts`/`sign`）。纯静态工具，无状态。
- **BiliService.fetchUpVideos(mid: number): Promise\<BiliVideo[]\>**（签名不变，行为变更）
  APP 签名头页（aid/next 缺省）优先：成功 → 更新 cursor 缓存、返回列表；任何失败 → 记日志、落 Web 三轮退避链（现状实现原样保留）：成功 → 删除该 mid cursor、返回列表；全败 → 抛最后一轮真实错误。
- **BiliService.fetchUpVideosOlder(mid: number, lastAid: number): Promise\<BiliVideo[]\>**（新增）
  无 cursor → 抛错（调用方走 Web）；有 cursor → 签名请求 `aid=lastAid, next=cursor.next`：成功 → 更新或（`has_next=false`/空页时）删除 cursor、返回列表；失败 → 删除 cursor（粘性降级）并抛错。
- **BiliService.fetchUpVideosByPage(mid: number, pn: number): Promise\<BiliVideo[]\>**（签名不变，行为变更）
  pn>1 纯 Web 三轮退避链（撤掉恒 -400 的 APP 裸调预检）；pn==1 行同 `fetchUpVideos`。
- **SourcePage.loadOlder UP 分支**（`pages/SourcePage.ets`）
  cursor 可用 → 先 `fetchUpVideosOlder(末条 aid)`：成功追加（bvid 去重保持）+ `olderPage++`；抛错 → 记日志、`fetchUpVideosByPage(mid, olderPage+1)`：成功追加 + `olderPage++`。cursor 不可用 → 直接 Web 同页号。空页 → `canLoadOlder=false`（现状）。endArmed/loadingOlder 门槛逻辑原样不动。
- **日志契约**（FR-006）: `'net'` 记 APP 签名链成功（含 mid/条数/是否续游标）与降级落 Web；`'error'` 记 APP 链失败明细（含错误码），条目文案可区分链路。

## Changelog

- 2026-10-08: 初版（Phase 2 产出）。D6 含一项 spec Edge Cases 偏离建议，待 Phase 2 Gate 确认后回写 spec.md。
