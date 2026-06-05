#!/bin/bash
# 将当前内核树编译的模块安装到 rootfs（须先 build-kernel.sh）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ROOTFS="${1:-${OUT_DIR}/rootfs}"
[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./scripts/setup-kernel.sh"
[[ -d "${ROOTFS}" ]] || die "rootfs 不存在: ${ROOTFS}（先 build-debian-rootfs.sh）"
[[ -f "${OUT_DIR}/kernel/Image" ]] || die "请先 ./scripts/build-kernel.sh"

setup_cross_compile
JOBS="$(job_count)"
ARCH=arm64
KMAKE=(make -C "${KERNEL_DIR}" -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}")

KERNEL_RELEASE="$("${KMAKE[@]}" -s kernelrelease)"
info "安装内核模块 ${KERNEL_RELEASE} -> ${ROOTFS}/lib/modules/"

"${KMAKE[@]}" modules
rm -rf "${ROOTFS}/lib/modules"
INSTALL_MOD_STRIP=1 "${KMAKE[@]}" INSTALL_MOD_PATH="${ROOTFS}" modules_install

info "模块已安装（共 $(find "${ROOTFS}/lib/modules/${KERNEL_RELEASE}" -name '*.ko*' | wc -l) 个 .ko）"
echo "${KERNEL_RELEASE}"
