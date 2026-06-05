#!/bin/bash
# 公共函数

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"

die() {
	echo "ERROR: $*" >&2
	exit 1
}

info() {
	echo "[INFO] $*"
}

warn() {
	echo "[WARN] $*" >&2
}

load_config() {
	[[ -f "$CONFIG_FILE" ]] || die "缺少 config.env，请执行: cp config.env.example config.env"
	# shellcheck disable=SC1090
	source "$CONFIG_FILE"
	[[ -n "${TSPI_SDK_ROOT:-}" ]] || die "config.env 中未设置 TSPI_SDK_ROOT"
}

ensure_dir() {
	mkdir -p "$@"
}

git_head_short() {
	local dir="$1"
	if [[ -d "$dir/.git" ]]; then
		git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown"
	else
		echo "no-git"
	fi
}

git_head_full() {
	local dir="$1"
	if [[ -d "$dir/.git" ]]; then
		git -C "$dir" rev-parse HEAD 2>/dev/null || echo "unknown"
	else
		echo "no-git"
	fi
}
