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

# 安装 IgH 用户态头文件（外置 sources/ethercat；make install 已装则跳过）
install_ethercat_headers() {
	local root="$1"
	local hdr="${ETHERCAT_DIR}/include/ecrt.h"
	local dest="${root}/usr/include/ecrt.h"
	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		return 0
	fi
	if [[ -f "${dest}" ]]; then
		info "ecrt.h 已由 IgH install 提供"
		return 0
	fi
	if [[ -f "${hdr}" ]]; then
		info "安装 ecrt.h -> ${root}/usr/include/"
		run_root mkdir -p "${root}/usr/include"
		run_root cp -a "${hdr}" "${dest}"
	else
		warn "未找到 ${hdr}（请先 ./bsp setup ethercat）"
	fi
}

# 交叉编译最小扫站工具（ioctl；优先官方 ethercat slaves）
install_ethercat_slaves() {
	local root="$1"
	local src="${BSP_ROOT}/vendor/rootfs/src/ethercat-slaves/ethercat-slaves.c"
	local ec_master="${ETHERCAT_DIR}/master"
	local ec_inc="${ETHERCAT_DIR}/include"
	local out_dir="${OUT_DIR}/ethercat-tools"
	local bin="${out_dir}/ethercat-slaves"

	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		return 0
	fi
	if [[ ! -f "${src}" ]]; then
		warn "缺少 ${src}"
		return 0
	fi
	if [[ ! -f "${ec_master}/ioctl.h" ]]; then
		warn "未找到 ${ec_master}/ioctl.h（请先 ./bsp setup ethercat）"
		return 0
	fi

	setup_cross_compile
	mkdir -p "${out_dir}"
	info "交叉编译 ethercat-slaves..."
	"${CROSS_COMPILE}gcc" -O2 -Wall -Wextra \
		-I"${ec_master}" -I"${ec_inc}" \
		-o "${bin}" "${src}" || die "ethercat-slaves 编译失败"

	run_root mkdir -p "${root}/usr/local/sbin" "${root}/usr/local/bin"
	run_root install -m 755 "${bin}" "${root}/usr/local/sbin/ethercat-slaves"
	run_root ln -sfn /usr/local/sbin/ethercat-slaves "${root}/usr/local/bin/ethercat-slaves"
}

# ServoDrive_FSMC 最小 PDO 周期例程（进 OP + 测唤醒抖动）
install_ethercat_io_demo() {
	local root="$1"
	local src="${BSP_ROOT}/vendor/rootfs/src/ethercat-io-demo/ethercat-io-demo.c"
	local out_dir="${OUT_DIR}/ethercat-tools"
	local bin="${out_dir}/ethercat-io-demo"
	local inc_flags=()
	local lib_flags=()

	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		return 0
	fi
	if [[ ! -f "${src}" ]]; then
		warn "缺少 ${src}"
		return 0
	fi

	setup_cross_compile
	mkdir -p "${out_dir}"

	if [[ -f "${OUT_DIR}/ethercat/usr/include/ecrt.h" ]]; then
		inc_flags+=("-I${OUT_DIR}/ethercat/usr/include")
	elif [[ -f "${ETHERCAT_DIR}/include/ecrt.h" ]]; then
		inc_flags+=("-I${ETHERCAT_DIR}/include")
	else
		warn "缺少 ecrt.h，跳过 ethercat-io-demo"
		return 0
	fi

	if [[ -f "${OUT_DIR}/ethercat/usr/lib/libethercat.so" ]] || \
		[[ -f "${OUT_DIR}/ethercat/usr/lib/libethercat.a" ]]; then
		lib_flags+=("-L${OUT_DIR}/ethercat/usr/lib" "-lethercat")
	elif [[ -f "${ETHERCAT_DIR}/lib/.libs/libethercat.so" ]]; then
		lib_flags+=("-L${ETHERCAT_DIR}/lib/.libs" "-lethercat")
	else
		warn "缺少 libethercat，跳过 ethercat-io-demo（先 ./bsp ethercat）"
		return 0
	fi

	info "交叉编译 ethercat-io-demo..."
	"${CROSS_COMPILE}gcc" -O2 -Wall -Wextra \
		"${inc_flags[@]}" -o "${bin}" "${src}" \
		"${lib_flags[@]}" -lrt -lpthread || die "ethercat-io-demo 编译失败"

	run_root mkdir -p "${root}/usr/local/sbin" "${root}/usr/local/bin"
	run_root install -m 755 "${bin}" "${root}/usr/local/sbin/ethercat-io-demo"
	run_root ln -sfn /usr/local/sbin/ethercat-io-demo "${root}/usr/local/bin/ethercat-io-demo"
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
		run_root chmod 755 "${rootfs}/usr/local/sbin/ethercat-info" 2>/dev/null || true
		run_root chmod 755 "${rootfs}/usr/local/sbin/ethercat-board-conf" 2>/dev/null || true
		run_root chmod 755 "${rootfs}/usr/local/sbin/ethercat-r8125-restore" 2>/dev/null || true
		run_root chmod 755 "${rootfs}/usr/local/sbin/ethercat-r8125-up" 2>/dev/null || true
		run_root chmod 755 "${rootfs}/usr/local/sbin/rt-latency-test" 2>/dev/null || true
		run_root chmod 644 "${rootfs}/etc/profile.d/bsp-path.sh" 2>/dev/null || true
		run_root chmod 644 "${rootfs}/etc/profile.d/bsp-bashrc.sh" 2>/dev/null || true
		# 供非 login 也能找到：再链到 /usr/local/bin
		run_root mkdir -p "${rootfs}/usr/local/bin"
		run_root ln -sfn /usr/local/sbin/ethercat-info "${rootfs}/usr/local/bin/ethercat-info" 2>/dev/null || true
		run_root ln -sfn /usr/local/sbin/rt-latency-test "${rootfs}/usr/local/bin/rt-latency-test" 2>/dev/null || true
		run_root mkdir -p "${rootfs}/etc/systemd/system/multi-user.target.wants"
		run_root ln -sfn /etc/systemd/system/ethercat.service \
			"${rootfs}/etc/systemd/system/multi-user.target.wants/ethercat.service" 2>/dev/null || true
		# 旧内嵌 EC 辅助服务不再默认启用
		run_root rm -f "${rootfs}/etc/systemd/system/multi-user.target.wants/ethercat-r8125.service" 2>/dev/null || true
	fi
	install_ky_firmware "${rootfs}"
	# 外置 IgH 用户态（模块等 kernelrelease 确定后再装）
	if [[ "${KERNEL_ETHERCAT}" == "y" || "${KERNEL_ETHERCAT}" == "1" ]]; then
		install_ethercat_oot "${rootfs}"
	fi
	install_ethercat_headers "${rootfs}"
	install_ethercat_slaves "${rootfs}"
	install_ethercat_io_demo "${rootfs}"

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
		# 外置 IgH .ko 需与 kernelrelease 一致；若早前已装过则再同步一次
		if [[ "${KERNEL_ETHERCAT}" == "y" || "${KERNEL_ETHERCAT}" == "1" ]]; then
			install_ethercat_oot "${rootfs}"
		fi
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
