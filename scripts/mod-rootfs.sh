#!/bin/bash
# rootfs：Debian debootstrap 或 Armbian 镜像/压缩包，统一打成 ext4

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

# 把本仓库编出的内核模块装进 rootfs（Debian / Armbian 两种 rootfs 共用）
rootfs_install_kernel_modules() {
	local root="$1" kernel_release
	[[ "${KERNEL_MODULES_INSTALL}" == "y" ]] || return 0
	[[ -d "${KERNEL_DIR}" ]] || { warn "未找到内核源码，跳过模块安装"; return 0; }
	[[ -f "${OUT_DIR}/kernel/Image" ]] || {
		warn "未找到 out/kernel/Image，跳过模块安装（先 ./bsp kernel）"
		return 0
	}

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

# ---------------- Debian（debootstrap） ----------------

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
		run_root rsync -a "${overlay}/" "${rootfs}/"
		run_root chmod 755 "${rootfs}/usr/local/sbin/rockchip-partnames" 2>/dev/null || true
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
	run_root chroot "${rootfs}" env \
		DEBIAN_MIRROR="${DEBIAN_MIRROR}" \
		DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
		ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME}" \
		ROOTFS_LOCALE="${ROOTFS_LOCALE}" \
		ROOTFS_ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD}" \
		ROOTFS_USER="${ROOTFS_USER}" \
		ROOTFS_USER_PASSWORD="${ROOTFS_USER_PASSWORD}" \
		bash /tmp/chroot-setup.sh

	rootfs_install_kernel_modules "${rootfs}"

	run_root rm -f "${rootfs}/tmp/chroot-setup.sh" "${rootfs}/tmp/extra-packages.list"
	run_root rm -f "${rootfs}/usr/bin/qemu-aarch64-static"

	cleanup_rootfs
	trap - EXIT

	rootfs_pack_ext4 "${rootfs}" "${image}"

	info "完成:"
	info "  目录: ${rootfs}"
	info "  镜像: ${image}"
}

# ---------------- Armbian（官方镜像或 rootfs 压缩包） ----------------

_ARMBIAN_LOOP=""
_ARMBIAN_MNT=""

armbian_cleanup() {
	if [[ -n "${_ARMBIAN_MNT}" ]] && mountpoint -q "${_ARMBIAN_MNT}" 2>/dev/null; then
		run_root umount "${_ARMBIAN_MNT}" 2>/dev/null || true
	fi
	[[ -n "${_ARMBIAN_MNT}" ]] && rmdir "${_ARMBIAN_MNT}" 2>/dev/null || true
	[[ -n "${_ARMBIAN_LOOP}" ]] && run_root losetup -d "${_ARMBIAN_LOOP}" 2>/dev/null || true
	_ARMBIAN_LOOP=""
	_ARMBIAN_MNT=""
	return 0
}

# 本地路径或 URL -> 本地文件（URL 下载到 sources/downloads 并缓存）
armbian_resolve_source() {
	local src="${ARMBIAN_ROOTFS_SOURCE}" name out
	if [[ -z "${src}" ]]; then
		die "ROOTFS_TYPE=armbian 需要 ARMBIAN_ROOTFS_SOURCE（Armbian 的 .img/.img.xz，
或 rootfs 的 .tar.zst/.tar.xz/.tar.gz，本地路径或 URL）"
	fi

	case "${src}" in
		http://*|https://*)
			name="$(basename "${src%%\?*}")"
			out="${SOURCES_DIR}/downloads/${name}"
			mkdir -p "$(dirname "${out}")"
			if [[ -s "${out}" ]]; then
				info "使用已下载的 $(basename "${out}")" >&2
			else
				info "下载: ${src}" >&2
				if command -v curl >/dev/null 2>&1; then
					curl -fL --retry 2 --connect-timeout 20 -o "${out}.part" "${src}" || \
						die "下载失败: ${src}"
				elif command -v wget >/dev/null 2>&1; then
					wget -q -O "${out}.part" "${src}" || die "下载失败: ${src}"
				else
					die "需要 curl 或 wget 下载 ${src}"
				fi
				mv -f "${out}.part" "${out}"
			fi
			printf '%s\n' "${out}"
			;;
		*)
			[[ -f "${src}" ]] || die "ARMBIAN_ROOTFS_SOURCE 不存在: ${src}"
			printf '%s\n' "${src}"
			;;
	esac
}

# .img.xz/.img.zst/.img.gz -> .img
# 解压结果统一放到 sources/downloads/（源文件所在目录可能只读），解压过一次后复用
armbian_decompress_image() {
	local f="$1" base out

	case "${f}" in
		*.xz|*.zst|*.zstd|*.gz) ;;
		*) printf '%s\n' "${f}"; return 0 ;;
	esac

	base="$(basename "${f}")"
	case "${f}" in
		*.xz) out="${SOURCES_DIR}/downloads/${base%.xz}" ;;
		*.zst|*.zstd) out="${SOURCES_DIR}/downloads/${base%.*}" ;;
		*.gz) out="${SOURCES_DIR}/downloads/${base%.gz}" ;;
	esac
	mkdir -p "$(dirname "${out}")"

	if [[ ! -s "${out}" ]]; then
		info "解压 ${base}（约 1~2 GB，稍等）..." >&2
		case "${f}" in
			*.xz) xz -dc "${f}" > "${out}" || die "xz 解压失败: ${f}" ;;
			*.zst|*.zstd) zstd -dc "${f}" > "${out}" || die "zstd 解压失败: ${f}" ;;
			*.gz) gzip -dc "${f}" > "${out}" || die "gzip 解压失败: ${f}" ;;
		esac
	fi
	printf '%s\n' "${out}"
}

# 在 loop 设备里挑 rootfs 分区：ARMBIAN_ROOTFS_PART=auto 取最大的 ext4，否则取分区号
armbian_pick_partition() {
	local loop="$1" want="${ARMBIAN_ROOTFS_PART}" p fstype size pick="" pick_size=0 i=0

	# 等 udev 把分区节点建出来
	while [[ ${i} -lt 50 ]] && ! compgen -G "${loop}p*" >/dev/null 2>&1; do
		sleep 0.1
		i=$((i + 1))
	done

	if [[ "${want}" != "auto" ]]; then
		p="${loop}p${want}"
		[[ -b "${p}" ]] || die "镜像里没有分区 ${want}（${p}）"
		printf '%s\n' "${p}"
		return 0
	fi

	for p in "${loop}"p*; do
		[[ -b "${p}" ]] || continue
		fstype="$(run_root blkid -o value -s TYPE "${p}" 2>/dev/null || true)"
		[[ "${fstype}" == "ext4" ]] || continue
		size="$(run_root blockdev --getsize64 "${p}" 2>/dev/null || echo 0)"
		if [[ "${size}" -gt "${pick_size}" ]]; then
			pick="${p}"
			pick_size="${size}"
		fi
	done

	[[ -n "${pick}" ]] || die "镜像里找不到 ext4 分区（可用 ARMBIAN_ROOTFS_PART=<分区号> 指定）"
	printf '%s\n' "${pick}"
}

# 从 Armbian 磁盘镜像里把 rootfs 分区 rsync 出来（需要 root/loop，脚本本来就要 sudo）
armbian_extract_image() {
	local img="$1" dest="$2" loop part

	command -v losetup >/dev/null 2>&1 || die "需要 losetup（util-linux）来解 Armbian 镜像"
	command -v blkid >/dev/null 2>&1 || die "需要 blkid（util-linux）来识别分区"

	info "挂载镜像 $(basename "${img}") ..."
	loop="$(run_root losetup -Pf --show "${img}")" || die "losetup 失败: ${img}"
	_ARMBIAN_LOOP="${loop}"

	part="$(armbian_pick_partition "${loop}")"
	_ARMBIAN_MNT="$(mktemp -d)"
	run_root mount -o ro "${part}" "${_ARMBIAN_MNT}" || die "挂载 ${part} 失败"

	info "复制 rootfs（$(basename "${part}")）..."
	run_root mkdir -p "${dest}"
	run_root rsync -aHAX --numeric-ids "${_ARMBIAN_MNT}/" "${dest}/"

	armbian_cleanup
}

# rootfs 压缩包（必须是 / 为根，不带顶层目录）
armbian_extract_tarball() {
	local f="$1" dest="$2"

	info "解包 $(basename "${f}") ..."
	run_root mkdir -p "${dest}"
	case "${f}" in
		*.tar.zst|*.tzst) run_root tar --zstd -xpf "${f}" -C "${dest}" ;;
		*.tar.xz|*.txz) run_root tar -xJpf "${f}" -C "${dest}" ;;
		*.tar.gz|*.tgz) run_root tar -xzpf "${f}" -C "${dest}" ;;
		*.tar) run_root tar -xpf "${f}" -C "${dest}" ;;
		*) die "不认识的压缩格式: ${f}" ;;
	esac
}

cmd_rootfs_armbian() {
	parse_build_flags "$@"
	local rootfs image overlay src img

	rootfs="${OUT_DIR}/rootfs"
	image="${OUT_DIR}/rootfs.ext4"
	overlay="${BSP_ROOT}/vendor/rootfs/overlay"

	if ! bsp_want_force && have_rootfs_artifacts; then
		info "已有 rootfs.ext4，跳过构建（加 --clean 强制重做）"
		ls -lh "${image}"
		return 0
	fi

	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4 (e2fsprogs)"

	src="$(armbian_resolve_source)"
	info "Armbian rootfs 来源: ${src}"
	info "工作目录: ${rootfs}"

	if [[ -d "${rootfs}" ]]; then
		warn "清理旧 rootfs: ${rootfs}"
		run_root rm -rf "${rootfs}"
	fi
	mkdir -p "${OUT_DIR}"

	trap armbian_cleanup EXIT

	case "${src}" in
		*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tzst)
			armbian_extract_tarball "${src}" "${rootfs}"
			;;
		*)
			img="$(armbian_decompress_image "${src}")"
			armbian_extract_image "${img}" "${rootfs}"
			;;
	esac

	# 镜像自带的 /boot 与 /lib/modules 属于别的内核，本项目用 out/boot.img + 自己编的模块
	if [[ "${ARMBIAN_KEEP_BOOT}" != "y" ]]; then
		info "清理 Armbian 自带内核（/boot 与 /lib/modules）..."
		run_root rm -rf "${rootfs}/lib/modules"/* 2>/dev/null || true
		run_root rm -rf "${rootfs}/boot"/* 2>/dev/null || true
	fi

	if [[ -d "${overlay}" ]]; then
		info "应用 overlay: ${overlay}"
		run_root rsync -a "${overlay}/" "${rootfs}/"
		run_root chmod 755 "${rootfs}/usr/local/sbin/rockchip-partnames" 2>/dev/null || true
	fi

	run_root mkdir -p "${rootfs}/etc"
	run_root bash -c "printf '%s\n' '${ROOTFS_HOSTNAME}' > '${rootfs}/etc/hostname'"
	install_ap6212_firmware "${rootfs}"
	rootfs_install_kernel_modules "${rootfs}"
	rootfs_pack_ext4 "${rootfs}" "${image}"

	trap - EXIT

	info "完成:"
	info "  目录: ${rootfs}"
	info "  镜像: ${image}"
	info "  提示: Armbian 用 NetworkManager 管理网络，WiFi 请用 nmcli 或"
	info "        /etc/NetworkManager/system-connections/ 配置；首次开机走 Armbian 的 first-run"
}

# ---------------- 分发 ----------------

cmd_rootfs() {
	case "${ROOTFS_TYPE}" in
		debian) cmd_rootfs_debian "$@" ;;
		armbian) cmd_rootfs_armbian "$@" ;;
		*) die "未知 ROOTFS_TYPE: ${ROOTFS_TYPE}（支持 debian | armbian）" ;;
	esac
}
