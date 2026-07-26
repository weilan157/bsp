#!/bin/bash
# 内核编译、FIT boot.img、模块安装

cmd_kernel() {
	parse_build_flags "$@"
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	if ! bsp_want_force && have_kernel_artifacts; then
		info "已有内核产物，跳过编译（加 --clean 强制重编）"
		ls -lh "${OUT_DIR}/kernel/Image" "${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
		return 0
	fi

	setup_cross_compile
	local jobs arch fragments dts_target
	jobs="$(job_count)"
	arch=arm64
	local -a kmake
	kmake=(make -C "${KERNEL_DIR}" -j"${jobs}" ARCH="${arch}" CROSS_COMPILE="${CROSS_COMPILE}")
	fragments="$(kernel_defconfig_fragments)"

	# 始终同步 vendor/kernel-config（含 bsp-boot.config、rk3576.config 等）
	cmd_sync_config

	info "配置内核: ${KERNEL_DEFCONFIG} ${fragments}"
	if [[ "${TSPI_VENDOR_KERNEL_CONFIG}" == "y" ]]; then
		info "已启用 TSPI_VENDOR_KERNEL_CONFIG（PANFROST / Mali Bifrost 等）"
	fi
	# shellcheck disable=SC2086
	"${kmake[@]}" "${KERNEL_DEFCONFIG}" ${fragments}

	dts_target="rockchip/${KERNEL_DTS_NAME}.dtb"
	info "编译 Image 与 ${dts_target} (jobs=${jobs})..."
	"${kmake[@]}" Image
	"${kmake[@]}" "${dts_target}"

	mkdir -p "${OUT_DIR}/kernel"
	install -m 644 "${KERNEL_DIR}/arch/arm64/boot/Image" "${OUT_DIR}/kernel/Image"
	install -m 644 "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/${KERNEL_DTS_NAME}.dtb" \
		"${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"

	info "编译完成:"
	info "  ${OUT_DIR}/kernel/Image"
	info "  ${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
}

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
	die "未找到 mkimage，请先 ./bsp setup uboot 并 ./bsp uboot"
}

mk_fitimage() {
	local target_img="$1" its="$2" kernel_img="$3" kernel_dtb="$4" resource_img="$5"
	local tmp_its mkimage_bin
	[[ -f "${its}" ]] || die "ITS 不存在: ${its}"
	local f
	for f in "${kernel_img}" "${kernel_dtb}" "${resource_img}"; do
		[[ -f "${f}" ]] || die "缺少文件: ${f}"
	done
	mkimage_bin="${MKIMAGE:?}"
	tmp_its="$(mktemp)"
	cp "${its}" "${tmp_its}"
	sed -i \
		-e "s~@KERNEL_DTB@~$(realpath -q "${kernel_dtb}")~" \
		-e "s~@KERNEL_IMG@~$(realpath -q "${kernel_img}")~" \
		-e "s~@RESOURCE_IMG@~$(realpath -q "${resource_img}")~" \
		"${tmp_its}"
	"${mkimage_bin}" -f "${tmp_its}" -E -p 0x800 "${target_img}"
	rm -f "${tmp_its}"
}

cmd_bootimg() {
	parse_build_flags "$@"
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	if ! bsp_want_force && have_bootimg_artifacts; then
		info "已有 boot.img，跳过打包（加 --clean 强制重做）"
		ls -lh "${OUT_DIR}/boot.img"
		return 0
	fi

	local kernel_image kernel_dtb resource_img boot_img fit_its resource_tool
	kernel_image="${OUT_DIR}/kernel/Image"
	kernel_dtb="${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
	resource_img="${OUT_DIR}/kernel/resource.img"
	boot_img="${OUT_DIR}/boot.img"
	fit_its="${BOOT_FIT_ITS:-${BSP_ROOT}/vendor/fit/boot.its}"

	if [[ ! -f "${kernel_image}" ]] || [[ ! -f "${kernel_dtb}" ]]; then
		info "未找到内核产物，先执行 ./bsp kernel"
		cmd_kernel
	fi

	export MKIMAGE
	MKIMAGE="$(find_mkimage)"
	info "mkimage: ${MKIMAGE}"

	resource_tool="${KERNEL_DIR}/scripts/resource_tool"
	if [[ ! -x "${resource_tool}" ]]; then
		info "编译 kernel resource_tool..."
		make -C "${KERNEL_DIR}/scripts" resource_tool
	fi

	local logo_args=()
	[[ -f "${KERNEL_DIR}/logo.bmp" ]] && logo_args+=( "${KERNEL_DIR}/logo.bmp" )
	[[ -f "${KERNEL_DIR}/logo_kernel.bmp" ]] && logo_args+=( "${KERNEL_DIR}/logo_kernel.bmp" )

	info "生成 resource.img ..."
	rm -f "${resource_img}"
	if [[ ${#logo_args[@]} -gt 0 ]]; then
		( cd "${KERNEL_DIR}" && ./scripts/resource_tool "${kernel_dtb}" "${logo_args[@]}" )
	else
		( cd "${KERNEL_DIR}" && ./scripts/resource_tool "${kernel_dtb}" )
	fi
	mv -f "${KERNEL_DIR}/resource.img" "${resource_img}"

	[[ -f "${fit_its}" ]] || die "FIT ITS 不存在: ${fit_its}"
	info "打包 FIT -> ${boot_img}"
	mk_fitimage "${boot_img}" "${fit_its}" "${kernel_image}" "${kernel_dtb}" "${resource_img}"

	info "完成:"
	info "  ${resource_img}"
	info "  ${boot_img}"
}

# stdout 仅一行 kernelrelease（供 rootfs 捕获）；日志走 stderr
install_kernel_modules() {
	local rootfs="${1:-${OUT_DIR}/rootfs}"
	local _info _warn
	_info() { echo "[INFO] $*" >&2; }
	_warn() { echo "[WARN] $*" >&2; }

	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"
	[[ -d "${rootfs}" ]] || die "rootfs 不存在: ${rootfs}（先 ./bsp rootfs）"
	[[ -f "${OUT_DIR}/kernel/Image" ]] || die "请先 ./bsp kernel"

	setup_cross_compile
	local jobs arch kernel_release mod_count
	jobs="$(job_count)"
	arch=arm64
	local -a kmake
	kmake=(make -C "${KERNEL_DIR}" -j"${jobs}" ARCH="${arch}" CROSS_COMPILE="${CROSS_COMPILE}" --no-print-directory)

	kernel_release="$("${kmake[@]}" -s kernelrelease 2>/dev/null | tr -d '[:space:]')"
	[[ -n "${kernel_release}" ]] || die "无法取得 kernelrelease"
	_info "安装内核模块 ${kernel_release} -> ${rootfs}/lib/modules/"

	"${kmake[@]}" modules >&2
	run_root rm -rf "${rootfs}/lib/modules"
	run_root env INSTALL_MOD_STRIP=1 ARCH="${arch}" CROSS_COMPILE="${CROSS_COMPILE}" \
		make -C "${KERNEL_DIR}" -j"${jobs}" --no-print-directory \
		INSTALL_MOD_PATH="${rootfs}" modules_install >&2

	mod_count="$(run_root find "${rootfs}/lib/modules/${kernel_release}" -name '*.ko*' | wc -l)"
	_info "模块已安装（共 ${mod_count} 个 .ko）"
	printf '%s\n' "${kernel_release}"
}

cmd_modules() {
	local rootfs="${1:-${OUT_DIR}/rootfs}"
	local release
	release="$(install_kernel_modules "${rootfs}")"
	info "kernelrelease=${release}"
}
