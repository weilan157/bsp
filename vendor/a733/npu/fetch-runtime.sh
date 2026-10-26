#!/bin/bash
# fetch-runtime.sh —— 拉取并编译 A733 NPU 用户态 runtime（VIPLite / vpm_run）
#
# 参考：https://github.com/jackhe183/radxa-dev（Radxa Cubie A7Z NPU 实战指南）
#   - A733 的 NPU 是 VeriSilicon VIPLite（3 TOPS），驱动节点 /dev/vipcore
#   - 用户态库在 ai-sdk/viplite-tina/lib/aarch64-none-linux-gnu/v2.0/
#   - 运行工具 examples/vpm_run（交叉编译）
#
# 用法： bash fetch-runtime.sh [--dest DIR]
# 产物： <dest>/stage/{lib,bin,share}，由 ./bsp rootfs 拷进镜像
set -euo pipefail

DEST="${1:-}"
if [ "$DEST" = "--dest" ]; then
	DEST="${2:-}"
fi
[ -n "$DEST" ] || DEST="${A733_NPU_RUNTIME_DIR:-/tmp/a733-npu-runtime}"

REPO="${A733_NPU_SDK_REPO:-https://github.com/jackhe183/radxa-dev.git}"
BRANCH="${A733_NPU_SDK_BRANCH:-main}"
CC="${A733_CROSS_COMPILE:-aarch64-linux-gnu-}"
SRC="$DEST/radxa-dev"
SDK="$SRC/npu_test/ai-sdk"
V="$SDK/viplite-tina/lib/aarch64-none-linux-gnu/v2.0"

log() { printf '[npu] %s\n' "$*"; }
die() { printf '[npu] 错误: %s\n' "$*" >&2; exit 1; }

mkdir -p "$DEST"

if [ ! -f "$V/libNBGlinker.so" ]; then
	log "拉取 ai-sdk（sparse）: $REPO"
	rm -rf "$SRC"
	git clone --depth 1 --filter=blob:none --sparse -b "$BRANCH" "$REPO" "$SRC" \
		|| die "克隆失败: $REPO"
	git -C "$SRC" sparse-checkout set \
		npu_test/ai-sdk/viplite-tina \
		npu_test/ai-sdk/examples/vpm_run \
		npu_test/ai-sdk/machinfo >/dev/null 2>&1 || die "sparse-checkout 失败"
fi

[ -f "$V/libNBGlinker.so" ] || die "缺少 $V/libNBGlinker.so"
[ -d "$SDK/examples/vpm_run" ] || die "缺少 examples/vpm_run"

log "交叉编译 vpm_run（$CC）"
(
	cd "$SDK/examples/vpm_run"
	make clean >/dev/null 2>&1 || true
	make AI_SDK_PLATFORM=a733 NPU_SW_VERSION=v2.0 CC="${CC}gcc" >/dev/null 2>&1 || \
		die "vpm_run 编译失败"
)
[ -x "$SDK/examples/vpm_run/vpm_run" ] || die "没有生成 vpm_run"

log "准备 stage 目录"
rm -rf "$DEST/stage"
mkdir -p "$DEST/stage/lib" "$DEST/stage/bin" "$DEST/stage/share" "$DEST/stage/etc"
cp -f "$V/libNBGlinker.so" "$V/libVIPhal.so" "$DEST/stage/lib/"
cp -f "$SDK/examples/vpm_run/vpm_run" "$DEST/stage/bin/"
cp -f "$SDK/examples/vpm_run/lenet.nb" "$SDK/examples/vpm_run/lenet.dat" \
	"$DEST/stage/share/" 2>/dev/null || true
if [ -f "$SDK/examples/vpm_run/sample_lenet.txt" ]; then
	cp -f "$SDK/examples/vpm_run/sample_lenet.txt" "$DEST/stage/share/"
else
	cat > "$DEST/stage/share/sample_lenet.txt" <<'EOF'
[network]
/usr/share/npu/lenet.nb
[input]
/usr/share/npu/lenet.dat
EOF
fi
cat > "$DEST/stage/etc/viplite.sh" <<'EOF'
# VIPLite 用户态库（由 ./bsp rootfs 安装）
export LD_LIBRARY_PATH="/usr/lib/viplite${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOF

log "完成: $(du -sh "$DEST/stage" | cut -f1)（lib $(du -sh "$DEST/stage/lib" | cut -f1)，bin $(du -sh "$DEST/stage/bin" | cut -f1)）"
