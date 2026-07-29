#!/bin/bash
# Debian rootfs：chroot 挂载、debootstrap、ext4（riscv64）

rootfs_mount() {
	local root="$1"
	run_root mount -t proc /proc "${root}/proc"
	run_root mount -t sysfs /sys "${root}/sys"
	run_root mount --bind /dev "${root}/dev"
	run_root mount --bind /dev/pts "${root}/dev/pts"
}

rootfs_umount() {
	local root="$1"
	local m
	for m in dev/pts dev sys proc; do
		run_root bash -c "mountpoint -q '${root}/${m}' 2>/dev/null" || continue
		run_root umount "${root}/${m}" 2>/dev/null || run_root umount -l "${root}/${m}" 2>/dev/null || true
	done
}

install_ky_firmware() {
	local root="$1"
	local src="${BSP_ROOT}/vendor/firmware/ky/esos.elf"
	if [[ -s "${src}" ]]; then
		info "安装 Ky 固件 esos.elf"
		run_root mkdir -p "${root}/lib/firmware"
		run_root cp -a "${src}" "${root}/lib/firmware/esos.elf"
	else
		warn "缺少 ${src}（部分 Ky 功能可能不可用）"
	fi
}

qemu_static_for_arch() {
	# 旧包 qemu-user-static：qemu-<arch>-static；新包 qemu-user：qemu-<arch>
	local candidates=()
	case "${DEBIAN_ARCH}" in
		riscv64) candidates=(qemu-riscv64-static qemu-riscv64) ;;
		arm64|aarch64) candidates=(qemu-aarch64-static qemu-aarch64) ;;
		*) candidates=("qemu-${DEBIAN_ARCH}-static" "qemu-${DEBIAN_ARCH}") ;;
	esac
	local name
	for name in "${candidates[@]}"; do
		if [[ -x "/usr/bin/${name}" ]]; then
			echo "/usr/bin/${name}"
			return 0
		fi
	done
	echo "/usr/bin/${candidates[0]}"
}

cmd_rootfs() {
	parse_build_flags "$@"
	command -v debootstrap >/dev/null 2>&1 || die "缺少 debootstrap，请运行 ./bsp env"
	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"

	if [[ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_RELEASE}" ]]; then
		die "本机 debootstrap 不支持 ${DEBIAN_RELEASE}，请升级 debootstrap 或 ./bsp config DEBIAN_RELEASE=bookworm"
	fi

	local rootfs image mirror overlay chroot_setup extra_list qemu_static
	rootfs="${OUT_DIR}/rootfs"
	image="${OUT_DIR}/rootfs.ext4"
	mirror="http://${DEBIAN_MIRROR}/debian"
	overlay="${BSP_ROOT}/vendor/rootfs/overlay"
	chroot_setup="${BSP_ROOT}/vendor/rootfs/chroot-setup.sh"
	extra_list="${BSP_ROOT}/vendor/rootfs/extra-packages.list"
	qemu_static="$(qemu_static_for_arch)"

	if ! bsp_want_rebuild && have_rootfs_artifacts; then
		info "已有 rootfs.ext4，跳过构建（加 --clean/--update 强制重做）"
		ls -lh "${image}"
		return 0
	fi

	# --clean/--update：清掉旧 rootfs 树与镜像后再构建
	if bsp_want_rebuild; then
		if [[ -d "${rootfs}" ]] || [[ -f "${image}" ]]; then
			info "清除 rootfs 缓存..."
			run_root rm -rf "${rootfs}" "${image}"
		fi
	fi

	info "构建 Debian ${DEBIAN_RELEASE} (${DEBIAN_ARCH}, variant=${DEBIAN_VARIANT})"
	info "镜像源: ${mirror}"

	if [[ -d "${rootfs}" ]]; then
		warn "清理旧 rootfs: ${rootfs}"
		run_root rm -rf "${rootfs}"
	fi
	mkdir -p "${OUT_DIR}"

	# 交叉架构：foreign + second-stage（配合 qemu-user-static）
	info "debootstrap --foreign (${DEBIAN_ARCH})..."
	run_root debootstrap --foreign --arch="${DEBIAN_ARCH}" --variant="${DEBIAN_VARIANT}" \
		"${DEBIAN_RELEASE}" "${rootfs}" "${mirror}"
	run_root chown root:root "${rootfs}"

	if [[ -x "${qemu_static}" ]]; then
		run_root cp "${qemu_static}" "${rootfs}/usr/bin/"
	else
		die "未找到 ${qemu_static}，请 ./bsp env 安装 qemu-user 或 qemu-user-static"
	fi

	info "debootstrap --second-stage..."
	run_root chroot "${rootfs}" /debootstrap/debootstrap --second-stage
	run_root chown root:root "${rootfs}"

	if [[ -d "${overlay}" ]]; then
		info "应用 overlay: ${overlay}"
		run_root rsync -a "${overlay}/" "${rootfs}/"
	fi
	install_ky_firmware "${rootfs}"

	rootfs_mount "${rootfs}"
	cleanup_rootfs() { rootfs_umount "${rootfs}"; }
	trap cleanup_rootfs EXIT

	run_root cp "${chroot_setup}" "${rootfs}/tmp/chroot-setup.sh"
	run_root chmod +x "${rootfs}/tmp/chroot-setup.sh"
	if [[ -f "${extra_list}" ]]; then
		run_root cp "${extra_list}" "${rootfs}/tmp/extra-packages.list"
	fi

	info "chroot 配置（无桌面最小系统）..."
	run_root chroot "${rootfs}" env \
		DEBIAN_MIRROR="${DEBIAN_MIRROR}" \
		DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
		ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME}" \
		ROOTFS_LOCALE="${ROOTFS_LOCALE}" \
		ROOTFS_ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD}" \
		ROOTFS_USER="${ROOTFS_USER}" \
		ROOTFS_USER_PASSWORD="${ROOTFS_USER_PASSWORD}" \
		bash /tmp/chroot-setup.sh

	if [[ "${KERNEL_MODULES_INSTALL}" == "y" ]] && [[ -d "${KERNEL_DIR}" ]] && \
		[[ -f "${OUT_DIR}/kernel/Image" ]]; then
		info "安装内核模块到 rootfs..."
		local kernel_release
		kernel_release="$(install_kernel_modules "${rootfs}" | tail -n1)"
		[[ "${kernel_release}" =~ ^[0-9] ]] || die "无效 kernelrelease: ${kernel_release}"
		if [[ ! -x "${rootfs}/sbin/depmod" ]] && [[ ! -x "${rootfs}/usr/sbin/depmod" ]]; then
			info "rootfs 缺少 depmod，安装 kmod..."
			run_root chroot "${rootfs}" apt-get update
			run_root chroot "${rootfs}" apt-get install -y --no-install-recommends kmod
		fi
		info "depmod -a ${kernel_release}"
		run_root chroot "${rootfs}" /sbin/depmod -a "${kernel_release}"
	fi

	run_root rm -f "${rootfs}/tmp/chroot-setup.sh" "${rootfs}/tmp/extra-packages.list"
	run_root rm -f "${rootfs}/usr/bin/$(basename "${qemu_static}")"

	cleanup_rootfs
	trap - EXIT

	if [[ -f "${image}" ]]; then
		run_root rm -f "${image}"
	fi

	local apparent_mb file_count image_size_mb
	apparent_mb="$(run_root du --apparent-size -sm "${rootfs}" | cut -f1)"
	file_count="$(run_root find "${rootfs}" | wc -l)"
	image_size_mb=$(( apparent_mb + file_count * 4 / 1024 + 64 ))
	image_size_mb=$(( image_size_mb * 110 / 100 ))

	info "打包 ext4: ${image} (${image_size_mb}M)"
	run_root mkfs.ext4 -d "${rootfs}" -L rootfs "${image}" "${image_size_mb}M"

	info "完成:"
	info "  目录: ${rootfs}"
	info "  镜像: ${image}"
}
