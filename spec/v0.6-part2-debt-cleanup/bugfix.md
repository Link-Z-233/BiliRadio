# Bugfix Log

直接修复的问题记录（不走 SDD 流程的），按发生顺序编号分节追加。跟 SDD 流程走的修复不进本文件。

## 1. 队列分P 窄行已播 ✓ 误扩到未听分P

**现象**：多P 视频 P1 听完（播完暂停或自然完播）后，队列内 P2/P3 等未听分P 的窄行也显示已播 ✓。

**根因**：窄行 ✓ 判定用 bvid 级 `isPlayed(bvid)`——同 bvid 任一历史条目 `progress===-1` 即真（v0.4-queue-multi-p-item 当时登记的「bvid 级宽松口径」设计，P1 完播即整组所有窄行打 ✓）。数据层无误：本地历史与云端完播上报均为分P 粒度，P2 自身完播状态未被写入。

**修复**：✓ 口径改分P 粒度——`PlayerController` 新增 `isPartPlayed(bvid, page)`（复合键命中历史且 `progress===-1`），`QueueSheet` 分P 窄行改用它；bvid 级 `isPlayed` 保留，清除已播、条目计数等条目口径行为不动（用户选定范围）。

**涉及文件**：`entry/src/main/ets/service/PlayerController.ets`、`entry/src/main/ets/component/QueueSheet.ets`

**遗留**：孤立分P（不成组、走单条目整行）的行尾 ✓ 仍为 bvid 级；如需一并改分P 粒度另行处理。
