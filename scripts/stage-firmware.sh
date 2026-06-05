#!/bin/bash
# 收集分区镜像到 out/firmware/（供烧录或 pack-firmware.sh）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

FW_DIR="${OUT_DIR}/firmware"
PARAMETER_SRC="${FIRMWARE_PARAMETER:-${BSP_ROOT}/vendor/firmware/parameter.txt}"
mkdir -p "${FW_DIR}"

[[ -d "${UBOOT_DIR}" ]] || die "请先 ./scripts/setup-sources.sh && ./scripts/build-uboot.sh"

LOADER="$(find "${UBOOT_DIR}" -maxdepth 1 -name 'rk3576_spl_loader_*.bin' | head -1)"
[[ -n "${LOADER}" ]] || die "未找到 rk3576_spl_loader_*.bin，请先 build-uboot.sh"
[[ -f "${UBOOT_DIR}/uboot.img" ]] || die "未找到 uboot.img"

link_or_copy() {
	local src="$1" dst="$2"
	if [[ "$(readlink -f "${src}")" == "$(readlink -f "${dst}" 2>/dev/null || true)" ]]; then
		return 0
	fi
	rm -f "${dst}"
	ln -rsf "${src}" "${dst}"
}

info "收集固件到 ${FW_DIR}/"
link_or_copy "${LOADER}" "${FW_DIR}/MiniLoaderAll.bin"
link_or_copy "${UBOOT_DIR}/uboot.img" "${FW_DIR}/uboot.img"
install -m 644 "${PARAMETER_SRC}" "${FW_DIR}/parameter.txt"

if [[ ! -f "${FW_DIR}/misc.img" ]]; then
	"${SCRIPT_DIR}/mk-misc.sh"
fi

if [[ -f "${OUT_DIR}/boot.img" ]]; then
	link_or_copy "${OUT_DIR}/boot.img" "${FW_DIR}/boot.img"
else
	warn "缺少 out/boot.img，请先 ./scripts/build-bootimg.sh"
fi

if [[ -f "${OUT_DIR}/rootfs.ext4" ]]; then
	link_or_copy "${OUT_DIR}/rootfs.ext4" "${FW_DIR}/rootfs.img"
elif [[ -f "${OUT_DIR}/rootfs/rootfs.img" ]]; then
	link_or_copy "${OUT_DIR}/rootfs/rootfs.img" "${FW_DIR}/rootfs.img"
else
	warn "缺少 rootfs.ext4，请先 ./scripts/build-debian-rootfs.sh"
fi

info "固件目录就绪:"
ls -lh "${FW_DIR}/"
