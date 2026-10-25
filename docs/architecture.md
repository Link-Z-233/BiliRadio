# 项目结构与实现方式（architecture）

> BiliRadio 架构总览。每轮必读行为规则见 AGENTS.md；V2 迁移批次记录见 agents/v2-migration-roadmap.md。

## 技术基线

- 单模块 HarmonyOS NEXT 应用（ArkTS/ArkUI），`compatibleSdkVersion = 26.0.0`（build-profile.json5）
- 零第三方依赖（entry/oh-package.json5 `dependencies` 为空），全部平台 Kit + 自研
- 状态管理已整体迁 V2（见「状态管理现状」节）

## 源码结构

源码全在 `entry/src/main/ets/`，共 49 个 .ets：

```
entry/src/main/ets/
├── entryability/            应用入口
├── entrybackupability/      备份恢复扩展
├── pages/                   页面（7）
├── component/               共用 UI（8）
├── service/                 业务服务与基础设施（26）
└── model/                   数据模型（6）
```

### pages/

| 文件 | 职责 |
|------|------|
| `Index.ets` | 唯一 `@Entry` 单页壳：五层 z 序挂载、debug 冷启动恢复 |
| `HomePage.ets` | 首页订阅源列表（新集徽标 / 长按进排序编辑态拖拽调序 / 左滑删除 / 空态） |
| `SourcePage.ets` | 订阅源详情（剧集列表 / 多选 / 刷新 / fav 入队 stamp 与归属回填） |
| `PlayerOverlay.ets` | 播放浮层（封面取色 / 音质档位 / 倍速） |
| `SettingsPage.ets` | 设置页（账号 / 播放 / 外观 / 订阅管理导出导入 / 历史与日志入口 / 关于） |
| `LogPage.ets` | 日志页（L2 层；导出 / 清空 / 分类过滤） |
| `AddSubscriptionSheet.ets` | 添加订阅面板（链接识别 / UID / UP / 合集 / 收藏夹） |

### component/

| 文件 | 职责 |
|------|------|
| `GlassSheet.ets` | 通用玻璃浮层容器（队列 / 历史面板共用） |
| `MiniPlayer.ets` | 悬浮迷你播放条（L1 胶囊） |
| `QueueSheet.ets` | 队列面板内容（多选 / 左滑删除 / 清除已播） |
| `HistorySheet.ets` | 播放历史面板内容（多选 / 已看完标记） |
| `CoverThumb.ets` | 封面缩略图（无封面显示耳机占位） |
| `SettingsGroup.ets` | 设置分组容器 |
| `SettingsRow.ets` | 设置行（图标 / 标题 / 开关 / 箭头） |
| `SelectCheckbox.ets` | 多选行首勾选框（宽度 / 透明度随激活态） |

### service/（按职责域分组）

**播控链**

| 文件 | 职责 |
|------|------|
| `PlayerController.ets` | 播控中枢（播放 / 队列 / 订阅收藏编排 / 队列移除联动取消收藏拦截与确认回调；零装饰器广播） |
| `AudioPlayer.ets` | media.AVPlayer 音频播放封装 |
| `MediaSession.ets` | avSession 系统播控（锁屏 / 控制中心）+ 后台长驻任务 |
| `SleepTimerController.ets` | 睡眠定时（定时暂停 / 播完暂停） |

**B 站 API 链**

| 文件 | 职责 |
|------|------|
| `BiliService.ets` | B 站 API 网关（全部端点、取流、音质解析；API 知识查 BILI_NOTES.md） |
| `BiliSession.ets` | 登录会话（cookie 持有 / 校验） |
| `AppSigner.ets` | APP 签名（TV appkey MD5 键序，UP 投稿取链） |
| `WbiSigner.ets` | WBI 签名（polymer 合集/追更接口鉴权） |
| `LinkResolver.ets` | B 站链接识别与短链解析 |
| `QrCode.ets` | 登录二维码生成（Nayuki 库 MIT 移植） |
| `CoverUrl.ets` | CDN 封面尺寸后缀工具 |
| `NetUtil.ets` | 网络状态探测（connection） |

**存储链**

| 文件 | 职责 |
|------|------|
| `AppStore.ets` | preferences 持久化封装（`KEY_*` 偏好） |
| `SecureStore.ets` | asset 安全存储（登录凭据） |
| `SubscriptionStore.ets` | 订阅源列表文件存储（加载 / 保存 / 逐源刷新 / 导出 cacheDir / 导入去重合并） |
| `HistoryMapper.ets` | 本地历史 ↔ B 站历史条目映射（云端同步预留边界，零网络调用） |

**UI / 系统支撑**

| 文件 | 职责 |
|------|------|
| `Appearance.ets` | 主题外观（强调色 / 深浅色模式设置与解析） |
| `CoverPalette.ets` | 播放页封面取色（palette-glow 光晕 / palette-bg 背景渐变） |
| `GripDetector.ets` | 握持手势检测（驱动胶囊侧别） |
| `Logger.ets` | 日志（hilog + 沙箱滚动文件 + 导出） |
| `V2State.ets` | V2 全局键基础设施（AppStorageV2 包装类） |
| `SelectLogic.ets` | 多选共享逻辑（源页 / 队列 / 历史三处共用） |
| `BackHandler.ets` | 返回链统一入口（逐层关闭浮层；首页编辑态句柄最前消费） |
| `Constants.ets` | 唯一常量真相源（存储键 / AppStorage 键 / 令牌 / 魔法数字） |
| `AppContext.ets` | UIAbilityContext 全局持有 |
| `FileUtil.ets` | 公共文件读写工具（含用户文件 URI 分块读取） |

### model/

| 文件 | 职责 |
|------|------|
| `BiliVideo.ets` | 视频条目（`@ObservedV2`，多分P 经 audio 分P 页兼容；`folderOwnerMid` 收藏夹主人归属） |
| `AudioQuality.ets` | 音质档位枚举（QualityTier）+ AudioTrack 音轨 + 静态映射工具 |
| `PlayHistoryItem.ets` | 播放历史条目（progress/duration 秒；-1 已看完） |
| `Subscription.ets` | 订阅源（四类源统一为定期拉取剧集列表的播客频道；fav 源含 `folderOwnerMid/folderOwnerName` 归属字段） |
| `Season.ets` | 合集 / 剧集元数据 |
| `FavFolder.ets` | 收藏夹元数据 |

## 模块依赖与边界

### 边界契约

| 模块 | 职责 | 允许依赖 | 禁止依赖 |
|---|---|---|---|
| `model/` | 纯数据类（无逻辑、无状态观测） | model/ 内部、内建类型 | service/、pages/、component/ |
| `service/` | 业务逻辑/B 站 API/存储/播控（单例范式 `X.getInstance()`） | model/、service/ 内部（含 `Constants`） | pages/（反向）、component/（反向） |
| `pages/` | 页面组装与交互 | service/、model/、component/、pages/ 内部 | — |
| `component/` | 可复用 UI | model/、`Constants`、service/ 单例（见耦合点）、component/ 内部 | pages/ |
| `service/Constants.ets` | 唯一常量真相源（存储键/AppStorage 键/令牌/色值/超时/页大小） | 内建类型（零 import） | 任何业务模块（防循环） |

全量 import 审计（engineering-refactor）：反向依赖零命中；`Constants` 零业务 import；model/ 零外部依赖（仅 model 内部：`PlayHistoryItem`/`Subscription` → `BiliVideo`）。

### 已知耦合点（登记，不拆分）

| 耦合点 | 现状 | 处理 |
|---|---|---|
| `MiniPlayer`/`QueueSheet` 直接持有 `PlayerController`/`AppStore` 单例 | 单例范式的组成部分（组件直调服务），非反向依赖、不属违规 | 不拆 |
| `PlayerController`（播控+队列+订阅+收藏） | 上帝对象候选 | 登记不拆分；拆分方案列远期 |
| `BiliService`（全部 B 站 API，约 1800 行） | 职责单一（B 站 API 网关），体量大但内聚 | 登记不拆分；文件拆分列远期 |
| `SettingsPage`（1400+ 行） | 页面体量大（分组+多面板） | 登记不拆分；远期可按面板抽组件 |

### 契约执行约定

- 新代码必须落位正确模块：数据类 → `model/`、业务逻辑 → `service/`、可复用 UI → `component/`、页面组装 → `pages/`
- 新增常量一律入 `Constants`（唯一真相源），禁止散落字面量
- 审计脚本口径（供复查）：`service → pages|component` 命中即违规；`Constants.ets` 出现业务 import 即违规

## 导航与五层 z 序

- 唯一 `@Entry`：`Index`（`main_pages.json` 注册）；`Navigation` + `NavPathStack` 仅存 `sourcePage` 单路由（`router_map.json`）
- 五层 z 序（高层物理覆盖低层）：

| 层 | 内容 | 实现 |
|----|------|------|
| L1 | 导航首页 + 胶囊（MiniPlayer） | Navigation |
| L2 | 设置层 + 日志层 | Stack 条件渲染（去路由） |
| L3 | 播放浮层 PlayerOverlay | Stack 条件渲染（非 `bindContentCover`——KI-5：ModalPage 渲染管线在 API 24 平板断裂） |
| L4 | 历史面板 | Index 单一挂载 GlassSheet（入口在设置页） |
| L5 | 队列面板 | Index 单一挂载 GlassSheet（非系统 sheet） |

- 返回链统一 `BackHandler.dismissOverlaysForBack` 逐层关闭（系统返回仅达 Index @Entry）

## 状态管理现状

- **V2 迁移整体完结**：模型层 6 类 `@ObservedV2`+`@Trace`；7 页面 + 挂键组件（SettingsRow/MiniPlayer/QueueSheet 等）全部 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；CoverThumb/SettingsGroup 免迁（`@Prop`-only）
- **`PlayerController` 零装饰器纯类**：手动 `subscribe`/`emitUi` 广播 + 版本计数，消费方（MiniPlayer/QueueSheet/PlayerOverlay/SettingsPage）`syncFrom` 拷贝进 `@Local`，代际无关
- **双轨存储**：`AS_*` 瞬态键经 `V2State.ets` 包装类（BoolState/NumState/StrState）走 `AppStorageV2.connect`，读写一律 `.value`，同 key 共享实例天然双向；`KEY_*` 持久化走 `AppStore`（preferences）。键清单集中在 `Constants.ets`
- **单例统一范式**：`X.getInstance()`（见 `Constants.ets` 文件头注释）
- **维度说明**：V2 仅覆盖「状态管理」一个维度，不等于整体重构；路由重构/服务拆分与 V1/V2 正交
- 行为规则（新代码代际规则、V2 边界 4 规则）见 AGENTS.md「状态管理」节；不可变模型数组 `@State` 持有 `@ObservedV2` 实例实测正常（批次 1），批次决策与实测细节见 agents/v2-migration-roadmap.md

## 资源与配置

| 路径 | 作用 |
|------|------|
| `build-profile.json5` | 构建配置（compatibleSdkVersion 26.0.0、签名配置） |
| `oh-package.json5` / `entry/oh-package.json5` | 包管理（零依赖） |
| `hvigorfile.ts` / `code-linter.json5` | 构建脚本 / linter 配置 |
| `signing.local.json5` | 本地签名（不入 git，见 docs/SECURITY.md） |
| `AppScope/app.json5` | 应用级配置（bundleName / 版本号） |
| `entry/src/main/module.json5` | 模块清单（权限 / routerMap / mainPages） |
| `resources/base/element/` | color.json（令牌色）/ float.json / string.json |
| `resources/base/media/` | 图标与图片资源 |
| `resources/base/profile/` | main_pages.json（页面注册）/ router_map.json（路由表）/ backup_config.json（备份声明） |

## 文档分工索引

| 想查什么 | 去哪 |
|---------|------|
| 每轮行为规则（协作/编码/构建/提交） | AGENTS.md |
| V2 迁移批次决策与实测 | docs/agents/v2-migration-roadmap.md |
| B 站 API 端点/字段/风控 | BILI_NOTES.md |
| 已知问题/登记/恢复线索 | docs/PROJECT_NOTES.md |
| 令牌豁免登记 | docs/token-exemptions.md |
| 签名与提交安全 | docs/SECURITY.md |
| 验证流程与经验追加 | docs/agents/verifying.md |
| 历轮 spec/plan/tasks 工件 | spec/（feature.json 指向活跃目录） |
