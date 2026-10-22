#!/bin/bash
# Cubie A7Z（Allwinner A733 / sun60iw2p1）
#
# 与 rk3566 分支同样的结构：官方 u-boot + 官方内核 + 自定义裁剪 rootfs + 板级设备树。
#   u-boot : radxa/u-boot@cubie-aiot-v1.4.6（Allwinner u-boot 2018.07 + boot0/brandy）
#   kernel : radxa/kernel@allwinner-aiot-linux-6.6（全志 6.6 BSP）
#            + radxa/allwinner-bsp@cubie-aiot-v1.4.8（bsp/ 驱动与 dtsi）
#   dts    : radxa/allwinner-device@device-a733-v1.4.8
#            configs/cubie_a7z/linux-6.6/board.dts
#   rootfs : 本仓库 micro（sysvinit + busybox + ZRAM + 扩容）
#   打包   : 按 device 的 configs/cubie_a7z/debian/sys_partition.fex 生成 MBR 镜像

A733_KERNEL_VERSION="${A733_KERNEL_VERSION:-6.6}"

# 官方源码
A733_UBOOT_REPO="${A733_UBOOT_REPO:-https://github.com/radxa/u-boot.git}"
A733_UBOOT_BRANCH="${A733_UBOOT_BRANCH:-cubie-aiot-v1.4.6}"
A733_KERNEL_SRC_REPO="${A733_KERNEL_SRC_REPO:-https://github.com/radxa/kernel.git}"
A733_KERNEL_SRC_BRANCH="${A733_KERNEL_SRC_BRANCH:-allwinner-aiot-linux-6.6}"
A733_BSP_REPO="${A733_BSP_REPO:-https://github.com/radxa/allwinner-bsp.git}"
A733_BSP_BRANCH="${A733_BSP_BRANCH:-cubie-aiot-v1.4.8}"
A733_DEVICE_REPO="${A733_DEVICE_REPO:-https://github.com/radxa/allwinner-device.git}"
A733_DEVICE_BRANCH="${A733_DEVICE_BRANCH:-device-a733-v1.4.8}"

A733_DTS_NAME="${A733_DTS_NAME:-sun60i-a733-cubie-a7z}"
A733_CROSS_COMPILE="${A733_CROSS_COMPILE:-aarch64-linux-gnu-}"
A733_BRANDY_DEFCONFIG="${A733_BRANDY_DEFCONFIG:-sun60iw2p1_a733_defconfig}"
A733_IMAGE_NAME="${A733_IMAGE_NAME:-a733-micro.img}"

A733_DIR="${SOURCES_DIR}/a733"
A733_UBOOT_DIR="${A733_DIR}/uboot"
A733_KERNEL_DIR="${A733_DIR}/k6.6"
A733_BSP_DIR="${A733_DIR}/bsp"
A733_DEVICE_DIR="${A733_DIR}/device"
A733_OUT="${OUT_DIR}/a733"

a733_env() {
	command -v apt-get >/dev/null 2>&1 || die "A733 构建按 Ubuntu/Debian 写的，需要 apt"
	local pkgs=(
		build-essential bc bison flex libssl-dev libelf-dev
		device-tree-compiler dpkg-dev debhelper fakeroot
		gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
		python3 python3-setuptools swig rsync curl wget git
		libncurses-dev libgnutls28-dev uuid-dev zstd kmod cpio
		dosfstools mtools u-boot-tools
	)
	info "安装 A733 构建依赖（需要 sudo）..."
	run_root apt-get update
	run_root apt-get install -y "${pkgs[@]}"
}

# a733_clone <url> <dest> <name> <branch>
a733_clone() {
	local url="$1" dest="$2" name="$3" branch="$4"
	if [[ -d "${dest}/.git" ]]; then
		info "已有 ${name}（${dest}）"
		return 0
	fi
	info "克隆 ${name}（${branch}）..."
	git clone --depth 1 -b "${branch}" "${url}" "${dest}" || die "克隆失败: ${url}"
}

cmd_a733_setup() {
	mkdir -p "${A733_DIR}"
	a733_clone "${A733_UBOOT_REPO}" "${A733_UBOOT_DIR}" "u-boot（官方）" "${A733_UBOOT_BRANCH}"
	a733_clone "${A733_KERNEL_SRC_REPO}" "${A733_KERNEL_DIR}" "kernel（官方）" "${A733_KERNEL_SRC_BRANCH}"
	a733_clone "${A733_BSP_REPO}" "${A733_BSP_DIR}" "allwinner-bsp" "${A733_BSP_BRANCH}"
	a733_clone "${A733_DEVICE_REPO}" "${A733_DEVICE_DIR}" "allwinner-device" "${A733_DEVICE_BRANCH}"
	info "源码就绪:"
	info "  u-boot: ${A733_UBOOT_DIR}"
	info "  kernel: ${A733_KERNEL_DIR}"
	info "  bsp:    ${A733_BSP_DIR}"
	info "  device: ${A733_DEVICE_DIR}"
}

# 官方 u-boot（2018.07 + brandy）：用仓库自带的 build.sh
cmd_a733_uboot() {
	local u="${A733_UBOOT_DIR}"
	[[ -d "${u}" ]] || die "请先 ./bsp setup"

	info "编译 u-boot + boot0（board=${A733_BRANDY_DEFCONFIG}）..."
	if [[ -x "${u}/build.sh" ]]; then
		(cd "${u}" && ./build.sh "${A733_BRANDY_DEFCONFIG}")
	elif [[ -f "${u}/Makefile" ]]; then
		die "官方 u-boot 没有 build.sh；Allwinner 的 boot0/brandy 由 longan 的打包仓库驱动，
请改用 u-boot-aw2501 打包仓库，或把 brandy 工具链放进 sources/a733/uboot"
	else
		die "u-boot 源码不完整: ${u}"
	fi

	mkdir -p "${A733_OUT}/uboot"
	local f
	for f in "${u}"/boot0*.bin "${u}"/u-boot*.bin "${u}"/u-boot-sunxi-with-spl.bin; do
		[[ -f "${f}" ]] && cp -f "${f}" "${A733_OUT}/uboot/"
	done
	ls -lh "${A733_OUT}/uboot/" 2>/dev/null || warn "没找到 boot0/u-boot 产物（看 build.sh 的输出目录）"
}

cmd_a733_kernel() {
	local k="${A733_KERNEL_DIR}" b="${A733_BSP_DIR}" d="${A733_DEVICE_DIR}"
	local dstdir="" kmake=()

	[[ -d "${k}/arch/arm64" ]] || die "请先 ./bsp setup"
	[[ -d "${b}/include" ]] || die "缺少 allwinner-bsp"
	[[ -f "${d}/configs/cubie_a7z/linux-6.6/board.dts" ]] || \
		die "缺少 allwinner-device 的 configs/cubie_a7z/linux-6.6/board.dts"

	# 1) 6.6 内核顶层 Makefile 已有 drivers-y += bsp/ 与 -I$(srctree)/bsp/include
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
}

cmd_a733_rootfs() {
	# 复用 microduck 的精简 rootfs（sysvinit + busybox + ZRAM + 扩容），
	# 只额外盖一层 A733 的 console/模块清单
	ROOTFS_OVERLAY_EXTRA="${BSP_ROOT}/vendor/a733/overlay" \
		INSTALL_AP6212_FIRMWARE=n \
		cmd_rootfs_micro "$@"
}

# 按官方 sys_partition.fex 组 MBR 镜像：boot0@8K、u-boot@128K、分区从 16MB 开始
cmd_a733_pack() {
	local fex="${BSP_ROOT}/vendor/a733/sys_partition.fex"
	local img="${A733_OUT}/${A733_IMAGE_NAME}"
	local uboot_bin="" boot0_bin="" mkimage_bin=""
	local -a pname=() psize=() pfile=()
	local line mbr_kb total off i name size file

	[[ -f "${fex}" ]] || die "缺少 ${fex}"
	[[ -f "${A733_OUT}/kernel/Image" ]] || die "请先 ./bsp kernel"
	[[ -f "${OUT_DIR}/rootfs.ext4" ]] || die "请先 ./bsp rootfs"

	for line in "${A733_OUT}"/uboot/*; do
		[[ -f "${line}" ]] || continue
		case "$(basename "${line}")" in
			boot0*) boot0_bin="${line}" ;;
			*loader*|u-boot*) uboot_bin="${line}" ;;
		esac
	done
	[[ -n "${boot0_bin}" ]] || warn "没有 boot0，镜像里 boot0 位置留空"
	[[ -n "${uboot_bin}" ]] || warn "没有 u-boot，镜像里 u-boot 位置留空"

	# 解析 fex
	mbr_kb="$(awk -F= '/^\[mbr\]/{f=1;next} f&&/^[ \t]*size/{gsub(/[^0-9]/,"",$2);print $2;exit}' "${fex}")"
	[[ -n "${mbr_kb}" ]] || mbr_kb=16384

	while IFS='|' read -r name size file; do
		[[ -n "${name}" ]] || continue
		pname+=("${name}"); psize+=("${size}"); pfile+=("${file}")
	done < <(awk '
		/^\[partition\]/ {
			if (n != "") print n "|" s "|" f
			n=""; s=""; f=""; inpart=1; next
		}
		/^\[/ { if (inpart && n != "") print n "|" s "|" f; inpart=0; n=""; next }
		inpart {
			line=$0; sub(/;.*/, "", line)
			if (line ~ /^[ \t]*name[ \t]*=/) { sub(/^[^=]*=/, "", line); gsub(/[ \t]/, "", line); n=line }
			else if (line ~ /^[ \t]*size[ \t]*=/) { sub(/^[^=]*=/, "", line); gsub(/[ \t]/, "", line); s=line }
			else if (line ~ /^[ \t]*downloadfile[ \t]*=/) { sub(/^[^=]*=/, "", line); gsub(/[ \t"]/, "", line); f=line }
		}
		END { if (inpart && n != "") print n "|" s "|" f }
	' "${fex}")
	[[ ${#pname[@]} -gt 0 ]] || die "解析 ${fex} 失败"

	# 总大小
	total=$(( mbr_kb * 1024 ))
	for size in "${psize[@]}"; do total=$(( total + size * 512 )); done

	mkdir -p "${A733_OUT}"
	rm -f "${img}"
	truncate -s "${total}" "${img}"

	[[ -n "${boot0_bin}" ]] && dd if="${boot0_bin}" of="${img}" bs=1 seek=8192 conv=notrunc status=none
	[[ -n "${uboot_bin}" ]] && dd if="${uboot_bin}" of="${img}" bs=1 seek=131072 conv=notrunc status=none

	# boot 分区：FAT，放 Image + dtb + boot.scr
	mkimage_bin="${A733_UBOOT_DIR}/tools/mkimage"
	[[ -x "${mkimage_bin}" ]] || mkimage_bin="$(command -v mkimage || true)"

	off=$(( mbr_kb * 1024 ))
	for i in "${!pname[@]}"; do
		name="${pname[$i]}"; size="${psize[$i]}"
		case "${name}" in
		boot)
			local bstaging="${A733_OUT}/boot.fex" bdir="${A733_OUT}/bootdir"
			rm -rf "${bdir}"; mkdir -p "${bdir}"
			cp -f "${A733_OUT}/kernel/Image" "${bdir}/"
			cp -f "${A733_OUT}/kernel/${A733_DTS_NAME}.dtb" "${bdir}/"
			cp -f "${BSP_ROOT}/vendor/a733/boot.cmd" "${bdir}/"
			[[ -n "${mkimage_bin}" ]] && \
				"${mkimage_bin}" -C none -A arm64 -T script -d "${BSP_ROOT}/vendor/a733/boot.cmd" "${bdir}/boot.scr" 2>/dev/null || \
				warn "mkimage 不可用，boot 分区里只有 boot.cmd（没有 boot.scr）"
			rm -f "${bstaging}"
			mkfs.vfat -F 32 -n boot -C "${bstaging}" $(( size / 2 )) >/dev/null
			mcopy -i "${bstaging}" -s "${bdir}"/* ::/ >/dev/null
			dd if="${bstaging}" of="${img}" bs=512 seek=$(( off / 512 )) conv=notrunc,sparse status=none
			;;
		rootfs)
			dd if="${OUT_DIR}/rootfs.ext4" of="${img}" bs=512 seek=$(( off / 512 )) conv=notrunc,sparse status=none
			;;
		*)
			# boot-resource/env/private 留空
			;;
		esac
		off=$(( off + size * 512 ))
	done

	info "镜像: ${img}"
	ls -lh "${img}"
	info "分区（按 sys_partition.fex）: ${pname[*]}"
	info "注意：boot0/u-boot 的写入偏移按 Allwinner 惯例 8K/128K，需上板验证。"
}
