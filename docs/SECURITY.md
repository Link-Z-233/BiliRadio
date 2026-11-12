# 安全说明

## 报告安全漏洞

如果你发现 BiliRadio 存在安全漏洞，请通过邮件联系维护者，不要直接在公开 Issue 中披露细节。

## 重要提示

- 请勿在公开 Issue、Pull Request 或评论中直接粘贴你的真实 B 站 Cookie（SESSDATA、bili_jct、DedeUserID 等）、签名口令或其他敏感凭据。
- 本仓库不包含任何签名凭据（证书、口令、签名材料），构建所需的签名配置参考下文「签名与证书隔离」的 `signing.local.json5` 格式，或使用 DevEco Studio 的自动 debug 签名。

## 签名与证书隔离

本仓库**不包含任何签名凭据**（证书、口令、签名材料），且通过两层机制保证签名材料**永不进入 git 历史**：

| 层 | 机制 | 位置 |
| --- | --- | --- |
| ① 基线 | 根 `build-profile.json5` 的 `signingConfigs` 恒为空数组（git 追踪文件，官方 FAQ 基线） | `build-profile.json5` |
| ② 外置通道 | 签名材料优先存放于被 `.gitignore` 忽略的本地文件，构建时由 `hvigorfile.ts` 动态加载（官方签名服务 FAQ「方式二」）；外置缺省时退回根文件内联材料保底（自动补 product 引用） | `signing.local.json5` / `build-profile.local.json5` |

### 恢复调试签名（交付后操作）

DevEco Studio 打开 BiliRadio → **File > Project Structure > Signing Configs** → 勾选 **Automatically generate signature**，为 `com.biliradio.app` 生成全新材料。DevEco 会把材料写入根 `build-profile.json5`——**提交前必须移出**，两条路径任选：

> **注意**：DevEco 自动签名只会把 `signingConfigs` 材料块写入根文件，**不会**给 `products` 补 `"signingConfig": "default"` 引用。`hvigorfile.ts` 已对此做保底：外置文件缺省时自动为内联材料补上 product 引用，构建照常出已签名包——「未检测到签名配置」仅在两个来源皆无时出现。内联材料可直接使用，但**提交前仍必须移出**（下方路径 A/B），避免签名材料进入 git 历史。

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

## 敏感信息范围

本项目涉及的需要妥善保护的敏感信息包括（但不限于）：

- B 站登录 Cookie（SESSDATA / bili_jct / DedeUserID）
- 应用签名证书与口令（.p12 / .cer / .p7b 及 keyPassword / storePassword）
- 任何访问令牌或 API 密钥
