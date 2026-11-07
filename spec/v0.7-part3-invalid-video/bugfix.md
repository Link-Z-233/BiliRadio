# bugfix — v0.7-part3-invalid-video 活跃目录

## 1. WbiSigner 签名漏 wts（真机 Web 链恒 -403 疑似根因）

- 现象：真机 WBI 端点（`x/space/wbi/arc/search`、`x/space/wbi/acc/info`）恒 `-403`（BILI_NOTES §3.2/§3.4，曾归因「网络出口级风控/设备指纹评分」）。
- 根因：`WbiSigner.signParams` 旧实现 `md5(query + mixinKey)` 的 query **不含 wts**（算完签名才把 wts 追加到请求），签名必然无效；标准算法 wts 须参与排序与 MD5（官方 PC 客户端逆向确认，`../../bili/API/接口调用学习笔记.md` §4；PC 探针按标准算法同出口直接放行，BILI_NOTES §3.12）。
- 修复：`signParams` 将 `wts` 并入参数参与排序/过滤/MD5，返回 `query（含 wts）+ '&w_rid='`；调用方零改动（6 处调用点接口不变）。
- 影响面：`arc/search`/`acc/info` 预期解封；polymer/series 系端点不校验或宽容 w_rid（带旧无效签名也恒可用），修复不受影响。
- 验证：`devecocli check arkts` 通过、`devecocli build` 成功；**真机解封与否待验证**（需真机登录态刷新订阅观察 Web 链返回码，验证后补录 BILI_NOTES §3.12）。
