#!/bin/bash
# 清除下载/编译缓存

cmd_clean() {
	local target="${1:-out}"
	case "${target}" in
		uboot|u-boot)
			info "清除 U-Boot 编译产物..."
			if [[ -d "${UBOOT_DIR}" ]]; then
				rm -f "${UBOOT_DIR}/uboot.img" "${UBOOT_DIR}/trust.img"
				rm -f "${UBOOT_DIR}"/rk3576_spl_loader_*.bin "${UBOOT_DIR}"/rk3576_idblock_*.img
				make -C "${UBOOT_DIR}" distclean >/dev/null 2>&1 || true
			fi
			;;
		kernel)
			info "清除内核产物..."
			rm -rf "${OUT_DIR}/kernel"
			if [[ -d "${KERNEL_DIR}" ]]; then
				# distclean 不依赖交叉链；失败可忽略
				make -C "${KERNEL_DIR}" ARCH=arm64 distclean >/dev/null 2>&1 || true
			fi
			;;
		bootimg)
			info "清除 boot.img..."
			rm -f "${OUT_DIR}/boot.img" "${OUT_DIR}/kernel/resource.img"
			;;
		rootfs)
			info "清除 rootfs..."
			run_root rm -rf "${OUT_DIR}/rootfs" "${OUT_DIR}/rootfs.ext4"
			;;
		pack|firmware)
			info "清除固件打包产物..."
			rm -rf "${OUT_DIR}/firmware" "${OUT_DIR}/firmware-pack" "${OUT_DIR}/update.img"
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
		all)
			cmd_clean out
			cmd_clean uboot
			cmd_clean kernel
			info "已清除全部编译缓存（源码 sources/ 保留；清除源码用 ./bsp clean sources）"
			;;
		*)
			die "clean 用法: ./bsp clean [uboot|kernel|bootimg|rootfs|pack|out|sources|all]"
			;;
	esac
	info "清除完成: ${target}"
}
