#!/bin/bash
# 从 GitHub 克隆 u-boot / rkbin（不依赖任何 SDK）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

mkdir -p "${SOURCES_DIR}" "${BACKUP_DIR}"

backup_local_rkbin() {
	[[ -n "${RKBIN_BACKUP_SRC}" ]] || return 0
	[[ -d "${RKBIN_BACKUP_SRC}" ]] || die "RKBIN_BACKUP_SRC 不是目录: ${RKBIN_BACKUP_SRC}"

	local stamp
	stamp="$(date +%Y%m%d-%H%M%S)"
	local dest="${BACKUP_DIR}/rkbin-local-${stamp}"
	info "备份本地 rkbin: ${RKBIN_BACKUP_SRC} -> ${dest}"
	rsync -a --delete "${RKBIN_BACKUP_SRC}/" "${dest}/"
}

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
		info "克隆 ${name} (${branch})..."
		git clone --depth 1 -b "${branch}" "${url}" "${dir}"
	fi
}

backup_local_rkbin

clone_or_update "${UBOOT_REPO}" "${UBOOT_BRANCH}" "${UBOOT_DIR}"
clone_or_update "${RKBIN_REPO}" "${RKBIN_BRANCH}" "${RKBIN_DIR}"

# u-boot/make.sh 要求 rkbin 与 u-boot 同级：sources/u-boot、sources/rkbin
[[ -d "${RKBIN_DIR}" ]] || die "rkbin 克隆失败: ${RKBIN_DIR}"

info "源码就绪:"
info "  u-boot: ${UBOOT_DIR}"
info "  rkbin:  ${RKBIN_DIR}"
