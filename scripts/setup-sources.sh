#!/bin/bash
# 1. 备份泰山派 SDK rkbin
# 2. 从 GitHub 克隆官方 u-boot / rkbin
# 3. 链接 prebuilts（可选）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

SOURCES_DIR="${ROOT_DIR}/sources"
BACKUP_DIR="${ROOT_DIR}/backup"
SDK_RKBIN="${TSPI_SDK_ROOT}/rkbin"
SDK_PREBUILTS="${TSPI_SDK_ROOT}/prebuilts"

UBOOT_DIR="${SOURCES_DIR}/u-boot"
RKBIN_GH_DIR="${SOURCES_DIR}/rkbin-github"
RKBIN_LINK="${SOURCES_DIR}/rkbin"
PREBUILTS_LINK="${SOURCES_DIR}/prebuilts"

ensure_dir "$SOURCES_DIR" "$BACKUP_DIR" "${ROOT_DIR}/logs"

[[ -d "$SDK_RKBIN" ]] || die "SDK rkbin 不存在: $SDK_RKBIN"

SDK_RKBIN_COMMIT="$(git_head_full "$SDK_RKBIN")"
SDK_RKBIN_SHORT="$(git_head_short "$SDK_RKBIN")"
BACKUP_TARGET="${BACKUP_DIR}/rkbin-sdk-${SDK_RKBIN_SHORT}"

info "备份 SDK rkbin -> ${BACKUP_TARGET}"
if [[ -d "$BACKUP_TARGET" ]]; then
	warn "备份已存在，跳过复制: $BACKUP_TARGET"
else
	rsync -a --delete "${SDK_RKBIN}/" "${BACKUP_TARGET}/"
	cat > "${BACKUP_TARGET}/BACKUP_MANIFEST.txt" <<EOF
source_path=${SDK_RKBIN}
commit=${SDK_RKBIN_COMMIT}
short=${SDK_RKBIN_SHORT}
backed_up_at=$(date -Iseconds)
note=TaishanPi SDK rkbin snapshot (read-only reference)
EOF
	info "SDK rkbin 备份完成: ${SDK_RKBIN_SHORT}"
fi

clone_or_update() {
	local url="$1"
	local branch="$2"
	local dest="$3"
	local name="$4"

	if [[ -d "$dest/.git" ]]; then
		info "更新 ${name} (${branch})..."
		git -C "$dest" fetch origin "$branch"
		git -C "$dest" checkout "$branch"
		git -C "$dest" pull --ff-only origin "$branch" || warn "${name} pull 失败，继续使用本地版本"
	else
		info "克隆 ${name} (${branch})..."
		git clone --depth 1 -b "$branch" "$url" "$dest"
	fi
}

clone_or_update "$UBOOT_REPO" "$UBOOT_BRANCH" "$UBOOT_DIR" "u-boot"

clone_or_update "$RKBIN_REPO" "$RKBIN_BRANCH" "$RKBIN_GH_DIR" "rkbin"

info "建立 sources/rkbin -> rkbin-github 符号链接（供 make.sh 使用）"
ln -sfn "$(basename "$RKBIN_GH_DIR")" "$RKBIN_LINK"

if [[ "${USE_SDK_PREBUILTS}" == "y" ]]; then
	[[ -d "$SDK_PREBUILTS" ]] || die "SDK prebuilts 不存在: $SDK_PREBUILTS"
	ln -sfn "$SDK_PREBUILTS" "$PREBUILTS_LINK"
	info "已链接 prebuilts: $PREBUILTS_LINK -> $SDK_PREBUILTS"
else
	warn "未链接 SDK prebuilts，编译时将使用系统 aarch64-linux-gnu- 工具链"
fi

UBOOT_COMMIT="$(git_head_full "$UBOOT_DIR")"
RKBIN_GH_COMMIT="$(git_head_full "$RKBIN_GH_DIR")"

cat > "${SOURCES_DIR}/VERSIONS.json" <<EOF
{
  "created_at": "$(date -Iseconds)",
  "sdk_rkbin_backup": "${BACKUP_TARGET}",
  "sdk_rkbin_commit": "${SDK_RKBIN_COMMIT}",
  "github_uboot": {
    "repo": "${UBOOT_REPO}",
    "branch": "${UBOOT_BRANCH}",
    "path": "${UBOOT_DIR}",
    "commit": "${UBOOT_COMMIT}"
  },
  "github_rkbin": {
    "repo": "${RKBIN_REPO}",
    "branch": "${RKBIN_BRANCH}",
    "path": "${RKBIN_GH_DIR}",
    "commit": "${RKBIN_GH_COMMIT}"
  },
  "active_rkbin_for_build": "${RKBIN_LINK}",
  "note": "Build uses GitHub rkbin; SDK rkbin is backup only"
}
EOF

info "源码准备完成"
info "  u-boot:  ${UBOOT_DIR} ($(git_head_short "$UBOOT_DIR"))"
info "  rkbin:   ${RKBIN_GH_DIR} ($(git_head_short "$RKBIN_GH_DIR"))"
info "  backup:  ${BACKUP_TARGET}"
