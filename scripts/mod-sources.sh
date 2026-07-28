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
		# 更新后需重新打 RT 补丁
		rm -f "${dir}/.bsp-rt-applied"
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
	apply_kernel_rt_patches
	info "内核源码就绪: ${KERNEL_DIR}"
}

# 过滤官方 RT 补丁中与 Ky 树冲突的 riscv 文件，写出可直接 patch 的文本
filter_rt_patch_for_ky() {
	local src_patch="$1"
	local dst_patch="$2"
	python3 - "$src_patch" "$dst_patch" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, "rb").read().decode("utf-8", "replace")
parts = re.split(r"(?=^diff --git )", text, flags=re.M)
skip = {
	"a/arch/riscv/Kconfig",
	"a/arch/riscv/include/asm/cpufeature.h",
	"a/arch/riscv/include/asm/thread_info.h",
	"a/arch/riscv/kernel/cpufeature.c",
	"a/arch/riscv/kernel/smpboot.c",
}
out = []
for p in parts:
	if not p.strip():
		continue
	m = re.match(r"diff --git (a/\S+)", p)
	if m and m.group(1) in skip:
		continue
	out.append(p)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
}

download_kernel_rt_patch() {
	local dest="${BSP_ROOT}/dl/${KERNEL_RT_PATCH_NAME}"
	mkdir -p "${BSP_ROOT}/dl"
	if [[ -f "${dest}" ]]; then
		echo "${dest}"
		return 0
	fi
	info "下载 PREEMPT_RT 补丁: ${KERNEL_RT_PATCH_URL}"
	if ! curl -fsSL --connect-timeout 30 -o "${dest}.partial" "${KERNEL_RT_PATCH_URL}"; then
		rm -f "${dest}.partial"
		die "下载 RT 补丁失败，可手动放到 ${dest}"
	fi
	mv "${dest}.partial" "${dest}"
	echo "${dest}"
}

# 应用官方 6.6.63-rt46（过滤冲突文件）+ vendor riscv 适配
apply_kernel_rt_patches() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"
	if [[ "${KERNEL_RT}" != "y" && "${KERNEL_RT}" != "1" ]]; then
		info "KERNEL_RT=${KERNEL_RT}，跳过 PREEMPT_RT 补丁"
		return 0
	fi

	local marker="${KERNEL_DIR}/.bsp-rt-applied"
	local localver="${KERNEL_DIR}/localversion-rt"
	if [[ -f "${marker}" ]] && [[ -f "${localver}" ]]; then
		info "PREEMPT_RT 补丁已应用 ($(cat "${marker}"))，检查增量适配补丁..."
		local p
		shopt -s nullglob
		for p in "${BSP_ROOT}/vendor/patches/kernel"/0002-*.patch \
			"${BSP_ROOT}/vendor/patches/kernel"/000[3-9]-*.patch; do
			# --forward：已打过则跳过；新补丁则补上
			if ! patch -d "${KERNEL_DIR}" -p1 --forward --batch --dry-run < "${p}" >/dev/null 2>&1; then
				continue
			fi
			info "应用增量 $(basename "${p}")"
			patch -d "${KERNEL_DIR}" -p1 --forward --batch < "${p}" || \
				die "应用 ${p} 失败"
		done
		shopt -u nullglob
		return 0
	fi

	command -v patch >/dev/null 2>&1 || die "需要 patch 命令（apt install patch）"
	command -v xz >/dev/null 2>&1 || die "需要 xz（apt install xz-utils）"
	command -v python3 >/dev/null 2>&1 || die "需要 python3"

	local xz_path filtered adapt
	xz_path="$(download_kernel_rt_patch)"
	filtered="${BSP_ROOT}/dl/${KERNEL_RT_PATCH_NAME%.xz}-ky-filtered.patch"
	info "过滤 Ky 冲突的 riscv 文件并打补丁..."
	xz -dc "${xz_path}" > "${BSP_ROOT}/dl/${KERNEL_RT_PATCH_NAME%.xz}"
	filter_rt_patch_for_ky "${BSP_ROOT}/dl/${KERNEL_RT_PATCH_NAME%.xz}" "${filtered}"

	if ! patch -d "${KERNEL_DIR}" -p1 --forward --batch < "${filtered}"; then
		die "应用官方 RT 补丁失败（见上方 patch 输出）"
	fi

	adapt="${BSP_ROOT}/vendor/patches/kernel/0001-riscv-enable-PREEMPT_RT-ky.patch"
	[[ -f "${adapt}" ]] || die "缺少 ${adapt}"
	info "应用 Ky riscv RT 适配: $(basename "${adapt}")"
	if ! patch -d "${KERNEL_DIR}" -p1 --forward --batch < "${adapt}"; then
		die "应用 ${adapt} 失败"
	fi

	# 其余按序应用（如 softirq ifdef 修复）
	local p
	shopt -s nullglob
	for p in "${BSP_ROOT}/vendor/patches/kernel"/0002-*.patch \
		"${BSP_ROOT}/vendor/patches/kernel"/000[3-9]-*.patch; do
		info "应用 $(basename "${p}")"
		if ! patch -d "${KERNEL_DIR}" -p1 --forward --batch < "${p}"; then
			die "应用 ${p} 失败"
		fi
	done
	shopt -u nullglob

	[[ -f "${localver}" ]] || die "打补丁后缺少 localversion-rt，补丁可能不完整"
	printf '%s\n' "${KERNEL_RT_PATCH_NAME}" > "${marker}"
	info "PREEMPT_RT 就绪: $(tr -d '\n' < "${localver}") ($(cat "${marker}"))"
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

	info "安装 kernel config fragment -> ${kernel_configs_dir}"

	local local_frags=()
	shopt -s nullglob
	local_frags=( "${vendor_cfg_dir}"/*.config )
	shopt -u nullglob

	if [[ ${#local_frags[@]} -eq 0 ]]; then
		warn "vendor/kernel-config 下无 .config 文件"
		return 0
	fi

	local f base
	for f in "${local_frags[@]}"; do
		base="$(basename "${f}")"
		# 完整 .config 副本不当作 arch/*/configs fragment（体积大且非 merge 用途）
		[[ "${base}" == linux-*-current.config ]] && continue
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
