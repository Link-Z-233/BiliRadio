# Git 提交规范（git-committing）

> 任何 commit/push 前必读。签名材料防护全貌见 docs/SECURITY.md；轮次行为规则见 AGENTS.md「Git 提交」。

## 一、提交时机与前置检查

- **提交前自查三件套**：`git status`（无意外文件混入）、`git diff` / `git diff --cached`（改动与意图一致）、`git log --oneline -10`（信息风格对齐近史）
- **构建前置**：涉及 `.ets` 改动的批次须 `devecocli build` 绿后再提交；纯 md/docs 轮次免构建
- **未完成不提交**：实施中的轮次要么完成验证后提交，要么回滚；不提交半途而废的中间态
- **失败不无限重试**：构建/钩子失败修根因后**新建提交**；禁止 amend 失败提交、force-push、`--no-verify` 跳钩子、改 git config 绕过

## 二、提交粒度

- 默认**按轮次一提交**（repo 先例：每个 spec 轮次独立提交）
- 单文件混多关切时按最大公共轮次归组，不为拆 hunks 引入风险；多关切大合并提交有先例（工程重构 + V2 迁移 + debt-cleanup 合并提交），用户指定合并即合并
- 纯 docs 修正（typo/断链）可单独小提交，不必绑定轮次

## 三、提交信息

### 标题行

格式：`<type>: <版本-轮次>（<主题>）`

- **type**：feat / fix / docs / refactor / chore
- **版本-轮次**：spec 轮次名（如 `v0.5-part5-play-anomaly`）；docs-only、bugfix 直修等无轮次场景可省略此段
- **主题**：一句话概括做了什么；双主线合并提交用「+」串联两个主题

### 正文

- 要点列表，每块改动一行，写清「做了什么 + 关键机制/根因」
- 同类小项合并一行以「等」收尾
- **不入提交信息**：验证结论与待验登记（VR-*）、文件级明细（git diff 自查）、日期时间戳（时间由 git 历史承载）

### 范例

```
feat: v0.4.0-Part1（浮层视觉重设计 + UX 修复轮）

- QueueDrawer 泛化为 GlassSheet 通用玻璃浮层容器，队列/历史共用，历史面板迁离系统 bindSheet
- UX 修复 12 项：收起键命中区、MiniPlayer 返回闪现、音质三档矩阵、历史多选、账号头像、关于页重写（含内容截断修复）等
- debug 冷启动恢复前移 Index；spec 目录归档重命名，附 Part1 工件与 Part2 双轮规划
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
