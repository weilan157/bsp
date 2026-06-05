#!/bin/bash
# chroot 挂载/卸载（debootstrap / apt 配置用）

set -euo pipefail

mnt() {
	local root="$1"
	mount -t proc /proc "${root}/proc"
	mount -t sysfs /sys "${root}/sys"
	mount -o bind /dev "${root}/dev"
	mount -o bind /dev/pts "${root}/dev/pts"
}

umnt() {
	local root="$1"
	for m in dev/pts dev sys proc; do
		mountpoint -q "${root}/${m}" 2>/dev/null || continue
		umount "${root}/${m}" 2>/dev/null || umount -l "${root}/${m}" 2>/dev/null || true
	done
}

case "${1:-}" in
-m)
	[[ -n "${2:-}" ]] || { echo "用法: $0 -m ROOTFS_DIR" >&2; exit 1; }
	mnt "$2"
	;;
-u)
	[[ -n "${2:-}" ]] || { echo "用法: $0 -u ROOTFS_DIR" >&2; exit 1; }
	umnt "$2"
	;;
*)
	echo "用法: $0 -m|-u ROOTFS_DIR" >&2
	exit 1
	;;
esac
