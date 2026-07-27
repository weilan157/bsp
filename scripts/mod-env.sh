#!/bin/bash
# 主机环境：apt 依赖、Ky riscv64 交叉工具链

cmd_env_ky_toolchain() {
	local name="${TOOLCHAIN_NAME}"
	local url="${TOOLCHAIN_URL}"
	local dest="${BSP_ROOT}/toolchains/${name}"
	local tarball="${BSP_ROOT}/toolchains/${name}.tar.xz"
	local marker="${dest}/.download-complete"

	mkdir -p "${BSP_ROOT}/toolchains"

	if [[ -f "${marker}" ]] && [[ -x "${dest}/bin/${CROSS_COMPILE_PREFIX}gcc" ]]; then
		info "Ky toolchain 已就绪: ${dest}"
		return 0
	fi

	if [[ ! -f "${tarball}" ]]; then
		info "下载 Ky toolchain (~610MB): ${url}"
		if command -v curl >/dev/null 2>&1; then
			curl -fL --retry 3 --connect-timeout 30 -o "${tarball}.partial" "${url}"
			mv -f "${tarball}.partial" "${tarball}"
		elif command -v wget >/dev/null 2>&1; then
			wget -O "${tarball}.partial" "${url}"
			mv -f "${tarball}.partial" "${tarball}"
		else
			die "需要 curl 或 wget 以下载 toolchain"
		fi
	fi

	info "解压 ${tarball} -> ${BSP_ROOT}/toolchains/"
	rm -rf "${dest}"
	tar -C "${BSP_ROOT}/toolchains" -xf "${tarball}"
	[[ -x "${dest}/bin/${CROSS_COMPILE_PREFIX}gcc" ]] || \
		die "解压后未找到 ${dest}/bin/${CROSS_COMPILE_PREFIX}gcc"
	touch "${marker}"
	info "Ky toolchain 安装完成: ${dest}/bin"
	"${dest}/bin/${CROSS_COMPILE_PREFIX}gcc" --version | head -1
}

cmd_env() {
	local host_tools=0
	local skip_toolchain=0
	local arg
	for arg in "$@"; do
		case "${arg}" in
			--host-tools) host_tools=1 ;;
			--skip-toolchain) skip_toolchain=1 ;;
			*) die "env 未知选项: ${arg}" ;;
		esac
	done

	if [[ "${host_tools}" -eq 1 ]]; then
		cmd_env_host_tools
		return
	fi

	info "检查主机架构..."
	[[ "$(uname -m)" == "x86_64" ]] || die "仅支持 x86_64 主机编译"

	local packages=(
		build-essential bc bison flex device-tree-compiler
		python3 python3-pip libssl-dev git rsync curl pkg-config
		u-boot-tools debootstrap qemu-user-static binfmt-support
		debian-archive-keyring e2fsprogs dosfstools fdisk gdisk parted
		xz-utils mtools
	)

	info "安装 apt 依赖（需要 sudo）..."
	if command -v sudo >/dev/null 2>&1; then
		sudo apt-get update
		sudo apt-get install -y "${packages[@]}"
	else
		apt-get update
		apt-get install -y "${packages[@]}"
	fi

	if [[ -x /usr/bin/python2 ]] && [[ ! -e /usr/bin/python ]]; then
		sudo ln -sf /usr/bin/python2 /usr/bin/python 2>/dev/null || ln -sf /usr/bin/python2 /usr/bin/python
		info "已创建 /usr/bin/python -> python2"
	elif ! command -v python2 >/dev/null 2>&1; then
		ensure_python2_wrapper
	fi

	# 启用 qemu-riscv64 binfmt（debootstrap chroot）
	if [[ -x /usr/sbin/update-binfmts ]]; then
		run_root update-binfmts --enable qemu-riscv64 2>/dev/null || true
	fi

	command -v dtc >/dev/null 2>&1 || die "dtc 未安装成功"
	command -v mkimage >/dev/null 2>&1 || die "mkimage (u-boot-tools) 未安装成功"
	command -v debootstrap >/dev/null 2>&1 || die "debootstrap 未安装成功"
	command -v mkfs.vfat >/dev/null 2>&1 || die "dosfstools 未安装成功"

	if [[ "${skip_toolchain}" -eq 0 ]]; then
		cmd_env_ky_toolchain
	fi

	setup_cross_compile
	command -v "${CROSS_COMPILE_PREFIX}gcc" >/dev/null 2>&1 || \
		die "交叉编译器 ${CROSS_COMPILE_PREFIX}gcc 不可用"

	info "主机环境就绪（ARCH=${KERNEL_ARCH}, CROSS=${CROSS_COMPILE_PREFIX}）"
}

cmd_env_host_tools() {
	local deb_dir="${BSP_ROOT}/.local/debs"
	local ht="${BSP_ROOT}/.local/host-tools"

	mkdir -p "${deb_dir}"
	(
		cd "${deb_dir}"
		local pkg
		for pkg in flex bison; do
			if ! ls "${pkg}"_*.deb >/dev/null 2>&1; then
				apt-get download "${pkg}"
			fi
		done
		rm -rf "${ht}"
		mkdir -p "${ht}"
		local f
		for f in flex_*.deb bison_*.deb; do
			dpkg-deb -x "${f}" "${ht}"
		done
	)
	info "已安装到 ${ht}"
	info "编译内核时会自动把 ${ht}/usr/bin 加入 PATH"
}
