#!/bin/bash
# 打包 Rockchip update.img（afptool + rkImageMaker）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PACK_DIR="${PACK_TOOLS_DIR:-${BSP_ROOT}/vendor/tools/pack-firmware}"
PACKAGE_FILE="${FIRMWARE_PACKAGE_FILE:-${BSP_ROOT}/vendor/firmware/package-file}"
WORK="${OUT_DIR}/firmware-pack"
UPDATE_IMG="${OUT_DIR}/update.img"

[[ -x "${PACK_DIR}/afptool" ]] || "${SCRIPT_DIR}/fetch-pack-tools.sh"
[[ -x "${PACK_DIR}/afptool" ]] || die "缺少 ${PACK_DIR}/afptool"
[[ -x "${PACK_DIR}/rkImageMaker" ]] || die "缺少 ${PACK_DIR}/rkImageMaker"

"${SCRIPT_DIR}/stage-firmware.sh"

[[ -f "${OUT_DIR}/firmware/MiniLoaderAll.bin" ]] || die "缺少 MiniLoaderAll.bin"
[[ -f "${OUT_DIR}/firmware/parameter.txt" ]] || die "缺少 parameter.txt"
[[ -f "${OUT_DIR}/firmware/uboot.img" ]] || die "缺少 uboot.img"
[[ -f "${OUT_DIR}/firmware/boot.img" ]] || die "缺少 boot.img"

rm -rf "${WORK}"
mkdir -p "${WORK}/Image"
cd "${WORK}"

install -m 644 "${PACKAGE_FILE}" package-file
for name in MiniLoaderAll.bin parameter.txt uboot.img misc.img boot.img rootfs.img; do
	[[ -f "${OUT_DIR}/firmware/${name}" ]] || continue
	ln -rsf "${OUT_DIR}/firmware/${name}" "Image/${name}"
done

# 按 package-file 过滤：跳过不存在的分区镜像行
{
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ "${line}" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${line//[[:space:]]/}" ]] && continue
		pkg_name="${line%%[[:space:]]*}"
		img_path="${line##*[[:space:]]}"
		case "${pkg_name}" in
			package-file|backup|RESERVED)
				echo -e "${pkg_name}\t${img_path}"
				;;
			*)
				if [[ -f "${img_path}" ]]; then
					echo -e "${pkg_name}\t${img_path}"
				else
					warn "package-file 跳过缺失镜像: ${pkg_name} -> ${img_path}"
				fi
				;;
		esac
	done
} < package-file > package-file.filtered
mv package-file.filtered package-file

info "package-file:"
cat package-file

AFPTOOL="${PACK_DIR}/afptool"
RKMAKER="${PACK_DIR}/rkImageMaker"

"${AFPTOOL}" -pack ./ "${WORK}/update.raw.img"
TAG="RK$(dd if=Image/MiniLoaderAll.bin bs=1 count=4 skip=21 status=none | rev)"
"${RKMAKER}" "-${TAG}" Image/MiniLoaderAll.bin "${WORK}/update.raw.img" "${UPDATE_IMG}" \
	-os_type:androidos

info "完成: ${UPDATE_IMG}"
ls -lh "${UPDATE_IMG}"
