#!/bin/bash
# 生成 resource.img 并打包 FIT boot.img

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./scripts/setup-kernel.sh"

KERNEL_IMAGE="${OUT_DIR}/kernel/Image"
KERNEL_DTB="${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
RESOURCE_IMG="${OUT_DIR}/kernel/resource.img"
BOOT_IMG="${OUT_DIR}/boot.img"
FIT_ITS="${BOOT_FIT_ITS:-${BSP_ROOT}/vendor/fit/boot.its}"

if [[ ! -f "${KERNEL_IMAGE}" ]] || [[ ! -f "${KERNEL_DTB}" ]]; then
	info "未找到内核产物，先执行 build-kernel.sh"
	"${SCRIPT_DIR}/build-kernel.sh"
fi

find_mkimage() {
	if [[ -n "${MKIMAGE_BIN:-}" ]] && [[ -x "${MKIMAGE_BIN}" ]]; then
		echo "${MKIMAGE_BIN}"
		return
	fi
	if [[ -x "${UBOOT_DIR}/tools/mkimage" ]]; then
		echo "${UBOOT_DIR}/tools/mkimage"
		return
	fi
	if [[ -x "${RKBIN_DIR}/tools/mkimage" ]]; then
		echo "${RKBIN_DIR}/tools/mkimage"
		return
	fi
	die "未找到 mkimage，请先 ./scripts/setup-sources.sh 并编译 u-boot"
}

export MKIMAGE
MKIMAGE="$(find_mkimage)"
info "mkimage: ${MKIMAGE}"

RESOURCE_TOOL="${KERNEL_DIR}/scripts/resource_tool"
if [[ ! -x "${RESOURCE_TOOL}" ]]; then
	info "编译 kernel resource_tool..."
	make -C "${KERNEL_DIR}/scripts" resource_tool
fi

LOGO_ARGS=()
[[ -f "${KERNEL_DIR}/logo.bmp" ]] && LOGO_ARGS+=( "${KERNEL_DIR}/logo.bmp" )
[[ -f "${KERNEL_DIR}/logo_kernel.bmp" ]] && LOGO_ARGS+=( "${KERNEL_DIR}/logo_kernel.bmp" )

info "生成 resource.img ..."
rm -f "${RESOURCE_IMG}"
if [[ ${#LOGO_ARGS[@]} -gt 0 ]]; then
	( cd "${KERNEL_DIR}" && ./scripts/resource_tool "${KERNEL_DTB}" "${LOGO_ARGS[@]}" )
else
	( cd "${KERNEL_DIR}" && ./scripts/resource_tool "${KERNEL_DTB}" )
fi
mv -f "${KERNEL_DIR}/resource.img" "${RESOURCE_IMG}"

[[ -f "${FIT_ITS}" ]] || die "FIT ITS 不存在: ${FIT_ITS}"

info "打包 FIT -> ${BOOT_IMG}"
"${SCRIPT_DIR}/mk-fitimage.sh" \
	"${BOOT_IMG}" "${FIT_ITS}" \
	"${KERNEL_IMAGE}" "${KERNEL_DTB}" "${RESOURCE_IMG}"

info "完成:"
info "  ${RESOURCE_IMG}"
info "  ${BOOT_IMG}"
