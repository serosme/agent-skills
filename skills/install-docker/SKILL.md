---
name: install-docker
description: 在 Debian 主机（本机或 WSL）用官方脚本配合国内镜像安装 Docker Engine，把 sudo 用户加入 docker 组，并验证服务、版本与权限。当需要在 Debian 上安装 Docker、升级或重装 Docker、安装后 docker 命令报权限错误时使用。
---

# Docker Engine 安装（Debian + 国内镜像）

## 适用场景

### 目标

在具备 root 或 sudo 的 Debian 主机上，用官方 `get.docker.com` 脚本配合国内镜像
安装 Docker Engine（含 CLI、containerd、compose 与 buildx 插件），
把执行 sudo 的用户加入 `docker` 组，并验证服务、版本与权限。
支持本机 Debian 与 WSL 中的 Debian 两种执行位置。

### 适用

- 在 Debian 上首次安装 Docker Engine。
- 国内网络下官方源过慢或不可用，需要用 USTC 等镜像安装。
- 已安装 Docker，需要按同一脚本升级或重装。
- 安装后普通用户执行 `docker` 报 `permission denied`，需要加入 `docker` 组并验证。

### 不适用

- Windows 或 macOS 桌面上安装 Docker Desktop。
- 在 Debian 以外的发行版上安装：本技能只覆盖 Debian 的流程与镜像路径。
- 给其他机器安装：本技能只处理本机与 WSL。
- 已装好 Docker，只需配置镜像加速、`daemon.json`、存储驱动或日志轮转。
- 离线或内网无外网的主机：本技能依赖下载安装脚本和软件包。
- Kubernetes、Docker Swarm 初始化，或 compose 独立版（standalone）安装。

## 前置条件

### 必要输入

- 执行位置：本机 Debian，或 WSL 中的 Debian 发行版。
- 目标主机的 root 或 sudo 权限。
- Debian 版本（codename）；不确定时先读取 `/etc/os-release`。

### 必要环境

- Debian 版本在官方脚本支持范围内（buster、bullseye、bookworm、trixie）；
  架构为 x86_64、aarch64 等官方支持的架构。
- 目标机能访问 `get.docker.com` 与所选镜像站
  （默认 `https://mirrors.ustc.edu.cn/docker-ce`）；网络不可用时先由用户处理，
  本技能不做网络绕行。
- 目标机有 `bash` 与 `curl`；WSL 内路径按 WSL 视角书写（如 `/mnt/c/...`）。
- 有 systemd 时脚本会自动启用并启动 `docker.service`；
  WSL2 中的 Debian 需在 `/etc/wsl.conf` 中启用 systemd 才能自动启动守护进程。

### 参考文件

- 执行安装前必须读取 [scripts/install-docker.sh](scripts/install-docker.sh)：
  技能自带的安装脚本，默认使用 USTC 镜像，`DOWNLOAD_URL` 可覆盖镜像地址，
  缺少 `curl` 时提前报错；网络错误时直接退出。
- 安装失败、镜像缺包、服务未启动或 `docker` 权限未生效时，
  读取 [references/troubleshooting.md](references/troubleshooting.md)。

### 信息缺失处理

- 没给出执行位置：默认按本机 Debian 处理；实际不是 Debian 或 WSL 时停止并询问。
- Debian 版本不在支持范围或已停止维护：说明支持范围，询问是否换官方源、
  手动安装或升级系统，不擅自换成未知第三方源。
- 已有 Docker 且用户未说明是升级、重装还是跳过：先读取现有版本并询问，
  确认前不执行安装。
- 无法确认权限：先执行 `id -u`（0 即 root）与 `sudo -n true` 探测，不靠猜测。

## 执行步骤

### 步骤 1：确认主机与权限

- 操作：
  - 读取系统信息：`cat /etc/os-release` 确认是 Debian 及 codename，
    `uname -m` 确认架构；WSL 中同时确认是 WSL2。
  - 确认权限：`id -u`；非 root 时用 `sudo -n true` 探测免密 sudo，
    否则说明执行时需要输入密码。
  - 探测前置条件：`command -v curl`、`systemctl is-system-running`
    （容器与未启用 systemd 的 WSL 可能不可用）、`df -h /var` 留出数百 MB。
  - 检查是否已安装：`command -v docker`、`docker version`，记录现有版本。
- 完成标志：
  - 能说 Debian 版本与 codename、架构、权限方式、是否已有 Docker、systemd 是否可用。
  - 未满足的前置条件已停止，或已请用户确认替代方案。

### 步骤 2：执行安装

- 操作：
  - 本机 Debian：

    ```bash
    sudo bash scripts/install-docker.sh
    ```

  - WSL 中的 Debian：在 Windows 侧用
    `wsl -u root -d <发行版> -- bash <脚本路径>` 执行，
    路径按 WSL 内视角书写（如 `/mnt/c/...`）。
    用 `-u root` 时 `SUDO_USER` 为空，脚本不会加组；安装后手动执行
    `usermod -aG docker <WSL 默认用户>`，再用 `wsl --terminate <发行版>`
    让组变更生效。WSL 需为 WSL2 且已启用 systemd。
  - 默认镜像为 USTC；需要换源时用环境变量覆盖，例如
    `sudo env DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce bash scripts/install-docker.sh`。
  - 脚本下载官方安装脚本并执行 `apt` 安装，最后启用并启动
    `docker.service`；过程约 1–5 分钟，保留镜像地址、包版本与报错行。
  - WSL 下官方安装脚本会提示推荐 Docker Desktop 并暂停约 20 秒，
    属正常行为，等待其继续，不要中途中断。
  - 下载或安装阶段出现网络错误或超时，立即停止并按「异常处理」报告，
    不换源、不换下载地址、不找替代安装脚本。
  - 不用 `curl ... | sudo sh` 代替本脚本：本技能要求脚本以文件形式执行。
- 完成标志：
  - 安装命令退出码为 0，输出中没有未处理的 apt 报错。
  - 失败时已按 troubleshooting 分类处理，而不是盲目重复执行。

### 步骤 3：验证服务、版本与权限

- 操作：
  - 服务：`systemctl is-enabled docker`、`systemctl is-active docker`；
    没有 systemd 时按 troubleshooting 中的手动启动方式处理并记录。
  - 版本：`docker version --format '{{.Client.Version}} {{.Server.Version}}'`；
    插件：`docker compose version`、`docker buildx version`。
  - 安装验证：`docker info`，确认 Server 段可读（Server 版本、存储驱动）。
    安装是否成功以此为准，不拉取镜像做验证，避免受镜像仓库网络影响。
  - 组权限：`getent group docker`；确认目标用户在组内
    `id -nG <user> | tr ' ' '\n' | grep -x docker`。
    组变更只对新会话生效：提示 `newgrp docker` 或重新登录；WSL 用
    `wsl --terminate`。
- 完成标志：
  - 客户端与服务端版本都能读到，服务已启用并运行。
  - 目标用户已在 `docker` 组，或已明确说明需要重新登录。
  - `docker info` 的 Server 段正常，Server 版本非空。

### 步骤 4：清理并汇总

- 操作：
  - 确认脚本内部已清理下载的 `get-docker.sh`；如果手动复制过脚本，
    删除对应的临时文件。
  - 汇总安装结果、验证结果、未验证项与待确认项。
  - 说明镜像加速未配置；用户需要时提示这是另一项操作，本技能不代配。
- 完成标志：
  - 临时文件已清理，报告内容与验收项一致。

## 约束

### 行为边界

- 安装脚本只能以 root 执行；不绕过权限、不修改 sudoers、不把脚本改成免 sudo。
- 只在 Debian 上执行；WSL 未启用 systemd 时不强行安装，
  而是说明原因与启用方式。
- 镜像源只用官方 `https://download.docker.com` 与公开镜像
  （USTC、Aliyun、AzureChinaCloud）；不写入未知第三方源，
  不改系统全局代理或 DNS。
- `docker` 组权限等价于 root：加组前说明影响，只为用户认可的用户加组。
- 已有 Docker 且用户未确认时，不重装、不卸载、不改动
  `/etc/apt/sources.list.d/docker.list` 等仓库配置。
- 不执行全系统升级（`apt upgrade`），不修改与安装无关的配置。
- 生产环境安装会变更软件包与服务：未经用户确认不执行。
- 默认不改脚本行为；用户要求换源、换用户或加校验时，改动后说明差异。
- 出现网络错误或超时时只报告、不处理网络：不重试、不换镜像源、
  不换下载地址、不下载替代安装脚本，等用户修复网络后重新执行。

### 异常处理

- 网络错误或超时（连接被重置、解析失败、i/o timeout、TLS 超时等）：
  立即停止，不重试、不换源、不换下载地址；报告出错的命令、目标地址与
  原始报错，请用户先处理网络，处理完成后再重新执行本技能。
- 镜像站返回 404 或缺包（网络已连通）：停止并报告 Debian 版本与 codename，
  是否换源由用户决定，不自动切换。
- 安装命令失败：保留报错原文，按 troubleshooting 分类，不隐藏失败。
- 服务无法启动：区分 systemd 不可用、端口或 cgroup 配置等原因，
  先按 troubleshooting 处理；无法解决时停止并报告已完成步骤。
- 权限未生效：属于会话问题，提示重新登录或 `newgrp`，不重复安装。
- 需要用户确认才能继续时（重装、换源、生产主机、非受支持版本），
  停止并列出待确认项，不擅自决定。

## 输出与验收

### 交付内容

- 安装摘要：执行位置（本机或 WSL）、Debian 版本与架构、镜像源、
  Docker 客户端与服务端版本、compose/buildx 版本、`docker.service` 状态、
  `docker` 组用户、`docker info` 的 Server 段结果。
- 执行的关键命令与输出；失败时附报错原文；网络错误时说明已停止等待用户处理。
- 未验证项与待确认项，例如需要重新登录、镜像拉取受限、
  未在目标环境实际运行的部分。
- 若改动过脚本，列出改动内容与原因；默认不改脚本行为。

### 验收标准

- Debian 版本在官方脚本支持范围内；不支持的情况已说明并停止。
- 安装命令退出码为 0；`docker version` 同时能读到 Client 与 Server 版本。
- `systemctl is-active docker` 为 `active`；无 systemd 时已说明替代启动方式
  及其结果。
- 目标用户在 `docker` 组内，且已提示生效方式（重新登录、`newgrp` 或 WSL 重启）；
  WSL 场景需重启发行版后用默认用户验证组权限。
- 出现网络错误或超时时，已停止并报告原始报错，未自行重试、换源或
  改用替代下载地址。
- 镜像与下载地址为 HTTPS 官方或公开镜像地址，报告中无密码、私钥或未知第三方源。
- `docker info` 的 Server 段可读、Server 版本非空；未通过拉取镜像验证，
  也未因镜像网络问题改动配置。
- 目标机上的临时安装脚本已清理。
- 未确认的重装、换源、生产环境安装没有被擅自执行。

## 示例

### 本机 Debian 12 首次安装

场景：

> 帮我在这台 Debian 12 机器上装 Docker，国内网络。

关键预期行为：

- 先读取 `/etc/os-release` 确认 Debian 12（bookworm）、`x86_64`，
  `id -u` 非 0 但 sudo 可用，没有既有 Docker。
- 执行 `sudo bash scripts/install-docker.sh`；输出显示从
  `https://mirrors.ustc.edu.cn/docker-ce` 下载。
- 验证：`docker version` 有 Server 版本，`systemctl is-active docker` 为
  `active`，`id -nG` 含 `docker`，`docker info` 的 Server 段正常。
- 报告版本与状态，并提示新会话或 `newgrp docker` 后生效。

预期反馈：

> 安装完成：Debian 12（bookworm）、x86_64、USTC 镜像；
> Docker 客户端与服务端版本均可读，`docker.service` 为 `active`；
> 用户已加入 `docker` 组，`docker info` 的 Server 段正常；
> 新会话或 `newgrp docker` 后免 sudo 使用。

### WSL2 中的 Debian 安装

场景：

> 在这台 Windows 的 WSL2 Debian 里装 Docker。

关键预期行为：

- 先确认是 WSL2、发行版为 Debian，且已启用 systemd；未启用时说明
  `/etc/wsl.conf` 的 `[boot] systemd=true` 配置与 `wsl --shutdown` 重启方式。
- 在 Windows 侧执行
  `wsl -u root -d <发行版> -- bash /mnt/c/.../install-docker.sh`；
  安装完成后手动执行 `usermod -aG docker <WSL 默认用户>`，并用
  `wsl --terminate` 重启发行版。
- 重启后验证 `docker version`、`id -nG` 含 `docker`、
  `docker info` 的 Server 段正常，并在报告中说明加组是手动完成的。

### 已有 Docker 的主机被要求重装

场景：

> 这台 Debian 机器之前装过 Docker，按这个脚本再装一遍。

关键预期行为：

- 先 `docker version`、`docker info` 读取现有版本，并询问是升级、重装还是跳过。
- 用户确认前不执行脚本；确认后说明脚本会覆盖 Docker 仓库配置并可能重装包。
- 安装后重新验证服务、版本、组权限与 `docker info`，并对比版本变化。
