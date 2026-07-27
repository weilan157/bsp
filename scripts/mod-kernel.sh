#!/bin/bash
# 内核编译、boot 分区镜像、模块安装（Ky X1 / RISC-V）

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
	arch="${KERNEL_ARCH}"
	local -a kmake
	kmake=(make -C "${KERNEL_DIR}" -j"${jobs}" ARCH="${arch}" CROSS_COMPILE="${CROSS_COMPILE}")
	fragments="$(kernel_defconfig_fragments)"

	cmd_sync_config
	cmd_sync_dts

	local dotconfig="${KERNEL_DOTCONFIG}"
	if [[ -z "${dotconfig}" ]] && [[ -z "${KERNEL_DEFCONFIG}" ]]; then
		dotconfig="${BSP_ROOT}/vendor/kernel-config/linux-ky-current.config"
	fi

	if [[ -n "${dotconfig}" ]]; then
		[[ -f "${dotconfig}" ]] || die "KERNEL_DOTCONFIG 不存在: ${dotconfig}"
		info "使用完整内核配置: ${dotconfig}"
		cp "${dotconfig}" "${KERNEL_DIR}/.config"
		"${kmake[@]}" olddefconfig
	else
		info "配置内核: ${KERNEL_DEFCONFIG} ${fragments}"
		# shellcheck disable=SC2086
		"${kmake[@]}" "${KERNEL_DEFCONFIG}" ${fragments}
	fi

	dts_target="${KERNEL_DTS_SUBDIR}/${KERNEL_DTS_NAME}.dtb"
	info "编译 Image 与 ${dts_target} (jobs=${jobs})..."
	"${kmake[@]}" Image
	"${kmake[@]}" "${dts_target}"

	mkdir -p "${OUT_DIR}/kernel"
	install -m 644 "${KERNEL_DIR}/arch/${arch}/boot/Image" "${OUT_DIR}/kernel/Image"
	install -m 644 \
		"${KERNEL_DIR}/arch/${arch}/boot/dts/${KERNEL_DTS_SUBDIR}/${KERNEL_DTS_NAME}.dtb" \
		"${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"

	# 复制 overlay dtbo（若有）
	local overlay_src overlay_dst
	overlay_src="${KERNEL_DIR}/arch/${arch}/boot/dts/${KERNEL_DTS_SUBDIR}/overlay"
	overlay_dst="${OUT_DIR}/kernel/overlay"
	if [[ -d "${overlay_src}" ]]; then
		mkdir -p "${overlay_dst}"
		find "${overlay_src}" -name '*.dtbo' -exec install -m 644 {} "${overlay_dst}/" \;
	fi

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
	if command -v mkimage >/dev/null 2>&1; then
		command -v mkimage
		return
	fi
	die "未找到 mkimage，请 ./bsp env 安装 u-boot-tools 或先 ./bsp uboot"
}

# 生成 /boot 内容目录 + FAT boot.img（非 Rockchip FIT）
cmd_bootimg() {
	parse_build_flags "$@"

	if ! bsp_want_force && have_bootimg_artifacts; then
		info "已有 boot.img，跳过打包（加 --clean 强制重做）"
		ls -lh "${OUT_DIR}/boot.img"
		return 0
	fi

	local kernel_image kernel_dtb boot_dir boot_img mkimage_bin
	kernel_image="${OUT_DIR}/kernel/Image"
	kernel_dtb="${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
	boot_dir="${OUT_DIR}/boot"
	boot_img="${OUT_DIR}/boot.img"

	if [[ ! -f "${kernel_image}" ]] || [[ ! -f "${kernel_dtb}" ]]; then
		info "未找到内核产物，先执行 ./bsp kernel"
		cmd_kernel
	fi

	mkimage_bin="$(find_mkimage)"
	info "mkimage: ${mkimage_bin}"

	rm -rf "${boot_dir}"
	mkdir -p "${boot_dir}/dtb/${KERNEL_DTS_SUBDIR}/overlay"

	install -m 644 "${kernel_image}" "${boot_dir}/Image"
	install -m 644 "${kernel_dtb}" \
		"${boot_dir}/dtb/${KERNEL_DTS_SUBDIR}/${KERNEL_DTS_NAME}.dtb"

	if [[ -d "${OUT_DIR}/kernel/overlay" ]]; then
		find "${OUT_DIR}/kernel/overlay" -name '*.dtbo' \
			-exec install -m 644 {} "${boot_dir}/dtb/${KERNEL_DTS_SUBDIR}/overlay/" \;
	fi

	# orangepiEnv.txt
	local env_src="${BOOT_ENV_SRC}"
	[[ -f "${env_src}" ]] || die "缺少 ${env_src}"
	{
		cat "${env_src}"
		echo "fdtfile=${KERNEL_DTS_SUBDIR}/${KERNEL_DTS_NAME}.dtb"
		echo "overlay_prefix=x1"
		echo "rootdev=/dev/mmcblk0p2"
		echo "rootfstype=ext4"
		echo "console=both"
		echo "earlycon=on"
	} > "${boot_dir}/orangepiEnv.txt"

	# boot.cmd → boot.scr（无 initrd）
	local cmd_src="${BOOT_CMD_SRC}"
	[[ -f "${cmd_src}" ]] || die "缺少 ${cmd_src}"
	install -m 644 "${cmd_src}" "${boot_dir}/boot.cmd"
	"${mkimage_bin}" -C none -A riscv -T script \
		-d "${boot_dir}/boot.cmd" "${boot_dir}/boot.scr"

	# 生成 FAT boot.img
	local boot_mib="${SD_BOOT_MIB}"
	info "打包 FAT boot.img (${boot_mib}MiB)..."
	rm -f "${boot_img}"
	truncate -s "${boot_mib}M" "${boot_img}"
	mkfs.vfat -F 32 -n BOOT "${boot_img}" >/dev/null

	if command -v mcopy >/dev/null 2>&1; then
		# mtools
		mcopy -i "${boot_img}" -s "${boot_dir}/Image" ::/Image
		mcopy -i "${boot_img}" -s "${boot_dir}/boot.cmd" ::/boot.cmd
		mcopy -i "${boot_img}" -s "${boot_dir}/boot.scr" ::/boot.scr
		mcopy -i "${boot_img}" -s "${boot_dir}/orangepiEnv.txt" ::/orangepiEnv.txt
		mcopy -i "${boot_img}" -s "${boot_dir}/dtb" ::/dtb
	else
		local mnt
		mnt="$(mktemp -d)"
		run_root mount -o loop "${boot_img}" "${mnt}"
		run_root cp -a "${boot_dir}/." "${mnt}/"
		run_root umount "${mnt}"
		rmdir "${mnt}"
	fi

	info "完成:"
	info "  ${boot_dir}/"
	info "  ${boot_img}"
}

install_kernel_modules() {
	local rootfs="${1:-${OUT_DIR}/rootfs}"
	local _info
	_info() { echo "[INFO] $*" >&2; }

	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"
	[[ -d "${rootfs}" ]] || die "rootfs 不存在: ${rootfs}（先 ./bsp rootfs）"
	[[ -f "${OUT_DIR}/kernel/Image" ]] || die "请先 ./bsp kernel"

	setup_cross_compile
	local jobs arch kernel_release mod_count
	jobs="$(job_count)"
	arch="${KERNEL_ARCH}"
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
