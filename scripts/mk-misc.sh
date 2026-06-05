#!/bin/bash
# 生成空白 misc.img（48KiB，与 SDK RK_MISC_BLANK 一致）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISC_IMG="${OUT_DIR}/firmware/misc.img"
mkdir -p "${OUT_DIR}/firmware"
truncate -s 48k "${MISC_IMG}"
info "已生成空白 misc.img: ${MISC_IMG}"
