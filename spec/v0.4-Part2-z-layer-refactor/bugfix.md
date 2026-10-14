# bugfix 记录

修复按发生顺序逐条追加分节。

## 1. 冷启动后未播放前设置页显示「未登录」（已修复，2026-10-14）

- **现象**：已登录用户冷启动后、未播放前打开设置页，账号区显示「未登录」或「已登录 (UID 0)」空头像的降级态；播放后恢复正确。
- **根因**：登录态恢复是异步链（init 内 `SecureStore.load` 载 cookie → fire-and-forget `fetchNav` 补昵称/头像），而设置页账号区只在挂载时读一次 + 播放器广播时刷新；未播放时 init 收尾广播后 fetchNav 落定**无任何广播**，账号区冻结在挂载瞬间的旧快照，直到播放触发下一次广播。
- **修复**（三处，[PlayerController.ets](../../entry/src/main/ets/service/PlayerController.ets) / [SettingsPage.ets](../../entry/src/main/ets/pages/SettingsPage.ets) / [SecureStore.ets](../../entry/src/main/ets/service/SecureStore.ets)）：
  1. fetchNav 落定（成败皆）补 `emitUi` 广播——昵称/头像补全、cookie 失效清空均驱动刷新；
  2. PlayerController 新增 `initDone` 完成标志（`inited` 是防重入哨兵、进入即置 true，不能表达完成）+ `isInited()`，设置页账号区在恢复完成前显示「正在恢复登录状态…」占位，消除「未登录」闪现；
  3. `SecureStore.load` 在 asset 查询成功但无记录时同样落到 prefs 兜底（潜伏洞：保存时 asset.add 失败走 prefs 的 cookie 此前永远读不回）。
- **验证**：arkts_check 改动文件零报错；`devecocli build` BUILD SUCCESSFUL。
- **待真机抽测**：冷启动后不播放直接进设置页，账号区应短暂「正在恢复登录状态…」后显示昵称/头像，不再出现「未登录」。

## 2. 历史面板层级与插播点播（已修复，2026-10-14）

- **现象**：历史面板为设置页树内 bindSheet 承载，与队列面板（Index 单挂载 GlassSheet）双范式并存，层级不符合五层 z 序契约（L1 导航+胶囊 → L2 设置+日志 → L3 播放浮层 → L4 历史面板 → L5 队列）；点播经 `goToPlayerTab` 中转链冗余。
- **修复**：新建 [HistorySheet.ets](../../entry/src/main/ets/component/HistorySheet.ets)（照 QueueSheet 模式，历史全链自 SettingsPage 迁入），历史面板升级为 Index 单一挂载 GlassSheet 独立层（L4），入口仍在设置页；BackHandler 返回链补历史块（多选优先→句柄→回退 flag）；点播改插播语义（`playDownloadedSong` splice 至 currentIndex 前 + `currentIndex += 1` 位移修正，播完回到原当前条目）；`goToPlayerTab` 整链删除。
- **验证**：arkts_check 零报错；`devecocli build` BUILD SUCCESSFUL。
- **待真机抽测**：设置页历史入口开合、返回链逐层关闭、插播后播完回原当前条目。

## 3. 点历史条目后播放浮层不弹起（已修复，2026-10-14）

- **现象**：历史面板点条目起播后播放浮层不出现（原设计如此），需手动另开播放页。
- **修复**：HistorySheet.replayHistory 在 `playDownloadedSong` 成功后置 `AS_SHOW_PLAYER_OVERLAY=true`——播放层（L3）垫在历史面板（L4）之下滑入，面板不收，收面板即见播放页。
- **验证**：`devecocli build` BUILD SUCCESSFUL。
- **待真机抽测**：点历史条目→收面板→播放页在台。

## 4. 冷启动未播放时播放页音质误示「未登录样式」（已修复，2026-10-14）

- **现象**：已登录（大会员）用户冷启动后、未播放前进播放页，音质入口与面板显示「64K + 登录后可选更高音质」（未登录样式误示）。
- **根因**：[PlayerOverlay.ets](../../entry/src/main/ets/pages/PlayerOverlay.ets) 三处叠加——`qualityEntryLabel` 非 dash 一律返回 '64K'（空闲态无独立分支）；`qualityPanel` else 分支把空闲（`currentTrackSource=''`）与 durl 兜底流混在一起，无条件显示登录引导；`currentQualityCode`（实际播到的档）未持久化，冷启动后为 0，空闲态无从显示真实档。
- **修复**：
  1. 三态拆分：dash → 实际音轨档名（现状）；空闲 → 优先显示缓存的上次实际档（新键 `KEY_LAST_QUALITY`，与进度同保存点写入，`init` 恢复歌单时读回），无缓存/清空过回退当前网络设置默认档（clamp 收敛）；durl →「默认」单选项（无档位概念的兜底流，取代 US5/FR-009 的「64K+登录引导」展示）。
  2. 持久化：[AppStore.ets](../../entry/src/main/ets/service/AppStore.ets) `savePlaylistFile` 加 `lastQualityCode` 参数（[PlayerController.ets](../../entry/src/main/ets/service/PlayerController.ets) 9 处调用点按语义传当前实际档，清空队列两处传 0），`persistProgress` 直写块同步补写。
- **验证**：arkts_check 零报错；`devecocli build` BUILD SUCCESSFUL。
- **待真机抽测**：冷启动未播放进播放页，音质入口显示上次实际档；起播后面板显示实际音轨列表；durl 兜底流显示「默认」单选项。
- **同轮联动**（功能变更，见 spec.md 修订注记）：默认音质选择器为大会员补 Hi-Res(30251)/杜比(30250) 档（`pickAudioTrack` 缺档回落上限修正为 192K），非大会员提示文案同步更新。
