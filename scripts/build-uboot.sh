#!/bin/bash
# 编译 RK3576 U-Boot（GitHub u-boot + rkbin，不调用 SDK）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ -d "${UBOOT_DIR}" ]] || die "请先运行 ./scripts/setup-sources.sh"
[[ -d "${RKBIN_DIR}" ]] || die "缺少 rkbin，请先运行 ./scripts/setup-sources.sh"

ensure_python2_wrapper
setup_cross_compile

cd "${UBOOT_DIR}"

info "清理旧产物..."
make distclean 2>/dev/null || true

info "编译 RK3576 U-Boot (board=${UBOOT_BOARD}, --spl-new)..."
# make.sh 默认查找 SDK prebuilts 内 linaro 链；显式传入 CROSS_COMPILE 以使用 apt 或 config.env TOOLCHAIN_BIN
./make.sh "${UBOOT_BOARD}" --spl-new "CROSS_COMPILE=${CROSS_COMPILE}"

info "编译完成，主要产物:"
ls -la "${UBOOT_DIR}"/uboot.img "${UBOOT_DIR}"/trust.img 2>/dev/null || true
ls -la "${UBOOT_DIR}"/rk3576_spl_loader_*.bin "${UBOOT_DIR}"/rk3576_idblock_*.img 2>/dev/null || true
