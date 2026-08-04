#!/bin/bash
# rockchip-bsp / Orange Pi Ky X1 公共函数

set -euo pipefail

BSP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${BSP_ROOT}/config.env"

if [[ -f "${CONFIG_FILE}" ]]; then
	# shellcheck source=/dev/null
	source "${CONFIG_FILE}"
elif [[ "${BSP_ALLOW_MISSING_CONFIG:-}" == "1" ]]; then
	:
else
	echo "错误: 未找到 ${CONFIG_FILE}，请先 cp config.env.example config.env 或运行 ./bsp config" >&2
	exit 1
fi

: "${BOARD:=orangepir2s}"
: "${UBOOT_REPO:=https://github.com/orangepi-xunlong/u-boot-orangepi.git}"
: "${UBOOT_BRANCH:=v2022.10-ky}"
: "${RKBIN_REPO:=}"
: "${RKBIN_BRANCH:=}"
: "${UBOOT_BOARD:=x1}"
: "${KERNEL_REPO:=https://github.com/orangepi-xunlong/linux-orangepi.git}"
: "${KERNEL_BRANCH:=orange-pi-6.6-ky}"
: "${KERNEL_ARCH:=riscv}"
: "${KERNEL_DEFCONFIG:=}"
: "${KERNEL_DOTCONFIG:=}"
: "${KERNEL_DEFCONFIG_FRAGMENTS:=}"
: "${KERNEL_DTS_NAME:=x1_orangepi-r2s}"
: "${KERNEL_DTS_SUBDIR:=ky}"
: "${VENDOR_DTS_SOURCE:=}"
# PREEMPT_RT：默认开启（下载并打 6.6.63-rt46 + Ky riscv 适配）
: "${KERNEL_RT:=y}"
: "${KERNEL_RT_PATCH_URL:=https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.6/older/patch-6.6.63-rt46.patch.xz}"
: "${KERNEL_RT_PATCH_NAME:=patch-6.6.63-rt46.patch.xz}"
# 外置 IgH EtherCAT（官方 stable-1.6 线；与 KERNEL_RT 无关）
: "${KERNEL_ETHERCAT:=y}"
: "${ETHERCAT_REPO:=https://gitlab.com/etherlab.org/ethercat.git}"
: "${ETHERCAT_BRANCH:=stable-1.6}"
# 发布 tarball（含 configure，无需主机 bootstrap）；与 stable-1.6 对齐
: "${ETHERCAT_VERSION:=1.6.10}"
: "${ETHERCAT_DIST_URL:=https://gitlab.com/api/v4/projects/24894054/packages/generic/ethercat/${ETHERCAT_VERSION}/ethercat-${ETHERCAT_VERSION}.tar.gz}"
# git：拉分支后需 autoconf bootstrap；dist：默认用官方发布包（推荐）
: "${ETHERCAT_SOURCE:=dist}"
# 设备驱动：r8169（原生 ec_r8169，RTL8125）或 generic
: "${ETHERCAT_DEVICE_MODULE:=r8169}"
# IgH 无 6.6 专用树；Ky 6.6 用最接近的 6.4
: "${ETHERCAT_R8169_KERNEL:=6.4}"
# RTL8125B 固件（ec_r8169 / r8125 均可 request_firmware）
: "${ETHERCAT_RTL8125_FW_URL:=https://raw.githubusercontent.com/armbian/firmware/master/rtl_nic/rtl8125b-2.fw}"
: "${ETHERCAT_RTL8125_FW_NAME:=rtl8125b-2.fw}"
# 默认 fragment：slim +（KERNEL_RT=y 时）rt +（KERNEL_ETHERCAT=y 时关闭内核内嵌 EC）
_kernel_default_frags="${BSP_ROOT}/vendor/kernel-config/slim.config"
if [[ "${KERNEL_RT}" == "y" || "${KERNEL_RT}" == "1" ]]; then
	_kernel_default_frags="${_kernel_default_frags} ${BSP_ROOT}/vendor/kernel-config/rt.config"
fi
if [[ "${KERNEL_ETHERCAT}" == "y" || "${KERNEL_ETHERCAT}" == "1" ]]; then
	_kernel_default_frags="${_kernel_default_frags} ${BSP_ROOT}/vendor/kernel-config/ethercat.config"
fi
: "${KERNEL_EXTRA_FRAGMENTS:=${_kernel_default_frags}}"
unset _kernel_default_frags
: "${DEBIAN_RELEASE:=trixie}"
: "${DEBIAN_ARCH:=riscv64}"
: "${DEBIAN_MIRROR:=mirrors.tuna.tsinghua.edu.cn}"
: "${DEBIAN_VARIANT:=minbase}"
: "${ROOTFS_HOSTNAME:=orangepi}"
: "${ROOTFS_LOCALE:=en_US.UTF-8}"
: "${ROOTFS_ROOT_PASSWORD:=root}"
: "${ROOTFS_USER:=weiqi}"
: "${ROOTFS_USER_PASSWORD:=321}"
: "${BOOT_CMD_SRC:=${BSP_ROOT}/vendor/boot/boot-ky.cmd}"
: "${BOOT_ENV_SRC:=${BSP_ROOT}/vendor/boot/orangepiEnv.txt}"
: "${MKIMAGE_BIN:=}"
: "${KERNEL_MODULES_INSTALL:=y}"
: "${CROSS_COMPILE_PREFIX:=riscv64-unknown-linux-gnu-}"
: "${TOOLCHAIN_BIN:=}"
: "${TOOLCHAIN_NAME:=ky-toolchain-linux-glibc-x86_64-v1.0.1}"
: "${TOOLCHAIN_URL:=http://www.iplaystore.cn/upload/_toolchain/ky-toolchain-linux-glibc-x86_64-v1.0.1.tar.xz}"
: "${MAKE_JOBS:=}"
: "${SD_OFFSET_MIB:=30}"
: "${SD_BOOT_MIB:=256}"
: "${SD_ROOTFS_EXTRA_MIB:=256}"
: "${SD_IMAGE:=}"

SOURCES_DIR="${BSP_ROOT}/sources"
BACKUP_DIR="${BSP_ROOT}/backup"
UBOOT_DIR="${SOURCES_DIR}/u-boot"
RKBIN_DIR="${SOURCES_DIR}/rkbin"
KERNEL_DIR="${SOURCES_DIR}/kernel"
ETHERCAT_DIR="${SOURCES_DIR}/ethercat"
VENDOR_DTS_DIR="${BSP_ROOT}/vendor/dts/${KERNEL_DTS_SUBDIR}"
OUT_DIR="${BSP_ROOT}/out"
LOCAL_BIN="${BSP_ROOT}/.local/bin"
TOOLCHAIN_DIR="${BSP_ROOT}/toolchains/${TOOLCHAIN_NAME}"

# 日志一律走 stderr，避免 $(func) 捕获 echo 返回值时混入 [INFO]
info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

run_root() {
	# sudo 默认 secure_path 不含交叉工具链；保留调用方 PATH（strip/gcc 等）
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo env "PATH=${PATH}" "$@"
	fi
}

ensure_host_build_tools() {
	local ht="${BSP_ROOT}/.local/host-tools"
	if [[ -d "${ht}/usr/bin" ]]; then
		export PATH="${ht}/usr/bin:${ht}/usr/sbin:${PATH}"
		[[ -d "${ht}/usr/share/bison" ]] && export BISON_PKGDATADIR="${ht}/usr/share/bison"
	fi
}

ensure_python2_wrapper() {
	mkdir -p "${LOCAL_BIN}"
	if [[ ! -x "${LOCAL_BIN}/python2" ]]; then
		cat > "${LOCAL_BIN}/python2" <<'PYWRAP'
#!/bin/sh
exec python3 "$@"
PYWRAP
		chmod +x "${LOCAL_BIN}/python2"
		info "已创建 ${LOCAL_BIN}/python2 -> python3 包装"
	fi
	export PATH="${LOCAL_BIN}:${PATH}"
}

resolve_toolchain_bin() {
	if [[ -n "${TOOLCHAIN_BIN}" ]]; then
		echo "${TOOLCHAIN_BIN}"
		return
	fi
	if [[ -d "${TOOLCHAIN_DIR}/bin" ]]; then
		echo "${TOOLCHAIN_DIR}/bin"
		return
	fi
	echo ""
}

setup_cross_compile() {
	ensure_host_build_tools
	local tb
	tb="$(resolve_toolchain_bin)"
	if [[ -n "${tb}" ]]; then
		[[ -d "${tb}" ]] || die "TOOLCHAIN_BIN 不存在: ${tb}"
		export PATH="${tb}:${PATH}"
	fi
	local cc="${CROSS_COMPILE_PREFIX}gcc"
	command -v "${cc}" >/dev/null 2>&1 || \
		die "未找到 ${cc}，请运行 ./bsp env（会下载 Ky toolchain）或设置 TOOLCHAIN_BIN"
	export CROSS_COMPILE="${CROSS_COMPILE_PREFIX}"
	export ARCH="${KERNEL_ARCH}"
	# modules_install INSTALL_MOD_STRIP 需要；绝对路径避免 sudo/make 子进程丢 PATH
	if command -v "${CROSS_COMPILE_PREFIX}strip" >/dev/null 2>&1; then
		export STRIP="$(command -v "${CROSS_COMPILE_PREFIX}strip")"
	else
		warn "未找到 ${CROSS_COMPILE_PREFIX}strip，modules_install 将无法 strip 模块"
	fi
	info "CROSS_COMPILE=${CROSS_COMPILE} ARCH=${ARCH}"
}

job_count() {
	if [[ -n "${MAKE_JOBS}" ]]; then
		echo "${MAKE_JOBS}"
	else
		nproc
	fi
}

kernel_defconfig_fragments() {
	local frags="${KERNEL_DEFCONFIG_FRAGMENTS}"
	if [[ -n "${KERNEL_EXTRA_FRAGMENTS}" ]]; then
		frags="${frags} ${KERNEL_EXTRA_FRAGMENTS//,/ }"
	fi
	# 压缩空白，避免 make/merge 吃到空参数
	echo "${frags}" | xargs
}

# 将 fragment 合并进 KERNEL_DIR/.config（完整 .config 与 defconfig 路径均适用）
apply_kernel_config_fragments() {
	local merge_script frag
	local -a frag_list=()
	local frags
	frags="$(kernel_defconfig_fragments)"
	[[ -n "${frags}" ]] || return 0

	# shellcheck disable=SC2086
	for frag in ${frags}; do
		[[ -f "${frag}" ]] || die "内核配置片段不存在: ${frag}"
		# 完整 config 不当作 fragment 再合并（避免自引用）
		[[ "$(basename "${frag}")" == "linux-ky-current.config" ]] && continue
		frag_list+=("${frag}")
	done
	((${#frag_list[@]} > 0)) || return 0

	info "合并内核配置片段: ${frag_list[*]}"
	merge_script="${KERNEL_DIR}/scripts/kconfig/merge_config.sh"
	if [[ -f "${merge_script}" ]]; then
		# -m：只合并不 olddefconfig；随后由调用方 olddefconfig
		ARCH="${KERNEL_ARCH}" bash "${merge_script}" -m -O "${KERNEL_DIR}" \
			"${KERNEL_DIR}/.config" "${frag_list[@]}"
	else
		warn "无 merge_config.sh，追加 fragment 到 .config"
		cat "${frag_list[@]}" >> "${KERNEL_DIR}/.config"
	fi
}

sd_image_path() {
	if [[ -n "${SD_IMAGE}" ]]; then
		echo "${SD_IMAGE}"
	else
		echo "${OUT_DIR}/${BOARD}.img"
	fi
}

: "${BSP_FORCE:=0}"
: "${BSP_UPDATE:=0}"

bsp_want_force() { [[ "${BSP_FORCE}" == "1" || "${BSP_FORCE}" == "y" ]]; }
bsp_want_update() { [[ "${BSP_UPDATE}" == "1" || "${BSP_UPDATE}" == "y" ]]; }
# 构建产物是否强制重做：--clean 或 --update（源码/下载已变，产物视为过期）
bsp_want_rebuild() { bsp_want_force || bsp_want_update; }

DL_DIR="${BSP_ROOT}/dl"

# --update 时删除已有下载物，迫使重新拉取
bsp_refresh_download() {
	local path="$1"
	if bsp_want_update && [[ -e "${path}" ]]; then
		info "刷新下载: ${path#"${BSP_ROOT}/"}"
		rm -rf "${path}"
	fi
}

have_uboot_artifacts() {
	[[ -f "${UBOOT_DIR}/u-boot-opensbi.itb" ]] && \
		[[ -f "${UBOOT_DIR}/FSBL.bin" ]] && \
		[[ -f "${UBOOT_DIR}/bootinfo_sd.bin" ]] && \
		[[ -f "${UBOOT_DIR}/u-boot-env-default.bin" ]]
}

have_kernel_artifacts() {
	[[ -f "${OUT_DIR}/kernel/Image" ]] && \
		[[ -f "${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb" ]]
}

have_bootimg_artifacts() {
	[[ -f "${OUT_DIR}/boot.img" ]] && [[ -f "${OUT_DIR}/boot/boot.scr" ]]
}

# kernel/dtb 比 boot.img 新时需重打包（避免只编了 kernel 却刷到旧 boot）
bootimg_stale_vs_kernel() {
	local ki kd bi
	ki="${OUT_DIR}/kernel/Image"
	kd="${OUT_DIR}/kernel/${KERNEL_DTS_NAME}.dtb"
	bi="${OUT_DIR}/boot.img"
	[[ -f "${bi}" ]] || return 0
	[[ -f "${ki}" && -f "${kd}" ]] || return 1
	[[ "${ki}" -nt "${bi}" || "${kd}" -nt "${bi}" ]]
}

have_rootfs_artifacts() {
	[[ -f "${OUT_DIR}/rootfs.ext4" ]]
}

have_pack_artifacts() {
	[[ -f "$(sd_image_path)" ]]
}

parse_build_flags() {
	BSP_CMD_ARGS=()
	local a
	for a in "$@"; do
		case "${a}" in
			--clean|--force) export BSP_FORCE=1 ;;
			--update) export BSP_UPDATE=1 ;;
			*) BSP_CMD_ARGS+=("${a}") ;;
		esac
	done
}
