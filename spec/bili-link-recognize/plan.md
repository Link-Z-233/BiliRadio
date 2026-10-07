# Implementation Plan: B站链接识别与短链解析修复（KI-4 闭环）

**Input**: Feature specification from `spec/bili-link-recognize/spec.md`

## Summary

在「添加订阅」输入框的识别链路最前置环节增加 B 站链接抽取（分享文案 → 干净 URL），将短链解析重写为「禁跟随重定向 + 直读 Location」的正确实现（含迭代跳数限制、错误分型、会话级缓存、专用超时），并扩展目标识别器的类型覆盖（av 号 URL 形态、移动端空间/收藏夹/合集/系列形态）。完成后更新 PROJECT_NOTES.md 闭环 KI-4。

**范围标记（用户确认）**：播放队列输入框（`QueueSheet.ets` 的 `addByBv`，L182-211）**本轮保持完全不动**——它是「批量 BV 号」工具，语义与本轮「单值识别分发」不同；其行为演化（入队不打断）按 PROJECT_NOTES.md「三、规划与预告」既有计划单独排期。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，compatibleSdkVersion 6.1.1(24) / targetSdkVersion 26）  
**Primary Dependencies**: `@kit.NetworkKit`（http）、`@kit.ArkUI`（promptAction）、`@kit.IMEKit`（inputMethod）  
**State Management**: 保留项目现有 State Management V1（`@State`/`@StorageProp`），增量改造不迁移 V2  
**Storage**: 无新增持久化；短链解析缓存为内存会话级（Map + LRU，不落盘）  
**Testing**: 项目无自动化测试框架；采用 `arkts_check` 静态检查 + `devecocli build` 构建 + 实机验证（US1/US2 使用两条真实分享文案）  
**Target Platform**: HarmonyOS 手机/平板（实机 + 模拟器）  
**Project Type**: 既有 HarmonyOS 应用（BiliRadio）增量改造  
**Performance Goals**: 短链解析单跳请求体 ≤ 1KB（302 响应）；缓存命中路径零网络请求  
**Constraints**: 短链解析专用超时短于通用值（现通用 connect 15s / read 30s，见 `Constants.ets` L87-88）  
**Scale/Scope**: 新增 1 个 service 文件，修改 3 个既有文件 + 1 个备忘录，不动页面结构与路由

## Project Structure

### Documentation (this feature)

```text
spec/bili-link-recognize/
├── spec.md              # 需求规格（Phase 1 产物）
└── plan.md              # 本文件（Phase 2 产物）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── LinkResolver.ets        # [新增] 链接抽取 + 目标识别 + 短链解析（KI-4 逻辑集中地）
│   ├── BiliService.ets         # [修改] 删除 resolveShortUrl（唯一调用方迁往 LinkResolver）；导出 UA/Referer 常量供 LinkResolver 复用
│   └── Constants.ets           # [修改] 新增短链解析专用超时两个常量
└── pages/
    └── AddSubscriptionSheet.ets # [修改] recognizeInput 迁出；handleMainInput 改为「抽取→判定→解析→分发」编排；删除回写；错误分型提示

PROJECT_NOTES.md                 # [修改] KI-4 条目闭环更新（含行号漂移修正、范围外新发现问题登记）
```

**Structure Decision**: 遵循项目既有架构（`pages/` + `service/` + `model/` + `component/`，无 MVVM 目录，不引入迁移）。新增 `LinkResolver.ets` 一个 service 文件集中 KI-4 全部链接识别逻辑（纯函数 + 静态方法，无 UI 依赖、可独立验证）；不拆更多文件——识别、抽取、解析三者共享模式常量与结果模型，拆分反而制造跨文件耦合。页面文件只保留编排与 UI 分发。`RecognizeResult` 模型随逻辑迁入 `LinkResolver.ets`（该类型仅识别链路使用，无需独立 model 文件）。

## Complexity Tracking

无 Constitution 违规需要辩护；未引入新模式、新目录、新依赖。

## Research & Decisions

### D1 短链解析改为「禁跟随 + 读 Location」

- **Decision**: 短链请求设置 `maxRedirects: 0`（本机 SDK `@ohos.net.http.d.ts` 确认：值为 0 时禁用重定向），从 3xx 响应头读取 `location`（键名大小写不敏感处理），人工迭代跟进：Location 仍为短链域名则继续请求（上限 3 跳），否则视为最终目标；相对 Location 按当前短链的协议+域名补全为绝对地址。最终目标须为 B 站域名，否则判「无有效目标」。
- **Rationale**: 实测（2026-10-07）b23.tv 全部以 302 + 绝对 Location 响应；系统 http 默认跟随重定向导致现实现拿到落地页正文，是「误取随机视频」的根源。禁跟随后每跳仅获得 ≤1KB 的 302 响应，快且无正文污染。
- **Alternatives considered**: ① 保持跟随 + 改进正文正则——无法可靠区分「页面里的目标链接」与「页面里随意出现的视频号」，误路由风险不可消除；② 用 `onHeadersReceive` 拦截重定向——API 面向流式场景，复杂度高于 `maxRedirects: 0` 直读。

### D2 新建 LinkResolver.ets 集中识别逻辑

- **Decision**: `recognizeInput` 与 `RecognizeResult` 从 `AddSubscriptionSheet.ets`（现 803 行）迁出，与新增的抽取、短链解析、缓存一起放入新文件 `service/LinkResolver.ets`；`BiliService.resolveShortUrl`（L935-966）删除。
- **Rationale**: 识别器需新增 5+ 个模式族，留在页面文件会继续膨胀且无法脱离 UI 验证；`BiliService` 已 1757 行，不宜再增。集中后 `AddSubscriptionSheet` 仅做「抽取结果 → 分发动作」的 UI 编排，`resolveShortUrl` 唯一调用方就是该页面，删除无涟漪。
- **Alternatives considered**: 全部留原文件最小 diff——拒绝理由：两处宿主文件均已过长，且 KI-4 后续若再扩展（动态/直播目标）需要稳定落点。

### D3 会话级 LRU 缓存

- **Decision**: 模块级静态 `Map<规范化短链, ShortLinkResult>`，容量 50：命中先删后插（实现 LRU 新鲜度），超容量淘汰最旧键；键为小写化 host + path 的规范化短链。不持久化、不设 TTL。
- **Rationale**: 短链 → 目标映射长期稳定，会话内去重即可满足 FR-006；Map 的插入序天然支持简易 LRU，无需引入数据结构。
- **Alternatives considered**: 持久化缓存——短链首解代价仅一次轻量 302 请求，落盘引入失效策略复杂度，收益不成比例。

### D4 错误分型用结果模型而非异常

- **Decision**: `resolveShortLink` 返回 `ShortLinkResult`，携带结局枚举（成功/网络失败/超出跳数/无有效目标/目标无法识别）与对应中文用户提示；网络异常在内部捕获，不再向上抛。
- **Rationale**: 现实现的 `return shortUrl` 静默降级（KI-4 #4）源于「失败与成功共用一个返回通道」；结果模型让页面按结局选择提示文案，分支清晰且天然可缓存（失败结果不入缓存）。
- **Alternatives considered**: 抛带类型的异常——ArkTS 下自定义异常类型经 catch 类型擦除后仍需判别字段，不比结果模型直接。

### D5 识别器目标覆盖扩展（模式族）

- **Decision**: `recognizeInput` 在既有 8 条规则基础上扩展，保持「先命中先返回」结构，新增/调整：
  1. av 号 URL 形态：`bilibili.com/video/av{数字}`（忽略大小写）→ `av`，插在 BV 全文扫描之后、空间/合集规则之前；
  2. UP 空间移动端形态：host 为 `m.bilibili.com` 的 `/space/{数字}` 路径 → `up`；
  3. 收藏夹/合集/系列：host 放宽为「bilibili.com 任意子域」，路径模式族不变（favlist/fid、lists、collectiondetail、seriesdetail），使 `space.bilibili.com` 与 `m.bilibili.com` 形态同规则命中；
  4. 既有桌面形态规则行为不变（回归基线）。
- **Rationale**: 实测空间短链 Location 为 `m.bilibili.com/space/{uid}?…`，不放宽 host 则 US2 不通；KI-4 #5 点名的 av/收藏夹/合集/系列同步补齐。「任意子域」比逐 host 枚举健壮（B 站存在 m./www./space./live. 等多种 host）。
- **Alternatives considered**: 逐 host 精确枚举——B 站 host 形态未穷举，枚举漏一个就失败一次，放宽到子域级别是识别场景的合理精度。

### D6 正文兜底收紧（防误路由）

- **Decision**: 仅当短链响应非 3xx（无 Location 可读）时才启用正文兜底；兜底**只提取**正文中「带 bilibili.com 域名（任意子域）的完整 URL」交识别器分类，**不再裸扫孤立的 BV 号**。
- **Rationale**: FR-009。现实现的裸 BV 扫描会把空间页里「最近投稿」的视频号当成目标（误播随机视频）；URL 形态提取天然把「目标链接」与「页面内容里出现的视频号」区分开。
- **Alternatives considered**: 保留裸 BV 扫描但限定响应码——不可靠，落地页是否含目标 BV 取决于页面结构，无法从外部保证。

### D7 短链路径视频号短路

- **Decision**: 短链 URL 的 path 部分命中 `BV` + 10 位字母数字时，直接产出视频目标，跳过全部网络请求（含缓存读写）。
- **Rationale**: 实测示例 `b23.tv/BV1iMtG6YEyr` 的目标就写在 path 里，302 都不用发；这是分享文案中最常见的视频短链形态。
- **Alternatives considered**: 一律走 302——多一次网络往返且增加一个失败面，无收益。

### D8 专用超时

- **Decision**: `Constants.ets` 新增 `SHORT_LINK_CONNECT_MS = 8000`、`SHORT_LINK_READ_MS = 8000`，仅短链解析请求使用；通用超时常量不动。
- **Rationale**: 302 响应体实测 ≤ 1KB，30s 读超时无意义；8s 覆盖弱网下单跳往返，且满足 FR-007「短于通用值」。
- **Alternatives considered**: 复用通用 15s/30s——弱网下用户面对「解析中」状态悬挂过久。

### D9 输入保持与统一清洗

- **Decision**: 全链路（短链与非短链分支）统一使用「抽取结果（或 trim 后原文）」；删除现短链成功后的 `mainInput` 回写。
- **Rationale**: FR-001/FR-010；顺带消除现非短链分支传未 trim 输入的失配（`" 123 "` 类 UID 输入）。
- **Alternatives considered**: 保留回写展示解析结果——用户原文更具上下文，识别成功本身已有后续动作（播放/进视图/toast）作为反馈，回写反而在失败重试时制造干扰。

## Data Model

```text
RecognizeResult（自 AddSubscriptionSheet.ets 迁入 LinkResolver.ets 并导出）
├── type: string    // '' | 'bv' | 'av' | 'up' | 'fav' | 'season' | 'series'
├── id: string      // 目标 ID（BV 号 / av 数字 / UID / fid / sid）
└── ownerMid: string // 合集/系列/收藏夹场景的归属 UP UID（可空）

ShortLinkOutcome（字符串常量集）
└── 'ok' | 'network' | 'hops' | 'no-target' | 'unrecognized'
    // 成功 | 网络失败 | 超出跳数 | 无有效目标 | 目标无法识别

ShortLinkResult
├── outcome: ShortLinkOutcome
├── target: string   // outcome='ok' 时的最终 B 站目标 URL；失败时为空
└── message: string  // 面向用户的中文提示（失败分型文案）

解析缓存（LinkResolver.ets 模块级静态）
└── Map<string, ShortLinkResult>  // 键：规范化短链（host 小写）；容量 50，LRU 淘汰；仅缓存 outcome='ok' 的结果
```

## Contracts & Interfaces

### LinkResolver.ets（新增，全部导出为静态方法/纯函数）

| 契约 | 签名 | 约束 |
|---|---|---|
| 链接抽取 | `extractBiliUrl(raw: string): string` | 返回文本中第一个 B 站域名（b23.tv / bili2233.cn / bilibili.com 及任意子域，忽略大小写）的 http(s) 链接，尾随标点（中英文句号/叹号/问号/右括号/引号等）已清除；未抽到返回 `raw.trim()` |
| 短链判定 | `isBiliShortLink(url: string): boolean` | host 为 b23.tv / bili2233.cn（忽略大小写）即真；无协议前缀的裸短链由调用方先经补前缀归一化 |
| 短链解析 | `resolveShortLink(shortUrl: string): Promise<ShortLinkResult>` | 先查缓存（命中零网络）；路径含视频号直接短路返回 `ok`；否则迭代 302（≤3 跳，`maxRedirects: 0`，读 Location 支持相对地址，专用超时 8s/8s）；最终目标须为 B 站域名；仅 `ok` 结果入缓存 |
| 目标识别 | `recognizeInput(input: string): RecognizeResult` | 语义同现实现并按 D5 扩展；先命中先返回 |

### AddSubscriptionSheet.ets（修改）

- `handleMainInput` 新编排（UI 层无网络/解析细节）：收起键盘 → `cleaned = extractBiliUrl(mainInput)` → 裸短链补前缀 → 若 `isBiliShortLink(cleaned)`：置 busy、调 `resolveShortLink`，按 `outcome` 分型提示或对 `target` 调 `recognizeInput` 后走既有分发 switch（bv/av/up/fav/season/series 六分支动作方法全部不变）；否则对 `cleaned` 直接 `recognizeInput` + 既有分发。
- 删除 `RecognizeResult`/`recognizeInput` 本地定义（改 import）、删除 `this.mainInput = resolved` 回写。
- 既有 `playBv`/`playAv`/`lookupUid`/`subscribeXxxById` 系列动作方法不动。

### BiliService.ets（修改）

- 删除 `resolveShortUrl`（L935-966）；导出现有模块级 `USER_AGENT`/`REFERER` 常量供 LinkResolver 复用（请求头与主站请求一致，避免风控特征分叉）。

### Constants.ets（修改）

- 新增 `SHORT_LINK_CONNECT_MS = 8000`、`SHORT_LINK_READ_MS = 8000`（只增不改）。

### PROJECT_NOTES.md（修改，验证通过后执行）

- KI-4 条目改「已修复」并修正登记行号；B3/B4/B5/B7/B8/C1/C2 等本轮范围外新发现问题按备忘录格式登记。

### 明确不改动（范围标记）

- `QueueSheet.ets` 的 `addByBv` 批量 BV 输入：本轮不动，演化计划见 PROJECT_NOTES.md「三、规划与预告」。
- 播放队列输入框、搜索框、源详情页等其余入口零改动。
