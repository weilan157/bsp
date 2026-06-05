#!/bin/bash
# Build Recovery + OTA package via TaishanPi SDK
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_config

TSPI_DEFCONFIG="${TSPI_DEFCONFIG:-tspi_3m_rk3576_debian_bookworm_desktop_defconfig}"
SDK="${TSPI_SDK_ROOT}"

[ -d "$SDK" ] || die "SDK not found: $SDK"
[ -x "$SDK/build.sh" ] || die "Invalid SDK (no build.sh): $SDK"

info "SDK: $SDK"
info "defconfig: $TSPI_DEFCONFIG"
info "Building recovery + ota-updateimg (requires network for Buildroot on first recovery build)..."

(
	cd "$SDK"
	./build.sh "$TSPI_DEFCONFIG" recovery ota-updateimg
)

info "Outputs:"
info "  recovery: $SDK/output/firmware/recovery.img"
info "  OTA:      $SDK/output/firmware/ota.img"
info "Board apply: copy ota.img to /userdata/update.img && tspi-ota apply"
