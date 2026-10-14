# v0.4-fix-multi-part bugfix 记录

直接修复（不走 SDD 五阶段）的 bug 按发生顺序在此登记。

## 1. 队列移除多P 条目 jscrash（2026-10-15）

**现象**：播放列表中移除多P 视频条目后应用闪退，重进后条目已移除（数据层无恙，纯渲染层崩溃）。

**日志锚点**：`Debug/jscrash-com.example.biliradio-20261015091404.606.txt`（Mate 70 Pro+，debug 0.4.0/4000，进程存活 10s，foreground）。

- `TypeError: Cannot read property page of undefined`
- 栈顶 `hasGroupHeader (QueueSheet.ets:203)` ← LazyForEach 条目内 If 分支 updateFunc（657 行）← `updateDirtyElements` ← `animateTo` action（381 行删除确认回调内 `removeQueueItem`）。

**根因**：`syncFrom` 增量删除分支先 `listSource.notifyDataDelete(removed[i])`，之后才 `this.items = next`（数组变短）。LazyForEach 在 `onDataDelete` 后对部分移位/缓存条目不重执行生成器（按键复用节点），条目闭包里的 `index` 保持删除前旧值；`this.items = next` 把依赖它的 `hasGroupHeader` If 条件标脏，flush 时以过期 index 对已缩短数组下标 → `items[index] === undefined` → 读 `.page` 崩溃。多P 移除一次删成组条目、移位最多，命中概率最高。属官方已知坑：LazyForEach 使用 `index` 参数时数据删除后框架不保证重绑。

**修复**（均 `QueueSheet.ets`）：

1. `hasGroupHeader` 边界守卫：index 越界一律返回 false（防崩兜底）。
2. `PlaylistDataSource` 新增 `notifyDataChange(index)`：界内守卫 + `onDataChange` 广播。
3. `syncFrom` 增量分支：`this.items = next` 后从最低删除位到末尾逐项 `notifyDataChange(i)`，强制重绑受影响条目闭包 index（守卫 `removed.length > 0`）。

**验证**：构建通过；真机（Mate 70 Pro+）部署启动成功（smoke PASS）；四条移除路径回归待用户真机自查。
