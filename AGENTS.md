# AGENTS.md

## 构建与运行

- **构建**：`devecocli build`（需安装 DevEco Studio；SDK 在 `D:\Program Files\Huawei\DevEco Studio\sdk`）
- **运行**：`devecocli run --skip-build`（构建成功后）
- **静态检查**（`.ets` 快速预检）：`arkts_check` — 本轮编辑的所有 `.ets` 文件一次性传入，通过后再 `devecocli build`
- **无测试套件**：devDependencies 有 `@ohos/hypium` / `@ohos/hamock` 但无测试文件

## 签名（关键）

签名材料**绝不入 git**，三层防护：

1. `build-profile.json5` 基线 `signingConfigs: []`
2. 签名放 `signing.local.json5`（`*.local.json5` 被 gitignore），构建时 `hvigorfile.ts` 动态加载
3. `.githooks/pre-commit` 拦截含签名关键词的暂存内容

钩子首次构建自动安装（`git config core.hooksPath .githooks`）。克隆后需先提交：`git config core.hooksPath .githooks`。DevEco 自动签名会写入 `build-profile.json5`，提交前须移至 `signing.local.json5`。详见 `SECURITY.md`。

## 架构

单模块 HarmonyOS NEXT 应用（ArkTS/ArkUI），源码全在 `entry/src/main/ets/`：

- **pages/** — `Index.ets`（唯一 `@Entry`、单页壳）、`HomePage`、`PlayerOverlay`、`SourcePage`、`SettingsPage`、`AddSubscriptionSheet`
- **service/** — 业务单例：`PlayerController`（播控）、`BiliService`（B 站 API）、`BiliSession`（登录）、`MediaSession`（锁屏/控中心）、`AudioPlayer`、`LinkResolver`、`WbiSigner`、`SleepTimerController`、`AppStore`（持久化）、`SecureStore`、`SubscriptionStore`、`Constants`
- **model/** — 数据类：`BiliVideo`、`AudioQuality`（音质档位）、`PlayHistoryItem`、`Subscription`、`Season`、`FavFolder`
- **component/** — 共用 UI：`MiniPlayer`、`QueueDrawer`、`QueueSheet`、`CoverThumb`、`LogSheet`

### 导航

- **唯一 `@Entry`**：`Index`（`main_pages.json` 注册）
- 其余页面走 `Navigation` + `NavPathStack`；路由在 `router_map.json`（`sourcePage`、`settingsPage`）
- 播放层是 **Stack 条件渲染**（非 `bindContentCover`——KI-5：ModalPage 渲染管线在 API 24 平板断裂）
- 队列是底部弹出面板（Stack 条件渲染，非系统 sheet）

### 状态管理

- 全局 V1 `@Component` + `@State`/`@StorageLink`/`@StorageProp`/`@Watch`
- AppStorage 键集中在 `Constants.ets`（`AS_*` 瞬态 UI，`KEY_*` 持久化偏好）
- 单例统一范式：`X.getInstance()`（见 `Constants.ets` 文件头注释）

## 编码原则（Ponytail）

编码前**必须调用 `skill` 工具加载 `ponytail`**（每轮、任何涉及代码的任务），以获得完整梯子与规则。
若 skill 不可用，回退以下精简原则：

- 动笔前逐级自问：要不要做？库里有？标准库/平台/依赖覆盖？一行够？以上不行才写最少能跑的代码
- Bug 修根因不修表象；不建没人要的抽象；删优于加，无聊优于聪明；最短可用 diff 胜出
- 刻意简化确知天花板时留 `ponytail:` 注释标注天花板与升级路径
- 不可偷懒：理解问题、输入校验、防数据丢失、安全、无障碍、真机校准、明确要求的事项
- **本项目追加**：代码零注释（除非明确要求 / `ponytail:` 标注）、输出零废话、不加 emoji、不加前置/后置解释；写完即停
- **Constants.ets 是唯一真相源**：所有魔法数字、存储键、AppStorage 键、色值、超时值只在此定义，禁止他处重复
- **禁 `any`/`unknown`/`as` 类型断言**——ArkTS 严格模式
- **B 站 API 坑**：APP 端点（`BILI_APP_ARCHIVE_URL`）须 BiliDroid UA（在 `Constants`），非浏览器 cookie；Web 端点须 WBI 签名（`WbiSigner`）；`@ohos.net.http` 的 `maxRedirects: 0` 是「零配额」而非「禁重定向」——短链解析用 `@kit.RemoteCommunicationKit` rcp + `autoRedirect`
- **`[API24-COMPAT]` 守卫**：保护 API 26 接口在 API 24 设备可用——`compatibleSdkVersion` 升至 26 前勿删

## 已知问题（PROJECT_NOTES.md）

- **KI-3**：首页订阅列表与播放队列的左滑删除未实现（播放历史已完成）
- **KI-6**：睡眠定时未经真机验证
- **KI-7**：链接识别边缘情况（B3–B8）——BV 优先级遮蔽复合 URL，裸数字一律当 UID
- **DIS-1**：首页下拉刷新已禁用（代码以注释保留，标记 `[DISABLED 2026-10]`）

## Spec

`spec/` 存放功能规格与 UX 反馈轮次，`spec/feature.json` 指向当前活跃目录。实现功能前先查阅对应 spec。

## 参考项目

- `D:/UsersFiles/Link_Z/Desktop/Code/PiliPlus` — Flutter 哔哩哔哩客户端（音质档位/设置交互参考）
- `D:/UsersFiles/Link_Z/Desktop/Code/bili/biliRelay` — B 站 API 取流参考（QUALITY_MAP / fnval）

## Pre-commit

`.githooks/pre-commit` 扫描暂存的 `build-profile.json5` 中签名关键词（`certpath`、`storeFile`、`storePassword`、`keyPassword`、`keyAlias`、`material`、`.ohos/config`），命中即拒绝提交。勿绕过。
