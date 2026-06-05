#!/bin/bash
# 官方 Debian 无桌面 rootfs（debootstrap minbase + ext4 镜像）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

command -v debootstrap >/dev/null 2>&1 || die "缺少 debootstrap，请运行 ./scripts/init-env.sh"
command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"

if [[ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_RELEASE}" ]]; then
	die "本机 debootstrap 不支持 ${DEBIAN_RELEASE}，请升级 debootstrap 或在 config.env 改用 bookworm"
fi

ROOTFS="${OUT_DIR}/rootfs"
IMAGE="${OUT_DIR}/rootfs.ext4"
MIRROR="http://${DEBIAN_MIRROR}/debian"
OVERLAY="${BSP_ROOT}/vendor/rootfs/overlay"
CHROOT_SETUP="${BSP_ROOT}/vendor/rootfs/chroot-setup.sh"
EXTRA_LIST="${BSP_ROOT}/vendor/rootfs/extra-packages.list"

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

info "构建 Debian ${DEBIAN_RELEASE} (${DEBIAN_ARCH}, variant=${DEBIAN_VARIANT})"
info "镜像源: ${MIRROR}"

if [[ -d "${ROOTFS}" ]]; then
	warn "清理旧 rootfs: ${ROOTFS}"
	run_root rm -rf "${ROOTFS}"
fi
mkdir -p "${OUT_DIR}"

info "debootstrap 第一阶段..."
run_root debootstrap --arch="${DEBIAN_ARCH}" --variant="${DEBIAN_VARIANT}" \
	"${DEBIAN_RELEASE}" "${ROOTFS}" "${MIRROR}"

QEMU_STATIC="/usr/bin/qemu-aarch64-static"
if [[ -x "${QEMU_STATIC}" ]]; then
	run_root cp "${QEMU_STATIC}" "${ROOTFS}/usr/bin/"
fi

if [[ -d "${OVERLAY}" ]]; then
	info "应用 overlay: ${OVERLAY}"
	run_root rsync -a "${OVERLAY}/" "${ROOTFS}/"
	run_root chmod 755 "${ROOTFS}/etc/init.d/S02rockchip-partnames" 2>/dev/null || true
fi

run_root "${SCRIPT_DIR}/ch-rootfs.sh" -m "${ROOTFS}"
cleanup() {
	run_root "${SCRIPT_DIR}/ch-rootfs.sh" -u "${ROOTFS}" 2>/dev/null || true
}
trap cleanup EXIT

run_root cp "${CHROOT_SETUP}" "${ROOTFS}/tmp/chroot-setup.sh"
run_root chmod +x "${ROOTFS}/tmp/chroot-setup.sh"
if [[ -f "${EXTRA_LIST}" ]]; then
	run_root cp "${EXTRA_LIST}" "${ROOTFS}/tmp/extra-packages.list"
fi

info "chroot 配置（无桌面最小系统）..."
run_root chroot "${ROOTFS}" env \
	DEBIAN_MIRROR="${DEBIAN_MIRROR}" \
	DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
	ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME}" \
	ROOTFS_LOCALE="${ROOTFS_LOCALE}" \
	ROOTFS_ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD}" \
	ROOTFS_USER="${ROOTFS_USER}" \
	ROOTFS_USER_PASSWORD="${ROOTFS_USER_PASSWORD}" \
	bash /tmp/chroot-setup.sh

run_root rm -f "${ROOTFS}/tmp/chroot-setup.sh" "${ROOTFS}/tmp/extra-packages.list"
run_root rm -f "${ROOTFS}/usr/bin/qemu-aarch64-static"

cleanup
trap - EXIT

if [[ -f "${IMAGE}" ]]; then
	run_root rm -f "${IMAGE}"
fi

APPARENT_MB="$(run_root du --apparent-size -sm "${ROOTFS}" | cut -f1)"
FILE_COUNT="$(run_root find "${ROOTFS}" | wc -l)"
IMAGE_SIZE_MB=$(( APPARENT_MB + FILE_COUNT * 4 / 1024 + 64 ))
IMAGE_SIZE_MB=$(( IMAGE_SIZE_MB * 110 / 100 ))

info "打包 ext4: ${IMAGE} (${IMAGE_SIZE_MB}M)"
run_root mkfs.ext4 -d "${ROOTFS}" -L rootfs "${IMAGE}" "${IMAGE_SIZE_MB}M"

info "完成:"
info "  目录: ${ROOTFS}"
info "  镜像: ${IMAGE}"
