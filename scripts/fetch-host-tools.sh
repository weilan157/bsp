#!/bin/bash
# 在无 sudo 时下载 flex/bison 到 .local/host-tools（内核 kconfig 需要）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEB_DIR="${BSP_ROOT}/.local/debs"
HT="${BSP_ROOT}/.local/host-tools"

mkdir -p "${DEB_DIR}"
cd "${DEB_DIR}"

for pkg in flex bison; do
	if ! ls "${pkg}"_*.deb >/dev/null 2>&1; then
		apt-get download "${pkg}"
	fi
done

rm -rf "${HT}"
mkdir -p "${HT}"
for f in flex_*.deb bison_*.deb; do
	dpkg-deb -x "${f}" "${HT}"
done

info "已安装到 ${HT}"
info "build-kernel.sh 会自动把 ${HT}/usr/bin 加入 PATH"
