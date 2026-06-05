#!/bin/bash
# 克隆 GitHub kernel 并同步泰山派设备树

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

mkdir -p "${SOURCES_DIR}"

clone_or_update() {
	local url="$1"
	local branch="$2"
	local dir="$3"
	local name
	name="$(basename "${dir}")"

	if [[ -d "${dir}/.git" ]]; then
		info "更新 ${name} (${branch})..."
		git -C "${dir}" fetch origin
		git -C "${dir}" checkout "${branch}"
		git -C "${dir}" pull --ff-only origin "${branch}" || true
	else
		info "克隆 ${name} (${branch})，体积较大，请耐心等待..."
		git clone --depth 1 -b "${branch}" "${url}" "${dir}"
	fi
}

clone_or_update "${KERNEL_REPO}" "${KERNEL_BRANCH}" "${KERNEL_DIR}"

"${SCRIPT_DIR}/sync-kernel-dts.sh"

info "内核源码就绪: ${KERNEL_DIR}"
