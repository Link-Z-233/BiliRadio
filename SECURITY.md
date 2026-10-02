# 安全说明

## 报告安全漏洞

如果你发现 BiliRadio 存在安全漏洞，请通过邮件联系维护者，不要直接在公开 Issue 中披露细节。

## 重要提示

- 请勿在公开 Issue、Pull Request 或评论中直接粘贴你的真实 B 站 Cookie（SESSDATA、bili_jct、DedeUserID 等）、签名口令或其他敏感凭据。
- 本仓库不包含任何签名凭据（证书、口令、签名材料），构建所需的签名配置请参考 `build-profile.json5.example`，或使用 DevEco Studio 的自动 debug 签名。

## 签名材料提交拦截（pre-commit 钩子）

- 仓库配有 `.git/hooks/pre-commit` 钩子：提交时检测根 `build-profile.json5` 的暂存内容，命中签名材料特征（`certpath` / `storeFile` / `storePassword` / `keyPassword` / `material` / `.ohos/config`）即拒绝提交。
- 签名材料只允许存放于被 `.gitignore` 忽略的外置文件（`signing.local.json5` / `build-profile.local.json5`），由 `hvigorfile.ts` 构建时动态加载，详见 README.md「签名与证书隔离」章节。
- **钩子重建**：`.git/hooks/` 目录不随代码传播，`git clone` 不会带钩子。重新克隆仓库后，需按 README.md「签名与证书隔离」章节中提供的脚本内容重建 `.git/hooks/pre-commit` 并添加可执行权限（`chmod +x`），否则提交拦截保护不生效。

## 敏感信息范围

本项目涉及的需要妥善保护的敏感信息包括（但不限于）：

- B 站登录 Cookie（SESSDATA / bili_jct / DedeUserID）
- 应用签名证书与口令（.p12 / .cer / .p7b 及 keyPassword / storePassword）
- 任何访问令牌或 API 密钥

如发现上述信息被误提交，请立即联系维护者处理。