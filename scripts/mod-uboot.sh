#!/bin/bash
# 编译 U-Boot（Orange Pi R2S / Ky X1）

cmd_uboot() {
	parse_build_flags "$@"
	# --update：先刷新 u-boot 源码（all 里已 setup 则跳过）
	if bsp_want_update && [[ "${BSP_SETUP_UBOOT_DONE:-}" != "1" ]]; then
		cmd_setup_uboot_sources
	fi
	[[ -d "${UBOOT_DIR}" ]] || die "请先运行 ./bsp setup uboot"

	if ! bsp_want_rebuild && have_uboot_artifacts; then
		info "已有 U-Boot 产物，跳过编译（加 --clean/--update 强制重编）"
		ls -la "${UBOOT_DIR}/u-boot-opensbi.itb" "${UBOOT_DIR}/FSBL.bin" \
			"${UBOOT_DIR}/bootinfo_sd.bin" 2>/dev/null || true
		return 0
	fi

	ensure_python2_wrapper
	setup_cross_compile

	local jobs defconfig
	jobs="$(job_count)"
	defconfig="${UBOOT_BOARD}_defconfig"

	(
		cd "${UBOOT_DIR}"
		info "清理旧产物..."
		make distclean 2>/dev/null || true
		info "配置 U-Boot: ${defconfig}"
		make -j"${jobs}" "${defconfig}" CROSS_COMPILE="${CROSS_COMPILE}"
		info "编译 U-Boot + OpenSBI (jobs=${jobs})..."
		# 生成: FSBL.bin bootinfo_*.bin u-boot-env-default.bin u-boot-opensbi.itb
		make -j"${jobs}" CROSS_COMPILE="${CROSS_COMPILE}"
	)

	have_uboot_artifacts || die "U-Boot 编译完成但缺少关键产物（u-boot-opensbi.itb / FSBL.bin / bootinfo_sd.bin）"

	mkdir -p "${OUT_DIR}/uboot"
	local f
	for f in bootinfo_sd.bin bootinfo_emmc.bin bootinfo_spinor.bin \
		FSBL.bin u-boot-env-default.bin u-boot-opensbi.itb; do
		[[ -f "${UBOOT_DIR}/${f}" ]] || continue
		install -m 644 "${UBOOT_DIR}/${f}" "${OUT_DIR}/uboot/${f}"
	done

	info "编译完成，主要产物:"
	ls -lh "${OUT_DIR}/uboot/"
}
