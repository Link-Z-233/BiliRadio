# bugfix — v0.7-part5-fav-adjustment 活跃目录

## 1. 播放中断网被误判为完播并自动跳歌（提前 completed 无守卫）

- 现象：播放中网络断开，播放停止后当前条目被标「已播完」（列表 ✓、云端上报看完），当前指针跳到下一项，原进度丢失；恢复网络点播放只能从头播或播错条目。
- 根因：AVPlayer 播放 HTTP 流遇连接重置时把 EOF 当流结束上报 `completed`（连接直接断走 completed，15s 缓存超时才走 error 5400104）；`onPlayerState('completed')` 无条件信任该事件——`markCurrentHistoryCompleted()` 写 progress=-1（本地 + 云端 `reportHeartbeatCompleted`）+ `handleCompleted()` → `next()` 跳下一项（断网下取流失败停在新条目，FR-014 又将其持久化为当前）。历史取流失败修复只覆盖 catch/onError 两扇门，`completed` 门从未被覆盖（完播即写 -1 决策时未考虑网络提前 EOF）。
- 修复：`completed` 分支前置守卫——`duration > 0 && currentTime < duration × Constants.PLAY_COMPLETE_RATIO` 判为提前 EOF：不标 -1、不上报云端、不跳歌，改走 `persistProgress` + `stopFailedPlayback` + `playbackError`（toast「播放出错，请稍后重试」）停等人工，与 v0.7-part3「网络瞬时失败停等人工」决策一致；并复位 `isPrepared` 使点播放走 `playRequest` 的未 prepared 分支 → `playIndex` 从断点重取流续播。duration 未知（=0）无从判定，维持既有完播语义；真完播不受影响（95% 阈值在 `onPlayerTime` 已提前标 -1，completed 内标记仅补漏）。
- 影响面：真完播（≥95%）路径不变；循环模式提前 EOF 不再误跳下一项（复现于「列表循环 + 断网」场景）；提前 EOF 时媒体会话/后台播放状态经停口正确修正。
- 验证：`devecocli check arkts` 通过、`devecocli build` 成功；真机自查待验——播放中断网 → toast「播放出错」、列表当前条目不亮 ✓ 不跳项，恢复网络点播放从断点续播；日志页应见 `premature completed` 条目。

## 2. 切换音质遇网络抖动后控制面卡死（err2 恢复失败停口缺失）

- 现象：切换音质（手动或网络变化自动触发）期间网络断开，换流失败且原档恢复也失败后，播放暂停图标假象，点播放/暂停均无响应，须重新点选条目才能恢复。
- 根因：`setQualityTier` 换流失败走原档恢复，恢复再失败（err2 分支）只复位 `isPreparing` 与 statusMsg：`playIntent` 残留 `wasPlaying=true`（暂停图标假象）、`isPrepared` 陈旧为 true（新 AVPlayer 实际未 prepared）→ 点播放走 `playRequest` 的 `player.play()` 分支被 AudioPlayer 的 prepared 门槛空操作，控制面整体卡死；且无停声、无媒体会话修正、无 toast；raw 错误串直接外露状态栏（违背 FR-012 精神）。取流失败停口修复（FR-008）只覆盖 `playIndex` catch，从未覆盖此音频音质设置轮旧路径。
- 修复：err2 分支补齐停口：`isPrepared` 复位（点播放走 `playIndex` 从断点重取流）+ `persistProgress` 保断点 + `stopFailedPlayback('切换音质失败')`（意图复位/停声/媒体会话/后台状态一次到位）+ `playbackError(..., '切换音质失败')` 触发 toast；raw 错误仅 Logger 留痕，不再外露状态栏。
- 影响面：仅换流+恢复双失败路径；换流失败恢复成功、正常切换音质路径不变。
- 验证：`devecocli check arkts` 通过、`devecocli build` 成功；真机自查待验——切音质瞬间断网 → 状态栏「切换音质失败」+ toast、播放键回播放图标，恢复网络点播放从断点续播。
