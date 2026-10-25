# BiliRadio 验证阶段专用文档

> **用途**：验证阶段专用文档——SDD Phase 5 必用本文档；非 SDD 验证（bugfix 直接修复后验证、轮次内小改动验证等）同样遵循。任何执行验证的一方（主代理/子代理/人工）验证前必读。覆盖验证范围判定、构建验证流程、UI 验证工具链与交互地图、已知坑与经验。
> **维护约定**：每轮验证结束后，验证执行方应把本轮新学到的技巧**追加**到经验追加区（≤10 行/条，可操作、不复述）。

## 1. 验证范围判定

- **SDD 轮次**：以 `tasks.md` Verification 阶段的标记为准：
  - `<!-- verification_scope: build-only -->`（默认）：仅执行第 2 节构建+部署验证
  - `<!-- verification_scope: build+ui -->`：构建+部署通过后，再执行第 3~5 节 UI 验证
- **非 SDD 验证**：无 tasks.md 标记时，默认同样只做第 2 节构建+部署验证；需要 UI 验证时走第 3~5 节
- **spec-verify 只验证一次**：失败不重调，报告交主代理处理并修复；主代理自行验证同一目标 ≤3 次
- 验证结果记录：SDD 轮次按 tasks.md 约定产出报告（PASS/FAIL/SKIP + 依据）；非 SDD 验证在对话中报告即可，不入文件

## 2. 构建验证（默认路径）

1. `devecocli build` 成功 = 构建通过；失败读输出中 `ERROR` 行定位（类型/导入/资源/权限/API 级别），修复后重试，同一目标 ≤3 次
2. 构建成功后 `devecocli run --skip-build` 部署，确认应用可安装启动（部署失败 ≠ 构建失败，按签名/设备问题排查）
3. 真机优先；多设备时 `--device` 指定

## 3. UI 验证工具链（deveco-cli）

### 交互与检查
| 命令 | 用途 | 关键点 |
|---|---|---|
| `devecocli ui layout [--format json] [--mode simplified] [--depth n]` | dump 可见区域 ArkUI 无障碍树 | **只返回屏上节点**——目标不在屏内先滚动；配合 `--id` 定位 |
| `devecocli ui click [x y]` 或 `--id <id>` | 点击 | **优先 `--id`**（自动解析到节点中心，免坐标换算）；坐标与 id 互斥 |
| `devecocli ui longclick / doubleclick` | 长按/双击 | 同上 |
| `devecocli ui swipe <x1 y1 x2 y2> [--speed n]` | 精确滑动 | 下拉刷新测试用它（从列表中部往下滑）；速度 200–40000 px/s |
| `devecocli ui dircfling <up\|down\|left\|right>` | 定向快滑 | 页面/列表滚动首选（系统默认速度，无需坐标） |
| `devecocli ui text <text> [--id <id>]` | 输入文本 | 特殊字符内部 Base64 传输；无参时输入到当前焦点输入框 |
| `devecocli ui screenshot --path <dir\|png>` | 截图留证 | 路径必须可写且**不覆盖**已有文件（每张用不同文件名） |
| `devecocli ui window list` | 窗口清单 | 多窗口/半模态排查用 |

### 设备与部署
| 命令 | 用途 | 关键点 |
|---|---|---|
| `devecocli device list` | 真机+模拟器清单 | 多设备时后续命令都要 `--device`；**真机优先**（用户平时真机测试） |
| `devecocli emulator list / start / stop` | 模拟器管理 | MatePad Pro 11；启动慢（分钟级），设长超时 |
| `devecocli run --skip-build` | 部署已构建产物 | 构建完成后用这个部署 |
| `devecocli run --apply <file>` | 增量热修 | 验证中修复代码后比全量 run 快得多；改动文件列表写入 `.hvigor/<file>`（相对路径，一行一个） |
| `devecocli log --bundle-name <pkg> [--level E] [--from 5m] [--tail 200]` | hilog | **不要用 `--follow`**（代理会缓冲到进程退出）；用 `--from`/`--tail` 有界查询；复现问题前 `devecocli log clear` |
| `devecocli log --crash --bundle-name <pkg>` | 崩溃日志 | 闪退/白屏先跑这个 |

### 已知坑（Troubleshooting）
- **`ui layout` 找不到预期节点** → 节点不在屏内。先 `ui dircfling` 滚动或 `ui swipe` 滚到可见区再 layout。
- **模拟器启动失败/OOM** → 宿主机内存瓶颈。启动前避免并发重负载（如并行构建）；失败重试一次，仍失败则按任务约定跳过 UI 验证不阻塞。
- **`install sign info inconsistent`** → 签名变了。用 `devecocli run --uninstall` 先卸载再装。
- **多设备连接** → 一切 ui/log/run 命令必须带 `--device <name|serial>`。
- **半模态 bindSheet** → 弹出后焦点窗口变化，`ui layout` 默认查焦点窗口；查不到时 `--window` 配合 `--id`，或 `ui window list` 先看窗口清单。

## 4. 交互地图（导航路径）

### 首页（HomePage，Navigation 首页）
- 订阅列表：LazyForEach 列表，**单击订阅卡片 → 进入订阅源详情页（SourcePage）**
- 右上角"更多"按钮（ellipsis_circle 图标）→ **直达设置页**（Round 3 起，不再经 MorePage）
- 首页下拉刷新：**已注释禁用**（Round 3）——下拉手势应无任何反应（US3 验证点）
- "＋"入口 → 添加订阅 sheet（粘贴 BV 号/链接）

### 订阅源详情页（SourcePage）
- **单击单个视频条目 → 仅该条入队并播放**（Round 3 起，US6）
- "播放全部"按钮 → 整源入队

### 播放层（PlayerOverlay，全屏 bindContentCover）
- 唤起方式：点击底部迷你条（MiniPlayer）
- 播放按钮缓冲态：**加载弧线紧贴按钮**（US1 验证点：无缓存歌曲触发缓冲）
- 无任务空态：**"暂无播放内容"占位**（US2，迷你条与播放层一致）
- 主标题行点击/箭头 → 详情 bindSheet（62%）：**完整标题不被截断**（US10）
- 封面顶部留白（US10：margin top 24）
- ±15 秒按钮在传输区（按钮文字/图标形态）

### 播放队列（QueueSheet，半模态）
- 打开：迷你条右侧队列图标 / 播放层队列入口
- **头部两行结构**（US5）：第一行"播放队列 共 N 首"，第二行 定位/搜索/多选/清空
- 多选模式：长按条目进入；"完成"按钮已移除（Round 2），**点遮罩关闭**

### 设置页（SettingsPage，路由页）
- 路由：`pushPathByName('settingsPage', '')`；带参 `'playHistory'`/`'about'` 可直开对应面板
- 区块顺序：账号 → 本地与缓存 → 播放设置 → 音质（新增：Wi-Fi/蜂窝默认音质双设置）→ 省流量（仅剩省流量模式与仅 Wi-Fi 播放两项，原「优先低码率音频流」已移除）→ 外观（主题色板）→ **播放历史 → 日志查询（Round 3 新增）** → 取消收藏历史 → 关于
- 播放历史/日志查询均为 bindSheet 62%；关于 75%
- 日志查询（US9）：触发网络请求后应有 时间/类别（网络/错误）/URL 摘要/响应码 条目，倒序

### 播控行为
- **顺序模式播完最后一首 → 停止，"播放结束"，不回绕**（US7）；手动点下一首 → 回绕第一首（预期行为非 bug）
- 随机/单曲循环 → 行为同旧版
- 播控中心（US8）：API 26 设备五元组 = 上一首/播放暂停/下一首/快退/快进；一级三元组 = 上一首/播放暂停/下一首（**系统硬规则，非缺陷**）

## 5. UI 验证工作流（每故事）

1. **前置**：确认应用已部署且在前台（`ui layout` 能 dump 到首页树）
2. **导航到目标场景**（按第 4 节交互地图）；不在屏内先滚动
3. **断言**：优先 `ui layout --format json` 找节点文本/属性（机器可判）；视觉性结论（间距/贴合度/颜色）用 `ui screenshot` 留证 + 自行判断
4. **失败时**：`devecocli log --from 2m --tail 100` 查异常 → 修复（改动文件写入 `.hvigor/changes.txt` → `devecocli run --apply changes.txt` 增量部署）→ 重新验证（每故事 ≤3 次尝试）
5. **网络依赖**：US1/US6/US9 需真实 B 站网络；订阅数据需账号已登录或有既有订阅。无网/未登录时记录 SKIPPED 原因，不算 FAIL
6. **每故事结束**：结果（PASS/FAIL/SKIP）+ 尝试次数 + 截图路径（如有）

## 6. 经验追加区（验证执行方维护）

<!-- 每轮验证后在此按固定格式追加（最新在最下，不回改历史条目）：
- <版本号+轮次或场景>（<验证范围：build-only / build+ui>，<部署环境：真机 / 模拟器>）：
  - <一条经验 = 可操作结论 + 触发条件或坑 + 处置方式；≤10 行/条>
  -->

- Round 3（两次验证会话被中断，主代理从会话恢复中代录）：
  - 命令纠错：设备清单是 `devecocli device list`（不是 `devices`）；`ui screenshot` 不接收位置参数（报 "too many arguments"），输出用 `--path` 指定
  - 首装报 `9568263 install version downgrade` → `devecocli run --uninstall` 重装；锁屏状态下 Smoke 会误报进程死亡（10106102）→ `devecocli emulator power` + 上滑解锁后重试
  - 瞬态 UI（0.6s 缓冲弧线）验证：verify_ui 截图时机可能错过窗口 → 用 hilog 时序（try stream→initialized→prepared→playing）+ 尺寸链代码核对 + 多截图像素分析交叉取证
  - **a11y 值可能是渲染停滞时的缓存快照**：layout dump 值陈旧 ≠ 应用逻辑错误；先用点按交互测试响应性，再以 hilog 判定真实状态——日志是权威信号
  - 排查"单组件 @State 滞留"：对比同数据源兄弟组件的新鲜度（MiniPlayer vs PlayerOverlay），可快速隔离"广播正常、特定组件未更新"
  - B 站风控：UID 23947287 首次抓取触发 -352，静默刷新冷却后恢复（30 集）——测试数据准备预留冷却时间
  - 播放完成类用例（如 US7 播完即停）优先入队短流（<3min）加速；手动 next() 回绕是预期行为非 bug
  - PowerShell 嵌套引号会报"字符串缺少终止符"——Select-String/grep 模式改用单引号或转义写法

- v0.6-part1（build-only，真机无线部署）：
  - 无线真机部署：`hdc tconn 192.168.x.x:port`（hdc 已入 PATH：SDK `toolchains` 目录）；连接后 `devecocli run` 须 `--device <serial>` 显式指定——stopped 模拟器也占设备清单位，单在线设备同样触发 `DEVICE_SELECTION_REQUIRED`
  - `devecocli emulator start --device <name>` 报 unknown option——设备名用位置参数；且启动可能超时不出现在 hdc list（非阻塞，改真机路径即可）

- v0.6-part2-debt-cleanup（build-only，部署取消·用户真机自部署）：
  - 构建告警清点必须全量构建：增量构建（CompileArkTS UP-TO-DATE）不重跑 lint，告警缺失是「没跑」不是「修了」——先 `devecocli build clean` 再 `devecocli build`，全量日志才可作告警验收依据
  - 告警清点对账法：完整日志在 `Temp\deveco\devecocli\build-*.log`（每次构建新文件）；WARN 行恒后随一条消息行，按「WARN 行 + 后随消息行」配对 Group-Object 分组，总数对账后再逐类定位——比逐模式分别计数不易漏项
  - syscap 类告警消息形态为 "The system capacity of this api 'X' is not supported on all devices"（清点检索 'system capacity'，非 'syscap' 字样）

- v0.6-part3-sub-manage（build-only，真机未连接·T017 部署未执行）：
  - arkts_check 报错先看文件归属再判定：`@arkts.lang.d.ets` 71/79 行 6 条（interface/Retention/const enum）是 SDK 自身已知误报，只有指向项目文件的错误才需修复——预检通过标准 = 项目文件零错误，勿为 SDK 误报返工
  - 无设备判定口径：`devecocli device list` 只列 active 设备（无设备时显示 No active devices）；`devecocli run` 才暴露 stopped 模拟器占位并以 DEVICE_SELECTION_REQUIRED 拒绝——确认「真机是否在线」以 run 输出为准，二者清单不一致

- v0.6-part3-sub-manage 追加批（build-only，真机无线部署成功）：
  - transition 无动画排查定式：`.transition(TransitionEffect.X)` 不带 `.animation()` 且状态翻转不在 animateTo 内 = 组件直接出现/消失（官方文档明示），真机表现为「无动画」；修复二选一——补 `.animation({ duration })` 或状态翻转包 `animateTo`（多选/删除补位先例形态），后者可与既有动画节奏统一（TransitionEffect 自带参数优先于 animateTo，两套并存时曲线不齐）
  - `DataChangeListener.onDataMove(from, to)` 官方语义是**交换**（本机 lazy_for_each.d.ts 注释「swapped between the from and to positions」），不是移动——单发 onDataMove(idx, 0) 做置顶视觉上是 idx 与 0 互换；移动语义须发相邻交换冒泡序列 onDataMove(idx, idx-1)…onDataMove(1, 0)（同一 animateTo 内全序列补间 = 移动视觉）
  - 行让位动画（内容被平滑挤压）成立三要素：单 List（无 if/else 分支替换）+ 让位组件恒挂载（宽度 0↔宽/透明度 0↔1 绑定状态，SelectCheckbox 模式）+ 内容 layoutWeight(1) 真实让位；分支替换销毁重建行节点，补间无从发生——想把让位动画做进既有双分支页面，先解决迫使分支的结构冲突（本项目卡点：拖拽 onMove 与长按菜单同用长按手势，onMove 无禁用开关，恒绑是单 List 必要代价）
  - 无线真机部署中途失连：hdc list targets 为空时先 `hdc tconn <ip:port>` 重连（Connect OK 即恢复），再 `devecocli run --skip-build --device <ip:port>`——devecocli 自身不重连
  - 行级手势阻塞系统拖拽（LazyForEach.onMove）：编辑行带 LongPressGesture（同为长按识别）时手势仲裁阻塞 onMove 拖拽、编辑态拖不动；修法 `subRowItem` 根节点 `.enabled(!editMode)`——编辑态行级交互全禁、触摸穿透给 LazyForEach 拖拽手势，整行恢复可拖（零手势的行 + onMove 才是拖拽正常的前提；合并双 List 为单 List 时编辑行会带上正常态手势，此坑必踩）
  - 单 List 合并 + `.enabled(!editMode)` 后，编辑态行触摸全穿透——swipeAction 绑在 ListItem 层是否被连带压制须真机核验（FR-024 要求编辑态不可侧滑），仍可侧滑则需 ListItem 层追加闸

- v0.6-part3-sub-manage 把手即按即拖（build-only，真机未连接·T040 部署未执行）：
  - `GestureEvent` 无 `globalY`（该字段属 `FingerInfo`，gesture.d.ts FingerInfo.globalY:655）；PanGesture 跟手位移用 `GestureEvent.offsetY`（按压起算累积偏移，:1082，PanGesture 场景专用）——arkts_check 报 `Property 'globalY' does not exist on type 'GestureEvent'` 即此坑
  - 手动拖拽 translate 挂点避开带 `.animation()` 的节点：`.animation({ duration })` 无 value 过滤时覆盖组件全部可动画属性（含 translate），拖拽逐帧位移会被平滑成橡皮筋——translate/zIndex 挂 ListItem（无 animation），视觉属性（scale/背景/阴影）留根 Row
  - 换位阈值实测口径：行起始间距 = 行内容高（封面 52）+ 行上下 padding（TOKEN_SPACE_10×2=20）+ List space（TOKEN_SPACE_S=8）= 80——TOKEN_SPACE_S 是 8 不是 4，令牌取值先 grep Constants 再算，勿凭记忆

- v0.6-part3-sub-manage 非编辑态边缘长按误触拖拽修复（真机验证通过）：
  - List 恒绑 onMove 后系统拖拽的可达面 = 行内未被手势认领的盒区：行 padding 留在无手势的根节点时，边缘 padding 带长按直接进系统拖拽（非编辑态也触发，落子才被闸拒绝，拖拽视觉已发生）——认领面必须与整卡重合，行 padding 应落在携带 LongPressGesture 的内容节点上（bugfix.md §1）
  - ArkUI `.width()` 是内容宽、padding 在外另加（`layoutWeight` 才是含 padding 的总尺寸分配）：`width(0)+padding` 造隐形残带触面，残带若仅挂 pan 则长按漏给父级内建拖拽——真零宽须 width 与 padding 同条件归零
  - 认领面二分定位法：`ui longclick <x> <y>` 逐点 + 截图 + `recognize_ui_components` 判菜单有无（先在已知认领区对照，确认 longclick 时长可达长按阈值）；a11y 容器 bounds 不可靠，以叶子文本 x 反推几何链
  - 几何推演按 content-box 逐模式算总占位：padding 迁移本身保恒等（内容起点 24/62 迁移前后不变），残带归零后正常态内容起点回正 12（与本轮前基线一致）、编辑态不变——勿按 border-box 直觉推
  - 部署 smoke FAIL_CRASH 未必真崩溃：重装会杀旧进程，先 `hdc shell pidof` 看新进程存活再判；锁屏状态启动报 10106102（开发者模式不可自动解锁），解锁后装包自动重启或 `aa start`
  - hdc 命令全无输出（连 `hdc list targets` 都空）= hdc server 崩了：`hdc kill; hdc start -r; hdc tconn <ip:port>` 恢复；无线设备频繁掉线时验证序列用 `&&` 串联一次跑完
