#!/bin/bash
# 全量编译：uboot → kernel → boot.img → rootfs（可选 modules）→ update.img

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

SKIP_ROOTFS="${SKIP_ROOTFS:-}"
SKIP_PACK="${SKIP_PACK:-}"

if [[ "${SKIP_ROOTFS}" != "y" ]]; then
	if ! command -v debootstrap >/dev/null 2>&1; then
		warn "未安装 debootstrap，跳过 rootfs（设置已存在 rootfs 后可 SKIP_ROOTFS=n 重试）"
		SKIP_ROOTFS=y
	fi
fi

"${SCRIPT_DIR}/setup-sources.sh"
"${SCRIPT_DIR}/build-uboot.sh"
"${SCRIPT_DIR}/setup-kernel.sh"
"${SCRIPT_DIR}/build-kernel.sh"
"${SCRIPT_DIR}/build-bootimg.sh"

if [[ "${SKIP_ROOTFS}" != "y" ]]; then
	"${SCRIPT_DIR}/build-debian-rootfs.sh"
fi

if [[ "${SKIP_PACK}" != "y" ]]; then
	if "${SCRIPT_DIR}/fetch-pack-tools.sh" 2>/dev/null; then
		"${SCRIPT_DIR}/pack-firmware.sh" || warn "pack-firmware 失败（可能缺少 rootfs 或打包工具）"
	else
		warn "跳过 update.img 打包（运行 ./scripts/fetch-pack-tools.sh）"
	fi
fi

info "全量编译完成。产物: out/ 与 sources/u-boot/"
