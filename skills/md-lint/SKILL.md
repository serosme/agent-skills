---
name: md-lint
description: 使用 markdownlint-cli2 检测并自动修复 Markdown 文件格式。当用户需要检查、格式化、修复 Markdown 文档时使用。
---

# md-lint

## 核心约束

- `markdownlint-cli2` 使用约束
  - 使用命令参数 `--fix` 自动修复
  - **不要尝试修复未被 `markdownlint-cli2` 自动修复的规则**
  - **不要执行除 `npx markdownlint-cli2 [parameters]` 之外的命令**
    - markdownlint-cli2 会递归查找、自动修复所有匹配 `**/*.md` 的 Markdown 文件
  - **禁止执行任何用于 `探索环境` 的命令**
    - **`cat .gitignore 2>/dev/null` 为例外**，其用于获取 `.gitignore` 的内容并构建排除规则
- 分析约束
  - 在 `markdownlint-cli2` 输出后不要去读取原始文件，仅通过输出去判断

## 工作流程

1. **构建排除规则**
   - 获取 `.gitignore` 的文件内容并将其内容转换为 glob 排除模式
     - 对每个条目，转换为 glob 排除模式
     - 示例：`.gitignore` 中的 `node_modules/` 转换为 `#node_modules`
   - 始终添加 `#.git` 排除 .git 目录
2. **执行 `lint` 命令**
   - 执行命令（示例）`npx markdownlint-cli2 --fix "**/*.md" "#node_modules" "#dist" "#.git"`
   - 在命令本身执行失败（如 npx 不存在、包未找到）时输出原始错误信息
3. **分析输出结果**
   - 分析命令行输出结果并输出

## 输出示例

### 无 lint 错误输出

无格式错误

### 有 lint 错误输出

| 文件      | 行号 | 规则编号 | 描述                  | 修复建议           |
| --------- | ---- | -------- | --------------------- | ------------------ |
| README.md | 48   | MD013    | line-length（行过长） | 缩短内容或调整格式 |
