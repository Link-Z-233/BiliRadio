# Implementation Plan: 音质选择与默认音质设置

**Input**: Feature specification from `spec/audio-quality-settings/spec.md`

## Summary

引入 B 站真实音质档位（最高/192K/132K/64K，qn 码 30280/30232/30216）：设置页「音质」分组提供 Wi-Fi/蜂窝双默认档位（默认 Wi-Fi=最高、蜂窝=132K）；播放页新增音质面板列出当前曲目实际可用音轨并即时切换（换流保进度，写回当前网络默认值）；播放中网络稳定切换后自动按新网络默认档换流（防抖）；非登录态限制（未登录仅 64K 下发）静默回落、选择器隐藏不支持档位（未登录仅显示最高/64K）并在 UI 提示。既有「优先低码率音频流」布尔链路（存储键→播放控制读取→取流函数带宽二选参数）整体退役，由档位选择机制重构取代；「省流量模式」（封面/头像）与「仅 Wi-Fi 播放」门控完全不动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，工程基线 API 24 兼容 / 目标 API 26）  
**Primary Dependencies**: @kit.NetworkKit（connection 网络类型与变化监听）、@kit.ArkUI、@kit.MediaKit（AVPlayer）、@kit.PerformanceAnalysisKit（hilog）  
**State Management**: 既有工程为 State Management V1（页面 @State/@StorageLink + PlayerController 单例 subscribe/emitUi 广播），本功能为增量改动，**保持 V1 不迁移**  
**Storage**: AppStore（preferences 键值）——新增两个音质档位键；旧「优先低码率」键读一次迁移后弃用（无删除 API，留置不读）  
**Testing**: 本批以编译 + 部署验证为准（与 Round 4 同）；`arkts_check` 严格模式静态检查全量改动 .ets  
**Target Platform**: HarmonyOS 手机/平板（单 HAP entry 模块）  
**Project Type**: mobile-app（B 站音频播放器）  
**Performance Goals**: 换流保持进度误差 ±2s、播放中断 <5s；切档换流仅一次 playurl 请求（cid 已缓存）  
**Constraints**: 未登录仅 64K 音轨下发（B 站服务端行为，客户端仅回落+隐藏不支持档位）；Hi-Res/杜比需大会员且需 fnval=4048 请求位；播放中网络切换须防抖排除抖动  
**Scale/Scope**: 改动 6 个存量文件 + 新增 1 个模型文件；无新页面、无新路由

## Project Structure

### Documentation (this feature)

```text
spec/audio-quality-settings/
├── spec.md              # 需求规格（12 条 FR / 4 个用户故事）
├── plan.md              # 本文件
└── tasks.md             # /spec-tasks 输出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── AudioQuality.ets          # [新增] QualityTier 枚举 + AudioTrack 模型 + 档位映射/标签工具
├── service/
│   ├── Constants.ets             # [改] 新增 KEY_WIFI_AUDIO_QUALITY / KEY_CELLULAR_AUDIO_QUALITY；移除 KEY_PREFER_LOW_BITRATE
│   ├── NetUtil.ets               # [改] 新增网络类型稳定变化监听（createNetConnection + 防抖回调）
│   ├── BiliService.ets           # [改] fetchDashAudioTracks（fnval=4048 全量音轨含 flac/dolby 节点）/ pickAudioTrack（回落算法）/ resolveAudioTrack（重试+durl 兜底）；移除 preferLowBitrate 布尔参数链路
│   ├── PlayerController.ets      # [改] playIndex 按网络套用默认档；setQualityTier 换流保进度+写回；网络监听自动换档；init 迁移；音质状态随 emitUi 广播
│   └── AppStore.ets              # [不动] getNumber/putNumber 既有能力直接复用
├── pages/
│   ├── SettingsPage.ets          # [改] 新增「音质」分组（两项 + 未登录提示 + 档位选择面板，未登录隐藏 132K/192K）；移除「优先低码率音频流」开关行与状态
│   └── PlayerOverlay.ets         # [改] 控制按钮行新增音质入口；qualityPanel 面板（可用音轨列表/当前档高亮/本地与 durl 来源占位）；syncFrom 同步音质状态
└── component/
    └── MiniPlayer.ets            # [不动]

PROJECT_NOTES.md                  # [改] 第三章本条目完成后状态更新
spec/ui-testing-playbook.md       # [改] 设置页区块顺序描述同步（新增「音质」分组、省流量分组仅剩两项）
```

**Structure Decision**: 遵循既有工程架构（service 单例 + model 纯数据 + pages/component 的 V1 状态分层），不引入 MVVM 目录、不做状态管理迁移。仅新增 1 个模型文件承载档位枚举与音轨模型（被 service 与 pages 双侧引用，独立成文件避免 service↔pages 反向依赖），其余全部为存量文件内的增量修改，文件数量与改动面最小。

## Complexity Tracking

> 无 Constitution 违规需豁免。

## Research & Decisions

- **Decision**: playurl 请求参数由 `fnval=16` 升级为 `fnval=4048`（qn=16、fourk=0 不变），使响应携带 flac（Hi-Res）与 dolby 音轨节点。  
  **Rationale**: biliRelay 实测注释「fnval=4048 → DASH + dolby audio」；仅 16 时响应只有常规三档音轨，「最高」档的 Hi-Res/杜比升级（FR-003）无法实现。  
  **Alternatives considered**: 保持 fnval=16 并放弃 Hi-Res/杜比（违背 spec「最高」档语义，否决）。

- **Decision**: flac/dolby 节点在响应中**不带档位 id**，解析时按 biliRelay 做法赋 id（flac→30251、dolby→30250）后合并进统一音轨列表（flac.audio 单对象、dolby.audio 数组）。  
  **Rationale**: 统一音轨模型让面板列表、回落选择、当前档标记共用一套数据；biliRelay 同法且经其 selfcheck 验证。  
  **Alternatives considered**: 单独维护特殊节点分支（三处 UI/选择逻辑都要特判，复杂度更高，否决）。

- **Decision**: 回落算法——期望档（192/132/64 对应 qn 码）存在→取之；不存在→取**不高于期望档 qn 码**的最高可用档；若不存在任何 ≤期望 的档（罕见，如期望 64K 但仅下发 192K）→取可用最高档兜底（不能不放）；「最高」→直接取最高带宽档（含 30251/30250）。  
  **Rationale**: spec FR-003；biliRelay「取不高于请求值的最佳音轨」+ PiliPlus findClosest 语义合并，兜底分支保证 SC-003「均能正常出声」。  
  **Alternatives considered**: 严格只取 ≤期望 档否则报错（违背"不中断播放"，否决）。

- **Decision**: playurl 请求/解析失败时**原参数重试一次**，仍失败走既有 durl 降级链（fetchDurlCandidates）。  
  **Rationale**: FR-006 的"以 64K 档重试"——失败通常为瞬时网络/风控问题，与档位参数无关（同一端点同一响应结构）；重试后 durl 兜底与 spec「仍无可用→既有降级链兜底」一致。  
  **Alternatives considered**: 字面按 64K 参数重发（请求与档位无关，仅多一次等价重试，无意义，否决）。

- **Decision**: 网络稳定变化监听在 NetUtil 扩展：`connection.createNetConnection().register()` 订阅 netAvailable/netCapabilitiesChange/netUnavailable，默认网络承载类型（Wi-Fi/非 Wi-Fi 二值）变化后启动 **3 秒防抖定时器**，窗口内回变则取消，到期以最新类型回调一次。仅 PlayerController 在 init 注册，进程生命周期内不注销。  
  **Rationale**: FR-010「排除网络抖动」；3 秒足够过滤 Wi-Fi/蜂窝快速往返；HarmonyOS connection API 无需额外权限（NetUtil.isWifi 已在用 getDefaultNet/getNetCapabilities）。  
  **Alternatives considered**: 监听后立即换流（抖动会反复换流中断体验，否决）；10 秒窗口（切网后等待过久，违背「立刻生效」，否决）。

- **Decision**: 播放页面板点选音轨→写回档位映射：30216→64K 档、30232→132K 档、30280→192K 档、30250/30251→**最高**档；写回目标键由 `NetUtil.isWifi()` 判定（Wi-Fi→KEY_WIFI_AUDIO_QUALITY，否则→KEY_CELLULAR_AUDIO_QUALITY）。  
  **Rationale**: Hi-Res/杜比仅能经「最高」档到达（无独立档位，spec Assumptions），写回最高档可复现用户选择；PiliPlus 同构（按当前网络写回对应设置）。  
  **Alternatives considered**: 写回 192K（用户点了 Hi-Res 却存 192K，无法复现，否决）。

- **Decision**: 存量迁移在 PlayerController.init 执行：读 KEY_WIFI_AUDIO_QUALITY，值 <0（未初始化，getNumber 默认 -1）→ 写入 Wi-Fi=0（最高）；蜂窝档同查，未初始化→旧 KEY_PREFER_LOW_BITRATE==1 ? 30216(64K) : 30232(132K)。旧键此后不再读取（无删除 API，留置）。  
  **Rationale**: FR-005；-1 哨兵区分「全新安装」与「已初始化」，迁移幂等；蜂窝默认与 spec FR-001 一致（132K）。  
  **Alternatives considered**: 单独迁移标记键（多一个键无必要，否决）。

- **Decision**: 换流保进度复用既有播放链路：setQualityTier 捕获 currentTime 与播放态（isPlaying && !pausedByUser）→ 置 isPreparing + statusMsg「正在切换音质…」→ loadToken++（作废在途 playIndex/切档）→ 以缓存的当前曲目 cid 解析新档音轨 → openStreamWithRetry(urls) → prepared 后 seek(进度) 并按原播放态恢复；失败则回滚状态保持原流（静默 + Logger 'player'）。切档前取消挂起的 seekBy 防抖定时器。  
  **Rationale**: 与 playIndex 同一套代际令牌并发模型（Round 4 US2 已验证），网络自动换流与手动切档并发时以最后触发者为准（spec Edge Cases）。cid 在 playIndex 解析后缓存，切档零额外视频信息请求。  
  **Alternatives considered**: 复用 playIndex(index, pos)（会重置播放状态/触发元数据重拉/走 Wi-Fi 门控确认，副作用大，否决）。

- **Decision**: 当前曲目音质状态由 PlayerController 持有并随 emitUi 广播：availableTracks（去重排序后的可用音轨）、currentQualityCode（实际生效 qn 码，30250/30251/30280/30232/30216）、currentTrackSource（'dash' | 'durl' | 'local'）；本地缓存路径播放在 playIndex 置 source='local'，durl 兜底置 'durl'。  
  **Rationale**: US3 面板与 FR-007 来源标识的数据源；复用既有 subscribe/syncFrom 管线，MiniPlayer 等不订阅新状态则零影响。  
  **Alternatives considered**: 面板打开时现场请求 playurl（多一次网络请求且与播放中音轨可能不一致，否决）。

- **Decision**: 登录态 UI 仅依据 `BiliSession.isLogged()`（SESSDATA 是否存在）：设置页「音质」分组在未登录时显示提示行「未登录时最高 64K，登录后可用更高音质」，且档位选择器**隐藏 132K/192K**（仅显示「最高」「64K」，FR-009 不支持的档位不显示；已存 132K/192K 值不改动，登录后自动生效）；不追踪 VIP 状态，192K/Hi-Res 的会员限制不额外提示（实际可用性以 playurl 下发音轨为准，面板列表天然准确）。  
  **Rationale**: spec Assumptions「矩阵用于 UI 提示与预期管理，不做本地硬校验拦截」；nav 接口虽可取 vipStatus 但会引入过期/刷新问题，收益低。  
  **Alternatives considered**: 解析 nav vipStatus 做三档提示（状态易过期、误导风险，否决）；未登录不隐藏仅提示（用户可选到必然无效的档位，违背 FR-009，否决）。

- **Decision**: 播放页音质面板采用与倍速/播放顺序/睡眠面板相同的根 Stack `if (this.showXxx)` 面板模式 + 控制按钮行新增入口；设置页档位选择采用既有 bindSheet 面板模式（单 sheet + 编辑目标标记 wifi/cellular）。  
  **Rationale**: 交互形态与既有面板一致（spec Assumptions），零新组件、零新样式体系。  
  **Alternatives considered**: 独立弹窗组件文件（两个页面各用一次、逻辑简单，不值得拆文件，否决）。

## Data Model

```text
QualityTier（enum，model/AudioQuality.ets）
  MAX = 0            // 最高：最高可用档，含 Hi-Res/杜比升级（无固定 qn）
  Q192K = 30280
  Q132K = 30232
  Q64K = 30216
  // 工具：fromStored(n)（非法值回落 MAX）、label(tier)、tierOfTrackId(id)（写回映射，30250/30251→MAX）

AudioTrack（class，model/AudioQuality.ets）
  id: number        // B 站 qn 码；flac/dolby 解析时赋 30251/30250；durl 兜底轨道 id=0
  bandwidth: number // bps，档位排序/最高档选择依据（durl 轨道为 0）
  urls: string[]    // 直链候选（baseUrl + backupUrl，沿袭 mcdn 过滤）

音轨来源（string 字面量约定，PlayerController）
  'dash' | 'durl' | 'local'

存储键（Constants.ets → AppStore preferences）
  KEY_WIFI_AUDIO_QUALITY: number     // QualityTier 值；-1 = 未初始化（迁移哨兵）
  KEY_CELLULAR_AUDIO_QUALITY: number // 同上
  KEY_PREFER_LOW_BITRATE: [移除常量] // 旧键值迁移读取一次后弃用
```

**状态流**：init（迁移→注册网络监听）→ playIndex（按网络取默认档→解析音轨→记录状态→emitUi）→ 面板/自动换流（setQualityTier→更新状态→emitUi）→ UI（syncFrom 读取渲染）。

## Contracts & Interfaces

```text
model/AudioQuality.ets
  enum QualityTier { MAX=0, Q192K=30280, Q132K=30232, Q64K=30216 }
  class AudioTrack { id: number; bandwidth: number; urls: string[] }
  QualityTier.fromStored(n: number): QualityTier          // 非法→MAX
  QualityTier.label(tier: QualityTier): string            // '最高'|'192K'|'132K'|'64K'
  QualityTier.tierOfTrackId(id: number): QualityTier      // 30216→Q64K 30232→Q132K 30280→Q192K；30250/30251/未知→MAX
  trackLabel(id: number): string                          // 30251→'Hi-Res' 30250→'杜比' 30280→'192K' 30232→'132K' 30216→'64K'

service/NetUtil.ets（扩展）
  static async isWifi(): Promise<boolean>                 // 既有
  static watchStableNetworkType(cb: (isWifi: boolean) => void): void
    // createNetConnection + register；默认网络承载类型二值变化→3s 防抖→cb(最新类型)；
    // 注册/事件异常静默 hilog 警告，不影响既有 isWifi

service/BiliService.ets（重构取流段）
  static async fetchDashAudioTracks(bvid: string, cid: number): Promise<AudioTrack[]>
    // playurl?bvid&cid&qn=16&fnver=0&fnval=4048&fourk=0
    // dash.audio[] 全量（id/bandwidth/baseUrl+backupUrl，mcdn 过滤）+ flac 节点(→30251) + dolby 节点(→30250)
    // 按 bandwidth 降序去重（同 id 保留高带宽）
  static pickAudioTrack(tracks: AudioTrack[], tier: QualityTier): AudioTrack
    // 纯函数回落算法（见 Research & Decisions）；空列表抛错
  static async resolveAudioTrack(bvid: string, cid: number, tier: QualityTier): Promise<AudioTrack>
    // fetchDashAudioTracks 失败→原参数重试一次→仍失败 fetchDurlCandidates 包装为 id=0 轨道
  // [移除] fetchDashAudioCandidates(bvid, cid, preferLowBitrate) / resolveAudioUrl(bvid, preferLowBitrate)
  //        / resolveAudioUrlFromCid(bvid, cid, preferLowBitrate) 的布尔参数签名

service/PlayerController.ets（扩展）
  // 广播状态（emitUi 供 syncFrom 读取）
  availableTracks: AudioTrack[]          // 当前曲目可用音轨（dash 轨道；durl/local 为空数组）
  currentQualityCode: number             // 实际生效 qn 码（durl=0/local=0）
  currentTrackSource: string             // 'dash'|'durl'|'local'
  // 行为
  async setQualityTier(tier: QualityTier, writeBack: boolean): Promise<void>
    // 守卫：source==='dash' 且非 isPreparing，否则静默跳过+Logger
    // 换流保进度（loadToken 并发模型）+ 失败回滚保持原流
    // writeBack=true（面板手动）：按 NetUtil.isWifi() 写 KEY_WIFI/CELLULAR_AUDIO_QUALITY
    // writeBack=false（网络自动换档）：不写（默认值本就是目标）
  private async applyDefaultTierForNetwork(): Promise<void>
    // 网络监听回调：source==='dash' 且非 isPreparing → setQualityTier(当前网络默认档, false)

pages/SettingsPage.ets（扩展）
  // 新增「音质」分组（播放设置之后、省流量设置之前）：
  //   Wi-Fi 默认音质 / 蜂窝默认音质 两行，副标题显示 QualityTier.label(当前值)
  //   未登录（BiliSession.isLogged()===false）时分组尾部提示行 + 选择器仅显示「最高」「64K」两项（隐藏 132K/192K）
  //   bindSheet 档位选择面板（单 sheet + qualityEditTarget: 'wifi'|'cellular'）
  // [移除] preferLowBitrate @State、开关行及其读写

pages/PlayerOverlay.ets（扩展）
  // 控制按钮行新增音质入口（图标按钮，样式同倍速/模式/睡眠入口）
  // showQuality @State + qualityPanel() 面板：
  //   dash 源：列出 availableTracks（trackLabel）+ 当前档高亮；点选→setQualityTier(tierOfTrackId(id), true)
  //   local 源：显示「本地缓存」占位；durl 源：显示「默认（当前不可用）」占位；均无可选项
  //   面板仅列实际下发音轨，不支持/不可用的音质不显示
  // syncFrom 增量同步三个音质状态字段
```

**不改动契约**：AppStore.getNumber/putNumber、AudioPlayer 全部公开方法、MediaSession、SleepTimerController、MiniPlayer、KEY_DATA_SAVER（省流量模式）与 KEY_WIFI_ONLY_DOWNLOAD（仅 Wi-Fi 播放）读写链路。
