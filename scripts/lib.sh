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
: "${CROSS_COMPILE_PREFIX:=aarch64-linux-gnu-}"
: "${TOOLCHAIN_BIN:=}"
: "${RKBIN_BACKUP_SRC:=}"
: "${MAKE_JOBS:=}"

SOURCES_DIR="${BSP_ROOT}/sources"
BACKUP_DIR="${BSP_ROOT}/backup"
UBOOT_DIR="${SOURCES_DIR}/u-boot"
RKBIN_DIR="${SOURCES_DIR}/rkbin"
LOCAL_BIN="${BSP_ROOT}/.local/bin"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

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
