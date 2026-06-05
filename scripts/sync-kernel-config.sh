#!/bin/bash
# 将 vendor/kernel-config 安装到 kernel arch/arm64/configs

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./scripts/setup-kernel.sh"

KERNEL_CONFIGS_DIR="${KERNEL_DIR}/arch/arm64/configs"
VENDOR_CFG_DIR="${BSP_ROOT}/vendor/kernel-config"

install_fragment() {
	local src="$1"
	local name
	name="$(basename "${src}")"
	install -m 644 "${src}" "${KERNEL_CONFIGS_DIR}/${name}"
	info "  ${name}"
}

info "安装 kernel config fragments -> ${KERNEL_CONFIGS_DIR}"

if [[ -n "${TSPI_KERNEL_CONFIG_SOURCE:-}" ]]; then
	[[ -d "${TSPI_KERNEL_CONFIG_SOURCE}" ]] || \
		die "TSPI_KERNEL_CONFIG_SOURCE 不是目录: ${TSPI_KERNEL_CONFIG_SOURCE}"
	info "自 SDK 路径复制可选 fragment:"
	for name in tspi-vendor.config rk3576.config; do
		[[ -f "${TSPI_KERNEL_CONFIG_SOURCE}/${name}" ]] || continue
		install_fragment "${TSPI_KERNEL_CONFIG_SOURCE}/${name}"
	done
fi

shopt -s nullglob
local_frags=( "${VENDOR_CFG_DIR}"/*.config )
[[ ${#local_frags[@]} -gt 0 ]] || die "vendor/kernel-config 下无 .config 文件"

info "自 vendor/kernel-config 复制:"
for f in "${local_frags[@]}"; do
	install_fragment "${f}"
done
