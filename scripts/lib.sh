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
: "${KERNEL_EXTRA_FRAGMENTS:=}"
: "${DEBIAN_RELEASE:=trixie}"
: "${DEBIAN_ARCH:=riscv64}"
: "${DEBIAN_MIRROR:=mirrors.tuna.tsinghua.edu.cn}"
: "${DEBIAN_VARIANT:=minbase}"
: "${ROOTFS_HOSTNAME:=orangepi}"
: "${ROOTFS_LOCALE:=en_US.UTF-8}"
: "${ROOTFS_ROOT_PASSWORD:=root}"
: "${ROOTFS_USER:=orangepi}"
: "${ROOTFS_USER_PASSWORD:=orangepi}"
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
VENDOR_DTS_DIR="${BSP_ROOT}/vendor/dts/${KERNEL_DTS_SUBDIR}"
OUT_DIR="${BSP_ROOT}/out"
LOCAL_BIN="${BSP_ROOT}/.local/bin"
TOOLCHAIN_DIR="${BSP_ROOT}/toolchains/${TOOLCHAIN_NAME}"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
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
	echo "${frags}"
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
