#!/bin/bash
# 源码克隆与 DTS/config 同步

clone_or_update() {
	local url="$1"
	local branch="$2"
	local dir="$3"
	local name
	name="$(basename "${dir}")"

	if [[ -d "${dir}/.git" ]]; then
		if ! bsp_want_update; then
			info "已有 ${name}，跳过下载（加 --update 可拉取更新）"
			return 0
		fi
		info "更新 ${name} (${branch})..."
		git -C "${dir}" fetch origin
		git -C "${dir}" checkout "${branch}"
		git -C "${dir}" pull --ff-only origin "${branch}" || true
	else
		info "克隆 ${name} (${branch})..."
		git clone --depth 1 -b "${branch}" "${url}" "${dir}"
	fi
}

backup_local_rkbin() {
	[[ -n "${RKBIN_BACKUP_SRC}" ]] || return 0
	[[ -d "${RKBIN_BACKUP_SRC}" ]] || die "RKBIN_BACKUP_SRC 不是目录: ${RKBIN_BACKUP_SRC}"

	local stamp dest
	stamp="$(date +%Y%m%d-%H%M%S)"
	dest="${BACKUP_DIR}/rkbin-local-${stamp}"
	info "备份本地 rkbin: ${RKBIN_BACKUP_SRC} -> ${dest}"
	rsync -a --delete "${RKBIN_BACKUP_SRC}/" "${dest}/"
}

cmd_setup_uboot_sources() {
	mkdir -p "${SOURCES_DIR}" "${BACKUP_DIR}"
	backup_local_rkbin
	clone_or_update "${UBOOT_REPO}" "${UBOOT_BRANCH}" "${UBOOT_DIR}"
	clone_or_update "${RKBIN_REPO}" "${RKBIN_BRANCH}" "${RKBIN_DIR}"
	[[ -d "${RKBIN_DIR}" ]] || die "rkbin 克隆失败: ${RKBIN_DIR}"
	info "源码就绪:"
	info "  u-boot: ${UBOOT_DIR}"
	info "  rkbin:  ${RKBIN_DIR}"
}

cmd_setup_kernel_sources() {
	mkdir -p "${SOURCES_DIR}"
	clone_or_update "${KERNEL_REPO}" "${KERNEL_BRANCH}" "${KERNEL_DIR}"
	cmd_sync_dts
	info "内核源码就绪: ${KERNEL_DIR}"
}

cmd_setup() {
	parse_build_flags "$@"
	local target="${BSP_CMD_ARGS[0]:-all}"
	case "${target}" in
		uboot|u-boot) cmd_setup_uboot_sources ;;
		kernel) cmd_setup_kernel_sources ;;
		all)
			cmd_setup_uboot_sources
			cmd_setup_kernel_sources
			;;
		*) die "setup 用法: ./bsp setup [uboot|kernel|all] [--update]" ;;
	esac
}

resolve_dts_source() {
	if [[ -n "${TSPI_DTS_SOURCE}" ]]; then
		[[ -d "${TSPI_DTS_SOURCE}" ]] || die "TSPI_DTS_SOURCE 不是目录: ${TSPI_DTS_SOURCE}"
		echo "${TSPI_DTS_SOURCE}"
		return
	fi
	[[ -d "${VENDOR_DTS_DIR}" ]] || die "缺少 ${VENDOR_DTS_DIR}，请设置 TSPI_DTS_SOURCE 或保留 vendor/dts"
	echo "${VENDOR_DTS_DIR}"
}

cmd_sync_dts() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	local dts_src kernel_dts_dir makefile tspi_mark
	dts_src="$(resolve_dts_source)"
	kernel_dts_dir="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip"
	makefile="${kernel_dts_dir}/Makefile"
	tspi_mark="tspi-3m-rk3576.dtb"

	info "设备树来源: ${dts_src}"
	info "目标目录:   ${kernel_dts_dir}"

	local local_files=()
	shopt -s nullglob
	local_files=( "${dts_src}"/tspi-3m-rk3576* )
	shopt -u nullglob
	[[ ${#local_files[@]} -gt 0 ]] || die "来源目录无 tspi-3m-rk3576* 文件"

	rsync -a "${local_files[@]}" "${kernel_dts_dir}/"

	if [[ -f "${dts_src}/rk3576-linux.dtsi" ]]; then
		rsync -a "${dts_src}/rk3576-linux.dtsi" "${kernel_dts_dir}/"
	fi
	if [[ -d "${dts_src}/device-tree-overlays" ]]; then
		rsync -a "${dts_src}/device-tree-overlays/" "${kernel_dts_dir}/device-tree-overlays/"
	fi

	if ! grep -q "${tspi_mark}" "${makefile}"; then
		info "向 Makefile 添加 ${tspi_mark} 条目"
		echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${tspi_mark}" >> "${makefile}"
	else
		info "Makefile 已包含 ${tspi_mark}"
	fi

	info "设备树同步完成 (${#local_files[@]} 个 tspi 文件)"
}

cmd_sync_config() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	local kernel_configs_dir vendor_cfg_dir
	kernel_configs_dir="${KERNEL_DIR}/arch/arm64/configs"
	vendor_cfg_dir="${BSP_ROOT}/vendor/kernel-config"

	install_fragment() {
		local src="$1"
		install -m 644 "${src}" "${kernel_configs_dir}/$(basename "${src}")"
		info "  $(basename "${src}")"
	}

	info "安装 kernel config fragments -> ${kernel_configs_dir}"

	if [[ -n "${TSPI_KERNEL_CONFIG_SOURCE:-}" ]]; then
		[[ -d "${TSPI_KERNEL_CONFIG_SOURCE}" ]] || \
			die "TSPI_KERNEL_CONFIG_SOURCE 不是目录: ${TSPI_KERNEL_CONFIG_SOURCE}"
		info "自 SDK 路径复制可选 fragment:"
		local name
		for name in tspi-vendor.config rk3576.config; do
			[[ -f "${TSPI_KERNEL_CONFIG_SOURCE}/${name}" ]] || continue
			install_fragment "${TSPI_KERNEL_CONFIG_SOURCE}/${name}"
		done
	fi

	local local_frags=()
	shopt -s nullglob
	local_frags=( "${vendor_cfg_dir}"/*.config )
	shopt -u nullglob
	[[ ${#local_frags[@]} -gt 0 ]] || die "vendor/kernel-config 下无 .config 文件"

	info "自 vendor/kernel-config 复制:"
	local f
	for f in "${local_frags[@]}"; do
		install_fragment "${f}"
	done
}

cmd_sync() {
	local what="${1:-}"
	case "${what}" in
		dts) cmd_sync_dts ;;
		config) cmd_sync_config ;;
		*) die "sync 用法: ./bsp sync [dts|config]" ;;
	esac
}
