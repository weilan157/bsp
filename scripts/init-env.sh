#!/bin/bash
# 安装 U-Boot 编译所需主机依赖（含交叉工具链）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

info "检查主机架构..."
[[ "$(uname -m)" == "x86_64" ]] || die "仅支持 x86_64 主机编译"

PACKAGES=(
	build-essential
	bc
	bison
	flex
	device-tree-compiler
	python2
	python3
	python3-pip
	libssl-dev
	git
	rsync
	curl
	pkg-config
	gcc-aarch64-linux-gnu
	debootstrap
	qemu-user-static
	binfmt-support
	debian-archive-keyring
	e2fsprogs
)

info "安装 apt 依赖（需要 sudo）..."
if command -v sudo >/dev/null 2>&1; then
	sudo apt-get update
	sudo apt-get install -y "${PACKAGES[@]}"
else
	apt-get update
	apt-get install -y "${PACKAGES[@]}"
fi

if [[ -x /usr/bin/python2 ]] && [[ ! -e /usr/bin/python ]]; then
	sudo ln -sf /usr/bin/python2 /usr/bin/python 2>/dev/null || ln -sf /usr/bin/python2 /usr/bin/python
	info "已创建 /usr/bin/python -> python2"
fi

if ! command -v dtc >/dev/null 2>&1; then
	die "dtc 未安装成功"
fi
if ! command -v python2 >/dev/null 2>&1 && [[ ! -x "${LOCAL_BIN}/python2" ]]; then
	warn "系统无 python2，build-uboot.sh 会使用 .local/bin/python2 包装"
fi
if ! command -v "${CROSS_COMPILE_PREFIX}gcc" >/dev/null 2>&1; then
	die "交叉编译器 ${CROSS_COMPILE_PREFIX}gcc 未安装成功"
fi
if ! command -v debootstrap >/dev/null 2>&1; then
	die "debootstrap 未安装成功"
fi

info "主机环境就绪"
