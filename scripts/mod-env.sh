#!/bin/bash
# 主机环境：apt 依赖、无 sudo 时的 host-tools

cmd_env() {
	local host_tools=0
	local arg
	for arg in "$@"; do
		case "${arg}" in
			--host-tools) host_tools=1 ;;
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
		gcc-aarch64-linux-gnu debootstrap qemu-user-static binfmt-support
		debian-archive-keyring e2fsprogs
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

	command -v dtc >/dev/null 2>&1 || die "dtc 未安装成功"
	command -v "${CROSS_COMPILE_PREFIX}gcc" >/dev/null 2>&1 || \
		die "交叉编译器 ${CROSS_COMPILE_PREFIX}gcc 未安装成功"
	command -v debootstrap >/dev/null 2>&1 || die "debootstrap 未安装成功"

	info "主机环境就绪"
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
