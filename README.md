# agent-skills

## 安装

```bash
npx skills add https://github.com/serosme/agent-skills.git -g -a opencode -y
```

## 更新

```bash
npx skills update -g -y
```

## 技能

- **commit** — 分析暂存区变更，生成符合规范的提交信息和 `git commit` 命令
- **markdown-lint** — 修改 Markdown 后检测格式并自动修复，无法修复的逐条报告；未安装则跳过并告知
- **spring-openfeign-client** — 基于 Spring Cloud OpenFeign 封装第三方 REST API，涵盖响应解包、Mock 切换、异常映射和可选认证
- **spring-processor** — 在 Spring 工程中使用 Processor + Context + Handler 模式编排多步骤业务操作
- **write-agents-md** — 按「约束 + 决策点」定位创建、精简或审查项目的 AGENTS.md
- **write-skills** — 按统一规范创建、重构和审查 Agent Skills

## 其他

[i-have-adhd](https://github.com/ayghri/i-have-adhd)

```bash
npx skills add ayghri/i-have-adhd -g -a opencode -y
```
