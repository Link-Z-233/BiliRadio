# BiliRadio

> 🎨 **Vibecoding 作品** — 本项目完全由 AI 生成代码，开发者仅负责需求描述与测试迭代。个人学习/自用作品，与哔哩哔哩官方无关。

把 B 站视频当播客听的鸿蒙音频应用：只取声音，不亮屏幕。订阅 UP 主、收藏夹、合集、系列，新视频自动标 NEW，一键入队；亦可通过粘贴链接或 BV 号手动添加。

## 核心功能

- **订阅追更**：UP 主 / 收藏夹 / 合集 / 系列四类源，新视频自动标 NEW
- **即点即听**：粘贴链接或 BV 号，立即播放音频
- **随心播控**：倍速、随机循环、睡眠定时、断点续播
- **后台不断**：锁屏、控制中心、实况窗都能控制播放
- **听得讲究**：四档音质可选，深浅色主题随心换

## 参考项目

参考开源项目 [BiliMusic](https://github.com/taotie256/BiliMusic)（Apache 2.0）、[PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)（GPL-3.0）开发。

## 界面一览

无页签单栈结构：首页订阅流常驻，其余界面按需弹出或压栈。

| 界面 | 形态 | 作用 |
| ---- | ---- | ---- |
| 首页 | 主页 | 订阅源列表（新集徽标）+ MiniPlayer + 「⋯」更多菜单 |
| 播放层 | 全屏覆盖 | 封面、进度、完整播放控制；支持下滑退出 |
| 播放队列 | 底部面板 | 歌单管理：左滑删除、多选移除、清除已播 |
| 订阅源详情 | 压栈页 | 单个订阅全部视频，整源入队 |
| 设置 | 压栈页 | 登录、外观、播放历史、缓存清理、关于 |

## 技术栈

- **语言/框架**：ArkTS + ArkUI 声明式 UI，零第三方依赖
- **状态管理**：ArkUI V2（`@ObservedV2` + `@ComponentV2`）
- **音频播放**：`@kit.AVSessionKit` 媒体会话 + AVPlayer
- **后台能力**：后台持续任务（音频播放模式）
- **数据存储**：`preferences` + 本地 JSON 文件

## 运行环境

- DevEco Studio（HarmonyOS NEXT 版本）
- HarmonyOS NEXT（最低 7.0 / API 26）手机或模拟器
- 手机与电脑连接（数据线或无线调试）

## 怎么运行

1. 下载项目，用 DevEco Studio 打开根目录，等待依赖加载完成。
2. 连接手机（开启开发者模式/USB 调试）或启动模拟器。
3. 点击「运行 ▶」选择设备，等待编译并安装。
4. 若提示未配置签名（产出未签名包无法装真机），按 [SECURITY.md](docs/SECURITY.md) 的「签名与证书隔离」恢复调试签名后重试。

## 怎么用

1. 首页点「＋」添加订阅（UP 主 / 收藏夹 / 合集 / 系列，可粘链接或 ID）。
2. 订阅源有新视频标 `NEW`，进源详情可整源入队。
3. 想单听某个视频：在添加订阅面板直接粘链接或 BV 号——队列空时立即播放，播放中则追加不打断。
4. 去「设置」登录账号可同步个人收藏夹（支持一键登录/扫码）。
5. 锁屏后可在锁屏界面或实况窗继续控制播放。

## 项目结构（给想了解代码的人）

```
BiliRadio
├── AppScope/                 # 应用级配置（包名、版本、图标）
├── entry/                    # 主模块（所有代码都在这里）
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/        # 应用入口
│       │   ├── entrybackupability/  # 备份恢复扩展
│       │   ├── pages/               # 各页面（首页、播放层、订阅源详情、设置）
│       │   ├── service/             # 核心服务（音频播放、B站接口、媒体会话、存储）
│       │   ├── model/               # 数据模型
│       │   └── component/           # 通用组件（MiniPlayer、底部播放队列面板等）
│       └── resources/               # 图标、文案等资源
├── docs/                     # 活文档（架构总览、模块边界契约、已知问题等）
├── build-profile.json5       # 构建配置（signingConfigs 恒为空数组，git 追踪）
├── hvigorfile.ts             # 构建脚本（含外置签名动态加载）
└── oh-package.json5          # 依赖声明
```

每文件的职责、模块依赖方向、五层 z 序与状态管理详见 [docs/architecture.md](docs/architecture.md)。

## 常见问题

- **构建提示「未检测到签名配置」？** 说明签名材料既不在外置的 `signing.local.json5`，根 `build-profile.json5` 中也没有。用 DevEco Studio 自动生成 debug 签名（File > Project Structure > Signing Configs）后重新构建；或按 [SECURITY.md](docs/SECURITY.md) 的「签名与证书隔离」手动配置。
- **为什么不能登录/加载不出内容？** 本软件调用 B 站接口，需正常联网；部分接口可能因 B 站策略调整失效。

## 贡献指引

欢迎提交 Issue 或 Pull Request。注意：把签名材料写入根 `build-profile.json5` 的提交会被 pre-commit 钩子拒绝（钩子随仓库传播，详见 [SECURITY.md](docs/SECURITY.md)）；不要在 Issue/PR 中粘贴真实 Cookie 或签名口令。

## License

本项目采用 [Apache License 2.0](LICENSE)，基于 taotie256 的 BiliMusic（Apache 2.0）开发。
