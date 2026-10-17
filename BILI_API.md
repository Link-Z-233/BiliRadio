# BILI_API

B 站 API 探索唯一沉淀点。三段式：§1 本项目（BiliRadio）在用端点与坑；§2 biliRelay 历史探索迁移；§3 本轮及后续新增实测。

## §1 本项目 API 探索汇总

素材来源：`AGENTS.md`、`entry/src/main/ets/service/Constants.ets` 与各 service 文件机制注释、既有 spec 工件。

### 1.1 在用端点清单

| 端点 | 用途 | 鉴权/签名 | 备注 |
| --- | --- | --- | --- |
| `GET api.bilibili.com/x/web-interface/view` | 视频详情（bvid/aid） | 匿名可用 | 风控最松 |
| `GET api.bilibili.com/x/player/playurl` | 播放取流 | 登录 Cookie | `qn=16` + `fnval=4048`（DASH 音频）/`fnval=0`（兜底）；稿件在但不给播回 `-404`，会员/付费 `-104`，风控 `-412` |
| `POST api.bilibili.com/x/click-interface/web/heartbeat` | 播放心跳上报 | 登录 Cookie | `Constants.BILI_HEARTBEAT_URL` |
| `GET api.bilibili.com/x/web-interface/nav` | 登录态校验 + WBI 密钥源 | 匿名需 buvid cookie | 签名钥在 `data.wbi_img`（属性名非 `wbi`）；匿名返回需 buvid cookie + Referer `https://www.bilibili.com/`；未登录时 `data` 非空、wbi_img 仍在 |
| `GET api.bilibili.com/x/frontend/finger/spi` | buvid3/buvid4 设备指纹 | 匿名 | `BiliSession` 暖场用 |
| `POST api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi` | 风控激活 | 匿名 | buvid 激活后才可过部分风控；`Constants.BILI_EXCLIMB_WUZHI_URL`，复刻验证 code 0 |
| `GET app.bilibili.com/x/v2/space/archive/cursor` | UP 投稿列表 APP 签名链（主链） | TV appkey APP 签名 + BiliDroid UA | 无 cookie/WBI 依赖；响应 `data.list.vlist` 与 `data.item` 双形状共用解析；翻页 `aid`=列表末条（int64）+ `has_next` 门控，响应已无 `data.next`；顶层 `data.count`=投稿总数（页头「N 集」真值来源） |
| `GET api.bilibili.com/x/space/wbi/arc/search` | UP 投稿 Web 补稠链（首选） | WBI 签名 + buvid cookie + space 头 | 与网页/PiliPlus 同源的完整数据端点；APP 签名链失败粘性降级至此 |
| `GET api.bilibili.com/x/space/arc/search` | UP plain 端点（降级兜底） | 无签名 | WBI 被风控时兜底；实测数据完整性次于 WBI（部分条目不下发） |
| `GET api.bilibili.com/x/space/wbi/acc/info` | UP 主信息 | WBI 签名 | `-352` 频发：最多 3 轮「WBI acc/info → card 兜底」，轮间重置 buvid 指数退避 |
| `GET api.bilibili.com/x/web-interface/card` | UP 信息兜底 | WBI 签名 | acc/info 风控失败后的降级 |
| `GET api.bilibili.com/x/v3/fav/folder/created/list-all` | 收藏夹列表 | 登录 Cookie | AddSubscriptionSheet |
| `GET api.bilibili.com/x/v3/fav/resource/list` | 收藏夹条目 | 匿名可查公开夹 | 无 rights 类逐条权限字段，仅 `attr`(int) |
| `POST api.bilibili.com/x/v3/fav/resource/deal` | 收藏/取消收藏 | 登录 Cookie + bili_jct | |
| `GET api.bilibili.com/x/polymer/web-space/seasons_series_list` | 合集/系列列举 | **无需 WBI（带签名反致 -400，见 §3.2）** | 匿名裸请求 code=0 正常（2026-10 核查） |
| `GET api.bilibili.com/x/polymer/web-space/seasons_archives_list` | 合集条目 | 匿名 | `season_id` 单参数即可，meta 自带 mid/名称/总数 |
| `GET api.bilibili.com/x/series/archives` | 系列条目 | 匿名 | |
| `GET api.bilibili.com/x/series/series` | 系列 meta 反查 | 匿名 | `series_id` 反查 mid/名称/总数 |
| `GET passport.bilibili.com/x/passport-login/web/qrcode/generate`、`/poll` | 扫码登录 | 匿名 | 凭证经 `data.url` 回调参数与 poll 响应 Set-Cookie 双路收集（§2.3 实验 13）；轮询须对瞬时失败容错（实验 11/12） |
| `b23.tv` 短链 | 链接解析 | - | rcp（`@kit.RemoteCommunicationKit`）+ `autoRedirect`，见 §1.3 |

### 1.2 鉴权与签名

- **APP 签名**（`entry/src/main/ets/service/AppSigner.ets`）：TV appkey/secret（`Constants.TV_APP_KEY/TV_APP_SEC`），`sign = md5(encodeURIComponent 排序参数 + secret)` 拼接 `&sign=`；请求头 BiliDroid UA（`Constants.BILI_APP_USER_AGENT`）。APP 端点（`app.bilibili.com`）不认浏览器 cookie。
- **WBI 签名**（`entry/src/main/ets/service/WbiSigner.ets`）：`nav` 接口 `wbi_img.img_key/sub_key` → 64 元混淆表取 32 位 mixinKey → 参数排序（过滤 `!'()*` 字符）+ `wts` → `w_rid = md5(串 + mixinKey)`。
- **设备指纹/风控激活**（`entry/src/main/ets/service/BiliSession.ets`）：SPI 取 buvid3/buvid4 → ExClimbWuzhi 激活 → 后续 Web 请求带 cookie；buvid 被风控标记后可重置重暖。
- **登录态**：扫码登录（`BiliSession`）→ SESSDATA/bili_jct 落 `SecureStore`；心跳维持播放会话。
- **space 端点头**：`Referer`/`Origin` 指向 `https://space.bilibili.com/{mid}`（`buildSpaceHeaders`）。

### 1.3 已知坑与对策

- **`@ohos.net.http` 的 `maxRedirects: 0` 是「零配额」而非「禁重定向」**——短链解析改用 rcp + `autoRedirect`（`entry/src/main/ets/service/LinkResolver.ets`）。
- **风控概率拦截（-412/-352）**：暖场 buvid + 退避重试；UP Web 链/acc/info 对可重试错误重置 buvid 指数退避后进下一轮，业务错误（-404/-400/-101）立即失败；全败抛最后一轮真实错误码。
- **密集请求风控会升级**（412 → 352 → 403/799 梯度，见 §2.3 实验 8）：实测脚本请求间隔 ≥3s；各端点风控强度不同，`view` 最松、`space` 最严。
- **分 P：顶层 `cid` 永远等于 P1 的 cid**，取哪一 P 只能读 `pages[].cid` 或用户指定的 `?p=N`（§2.3 实验 19）。
- **列表源字段名各不相同**，勿写一条回落链硬套（§2.3 实验 20）。
- **登录态下 `data` 可能为 null**（如 nav 未登录回 `-101`），解析必须判空兜底（§2.2 速查表）。

## §2 biliRelay API 探索迁移

> 来源：`../bili/biliRelay/docs/B站API试错记录.md`（按原文迁移不改写，仅调整标题层级与编号）。
> 原文环境备注：记录 biliRelay 对 B 站接口的真实试错过程（2026-09-05，M1 真网冒烟期间），包括每次实验的假设 → 结果 → 结论，以及一份「接口挂了怎么排查」的手册；结论已沉淀到 biliRelay 的 `AGENTS.md` 关键技术事实与代码注释，原文保存推理过程和证据，方便将来对照新变化。环境：Windows 11 家宽 IP、Python 3.14、无登录态（匿名）请求为主。
> 迁移说明：实验 15（Docker 部署验证）为非 API 内容，已剔除；其余章节全量迁入。

### 2.1 结论速查（截至 2026-09-05 的有效配置）

| 主题 | 有效做法 | 代码位置 |
|---|---|---|
| 匿名 412 | 请求前先匿名 GET `https://www.bilibili.com/` 领 `buvid3/b_nut/buvid4`（Set-Cookie），进程内缓存；用户 Cookie 优先、匿名时自动补设备键 | `bili_api._get_anon_cookie` / `_merge_cookie` |
| 412 / -352 概率拦截 | `_api_get` 退避重试 3 次（2s、4s 间隔），重试间重置设备 Cookie 重新暖场 | `bili_api._api_get` |
| dm_img_* 参数 | **不要带**（见实验 5：现在是负优化） | `get_up_videos` docstring 有警示 |
| space 列表接口 | 不带 dm_img_* 的 BRSS 原参数集 + WBI 签名 + 退避重试；实在被拦就隔 45–60s 再试 | `get_up_videos` |
| 302 直连 CDN | CDN 节点要求 **Referer+UA 同时在场**，缺一即 403；URL 可复用、支持 Range | 见实验 7 |
| 客户端直连 403 时 | 切 `BILICAST_DIRECT=0` 走服务端 Range 代理（实测 206 + Content-Range 正确） | `engine.serve_stream` |
| 分 P 用哪一 P | **顶层 `cid` 永远等于 P1 的 cid**，要哪一 P 只能读 `pages[].cid` 或用户给的 `?p=N` | 见实验 19；`engine._fetch_bv` |
| 列表源的字段名 | **六个源各不相同**，别写一条回落链硬套：fav=`intro/pubtime/upper.name/cover`、up=`description/created/author/length`、watchlater=`desc/pubdate/owner.name`、season/series 条目**不带**作者与简介 | 见实验 20；`engine._fetch_playlist` / `_fetch_collection` |

### 2.2 状态码速查（本机实测含义，非官方文档转述）

| 码 | 含义（实测） | 触发场景 | 对策 |
|---|---|---|---|
| HTTP 412（JSON code -412） | WAF 拦截 "request was banned" | 匿名无 buvid 必现；有 buvid 也概率出现；请求密集时加剧 | 暖场 + 退避重试 |
| -352 | 风控校验失败 | space WBI 端点概率性返回（有 buvid、签名有效时仍出现） | 退避重试；间隔重试 |
| -403 | 访问权限不足 | **dm_img_* 带了硬编码占位值时必现**（详见实验 5/6）；另：WBI 请求未带签名也会这样 | 去掉 dm_img_*；确认 w_rid 在参数里 |
| -799 | 请求过于频繁，请稍后再试 | 短时间高频测试后（自己把自己打限流了） | 冷却 1–5 分钟 |
| -101 | 账号未登录 | nav 带过期 Cookie；注意此时响应 `"data": null`，解析必须 `(data or {})` 兜底 | 重新登录 |
| 86101 / 86090 / 0 / 86038 | 扫码：待扫 / 已扫待确认 / 成功 / 过期 | passport qrcode generate/poll | 状态机轮询 |
| HTTP 403（CDN，无 JSON） | CDN 拒绝请求 | 裸请求或只带 UA、只带 Referer 访问 bilivideo CDN | Referer+UA 同时带 |

### 2.3 试错时间线

#### 实验 1：首跑 feed 直接 412
- **操作**：起服务，`curl /feed/up/546195.xml`。
- **结果**：404，日志 `{'ok': False, 'code': -412, 'message': 'request was banned'}`。
- **假设**：匿名请求没有 buvid 设备 Cookie（AGENTS 事实 2 的已知坑），B 站 WAF 对无 buvid 请求直接 412，与签名/登录无关。
- **依据**：bili-podcast `network.py::ensure_cookies` 的注释明说「B 站 WAF 对没有 buvid 设备 Cookie 的请求直接回 412」。

#### 实验 2：照 bili-podcast 模式做暖场
- **操作**：`bili_api` 加 `_get_anon_cookie()`（匿名 GET 主站，从 Set-Cookie 提取 buvid3/b_nut/buvid4，进程内缓存）+ `_merge_cookie()`（用户 Cookie 优先）。重启服务重试。
- **结果**：仍 -412。
- **关键诊断**：独立进程里先取 Cookie 再调 `get_up_videos`——**第一次调用就成功**。
- **结论**：暖场有效，但 WAF 是**概率性**放行（AGENTS 事实 1），单次失败不代表配置错 → 需要退避重试，而不是继续改请求本身。

#### 实验 3：退避重试
- **操作**：`_api_get` 对 -412 退避重试 3 次（间隔 2s、4s），重试间重置设备 Cookie（新 buvid 可能通过率更高）。
- **结果**：server 侧仍失败，但错误码**变成了 -352 风控校验失败**——说明 412 已能穿透，暴露出下一层风控。
- **推论**：412（WAF 层）和 -352（风控层）是两道独立的闸，重试列表要同时覆盖。

#### 实验 4：量化概率
- **操作**：独立进程跑 5 次冷启动（每次重置匿名 Cookie），中间 sleep 1s。
- **结果**：`-412 / -352 / -352 / -412 / ok`，成功率 1/5，单次耗时 4–16s（含内部重试）。
- **结论**：概率放行实锤。纯重试能过但慢；此时怀疑缺防风控参数 → 去找蓝本对照。

#### 实验 5：照 Bili23 补 dm_img_* 指纹参数（**负优化，已回退**）
- **操作**：只读 Bili23 `parse/parser/space.py`：它请求 `x/space/wbi/arc/search` 时带 `dm_img_list="[]"`、`dm_img_str`（base64 的 WebGL 串）、`dm_cover_img_str`、`dm_img_inter`（JSON 串）等常量占位指纹参数。以为这就是 -352 的缺口，照搬补齐并一并签名。
- **结果**：5 次冷启动**全部 -403 访问权限不足**——失败率从 4/5 变 5/5，且错误码变了。
- **结论（重要）**：B 站现在**校验 dm_img_* 的值**，网上流传的硬编码占位值已是负优化。勿照搬上游参数集；从上游同步代码时先实测再定。

#### 实验 6：对照矩阵隔离变量
- **操作**：同一进程内 2×2 对照（间隔 3s）：plain 端点不带 dm_img / WBI 端点不带 dm_img / WBI 端点带 dm_img。
- **结果**：
  ```
  plain-noDM  0  OK
  wbi-noDM    0  OK
  wbi-DM    -403  访问权限不足
  ```
- **结论**：-403 就是 dm_img_* 引起的，铁证。回退到 BRSS 原参数集（`mid/ps/pn/order/tid/keyword/platform/web_location`）后 plain 和 WBI 端点都通。
- **副产品**：也解释了 -403 的另一个可能成因——`_get_mixin_key()` 走 nav 取 mixin key，nav 也被 WAF 拦时会**静默返回 None → 请求未签名** → WBI 端点同样报 -403。排查 -403 时先确认请求里有没有 `w_rid`。

#### 实验 7：回退后间隔重试
- **操作**：服务侧以 45s 间隔重试 `/feed/up/546195.xml`。
- **结果**：第 1 次即 200、30 个条目；feed 缓存 30 分钟内不再打 B 站。
- **结论**：概率拦截窗口是秒级到分钟级的；对单用户场景「重试 + 缓存」足够，不需要更复杂的方案。

#### 实验 8：密集测试的自我放大
- **过程**：冒烟期间几十次密集请求后，出现 -799（过于频繁），冷却 1–2 分钟内仍 -403，数分钟后恢复。
- **结论**：风控强度与请求密度相关且**会升级**（412 → 352 → 403/799 梯度）。调试时别贪快，间隔 45–60s；各端点风控强度不同：`view`（视频详情）全程宽松，`space`（UP 列表）最严——冒烟时可以先打 view 确认服务本身是好的，再等 space 放行。

#### 实验 9：302 直连的 CDN Referer 陷阱
- **操作**：`/stream/<bvid>` 得到 302 → 对 Location（cn-sdjn bilivideo CDN 音轨）做头组合实验：
  ```
  UA(full Chrome) only          403
  Referer only                  403
  无头                          403
  UA("Mozilla/5.0") + Referer   206（Range 0-1023，精确 1024 字节）
  UA + Referer（重复请求）       200，全文可复用
  full Chrome UA + Referer      200
  ```
- **结论**：
  1. 该节点要求 **Referer+UA 同时在场**，缺一即 403，与 UA 具体值无关；
  2. playurl 签名 URL **可复用**（deadline 内多次请求均可）；
  3. 播客客户端跟随 302 时不会带 B 站 Referer → **直连模式对这类客户端可能 403**。这正是 engine 预留代理回退的原因。
  4. **AntennaPod 真机实测（2026-09-06）**：直连模式播放报 403（无法播放媒体文件），坐实第 3 条；切代理模式后可用。
- **对策**：播放异常切 `BILICAST_DIRECT=0`。升级路径（未做）：302 时从 playurl 的 `backup_url` 里挑不查 Referer 的节点。

#### 实验 10：代理模式验收
- **操作**：`BILICAST_DIRECT=0` 重启，对 `/stream` 发 `Range: bytes=1000000-1000999`。
- **结果**：206 + `Content-Range: bytes 1000000-1000999/1167163` + `Content-Length: 1000`（寻址正确）；全量 200 拉完 1.17MB @ ~7MB/s。
- **结论**：代理模式下客户端 seek 可用，性能足够单用户流式。

#### 实验 11：扫码登录被 WAF 打断（首次失败）+ 手机端「登录有效期」弹窗
- **操作**：`--qr` 生成二维码（19:59），用户手机扫码确认（20:00）。
- **现象**：
  1. 手机确认时弹出**新弹窗「温馨提示」：选择「短期登录」（24 小时有效）或「普通登录」**——B 站 App 较新的行为，服务器/自用场景必须选**普通登录**，选短期登录 Cookie 一天就失效；
  2. 手机端确认成功，但 CLI 侧没有落盘 cookies.json。
- **根因**：轮询请求（passport qrcode/poll）自身也会撞 WAF 概率 412；初版 `_cmd_qr` 把任何一次轮询顶层失败当致命错误直接退出——用户在手机上确认时，CLI 已经退了，没人接住凭证回调。
- **修复**：轮询循环对瞬时失败容错（连续 5 次才放弃，waiting/scanned 会清零计数），只把 86038 过期当终止条件；提示文案加「选普通登录」。
- **教训**：与 B 站交互的每一条请求（包括 passport 轮询）都要按概率被拦来设计；等待循环不能因为一次失败就终止。

#### 实验 12：多步确认弹窗耗尽二维码寿命 → 过期自动续期（Bili23 对照）
- **现象**：第二次扫码，手机端在「短期/普通登录」之后又出现「是否在公共环境登录」等**多步正常登录选项**（用户确认：这些是正常登录 UX，不是风控），在这一步登录失败。
- **根因**：B 站二维码寿命**从生成起算约 3 分钟**；App 端每多一个确认弹窗就多几秒到几十秒，答完弹窗二维码已过期（86038）→ CLI 退出、手机端确认也随之失败。弹窗本身不失败，**耗时才是敌人**。
- **Bili23 对照（只读）**：其 `QRCodeScanStatus` 枚举与我们一致（86101/86090/0/86038，无新码）——弹窗不在协议层；它是 GUI 应用，二维码画在窗口里、**1 秒轮询**、过期后用户点一下界面重新生成。App 弹窗它完全不参与。成功后从 HTTP 客户端 cookiejar 快照取 Cookie（与我们解析回调 URL 同源等价）。
- **修复**（CLI 等价实现）：轮询 2s→1s；86038 不再退出，**自动重新生成二维码**并重写同一页面文件；页面加 `<meta refresh=30>` 自动刷新，浏览器无需手动操作；最多续期 5 次后提示改用粘贴登录。落盘页面改为原子写（防自动刷新读到半截文件）。
- **教训**：把「二维码过期」当流程分支而不是错误；确认流程越长越要自动续期。

#### 实验 13：扫码成功后「没解析到 SESSDATA」——凭证改走 Set-Cookie 下发
- **现象**：第三次扫码（CLI 已加自动续期），手机端确认成功、poll 也返回了 success，但 CLI 报
  「✗ 没解析到 SESSDATA」——`data.url` 回调参数里没有凭证。
- **根因**：B 站把扫码凭证的下发方式**从「data.url 回调查询参数」改成了（或按账号/新确认流程分流到）「poll 响应的 Set-Cookie 头」**。只解析 url 参数的客户端（bili-podcast 旧形态）会拿到空 Cookie。这也解释了为什么 Bili23 成功后是**从 HTTP 客户端 cookiejar 快照**读 Cookie（`base.py::update_cookies` → `snapshot_client_cookies()`），BRSS 也是双路收集（URL 参数为主、Set-Cookie 兜底、跨域跳转兜底）。
- **修复**：poll 改用带 CookieJar 的请求保留响应 Set-Cookie（`auth._passport_get_with_jar`），成功时把
  **url 参数与 Set-Cookie 两路合并**进 `data["cookies"]`（url 优先、jar 补缺）；412 退避重试同样适用于 poll。
- **教训**：同一接口的凭证下发位置会随账号的确认流程变化；回调参数和响应头两路都要收，对照 Bili23 的
  cookiejar 方案不是风格差异而是功能必需。

#### 实验 14：合集/系列（M2）端点发现——`seasons_list` 404，从 space 页 JS 包挖出真实端点
- **现象**：按 bilibili-API-collect 记载的 `x/polymer/web-space/seasons_list`（列用户全部合集）请求返回 -404
  （带 WBI 签名也一样），`x/series/serieslists` 同样 404；space 列表页 HTML 是 JS 壳（10KB，无 SSR 数据可挖）。
- **方法**：抓 space 列表页引用的 JS bundle，正则 grep `/x/...season|series|lists...` 路径——拿到 2026 年前端
  实际在用的全部端点：`/x/polymer/web-space/home/seasons_series`（合集+系列总列表）、
  `/x/polymer/web-space/seasons_archives_list`（合集视频列表）、`/x/series/archives`（系列视频列表）、
  `/x/series/series`（系列 meta），与 Bili23 蓝本一致的三个都在，仅"总列表"端点换了新路径。
- **实测结论**：
  1. `seasons_archives_list` **不需要 mid**（只传 season_id 即返回 meta+archives，meta 自带 mid/名称/总数/封面）
     → feed 路由可以只带 season_id 单参数；
  2. `x/series/series?series_id=` 可从 series_id **反查 mid/名称/总数**（系列列表接口不含 meta，Bili23 两步走
     依然是必要的）；
  3. `home/seasons_series?mid=&page_num=&page_size=` 返回 `items_lists.{seasons_list,series_list}`，
     列一个 UP 的全部合集与系列（M3 WebUI「选合集」可用）；
  4. 三个列表接口均无需 WBI 签名、无需登录（匿名可查他人空间）。
- **顺带修正**：`collectiondetail?sid=` 旧合集页在 M1 曾按 BRSS 逻辑映射为收藏夹（fav），M2 按语义修正为
  season（有断言锁定）；`seriesdetail?sid=` → series；新版 `/lists/{sid}?type=season|series` 无 type 默认 season。
- **教训**：接口文档滞后时，**前端 JS 包是最可靠的端点字典**；HTML 没有 SSR 数据就直接 grep bundle。

> （实验 15 为 Docker 部署验证，非 API 内容，迁移时剔除）

#### 实验 16：Cookie 自动续期（refresh_token）可行性探针（2026-09-19，只读）
- **动机**：扫码登录时下发的 `refresh_token` 已存 `cookies.json` 的 `ac_time_value` 但一直没用；
  若能自动续期，fav/watchlater 每月一次的静默降级就变成自动保活。本轮只验证可行性，**不执行刷新 POST**
  （POST 会轮换 refresh_token，属真实变更，等拍板后单独实施）。
- **端点核对**（bilibili-API-collect `docs/login/login_action/cookie_refresh.md`）：
  注意主机是 **`passport.bilibili.com`**——用 `api.bilibili.com` 会 404（本轮实测踩到）。
  1. `GET /x/passport-login/web/cookie/info` → 返回体只有 **`refresh`**（是否需要刷新）+ **`timestamp`**；
  2. `GET /x/passport-login/web/key` → 返回 **`data.key`**（RSA 公钥）+ **`data.hash`**（key id）；
  3. `POST /x/passport-login/web/cookie/refresh`：`csrf`（cookie 里的 bili_jct）+ `refresh_csrf`
     （把 `'"ts"'` **含双引号** 用公钥 RSA 加密）+ `refresh_token`（旧 refresh_token 同样 RSA 加密）+
     `source=main_web`；成功后还要 `POST /x/passport-login/web/confirm/refresh` 确认并**换存新 refresh_token**。
- **实测结果**：两个 GET 都 `code: 0`；当前 Cookie 的 **`refresh: True`**（已被 B 站标记需要刷新）。
- **可行性结论：成立。** 剩余实现点：① 纯标准库 RSA/PKCS#1 v1.5 加密（`pow(m, e, n)` 手工填充，约 20 行）；
  ② 刷新成功沿用现有「nav 验证通过才原子落盘」事务写新 Cookie；③ 失败回滚 + 保留现有邮件告警兜底。
- **教训**：接口文档要核对**主机名**（passport vs api）；探针阶段只做只读 GET，
  会变更状态的 POST 留到正式实施——探针脚本本身也应一次性用完即删。
- **事后勘误（实验 17）**：本实验"用 `x/passport-login/web/key` 的公钥加密 `'"ts"'`"的推断**是错的**——
  该接口是密码登录的加密公钥；正确流程见实验 17。

#### 实验 17：Cookie 自动续期正式实施——三个坑 + 真机跑通（2026-09-19）

补丁 11 实施（`auth.refresh_if_needed` + `notify --check` 接线 + `--refresh` CLI），以 bilibili-API-collect
`docs/login/cookie_refresh.md` 原文为准重推流程，真机 `--refresh` 跑通（`refreshed`，SESSDATA/bili_jct/
ac_time_value 全部滚动，`--status` logged_in）。三个坑，全是"想当然 vs 文档原文"的差距：

1. **`web/key` 是密码登录的公钥，与 Cookie 刷新无关。** 第一版按实验 16 的推断用它加密 `'"ts"'` 与
   refresh_token 上送 → POST 回 `-101 账号未登录`（参数不被识别时服务端不给细分错误码，别从 -101 反推
   Cookie 没带上）。**正确流程**：RSA 只用来生成 correspond 页**路径**——OAEP(SHA-256) 加密
   `refresh_<毫秒时间戳>`（明文无引号、空 label）→ 小写 hex，公钥是 web 端 wasm 内置的**固定值**。
2. **`refresh_csrf` 是从 correspond 页面 SSR 出来的**：GET `www.bilibili.com/correspond/1/<path>`，
   解析 `<div id="1-name">` 的文本；path 错/过期返回 404 页。POST 的 `refresh_csrf` 与 `refresh_token`
   （旧值）都是**明文**参数。
3. **correspond 页返回 gzip**：urllib 不自动解压，首测拿到 590 字节"乱码"、正则全空。显式发
   `Accept-Encoding: gzip` 并手动 `gzip.decompress`。

另两个易错点（文档口径，实现时对齐）：POST `cookie/refresh` 的 `refresh_token` 用**旧**值、
新 token 只在响应 `data.refresh_token` 里；`confirm/refresh` 的 `refresh_token` 也是**旧**值（不是新值），
csrf 用**新** bili_jct。落盘前必须 nav 验证（本项目现有事务），confirm 失败不阻断。

#### 实验 18：space 恒 -403 —— 不是 IP 风控，是 WBI 密钥取不到（2026-09-20，生产机只读诊断）

- **现象**：云服务器上三个 **UP 主（`up`）** 源的 DAV 目录全空（rclone 挂载点里 `ls` 无内容），
  日志里三行 `get_up_videos_all failed: {'ok': False, 'code': -403, 'message': '访问权限不足'}`；
  同一批请求里**三个合集（`season`）源全部 207 正常**。根目录列表里三个 UP 源的
  `getlastmodified` 是 `Jan 1 2000`（= 无 items 缓存），三个合集有真实时间。
- **第一反应（错的）**：对照组只有 season 正常 + 云机房 IP → 判成"space 端点风控/机房 IP 被封"
  （旧结论还写进了项目记忆）。**幸好没有就此收工**：真要分档，得单独把每个口打一遍。
- **分层实测**（同一进程，4 个请求）：
  ```
  NAV    code= -101  data 是对象、wbi_img 存在      ← nav 正常（-101=未登录，符合预期）
  mixin_key= None                                    ← 拿不到密钥（3/3 次都是 None，不是偶发）
  PLAIN  space code= -799 请求过于频繁               ← 无签名那个口只是被限流（瞬时）
  signed 里有没有 w_rid = False                      ← 请求是"裸奔"发出去的
  WBI    space code= -403 访问权限不足               ← 报的就是这个，把 -799 盖掉了
  对照   season code= 0                              ← IP 没被封
  ```
- **根因**（`bili_api._get_mixin_key_locked`）：写了 `_mixinkey_ts = now`，而 `now` 只在外层
  `_get_mixin_key()` 里定义 → `NameError` → 被 `except Exception: return None` 吞掉 → 每次都返回
  None → `_sign_params(use_wbi=True)` 见密钥为空就**照原样发不签名请求** → WBI 端点回 -403。
  与实验 6 的副产品同源（"nav 被拦 → 静默不签名 → -403"），只是这次不是 nav 被拦，是我们自己的
  NameError。**自检为什么没抓到**：那条"WBI 签名向量"是直接注入 `_mixinkey` 的，只测 `_sign_params`，
  从不经过取密钥这条路 → 157 项全绿。
- **验证**：手工按混淆表算出 32 位密钥、注入 `_mixinkey/_mixinkey_ts` 后，**同一 IP、同一分钟**
  `get_up_videos('278761367', page=1, page_size=1)` → `ok=True, total=332, 首条 BV17Neb6wE87`。
- **结论**：
  1. `-403 访问权限不足` 在 space 上**首先怀疑签名**（请求里有没有 `w_rid`），其次才是权限/IP；
     一个无签名接口（season）作对照就能排除 IP 级封禁。
  2. 取密钥失败**必须留痕**，否则这个 -403 会把排查带向风控方向；已在 `_warn_mixinkey` 里加 stderr
     节流告警（本手册 §3 第 3 步那条 `print(api._get_mixin_key())` 本来就能一眼看穿，别跳过它）。
  3. `get_up_videos` 的错误是**两段覆盖**的：plain 的 -799 会被 WBI 的 -403 顶掉，日志里只看到最后一个
     —— 判 -403 之前先想想"第一个口说了什么"。

#### 实验 19：分 P 视频恒定出 1 条 —— 顶层 `cid` 是 P1 的 cid，不是"被选中的那一 P"（2026-09-20）

- **现象**：一个 2 分 P 的视频订阅后 feed 里只有 1 条，DAV 里只有 1 个文件，播出来的永远是 P1。
  `/video/BVx?p=2` 这种链接里的 `p` 被 `_recognize_url` 整个丢掉，连"用户想要哪一 P"都没进模型。
- **根因（一句话）**：`x/web-interface/view` 的**顶层 `cid` 就等于 `pages[0].cid`**——B站语义里它就是 P1，
  **不是"当前选中的那一 P"**。修前的 `engine._fetch_bv` 只读顶层 `cid`，于是 N 个分 P 全部塌到 P1。
- **实测证据**（匿名，`view` 端点，风控最松）：

  ```
  [view] BV1e6eF6yEnn  videos=2  顶层 cid=41934589711
         pages = [(page=1, cid=41934589711, part="琵琶曲真人翻拍"),
                  (page=2, cid=41934654420, part="P2对比版")]
  ```
  顶层 `cid` == `pages[0].cid`（41934589711），P2 的 cid（41934654420）**只存在于 `pages[]` 里**。
- **上游的同一口径**（独立佐证，Unlicense 的 yt-dlp 源码 `extractor/bilibili.py`）：
  ```python
  part_id = int_or_none(parse_qs(url).get('p', [None])[-1])
  cid = traverse_obj(video_data, ('pages', part_id - 1, 'cid')) if part_id else video_data.get('cid')
  ```
  —— 给了 `p` 就取 `pages[p-1].cid`；**没给才用顶层 `cid`**，而那时它 == P1。
  另外 `--no-playlist` 下多分 P 视频会落到 `part_id = part_id or 1`，也就是 P1——与我们的老行为同病。
- **修复**（见 v2.0 补丁 13）：`_fetch_bv` 读 `pages[]` 展开成 N 条（每条带自己的 `cid`/`page`），
  `?p=N` 进识别结果与缓存键（只订阅那一 P），身份穿透到 guid / enclosure / DAV / 体积键 / yt-dlp。
- **真网对照验证**（同一个 2 分 P 视频，`BV1e6eF6yEnn`）：

  | 检查 | 结果 |
  |---|---|
  | feed 条数 / guid | 2 条；`BV1e6eF6yEnn-41934589711`、`BV1e6eF6yEnn-41934654420`（两两不同） |
  | enclosure | `…/stream/BV1e6eF6yEnn?quality=64&cid=<各 P>` |
  | 两条流的 `Content-Range` 总长 | 524761 / 525002（不同） |
  | 两条流前 64KB 的 sha1 | `e2df6c23f022` / `84788fcb4927`（**不同音轨**） |
  | 不带 cid 的老 URL | 与 P1 同源（= 修前行为，正是要修掉的那个） |
  | DAV 目录体积 | 封面 125092 + 两集 524761 / 525002（各 P 各一把 `davsize:<bvid>:<cid>:q64` 键） |
  | yt-dlp `?p=2` | 落盘 `BV1e6eF6yEnn_p2.m4a`（1.15MB），与 `_p1.m4a`（1.09MB）互不覆盖 |
- **结论 / 将来的判据**：
  1. **顶层 `cid` 永远当不得"选中项"**：要哪一 P 只能来自 `pages[]` 的显式条目或用户给的 `?p=N`。
     凡是"识别 → 转换 → 缓存 → 播放"的链路上丢掉 `page`/`cid` 的地方，症状都是"N 条看着都在，实际全指向 P1"。
  2. 分 P 的**身份用 `cid`**（不是序号）：上传者在中间插/删分 P 时序号整体平移，`cid` 不会。
     序号只用于人类可读的 `?p=` 与 yt-dlp 的 `part_id`。
  3. 多分 P 的 `duration` 要用 `pages[].duration`（**视频级 `duration` 是各 P 之和**），标题用 `pages[].part`。
  4. **列表类源不给逐条分 P 信息**，要展开就得逐条打 `view`（500 集 = 500 请求，风控必爆）——
     所以只对 `bv` 源展开。**例外：`watchlater` 的返回体自带 `pages`（2026-09-20 实测）**，
     将来要扩展先从它试点。
- **排查手册增补**：DAV/feed 里"某个视频只有一集"先看它 `videos` 字段是否 > 1；
  多分 P 视频的每个文件都指向 P1 时，查 `_fetch_bv` 是不是又在读顶层 `cid`。

#### 实验 20：列表类源的条目字段名各不相同 —— fav 的发布时间真名是 `pubtime`（2026-09-20）

- **发现方式**：审计"六个源的 item 映射对不对"时，把每个列表接口的**原始返回体键名**打出来对照，
  而不是看代码里的回落链（回落链本身写得很像"已经兜住了"，实际一个都没兜住）。
- **实测键名（登录态，各 1 个请求）**：

  | 源 | 接口 | 条目的字段名 |
  |---|---|---|
  | `up` | `x/space/arc/search` 的 `list.vlist` | `description` / **`created`** / `author` / **`length`** / `pic`（**没有 `pubdate`**） |
  | `fav` | `x/v3/fav/resource/list` 的 `medias` | **`intro`** / **`pubtime`** / **`upper.name`** / `duration` / **`cover`** / `page`(=分P数) / `ctime` / `fav_time` |
  | `watchlater` | `x/v2/history/toview/web` 的 `list` | **`desc`** / `pubdate` / `owner.name` / `duration` / `pic` / **`pages`** / `videos` / `cid` |
  | `season` / `series` | `seasons_archives_list` / `x/series/archives` 的 `archives` | `title` / `pubdate` / `duration` / `pic` / `ctime` / `stat` —— **没有作者、没有简介** |

- **修前状况**：`_fetch_playlist` 一条回落链同时伺候三个源（`description|desc`、`pubdate|created`、
  `author|owner.name`、`pic`），于是 **fav 的每一条都吃空**：`pubdate` = 0 → feed 的 `<pubDate>` 变成
  "生成本刻"（渲染时取 now）、`?num=1` 的编号退化成接口顺序（不是发布时间序）、DAV 里
  `getlastmodified` 为空（`mtime=0` 直接省略该属性）；`author` / `description` 也全空。
  `up` 与 `watchlater` 是**对的**（`created` / `owner.name` 正好命中）。
- **修复**：`pubtime` / `upper.name` 补进回落链；**合集/系列的作者改由 card 接口按源抓一次**
  （条目里上游就不给，`x/web-interface/card?mid=` → `data.card.name`，名字存 30 天缓存，
  同一 UP 的多个合集只抓一次；取不到就留空，不影响取数）。简介按用户决定**留空**（fav 的 `intro` 不用）。
- **副作用（已在版本记录写明）**：fav 的 `pubdate` 一变真，"勾了按发布时间编号"的收藏夹源会在 DAV 里
  **重排一次文件名**（编号=文件名=ABS 认集的身份）→ 判"删旧集+新集"、丢一次进度；缓解办法是先把该源的
  编号取消勾选再刷新（不编号的文件名是纯标题，只换列表顺序）。
- **教训**：**"回落链"不等于"兜住了"**——同一个内部模型被多个上游**不同**的字段名供料时，
  必须逐个源把**真实返回体的键名**打出来核对（这次是 `grep` 代码看不出来的错，只有实测键名才暴露）。

### 2.4 排查手册（将来接口再挂时按序做）

1. **先看错误码**：对照 2.2 速查表。-412/-352 → 大概率概率拦截，隔 45–60s 重试几次再判断；-403 → **先查请求里有没有 `w_rid`**（签名缺失也会报 -403，见实验 18；其次才想 dm_img 参数集、权限、IP）；-799 → 冷却。
2. **分层验证**：先用 `view` 端点（`get_video_info('BV1GJ411x7h7')`）打一下——它风控最松。view 通而 space 不通 → space 专属风控/参数问题；view 也不通 → 设备 Cookie/网络/IP 层问题。
3. **单进程复现**：别只看 server 日志，用独立 python 进程复现（排除 server 缓存/并发干扰）：
   ```bash
   cd biliRelay
   python -X utf8 -c "
   from src import bili_api as api
   api._anon_cookie = None                      # 强制重新暖场
   print('buvid:', bool(api._merge_cookie(''))) # 暖场是否拿到设备 Cookie
   print(api._get_mixin_key())                  # WBI mixin key 能否取到
   r = api.get_up_videos(546195)
   print('ok' if r.get('ok') else r.get('code'), str(r.get('message'))[:60])
   "
   ```
4. **变量隔离**：怀疑某个参数时做对照矩阵（带/不带 × 端点A/B，见实验 6），一次只动一个变量，请求间隔 ≥3s。
5. **对照蓝本**：参数写法对照 Bili23 解析层（GPL 只读）与 bilibili-API-collect；但**先实测再抄**——上游的值本身可能已经过时（实验 5）。
6. **登录态兜底**：匿名持续被拦时，登录 Cookie 的请求风控档位通常更低（fav/watchlater 场景本来就需要登录）。

### 2.5 已知未验证 / 待观察

- 其他 CDN 节点是否同样校验 Referer（backup_url 路线未验证）。
- 登录态下 space 端点的风控档位是否更低（待登录后观察）。
- ~~buvid 设备 Cookie 是否需要持久化~~（**已做**：2026-09-19 补丁 10 落盘 `data/anon_cookie.json`）。
- 「短期登录/普通登录」弹窗的出现条件（似乎与非常用设备判定有关；本机扫码确认时出现）。
- Cookie 实际有效期（普通登录官方口径约 1 个月起，以服务端失效为准；到期表现 = fav/watchlater 静默降级，
  靠 nav 检测发现。**2026-09-19 起有自动续期兜底**（实验 17），续期失败仍走邮件提醒）。

## §3 新增实测

### 3.1 seasons_series_list -400 根因核查（2026-10，PiliPlus 对照）

**背景**：2026-10 实测轮顺带发现该端点带 WBI 签名一律 `-400 请求错误`（匿名+登录态均复现），初判「疑似上游收紧」。

**核查**（对照 PiliPlus 生产请求形状）：裸请求匿名即 `code=0` 正常——无 `w_rid`/`wts`，fresh buvid3/buvid4 cookie + Referer + PC UA（老番茄 mid=546195 返回 6 合集 + 4 系列）；PiliPlus 生产同端点即不签名（`lib/http/member.dart` `seasonSeriesList`）。

**结论**：端点存活；该端点不要求 WBI，多余签名参数触发 `-400`（与 biliRelay 实验 14「匿名可查」记载一致）。

**顺带发现**（与本轮无关，待后续核查）：

- 匿名 `nav` 接口仅在带 buvid cookie + Referer 时返回 `wbi_img` 签名钥（裸请求 `data` 为 null）。
- APP cursor 翻页：响应已无 `data.next`，翻页靠 `aid` 参数（上一页末条 `param`）+ `has_next` 判断；本项目 `fetchUpVideosViaApp` 的 aid/next 双参容错写法兼容现状。
