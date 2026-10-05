# BiliRadio UI 测试 Playbook（子代理专用）

> **用途**：spec-verify 子代理执行 UI 验证（T024 类任务）前必读。记录工具链用法、本项目交互地图、已知坑与解法。
> **维护约定**：每轮 UI 验证结束后，执行验证的子代理应把本轮新学到的技巧**追加**到对应章节（≤10 行/条，可操作、不复述）。

## 1. 工具链（deveco-cli）

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
| `devecocli run --skip-build` | 部署已构建产物 | 构建（T021）完成后用这个部署 |
| `devecocli run --apply <file>` | 增量热修 | 验证中修复代码后比全量 run 快得多；改动文件列表写入 `.hvigor/<file>`（相对路径，一行一个） |
| `devecocli log --bundle-name <pkg> [--level E] [--from 5m] [--tail 200]` | hilog | **不要用 `--follow`**（代理会缓冲到进程退出）；用 `--from`/`--tail` 有界查询；复现问题前 `devecocli log clear` |
| `devecocli log --crash --bundle-name <pkg>` | 崩溃日志 | 闪退/白屏先跑这个 |

### 已知坑（ Troubleshooting ）
- **`ui layout` 找不到预期节点** → 节点不在屏内。先 `ui dircfling` 滚动或 `ui swipe` 滚到可见区再 layout。
- **模拟器启动失败/OOM** → 宿主机内存瓶颈。启动前避免并发重负载（如并行构建）；失败重试一次，仍失败则按任务约定跳过 UI 验证不阻塞。
- **`install sign info inconsistent`** → 签名变了。用 `devecocli run --uninstall` 先卸载再装。
- **多设备连接** → 一切 ui/log/run 命令必须带 `--device <name|serial>`。
- **半模态 bindSheet** → 弹出后焦点窗口变化，`ui layout` 默认查焦点窗口；查不到时 `--window` 配合 `--id`，或 `ui window list` 先看窗口清单。

## 2. BiliRadio 交互地图（导航路径）

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
- 区块顺序：账号 → 本地与缓存 → 播放设置 → 省流量 → 外观（主题色板）→ **播放历史 → 日志查询（Round 3 新增）** → 取消收藏历史 → 关于
- 播放历史/日志查询均为 bindSheet 62%；关于 75%
- 日志查询（US9）：触发网络请求后应有 时间/类别（网络/错误）/URL 摘要/响应码 条目，倒序

### 播控行为
- **顺序模式播完最后一首 → 停止，"播放结束"，不回绕**（US7）；手动点下一首 → 回绕第一首（预期行为非 bug）
- 随机/单曲循环 → 行为同旧版
- 播控中心（US8）：API 26 设备五元组 = 上一首/播放暂停/下一首/快退/快进；一级三元组 = 上一首/播放暂停/下一首（**系统硬规则，非缺陷**）；API<26 设备无微调按钮（[API24-COMPAT] 降级预期）

## 3. 验证工作流（每故事）

1. **前置**：确认应用已部署且在前台（`ui layout` 能 dump 到首页树）
2. **导航到目标场景**（按第 2 节交互地图）；不在屏内先滚动
3. **断言**：优先 `ui layout --format json` 找节点文本/属性（机器可判）；视觉性结论（间距/贴合度/颜色）用 `ui screenshot` 留证 + 自行判断
4. **失败时**：`devecocli log --from 2m --tail 100` 查异常 → 修复（改动文件写入 `.hvigor/changes.txt` → `devecocli run --apply changes.txt` 增量部署）→ 重新验证（每故事 ≤3 次尝试）
5. **网络依赖**：US1/US6/US9 需真实 B 站网络；订阅数据需账号已登录或有既有订阅。无网/未登录时记录 SKIPPED 原因，不算 FAIL
6. **每故事结束**：结果（PASS/FAIL/SKIP）+ 尝试次数 + 截图路径（如有）

## 4. 经验追加区（验证子代理维护）

<!-- 每轮验证后在此追加：
- 日期 / 轮次
- 新技巧或新坑（≤10 行/条，可操作）
-->

- 2026-10-05 / Round 3（两次验证会话被中断，主代理从会话恢复中代录）：
  - 命令纠错：设备清单是 `devecocli device list`（不是 `devices`）；`ui screenshot` 不接收位置参数（报 "too many arguments"），输出路径配置方式待查证
  - 首装报 `9568263 install version downgrade` → `devecocli run --uninstall` 重装；锁屏状态下 Smoke 会误报进程死亡（10106102）→ `devecocli emulator power` + 上滑解锁后重试
  - 瞬态 UI（0.6s 缓冲弧线）验证：verify_ui 截图时机可能错过窗口 → 用 hilog 时序（try stream→initialized→prepared→playing）+ 尺寸链代码核对 + 多截图像素分析交叉取证
  - **a11y 值可能是渲染停滞时的缓存快照**：layout dump 值陈旧 ≠ 应用逻辑错误；先用点按交互测试响应性，再以 hilog 判定真实状态——日志是权威信号
  - 排查"单组件 @State 滞留"：对比同数据源兄弟组件的新鲜度（MiniPlayer vs PlayerOverlay），可快速隔离"广播正常、特定组件未更新"
  - B 站风控：UID 23947287 首次抓取触发 -352，静默刷新冷却后恢复（30 集）——测试数据准备预留冷却时间
  - 播放完成类用例（如 US7 播完即停）优先入队短流（<3min）加速；手动 next() 回绕是预期行为非 bug
  - PowerShell 嵌套引号会报"字符串缺少终止符"——Select-String/grep 模式改用单引号或转义写法
