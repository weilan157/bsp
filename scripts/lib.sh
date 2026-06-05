#!/bin/bash
# rockchip-bsp 公共函数

set -euo pipefail

BSP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${BSP_ROOT}/config.env"

if [[ -f "${CONFIG_FILE}" ]]; then
	# shellcheck source=/dev/null
	source "${CONFIG_FILE}"
else
	echo "错误: 未找到 ${CONFIG_FILE}，请先 cp config.env.example config.env" >&2
	exit 1
fi

: "${UBOOT_REPO:=https://github.com/rockchip-linux/u-boot.git}"
: "${UBOOT_BRANCH:=next-dev}"
: "${RKBIN_REPO:=https://github.com/rockchip-linux/rkbin.git}"
: "${RKBIN_BRANCH:=master}"
: "${UBOOT_BOARD:=rk3576}"
: "${KERNEL_REPO:=https://github.com/rockchip-linux/kernel.git}"
: "${KERNEL_BRANCH:=develop-6.1}"
: "${KERNEL_DEFCONFIG:=rockchip_linux_defconfig}"
: "${KERNEL_DEFCONFIG_FRAGMENTS:=rk3576.config}"
: "${KERNEL_DTS_NAME:=tspi-3m-rk3576}"
: "${TSPI_DTS_SOURCE:=}"
: "${TSPI_VENDOR_KERNEL_CONFIG:=n}"
: "${TSPI_KERNEL_CONFIG_SOURCE:=}"
: "${KERNEL_EXTRA_FRAGMENTS:=}"
: "${DEBIAN_RELEASE:=trixie}"
: "${DEBIAN_ARCH:=arm64}"
: "${DEBIAN_MIRROR:=deb.debian.org}"
: "${DEBIAN_VARIANT:=minbase}"
: "${ROOTFS_HOSTNAME:=rockchip}"
: "${ROOTFS_LOCALE:=en_US.UTF-8}"
: "${ROOTFS_ROOT_PASSWORD:=root}"
: "${ROOTFS_USER:=debian}"
: "${ROOTFS_USER_PASSWORD:=debian}"
: "${BOOT_FIT_ITS:=${BSP_ROOT}/vendor/fit/boot.its}"
: "${MKIMAGE_BIN:=}"
: "${KERNEL_MODULES_INSTALL:=y}"
: "${PACK_TOOLS_DIR:=${BSP_ROOT}/vendor/tools/pack-firmware}"
: "${PACK_TOOLS_SRC:=}"
: "${FIRMWARE_PARAMETER:=${BSP_ROOT}/vendor/firmware/parameter.txt}"
: "${FIRMWARE_PACKAGE_FILE:=${BSP_ROOT}/vendor/firmware/package-file}"
: "${CROSS_COMPILE_PREFIX:=aarch64-linux-gnu-}"
: "${TOOLCHAIN_BIN:=}"
: "${RKBIN_BACKUP_SRC:=}"
: "${MAKE_JOBS:=}"

SOURCES_DIR="${BSP_ROOT}/sources"
BACKUP_DIR="${BSP_ROOT}/backup"
UBOOT_DIR="${SOURCES_DIR}/u-boot"
RKBIN_DIR="${SOURCES_DIR}/rkbin"
KERNEL_DIR="${SOURCES_DIR}/kernel"
VENDOR_DTS_DIR="${BSP_ROOT}/vendor/dts/rockchip"
OUT_DIR="${BSP_ROOT}/out"
LOCAL_BIN="${BSP_ROOT}/.local/bin"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

# 无 sudo 时可用 .local/host-tools（flex/bison 等，见 scripts/fetch-host-tools.sh）
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

setup_cross_compile() {
	ensure_host_build_tools
	if [[ -n "${TOOLCHAIN_BIN}" ]]; then
		[[ -d "${TOOLCHAIN_BIN}" ]] || die "TOOLCHAIN_BIN 不存在: ${TOOLCHAIN_BIN}"
		export PATH="${TOOLCHAIN_BIN}:${PATH}"
	fi
	local cc="${CROSS_COMPILE_PREFIX}gcc"
	command -v "${cc}" >/dev/null 2>&1 || die "未找到 ${cc}，请运行 ./scripts/init-env.sh 或设置 TOOLCHAIN_BIN"
	export CROSS_COMPILE="${CROSS_COMPILE_PREFIX}"
	info "CROSS_COMPILE=${CROSS_COMPILE}"
}

job_count() {
	if [[ -n "${MAKE_JOBS}" ]]; then
		echo "${MAKE_JOBS}"
	else
		nproc
	fi
}

# 返回传给 make 的 defconfig fragment 列表（空格分隔）
kernel_defconfig_fragments() {
	local frags="${KERNEL_DEFCONFIG_FRAGMENTS}"

	if [[ "${TSPI_VENDOR_KERNEL_CONFIG}" == "y" ]]; then
		frags="${frags} tspi-vendor.config"
	fi
	if [[ -n "${KERNEL_EXTRA_FRAGMENTS}" ]]; then
		frags="${frags} ${KERNEL_EXTRA_FRAGMENTS//,/ }"
	fi
	echo "${frags}"
}
