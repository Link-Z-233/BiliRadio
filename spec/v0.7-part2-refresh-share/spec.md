# Spec: 回前台静默刷新、新集提醒、首页拖拽边缘滚动与分享导入（v0.7-part2-refresh-share）

**Input**: User reports: ① 「进首页为何不检查更新了」——某 UP 数日未出现新视频，手动进源页刷新才出现；② 修复方向拍板为「回前台触发」——经现有 `AS_HOME_REFRESH_TICK` 全局键驱动 HomePage 既有 @Monitor 补调 silentRefresh，15 分钟全局 CD + 15 分钟单源 TTL + refreshingNow 防重入三层门已有，多触发点安全；③ 新集提醒拍板为「有新集才提醒」——静默刷新完成后全源新集总数（各源 countNew 之和）较刷新前增加才弹一次 toast「发现 N 集新节目」，纯成功/无新集/CD 跳过零提示；④ 目录名 v0.7-part2 不带功能后缀（后续功能可能调整）；⑤ feature.json 不切换——活跃目录保持 v0.7-part1-queue-insert，bugfix.md 继续落该目录。诊断结论（已确证）：静默刷新唯一触发点是 HomePage.aboutToAppear（进程内仅冷启动执行一次），电台应用进程常驻后台数日时永不重跑，首页长期吃旧缓存；手动刷新（SourcePage.refreshSource 无 CD 必然执行）是唯一活口。风控非本轮根因（BILI_NOTES §3.2/§3.4 证真机 APP 签名链可用、Web 链静默降级不阻塞供数）。
⑥ 首页拖拽排序问题并入本轮（用户拍板不走独立 SDD 轮）：把手手动拖拽（US9 FR-026 自绘路径）无边缘自动滚动作废长列表排序——功能缺口需补齐；⑦ 底部拖拽滚动触发区上提拍板为「首页列表底缘永久让位 miniplayer」（用户明确「永久」而非编辑态临时）——列表视口不再延伸至屏底，内建拖拽（onMove 系统拖拽）触发区随视口底缘上提到胶囊上方（「内建触发区跟随视口底缘」为实测推断非文档承诺，真机验证，不成立回退重议），内建拖拽保留不禁用，FR-015「视口延伸至屏底、内容从胶囊下穿过」设计废止。
⑧ 分享导入（tasks Gate 新增，回溯重走 Phase 1~3）：支持系统分享到应用实现导入——分享到 BiliRadio 后抽到 B 站链接即打开加号面板、链接灌入输入框并自动执行一次既有检索链；抽不到 B 站链接 toast 提示不支持、不弹面板（用户拍板「直接提示不支持」）；仅文本类分享注册（图片/文件不接），应用内处理方案（非 ShareExtensionAbility 分享详情页）；PiliPlus 参考库已更新（bb2d86ca2→c7ff9683c，本轮无鸿蒙侧旁证需求，Share Kit 文档为准）。
⑨ 消闪拍板（实施后追加，用户拍板「分享在视频在不出错时不开面板」）：分享视频链接（bv/av，含短链解析后）成功入队直接 toast 反馈、不开面板——原「一律打开加号面板」通用路径对视频类产生「闪一下」（面板自动检索入队完成后 onDismiss 关面板，弹出动画未完成即被关）；入队失败/归一化异常/短链解析失败回退打开加号面板走既有链（面板内反馈+可手动重试）；订阅类分享照旧开面板。
⑩ 源页两小需求（验证后追加，直接指令式）：订阅源详情页（SourcePage）列表增下拉刷新（复用既有 refreshSource 链，多选模式禁用）；「更多」菜单「取消订阅」项文字改红色警示（danger_red 既有资源），「刷新」项默认色。
⑪ 下拉刷新真机反馈修正（验证后追加，用户提议方向「自定义刷新区域内容 + 下拉提示」）：真机两问题——默认下拉指示器冻结不旋转、多选模式下拉仍显示加载图标（pullToRefresh(false) 只挡发起刷新不挡下拉手势与指示器视觉，refresh.d.ts 证实）；修正为 refreshingContent 自定义提示区（自转 LoadingProgress + 提示文案）承载；多选禁用先试 pullDownRatio(0)（0=下拉不跟手，官方 FAQ 唯一记载彻底禁用法）——真机复测发现顶部跟手回弹被一并焊死，⑫ 推翻。
⑫ 提示状态机与多选回弹拍板（⑪ 实施后追加）：提示文案做全状态机「下拉刷新→释放刷新→刷新中」（onStateChange 驱动，用户拍板「全状态机」）；多选顶部回弹恢复（真机反馈 pullDownRatio(0) 连跟手回弹一起焊死，用户拍板「恢复回弹藏图标」）——多选禁用退回 pullToRefresh（只挡发起刷新不挡手势视觉，满足「多选不触发刷新」原诉求）+ 刷区内容多选隐藏（params.visible + enterSelectMode/exitSelectMode 联动 update），跟手回弹保留、图标文案不出现，代价为多选下拉时列表上方露出页面底色空白。
⑬ 刷新提示区静息可见 bug 修复（⑫ 实施后真机反馈「点开详情就有一个加载动画」）：minHeight 使 refreshingContent 自定义区自适应高度静息下限 32、visible 默认 true，详情页挂载即现提示区加载动画；修复为可见性刷新态门控——params.visible 默认 false（静息/挂载不显），onStateChange 计算（Drag/OverDrag/Refresh 且非多选 → 可见，Inactive/Done → 隐藏），builder 以 .visibility(Visible/None) 属性绑定承载（弃 if 结构渲染，规避 ComponentContent update 结构 diff 风险），exitSelectMode 按 this.refreshing 恢复（刷新中退出多选提示区回显，静息退出不误显）。
⑭ 静默刷新 CD 分层拍板（US1 再优化）：四触发点分 CD——冷启动（aboutToAppear）15 分钟；回前台（Index.onPageShow）/源页退出回首页（SourcePage.onHidden）/设置层关闭回首页（SettingsPage.aboutToDisappear，触发点由「设置页导入完成」迁移至此）共用 1 小时；均对同一「上次刷新」时间戳判定，1 小时内触发仅重算列表零网络请求，防重入与单源 15 分钟 TTL 不变。触发点 4 迁移依据：设置页导入的新订阅数据由导入链自行拉取（refreshAll(newSubs) 无 CD），「导入后须不限时刷新拿数据」的担忧不成立（1 小时 CD 零伤害），导入链仅保留拉取完成后令首页重算的 bump。回前台触发（2）保留：应用后台数日进程不死时回首页的唯一自动刷新机会，1 小时 CD 消除频繁触发顾虑；语义维持「回前台」（当时拍板记录，非首页界面照常在底层刷新、回首页即见），不改严格「回首页才触发」（需感知全部遮挡层状态，耦合面大，可观察收益仅 toast 位置）。

**Output**: 回前台触发静默刷新（复用 homeRefreshTick 键链路，CD 门限频）、静默刷新新集 toast 提醒（仅正向增量弹）、失败 toast 行为不变、既有触发方行为兼容；首页列表底缘永久让位 miniplayer、内建拖拽底部触发区随视口上提、把手拖拽补边缘自动滚动（滚动位移并入换位基准）；系统分享到应用导入（视频链接直达入队、成功不开面板，订阅链接灌入加号输入框+自动检索，非 B 站内容 toast 拒收）；源页列表下拉刷新与「取消订阅」红色警示。

**Context**: master `e668298`（v0.7-part1-queue-insert 已完结提交）；part2 首批为规划轮产物，后续并入需求随三工件重出统一承载，实施批次建议见 tasks。现状关键事实：homeRefreshTick 现有触发方为源页退出（SourcePage.onHidden）与设置页导入完成（SettingsPage），仅驱动 rebuild 不刷数据；silentRefresh 已有 CD 门（HOME_SILENT_REFRESH_CD_MS=15min）+ 单源 TTL（Subscription.CACHE_TTL_MS=15min）+ refreshingNow 防重入；失败 toast（「N 个订阅刷新失败」）已存在且 CD 时间戳在收尾无条件写入；rebuild 逐行算 countNew，全源新集总数可由其聚合。首页拖拽现状：HomePage 单 List 恒绑 onMove（FR-023 行节点恒存续前提），内建拖拽触发区在 List 视口底缘（现延伸至屏底，`contentEndOffset(MINI_PLAYER_CLEARANCE + navBarHeight)` 让最后一条露出胶囊上方）；把手拖拽为 PanGesture 自绘（累积偏移跨 TOKEN_DRAG_SWAP_DISTANCE 换位 + provider.swapNotify），无任何滚动接入；SourcePage 已有 EdgeAutoScroller（SelectLogic，setInterval 时钟驱动 scrollBy，含到顶/到底停滚）与边缘带常量（SELECT_SWEEP_EDGE_ZONE）可复用。分享现状：本应用未注册任何分享/链接接收（module.json5 skills 仅 home 入口），EntryAbility 无 onCreate/onNewWant 的 want 处理；接收系统分享须 module.json5 注册 `ohos.want.action.sendData`（应用内处理方案）并在 onCreate/onNewWant 经 systemShare.getSharedData 取数据（onForeground 取不到，官方 FAQ 证实）；加号面板（AddSubscriptionSheet）既有 mainInput 输入态 + handleMainInput 检索链（extractBiliUrl 清洗→短链 resolveShortLink 解析→recognizeInput 识别→dispatchRecognized 分发：bv/av 进队列播放、up/fav/season/series/lists 走订阅、ep 提示暂不支持），分享导入即自动化该手动链路，零新识别逻辑。

## User Stories

### US1 回前台触发静默刷新 (Priority: P1) 🎯 MVP

应用从后台回前台时，首页静默刷新链路重新获得执行机会：回前台 → bump `homeRefreshTick` → HomePage 重算列表并尝试静默刷新。CD 分层（⑭）：冷启动 15 分钟、回前台/源页退出回首页/设置层关闭回首页共用 1 小时（同一时间戳判定；1 小时内的触发仅重算列表、零网络请求），CD 过期后的首次触发真正发起刷新。进程常驻后台数日的场景下，用户每次回到应用都能在 1 小时 CD 语义内拿到最新数据，不再依赖冷启动或手动进源页刷新。

**Why this priority**: 首批根因修复——静默刷新只挂冷启动导致首页数据滞留数日。

**Independent Test**: 应用进程存活、距上次静默刷新超 1 小时时从后台回前台（不冷启动），首页数据自动更新（NEW 角标/最新一集标题变化）；不足 1 小时的回前台零网络请求；冷启动保持 15 分钟 CD。

1. **Given** 应用进程存活且距上次静默刷新 ≥1 小时, **When** 应用从后台回前台, **Then** 触发一次静默刷新尝试（重算列表 + 过 CD 门发起刷新，数据更新后首页角标/标题随之变化）
2. **Given** 距上次静默刷新 <1 小时, **When** 回前台, **Then** 零网络请求、零提示（CD 门挡住）
3. **Given** 静默刷新进行中（refreshingNow=true）, **When** 再次回前台或触发 tick, **Then** 不产生并发刷新（防重入）
4. **Given** 回前台时停留在源页/播放浮层/设置层等非首页界面, **When** 触发, **Then** 刷新照常进行（首页恒挂载，数据就绪后回首页即见）
5. **Given** 源页退出/设置层关闭等 tick 触发方, **When** 触发, **Then** 行为兼容——重算照旧，另获得 1 小时 CD 门内的静默刷新尝试
6. **Given** 冷启动（进程被杀后重开）且距上次刷新 ≥15 分钟, **When** 冷启动, **Then** 发起静默刷新（冷启动 CD 15 分钟独立于 1 小时层）

### US2 静默刷新新集 toast 提醒 (Priority: P2)

静默刷新完成且全源新集总数较刷新前增加 N（N>0）时，弹一次 toast「发现 N 集新节目」（文案见 FR-004，N 为增量数）；纯成功无新集、CD 跳过、刷新失败不弹此 toast（失败沿用既有失败 toast）。解决「打开应用停留在播放页/其他界面时，错过首页 NEW 角标」的信息触达缺口。

**Why this priority**: 角标是被动的可见提醒，需用户主动看首页；toast 补主动告知，且仅在正向增量时弹，避免每次刷新成功都打扰。

**Independent Test**: 缓存无新集状态下使某源出现新视频，CD 过期后触发静默刷新，完成后弹「发现 N 集新节目」；随后再触发一次（无新集）不弹。

1. **Given** 刷新前全源新集总数 X, **When** 静默刷新完成后总数增至 X+N（N>0）, **Then** 弹一次「发现 N 集新节目」
2. **Given** 刷新前后总数不变, **When** 刷新完成, **Then** 无新集 toast（首页角标照常更新）
3. **Given** 刷新后总数不增（含下降：近窗滚动覆盖缓存、标记已看书变化）, **When** 刷新完成, **Then** 不弹（仅认正向增量）
4. **Given** 部分源刷新失败且其他源发现新集, **When** 刷新完成, **Then** 新集 toast 与失败 toast 按既有各自语义展示，互不吞并
5. **Given** CD 跳过（未实际刷新）, **When** 回前台, **Then** 零提示

### US3 首页列表底缘永久让位与内建拖拽触发区上提 (Priority: P2)

首页列表可视底缘从屏幕底永久收到 MiniPlayer 上方（正常态与编辑态一致，非编辑态临时切换）：滚动时内容不再从胶囊下方穿过（FR-015 下穿过设计废止），滚到底最后一条完整露出在胶囊上方（既有语义保留）。视口底缘上移后，内建拖拽（编辑态长按卡片走 onMove 的系统拖拽）的底部自动滚动触发区随视口底缘上提到胶囊上方——拖到胶囊上方即可触发滚动，不再需要拖到 miniplayer 之下。

**Why this priority**: 直接解决用户痛点（内建拖拽触发区被 miniplayer 遮挡，需拖到胶囊下才滚动）；让位是触发区上提的前提，独立可验。

**Independent Test**: 正常态滚动列表，内容不经胶囊下方穿过、最后一条完整露出在胶囊上方；编辑态内建拖拽卡片至胶囊上方边缘，列表自动滚动。

1. **Given** 正常态, **When** 列表滚动, **Then** 内容不经胶囊下方穿过，滚到底最后一条完整露出在胶囊上方
2. **Given** 编辑态内建拖拽进行中, **When** 卡片拖至胶囊上方底部触发带, **Then** 列表自动向下滚动（真机验证：系统触发区跟随视口底缘）
3. **Given** 列表已滚到底, **When** 继续内建拖拽至底部触发带, **Then** 不再滚动（尽头停止）
4. **Given** 内建拖拽至顶部触发带, **When** 继续上拖, **Then** 列表向上自动滚动，到顶停止

### US4 把手拖拽边缘自动滚动 (Priority: P2)

编辑态把手手动拖拽（US9 FR-026 路径）补齐边缘自动滚动：拖行至列表顶部/底部触发带时列表自动滚动，滚动位移并入换位基准——被拖行与相邻行的相对位置随滚动持续换位，不松手即可完成跨视口长距离排序；手指离开触发带停滚，列表到顶/到底停滚，松手落位落盘链路不变。体验与内建拖拽对齐（「和内建同步」）。

**Why this priority**: 把手拖拽当前只能视口内换位（US9 FR-026 功能缺口），长列表排序作废；与 US3 共同恢复排序可用性。

**Independent Test**: 编辑态把手拖一张卡片至底部触发带不放，列表持续滚动且被拖行持续与邻行换位，跨过一屏后松手，顺序已变且重启后顺序保持（落盘）。

1. **Given** 把手拖拽进行中, **When** 拖至底部触发带并按住, **Then** 列表自动向下滚动，滚动期间每跨换位阈值与相邻行交换
2. **Given** 边缘滚动进行中, **When** 手指移回列表中部, **Then** 停止滚动（已滚到的位置保持）
3. **Given** 列表滚到底, **When** 仍按住底部触发带, **Then** 停止滚动
4. **Given** 把手拖拽至顶部触发带并按住, **Then** 列表向上自动滚动，到顶停止
5. **Given** 边缘滚动+换位后松手, **When** 落位, **Then** sortOrder 归一化落盘、行落槽动画与既有一致

### US5 系统分享到应用导入 (Priority: P2)

从其他应用（浏览器/B 站 App/聊天工具）经系统分享面板把内容分享到 BiliRadio：分享文本中抽到 B 站链接（含短链）时按识别结果分流——视频链接（bv/av，含短链解析后）成功入队直接 toast 反馈、不开面板（消闪，⑨）；入队失败/归一化异常/短链解析失败回退打开加号面板、链接灌入输入框并自动执行一次既有检索链（面板内反馈+可重试）；UP 主/合集/收藏夹等订阅链接打开加号面板、灌入+自动检索——行为与手动「加号→粘贴→检索」语义一致；抽不到 B 站链接时 toast 提示不支持、不弹面板。

**Why this priority**: 分享是移动端导入链接的最短路径，现状须手动复制→打开应用→加号→粘贴；复用既有识别分发链，零新识别逻辑。

**Independent Test**: 从浏览器分享一个 B 站视频链接到 BiliRadio，应用打开且视频直接入队播放（toast 反馈、不弹面板）；再分享一个 UP 主链接，加号面板弹出、链接已填入、检索已自动执行；再分享一段纯文本，不弹面板、toast 提示不支持。

1. **Given** 应用未运行, **When** 分享含 B 站视频链接的文本到 BiliRadio, **Then** 冷启动打开应用、视频直接入队播放（toast 反馈，不开面板）（onCreate 链）
2. **Given** 应用已启动（前台或后台）, **When** 分享含 B 站视频链接的文本到 BiliRadio, **Then** 视频直接入队播放（toast 反馈，不开面板）（onNewWant 链）
3. **Given** 分享纯文本或其他网站链接（抽不到 B 站链接）, **When** 分享到 BiliRadio, **Then** 不弹面板，toast 提示不支持
4. **Given** 加号面板已开, **When** 再次分享另一 B 站链接, **Then** 视频链接直接入队（面板不动）、订阅链接更新输入并重新检索
5. **Given** 分享短链（b23.tv 等）, **When** 检索, **Then** 视频短链解析成功直接入队（不开面板）、订阅短链解析后走订阅链、解析失败回退打开加号面板走既有链
6. **Given** 播放浮层/设置层/编辑态等界面状态下分享进入, **When** 面板弹出, **Then** 按既有层序叠加，返回/关闭后原界面无损
7. **Given** 分享视频链接但入队失败（FAILED/网络异常/归一化失败）, **When** 检索, **Then** 回退打开加号面板走既有链（面板内反馈+可手动重试）

### US6 订阅源详情页下拉刷新与「取消订阅」红色警示 (Priority: P2)

订阅源详情页（SourcePage）节目列表支持下拉刷新：列表顶部下拉出现自定义刷新提示区（自转 LoadingProgress + 状态机文案「下拉刷新」→「释放刷新」→「刷新中」，onStateChange 驱动；静息态不显——可见性经刷新态门控），松手触发既有 refreshSource 链路（完成 toast「已更新」、回顶部），与右上「更多」菜单内「刷新」行为同源；多选择模式（selectMode）下拉不触发刷新且刷区内容隐藏（顶部跟手回弹保留），避免与横扫多选手势冲突。顶部「更多」（···）菜单改自定义菜单承载：「取消订阅」项文字使用红色警示色（danger_red，明暗双态），「刷新」项保持系统默认色——破坏性操作红色警示降低误触风险，菜单行为与原数组菜单一致。

**Why this priority**: 验证后追加的直接指令式小需求（⑩，用户指定）；下拉刷新补齐源页最自然的刷新手势，红色警示为破坏性操作视觉规范。

**Independent Test**: 进入订阅源详情页，顶部无任何加载动画（提示区静息不显）；列表顶部下拉出现自定义提示区（旋转 LoadingProgress，文案随「下拉刷新」→「释放刷新」→「刷新中」状态机切换）、松手触发刷新、完成后 toast「已更新」且回到顶部；多选模式下拉有跟手回弹但无图标文案、不触发刷新；点开「···」菜单，「取消订阅」为红色文字、「刷新」为默认色，两项点击行为与改动前一致。

1. **Given** 列表在顶部, **When** 下拉, **Then** 出现自定义刷新提示区（旋转 LoadingProgress，文案「下拉刷新」，过阈值切「释放刷新」），松手触发既有 refreshSource 链（文案切「刷新中」，完成 toast「已更新」+ 回顶部 + 文案回落「下拉刷新」）
2. **Given** 刷新进行中, **When** 再次下拉或菜单点「刷新」, **Then** 不产生并发刷新（组件 refreshing 态收敛；刷新中「···」图标被 LoadingProgress 替换，菜单不可再触发）
3. **Given** 多选择模式（selectMode）, **When** 列表下拉, **Then** 列表跟手回弹但刷区无图标无文案、不触发刷新（pullToRefresh 挡发起 + 刷区内容隐藏）
4. **Given** 点开「···」菜单, **Then** 「刷新」默认色、「取消订阅」红色（danger_red 明暗双态）
5. **Given** 菜单点「刷新」/「取消订阅」, **Then** 行为与原数组菜单一致（refreshSource / 既有 unsubscribe 确认链）

## Functional Requirements

- **FR-001**: 应用回前台 MUST 触发首页重算并尝试静默刷新——经现有 `AS_HOME_REFRESH_TICK` 全局键驱动 HomePage 既有 @Monitor，Monitor 内补调 silentRefresh；新增触发点为 Index 页面显示生命周期（onPageShow）
- **FR-002**: 尝试静默刷新 MUST 复用既有三层门，CD 分层（⑭）：冷启动（aboutToAppear 直调）15 分钟（`HOME_COLD_START_REFRESH_CD_MS`，原 `HOME_SILENT_REFRESH_CD_MS` 更名）、回前台/源页退出/设置层关闭（tick 链）共用 1 小时（`HOME_FOREGROUND_REFRESH_CD_MS`），均对同一「上次刷新」时间戳（`KEY_LAST_SILENT_REFRESH_AT`）判定；15 分钟单源 TTL 与 refreshingNow 防重入不变；CD 内触发零网络请求零提示；冷启动 aboutToAppear 与新触发点并存时 MUST 收敛为单次实际刷新
- **FR-003**: 既有 tick 触发方 MUST 行为兼容——源页退出（SourcePage.onHidden）重算照旧；设置层关闭（SettingsPage.aboutToDisappear，⑭ 由「设置页导入完成」迁移）替代原导入完成触发——导入链新订阅数据自拉（refreshAll(newSubs) 无 CD）不受影响，仅保留拉取完成后令首页重算的 bump；两者另获得 1 小时 CD 门内的静默刷新尝试，无重复刷新
- **FR-004**: 静默刷新完成后，全源新集总数（各源 countNew 之和）较刷新前增加 N（N>0）时 MUST 弹一次 toast，文案为 Constants 新增 `TOAST_NEW_EPISODES_FOUND`（「发现 N 集新节目」，N 占位替换）；增量 ≤0、CD 跳过、未实际刷新 MUST 不弹
- **FR-005**: 刷新失败 toast（「N 个订阅刷新失败」）行为 MUST 不变；与新集 toast 并存时两者均发出（展示层按系统 toast 既有规则），互不吞并
- **FR-006**: 新 toast 文案 MUST 落 Constants（TOAST_* 惯例，零裸文案）；无新增魔法数字（增量动态计算）
- **FR-007**: 首页列表渲染、编辑态（拖拽排序/挂起重算补跑）、角标计算、源页手动刷新路径 MUST 零回归
- **FR-008**: 首页列表可视底缘 MUST 永久让位至 MiniPlayer 上方（正常态与编辑态一致）；滚动内容不再从胶囊下方穿过；滚到底最后一条完整露出在胶囊上方的既有语义 MUST 保留；FR-015「视口延伸至屏底、内容从胶囊下穿过」设计废止
- **FR-009**: 列表底缘让位后，内建拖拽的底部自动滚动触发区 MUST 位于 MiniPlayer 上方（系统行为跟随视口底缘为实测推断，实施后 MUST 真机验证；不成立时 MUST 回退重议而非强行绕过）
- **FR-010**: 把手手动拖拽 MUST 支持边缘自动滚动：拖入顶部/底部触发带启动滚动、移出停止、列表到顶/到底停止；触发带自列表视口顶/底起算，宽度沿用既有边缘带常量（Constants 单一定义）
- **FR-011**: 边缘滚动期间滚动位移 MUST 并入把手换位判定基准（被拖行与邻行相对位置变化持续参与换位）；换位动画、sortOrder 归一化落盘、松手落槽、双路径互斥闸（FR-026）MUST 与既有行为一致
- **FR-012**: 既有链路零回归：非编辑态落子拒收、置顶飞行、编辑态进出动画、List 恒绑 onMove 行节点恒存续前提（FR-023）、正常态滚动与回弹、MiniPlayer 既有布局与其他页面零影响
- **FR-013**: module.json5 MUST 为 EntryAbility 注册文本类分享接收能力（skills 增 `ohos.want.action.sendData`），应用出现在系统分享面板；图片/文件类分享不接
- **FR-014**: EntryAbility 冷启动（onCreate）与热启动（onNewWant）MUST 经 systemShare.getSharedData(want) 取分享文本并经全局键传至 UI 层；分享数据 MUST 在 UI 就绪后消费（冷启动早于页面挂载的写入不得丢失）
- **FR-015**: 分享文本经既有链接抽取逻辑抽到 B 站链接（含短链）时按识别结果分流：视频链接（bv/av，含短链解析后）成功入队 MUST 直接 toast 反馈、不开面板（APPENDED/STARTED/DUPLICATE 均视为成功，⑨ 消闪拍板）；入队失败/归一化异常/短链解析失败 MUST 回退打开加号面板、链接灌入 mainInput、自动触发一次既有 handleMainInput 检索链（面板内反馈+可重试）；订阅类链接（up/fav/season/series/lists）MUST 打开加号面板、灌入+自动检索；识别分发行为 MUST 与手动输入完全一致
- **FR-016**: 抽不到 B 站链接 MUST 不弹面板，toast 提示不支持（文案落 Constants TOAST_* 惯例）；加号面板已开时再次分享 MUST 按同语义分流（视频入队不动面板、订阅更新输入重新检索）
- **FR-017**: 分享导入 MUST 不破坏既有层序与返回链（面板按既有 z 序叠加，BackHandler 链路零改动）；播放、编辑态、浮层等既有界面状态零回归
- **FR-018**: SourcePage 节目列表 MUST 支持下拉刷新——Refresh 组件包裹既有 List（refreshing `!!` 双向绑定），onRefreshing 触发既有 refreshSource 链路（toast「已更新」/回顶部/失败复位全复用）；刷新提示区 MUST 经 refreshingContent 自定义承载（模块级 RefreshHintParams（text/visible）+ @Builder + wrapBuilder + ComponentContent，自转 LoadingProgress + text_secondary 色，constraintSize minHeight 防高度塌缩——refresh.d.ts 证实自定义区高度随下拉距离自适应、无最小高约束会塌缩；builder 形态弃用：刷新中销毁重建自定义区致动画中断，官方 FAQ 证实）；提示文案 MUST 全状态机切换（⑫ 拍板）——onStateChange：OverDrag「释放刷新」/ Refresh「刷新中」/ 其余「下拉刷新」（REFRESH_HINT_* 三 token，update() 驱动重渲染，下拉与菜单两入口同态）；提示区可见性 MUST 刷新态门控（⑬）——params.visible 默认 false（静息/挂载不显——minHeight 使自适应高度静息下限 32，不门控则详情页打开即现加载动画，真机证实），onStateChange 计算（Drag/OverDrag/Refresh 且非多选 → 可见，Inactive/Done → 隐藏），builder 以 .visibility(Visible/None) 属性绑定承载（弃 if 结构渲染，规避 ComponentContent update 结构 diff 风险）；refreshSource 既有 refreshing 防重入守卫 MUST 移除（双向绑定下组件先行置 refreshing=true，守卫会使下拉刷新永不执行），防重入由组件 refreshing 态与刷新中「···→LoadingProgress」图标替换承担
- **FR-019**: selectMode 多选择模式 MUST 禁触发下拉刷新且刷新图标文案不出现（⑫ 拍板）——`.pullToRefresh(!selectMode)` 只挡发起刷新（满足「多选不触发刷新」原诉求）+ 刷区内容经 onStateChange 可见性门控 !selectMode 条件自动隐藏（⑬）与 enterSelectMode（置 false）/exitSelectMode（按 refreshing 恢复）联动（顶部跟手回弹保留；pullDownRatio(0) 弃用——彻底禁用连跟手回弹一起焊死，真机反馈推翻）；「更多」菜单 MUST 改自定义 Menu/MenuItem builder 承载（bindMenu builder 形态，placement BottomRight 保留），「取消订阅」项文字 MUST 用 `$r('app.color.danger_red')`（明暗双态既有资源，零新增），「刷新」项保持默认色；菜单文案 MUST 落 Constants（MENU_LABEL_* 惯例）

## Success Criteria

- **SC-001**: US1 五场景全部通过（CD 外触发/CD 内静默/防重入/非首页界面触发/既有触发方兼容）
- **SC-002**: US2 五场景全部通过（增量弹/无增量不弹/非正向不弹/失败 toast 并存/CD 零提示）
- **SC-003**: 冷启动静默刷新、手动源页刷新、首页编辑态、角标与列表渲染零回归
- **SC-004**: US3 四场景全部通过（含真机验证内建触发区随视口上提）
- **SC-005**: US4 五场景全部通过（边缘滚起/移出停/尽头停/顶带上滚/松手落盘一致）
- **SC-006**: US5 七场景全部通过（冷启动链/热启动链/非 B 站拒收/面板已开分流/短链分流/层序无损/失败回退）
- **SC-007**: 构建通过（arkts_check + devecocli build）
- **SC-008**: US6 五场景全部通过（下拉刷新/防重入/selectMode 禁用/红色警示/菜单行为一致）

## Edge Cases & Design Considerations

- onPageShow 冷启动时也触发一次，而 aboutToAppear 已起静默刷新：两次尝试被 refreshingNow/CD 门收敛为单次实际刷新，属预期空转，不视为缺陷
- onPageShow 为页面级生命周期，Navigation 推入源页不触发；源页返回的 tick 由 SourcePage.onHidden 既有链路发出，两链路并存
- 新集总数差值为全源聚合口径：同一刷新窗内「单源角标被清（进源页更新 lastSeenAt）」与「另一源新增」抵消时可能漏弹（概率低，播客语义可接受）；编辑态挂起的重算会使差值退化（不弹），可接受
- 总数下降场景（近窗滚动覆盖缓存、标记已看完）不弹不补偿，只认正向增量
- CD 分层（⑭）：冷启动 15 分钟 / 回前台与回首页类（回前台/源页退出/设置层关闭）1 小时，共用同一时间戳——任一次刷新完成后各层重新计时；冷启动时 onPageShow 的 1 小时门不构成额外限制（aboutToAppear 先行、15 分钟门更松）；「收尾无条件写 CD 时间戳」既有行为不动（全败也起算 CD——已向用户披露，未选修复）；单源 TTL 15 分钟不动
- feature.json 不切换：活跃目录保持 spec/v0.7-part1-queue-insert（bugfix.md 落点不变）；本目录仅存规划三工件
- 「内建拖拽触发区跟随视口底缘」由用户观察现状反推（触发区在屏底=现视口底缘），非文档明示；真机验证不成立时回退方案（如编辑态临时隐藏 miniplayer）须报用户重新拍板，不静默绕过
- 永久让位后底部弹簧过冲回弹发生在胶囊上方而非屏底（视觉变化随设计变更接受）；miniplayer 下方导航条区域背景由页面底色承接
- 既有 `contentEndOffset` 用途（视口延伸至屏底前提下的内容裁剪边界）随视口收短失去必要性，删除或保留 navBarHeight 部分由 plan 定
- 空列表态 emptyView 居中基准随视口高度变化，实施时确认观感
- 把手边缘滚动与既有拖拽态（dragOffsetY/dragBaseline/dragFromIndex）叠加：滚动位移并入基准的方式须保证 settleDrag 落槽语义不变（松手时被拖行落回当前槽位）
- 系统分享面板按内容类型匹配应用（无法按「是否 B 站链接」预过滤）：任意文本分享面板均会出现本应用，非 B 站内容由应用内 toast 拒收层兜底（FR-016）
- 分享视频「闪一下」根因：面板 aboutToAppear 灌入+自动检索 → addSingleVideo 完成后 onDismiss() 关面板，弹出动画未完成即被关；消闪以视频短路路由规避（⑨），失败分支保留面板反馈与重试能力
- refreshSource 守卫移除后的防重入面：下拉（组件 refreshing 态不重触发）与菜单（刷新中「···」图标替换为 LoadingProgress，入口不可达）两入口均无法并发；源页退出 tick 不经 refreshSource，零影响
- 下拉自定义提示区（LoadingProgress+文案）与右上 LoadingProgress 刷新中同时可见（同一 refreshing 态驱动），属预期双指示
- 多选禁用三段演进：pullToRefresh(false)（图标仍出现，⑪ 前形态）→ pullDownRatio(0)（图标消失但顶部跟手回弹一并焊死，真机反馈推翻）→ 终态 pullToRefresh 挡发起 + 刷区内容隐藏（回弹保留、图标不出现）；多选下拉时列表上方露出页面底色空白（刷区无内容），属接受代价
- 默认下拉指示器真机冻结（不旋转）是换 refreshingContent 自定义提示区的动因（⑪）；提示文案全状态机（下拉刷新/释放刷新/刷新中）为用户拍板（⑫），onStateChange + params.update 承载
- refreshingContent 自定义区 minHeight 使自适应高度静息下限 32：不作可见性门控则详情页挂载即现提示区加载动画（⑬ 真机反馈），故 params.visible 默认 false + onStateChange 刷新态门控（Drag/OverDrag/Refresh 且非多选显、Inactive/Done 隐）；提示区显隐用 .visibility(Visible/None) 属性绑定而非 if 结构渲染（ComponentContent update 的结构 diff 行为无文档保证）；Done 后 Inactive 是否必至无文档保证，刷新完成即隐藏
- bindMenu 数组形态（MenuElement）无文字色参数，「取消订阅」着色必须走自定义 Menu/MenuItem builder（menu_item.d.ts contentFontColor 核验）
- 分享数据在 onForeground 取不到（官方 FAQ 证实），仅 onCreate/onNewWant 消费；冷启动时分享写入早于 UI 挂载，经全局键消费模式（挂载时读当前值+监听后续变化）保证不丢
- 编辑态拖拽进行中分享进入：面板叠加弹出，关闭面板回编辑态原样（拖拽态不中断）；属可接受边界
