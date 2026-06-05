#!/bin/bash
# 编译 GitHub u-boot（RK3576，--spl-new）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

SOURCES_DIR="${ROOT_DIR}/sources"
UBOOT_DIR="${SOURCES_DIR}/u-boot"
RKBIN_LINK="${SOURCES_DIR}/rkbin"
PREBUILTS_LINK="${SOURCES_DIR}/prebuilts"
LOG_DIR="${ROOT_DIR}/logs"
BUILD_LOG="${LOG_DIR}/build-uboot-$(date +%Y%m%d-%H%M%S).log"

[[ -d "$UBOOT_DIR" ]] || die "请先运行: ./scripts/setup-sources.sh"
[[ -e "$RKBIN_LINK" ]] || die "缺少 sources/rkbin 链接，请先运行 setup-sources.sh"

JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"
CROSS_COMPILE_ARG=""

if [[ "${USE_SDK_PREBUILTS}" == "y" ]]; then
	GCC_DIR="${PREBUILTS_LINK}/gcc/linux-x86/aarch64"
	GCC_BIN="$(find "$GCC_DIR" -name 'aarch64-none-linux-gnu-gcc' -type f 2>/dev/null | head -1)"
	[[ -n "$GCC_BIN" ]] || GCC_BIN="$(find "$GCC_DIR" -name 'aarch64-linux-gnu-gcc' -type f 2>/dev/null | head -1)"
	[[ -n "$GCC_BIN" ]] || die "在 SDK prebuilts 中未找到 aarch64 gcc: $GCC_DIR"
	CROSS_COMPILE_ARG="CROSS_COMPILE=${GCC_BIN%gcc}"
	info "工具链: ${CROSS_COMPILE_ARG#CROSS_COMPILE=}"
else
	command -v "${CROSS_COMPILE_PREFIX}gcc" >/dev/null 2>&1 || \
		die "未找到 ${CROSS_COMPILE_PREFIX}gcc，请 apt install gcc-aarch64-linux-gnu 或开启 USE_SDK_PREBUILTS=y"
	CROSS_COMPILE_ARG="CROSS_COMPILE=${CROSS_COMPILE_PREFIX}"
	info "工具链: ${CROSS_COMPILE_PREFIX}"
fi

ensure_dir "$LOG_DIR"

info "开始编译 ${UBOOT_BOARD} (jobs=${JOBS}, --spl-new)..."
info "日志: ${BUILD_LOG}"

(
	cd "$UBOOT_DIR"
	# make.sh 要求 ../rkbin 与 u-boot 同级
	[[ -d ../rkbin ]] || die "u-boot 同级目录缺少 rkbin"

	set -x
	./make.sh "$UBOOT_BOARD" --spl-new "$CROSS_COMPILE_ARG" 2>&1 | tee "$BUILD_LOG"
	set +x

	echo ""
	echo "=== 编译产物 ==="
	ls -lh uboot.img trust.img rk3576_* 2>/dev/null || true
) 

info "编译完成"
