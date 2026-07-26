#!/bin/bash
# Debian rootfs：chroot 挂载、debootstrap、ext4

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

# AP6256：bcmdhd 需要 fw_bcm43456c5_ag.bin + nvram_ap6256.txt
fetch_ap6256_firmware() {
	local dir="${BSP_ROOT}/vendor/firmware/ap6256"
	local base="https://raw.githubusercontent.com/armbian/firmware/master"
	local f
	mkdir -p "${dir}"
	for f in fw_bcm43456c5_ag.bin nvram_ap6256.txt BCM4345C5.hcd; do
		if [[ -s "${dir}/${f}" ]]; then
			continue
		fi
		info "下载 AP6256 固件: ${f}"
		if command -v curl >/dev/null 2>&1; then
			curl -fsSL -o "${dir}/${f}" "${base}/${f}" || die "下载失败: ${f}"
		elif command -v wget >/dev/null 2>&1; then
			wget -q -O "${dir}/${f}" "${base}/${f}" || die "下载失败: ${f}"
		else
			die "需要 curl 或 wget 以下载 AP6256 固件"
		fi
	done
}

install_ap6256_firmware() {
	local root="$1"
	local src="${BSP_ROOT}/vendor/firmware/ap6256"
	fetch_ap6256_firmware
	[[ -s "${src}/fw_bcm43456c5_ag.bin" ]] || die "缺少 ${src}/fw_bcm43456c5_ag.bin"
	[[ -s "${src}/nvram_ap6256.txt" ]] || die "缺少 ${src}/nvram_ap6256.txt"

	info "安装 AP6256 固件到 rootfs (/vendor/etc/firmware 与 /lib/firmware)"
	run_root mkdir -p "${root}/vendor/etc/firmware" "${root}/lib/firmware/brcm"
	run_root cp -a "${src}/fw_bcm43456c5_ag.bin" "${src}/nvram_ap6256.txt" \
		"${root}/vendor/etc/firmware/"
	run_root cp -a "${src}/fw_bcm43456c5_ag.bin" "${src}/nvram_ap6256.txt" \
		"${root}/lib/firmware/"
	# 兼容内核默认占位文件名（实际加载时会按芯片改写为上面的名字）
	run_root ln -sf fw_bcm43456c5_ag.bin "${root}/vendor/etc/firmware/fw_bcmdhd.bin"
	run_root ln -sf nvram_ap6256.txt "${root}/vendor/etc/firmware/nvram.txt"
	run_root ln -sf fw_bcm43456c5_ag.bin "${root}/lib/firmware/fw_bcmdhd.bin"
	run_root ln -sf nvram_ap6256.txt "${root}/lib/firmware/nvram.txt"
	if [[ -s "${src}/BCM4345C5.hcd" ]]; then
		run_root cp -a "${src}/BCM4345C5.hcd" "${root}/lib/firmware/brcm/"
		run_root cp -a "${src}/BCM4345C5.hcd" "${root}/vendor/etc/firmware/"
	fi
}

cmd_rootfs() {
	parse_build_flags "$@"
	command -v debootstrap >/dev/null 2>&1 || die "缺少 debootstrap，请运行 ./bsp env"
	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"

	if [[ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_RELEASE}" ]]; then
		die "本机 debootstrap 不支持 ${DEBIAN_RELEASE}，请升级 debootstrap 或 ./bsp config DEBIAN_RELEASE=bookworm"
	fi

	local rootfs image mirror overlay chroot_setup extra_list
	rootfs="${OUT_DIR}/rootfs"
	image="${OUT_DIR}/rootfs.ext4"
	mirror="http://${DEBIAN_MIRROR}/debian"
	overlay="${BSP_ROOT}/vendor/rootfs/overlay"
	chroot_setup="${BSP_ROOT}/vendor/rootfs/chroot-setup.sh"
	extra_list="${BSP_ROOT}/vendor/rootfs/extra-packages.list"

	if ! bsp_want_force && have_rootfs_artifacts; then
		info "已有 rootfs.ext4，跳过构建（加 --clean 强制重做）"
		ls -lh "${image}"
		return 0
	fi

	info "构建 Debian ${DEBIAN_RELEASE} (${DEBIAN_ARCH}, variant=${DEBIAN_VARIANT})"
	info "镜像源: ${mirror}"

	if [[ -d "${rootfs}" ]]; then
		warn "清理旧 rootfs: ${rootfs}"
		run_root rm -rf "${rootfs}"
	fi
	mkdir -p "${OUT_DIR}"

	info "debootstrap 第一阶段..."
	run_root debootstrap --arch="${DEBIAN_ARCH}" --variant="${DEBIAN_VARIANT}" \
		"${DEBIAN_RELEASE}" "${rootfs}" "${mirror}"
	run_root chown root:root "${rootfs}"

	local qemu_static="/usr/bin/qemu-aarch64-static"
	if [[ -x "${qemu_static}" ]]; then
		run_root cp "${qemu_static}" "${rootfs}/usr/bin/"
	fi

	if [[ -d "${overlay}" ]]; then
		info "应用 overlay: ${overlay}"
		run_root rsync -a "${overlay}/" "${rootfs}/"
		run_root chmod 755 "${rootfs}/usr/local/sbin/rockchip-partnames" 2>/dev/null || true
	fi
	install_ap6256_firmware "${rootfs}"

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
	run_root rm -f "${rootfs}/usr/bin/qemu-aarch64-static"

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
