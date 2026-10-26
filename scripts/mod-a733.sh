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
# 调试串口：none | uart2（PB0/PB1 = 40-pin 7/11）| uart4（PJ24/PJ25 = 40-pin 16/18）
A733_DEBUG_UART="${A733_DEBUG_UART:-none}"


A733_DIR="${SOURCES_DIR}/a733"
A733_UBOOT_DIR="${A733_DIR}/uboot"
A733_KERNEL_DIR="${A733_DIR}/k6.6"
A733_BSP_DIR="${A733_DIR}/bsp"
A733_DEVICE_DIR="${A733_DIR}/device"
A733_OUT="${OUT_DIR}/a733"

cmd_a733_env() {
	command -v apt-get >/dev/null 2>&1 || die "A733 构建按 Ubuntu/Debian 写的，需要 apt"
	local pkgs=(
		build-essential bc bison flex libssl-dev libelf-dev
		device-tree-compiler dpkg-dev debhelper fakeroot
		gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
		# A733 的 u-boot 是 AArch32，必须用 soft-float 的 gnueabi 工具链
		gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
		python3 python3-setuptools swig rsync curl wget git
		libncurses-dev libgnutls28-dev uuid-dev zstd kmod cpio xxd
		dosfstools fdisk uuid-runtime mtools u-boot-tools binutils-aarch64-linux-gnu lz4
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
	local u="${A733_UBOOT_DIR}" d="${A733_DEVICE_DIR}"
	[[ -d "${u}" ]] || die "请先 ./bsp setup"
	[[ -f "${d}/configs/cubie_a7z/uboot-board.dts" ]] || \
		die "缺少 allwinner-device 的 configs/cubie_a7z/uboot-board.dts"

	# u-boot 的板级 dts（arch/arm/dts/sun60i-a733-cubie-a7z.dts）最后一行是
	#   #include "../../../../device-a733/configs/cubie_a7z/uboot-board.dts"
	# 相对路径指到 u-boot 的父目录，所以把 device 仓库挂成 device-a733
	# （archlinuxarm-a733 是把 device 目录拷进 u-boot 再 sed 路径，效果一样）。
	ln -sfn "${d}" "${A733_DIR}/device-a733"

	# Allwinner 源码里的宏名拼写错误（PMIS→PMIC），新版 GCC 下会重定义报错
	local h
	for h in "${u}/arch/arm/include/asm/arch-sunxi/pmic_bus.h" \
	         "${u}/arch/riscv/include/asm/arch-sunxi/pmic_bus.h"; do
		[[ -f "${h}" ]] && sed -i 's/_SUNXI_PMIS_BUS_H/_SUNXI_PMIC_BUS_H/g' "${h}"
	done

	# 这棵官方 u-boot 只有标准 Makefile（没有 build.sh / brandy 目录）：
	# boot0 用 device 仓库自带的预编译 boot0_sdcard_*.bin，u-boot 自己编。
	# 注意 A733 的 u-boot 是 AArch32（CONFIG_SUNXI_ARM64 仍走 armv7-a + 64 位物理地址），
	# 必须用 soft-float 的 arm-linux-gnueabi-；armhf 工具链会因为默认
	# -mfloat-abi=hard 在 -march=armv7-a 下报 "architecture lacks an FPU"。
	local cc="${A733_UBOOT_CROSS_COMPILE:-arm-linux-gnueabi-}"
	command -v "${cc}gcc" >/dev/null 2>&1 || \
		die "缺少 ${cc}gcc（apt install gcc-arm-linux-gnueabi）"
	local dt="${A733_UBOOT_DTS:-sun60i-a733-cubie-a7z}"
	local defconfig="${A733_BRANDY_DEFCONFIG}"
	[[ -f "${u}/configs/${defconfig}" ]] || \
		die "u-boot 里没有 configs/${defconfig}"

	# GCC 11/12 会对 2018.07 的老代码报新的 -Werror 项。官方打包仓库
	# （radxa-pkg/u-boot-aw2501 的 Makefile.local）用的是 EXTRA_CFLAGS 关掉这些告警，
	# 这里保持一致。
	local extra_cflags="-Wno-attributes -Wno-array-bounds -Wno-address-of-packed-member"
	extra_cflags="${extra_cflags} -Wno-maybe-uninitialized -Wno-misleading-indentation"
	extra_cflags="${extra_cflags} -Wno-stringop-overflow -Wno-stringop-truncation"

	# 环境里缺 xxd 时，u-boot 的 prepare 会留下 0 字节的 sunxi_challenge.c，
	# make 之后看到文件已存在就不再生成，链接时报 undefined reference。
	if [[ -f "${u}/board/sunxi/sunxi_challenge.c" && ! -s "${u}/board/sunxi/sunxi_challenge.c" ]]; then
		rm -f "${u}/board/sunxi/sunxi_challenge.c"
	fi
	info "配置 u-boot: ${defconfig}（dt=${dt}）"
	# u-boot 的 Makefile 以当前目录为 objtree，必须 cd 进去（make -C 会把
	# arch/arm/dts 之类的路径解析到工作区根上）
	(
		cd "${u}" || die "无法进入 ${u}"
		make ARCH=arm CROSS_COMPILE="${cc}" "${defconfig}" >/dev/null
		# defconfig 的默认 DT 是参考板 soc-system，这里换成 A7Z 板级 dts，
		# 否则 dts/dt.dtb 会把 soc-system.dtb 一起 grep 进来（不存在就失败）
		sed -i "s|^CONFIG_DEFAULT_DEVICE_TREE=.*|CONFIG_DEFAULT_DEVICE_TREE=\"${dt}\"|" .config
		# 调试串口换到 UART2/4 时，u-boot 的 console 索引也跟着换
		# （sunxi 的 CONFIG_CONS_INDEX 是 1-based：uart0=1, uart2=3, uart4=5）
		case "${A733_DEBUG_UART}" in
		uart2) sed -i 's/^CONFIG_CONS_INDEX=.*/CONFIG_CONS_INDEX=3/' .config ;;
		uart4) sed -i 's/^CONFIG_CONS_INDEX=.*/CONFIG_CONS_INDEX=5/' .config ;;
		esac
		make ARCH=arm CROSS_COMPILE="${cc}" olddefconfig >/dev/null

		info "编译 u-boot（ARCH=arm CROSS_COMPILE=${cc}）..."
		make ARCH=arm CROSS_COMPILE="${cc}" -j"$(job_count)" \
			DEVICE_TREE="${dt}" EXTRA_CFLAGS="${extra_cflags}"
	)

	local out="${A733_OUT}/uboot"
	mkdir -p "${out}"
	cp -f "${u}/u-boot.bin" "${out}/u-boot.bin"
	[[ -f "${u}/u-boot.dtb" ]] && cp -f "${u}/u-boot.dtb" "${out}/u-boot.dtb"

	# ---- boot0 + boot_package.fex：必须用 Allwinner 的官方工具处理 ----
	# 1) device/bin 里的 boot0_sdcard_*.bin 只是「模板」，出厂前要用
	#    update_boot0 把板子的 sys_config.bin（DRAM 参数、GPIO）注进去；
	#    不注入就是错误的 DDR 时序，BROM 跳过去直接死，串口一个字都没有。
	# 2) u-boot 不能裸放，要 dragonsecboot 打成 TOC1 包，且里面必须有
	#    monitor（BL31/ATF），boot0 先跳 BL31 再跳 u-boot。
	a733_ensure_tools
	a733_pack_bootloader "${u}" "${d}" "${out}"

	ls -lh "${out}/"
}

# 官方打包工具（update_boot0 / script / dragonsecboot）
A733_TOOLS_REPO="${A733_TOOLS_REPO:-https://gitlab.com/tina5.0_aiot/lichee/tools.git}"
A733_TOOLS_BRANCH="${A733_TOOLS_BRANCH:-product-aiot-stable}"
A733_TOOLS_DIR="${A733_TOOLS_DIR:-${A733_DIR}/awtools}"

a733_ensure_tools() {
	local t="${A733_TOOLS_DIR}"
	if [[ ! -x "${t}/pack/pctools/linux/mod_update/update_boot0" ]]; then
		info "拉取 Allwinner 打包工具（${A733_TOOLS_BRANCH}）..."
		rm -rf "${t}"
		git clone --depth 1 --filter=blob:none --sparse \
			-b "${A733_TOOLS_BRANCH}" "${A733_TOOLS_REPO}" "${t}" || \
			die "克隆打包工具失败: ${A733_TOOLS_REPO}"
		git -C "${t}" sparse-checkout set \
			pack/pctools/linux/mod_update pack/pctools/linux/openssl
	fi
	local f
	for f in mod_update/update_boot0 mod_update/script openssl/dragonsecboot; do
		[[ -x "${t}/pack/pctools/linux/${f}" ]] || die "打包工具缺 ${f}（${t}）"
	done
}

# 生成 boot0.bin（已注入 sys_config）与 boot_package.fex（u-boot + BL31）
a733_pack_bootloader() {
	local u="$1" d="$2" out="$3"
	local t="${A733_TOOLS_DIR}/pack/pctools/linux"
	local work tmp cfg

	work="${A733_OUT}/bootloader"
	rm -rf "${work}"
	mkdir -p "${work}"
	cd "${work}" || die "无法进入 ${work}"

	# sys_config.fex -> sys_config.bin（fex 需要 CRLF，官方用 unix2dos）
	cp -f "${d}/configs/cubie_a7z/sys_config.fex" sys_config.fex
	# boot0 的调试打印走 115200 串口，量不小；生产默认关掉（调试时 A733_BOOT0_DEBUG=y）
	if [[ "${A733_BOOT0_DEBUG:-n}" != "y" ]]; then
		sed -i 's/^debug_mode.*/debug_mode  = 0/' sys_config.fex
	fi
	# UART2 调试口（PB0/PB1）和 JTAG 复用同一组脚，用 uart2 时把 JTAG 关掉
	if [[ "${A733_DEBUG_UART}" == "uart2" ]]; then
		sed -i 's/^jtag_enable.*/jtag_enable     = 0/' sys_config.fex
	fi
	# 调试串口搬到 UART2/4（boot0 从 [uart_para] 读），UART0 留给舵机
	case "${A733_DEBUG_UART}" in
	uart4)
		sed -i 's/^uart_debug_port.*/uart_debug_port = 4/' sys_config.fex
		sed -i 's/^uart_debug_tx.*/uart_debug_tx   = port:PJ24<2><1><default><default>/' sys_config.fex
		sed -i 's/^uart_debug_rx.*/uart_debug_rx   = port:PJ25<2><1><default><default>/' sys_config.fex
		;;
	uart2)
		sed -i 's/^uart_debug_port.*/uart_debug_port = 2/' sys_config.fex
		sed -i 's/^uart_debug_tx.*/uart_debug_tx   = port:PB00<2><1><default><default>/' sys_config.fex
		sed -i 's/^uart_debug_rx.*/uart_debug_rx   = port:PB01<2><1><default><default>/' sys_config.fex
		;;
	esac
	sed -i 's/\r$//; s/$/\r/' sys_config.fex
	"${t}/mod_update/script" sys_config.fex >/dev/null || die "sys_config.fex 转换失败"
	[[ -f sys_config.bin ]] || die "没有得到 sys_config.bin"

	# boot0：SD 卡版注入 SDMMC_CARD，UFS 版注入 UFS
	local src dst dev
	for dev in SDMMC_CARD UFS; do
		case "${dev}" in
			SDMMC_CARD) src="${d}/bin/boot0_sdcard_sun60iw2p1.bin"; dst=boot0_sdcard.bin ;;
			UFS)        src="${d}/bin/boot0_ufs_sun60iw2p1.bin";   dst=boot0_ufs.bin ;;
		esac
		[[ -f "${src}" ]] || { warn "缺少 ${src}"; continue; }
		cp -f "${src}" "${dst}"
		info "update_boot0 ${dst}（${dev}）"
		"${t}/mod_update/update_boot0" "${dst}" sys_config.bin "${dev}" \
			| sed 's/^/  /' || die "update_boot0 ${dst} 失败"
	done

	# boot_package.fex：u-boot + monitor（BL31），有 SCP 固件就一起打
	cfg="boot_package.cfg"
	cp -f "${u}/u-boot-sun60iw2p1.bin" . 2>/dev/null || cp -f "${u}/u-boot.bin" u-boot-sun60iw2p1.bin
	cp -f "${d}/bin/bl31.bin" bl31-a733.bin
	{
		echo "[package]"
		echo "item=u-boot, u-boot-sun60iw2p1.bin"
		echo "item=monitor, bl31-a733.bin"
	} > "${cfg}"
	local scp
	for scp in "${d}"/bin/scp*.bin "${A733_OUT}"/scp.bin; do
		[[ -f "${scp}" ]] || continue
		cp -f "${scp}" scp-a733.bin
		echo "item=scp, scp-a733.bin" >> "${cfg}"
		break
	done
	info "dragonsecboot -pack（$(grep -c '^item=' "${cfg}") 个 item）"
	"${t}/openssl/dragonsecboot" -pack "${cfg}" >/dev/null || die "dragonsecboot 打包失败"
	[[ -f boot_package.fex ]] || die "没有得到 boot_package.fex"

	cp -f boot0_sdcard.bin "${out}/boot0.bin"
	[[ -f boot0_ufs.bin ]] && cp -f boot0_ufs.bin "${out}/boot0_ufs.bin"
	cp -f boot_package.fex "${out}/boot_package.fex"
	cp -f sys_config.bin "${out}/sys_config.bin"
	info "boot0 / boot_package.fex 就绪（sys_config 已注入）"
}

cmd_a733_kernel() {
	local k="${A733_KERNEL_DIR}" b="${A733_BSP_DIR}" d="${A733_DEVICE_DIR}"
	local dstdir="" kmake=()

	[[ -d "${k}/arch/arm64" ]] || die "请先 ./bsp setup"
	[[ -d "${b}/include" ]] || die "缺少 allwinner-bsp"
	[[ -f "${d}/configs/cubie_a7z/linux-6.6/board.dts" ]] || \
		die "缺少 allwinner-device 的 configs/cubie_a7z/linux-6.6/board.dts"

	# BSP 的 ccu_common.c 需要 <sunxi-autogen.h>（正常由 longan 的 mkkernel.sh 生成，
	# 内容只有 AW_BSP_VERSION）。放到它所在目录，保证角度包含能找到。
	a733_gen_sunxi_autogen() {
		local b="$1" h
		for h in "${b}/include/sunxi-autogen.h" "${b}/drivers/clk/sunxi-ng/sunxi-autogen.h"; do
			[[ -f "${h}" ]] && continue
			printf '/* generated by microduck ./bsp kernel */\n#define AW_BSP_VERSION "microduck-a733"\n' > "${h}"
		done
	}
	a733_gen_sunxi_autogen "${b}"

	# 1) 6.6 内核顶层 Makefile 已有 drivers-y += bsp/ 与 -I$(srctree)/bsp/include
	ln -sfn "${b}" "${k}/bsp"

	# 2) SoC dtsi（BSP）+ 板级 board.dts（device）+ microduck 的 HAT 适配
	dstdir="${k}/arch/arm64/boot/dts/allwinner"
	info "安装 dts: ${A733_DTS_NAME}"
	cp -f "${b}"/configs/linux-6.6/*.dtsi "${dstdir}/"
	cp -f "${d}/configs/cubie_a7z/linux-6.6/board.dts" "${dstdir}/board-a7z.dts"
	cp -f "${BSP_ROOT}/vendor/a733/dts/microduck-a7z.dtsi" "${dstdir}/"
	{
		echo "// 由 ./bsp kernel 生成：官方 board.dts + microduck HAT 适配"
		echo '#include "board-a7z.dts"'
		echo '#include "microduck-a7z.dtsi"'
		if [[ "${A733_WITH_CAMERA:-n}" == "y" ]]; then
			cp -f "${BSP_ROOT}/vendor/a733/dts/microduck-a7z-camera.dtsi" "${dstdir}/"
			echo '#include "microduck-a7z-camera.dtsi"'
		fi
		if [[ "${A733_DEBUG_UART}" == "uart2" || "${A733_DEBUG_UART}" == "uart4" ]]; then
			echo '#include "microduck-debug-uart.dtsi"'
		fi
	} > "${dstdir}/${A733_DTS_NAME}.dts"

	# 调试串口：UART0（8/10）留给舵机，按 A733 的 pinmux 表把 UART2/4 引到空闲脚。
	#   uart2 -> PB0/PB1 = 40-pin 7/11（注意 7 脚 HAT 做 Stemma SDA 时不要用）
	#   uart4 -> PJ24/PJ25 = 40-pin 16/18（HAT 的 GPIO23/24 没分配功能，推荐）
	if [[ "${A733_DEBUG_UART}" == "uart2" ]]; then
		debug_pins='"PB0", "PB1"'
	elif [[ "${A733_DEBUG_UART}" == "uart4" ]]; then
		debug_pins='"PJ24", "PJ25"'
	else
		debug_pins=""
	fi
	if [[ -n "${debug_pins}" ]]; then
		cat > "${dstdir}/microduck-debug-uart.dtsi" <<EOF
/* 由 ./bsp kernel 生成：${A733_DEBUG_UART} 调试串口（UART0 留给舵机） */
&pio {
	uart_debug_pins: uart-debug-pins {
		pins = ${debug_pins};
		function = "${A733_DEBUG_UART}";
	};
};

&${A733_DEBUG_UART} {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&uart_debug_pins>;
};
EOF
	fi
	grep -q "${A733_DTS_NAME}.dtb" "${dstdir}/Makefile" || \
		echo "dtb-\$(CONFIG_ARCH_SUNXI) += ${A733_DTS_NAME}.dtb" >> "${dstdir}/Makefile"

	# 3) 配置：defconfig + 精简 fragment
	install -m 644 "${BSP_ROOT}/vendor/a733/microduck.config" \
		"${k}/arch/arm64/configs/microduck.config"
	# BSP 的 Kconfig 用 $(BSP_TOP)platform/Kconfig（结尾斜杠），
	# nand/codec 的 Makefile 还依赖 LICHEE_KERN_DIR 和 PWD（codec 用 $(PWD) 拼绝对路径）。
	export BSP_TOP="${k}/bsp/"
	export LICHEE_KERN_DIR="${k}"
	# cedar-ve/platforms/*.c 用 `"cedar_ve.h"`，Kbuild 只加了 platforms 目录
	export KCFLAGS="-I${b}/drivers/ve/cedar-ve"
	cd "${k}" || die "无法进入 $k"
	kmake=(make ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}")
	info "生成配置：defconfig + microduck.config"
	"${kmake[@]}" defconfig
	bash "${k}/scripts/kconfig/merge_config.sh" -m -O "${k}" "${k}/.config" \
		"${k}/arch/arm64/configs/microduck.config"
	"${kmake[@]}" olddefconfig

	# 4) 编译
	info "编译 Image 与 ${A733_DTS_NAME}.dtb (jobs=$(job_count))"
	"${kmake[@]}" -j"$(job_count)" Image
	# 只编我们这一个 dtb：make dtbs 会把 mainline 的 dts 全编一遍（1-2 分钟），
	# 这里直接用 cpp + dtc，几十毫秒。BSP 的 dt-bindings 头靠 -I bsp/include。
	info "编译 dtb: ${A733_DTS_NAME}.dtb"
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
		-I "${k}/include" -I "${b}/include" \
		-I "${k}/arch/arm64/boot/dts" -I "${dstdir}" \
		-I "${k}/scripts/dtc/include-prefixes" \
		-o "${dstdir}/${A733_DTS_NAME}.dtb.pp" "${dstdir}/${A733_DTS_NAME}.dts" || \
		die "dts cpp 失败"
	dtc -I dts -O dtb -o "${dstdir}/${A733_DTS_NAME}.dtb" \
		"${dstdir}/${A733_DTS_NAME}.dtb.pp" || die "dtc 失败"
	rm -f "${dstdir}/${A733_DTS_NAME}.dtb.pp"

	mkdir -p "${A733_OUT}/kernel"
	cp -f "${k}/arch/arm64/boot/Image" "${A733_OUT}/kernel/"
	cp -f "${k}/arch/arm64/boot/dts/allwinner/${A733_DTS_NAME}.dtb" "${A733_OUT}/kernel/"

	# 可选：压一份 Image.lz4（arm64 内核不自解压，要 u-boot 带 lz4 命令才能用）。
	# Tina 裁剪指南实测总时间 LZO 159ms、LZ4 170ms、GZIP 213ms、XZ 771ms。
	if [[ "${A733_KERNEL_COMPRESS:-}" == "lz4" ]]; then
		if command -v lz4 >/dev/null 2>&1; then
			info "生成 Image.lz4（legacy 格式，给 u-boot lz4 用）"
			lz4 -l -9 -f "${A733_OUT}/kernel/Image" "${A733_OUT}/kernel/Image.lz4" >/dev/null
		else
			warn "没有 lz4 命令，跳过 Image.lz4（apt install lz4）"
		fi
	fi
}

cmd_a733_rootfs() {
	# 复用 microduck 的精简 rootfs（sysvinit + busybox + ZRAM + 扩容），
	# 只额外盖一层 A733 的 console/模块清单
	ROOTFS_OVERLAY_EXTRA="${BSP_ROOT}/vendor/a733/overlay" \
		INSTALL_AP6212_FIRMWARE=n \
		ROOTFS_STRIP=y \
		cmd_rootfs_micro "$@"
}

# 把 A733 内核树编出的模块装进 rootfs：rk3566 的 install_kernel_modules 只看
# ${KERNEL_DIR}（sources/kernel）与 out/kernel/Image，A733 两者都不是。
# 由 mod-rootfs.sh 的 cmd_rootfs_micro 通过 hook 调用。
rootfs_install_platform_modules() {
	local rootfs="$1" k="${A733_KERNEL_DIR}" b="${A733_BSP_DIR}" rel
	[[ "${KERNEL_MODULES_INSTALL}" == "y" ]] || return 0
	[[ -d "${k}" ]] || return 0
	[[ -f "${A733_OUT}/kernel/Image" ]] || return 0

	info "编译并安装 A733 内核模块 -> ${rootfs}/lib/modules"
	# 先把最新的 fragment 合进 .config：否则改了 microduck.config（比如关掉
	# AW_INPUT_SENSORINIT）又没重跑 ./bsp kernel 时，modules 会按旧配置编出
	# init-input.ko，modpost 报 irq_to_desc undefined。
	(
		cd "${k}" || exit 1
		# Kconfig 的 bsp/Kconfig 用 $(BSP_TOP) 拼路径，这里也要带上
		export BSP_TOP="${k}/bsp/"
		export LICHEE_KERN_DIR="${k}"
		install -m 644 "${BSP_ROOT}/vendor/a733/microduck.config" \
			"${k}/arch/arm64/configs/microduck.config" || exit 1
		bash "${k}/scripts/kconfig/merge_config.sh" -m -O "${k}" "${k}/.config" \
			"${k}/arch/arm64/configs/microduck.config" >/dev/null 2>&1 || exit 1
		make ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}" olddefconfig >/dev/null 2>&1 || exit 1
	)
	(
		cd "${k}" || exit 1
		export BSP_TOP="${b%/}/"
		export LICHEE_KERN_DIR="${k}"
		export KCFLAGS="-I${b}/drivers/ve/cedar-ve"
		make ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}" -j"$(job_count)" modules
	)
	run_root rm -rf "${rootfs}/lib/modules"
	(
		cd "${k}" || exit 1
		export BSP_TOP="${b%/}/"
		export LICHEE_KERN_DIR="${k}"
		run_root env INSTALL_MOD_STRIP=1 \
			make ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}" \
			INSTALL_MOD_PATH="${rootfs}" modules_install
	)
	rel="$(make -s -C "${k}" ARCH=arm64 CROSS_COMPILE="${A733_CROSS_COMPILE}" \
		kernelrelease 2>/dev/null | tr -d '[:space:]')"
	if [[ -n "${rel}" ]] && command -v depmod >/dev/null 2>&1; then
		run_root depmod -b "${rootfs}" -a "${rel}" || warn "depmod 失败"
	fi
	info "模块数: $(run_root find "${rootfs}/lib/modules" -name '*.ko*' | wc -l)"
}

# 检查编出来的 dtb 是否满足 HAT 的 BSP/HAL 基本要求
cmd_a733_hal() {
	local dtb="${A733_OUT}/kernel/${A733_DTS_NAME}.dtb"
	local txt fail=0

	[[ -f "${dtb}" ]] || die "请先 ./bsp kernel（找不到 ${dtb}）"
	txt="$(mktemp)"
	dtc -I dtb -O dts "${dtb}" > "${txt}" 2>/dev/null || die "反编译 dtb 失败: ${dtb}"

	check() {
		local name="$1" pat="$2"
		if grep -qE "${pat}" "${txt}"; then
			printf '  [ok]   %s\n' "${name}"
		else
			printf '  [FAIL] %s\n' "${name}"
			fail=1
		fi
	}

	info "HAT BSP/HAL 检查: ${dtb}"
	# 舵机：UART0 PB9/PB10，不被 console 占用（console 在 bootargs 里，见 boot.cmd）
	check "舵机串口 uart0 = PB9/PB10" 'pins = "PB9'
	check "I2C twi7 = PJ22/PJ23, 400 kHz" '0x61a80'
	check "codec TLV320AIC3104 @0x18" 'tlv320aic3104'
	check "ToF VL53L5CX @0x29" 'vl53l5cx'
	check "BMI088 accel @0x19 / gyro @0x68" 'bmi088'
	check "I2S0 音频（soundcard-mach）" 'i2s0_mach'
	check "关机检测 PB2（gpio-keys）" 'hat-power-detect'
	if [[ "${A733_WITH_CAMERA:-n}" == "y" ]]; then
		check "摄像头 IMX219（VIN sensor0）" 'imx219'
	fi

	rm -f "${txt}"
	[[ ${fail} -eq 0 ]] || die "HAT 检查有失败项（见上）"
	info "HAT 基本要求全部满足"
}

# 按 rsdk 官方布局生成 SD 卡镜像（A733：GPT + config + rootfs）
#   0..16 MiB      boot0 @128 KiB（setup.sh: seek=256）、boot0_ufs @2064 扇区、
#                  boot_package.fex @12 MiB（seek=24576）
#   16..32 MiB     p1 FAT "config"（16 MiB，rsdk 的 /config）
#   32 MiB..末尾    p2 ext4 "rootfs"（内核/设备树/启动脚本都在 rootfs 的 /boot 下）
# 依据：rsdk src/share/rsdk/build/image.jsonnet（part-add 32768 65535 / 65536 -34）
#       与 configs/socs.json（a733: partition_table_type=gpt, firmware_type=u-boot）；
#       boot0/boot_package 偏移来自 u-boot 包里的 setup.sh update_bootloader。
cmd_a733_pack() {
	local img="${A733_OUT}/${A733_IMAGE_NAME}"
	local rootdir="${OUT_DIR}/rootfs"
	local boot0="${A733_OUT}/uboot/boot0.bin"
	local boot0ufs="${A733_OUT}/uboot/boot0_ufs.bin"
	local pkg="${A733_OUT}/uboot/boot_package.fex"
	local kernel="${A733_OUT}/kernel/Image"
	local dtb="${A733_OUT}/kernel/${A733_DTS_NAME}.dtb"
	local mkimage_bin="${A733_UBOOT_DIR}/tools/mkimage"
	local cfg_start=32768 cfg_size=32768 root_start=65536
	local rootfs_uuid cfg_id cfg_uuid img_size fs_mb tmp_cfg pt
	local bootargs

	[[ -f "${boot0}" ]] || die "缺少 ${boot0}，请先 ./bsp uboot"
	[[ -f "${pkg}" ]] || die "缺少 ${pkg}，请先 ./bsp uboot"
	[[ -f "${kernel}" && -f "${dtb}" ]] || die "请先 ./bsp kernel"
	[[ -d "${rootdir}" ]] || die "缺少 ${rootdir}，请先 ./bsp rootfs"
	command -v mkfs.vfat >/dev/null 2>&1 || die "缺少 mkfs.vfat（dosfstools）"
	command -v mkfs.ext4 >/dev/null 2>&1 || die "缺少 mkfs.ext4（e2fsprogs）"
	if [[ ! -x "${mkimage_bin}" ]]; then
		mkimage_bin="$(command -v mkimage || true)"
		[[ -n "${mkimage_bin}" ]] || die "缺少 mkimage（u-boot-tools）"
	fi

	rootfs_uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
	cfg_id="$(printf '%s' "${rootfs_uuid}" | cut -c1-8 | tr 'a-f' 'A-F')"
	cfg_uuid="${cfg_id:0:4}-${cfg_id:4:4}"
	local console
	if [[ -n "${A733_CONSOLE:-}" ]]; then
		console="${A733_CONSOLE}"
	else
		case "${A733_DEBUG_UART}" in
		uart4) console="ttyS4,115200" ;;
		uart2) console="ttyS2,115200" ;;
		*) console="tty1" ;;
		esac
	fi
	bootargs="console=${console} root=UUID=${rootfs_uuid} rw cma=8M loglevel=3"

	# 1) 内核/设备树/启动脚本放进 rootfs 的 /boot（官方镜像就是这样，
	#    u-boot 的 distro_bootcmd 扫到 ext4 分区根上的 /boot.scr 再 source 它）
	info "安装内核与启动脚本到 rootfs /boot"
	run_root mkdir -p "${rootdir}/boot/extlinux" "${rootdir}/etc/kernel" "${rootdir}/config"
	run_root cp -f "${kernel}" "${rootdir}/boot/Image"
	run_root cp -f "${dtb}" "${rootdir}/boot/${A733_DTS_NAME}.dtb"

	sed -e "s|@BOOTARGS@|${bootargs}|" \
		-e "s|@DTB@|${A733_DTS_NAME}.dtb|" \
		"${BSP_ROOT}/vendor/a733/boot.cmd" > "${A733_OUT}/boot.cmd"
	"${mkimage_bin}" -C none -A arm64 -T script -d "${A733_OUT}/boot.cmd" \
		"${rootdir}/boot/boot.scr" >/dev/null || die "生成 boot.scr 失败"

	# extlinux.conf / cmdline：rsdk 会给内核 deb 里的这两个文件改 root=UUID，
	# 本 u-boot 没有 sysboot 命令（没有 CONFIG_CMD_SYSBOOT），实际启动走 boot.scr，
	# 这里仍按官方格式生成，方便换成支持 extlinux 的 u-boot 时直接生效
	cat > "${A733_OUT}/extlinux.conf" <<EOF
default l0
menu title Boot menu
label l0
	menu label Debian GNU/Linux
	linux /boot/Image
	fdt /boot/${A733_DTS_NAME}.dtb
	append ${bootargs}
EOF
	run_root cp -f "${A733_OUT}/extlinux.conf" "${rootdir}/boot/extlinux/extlinux.conf"
	printf '%s\n' "${bootargs}" > "${A733_OUT}/cmdline"
	run_root cp -f "${A733_OUT}/cmdline" "${rootdir}/etc/kernel/cmdline"

	# fstab：按 rsdk 的做法用文件系统 UUID（config + rootfs）
	cat > "${A733_OUT}/fstab" <<EOF
# rsdk 布局：p1 config（FAT）/ p2 rootfs（ext4）
UUID=${cfg_uuid}  /config  vfat  defaults  0 2
UUID=${rootfs_uuid}  /  ext4  defaults,noatime  0 1
EOF
	run_root cp -f "${A733_OUT}/fstab" "${rootdir}/etc/fstab"

	# 2) 重打 ext4（带 /boot 内容），文件系统 UUID 固定成 fstab 里那个
	fs_mb="$(run_root du --apparent-size -sm "${rootdir}" | cut -f1)"
	local file_count
	file_count="$(run_root find "${rootdir}" | wc -l)"
	fs_mb=$(( fs_mb + file_count * 4 / 1024 + 64 ))
	fs_mb=$(( fs_mb * 110 / 100 ))
	img_size=$(( root_start * 512 + fs_mb * 1024 * 1024 ))
	info "rootfs.ext4: ${fs_mb} MiB，UUID=${rootfs_uuid}"
	run_root rm -f "${OUT_DIR}/rootfs.ext4"
	run_root mkfs.ext4 -d "${rootdir}" -L rootfs -U "${rootfs_uuid}" \
		"${OUT_DIR}/rootfs.ext4" "${fs_mb}M" >/dev/null || die "mkfs.ext4 失败"

	# 3) config 分区（16 MiB FAT）
	tmp_cfg="${A733_OUT}/config.fat"
	run_root rm -f "${tmp_cfg}"
	run_root mkfs.vfat -F 16 -n config -i "${cfg_id}" -C "${tmp_cfg}" \
		"$(( cfg_size / 2 ))" >/dev/null || die "mkfs.vfat 失败"

	# 4) 组镜像
	info "生成镜像: ${img}（GPT，config@16MiB，rootfs@32MiB）"
	run_root mkdir -p "${A733_OUT}"
	run_root rm -f "${img}"
	run_root truncate -s "${img_size}" "${img}"
	run_root dd if="${boot0}" of="${img}" bs=512 seek=256 conv=notrunc status=none
	if [[ -f "${boot0ufs}" ]]; then
		# setup.sh 同时写一份 UFS 用的 boot0（seek=2064），照做
		run_root dd if="${boot0ufs}" of="${img}" bs=512 seek=2064 conv=notrunc status=none
	fi
	run_root dd if="${pkg}" of="${img}" bs=512 seek=24576 conv=notrunc status=none
	run_root dd if="${tmp_cfg}" of="${img}" bs=512 seek="${cfg_start}" conv=notrunc,sparse status=none
	run_root dd if="${OUT_DIR}/rootfs.ext4" of="${img}" bs=512 seek="${root_start}" \
		conv=notrunc,sparse status=none

	# 5) GPT（两个分区：config 16 MiB、rootfs 到末尾）
	pt="$(mktemp)"
	{
		echo "label: gpt"
		echo "unit: sectors"
		echo
		echo "start=${cfg_start}, size=${cfg_size}, name=\"config\""
		echo "start=${root_start}, name=\"rootfs\""
	} > "${pt}"
	run_root sfdisk --no-tell-kernel --force --quiet "${img}" < "${pt}" || die "写 GPT 失败"
	rm -f "${pt}"

	info "镜像: ${img}"
	ls -lh "${img}"
	sfdisk -d "${img}" 2>/dev/null | sed 's/^/  /'
	info "boot0@128KiB、boot0_ufs@2064 扇区、boot_package.fex@12MiB"
	info "p1 config(FAT)@16MiB、p2 rootfs(ext4)@32MiB；u-boot 从 p2 的 /boot.scr 启动"
	info "注意：与 rsdk 布局对齐，但仍需上板验证"
}

