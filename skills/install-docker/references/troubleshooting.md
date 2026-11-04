# 安装故障排查

读取时机：安装命令失败、Docker 服务未启动、`docker` 命令报错，
或用户后续自行拉取镜像失败时。

按现象定位，先保留原始报错再动手恢复；每一步都说明预期结果。
改配置、卸载软件包、删除数据目录前，先取得用户确认。

## 先收集信息

```bash
cat /etc/os-release
uname -m
systemctl status docker --no-pager
sudo journalctl -u docker -n 100 --no-pager
docker info
```

预期：能判断 Debian 版本与 codename、systemd 是否可用、守护进程是否运行、
是否有明确的报错行。

## 目标机缺少 curl

现象：脚本输出 `curl not found: install curl first` 并退出。

处理：

- Debian：`sudo apt-get update && sudo apt-get install -y curl`。
- 安装 `curl` 后重新执行本技能脚本；不改用 `wget` 等替换下载方式，
  脚本行为变化需要用户确认。

## get.docker.com 无法下载

现象：`curl: (35) Recv failure`、`(28) Operation timed out`、
`(6) Could not resolve host`，脚本立即退出且没有 apt 输出。

处理：

- 立即停止，不重试、不换源、不换下载地址、不找替代安装脚本。
- 报告出错的命令、目标地址 `https://get.docker.com` 和 curl 原始报错。
- 说明这是网络层问题（DNS、代理、防火墙或运营商阻断），请用户先恢复对
  `get.docker.com` 的访问；恢复后重新执行本技能脚本。

## 镜像站缺包或 404

现象：`E: The repository '.../docker-ce/linux/debian bookworm Release' does
not have a Release file`，或 `404 Not Found`，常见于镜像未同步 Debian
新 codename。

处理：

```bash
. /etc/os-release
base=https://mirrors.ustc.edu.cn/docker-ce/linux/debian
curl -sSI "$base/dists/$VERSION_CODENAME/Release" | head -n 1
```

- 返回 `200`：镜像有该版本，检查 apt 报错中的具体包或组件。
- 返回 `404`：镜像未同步该 codename，停止并报告 Debian 版本与 codename；
  是否换源由用户决定，不自动切换。

## GPG 或签名错误

现象：`NO_PUBKEY`、`The following signatures couldn't be verified`，
或 `signed-by` 相关错误。

处理：

- 确认 `/etc/apt/keyrings/docker.asc` 存在且非空；
  文件缺失多为镜像未同步 gpg，停止并报告，是否换源由用户决定。
- 不用 `--allow-unauthenticated` 等方式绕过校验，
  这会把安装变成不可信来源。

## 包管理冲突或锁占用

现象：`Could not get lock /var/lib/dpkg/lock-frontend`、
`dpkg was interrupted`、`conflicts with`。

处理：

- 锁占用：确认没有其他 apt/dpkg 进程在运行，等待结束后重试；
  不删除锁文件。
- 依赖冲突：记录冲突包名，不擅自 purge 现有包或移除仓库；
  报告用户并确认后再处理。
- `dpkg was interrupted` 时按提示执行 `sudo dpkg --configure -a`，
  完成后重新执行安装脚本。

## 服务未启动或启动后立即退出

处理：

- 先判断 systemd 是否可用：`systemctl is-system-running`。
  容器、部分 VPS 和未启用 systemd 的 WSL 返回 `offline` 或命令失败。
- WSL2 启用 systemd：在 `/etc/wsl.conf` 写入

  ```ini
  [boot]
  systemd=true
  ```

  然后 `wsl --shutdown` 重新进入发行版。
- systemd 可用但服务未启动：`sudo systemctl enable --now docker`，
  再用 `systemctl status docker` 确认。
- 启动即退出：读取 `journalctl -u docker -n 100`，常见原因有
  `/var/lib/docker` 残留或权限异常、containerd 版本冲突、磁盘满、
  端口被占用、cgroup 配置不兼容。
- 无 systemd 时手动运行 `dockerd` 只能做临时验证，不作为正式方案；
  报告时说明未验证的自动启动能力。

## docker 命令权限错误

现象：`permission denied while trying to connect to the Docker daemon socket`。

处理：

- 查组：`getent group docker`；查用户：`id -nG <user>`。
- 脚本只给 `SUDO_USER` 加组。经 `wsl -u root`、`su -` 或 root 直接执行时
  `SUDO_USER` 为空，需要手动执行：`sudo usermod -aG docker <user>`。
- 生效方式：重新登录、开新终端、`newgrp docker`；
  WSL 用 `wsl --terminate <发行版>` 重启发行版。
- 说明 `docker` 组权限等价 root 的风险，不把加组当作权限问题的默认解法。

## 拉取镜像失败（用户后续使用）

本技能不通过拉取镜像验证安装，`docker info` 正常即视为安装成功。
此节只用于用户后续自行 `docker pull` 或 `docker run` 时的网络问题。

现象：`docker pull <镜像>` 或 `docker run <镜像>` 报 TLS handshake timeout、
`dial tcp ... i/o timeout`、`pull access denied`。

处理：

- 先确认安装正常：`docker info` 有 Server 段，
  `systemctl is-active docker` 为 `active`。
- 归因为网络或 registry 问题，立即停止并报告原始报错；
  不重装、不换安装脚本、不修改 `daemon.json`、不改代理或 DNS。
- 请用户处理镜像拉取网络（registry 访问、代理或镜像加速）；
  用户明确提供可信加速地址并授权后，才另行配置并重启 docker。
- `docker info` 的 `Registry Mirrors` 段可验证既有配置是否生效。

## 重装或卸载

只在用户明确要求时执行，并说明会删除镜像与容器数据。

- Debian：

  ```bash
  sudo apt-get remove -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ```

- `/var/lib/docker`、`/var/lib/containerd`、`/etc/docker` 中的数据目录
  只在其明确同意后删除；删除后不可恢复。
- 重装前保留 `docker info` 输出，便于安装后对比版本与配置变化。
