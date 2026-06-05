---
name: commit
description: 通过分析暂存区更改，生成 Conventional Commits 风格的提交信息。当用户需要提交代码、编写提交信息时使用。
---

# Commit Skill

当用户要求你提交代码变更时使用本 skill。按以下步骤产生清晰、规范的 commit。

## 何时使用

- 用户说提交代码、commit 一下、创建提交等
- 用户要求你为已暂存的变更编写 commit message

## 步骤

### 1. 暂存文件

使用 `git add` 暂存相关文件。如果不确定包含哪些文件，先询问用户。常见用法：

- `git add <file1> <file2>` — 添加特定文件
- `git add -A` 或 `git add .` — 添加所有变更（当用户说提交全部时使用）
- 如果用户要求只提交文件的部分内容，使用 `git add -p <file>` 交互式暂存

### 2. 获取暂存区变更

先获取暂存区文件列表：

```bash
git diff --staged --name-status
```

- 如果暂存区为空，输出「暂存区无变更，提交终止」并停止

再逐文件查看具体改动：

```bash
git diff --staged -- <file>
```

### 3. 构建提交信息

```text
<type>: <description>

[可选的 body]

[可选的 footer]
```

#### 语言选择

获取最新一条历史提交信息：

```bash
git log -1 --format="%s"
```

- 若该提交使用中文，则本次提交信息使用中文
- 若无历史提交或该提交使用英文，则本次提交信息使用英文
- 若使用英文提交，在执行提交命令之前，先告知用户对应的中文提交信息

#### 构建 subject（必选，type + description）

**type** — 从**使用方视角**判断本次变更的实质影响（核心问题：这个仓库被使用时，产出是什么？本次变更对产出做了什么？）

- `feat`：为仓库的**核心产出**新增能力或内容（如 skills 仓库新增/更新 SKILL.md、dotfiles 仓库新增配置）
- `fix`：修复核心产出的错误、缺陷或逻辑问题
- `perf`：优化核心产出的性能或质量，不影响功能
- `refactor`：重构但不改变对外行为（如调整内部结构、拆分文件）
- `style`：不影响内容的格式调整（空格、换行、缩进）
- `test`：新增或修改测试
- `chore`：不直接影响核心产出的维护性操作（依赖、脚本、配置）
- `docs`：仅对**说明书类内容**（README、使用指南、注释）的变更，**且该变更不改变仓库的核心产出**
- `build`：影响构建系统或外部依赖的变更（如打包配置、依赖管理、构建脚本）
- `ci`：持续集成配置文件和脚本的变更（如 GitHub Actions、Jenkins、流水线配置）

**描述**：

- 祈使句，首字母小写（英文），不以句号结尾
- 描述做了什么

#### 构建 body 和 footer

仅在以下情况添加：

- 用户明确要求（如写详细点、加上 body 等）
- 变更包含破坏性变化（diff 中包含函数签名变更、删除接口、修改配置默认值等）——此时必须包含 `BREAKING CHANGE` footer

**body 格式**：

- 空一行与 subject 分隔
- 描述**为什么做**（变更原因、之前的问题、影响范围）
- 句子正常以句号结尾

**footer 格式**：

- `BREAKING CHANGE: <描述>`
- 其他 `token: 内容`，如 `Closes #123`

### 4. 输出提交信息、等待确认并执行提交

向用户展示完整的提交消息，**经用户确认后**根据内容结构执行对应命令：

- **仅有 subject（无 body 和 footer）**

  ```bash
  GIT_EDITOR=true git commit -m "<subject>"
  ```

- **有 subject 和 body（无 footer）**

  ```bash
  GIT_EDITOR=true git commit -m "<subject>" -m "<body>"
  ```

- **三者齐全（subject + body + footer）**

  ```bash
  GIT_EDITOR=true git commit -m "<subject>" -m "<body>" -m "<footer>"
  ```

### 5. 验证

执行 `git --no-pager log --oneline -n 3` 确认提交已经在最新位置。
如果用户还要求推送，可以继续执行 `GIT_EDITOR=true git push`。

## 最佳实践

- 主题行控制在 72 字符以内
- 主题行末尾不要加句号
- 用正文解释动机和与之前行为的区别
- 每次提交只包含一个逻辑变更，不要混合无关改动
