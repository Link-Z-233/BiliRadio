# v0.7-part2-refresh-share bugfix 记录

直接修复（不走 SDD 五阶段）的 bug 按发生顺序在此登记。

## 1. 队列重排后当前播放高亮错位、点击切播错条目

**现象**：播放队列多选批量移动（移到队尾/当前播放之后）后，当前播放条目的强调色指示出现在错误行；同状态下点击行切播会播放错误条目（行内容显示正常，音频切错）。条目滚出缓存区再滚回会自愈。

**根因**：重排走 `QueueSheet.syncFrom` 整表 reload 路径（`diffRemovedEntries` 对重排返回 undefined）。LazyForEach 同键节点跨 `onDataReloaded` 复用时不重执行生成器闭包（官方 FAQ faqs-arkui-828/1642，与 `v0.4-fix-multi-part` bugfix #1 删除路径 jscrash 同一类）：行内容经共享 `BiliVideo` 对象引用仍正确，但闭包内旧 `entry.startIndex` 与新 `currentIndex` 比对 → 高亮错位；点击切播（分P 行/单条目行）用同一过期 `startIndex` → 错播。尾部追加不动存量 startIndex 天然无感，重排/中段插入必现。

**修复**（均 `QueueSheet.ets`，复合键实时解析——HistorySheet 既有规避模式）：

1. `@Local currentIndex` → `@Local currentKey`（当前条目复合键，`syncFrom` 同步，占位 0≡1 经 `itemKeyOf` 归一化天然对齐）。
2. 三处高亮比对改 `itemKeyOf(...) === this.currentKey`：分P 行字色、单条目封面 highlight、单条目标题字色。
3. 两处点击切播改 `indexOfQueueItem(bvid, page)` 实时定位 + `-1` 守卫。
4. `queuePartRow` 去掉仅服务于扁平下标换算的 `partIdx` 参数（调用点同步）。
5. 五处扫选/拖选锚点改键实时解析：新增 `entryIndexOf(key)` 辅助，`startSweep(this.entryIndexOf(entry.key))` ×2、`dragStartEntryIndex = this.entryIndexOf(entry.key)` ×3；拖选 Pan onActionUpdate 加 `dragStartEntryIndex < 0` no-op 守卫（-1 经 `targetEntryIndex` 会钳到 0 误选首条目）。
6. 三行 builder（`videoHeaderRow`/`queuePartRow`/`queueFullRow`）与 LazyForEach 生成器的 `index`/`entryIndex` 参数全退场——闭包内零位置量，此类 bug 根治；顺带删除只写不读的 `currentItemEnded` 死同步（`PlayerController` 本体仍是活代码）。

**验证**：`devecocli check arkts` 零错误（40 条告警均为既有基线，QueueSheet 3 条在未改动行）；`devecocli build` 成功。真机复测待用户：重排后高亮跟当前条目、点击切播正确、五种行长按拖选/扫选起点不错行。
