# 命令与规则细节

本文件说明 `markdownlint-cli2` 的调用形式、范围与忽略规则、输出解读，
以及常见规则的处理倾向。执行流程、边界与验收标准以 `SKILL.md` 为准。

以下行为均在本机 `markdownlint-cli2 v0.23.3` 上实测确认；
其他版本可能不同，以本机 `--version` 与 `--help` 为准。

## 可用的调用形式

只使用本机已存在的安装：

- `markdownlint-cli2`：已全局安装或位于 PATH。
- `pnpm exec markdownlint-cli2`：目标仓库本地已安装（`node_modules/.bin`）。
- `node_modules/.bin/markdownlint-cli2`（Windows 为 `.cmd`）：直接调用本地可执行文件。

禁止使用（会触发下载或改写环境）：

- `npx markdownlint-cli2`、`pnpm dlx markdownlint-cli2`、`npm exec markdownlint-cli2`
- `npm install` / `pnpm add` / `yarn add`
- `brew install` / `choco install` / `scoop install` / `winget install`

## 常用命令形态

```bash
markdownlint-cli2 --version                    # 探测是否可用
markdownlint-cli2 --no-globs "docs/**/*.md"    # 只查显式范围
markdownlint-cli2 --no-globs "**/*.md" "#node_modules/**" "#.agents/**"
markdownlint-cli2 --config .markdownlint-cli2.jsonc --no-globs "docs/a.md"
markdownlint-cli2 --no-globs --fix "docs/a.md" # 自动修复，只改 Markdown 文件
printf '# t\n' | markdownlint-cli2 --no-globs - # 检查 stdin，不落盘
```

枚举要检查的文件（Git 天然跳过被忽略的路径）：

```bash
git status --short -- '*.md'                   # 本次改动
git ls-files -co --exclude-standard -- '*.md'  # 已跟踪 + 未跟踪但未被忽略
```

- 记得给 glob 加引号，避免被 shell 提前展开。
- `git diff --name-only` 默认只列**未暂存**改动；
  要同时覆盖已暂存与未暂存，用 `git status --short` 或 `git diff HEAD --name-only`。
- 用 `-` 检查标准输入时也要配 `--no-globs`，
  否则标准输入会叠加在配置 `globs` 之后一起检查。
- 输出中每条问题形如 `文件:行:列 MDxxx 描述`，报告时原样带上规则与位置。

## 范围与忽略（工具不会替你做）

实测：`markdownlint-cli2` **不读 `.gitignore`，也没有内置忽略**。
在同时含 `.git/`、`node_modules/`、`dist/`、`.agents/skills/` 的目录里执行
`markdownlint-cli2 "**/*.md"`，这 9 个文件全部被检查，只有手写文件是预期的。
范围排除必须自己做。

默认排除（除非用户明确要求检查）：

- 依赖：`node_modules/`、`vendor/`、`bower_components/`
- 构建与缓存：`dist/`、`build/`、`out/`、`target/`、`coverage/`、
  `.next/`、`.nuxt/`、`.output/`、`.cache/`
- Agent 技能安装副本：`.agents/skills/`、`.opencode/skill/`、
  `.claude/skills/`、`.dsh/skills/`
- 版本库与忽略路径：`.git/`、`.gitignore` 与 `.git/info/exclude` 命中的路径

实现方式：

- 用 Git 枚举候选文件，天然排除被忽略的路径，不依赖工具支持。
- 排除项写成负向 glob，用 `#` 而不是 `!`（部分 shell 会解析 `!`）：
  `"#node_modules/**"`、`"#.agents/**"`、`"#dist/**"`。
- **命令行 glob 与配置 `globs` 是叠加关系，不是覆盖**：
  仓库配置了 `"globs": ["**/*.md"]` 时执行 `markdownlint-cli2 "docs/a.md"`，
  `Finding:` 会同时列出 `docs/a.md` 和配置里的 glob，范围并没有收窄。
  要真正收窄范围，必须加 `--no-globs`。

## 配置发现

- 配置只在**当前工作目录**查找，不向父目录回溯：
  从 `docs/` 里运行检查，仓库根的 `.markdownlint-cli2.jsonc` 不会生效，
  规则退回默认值（实测；`.markdownlint.json` 同样如此）。
- 所以要么在配置所在目录执行，要么显式写 `--config <路径>`。
- 配置里的 `globs` / `ignores` 要尊重，不修改；
  需要临时收窄范围时用 `--no-globs` 与命令行负向 glob，
  不要为了结果变绿去改配置或加忽略。

## 输出解读与退出码

- `Finding:` 列出本次生效的全部 glob（含来自配置的）。
- `Linting: N files` 是**实际检查的文件数**，核对范围看这一行。
- `Summary: N issues in M files` 的 `M` 是**有问题的文件数**：
  全部干净时同样显示 `0 issues in 0 files`，不能据此判断是否扫描到文件。
- 退出码（实测）：
  - `0`：没有发现问题；也可能是**一个文件都没匹配到**。
  - `1`：存在 lint 问题。
  - `2`：工具或配置出错，例如配置文件无法解析，
    或既没有配置 `globs` 又没有命令行 glob（这种情况会打印用法）。
- 不要只用退出码下结论，结合 `Linting:` 与输出原文判断。

## 链接与共享副本

- 实测：`--fix` 会穿透符号链接与 Windows junction，直接改写**链接目标**；
  对被链接的路径执行修复，等于改了链接另一端。
- 技能安装目录（如 `.agents/skills/`）常是安装工具写入的副本或链接，
  修复它们等于改动源仓库或全局安装，默认排除。
- 运行 `--fix` 后用 `git status --short -- '*.md'` 核对，
  只允许出现计划内的文件。注意 `git diff --name-only` 默认只列未暂存改动，
  已暂存（`git add` 过）的文件会漏掉，核对范围不要用它。

## 常见规则的处理倾向

`--fix` 能处理的机械问题交给 `--fix`，需要判断的留给用户。
规则编号与描述以工具输出为准；下表只是判断倾向，不是规则全集。

| 规则    | 倾向   | 常见现象                               |
| ------- | ------ | -------------------------------------- |
| `MD009` | 自动修 | 行尾多余空格                           |
| `MD010` | 自动修 | 硬制表符                               |
| `MD012` | 自动修 | 连续多个空行                           |
| `MD022` | 自动修 | 标题前后缺空行                         |
| `MD031` | 自动修 | 围栏代码块前后缺空行                   |
| `MD032` | 自动修 | 列表前后缺空行                         |
| `MD047` | 自动修 | 文件末尾不是单个换行                   |
| `MD048` | 自动修 | 围栏符号风格不统一（` ``` ` 与 `~~~`） |
| `MD049` | 自动修 | 强调符号风格不统一                     |
| `MD050` | 自动修 | 加粗符号风格不统一                     |
| `MD013` | 报告   | 行长度超标；拆行会改变语义或渲染       |
| `MD024` | 报告   | 重复标题；可能是有意的结构             |
| `MD025` | 报告   | 多个一级标题；属于结构问题             |
| `MD033` | 报告   | 行内 HTML；换行、占位符等场景可能必要  |
| `MD036` | 报告   | 用强调当标题；要判断是否该改成标题     |
| `MD040` | 报告   | 围栏代码块缺语言标注；需要选定语言     |
| `MD041` | 报告   | 首行不是一级标题；取决于文件类型       |

没有仓库配置时规则用默认值：默认 `MD013` 行长上限 80，
CJK 表格和长 URL 很容易触发，这类既有问题与本次改动无关，报告时要分开。

## 反馈模板

未安装时：

> 本机未安装 markdownlint-cli2，本次跳过 Markdown 格式检查，也没有尝试安装。
> 需要的话你可以自行安装后再让我复检，我不会代为执行。

存在需要用户决定的问题时：

> 自动修复已完成；`{文件}:{行}:{列}` 仍有 `{规则}`：{描述}。
> {为什么不宜自动改}，请确认怎么处理。

跳过机器生成范围时：

> 本次只检查了 {文件数} 个手写文件（`Linting: {N} files`）。
> {目录} 是机器生成/安装内容，按默认范围跳过；需要检查请明确告诉我。

没有可检查文件时：

> 本次没有需要检查的 Markdown 文件：{原因}。
> 没有执行格式检查，也没有改动任何文件。

工具报错（不是「有问题」）时：

> `markdownlint-cli2` 执行失败（退出码 {码}）：{原始错误}。
> 未修改任何文件，也没有改动配置；请确认环境或配置后再跑。
