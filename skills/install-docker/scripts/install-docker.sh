#!/usr/bin/env bash
# 在 Debian 上用官方 get.docker.com 脚本安装 Docker Engine，
# 软件包默认从 USTC 镜像下载；sudo 调用者会被加入 docker 组。
#
# 用法：
#   sudo bash install-docker.sh
#   sudo env DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce bash install-docker.sh
#
# 下载或安装阶段出现网络错误/超时即停止，由用户先处理网络，不换源重试。

set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "root required: sudo $0" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || { echo "curl not found: install curl first" >&2; exit 1; }

mirror_url="${DOWNLOAD_URL:-https://mirrors.ustc.edu.cn/docker-ce}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "Installing Docker Engine from mirror: $mirror_url"

if ! curl -fsSL https://get.docker.com -o "$work_dir/get-docker.sh"; then
    echo "network error: failed to download https://get.docker.com" >&2
    echo "fix network access first, then re-run this script; not continuing" >&2
    exit 1
fi

DOWNLOAD_URL="$mirror_url" sh "$work_dir/get-docker.sh"

if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER"
    echo "User $SUDO_USER added to docker group. Re-login or run: newgrp docker"
else
    echo "Running as root directly. No regular user added to docker group."
fi
