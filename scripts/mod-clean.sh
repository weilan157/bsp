#!/bin/bash
# 清除下载/编译缓存

cmd_clean() {
	local target="${1:-out}"
	case "${target}" in
		uboot|u-boot)
			info "清除 U-Boot 编译产物..."
			if [[ -d "${UBOOT_DIR}" ]]; then
				rm -f "${UBOOT_DIR}/u-boot-opensbi.itb" "${UBOOT_DIR}/FSBL.bin"
				rm -f "${UBOOT_DIR}"/bootinfo_*.bin "${UBOOT_DIR}/u-boot-env-default.bin"
				rm -f "${UBOOT_DIR}/u-boot-env-default.txt" "${UBOOT_DIR}/fw_dynamic.bin"
				make -C "${UBOOT_DIR}" distclean >/dev/null 2>&1 || true
			fi
			rm -rf "${OUT_DIR}/uboot"
			;;
		kernel)
			info "清除内核产物..."
			rm -rf "${OUT_DIR}/kernel"
			if [[ -d "${KERNEL_DIR}" ]]; then
				make -C "${KERNEL_DIR}" ARCH="${KERNEL_ARCH}" distclean >/dev/null 2>&1 || true
			fi
			;;
		bootimg)
			info "清除 boot.img..."
			rm -rf "${OUT_DIR}/boot" "${OUT_DIR}/boot.img"
			;;
		rootfs)
			info "清除 rootfs..."
			run_root rm -rf "${OUT_DIR}/rootfs" "${OUT_DIR}/rootfs.ext4"
			;;
		pack|firmware)
			info "清除固件打包产物..."
			rm -rf "${OUT_DIR}/firmware" "${OUT_DIR}/firmware-pack"
			rm -f "$(sd_image_path)" "${OUT_DIR}/update.img"
			;;
		out)
			info "清除 out/ ..."
			run_root rm -rf "${OUT_DIR}"
			mkdir -p "${OUT_DIR}"
			;;
		sources)
			info "清除 sources/（需重新 ./bsp setup）..."
			rm -rf "${SOURCES_DIR}"
			;;
		toolchain)
			info "清除 toolchains/ ..."
			rm -rf "${BSP_ROOT}/toolchains"
			;;
		all)
			cmd_clean out
			cmd_clean uboot
			cmd_clean kernel
			info "已清除全部编译缓存（源码 sources/ 保留；清除源码用 ./bsp clean sources）"
			;;
		*)
			die "clean 用法: ./bsp clean [uboot|kernel|bootimg|rootfs|pack|out|sources|toolchain|all]"
			;;
	esac
	info "清除完成: ${target}"
}
