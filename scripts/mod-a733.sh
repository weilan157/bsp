#!/bin/bash
# Cubie A7Z（Allwinner A733 / sun60i / sun60iw2p1）
#
# 两条路线，由 A733_KERNEL_VERSION 选择：
#   5.15（默认）：Radxa 的 Debian 打包仓库，make build -> linux-*_arm64.deb
#                 https://github.com/radxa-pkg/linux-a733（submodule: kernel 5.15 + bsp + device）
#   6.6 ：全志官方 v1.4.8 的原生组合（Allwinner 已经为 6.6 提供 board.dts 与 SoC dtsi）
#                 radxa/kernel@allwinner-aiot-linux-6.6      （6.6.98）
#                 radxa/allwinner-bsp@cubie-aiot-v1.4.8       （drivers/ve、configs/linux-6.6/*.dtsi）
#                 radxa/allwinner-device@device-a733-v1.4.8   （configs/cubie_a7z/linux-6.6/board.dts）
#
# 镜像（output.img）始终由 Radxa 的 rsdk（Docker）负责。

A733_KERNEL_VERSION="${A733_KERNEL_VERSION:-5.15}"

# ---- 5.15：Debian 打包仓库 ----
A733_KERNEL_REPO="${A733_KERNEL_REPO:-https://github.com/radxa-pkg/linux-a733.git}"
A733_UBOOT_REPO="${A733_UBOOT_REPO:-https://github.com/radxa-pkg/u-boot-aw2501.git}"
A733_RSDK_REPO="${A733_RSDK_REPO:-https://github.com/RadxaOS-SDK/rsdk.git}"
A733_BOARD="${A733_BOARD:-radxa-a733}"
A733_KERNEL_DEFCONFIG="${A733_KERNEL_DEFCONFIG:-defconfig radxa.config microduck.config}"
A733_CROSS_COMPILE="${A733_CROSS_COMPILE:-aarch64-linux-gnu-}"

# ---- 6.6：全志 v1.4.8 三件套 ----
A733_KERNEL_SRC_REPO="${A733_KERNEL_SRC_REPO:-https://github.com/radxa/kernel.git}"
A733_KERNEL_SRC_BRANCH="${A733_KERNEL_SRC_BRANCH:-allwinner-aiot-linux-6.6}"
A733_BSP_REPO="${A733_BSP_REPO:-https://github.com/radxa/allwinner-bsp.git}"
A733_BSP_BRANCH="${A733_BSP_BRANCH:-cubie-aiot-v1.4.8}"
A733_DEVICE_REPO="${A733_DEVICE_REPO:-https://github.com/radxa/allwinner-device.git}"
A733_DEVICE_BRANCH="${A733_DEVICE_BRANCH:-device-a733-v1.4.8}"
A733_DTS_NAME="${A733_DTS_NAME:-sun60i-a733-cubie-a7z}"

A733_DIR="${SOURCES_DIR}/a733"
A733_KERNEL_DIR="${A733_DIR}/kernel"      # 5.15 打包仓库
A733_UBOOT_DIR="${A733_DIR}/uboot"
A733_RSDK_DIR="${A733_DIR}/rsdk"
A733_66_KERNEL_DIR="${A733_DIR}/k6.6"     # 6.6 内核源码
A733_66_BSP_DIR="${A733_DIR}/bsp"         # 6.6 的 bsp/
A733_66_DEVICE_DIR="${A733_DIR}/device"   # 6.6 的 board.dts
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

# a733_clone <url> <dest> <name> [branch] [--submodules]
a733_clone() {
	local url="$1" dest="$2" name="$3" branch="${4:-}" mode="${5:-}"
	if [[ -d "${dest}/.git" ]]; then
		info "已有 ${name}（${dest}）"
		return 0
	fi
	info "克隆 ${name} ...（首次较久）"
	local -a args=(clone --depth 1)
	[[ -n "${branch}" ]] && args+=(-b "${branch}")
	[[ "${mode}" == "--submodules" ]] && args+=(--recurse-submodules)
	git "${args[@]}" "${url}" "${dest}" || die "克隆失败: ${url}"
}

cmd_a733_setup() {
	mkdir -p "${A733_DIR}"
	if [[ "${A733_KERNEL_VERSION}" == "6.6" ]]; then
		a733_clone "${A733_KERNEL_SRC_REPO}" "${A733_66_KERNEL_DIR}" "kernel 6.6" "${A733_KERNEL_SRC_BRANCH}"
		a733_clone "${A733_BSP_REPO}" "${A733_66_BSP_DIR}" "allwinner-bsp" "${A733_BSP_BRANCH}"
		a733_clone "${A733_DEVICE_REPO}" "${A733_66_DEVICE_DIR}" "allwinner-device" "${A733_DEVICE_BRANCH}"
		info "源码就绪（6.6）："
		info "  kernel: ${A733_66_KERNEL_DIR}"
		info "  bsp:    ${A733_66_BSP_DIR}"
		info "  device: ${A733_66_DEVICE_DIR}"
		return 0
	fi

	a733_clone "${A733_KERNEL_REPO}" "${A733_KERNEL_DIR}" "linux-a733" "" "--submodules"
	a733_clone "${A733_UBOOT_REPO}" "${A733_UBOOT_DIR}" "u-boot-aw2501" "" "--submodules"
	if [[ "${A733_WITH_RSDK:-n}" == "y" ]]; then
		a733_clone "${A733_RSDK_REPO}" "${A733_RSDK_DIR}" "rsdk" "" "--submodules"
	fi
	info "源码就绪（5.15）："
	info "  kernel: ${A733_KERNEL_DIR}"
	info "  uboot:  ${A733_UBOOT_DIR}"
}

# 6.6 原生构建：把 bsp/ 挂进内核树，拼上 A7Z 的 dts，再 defconfig + microduck.config
a733_build_66() {
	local k="${A733_66_KERNEL_DIR}" b="${A733_66_BSP_DIR}" d="${A733_66_DEVICE_DIR}"
	local dstdir="" kmake=()

	[[ -d "${k}/arch/arm64" ]] || die "请先 ./bsp setup（A733_KERNEL_VERSION=6.6）"
	[[ -d "${b}/include" ]] || die "缺少 allwinner-bsp"
	[[ -f "${d}/configs/cubie_a7z/linux-6.6/board.dts" ]] || \
		die "缺少 allwinner-device 的 configs/cubie_a7z/linux-6.6/board.dts"

	# 1) 6.6 的内核顶层 Makefile 已经有 drivers-y += bsp/ 与 -I$(srctree)/bsp/include
	ln -sfn "${b}" "${k}/bsp"

	# 2) SoC dtsi（BSP）+ 板级 board.dts（device）
	dstdir="${k}/arch/arm64/boot/dts/allwinner"
	info "安装 dts: ${A733_DTS_NAME}"
	cp -f "${b}"/configs/linux-6.6/*.dtsi "${dstdir}/"
	cp -f "${d}/configs/cubie_a7z/linux-6.6/board.dts" "${dstdir}/${A733_DTS_NAME}.dts"
	grep -q "${A733_DTS_NAME}.dtb" "${dstdir}/Makefile" || \
		echo "dtb-\$(CONFIG_ARCH_SUNXI) += ${A733_DTS_NAME}.dtb" >> "${dstdir}/Makefile"

	# 3) 配置：defconfig + 精简 fragment
	install -m 644 "${BSP_ROOT}/vendor/a733/microduck.config" \
		"${k}/arch/arm64/configs/microduck.config"
	kmake=(make -C "${k}" ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}")
	info "生成配置：defconfig + microduck.config"
	"${kmake[@]}" defconfig
	bash "${k}/scripts/kconfig/merge_config.sh" -m -O "${k}" "${k}/.config" \
		"${k}/arch/arm64/configs/microduck.config"
	"${kmake[@]}" olddefconfig

	# 4) 编译
	info "编译 Image 与 ${A733_DTS_NAME}.dtb (jobs=$(job_count))"
	"${kmake[@]}" -j"$(job_count)" Image
	"${kmake[@]}" "arch/arm64/boot/dts/allwinner/${A733_DTS_NAME}.dtb"

	mkdir -p "${A733_OUT}/kernel"
	cp -f "${k}/arch/arm64/boot/Image" "${A733_OUT}/kernel/"
	cp -f "${k}/arch/arm64/boot/dts/allwinner/${A733_DTS_NAME}.dtb" "${A733_OUT}/kernel/"
	info "完成:"
	info "  ${A733_OUT}/kernel/Image"
	info "  ${A733_OUT}/kernel/${A733_DTS_NAME}.dtb"
}

cmd_a733_kernel() {
	if [[ "${A733_KERNEL_VERSION}" == "6.6" ]]; then
		a733_build_66
		return
	fi

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

本仓库只负责 kernel/u-boot 的 deb（或 6.6 的 Image/dtb）与精简 rootfs，
不重写 rsdk 的分区/打包逻辑。
EOF
}
