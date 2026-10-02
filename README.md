# BiliRadio

一个运行在鸿蒙（HarmonyOS NEXT）上的 B 站音频播客应用——长期定位是「收听我关注的内容」。当前版本由 [taotie256 的 BiliMusic](https://github.com/taotie256/BiliMusic)（Apache 2.0）复制创建，功能与其保持一致：把 B 站视频当成「播客/歌」来听，支持后台播放、锁屏/实况窗控制、收藏夹同步。

> BiliRadio 基于 taotie256 的 BiliMusic（Apache 2.0）开发，许可证原文见 [LICENSE](LICENSE)。
> 本软件是个人学习/自用作品，与哔哩哔哩官方无关。

## 与 BiliMusic 的关系

- BiliRadio 是从 BiliMusic 完整复制而来的**独立工程**（独立 bundleName `com.example.biliradio`，可与已安装的 BiliMusic 共存）。
- **当前功能与 BiliMusic 完全一致**，未做任何功能增删。
- 版本号从 1.0.0 重新起版，Git 历史全新开始。

## 路线图

- 🎙️ **播客化**：围绕「播放我关注的内容」演进——让关注列表成为收听源。
- 🎨 **界面风格重做**：打造 BiliRadio 自己的视觉语言（现沿用 BiliMusic 的沉浸光感界面）。

## 它能做什么

- 🎵 **当音乐播放**：输入 B 站视频链接或 BV 号，直接播放视频的音频，不用看画面。
- ▶️ **完整播放控制**：播放/暂停、上一首、下一首、随机播放、列表循环、倍速、拖动进度。
- 📃 **播放列表**：把你收藏或添加的视频排成歌单，切换歌曲时自动记住播放进度。
- ⭐ **歌曲源**：登录后同步 B 站收藏夹一键导入成歌单；也能按 UID 查某位 UP 主的公开合集，把合集视频批量生成歌单。
- 🔐 **登录 B 站**：支持「B站一键登录」（直接拉起 B 站 App 确认，无需扫码）、扫码登录、手动粘贴 Cookie 三种方式。
- 🔔 **后台与实况窗**：锁屏、控制中心、实况窗里都能看到正在播放的歌，直接控制播放，也能拖动进度条。
- 🗂️ **下载与缓存**：可把歌曲下载到本地离线播放、批量管理；临时播放缓存也会保留，下次播放更快，可一键清空。
- ✨ **沉浸光感界面**：播放时封面颜色透出、笼罩整个界面并随歌渐变；按钮半透明毛玻璃、进度条沉浸材质、文字智能反色，视觉随设备算力自适应。
- 🎨 **深浅色主题**：跟随系统 / 浅色 / 深色 三种外观，设置页一键切换，全局即时生效。

## 界面一览

应用底部有四个页签：

| 页签 | 作用 |
| ---- | ---- |
| 播放 | 正在播放的歌曲大图、进度、控制按钮 |
| 播放列表 | 管理当前歌单，添加/移除歌曲 |
| 歌曲源 | 个人收藏夹 / UP主合集 / 下载内容三个来源，可生成歌单或管理下载 |
| 设置 | 登录、外观（深浅色）、缓存清理等 |

## 技术栈

- **语言/框架**：ArkTS（HarmonyOS 的 TypeScript 方言）+ ArkUI 声明式 UI
- **音频播放**：`@kit.AVSessionKit` 媒体会话 + AVPlayer
- **空间化 UI**：`@kit.UIDesignKit`（HDS 页签 + 沉浸光感材质 + 点光源液态动效）
- **后台能力**：后台持续任务（音频播放模式）
- **数据存储**：`preferences` 轻量存储 + 本地 JSON 文件

## 运行环境

要编译、运行这个项目，你需要：

- 一台电脑，装好 **DevEco Studio**（HarmonyOS NEXT 版本）
- 一台 **HarmonyOS NEXT（API 26 及以上）** 的手机，或 DevEco Studio 自带的模拟器
- 手机和电脑连接（用数据线或无线调试）

## 怎么运行

1. 把整个项目文件夹下载到本地。
2. 打开 DevEco Studio，选择「打开项目」，选中本项目根目录。
3. 等 IDE 自动加载依赖（`oh_modules`）。
4. 用数据线连接手机并开启开发者模式/USB 调试，或在 IDE 里启动模拟器。
5. 点击工具栏的「运行 ▶」按钮，选择你的手机或模拟器，等待编译并安装。

未配置签名时，构建产出**未签名**的 debug 包（见下方「签名与证书隔离」）；需安装到真机时，先按下文恢复调试签名。

## 怎么用

1. 打开 App，在「播放」页或「播放列表」页粘贴一个 B 站视频链接（或 BV 号）。
2. 它会自动解析并开始播放音频。
3. 如果想同步收藏夹，去「设置」页登录 B 站账号（支持「B站一键登录」或扫码登录）。
4. 锁屏后，可以在锁屏界面或实况窗里继续控制播放。

## 签名与证书隔离

本仓库**不包含任何签名凭据**（证书、口令、签名材料），且通过三层机制保证签名材料**永不进入 git 历史**：

| 层 | 机制 | 位置 |
| --- | --- | --- |
| ① 基线 | 根 `build-profile.json5` 的 `signingConfigs` 恒为空数组（git 追踪文件，官方 FAQ 基线） | `build-profile.json5` |
| ② 外置通道 | 签名材料只存放于被 `.gitignore` 忽略的本地文件，构建时由 `hvigorfile.ts` 动态加载（官方签名服务 FAQ「方式二」） | `signing.local.json5` / `build-profile.local.json5` |
| ③ 提交拦截 | pre-commit 钩子检测根文件的暂存内容，命中签名材料特征即拒绝提交 | `.git/hooks/pre-commit` |

### 恢复调试签名（交付后操作）

DevEco Studio 打开 BiliRadio → **File > Project Structure > Signing Configs** → 勾选 **Automatically generate signature**，为 `com.example.biliradio` 生成全新材料。DevEco 会把材料写入根 `build-profile.json5`——**提交前必须移出**，两条路径任选：

- **路径 A（先试，零成本）**：把根文件中的 `signingConfigs` 材料块**剪切**到工程根目录的 `build-profile.local.json5`（保持 `"app": { "signingConfigs": [...] }` 结构），构建验证是否生效。此捷径在上游项目有实证，但**无官方文档背书**。
- **路径 B（保底，官方支持）**：把材料放入工程根目录的 `signing.local.json5`，格式与 `build-profile.local.json5` 相同：

  ```json5
  {
    "app": {
      "signingConfigs": [
        {
          "name": "default",
          "type": "HarmonyOS",
          "material": {
            "certpath": "<你的证书路径>",
            "keyAlias": "<KEY_ALIAS>",
            "keyPassword": "<KEY_PASSWORD>",
            "profile": "<PROFILE_PATH>",
            "signAlg": "SHA256withECDSA",
            "storeFile": "<STORE_PATH>",
            "storePassword": "<STORE_PASSWORD>"
          }
        }
      ]
    }
  }
  ```

  `hvigorfile.ts` 构建时会自动检测该文件：存在则注入签名配置（产物为已签名包）；不存在则不注入，构建照常成功（产物为未签名包）。

两个文件均被 `.gitignore` 的 `*.local.json5` 规则忽略，不会出现在 `git status` 中。根文件材料移走后（`signingConfigs` 恢复为 `[]`），提交即可正常进行。

### pre-commit 钩子（位置与重建方法）

钩子位于 `.git/hooks/pre-commit`，提交时检测根 `build-profile.json5` 的**暂存内容**是否含签名材料特征（`certpath` / `storeFile` / `storePassword` / `keyPassword` / `material` / `.ohos/config`），命中则以非零退出码拒绝提交并在 stderr 输出引导提示。

**注意**：`.git/hooks/` 不随代码传播（`git clone` 不会带钩子）。**重新克隆仓库后需手动重建**：将以下内容保存为 `.git/hooks/pre-commit`（LF 行尾），并执行 `chmod +x .git/hooks/pre-commit`（Windows 下用 Git Bash 执行）：

```sh
#!/bin/sh
# BiliRadio pre-commit hook — 证书隔离第 3 层：提交拦截（FR-013）
TARGET="build-profile.json5"
FEATURES='certpath|storeFile|storePassword|keyPassword|keyAlias|material|\.ohos[\\/]config'
if git diff --cached --name-only -- "$TARGET" | grep -q .; then
  if git show ":$TARGET" | grep -nEi "$FEATURES" >/dev/null 2>&1; then
    echo "[pre-commit] 拒绝提交：根 build-profile.json5 的暂存内容包含签名材料特征。" >&2
    echo "请把 signingConfigs 材料块移到 signing.local.json5（或 build-profile.local.json5），" >&2
    echo "将根文件 signingConfigs 恢复为空数组 [] 后重新提交。详见 README.md「签名与证书隔离」。" >&2
    exit 1
  fi
fi
exit 0
```

## 项目结构（给想了解代码的人）

```
BiliRadio
├── AppScope/                 # 应用级配置（包名、版本、图标）
├── entry/                    # 主模块（所有代码都在这里）
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/ # 应用入口
│       │   ├── pages/        # 各页面（播放、列表、收藏夹、设置）
│       │   ├── service/      # 核心服务（音频播放、B站接口、媒体会话、存储）
│       │   ├── model/        # 数据模型
│       │   └── component/    # 通用组件
│       └── resources/        # 图标、文案等资源
├── build-profile.json5       # 构建配置（signingConfigs 恒为空数组，git 追踪）
├── build-profile.json5.example  # 签名配置参考模板
├── hvigorfile.ts             # 构建脚本（含外置签名动态加载）
└── oh-package.json5          # 依赖声明
```

## 常见问题

- **为什么不能登录/加载不出内容？** 本软件调用的是 B 站接口，需要能正常联网；部分接口可能因 B 站策略调整而失效。
- **音频听不了？** 确认手机已联网，且视频本身有可播放的音频。
- **这不是官方 App，可能违反 B 站部分条款，请仅用于个人学习，勿用于商业用途。**

## 免责声明

本项目仅用于个人学习与自用，与哔哩哔哩无关。请勿将其用于任何商业或违规用途，相关风险由使用者自行承担。

## 贡献指引

欢迎提交 Issue 或 Pull Request。提交前请注意：

- 提交代码时会经过 pre-commit 钩子检查：把签名材料写入根 `build-profile.json5` 的提交会被直接拒绝。
- 不要在 Issue 或 PR 中粘贴真实 Cookie 或签名口令。

## License

本项目采用 [Apache License 2.0](LICENSE) 开源许可证，基于 taotie256 的 BiliMusic（Apache 2.0）开发。
