# bugfix

直接修复/小改动登记（不走 SDD 的），按发生顺序编号，不带日期。

## 1. 日志导出文件名加时间戳

- 问题：LogPage 导出日志固定建议名 `biliradio_log.txt`（`Constants.LOG_FILE_NAME`），多次导出易同名覆盖或混淆，需手动改名归档
- 修复：导出建议名改为 `biliradio_log_YYYYMMDD_HHmmss.txt`（`LogPage.exportFileStamp()` 生成，基础名仍引用 `Constants.LOG_FILE_NAME` 单一来源）
- 边界：仅改导出建议名（用户在系统保存框仍可改）；`Logger` 沙箱内滚动日志文件名不变（`Logger.ets` 引用同一常量，固定名滚动写入）

## 2. 存量弃用警告清理（登记待办，未实施）

- 问题：全项目约 92 条 ArkTS 弃用警告（UIContext 改造前的全局/静态 UI API 旧写法），纯警告不影响构建产物与运行
- 分布：`promptAction.showToast` 37 处 / `getContext(this)` 21 处 / `AlertDialog.show` 15 处 / `matchMediaSync` 1 处（Index.ets:38）/ AVSession 相关 3 条（ContentType/CONTENT_TYPE_MUSIC/get）
- 替换映射：showToast → `this.getUIContext().getPromptAction().showToast()`；AlertDialog.show → `this.getUIContext().showAlertDialog()`；getContext(this) → `this.getUIContext().getHostContext()`；matchMediaSync → `this.getUIContext().getMediaQuery().matchMediaSync()`；AVSession 3 条替换写法以本机 SDK `.d.ts` 为准
- 状态：已实施；21 处 getContext 经用户批准统一改新建 service/AppContext 进程级持有者（EntryAbility.onCreate 注入，偏离原 getHostContext 映射），顺带消除 5 处 as 断言；showToast/AlertDialog/matchMediaSync/componentSnapshot.get 按登记映射；AudioPlayer 删 content 字段行

## 3. APP cursor 端点字段改版致剧集行时长角标消失

- 现象：订阅剧集行视频时长角标不显示（用户报告）；与充电角标注释无关（另一 UI 块，结构完好）
- 根因：B 站 `app.bilibili.com/x/v2/space/archive/cursor` 接口改版——条目 `length` 由秒数/时长串改为**空字符串**，时长迁至 `duration` 字段（PC 复刻签名探针实测：`length=""`、`duration=2369`，响应新增 `translated_title`/`publish_time_text` 等字段佐证升版）；`parseVlistRecords` 只读 `length`，空串解析得 0，角标条件 `duration > 0` 不成立
- 修复：`parseVlistRecords` 中 `length` 解析为 0 时以 `rec['duration']` 兜底（`entry/src/main/ets/service/BiliService.ets`）；Web vlist `length` 时长串解析路径不受影响
- 登记：字段形态发现补录 `BILI_API.md` §3.5，端点表（§1.1）同步注记
