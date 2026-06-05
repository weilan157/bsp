#!/bin/bash
# 安装 Rockchip afptool + rkImageMaker 到 vendor/tools/pack-firmware/

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEST="${PACK_TOOLS_DIR:-${BSP_ROOT}/vendor/tools/pack-firmware}"
mkdir -p "${DEST}"

if [[ -x "${DEST}/afptool" ]] && [[ -x "${DEST}/rkImageMaker" ]]; then
	info "打包工具已存在: ${DEST}"
	exit 0
fi

SRC="${PACK_TOOLS_SRC:-}"
if [[ -z "${SRC}" ]]; then
	while IFS= read -r d; do
		if [[ -x "${d}/afptool" ]] && [[ -x "${d}/rkImageMaker" ]]; then
			SRC="${d}"
			break
		fi
	done < <(find "${BSP_ROOT}/.." /opt -path '*/Linux_Pack_Firmware/rockdev' -type d 2>/dev/null | head -20)
fi

[[ -n "${SRC}" ]] || die "未找到 afptool/rkImageMaker。请设置 PACK_TOOLS_SRC 或手动复制到 ${DEST}/"

install -m 755 "${SRC}/afptool" "${SRC}/rkImageMaker" "${DEST}/"
info "已安装打包工具到 ${DEST}"
