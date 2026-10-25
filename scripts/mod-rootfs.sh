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

# 板载 AP6212A（BCM43438）：bcmdhd 固件，取自 SDK 的 external/rkwifibt
# 路径与 kernel-config/tspi-1m.config 里的 BCMDHD_FW_PATH/NVRAM_PATH 一致
install_ap6212_firmware() {
	local root="$1"
	[[ "${INSTALL_AP6212_FIRMWARE}" == "y" ]] || return 0
	local src="${BSP_ROOT}/vendor/firmware/ap6212"
	local f
	[[ -d "${src}" ]] || return 0

	info "安装 AP6212A 固件到 ${root}/lib/firmware"
	run_root mkdir -p "${root}/lib/firmware" "${root}/lib/firmware/brcm"
	for f in fw_bcm43438a1.bin nvram_ap6212a.txt BCM4343A1.hcd; do
		[[ -s "${src}/${f}" ]] || continue
		run_root install -m 644 "${src}/${f}" "${root}/lib/firmware/${f}"
	done
	# 蓝牙 HCD 由 bluez 从 /lib/firmware/brcm/ 取
	[[ -s "${src}/BCM4343A1.hcd" ]] && \
		run_root install -m 644 "${src}/BCM4343A1.hcd" "${root}/lib/firmware/brcm/BCM4343A1.hcd"
	return 0
}

# 宿主上的 overlay 来自 Windows 工作区（drvfs 777/uid1000），rsync -a 会原样带进来；
# 去掉 group/other 写权限，否则 chroot 里 perl -T 的 adduser（bluez 等）会拒绝 $PATH
rootfs_fix_perms() {
	local root="$1"
	run_root find "${root}" -xdev -type d -perm /002 -exec chmod go-w {} + 2>/dev/null || true
	run_root find "${root}" -xdev -type f -perm /002 -exec chmod go-w {} + 2>/dev/null || true
	run_root chmod 1777 "${root}/tmp" 2>/dev/null || true
	run_root chmod 1777 "${root}/var/tmp" 2>/dev/null || true
	run_root chown root:root "${root}" 2>/dev/null || true
}
# 把本仓库编出的内核模块装进 rootfs（Debian / micro 共用）
rootfs_install_kernel_modules() {
	local root="$1" kernel_release

	info "安装内核模块到 rootfs..."
	kernel_release="$(install_kernel_modules "${root}" | tail -n1)"
	[[ "${kernel_release}" =~ ^[0-9] ]] || die "无效 kernelrelease: ${kernel_release}"
	if [[ ! -x "${root}/sbin/depmod" ]] && [[ ! -x "${root}/usr/sbin/depmod" ]]; then
		info "rootfs 缺少 depmod，安装 kmod..."
		run_root chroot "${root}" apt-get update
		run_root chroot "${root}" apt-get install -y --no-install-recommends kmod
	fi
	info "depmod -a ${kernel_release}"
	run_root chroot "${root}" /sbin/depmod -a "${kernel_release}"
}

# 目录 -> ext4 镜像
rootfs_pack_ext4() {
	local root="$1" image="$2"
	local apparent_mb file_count image_size_mb

	[[ -f "${image}" ]] && run_root rm -f "${image}"
	apparent_mb="$(run_root du --apparent-size -sm "${root}" | cut -f1)"
	file_count="$(run_root find "${root}" | wc -l)"
	image_size_mb=$(( apparent_mb + file_count * 4 / 1024 + 64 ))
	image_size_mb=$(( image_size_mb * 110 / 100 ))

	info "打包 ext4: ${image} (${image_size_mb}M)"
	run_root mkfs.ext4 -d "${root}" -L rootfs "${image}" "${image_size_mb}M"
}

# 裁剪目录里的 ELF 符号/调试段（Tina 裁剪指南 2.4.3）
# 用 aarch64 的 strip，别用宿主 strip（x86 的 binutils 不一定带 aarch64 目标）
rootfs_strip() {
	local root="$1"
	local strip_bin="${ROOTFS_STRIP_BIN:-aarch64-linux-gnu-strip}"
	local before after

	if [[ "${ROOTFS_STRIP:-n}" != "y" ]]; then
		return 0
	fi
	if ! command -v "${strip_bin}" >/dev/null 2>&1; then
		warn "没有 ${strip_bin}，跳过 strip（apt install binutils-aarch64-linux-gnu）"
		return 0
	fi

	before="$(run_root du -sm "${root}" | cut -f1)"
	info "strip 可执行文件与 .so（${strip_bin}）..."
	# 跳过动态加载器（ld-*.so），只处理普通 ELF；非 ELF 会被 strip 拒绝，直接忽略
	run_root find "${root}" -xdev -type f \
		\( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) \
		! -name 'ld-*.so' ! -name 'ld-*.so.*' -print0 2>/dev/null |
		xargs -0 -r "${strip_bin}" --strip-unneeded 2>/dev/null || true
	after="$(run_root du -sm "${root}" | cut -f1)"
	info "strip 完成: ${before} MB -> ${after} MB"
}

cmd_rootfs_debian() {
	parse_build_flags "$@"
	command -v debootstrap >/dev/null 2>&1 || die "缺少 debootstrap，请运行 ./bsp env"
	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"

	if [[ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_RELEASE}" ]]; then
		die "本机 debootstrap 不支持 ${DEBIAN_RELEASE}，请升级 debootstrap 或 ./bsp config DEBIAN_RELEASE=bookworm"
	fi

	# 没跑过 ./bsp env 的主机也可能 debootstrap：keyring 太旧时这里补一次，
	# 否则会在 "Checking Release signature" 阶段失败（见 mod-env.sh）
	if declare -F ensure_debian_keyring >/dev/null; then
		ensure_debian_keyring
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
		run_root rsync -a --chown=root:root "${overlay}/" "${rootfs}/"
		run_root chmod 755 "${rootfs}/usr/local/sbin/rockchip-partnames" 2>/dev/null || true
		rootfs_fix_perms "${rootfs}"
	fi
	install_ap6212_firmware "${rootfs}"

	rootfs_mount "${rootfs}"
	cleanup_rootfs() { rootfs_umount "${rootfs}"; }
	trap cleanup_rootfs EXIT

	run_root cp "${chroot_setup}" "${rootfs}/tmp/chroot-setup.sh"
	run_root chmod +x "${rootfs}/tmp/chroot-setup.sh"
	if [[ -f "${extra_list}" ]]; then
		run_root cp "${extra_list}" "${rootfs}/tmp/extra-packages.list"
	fi

	info "chroot 配置（无桌面最小系统）..."
	# env -i + 干净 PATH：避免宿主 PATH/cwd 泄漏进 chroot，
	# 否则 perl -T 的 adduser（bluez 等包）会报 "Insecure directory in $ENV{PATH}"
	(
		cd "${rootfs}"
		run_root chroot "${rootfs}" env -i \
			HOME=/root \
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
			TERM=linux \
			DEBIAN_FRONTEND=noninteractive \
			DEBIAN_MIRROR="${DEBIAN_MIRROR}" \
			DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
			ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME}" \
			ROOTFS_LOCALE="${ROOTFS_LOCALE}" \
			ROOTFS_ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD}" \
			ROOTFS_USER="${ROOTFS_USER}" \
			ROOTFS_USER_PASSWORD="${ROOTFS_USER_PASSWORD}" \
			bash /tmp/chroot-setup.sh
	)

	if [[ "${KERNEL_MODULES_INSTALL}" == "y" ]] && [[ -d "${KERNEL_DIR}" ]] && \
		[[ -f "${OUT_DIR}/kernel/Image" ]]; then
		rootfs_install_kernel_modules "${rootfs}"
	fi

	run_root rm -f "${rootfs}/tmp/chroot-setup.sh" "${rootfs}/tmp/extra-packages.list"
	run_root rm -f "${rootfs}/usr/bin/qemu-aarch64-static"

	cleanup_rootfs
	trap - EXIT

	rootfs_strip "${rootfs}"
	rootfs_pack_ext4 "${rootfs}" "${image}"

	info "完成:"
	info "  目录: ${rootfs}"
	info "  镜像: ${image}"
}

# ---------------- microduck 精简 rootfs ----------------

cmd_rootfs_micro() {
	parse_build_flags "$@"
	command -v debootstrap >/dev/null 2>&1 || die "缺少 debootstrap，请运行 ./bsp env"
	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"
	[[ -f "/usr/share/debootstrap/scripts/${DEBIAN_RELEASE}" ]] || \
		die "本机 debootstrap 不支持 ${DEBIAN_RELEASE}，请升级 debootstrap 或 ./bsp config DEBIAN_RELEASE=bookworm"
	if declare -F ensure_debian_keyring >/dev/null; then
		ensure_debian_keyring
	fi

	local rootfs image mirror overlay setup_dir
	rootfs="${OUT_DIR}/rootfs"
	image="${OUT_DIR}/rootfs.ext4"
	mirror="http://${DEBIAN_MIRROR}/debian"
	overlay="${BSP_ROOT}/vendor/rootfs/micro/overlay"
	setup_dir="${BSP_ROOT}/vendor/rootfs/micro"

	if ! bsp_want_force && have_rootfs_artifacts; then
		info "已有 rootfs.ext4，跳过构建（加 --clean 强制重做）"
		ls -lh "${image}"
		return 0
	fi

	info "构建 microduck rootfs（Debian ${DEBIAN_RELEASE} minbase + sysvinit/busybox）"
	if [[ -d "${rootfs}" ]]; then
		warn "清理旧 rootfs: ${rootfs}"
		run_root rm -rf "${rootfs}"
	fi
	mkdir -p "${OUT_DIR}"

	run_root debootstrap --arch="${DEBIAN_ARCH}" --variant=minbase \
		"${DEBIAN_RELEASE}" "${rootfs}" "${mirror}"
	run_root chown root:root "${rootfs}"

	local qemu_static="/usr/bin/qemu-aarch64-static"
	[[ -x "${qemu_static}" ]] && run_root cp "${qemu_static}" "${rootfs}/usr/bin/"

	if [[ -d "${overlay}" ]]; then
		info "应用 micro overlay: ${overlay}"
		run_root rsync -a --chown=root:root "${overlay}/" "${rootfs}/"
	fi
	if [[ -n "${ROOTFS_OVERLAY_EXTRA:-}" && -d "${ROOTFS_OVERLAY_EXTRA}" ]]; then
		info "应用平台 overlay: ${ROOTFS_OVERLAY_EXTRA}"
		run_root rsync -a --chown=root:root "${ROOTFS_OVERLAY_EXTRA}/" "${rootfs}/"
	fi
	if [[ -d "${overlay}" ]]; then
		rootfs_fix_perms "${rootfs}"
	fi
	install_ap6212_firmware "${rootfs}"

	rootfs_mount "${rootfs}"
	cleanup_micro() { rootfs_umount "${rootfs}"; }
	trap cleanup_micro EXIT

	run_root cp "${setup_dir}/chroot-setup.sh" "${rootfs}/tmp/chroot-setup.sh"
	run_root chmod +x "${rootfs}/tmp/chroot-setup.sh"

	info "chroot 配置（micro）..."
	(
		cd "${rootfs}"
		run_root chroot "${rootfs}" env -i \
			HOME=/root \
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
			TERM=linux \
			DEBIAN_FRONTEND=noninteractive \
			DEBIAN_MIRROR="${DEBIAN_MIRROR}" \
			DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
			ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME}" \
			ROOTFS_ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD}" \
			bash /tmp/chroot-setup.sh
	)

	if [[ "${KERNEL_MODULES_INSTALL}" == "y" ]] && [[ -f "${OUT_DIR}/kernel/Image" ]]; then
		rootfs_install_kernel_modules "${rootfs}"
	fi
	# 平台自己的模块安装（A733 的内核树不在 sources/kernel，路径不同）
	if declare -F rootfs_install_platform_modules >/dev/null; then
		rootfs_install_platform_modules "${rootfs}"
	fi

	# apt 装 sysvinit/busybox 时可能覆盖 /etc/inittab、/etc/init.d/rcS、fstab，
	# 这里再铺一次 overlay，保证我们的启动脚本最后生效
	if [[ -d "${overlay}" ]]; then
		info "覆盖启动脚本（overlay 二次应用）"
		run_root rsync -a --chown=root:root "${overlay}/" "${rootfs}/"
		if [[ -n "${ROOTFS_OVERLAY_EXTRA:-}" && -d "${ROOTFS_OVERLAY_EXTRA}" ]]; then
			run_root rsync -a --chown=root:root "${ROOTFS_OVERLAY_EXTRA}/" "${rootfs}/"
		fi
		rootfs_fix_perms "${rootfs}"
		run_root chmod 755 "${rootfs}/etc/init.d/rcS" "${rootfs}"/usr/sbin/microduck-* \
			"${rootfs}/usr/share/udhcpc/default.script" \
			"${rootfs}"/www/cgi-bin/*.cgi 2>/dev/null || true
	fi

	run_root rm -f "${rootfs}/tmp/chroot-setup.sh" "${rootfs}/usr/bin/qemu-aarch64-static"
	cleanup_micro
	trap - EXIT

	rootfs_strip "${rootfs}"
	rootfs_pack_ext4 "${rootfs}" "${image}"

	info "完成:"
	info "  目录: ${rootfs}"
	info "  镜像: ${image}"
	info "  开机扩容: parameter.txt 的 rootfs 为 grow，init 里 resize2fs"
	info "  ZRAM: /usr/sbin/microduck-zram（lz4，内存的一半）"
}

cmd_rootfs() {
	case "${ROOTFS_TYPE}" in
		debian) cmd_rootfs_debian "$@" ;;
		micro) cmd_rootfs_micro "$@" ;;
		*) die "未知 ROOTFS_TYPE: ${ROOTFS_TYPE}（支持 debian | micro）" ;;
	esac
}