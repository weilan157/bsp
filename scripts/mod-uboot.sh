#!/bin/bash
# 编译 U-Boot

cmd_uboot() {
	parse_build_flags "$@"
	[[ -d "${UBOOT_DIR}" ]] || die "请先运行 ./bsp setup uboot"
	[[ -d "${RKBIN_DIR}" ]] || die "缺少 rkbin，请先运行 ./bsp setup uboot"

	if ! bsp_want_force && have_uboot_artifacts; then
		info "已有 U-Boot 产物，跳过编译（加 --clean 强制重编）"
		ls -la "${UBOOT_DIR}/uboot.img" "$(uboot_loader_path)" 2>/dev/null || true
		return 0
	fi

	ensure_python2_wrapper
	setup_cross_compile

	(
		cd "${UBOOT_DIR}"
		apply_uboot_patches
		info "清理旧产物..."
		make distclean 2>/dev/null || true
		info "编译 U-Boot (board=${UBOOT_BOARD}, --spl-new)..."
		./make.sh "${UBOOT_BOARD}" --spl-new "CROSS_COMPILE=${CROSS_COMPILE}"
	)

	info "编译完成，主要产物:"
	ls -la "${UBOOT_DIR}"/uboot.img "${UBOOT_DIR}"/trust.img 2>/dev/null || true
	ls -la "${UBOOT_DIR}"/rk3576_spl_loader_*.bin "${UBOOT_DIR}"/rk3576_idblock_*.img 2>/dev/null || true
}
