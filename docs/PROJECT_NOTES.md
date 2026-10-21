# 项目备忘

三章登记：① 已知问题；② 已移除与禁用功能（含恢复线索）；③ 规划与预告。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。
已完成项与原「四、API 26 基线化」「五、待真机验证」两章已于 2026-10-15 清理（内容存 git 历史；待验事项改按 AGENTS.md「真机自查事项」规则在轮次结束总结集中输出，历史 VR 明细另存 spec 各轮验证报告）。

## 一、已知问题

### KI-7 链接识别链路遗留问题

- **位置**：[LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets) `recognizeInput`（编号沿用特性走查记录；B4/B5/C1 已修复销项，见 git 历史）。
- **登记项**：
  1. **B3 系列默认类型歧义**：`lists` 路径无 `type=series` 参数时默认按合集（season）处理，实际可能为系列。
  2. **B8 BV 无合法性校验**：仅匹配形态不校验，伪 BV 号要进入网络请求后才失败。

## 二、已移除与禁用功能

### REM-1 下载页（三文件移除）

- **提交**：@6d403dd（`feat: floating mini player capsule and right-side queue drawer`），配合 @382e789 流式边下边播改造。
- **移除文件**：`entry/src/main/ets/pages/DownloadsPage.ets`（320 行）、`entry/src/main/ets/service/DownloadManager.ets`（199 行）、`entry/src/main/ets/model/DownloadedSong.ets`（130 行），及 `router_map.json` 中 downloadsPage 路由条目。
- **原因**：改为流式边下边播（CDN 直链直推播放器）后，整段下载链路成为死代码。
- **恢复线索**：`git show 6d403dd` 可取三文件历史版本；若恢复需适配现流式缓存结构（`BiliService.cleanCache` 管理）与现路由表。

### REM-3 取消收藏历史（整链移除）

- **本轮（ux-feedback-round5，2026-10-07）**：移除「取消收藏后可找回」的本地历史记录整条链路；取消收藏操作本身仍即时生效，仅不再留痕。
- **移除内容**：`entry/src/main/ets/model/UnfavoriteRecord.ets`（已删除）；SettingsPage 侧历史面板全链（`showHistory`/`historyItems`/`historyVersion`、`openHistory`/`formatRemovedAt`、`historyPanel` builder、入口行及 `onBackPressed` 分支）；PlayerController 的 `unfavoriteHistory`/`pushHistory`/`refavoriteFromHistory`/`clearUnfavoriteHistory` 及入史调用；AppStore 的 `loadUnfavoriteHistory`/`saveUnfavoriteHistory`；`Constants.AS_SHOW_HISTORY` 键。
- **原因**：实机反馈使用率极低，与「清空队列」「播放历史」职责重叠。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/model/UnfavoriteRecord.ets` 定位删除提交，按上述移除内容反向恢复各调用点。
- **遗留数据**：老版本写入的 `unfavorite_history.json` 不清理（应用不再读写，无功能影响）；若未来恢复，旧文件数据仍可读取。

## 三、规划与预告

- **空态字号/观感收敛组件化（远期）**：UI 令牌化「数值不变」约束下空态字号 14/15/16 并存不可归一，结构组件化与观感收敛一并列远期待产品确认（工件见 spec/v0.3-engineering-refactor/）。
- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，未排期。
- **audio 三元组优先级限制**：播控中心/后台卡片元数据依赖系统侧信息优先级策略，B 站侧字段缺失时展示可能不全，属系统与上游数据限制，暂不适配。
- **订阅源导出导入**（ux-feedback-round6 轮登记，2026-10-09）：导出载体（本地 JSON 文件 / 分享文本）与去重合并策略待产品决策。
