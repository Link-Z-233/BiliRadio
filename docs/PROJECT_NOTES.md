# 项目备忘

三章登记：① 已知问题；② 已移除与禁用功能（含恢复线索）；③ 规划与预告。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。
已完成项与原「四、API 26 基线化」「五、待真机验证」两章已于 2026-10-15 清理（内容存 git 历史；待验事项改按 AGENTS.md「真机自查事项」规则在轮次结束总结集中输出，历史 VR 明细另存 spec 各轮验证报告）。

## 一、已知问题

### KI-7 链接识别链路遗留问题（已全部销项）

- **位置**：[LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets) `recognizeInput`（编号沿用特性走查记录；B3/B4/B5/B8/C1 全部修复销项，见 git 历史）。
- **B8 销项口径**：BV 形态校验已加严（base58 字符集，排除 0/O/I/l），存在性校验维持网络路径（view 接口失败已有提示）。

### KI-8 hvigor SemVer 判定拒绝 0.x 主版本

- **表现**：`entry/oh-package.json5` version 为 0.x（如 `0.1.0`）时构建恒报 `The version number of the 'entry' module does not comply with the SemVer specification`；主版本 ≥ 1（如 `1.0.0`）告警消失；根 `oh-package.json5` 有无 version 字段与此无关（对照实验排除）。
- **现状**：v0.6-part2 已固化 entry version `1.0.0`，告警消除；oh-package version 仅 ohpm 发布维度语义，安装升级走 AppScope versionCode 不受影响。
- **未深挖**：hvigor 内部判定规则细节（检查正则 / semver 库版本）未查证——实验已足定位与修复；若未来 hvigor 重新接受 0.x，最多告警不再出现，无行为影响。

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
