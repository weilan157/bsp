#!/bin/bash
# 源码克隆与 DTS/config 同步（Ky X1 / RISC-V）

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

cmd_setup_uboot_sources() {
	mkdir -p "${SOURCES_DIR}" "${BACKUP_DIR}"
	clone_or_update "${UBOOT_REPO}" "${UBOOT_BRANCH}" "${UBOOT_DIR}"
	info "源码就绪:"
	info "  u-boot: ${UBOOT_DIR}"
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

# Ky 内核已自带 arch/riscv/boot/dts/ky；仅在有 vendor 覆盖时同步
cmd_sync_dts() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	local dts_src="" kernel_dts_dir
	kernel_dts_dir="${KERNEL_DIR}/arch/${KERNEL_ARCH}/boot/dts/${KERNEL_DTS_SUBDIR}"

	if [[ -n "${VENDOR_DTS_SOURCE}" ]]; then
		[[ -d "${VENDOR_DTS_SOURCE}" ]] || die "VENDOR_DTS_SOURCE 不是目录: ${VENDOR_DTS_SOURCE}"
		dts_src="${VENDOR_DTS_SOURCE}"
	elif [[ -d "${VENDOR_DTS_DIR}" ]] && compgen -G "${VENDOR_DTS_DIR}/*" >/dev/null; then
		dts_src="${VENDOR_DTS_DIR}"
	fi

	if [[ -z "${dts_src}" ]]; then
		info "使用内核树自带设备树: ${kernel_dts_dir}"
		[[ -d "${kernel_dts_dir}" ]] || die "内核缺少 dts 目录: ${kernel_dts_dir}"
		return 0
	fi

	info "设备树覆盖来源: ${dts_src} -> ${kernel_dts_dir}"
	mkdir -p "${kernel_dts_dir}"
	rsync -a "${dts_src}/" "${kernel_dts_dir}/"
	info "设备树同步完成"
}

cmd_sync_config() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"

	local kernel_configs_dir vendor_cfg_dir
	kernel_configs_dir="${KERNEL_DIR}/arch/${KERNEL_ARCH}/configs"
	vendor_cfg_dir="${BSP_ROOT}/vendor/kernel-config"
	mkdir -p "${kernel_configs_dir}"

	install_fragment() {
		local src="$1"
		install -m 644 "${src}" "${kernel_configs_dir}/$(basename "${src}")"
		info "  $(basename "${src}")"
	}

	info "安装 kernel config -> ${kernel_configs_dir}"

	local local_frags=()
	shopt -s nullglob
	local_frags=( "${vendor_cfg_dir}"/*.config )
	shopt -u nullglob

	if [[ ${#local_frags[@]} -eq 0 ]]; then
		warn "vendor/kernel-config 下无 .config 文件"
		return 0
	fi

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
