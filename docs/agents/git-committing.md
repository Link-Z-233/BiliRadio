# Git 提交规范（git-committing）

> 任何 commit/push 前必读。签名材料防护全貌见 docs/SECURITY.md；轮次行为规则见 AGENTS.md「Git 提交」。

## 一、提交时机与前置检查

- **提交前自查三件套**：`git status`（无意外文件混入）、`git diff` / `git diff --cached`（改动与意图一致）、`git log --oneline -10`（信息风格对齐近史）
- **构建前置**：涉及 `.ets` 改动的批次须 `devecocli build` 绿后再提交；纯 md/docs 轮次免构建
- **未完成不提交**：实施中的轮次要么完成验证后提交，要么回滚；不提交半途而废的中间态
- **失败不无限重试**：构建/钩子失败修根因后**新建提交**；禁止 amend 失败提交、force-push、`--no-verify` 跳钩子、改 git config 绕过

## 二、提交粒度

- 默认**按轮次一提交**（repo 先例：每个 spec 轮次独立提交）
- **bug 修复带 bug 前缀**：feat 提交正文中的 bug 修复条目以「bug:」前缀标示
- 单文件混多关切时按最大公共轮次归组，不为拆 hunks 引入风险；多关切大合并提交有先例（工程重构 + V2 迁移 + debt-cleanup 合并提交），用户指定合并即合并
- 纯 docs 修正（typo/断链）可单独小提交，不必绑定轮次

## 三、提交信息

- **简短**：正文每条一行、一句话量级，只说做了什么；机制/根因/细节由 spec 与 bugfix 工件承载，不入正文
- **不带组件名**：标题与正文不出现组件/文件/API/函数名，以功能与行为描述代替

### 标题行

格式：`<type>: <版本-轮次>（<主题>）`

- **type**：feat / fix / docs / refactor / chore
- **版本-轮次**：spec 轮次名（如 `v0.5-part5-play-anomaly`）；docs-only、bugfix 直修等无轮次场景可省略此段
- **主题**：一句话概括，多主题用「/」串联；bug 修复不进标题（正文 bug: 条目承载）

### 正文

- 按标题主题逐项展开，一主题一行；bug 修复条目以「bug: 」前缀列于主题条目之后；杂项一行「随附：」收尾
- **不入提交信息**：验证结论与待验登记（VR-*）、文件级明细（git diff 自查）、日期时间戳（时间由 git 历史承载）

### 范例

```
feat: v0.6-part3-sub-manage（订阅源管理：长按菜单/排序编辑态/导入导出分享）

- 长按弹菜单（置顶/排序/删除），置顶带补位动画
- 编辑态整行拖拽调序，把手即按即拖（长按触发已去除）
- 订阅导出经分享面板，导入去重合并并自动刷新
- bug: 修复非编辑态边缘长按误触拖拽
- bug: 修复队列分P 已播标记误扩到未听分P
- 随附：文档同步与实测补录
```

## 四、暂存纪律

- **只暂存意图内文件**：按路径显式 add；`git add -A` 前必须先 status 分辨每项来源，意外出现的目录/文件查清归属再决定
- **文档移动/重命名用 `git mv`**：保留历史可追溯（先例：文档体系重构整批 git mv）
- **删除已暂存移动/重命名的文件用 `git rm -f`**：普通 `git rm` 会对 staged rename 报错
- **签名检查**：提交前确认 `git check-ignore signing.local.json5` 有输出、status 无任何 signing/证书文件混入

## 五、签名材料绝不入 git

- 三层防护：`signing.local.json5`（.gitignore 隔离）、pre-commit 特征拦截（`.githooks` 随仓库传播，hvigorfile.ts 首次构建激活）、调试签名恢复流程
- pre-commit 拒绝时：把签名材料移回 `signing.local.json5`、根 `build-profile.json5` 的 `signingConfigs` 恢复空数组 `[]` 后重新提交
- 详见 docs/SECURITY.md

## 六、推送

- push 前确认远端指向与分支领先/落后态（`git remote -v`、`git status`）
- 远端有新提交先 pull 再 push，禁止 force-push 覆盖远端
