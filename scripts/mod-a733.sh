#!/bin/bash
# Cubie A7Z（Allwinner A733 / sun60i）
# 直接复用 Radxa 官方的 debian 打包仓库，不再重写 Allwinner 的 longan 流程：
#   kernel: https://github.com/radxa-pkg/linux-a733         （submodule: radxa/kernel 5.15 BSP + allwinner-bsp + device）
#   u-boot: https://github.com/radxa-pkg/u-boot-aw2501      （submodule: radxa/u-boot + aw 的 tools/arisc/dramlib）
#   镜像:   https://github.com/RadxaOS-SDK/rsdk            （rsdk TUI，构建 output.img）

A733_KERNEL_REPO="${A733_KERNEL_REPO:-https://github.com/radxa-pkg/linux-a733.git}"
A733_UBOOT_REPO="${A733_UBOOT_REPO:-https://github.com/radxa-pkg/u-boot-aw2501.git}"
A733_RSDK_REPO="${A733_RSDK_REPO:-https://github.com/RadxaOS-SDK/rsdk.git}"
A733_BOARD="${A733_BOARD:-radxa-a733}"
# Radxa 的 Makefile.extra 默认就是 "defconfig radxa.config"，这里再叠我们的精简配置
A733_KERNEL_DEFCONFIG="${A733_KERNEL_DEFCONFIG:-defconfig radxa.config microduck.config}"
A733_CROSS_COMPILE="${A733_CROSS_COMPILE:-aarch64-linux-gnu-}"

A733_DIR="${SOURCES_DIR}/a733"
A733_KERNEL_DIR="${A733_DIR}/kernel"
A733_UBOOT_DIR="${A733_DIR}/uboot"
A733_RSDK_DIR="${A733_DIR}/rsdk"
A733_OUT="${OUT_DIR}/a733"

a733_env() {
	command -v apt-get >/dev/null 2>&1 || die "A733 构建按 Ubuntu/Debian 写的，需要 apt"
	local pkgs=(
		build-essential bc bison flex libssl-dev libelf-dev
		device-tree-compiler dpkg-dev debhelper fakeroot
		gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
		python3 python3-setuptools swig rsync curl wget git
		libncurses-dev libgnutls28-dev uuid-dev zstd kmod cpio
	)
	info "安装 A733 构建依赖（需要 sudo）..."
	run_root apt-get update
	run_root apt-get install -y "${pkgs[@]}"
}

a733_clone() {
	local url="$1" dest="$2" name="$3"
	if [[ -d "${dest}/.git" ]]; then
		info "已有 ${name}（${dest}）"
		return 0
	fi
	info "克隆 ${name} ...（含 submodule，首次几 GB，耐心等）"
	git clone --recurse-submodules --depth 1 "${url}" "${dest}" || \
		die "克隆失败: ${url}（GitLab 上的 tools/arisc/dramlib 可能被墙）"
}

cmd_a733_setup() {
	mkdir -p "${A733_DIR}"
	a733_clone "${A733_KERNEL_REPO}" "${A733_KERNEL_DIR}" "linux-a733"
	a733_clone "${A733_UBOOT_REPO}" "${A733_UBOOT_DIR}" "u-boot-aw2501"
	if [[ "${A733_WITH_RSDK:-n}" == "y" ]]; then
		a733_clone "${A733_RSDK_REPO}" "${A733_RSDK_DIR}" "rsdk"
	fi
	info "源码就绪:"
	info "  kernel: ${A733_KERNEL_DIR}"
	info "  uboot:  ${A733_UBOOT_DIR}"
}

cmd_a733_kernel() {
	[[ -d "${A733_KERNEL_DIR}/src" ]] || die "请先 ./bsp setup"
	[[ -d "${A733_KERNEL_DIR}/src/arch/arm64/configs" ]] || die "kernel submodule 不完整（src/ 为空）"

	install -m 644 "${BSP_ROOT}/vendor/a733/microduck.config" \
		"${A733_KERNEL_DIR}/src/arch/arm64/configs/microduck.config"

	info "编译 kernel（Radxa 打包流程，defconfig = ${A733_KERNEL_DEFCONFIG}）..."
	info "产物是 .deb，落在 ${A733_KERNEL_DIR}/../"
	make -C "${A733_KERNEL_DIR}" build \
		KERNEL_DEFCONFIG="${A733_KERNEL_DEFCONFIG}" \
		CROSS_COMPILE="${A733_CROSS_COMPILE}" \
		-j"$(job_count)"

	mkdir -p "${A733_OUT}/kernel"
	cp -f "${A733_KERNEL_DIR}"/../linux-*_arm64.deb "${A733_OUT}/kernel/" 2>/dev/null || true
	ls -lh "${A733_OUT}/kernel/" 2>/dev/null || true
}

cmd_a733_uboot() {
	[[ -d "${A733_UBOOT_DIR}" ]] || die "请先 ./bsp setup"
	info "编译 u-boot + boot0（Radxa 打包流程）..."
	# u-boot-aw2501 的 Makefile.extra 提供 build/deb 目标，按存在情况选择
	if grep -qE '^build:' "${A733_UBOOT_DIR}/Makefile.extra" 2>/dev/null; then
		make -C "${A733_UBOOT_DIR}" build CROSS_COMPILE="${A733_CROSS_COMPILE}" -j"$(job_count)"
	else
		make -C "${A733_UBOOT_DIR}" deb
	fi
	mkdir -p "${A733_OUT}/uboot"
	cp -f "${A733_UBOOT_DIR}"/../u-boot-*_arm64.deb "${A733_OUT}/uboot/" 2>/dev/null || true
	ls -lh "${A733_OUT}/uboot/" 2>/dev/null || true
}

cmd_a733_rootfs() {
	# 复用 microduck 的精简 rootfs（sysvinit + busybox + ZRAM + 扩容），
	# 只额外盖一层 A733 的 console/fstab
	ROOTFS_OVERLAY_EXTRA="${BSP_ROOT}/vendor/a733/overlay" \
		cmd_rootfs_micro "$@"
}

cmd_a733_os() {
	cat <<EOF
Radxa OS 镜像（output.img）需要 rsdk，它是 Docker/Dev Container 里的 TUI：

  git clone --recurse-submodules ${A733_RSDK_REPO}
  cd rsdk && rsdk          # 选 Build system image -> ${A733_BOARD}

本仓库只负责 kernel/u-boot 的 deb 与精简 rootfs，
不重写 rsdk 的分区/打包逻辑。
EOF
}
