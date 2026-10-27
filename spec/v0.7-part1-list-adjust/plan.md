# Plan: 队列插入位置控制（v0.7-part1）

**Input**: spec.md (this directory)

**Tech Stack**: 既有单模块 ArkTS/ArkUI 工程（API 26），改动落在既有 7 源文件 + 1 配置文件（PlayerController/QueueSheet/HistorySheet/SourcePage/SettingsPage/HomePage/Constants + app.json5），零新增文件、零新增依赖。

**Architecture Impact**: 无结构变化——PlayerController 加一可选参与一批量移动方法、QueueSheet 多选行加两图标按钮/飞越动画/退多选同时化/toast/长按气泡且头部按钮互换、HistorySheet 多选行计数「已选N条」/长按气泡、SourcePage 底栏三按钮化（位序互换+双 accent 主按钮+中描边）、SettingsPage 加一行一 sheet、HomePage 置顶飞越动画、Constants 加一键一字号令牌。docs/architecture.md 无需同步（无文件增删、无边界变化）；BILI_NOTES 无 API 变化不补录。

**Storage**: 既有 Preferences 经 `AppStore.getNumber/putNumber`（`KEY_SINGLE_INSERT_NEXT`，1=下一首播放 0=队列末播放，缺省 0=现状无迁移）

## Decisions

- **D1 核心插入 API：`loadPlaylistAndPlay` 加 `insertAfterCurrent` 可选参（默认 false）**
  - **Decision**: 签名扩为 `loadPlaylistAndPlay(items, startIndex, insertAfterCurrent = false)`。空队列分支不变（照旧起播）；非空分支去重逻辑不变，追加点分支：`insertAfterCurrent && currentIndex >= 0` 时经 `getQueueEntryGroups` 定位当前播放条目游程（分P 组整组口径），`splice` 插到该游程末之后，否则维持 `push` 追加队尾。插入点恒在 `currentIndex` 之后，`currentIndex` 与播放状态零改动；持久化/广播/返回值语义照旧（APPENDED/DUPLICATE）。既有 4 处调用（源页 enqueueSelected/enqueueAndToast、addSingleVideo 两处）不传新参即维持现状，零改动。
  - **Alternatives considered**: 独立 `insertItemsAfterCurrent` 方法（去重/起播/持久化逻辑整段复制，弃）；通用 `insertAt` 位置参（对布尔语义调用方过曝，弃）。

- **D2 队列条目批量移动 API：`PlayerController.moveFlatItems(indices: Set<number>, toEnd: boolean): number`**
  - **Decision**: 入参为扁平下标集（QueueSheet 由 `entries` + `selectedKeys` 就地收集：单条目=起始下标、组条目=`startIndex .. startIndex+videos.length-1` 全区间）。Controller 侧：越界下标丢弃（与 entries 失步防御）；当前播放条目游程内下标剔除（FR-001，游程识别复用 `getQueueEntryGroups` 单一来源）；movers 与 kept 各自保序重组——`toEnd` → `[kept][movers]`，否则（下一首播放）→ `[prefix(≤当前游程末, kept)][movers][suffix(kept)]`。`currentIndex` 以当前条目复合键在重组后线性重定位（非下标换算）；`playlistVersion++`、`savePlaylistFile`、`statusMsg`、`emitUi`；不动播放器（不打断）。返回实际移动条目数（全被剔除时返回 0，调用方静默退多选）。随机模式的 `shuffleHistory/forwardHistory` 为复合键存储，键不随重组失效，零处理。
  - **Alternatives considered**: 条目键（`g:/s:`）作参数（控制器需复制 UI 端键消歧逻辑，弃）；移动后 `playIndex` 重播当前（打断播放，违背 FR-002，弃）；二维区间数组（等价更繁，弃）。

- **D3 QueueSheet 多选行改造：图标形态 + 用户位序 + 「已选N条」计数 + 移动 toast（Phase 2 审查用户决策 + 再优化批）**
  - **Decision**: 多选操作行扩为：全选（纯图标玻璃按钮，现状不动）+ 独立计数（全选按钮**右侧、按钮外**，再优化批格式升级——Text+Span 组合「已选N条」：N 色本页 accentColor、其余字 `text_primary`、字号 `TOKEN_FONT_17`（同「播放队列」标题字号 17）、间距 `TOKEN_SPACE_XS`，随勾选实时变化、0 也显示「已选0条」）· Blank · 移除（纯 trash 图标，去内嵌计数，确认链路不变）·「移到最后」`sys.symbol.arrow_down_to_line` ·「下一首播放」`sys.symbol.forward_end_fill` · 退出（`chevron_left` 右缘位置不动）。从外（右缘）向内依次：退出 → 下一首播放 → 移到最后 → 移除（用户位序决策）；两新图标均已在本机 sysResource.js 确认存在，色 text_primary（非破坏性，区别移除 danger_red）。无选中时 移除/移到最后/下一首播放 三按钮共享禁用（opacity 降档 + enabled false）。点击两新按钮：收集选中条目扁平下标 → 飞越动画包裹 `moveFlatItems`（D11）→ 动画结束 toast「已插入 N 项到当前播放之后」/「已移动 N 项至队尾」（内联模板串，沿 HistorySheet 播放失败 toast 先例）并退多选清空。多选行 5 枚图标按钮挂长按提示（D12）。
  - **Alternatives considered**: 底部悬浮双胶囊文字条（初稿；用户偏好图标形态，弃）；计数内嵌全选按钮（用户决策放按钮外右侧，弃）；移除按钮保留计数（弃）；文字+图标混合（行宽挤，弃）；退出按钮挪位/移除（用户选保留右缘，弃）；toast 常量化进 Constants（N 动态替换需运行时拼串，内联模板串沿先例，弃）。

- **D9 历史面板多选行镜像（US5/US6，Phase 2 审查用户决策 + 再优化批）**
  - **Decision**: HistorySheet 多选行与 QueueSheet 同档式镜像：全选按钮右侧加独立计数（同 D3 档式：「已选N条」Text+Span 组合，N accent、余字 `text_primary`、`TOKEN_FONT_17`、`TOKEN_SPACE_XS` 间距、实时变化、0 也显示）；「删除所选」按钮去内嵌计数变纯 trash 图标（danger_red 色、确认弹窗、onClick 零改动）；返回按钮不动；3 枚图标按钮挂长按提示（D12，文案 全选/删除所选/退出多选）。现状核实：QueueSheet/HistorySheet 多选行为各自内联实现（无现行共享组件），按「同一档式两处镜像」落地，不抽共享行组件。
  - **Alternatives considered**: 抽共享多选行组件（两面板按钮集不同——队列 移除/移到最后/下一首播放/退出 vs 历史 删除所选/返回——槽位化改造改动大于收益，弃，按镜像落地保视觉/交互一致）。

- **D4 源页多选三按钮底栏（再优化批：位序互换；第三修正：双 accent 主按钮 + 中描边）**
  - **Decision**: `selectActionBar` 三按钮新位序新样式：左「队列末播放 (N)」（accent 底主按钮 + `fg_on_dark` 白字，→ `enqueueSelected(false)`，原「加入队列 (N)」更名，语义不变追加队尾）·中「标记已看完」（card 底 + 主题色描边 `border({ width: 1, color: accentColor, radius: TOKEN_RADIUS_XXL })`，原 card 档式加描边）·右「下一首播放 (N)」（accent 底主按钮 + `fg_on_dark` 白字，→ `enqueueSelected(true)` 收集选中剧集调 `loadPlaylistAndPlay(items, 0, true)`）；两枚入队按钮样式一致（用户第三修正决策）。toast 沿用三分型、完成后退多选。360dp 单行适配：三按钮统一 `TOKEN_FONT_BODY_S` 字号 + 横向边距收紧一档（`TOKEN_SPACE_M`），计数保留（用户决策）；实施后 360dp 宽度校验单行不溢出（自查事项）。过渡：左 START 滑入、右 END 滑入、中 OPACITY（`TransitionEffect` 组合沿用）。
  - **Alternatives considered**: 左 card+描边/右 accent 主按钮（第二版双主色形态，用户第三修正改左右一致，弃）；三枚全 card+描边（用户选左右 accent 主按钮，弃）；纯换位不动样式（弃）；计数去角（用户已决策保留，弃）；两行堆叠（破坏既有单行档，弃）。

- **D5 单集插入位置设置：播放设置组 SettingsRow + 两选项 sheet（音质先例）**
  - **Decision**: 播放设置组「仅在 Wi-Fi 环境播放」之后加 `SettingsRow`（title「单集插入位置」，valueText 显示当前值「队列末播放/下一首播放」，showArrow，rowAction 开 sheet）；`bindSheet` 两选项单选面板复刻 `qualitySheetPanel` 档式（标题 + 两行选项、当前项 ✓ 高亮、选中即持久化并关闭）。持久化 `Constants.KEY_SINGLE_INSERT_NEXT = 'singleInsertNext'`，缺省 0（老用户现状无感）。`@Local` 状态 + aboutToAppear 读取（历史同步行先例）。
  - **Alternatives considered**: Toggle 行（二值但无法展示当前值名称，用户已命名两项值，弃）；外观组胶囊档（播放设置组内行式统一优先，弃）。

- **D6 单击路径接设置（仅源页单击，实时读取）**
  - **Decision**: `SourcePage.enqueueAndToast` 内实时读 `AppStore.getNumber(KEY_SINGLE_INSERT_NEXT, 0) === 1` 传第三参（点击时生效无缓存同步问题，移除前确认开关同款先例）；`playEpisode` 的详情/兜底两路自通。多选按钮（显式参）、添加订阅、历史面板零改动。
  - **Alternatives considered**: aboutToAppear 缓存设置值（设置页改动需跨页广播同步，多余机制，弃）。

- **D7 版本号**
  - **Decision**: `AppScope/app.json5`：`versionName` 0.6.0→0.7.0、`versionCode` 6000→7000（仓库既有升版惯例）。
  - **Alternatives considered**: 无。

- **D8 队列头部按钮位序互换（US4，Phase 2 审查追加）**
  - **Decision**: QueueSheet 单行头部右侧三枚图标按钮位序由 清除已播 → 多选 → 清空 调整为 清空 → 多选 → 清除已播（`trash` 与 `wand_and_stars` 两按钮整块互换，图标/onClick/样式/确认弹窗零改动）。空队列态按钮隐藏逻辑随按钮原样移动（现状 entries.length > 0 才渲染三按钮）。
  - **Alternatives considered**: 仅在多选态互换（无差别语义，弃）。

- **D10 首页置顶飞越动画（US7/FR-012，再优化批，实施序先于 D11）**
  - **Decision**: HomePage `pinToTop` 既有机制保留——`animateTo` 闭包内数据前插 + `provider.moveToFront` 相邻交换冒泡 `onDataMove` 通知驱动 LazyForEach 补位动画；新增 `@Local flightKey: string = ''`（V2 状态，重赋值触发）：`pinToTop` 置 `flightKey` 为被置顶行键，`animateTo` 的 `onFinish` 清空；列表行节点挂 `.zIndex(this.flightKey === row.key ? 1 : 0)`——飞行期间被置顶行渲染于其他行之上（飞越），动画结束复位；其余行向下补位（既有交换通知视觉）。首位幂等（idx ≤ 0 早退）不变；长按菜单/拖拽排序/删除路径零改动。
  - **Alternatives considered**: overlay 幽灵行飞行（需测位、复制行内容、时序协调，复杂度远超 zIndex 方案，弃）；scale/阴影抬起微调（观感增强项不承诺，真机观感不足再议）。

- **D11 队列移动飞越动画 + toast + 退多选同时化（US1/FR-002，再优化批+第三修正，机制复用 D10、不抽公共组件——用户决策）**
  - **Decision**: QueueSheet `moveSelected(toEnd)` 改造：新增 `@Local flightKeys: Set<string> = new Set()`（重赋值触发）。点击移动按钮：`flightKeys` 赋值为选中条目键集（重赋值新 Set）→ `getUIContext().animateTo({ duration: TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut, onFinish })` 闭包内调 `moveFlatItems`（同步广播链内 entries 重建参与动画，ForEach 键稳定节点复用）；列表条目节点挂 `.zIndex(this.flightKeys.has(entry.key) ? 1 : 0)`——被移动条目飞行期间盖在其他条目之上飞至新位置，其余条目补位。**退多选同时化（第三修正）**：闭包内 `moveFlatItems` 返回 `moved > 0` 时直接调裸 `exitSelectMode()`（endSweep + selectMode 翻转 + selectedKeys 清空，无动画壳、避免嵌套 animateTo）——勾选框收起/头部双态切换与条目飞行同一起点同参数（TOKEN_SELECT_ANIM_MS/EaseOut）同步驱动，总时长 ~300ms；`moved === 0`（仅当前播放条目被选中）不退多选不 toast（既有闸保留）。`onFinish`：清 `flightKeys`（重赋值空 Set）→ toast（「已插入 N 项到当前播放之后」/「已移动 N 项至队尾」）。降级：广播链异步致动画不生效时 `flightKeys` 仍 onFinish 清、功能与 toast 不受阻（spec Edge Cases 已定）。
  - **Alternatives considered**: 退多选 onFinish 串行（第二版：飞越 300ms 播完再起退多选 300ms，总 ~600ms 先后观感，用户第三修正改同时，弃）；toast 提前到点击即弹（用户定文案含目标位置，时机随移动完成，落 onFinish 语义更贴合）；抽公共飞越组件（用户决策不抽，各自实现）。

- **D12 多选行图标按钮长按气泡提示（US6/FR-011，再优化批；第三修正 toast→bindPopup——用户决策）**
  - **Decision**: 两面板各加 `@Local popupTip: string = ''`（单态互斥，重赋值触发）；多选行全部图标按钮挂 `.bindPopup(this.popupTip === '<按钮键>', { message: '功能名', placement: Placement.Bottom })` + `.gesture(LongPressGesture().onAction((): void => { this.popupTip = '<按钮键>' }))`：队列 5 枚（全选/移除所选/移到最后/下一首播放/退出多选）、历史 3 枚（全选/删除所选/退出多选）。气泡锚定被长按按钮、出现在按钮下方（多选行居面板顶部，朝下不遮操作栏）、autoCancel 点面板任意处消失；`onStateChange` 在气泡不可见时清 `popupTip`（与 autoCancel 消失同步，避免状态残留致同按钮二次长按不弹）。与 `onClick` 并存——手势竞争下长按触发后不触发点击（框架默认竞争语义）；气泡弹出后首次点击可能先关气泡再执行功能（真机核验项）。长按时长用系统默认阈值。
  - **Alternatives considered**: showToast 全局提示（第二版：离按钮远、指向弱，用户第三修正改按钮处气泡，弃）；CustomBuilder 自定义气泡（message 纯文字已满足，弃）；定时自动消失（autoCancel 已满足，setTimeout 多余，弃）；onActionEnd 松手即消（阅读时间不足，弃）；每按钮独立布尔状态（8 个状态 vs 单 popupTip 互斥，弃）。

## Technical Details

- **Constants.ets**: `KEY_SINGLE_INSERT_NEXT = 'singleInsertNext'`（KEY_ANOMALY_SKIP 后的 Preferences 键区）；新增 `TOKEN_FONT_17 = 17`（字号令牌区，TOKEN_FONT_TITLE 与 TOKEN_FONT_18 之间——「已选N条」与「播放队列」标题同源字号）；无新 toast 常量（移动 toast 为 N 动态内联模板串、入队沿用三分型）
- **PlayerController.ets**: `loadPlaylistAndPlay` 第三可选参 + 非空分支插入点分支（当前游程定位经 `getQueueEntryGroups`）；新方法 `moveFlatItems(indices, toEnd)` 置 `removeSelectedFromPlaylist` 邻域（队列批量操作聚集）；statusMsg 内联模板串（沿本文件现状惯例）
- **QueueSheet.ets**: 多选行加「移到最后」「下一首播放」两枚图标玻璃按钮（禁用联动 + `moveSelected` 飞越改造：flightKeys + animateTo + zIndex + 闭包内裸退多选（同时化）/onFinish toast）；计数改「已选N条」（Text+Span、`TOKEN_FONT_17`）；5 枚按钮长按气泡（bindPopup + popupTip + onStateChange 清理）；标题字面 17 替换为 `TOKEN_FONT_17`；单行头部 `trash` 与 `wand_and_stars` 两按钮块互换
- **HistorySheet.ets**: 多选行计数改「已选N条」（同 QueueSheet 档式）；3 枚按钮长按气泡（同 D12 机制）
- **SourcePage.ets**: `selectActionBar` 三按钮位序互换 + 左右 accent 主按钮（左 队列末/右 下一首，fg_on_dark 白字）+ 中 card 底 accent 描边；`enqueueSelected` 加布尔参；`enqueueAndToast` 读设置传第三参
- **SettingsPage.ets**: 播放设置组新 SettingsRow + 两选项 sheet 面板 + `@Local` 状态与读写
- **HomePage.ets**: `pinToTop` 飞越（`@Local flightKey` + 行节点 `.zIndex` + `onFinish` 复位），其余路径零改动
- **AppScope/app.json5**: 版本号两项

**Structure Decision**: 全部沿用既有分层（service→model、pages→service/model 单向依赖；Constants 零业务依赖），不引入新目录/新文件。

**Performance Goals**: 移动为 O(n) 数组重组（歌单量级 ≤ 数百，瞬时完成）；飞越动画为 zIndex 状态翻转（无常驻开销、无额外节点）；插入路径零额外网络请求；全部改动无常驻开销。

## Risks & Mitigations

| 风险 | 等级 | 缓解 |
|---|---|---|
| `moveFlatItems` 重组后 currentIndex 定位错 → 播错/断播 | 中 | 复合键重定位而非下标换算；当前条目游程强制剔除不移动；按 US1 六场景逐条验证 |
| 队列飞越动画不生效（广播链异步/时序） | 中 | 降级路径：flightKeys 仍 onFinish 清、功能与 toast 不受阻（spec Edge 已定）；真机核验飞越观感 |
| zIndex 在 List/ListItem 飞行期不生效（渲染层级差异） | 低 | zIndex 为通用属性；D10/D11 真机核验，不生效改 overlay 方案再议 |
| 三按钮 360dp 单行溢出 | 中 | 字号/边距令牌降一档（D4）；360dp 宽度校验列入自查事项 |
| 移动图标语义辨识度（`forward_end_fill`/`arrow_down_to_line`） | 低 | 图标已确认存在且为既有/常见语义；长按提示补足辨识度（D12）；真机自查 |
| 长按气泡与行手势冲突（行拖选/长按菜单） | 低 | 按钮节点独立于行节点；手势竞争长按胜出后不触发点击（框架语义）；真机核验 |
| 气泡弹出后首次点击被关气泡吃掉（bindPopup autoCancel 语义） | 低 | 真机核验；预期首次点击关气泡、二次点击执行（提示→确认节奏）；观感不佳再议 onStateChange 配合调整 |
| 多选态 entries 与 playlist 失步（异步竞态） | 低 | 点击即收集即调用（同帧无 await）；Controller 边界校验丢弃越界下标 |
| 插入/移动与随机、单曲循环模式的观感差异 | 低 | spec 已声明仅承诺队列线性位置；statusMsg 提示实际结果 |
| `loadPlaylistAndPlay` 签名波及既有 4 调用方 | 低 | 第三参默认 false 编译期保证既有路径零变化 |
| 移动无独立测试（仓库无测试设施） | 低 | 家例为构建验证 + 场景自查；重组逻辑为纯数组操作，US1 场景覆盖分支即验 |
