# bugfix 记录

直接修复的 bug（不走 SDD 流程），按发生顺序编号追加。

## 1. seasons_series_list 带 WBI 签名致 -400

- **现象**：添加订阅页合集/系列列举失败，接口返回 `-400 请求错误`（匿名+登录态均复现）。
- **根因**：`x/polymer/web-space/seasons_series_list` 不要求 WBI 签名，生产代码 `fetchSeasonsList`/`fetchSeriesList` 画蛇添足追加 `w_rid`/`wts`，被服务端参数校验拒绝。核查与结论详见根目录 `BILI_API.md` §3.1（PiliPlus 生产同端点即不签名；裸请求匿名 code=0）。
- **修复**：两函数去掉 `WbiSigner.signParams`，改为 `mid/page_num/page_size` 裸 query 直拼；buvid cookie + Referer + UA 请求头不变（`BiliService.ets`）。
- **验证**：arkts_check 零诊断，`devecocli build` 通过。

## 2. 订阅详情页「N 集」显示已加载数而非源总数

- **现象**：小约翰可汗（UP，投稿 265）详情页页头显示「20 集」——实际是「近期一页」已加载数，非源内总集数。
- **根因**：页头取 `episodeCount`（内存 episodes 数组长度），而订阅刷新契约只拉近期一页（US 契约，`refreshSubscription`），加载量恒小于源总数；各链响应中的总数字段（UP `data.count`/`page.count`、收藏夹 `info.media_count`、合集/系列 `page.total`）一直被丢弃。
- **修复**：`Subscription` 加 `@Trace totalCount`（持久化）；`BiliService` 四类链捕获总数（UP：APP 链 `data.count` 权威覆盖、Web 链 `page.count` 仅缺失兜底，模块级缓存 + getter；FAV：`FolderFetchResult.folderTotal` 读 `data.info.media_count`；SEASON/SERIES：`seasonTotalCache` 存 `page.total`）；`refreshSubscription` 按类型写入 `sub.totalCount`，`persistRefreshedSub` 落盘；`SourcePage` 页头改 `headerCount()`——totalCount>0 优先，回退 episodeCount。
- **验证**：arkts_check + `devecocli build` + 模拟器四类源页头核对（小约翰可汗应显示 265 集）。

## 3. 刷新后 ··· 卡脱落压住返回卡（TitleBar menus 容器布局错乱）

- **现象**：订阅详情页触发刷新后，··· 卡从右上角跳到左上角压住返回卡（布局 dump：menus 内容 Row 从 `[1098,164,1238,304]` 变 `[0,164,140,304]`，其 EffectComponent 仍留原位）。
- **根因**：`.menus()` 自定义内容里 `if (this.refreshing)` 在刷新时销毁/重建菜单锚点（SymbolGlyph ↔ LoadingProgress），TitleBar menus 容器在内容交换后丢失右定位，内容 Row 脱落至 x=0——框架级 menus 容器布局怪癖，非业务代码逻辑错误。
- **修复**：弃用 `.menus()`，··· 卡并入 `sourceTitleBuilder` 自控 Row（与返回卡同范式，不依赖框架 menus 布局）；外层 Row 右边距由预留 menus 区（`TOKEN_ICON_BTN + 2*TOKEN_SPACE_M`）收为 `TOKEN_SPACE_M`（卡右缘 12vp 贴边不变）；垂直对齐由 Row `alignItems(Center)` 天然保证（40vp 卡在 36vp 行内居中溢出，y 轴与原验证位逐像素一致）；`placement: BottomRight` 下拉展开行为保留。
- **验证**：arkts_check 零诊断、`devecocli build` 通过；模拟器触发刷新后复验 ··· 卡保持右上原位、不压返回卡。

## 4. Web 补稠链端点顺序颠倒：数据完整性让位于可用性

- **现象**：`fetchUpVideosViaWeb` 补稠链优先旧版 `x/space/arc/search`，完整数据端点排在失败兜底位。
- **根因**：旧端点登录态实测成功（HTTP 200 + code=0）但 vlist 数据被服务端过滤（补稠合并零新增可证）；`x/space/wbi/arc/search`（PiliPlus 生产同款、网页同源）为完整数据端点，却仅在旧端点失败后才尝试。
- **修复**：`fetchUpVideosViaWeb` 交换为 WBI 优先、旧端点降级兜底（`BiliService.ets`）——WBI 被风控时旧链数据仍可得，韧性不降。
- **现状**：WBI 端点当前被 -403 space 风控拦截（模拟器 3 轮刷新全败，带登录 cookie 仍拦），走旧端点兜底；网页端可过的差异在浏览器级指纹评分，非登录态。
- **验证**：arkts_check 零诊断、`devecocli build` 通过；模拟器部署后日志确认新顺序生效（第 1 轮 WBI → 失败 → 直连兜底成功）。
