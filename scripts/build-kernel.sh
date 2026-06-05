#!/bin/bash
# 编译 GitHub kernel + 泰山派设备树

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./scripts/setup-kernel.sh"

setup_cross_compile
JOBS="$(job_count)"
ARCH=arm64
KMAKE=(make -C "${KERNEL_DIR}" -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}")
FRAGMENTS="$(kernel_defconfig_fragments)"

if [[ "${TSPI_VENDOR_KERNEL_CONFIG}" == "y" ]] || [[ -n "${KERNEL_EXTRA_FRAGMENTS}" ]] || \
	[[ -n "${TSPI_KERNEL_CONFIG_SOURCE:-}" ]]; then
	"${SCRIPT_DIR}/sync-kernel-config.sh"
fi

info "配置内核: ${KERNEL_DEFCONFIG} ${FRAGMENTS}"
if [[ "${TSPI_VENDOR_KERNEL_CONFIG}" == "y" ]]; then
	info "已启用 TSPI_VENDOR_KERNEL_CONFIG（PANFROST / Mali Bifrost 等）"
fi
# shellcheck disable=SC2086
"${KMAKE[@]}" "${KERNEL_DEFCONFIG}" ${FRAGMENTS}

DTS_TARGET="rockchip/${KERNEL_DTS_NAME}.dtb"
info "编译 Image 与 ${DTS_TARGET} (jobs=${JOBS})..."
"${KMAKE[@]}" Image
"${KMAKE[@]}" "${DTS_TARGET}"

mkdir -p "${OUT_DIR}/kernel"
install -m 644 "${KERNEL_DIR}/arch/arm64/boot/Image" "${OUT_DIR}/kernel/Image"
install -m 644 "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/${KERNEL_DTS_NAME}.dtb" \
	"${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"

info "编译完成:"
info "  ${OUT_DIR}/kernel/Image"
info "  ${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
