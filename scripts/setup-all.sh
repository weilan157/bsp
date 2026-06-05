#!/bin/bash
# 一键：环境 + 源码 + 编译

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/init-env.sh"
"${SCRIPT_DIR}/setup-sources.sh"
"${SCRIPT_DIR}/build-uboot.sh"

echo ""
echo "全部完成。产物见 sources/u-boot/"
