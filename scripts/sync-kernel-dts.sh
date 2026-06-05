#!/bin/bash
# 将泰山派设备树复制到 GitHub kernel 树

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./scripts/setup-kernel.sh"

resolve_dts_source() {
	if [[ -n "${TSPI_DTS_SOURCE}" ]]; then
		[[ -d "${TSPI_DTS_SOURCE}" ]] || die "TSPI_DTS_SOURCE 不是目录: ${TSPI_DTS_SOURCE}"
		echo "${TSPI_DTS_SOURCE}"
		return
	fi
	[[ -d "${VENDOR_DTS_DIR}" ]] || die "缺少 ${VENDOR_DTS_DIR}，请设置 TSPI_DTS_SOURCE 或保留 vendor/dts"
	echo "${VENDOR_DTS_DIR}"
}

DTS_SRC="$(resolve_dts_source)"
KERNEL_DTS_DIR="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip"
MAKEFILE="${KERNEL_DTS_DIR}/Makefile"
TSPI_MARK="tspi-3m-rk3576.dtb"

info "设备树来源: ${DTS_SRC}"
info "目标目录:   ${KERNEL_DTS_DIR}"

shopt -s nullglob
local_files=( "${DTS_SRC}"/tspi-3m-rk3576* )
[[ ${#local_files[@]} -gt 0 ]] || die "来源目录无 tspi-3m-rk3576* 文件"

rsync -a "${local_files[@]}" "${KERNEL_DTS_DIR}/"

if [[ -f "${DTS_SRC}/rk3576-linux.dtsi" ]]; then
	rsync -a "${DTS_SRC}/rk3576-linux.dtsi" "${KERNEL_DTS_DIR}/"
fi

if [[ -d "${DTS_SRC}/device-tree-overlays" ]]; then
	rsync -a "${DTS_SRC}/device-tree-overlays/" "${KERNEL_DTS_DIR}/device-tree-overlays/"
fi

if ! grep -q "${TSPI_MARK}" "${MAKEFILE}"; then
	info "向 Makefile 添加 ${TSPI_MARK} 条目"
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${TSPI_MARK}" >> "${MAKEFILE}"
else
	info "Makefile 已包含 ${TSPI_MARK}"
fi

info "设备树同步完成 (${#local_files[@]} 个 tspi 文件)"
