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
# NPU：A733 的 VIP9000（aw_nna_vip/vip2）。默认不开（驱动默认 n、官方 min defconfig 也没开）
A733_WITH_NPU="${A733_WITH_NPU:-y}"
# 是否把 NPU 用户态 runtime（VIPLite/vpm_run）也装进 rootfs
A733_NPU_RUNTIME="${A733_NPU_RUNTIME:-y}"


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
		# 我们的镜像用 GPT；这颗 defconfig 默认没开 EFI_PARTITION，
		# u-boot 就会只认 MBR，报 "Invalid partition 1"、扫不到 rootfs 分区
		if ! grep -q '^CONFIG_EFI_PARTITION=y' .config; then
			sed -i 's|^# CONFIG_EFI_PARTITION is not set|CONFIG_EFI_PARTITION=y|' .config
			grep -q '^CONFIG_EFI_PARTITION=y' .config || echo 'CONFIG_EFI_PARTITION=y' >> .config
		fi
		# Kconfig 里这一项 default 56 if ARCH_SUNXI；sfdisk 写的 GPT 是 128 项，
		# u-boot 只读 56 项（7 KiB 缓冲区）却按 header 的 128 项算 CRC，
		# 尾巴是未初始化内存 → 每次都报 "Entry Array CRC is wrong"，
		# 然后回退到「卡末尾」找备份 GPT（30 GB 卡上当然是垃圾）→ 分区全丢。
		# 设成 128 后 CRC 与缓冲区都对得上，GPT 解析就稳定了。
		sed -i 's|^CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=.*|CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=128|' .config
		grep -q '^CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=128' .config || \
			echo 'CONFIG_EFI_PARTITION_ENTRIES_NUMBERS=128' >> .config
		# 这颗 sunxi u-boot 在这张卡上解析分区表（GPT/MBR 都试过）不可靠：
		# 报 "No partition table - mmc 0" 或 GPT CRC 错，distro_bootcmd 扫不到
		# /boot.scr。这里的镜像把 Image/dtb 裸放在固定 LBA（16MiB / 55MiB），
		# 用 `mmc read` 直接读，完全绕开分区表；分区表只留给内核用。
		# 注意：不要关 CONFIG_ENV_IS_IN_SUNXI_FLASH —— 关掉它会连带丢失
		# CONFIG_ENV_SIZE，u-boot 编不过（environment.h 里 ENV_SIZE 依赖它）。
		# 卡上 env 无效时会退回默认 env，用的就是下面这条 CONFIG_BOOTCOMMAND。
		sed -i 's|^CONFIG_BOOTDELAY=.*|CONFIG_BOOTDELAY=1|' .config
		# 注意：一次 mmc read 的块数有上限（超了会失败，而 hush 里某条命令失败会
		# 静默中止后面所有命令，看起来就像"卡在 mmc dev 0"）。这里按 16 MiB
		# 一段分三次读 Image（74k 扇区），再读 dtb。
		# 关键：mmc read 的 block/count 按十六进制解析！
		# Image@16MiB=0x8000 扇区，dtb@56MiB=0x1C000 扇区；每段 0x8000（16 MiB）
		local rawboot
		# console/earlycon 与内核 cmdline 保持一致（uart4 时是 ttyAS4 + 0x02504000）
		local uboot_console="ttyAS0,115200" uboot_early="0x02500000"
		case "${A733_DEBUG_UART:-none}" in
		uart4) uboot_console="ttyAS4,115200"; uboot_early="0x02504000" ;;
		uart2) uboot_console="ttyAS2,115200"; uboot_early="0x02502000" ;;
		esac
		rawboot="mmc dev 0; setenv bootargs console=${uboot_console} earlycon=uart8250,mmio32,${uboot_early} root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait cma=128M loglevel=8"
		rawboot="${rawboot}; mmc read 0x40080000 0x8000 0x8000"
		rawboot="${rawboot}; mmc read 0x41080000 0x10000 0x8000"
		rawboot="${rawboot}; mmc read 0x42080000 0x18000 0x2200"
		rawboot="${rawboot}; mmc read 0x43000000 0x1C000 0x800"
		rawboot="${rawboot}; booti 0x40080000 - 0x43000000"
		rawboot="${rawboot}; run distro_bootcmd"
		sed -i "s|^CONFIG_BOOTCOMMAND=.*|CONFIG_BOOTCOMMAND=\"${rawboot}\"|" .config
		grep -q '^CONFIG_BOOTCOMMAND="mmc dev 0' .config || \
			echo "CONFIG_BOOTCOMMAND=\"${rawboot}\"" >> .config

		# ---- 快速启动（A733_UBOOT_FAST=y，默认开）----
		# 实测上电到内核的时间几乎全在 u-boot：PCIe 链路训练两次 timeout(~2.4s)、
		# UFS 无设备仍做 4 次校准(~2-3s)、USB 双总线扫描 + usb burn(~1s)。
		# 本板从 SD 卡启动，这些都用不到，直接关掉；bootcmd 改成直接 sysboot
		# 到 extlinux.conf，跳过 distro_bootcmd 的设备枚举（失败再回退）。
		if [[ "${A733_UBOOT_FAST:-y}" == "y" ]]; then
			local sym fastboot
			# 说明：只关驱动本体不够——board/sunxi 与 cmd/ 里还有无条件引用，
			# 会链接失败（sunxi_pcie_exit / sunxi_usb_dev_register /
			# sunxi_fastboot_status_read）。所以把"使用者"也一起关掉：
			#   CONFIG_PCI               -> board_quiesce_devices 里的 sunxi_pcie_exit
			#   CONFIG_CMD_FASTBOOT      -> cmd_fastboot.c 的 sunxi_usb_*
			#   CONFIG_CMD_SPRITE        -> sunxi_sprite.c 的 sunxi_usb_*
			#   CONFIG_SUNXI_ANDROID_BOOT-> board_late_init 的 sunxi_fastboot_status_read
			for sym in CONFIG_UFS CONFIG_SUNXI_UFS \
				   CONFIG_PCI CONFIG_PCIE_ALLWINNER_RC \
				   CONFIG_USB CONFIG_CMD_USB CONFIG_USB_EHCI_HCD \
				   CONFIG_USB_STORAGE CONFIG_SUNXI_USB CONFIG_DM_USB \
				   CONFIG_CMD_FASTBOOT CONFIG_CMD_SUNXI_SPRITE \
				   CONFIG_SUNXI_ANDROID_BOOT; do
				sed -i "s|^${sym}=.*|# ${sym} is not set|" .config
				grep -q "^# ${sym} is not set" .config || \
					echo "# ${sym} is not set" >> .config
			done
			sed -i 's|^CONFIG_BOOTDELAY=.*|CONFIG_BOOTDELAY=0|' .config
			# 单引号：${scriptaddr} 要留给 u-boot 运行时展开
			fastboot='mmc dev 0; sysboot mmc 0:2 ${scriptaddr} /boot/extlinux/extlinux.conf'
			fastboot="${fastboot}; run distro_bootcmd"
			sed -i "s|^CONFIG_BOOTCOMMAND=.*|CONFIG_BOOTCOMMAND=\"${fastboot}\"|" .config
			info "u-boot 快速启动：关 PCIe/UFS/USB，bootdelay=0，直接 sysboot extlinux"
		fi
		# 调试串口换到 UART2/4 时，u-boot 的 console 索引也跟着换
		# （sunxi 的 CONFIG_CONS_INDEX 是 1-based：uart0=1, uart2=3, uart4=5）
		case "${A733_DEBUG_UART:-}" in
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
	# 优先用 vendor/a733 里的官方 boot0（从 Radxa u-boot-aw2501 deb 提取的成品）：
	# 我们拿 device/bin 里的 template + update_boot0/update_chip 转出来的 boot0，
	# 和官方成品差 9 字节（偏移 242..246），BL31 会在 bl31_platform_setup 里
	# 报 "hardware check error1" 直接 PANIC。boot0 是闭源二进制，直接沿用官方成品。
	local src dst dev
	local vendor_boot0="${BSP_ROOT}/vendor/a733/boot0_sdcard.bin"
	if [[ -f "${vendor_boot0}" ]]; then
		info "使用官方 boot0（vendor/a733/boot0_sdcard.bin，已含 A7Z sys_config）"
		cp -f "${vendor_boot0}" boot0_sdcard.bin
		[[ -f "${BSP_ROOT}/vendor/a733/boot0_ufs.bin" ]] && \
			cp -f "${BSP_ROOT}/vendor/a733/boot0_ufs.bin" boot0_ufs.bin
	else
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
	fi

	# boot_package.fex：u-boot + monitor（BL31）+ scp（ARISC），
	# 三个 item 缺一不可：BL31 起来后会等 SCP，缺了会在
	# "hardware check error1" 处 PANIC（这个坑踩过）。
	# scp 来自 Radxa 官方 u-boot-aw2501 deb 里的 boot_package.fex（vendor/a733/scp-a733.bin）。
	# 和官方镜像保持完全一致：直接用 Radxa u-boot-aw2501 deb 里的
	# boot_package.fex（官方 u-boot + BL31 + SCP，TOC/偏移都是官方调好的）。
	# 只有拿不到官方包时才自己用 dragonsecboot 打（下面那段）。
	local vendor_pkg="${BSP_ROOT}/vendor/a733/boot_package.fex"
	# A733_UBOOT_FAST=y 时 u-boot 里带了快速启动配置（关 PCIe/UFS/USB、
	# bootdelay=0、直连 extlinux），必须用我们编的 u-boot 重打包；
	# boot0 仍然用官方成品，BL31/SCP 也用官方二进制，只有 u-boot 这一项是新的。
	if [[ -f "${vendor_pkg}" && "${A733_UBOOT_FAST:-y}" != "y" ]]; then
		info "使用官方 boot_package.fex（vendor/a733/，与官方镜像一致）"
		cp -f "${vendor_pkg}" boot_package.fex
		cp -f boot_package.fex "${A733_OUT}/uboot/boot_package.fex"
		info "boot0 / boot_package.fex 就绪（官方成品，未做任何改动）"
		return 0
	fi

	cfg="boot_package.cfg"
	cp -f "${u}/u-boot-sun60iw2p1.bin" . 2>/dev/null || cp -f "${u}/u-boot.bin" u-boot-sun60iw2p1.bin
	cp -f "${d}/bin/bl31.bin" bl31-a733.bin
	{
		echo "[package]"
		echo "item=u-boot, u-boot-sun60iw2p1.bin"
		echo "item=monitor, bl31-a733.bin"
	} > "${cfg}"
	local scp
	for scp in "${BSP_ROOT}/vendor/a733/scp-a733.bin" "${d}"/bin/scp*.bin "${A733_OUT}"/scp.bin; do
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

	# 1.5) 应用内核补丁（幂等）。补丁全部打在 BSP 驱动上（bsp/ 是符号链接，
	#      不在内核 git 仓库里，所以必须用补丁文件固化，保证全新构建可复现）。
	#      判断顺序：先试 -R（已应用）→ 再试正向（未应用）→ 都不行则报错。
	a733_patch_already() {
		# 按内容判断补丁是否已在树里：取补丁里第一条新增文本（+ 开头、非 +++）
		# 作为标记，能在源码里 grep 到就算已应用。比 patch -R --dry-run 稳，
		# 也不会因为本地调试留下的额外改动而误判。
		local patch_file="$1" tree="$2" marker
		marker=$(awk '/^\+\+\+/{next} /^\+[^+]/{sub(/^\+/, ""); print; exit}' "${patch_file}")
		[[ -n "${marker}" ]] || return 1
		grep -rqF -- "${marker}" "${tree}/drivers" 2>/dev/null
	}
	a733_apply_kernel_patches() {
		local pdir="${BSP_ROOT}/vendor/a733/patches/kernel" p
		[[ -d "${pdir}" ]] || return 0
		for p in "${pdir}"/*.patch; do
			[[ -f "${p}" ]] || continue
			if a733_patch_already "${p}" "${b}"; then
				info "内核补丁已应用：$(basename "${p}")"
				continue
			fi
			if patch -p1 --dry-run -s -f -d "${b}" < "${p}" >/dev/null 2>&1; then
				patch -p1 -s -d "${b}" < "${p}" || \
					die "应用内核补丁失败：$(basename "${p}")"
				info "内核补丁已应用：$(basename "${p}")"
				continue
			fi
			# 反向再试一次（树是已打状态但标记没匹配上，例如标记行被改过）
			if patch -p1 -R --dry-run -s -f -d "${b}" < "${p}" >/dev/null 2>&1; then
				info "内核补丁已应用：$(basename "${p}")"
				continue
			fi
			die "内核补丁无法应用（源码状态不符）：$(basename "${p}")"
		done
	}
	a733_apply_kernel_patches

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
		# 两个脚都保留给 uart4：PJ25 若让出去做 PA MUTE，串口就没有 RX，
		# 只能看日志、无法登录（实测踩过）。功放 MUTE 用内部下拉保守处理
		# （ET/EU 版实测播放期间 TWI7 零报错）。
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
		drive-strength = <10>;
		/* HAT 原理图：40-pin pin16/18 = IO_23/IO_24 = PAM8406 MODE/MUTE，
		 * 与 uart4 的 PJ24/PJ25 复用。
		 * 实测（EV）去掉下拉后，播放期间 TWI7 出现大量
		 *   Bus error / Arbitration lost / xfer failed(0x18)
		 * 说明 MUTE 悬空时功放状态抖动会干扰总线/供电；加下拉（保持未静音）
		 * 时总线干净（ET/EU 那两版播放期间 twi 报错为 0）。
		 * 代价：该脚作 UART RX 收不到数据，需要输入请用 SSH。 */
		bias-pull-down;
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
	# A733 的 NPU 是 VIP9000（驱动里 sun60iw2 对应 vip2）；两个驱动都 match
	# "allwinner,npu"，galcore 是另一套（源码 28MB），二选一，别同时开。
	if [[ "${A733_WITH_NPU}" == "y" ]]; then
		cat >> "${k}/arch/arm64/configs/microduck.config" <<EOF

# ---- NPU（VIP9000 / vip2）----
CONFIG_AW_NNA_VIP=y
CONFIG_NNA_VIP2=y
# CONFIG_NNA_VIP1 is not set
# CONFIG_AW_NNA_GALCORE is not set
# VIP2 的 debugfs 代码依赖 DEBUG_FS；NPU_SET_CLK_VOL 打开时钟/电压节点
CONFIG_DEBUG_FS=y
CONFIG_NPU_SET_CLK_VOL=y
EOF
	fi
	# BSP 的 Kconfig 用 $(BSP_TOP)platform/Kconfig（结尾斜杠），
	# nand/codec 的 Makefile 还依赖 LICHEE_KERN_DIR 和 PWD（codec 用 $(PWD) 拼绝对路径）。
	export BSP_TOP="${k}/bsp/"
	export LICHEE_KERN_DIR="${k}"
	# cedar-ve/platforms/*.c 用 `"cedar_ve.h"`，Kbuild 只加了 platforms 目录
	export KCFLAGS="-I${b}/drivers/ve/cedar-ve -I${b}/drivers/sound/platform -I${b}/drivers/sound/adapter -I${b}/drivers/sound/misc -I${b}/drivers/sound/pa -I${b}/drivers/sound/codecs"
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
		ROOTFS_TINY=y \
		ROOTFS_INIT="${A733_ROOTFS_INIT:-systemd}" \
		INSTALL_AP6212_FIRMWARE=n \
		ROOTFS_STRIP=y \
		cmd_rootfs_micro "$@" || return

	# NPU 用户态：VIPLite 库 + vpm_run + LeNet 冒烟样例
	# （参考 jackhe183/radxa-dev：A733 是 VeriSilicon VIPLite，节点 /dev/vipcore）
	if [[ "${A733_WITH_NPU}" == "y" && "${A733_NPU_RUNTIME:-y}" == "y" ]]; then
		local stage="${SOURCES_DIR}/a733/npu-runtime"
		info "安装 NPU runtime（VIPLite + vpm_run）"
		if A733_CROSS_COMPILE="${A733_CROSS_COMPILE}" \
			bash "${BSP_ROOT}/vendor/a733/npu/fetch-runtime.sh" --dest "${stage}" >/dev/null 2>&1; then
			run_root mkdir -p "${OUT_DIR}/rootfs/usr/lib/viplite" \
				"${OUT_DIR}/rootfs/usr/bin" "${OUT_DIR}/rootfs/usr/share/npu"
			run_root cp -f "${stage}/stage/lib/"*.so "${OUT_DIR}/rootfs/usr/lib/viplite/"
			run_root cp -f "${stage}/stage/bin/vpm_run" "${OUT_DIR}/rootfs/usr/bin/vpm_run"
			run_root cp -f "${stage}/stage/share/"* "${OUT_DIR}/rootfs/usr/share/npu/" 2>/dev/null || true
			run_root chmod 755 "${OUT_DIR}/rootfs/usr/bin/vpm_run" "${OUT_DIR}/rootfs/usr/sbin/microduck-npu" 2>/dev/null || true
			run_root strip --strip-unneeded "${OUT_DIR}/rootfs/usr/bin/vpm_run" 2>/dev/null || true
			info "NPU runtime: $(run_root du -sh "${OUT_DIR}/rootfs/usr/lib/viplite" | cut -f1) + vpm_run $(run_root du -sh "${OUT_DIR}/rootfs/usr/share/npu" | cut -f1) 样例"
		else
			warn "NPU runtime 拉取/编译失败：镜像里只有内核驱动（/dev/vipcore），没有 vpm_run"
		fi
	fi
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
		export KCFLAGS="-I${b}/drivers/ve/cedar-ve -I${b}/drivers/sound/platform -I${b}/drivers/sound/adapter -I${b}/drivers/sound/misc -I${b}/drivers/sound/pa -I${b}/drivers/sound/codecs"
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

	# 只留和这块板子相关的模块：QCOM/Renesas/Rockchip/MediaTek/Tegra/Ath/Marvell/
	# Broadcom 等其它平台的驱动对 A733 没用，937 个 .ko 里能砍掉十几 MB。
	if [[ "${MICRODUCK_MIN_MODULES:-y}" == "y" ]]; then
		local before after
		before="$(run_root du -sk "${rootfs}/lib/modules" 2>/dev/null | cut -f1)"
		run_root find "${rootfs}/lib/modules" -name '*.ko*' -print0 2>/dev/null |
			while IFS= read -r -d '' ko; do
				case "${ko}" in
				*/qcom/*|*/renesas/*|*/rockchip/*|*/mediatek/*|*/tegra/*|*/ath/*/|*/ath[0-9]*)
					run_root rm -f "${ko}" ;;
				*/marvell/*|*/brcm/*|*/broadcom/*|*/samsung/*|*/fsl/*|*/imx/*|*/wcn/*|*/ti/*|*/hisilicon/*|*/amlogic/*|*/nvidia/*|*/intel/*|*/amd/*|*/xilinx/*)
					run_root rm -f "${ko}" ;;
				esac
			done
		run_root depmod -b "${rootfs}" -a "$(make -s -C "${k}" ARCH=arm64 \
			CROSS_COMPILE="${A733_CROSS_COMPILE}" kernelrelease 2>/dev/null | tr -d '[:space:]')" \
			>/dev/null 2>&1 || warn "裁剪后 depmod 失败"
		after="$(run_root du -sk "${rootfs}/lib/modules" 2>/dev/null | cut -f1)"
		info "模块裁剪: $((before / 1024)) MB -> $((after / 1024)) MB（$(run_root find "${rootfs}/lib/modules" -name '*.ko*' | wc -l) 个）"
	fi
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
	if [[ "${A733_WITH_NPU:-n}" == "y" ]]; then
		check "NPU 节点 npu@3600000" 'npu@3600000'
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
	# 布局（单位：512B 扇区）
	#   0..16MiB   boot0@128KiB、boot0_ufs@2064、boot_package@24576(12MiB)
	#   16MiB      Image（u-boot 用 mmc read 裸读，绕开分区表解析）
	#   55MiB      dtb（同样裸读）
	#   64MiB      p1 config FAT 16MiB
	#   80MiB      p2 rootfs ext4 到末尾
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
	# 这颗内核的串口是 Allwinner BSP 驱动，注册的是 /dev/ttyAS*（不是 ttyS*）；
	# 写 ttyS0 会出现 "unable to open an initial console"。earlycon 仍然用
	# uart8250 + UART0 基址，保证 console 驱动 probe 之前也能看到 log。
	# loglevel=4：只保留 warning 以上。115200 下日志本身要占掉几百毫秒，
	# 调试时临时改成 7/8 即可。
	# 调试口：默认 UART0；A733_DEBUG_UART=uart4/uart2 时跟着换。
	# 注意内核串口是 BSP 的 uart-v100 驱动，注册名是 ttyAS*（不是 ttyS*），
	# 写 ttyS4 会 "unable to open an initial console"。
	local debug_console="ttyAS0,115200"
	local earlycon_addr="0x02500000"
	case "${A733_DEBUG_UART:-none}" in
	uart4) debug_console="ttyAS4,115200"; earlycon_addr="0x02504000" ;;
	uart2) debug_console="ttyAS2,115200"; earlycon_addr="0x02502000" ;;
	esac
	[[ -n "${A733_CONSOLE:-}" ]] && debug_console="${A733_CONSOLE}"
	# rootfstype=ext4：显式指定文件系统类型。不加的话内核会依次尝试
	# ext2/ext3/ext4，ext2 对带 extents/64bit/flex_bg 的 rootfs 会报
	# "unsupported optional features (2c0)"，把真正的 ext4 报错盖住。
	bootargs="console=${debug_console} root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait cma=128M loglevel=6 net.ifnames=0 biosdevname=0"

	# 1) 内核/设备树/启动脚本放进 rootfs 的 /boot（官方镜像就是这样，
	#    u-boot 的 distro_bootcmd 扫到 ext4 分区根上的 /boot.scr 再 source 它）
	# Radxa 官方 USB 驱动包（vendor/a733/aic8800-usb）：
	#   aic_load_fw   —— 8d80（Boot ROM）阶段下载并启动固件
	#   aic8800_fdrv  —— 8d81（运行态）建 wlan0
	# BSP 自带的 aic8800_bsp/aic8800_fdrv 走不通（固件启动后 ~2.5s 抛异常），
	# 且 fdrv 模块名冲突，所以配置里已关掉；这里单独编译这两个模块并装进
	# rootfs 的 /lib/modules/<rel>/extra。两个模块有符号依赖（get_fw_path 等），
	# fdrv 必须用 load_fw 的 Module.symvers 编译。
	a733_build_aic8800_usb() {
		local k="${A733_KERNEL_DIR}" src="${BSP_ROOT}/vendor/a733/aic8800-usb"
		local work="${A733_OUT}/aic8800-usb" rel dst
		[[ -d "${src}" ]] || return 0
		[[ -f "${k}/arch/arm64/boot/Image" ]] || { warn "内核未构建，跳过 Radxa WiFi 驱动"; return 0; }
		rm -rf "${work}"
		mkdir -p "${work}"
		cp -a "${src}/." "${work}/"
		make -C "${k}" M="${work}/aic_load_fw" ARCH=arm64 \
			CROSS_COMPILE="${A733_CROSS_COMPILE}" \
			CONFIG_PLATFORM_UBUNTU=y CONFIG_AIC_INTF_USB=y modules \
			> "${A733_OUT}/aic_load_fw.build.log" 2>&1 || \
			die "编译 aic_load_fw 失败（见 out/a733/aic_load_fw.build.log）"
		make -C "${k}" M="${work}/aic8800_fdrv" ARCH=arm64 \
			CROSS_COMPILE="${A733_CROSS_COMPILE}" \
			CONFIG_PLATFORM_UBUNTU=y CONFIG_AIC_INTF_USB=y \
			KBUILD_EXTRA_SYMBOLS="${work}/aic_load_fw/Module.symvers" modules \
			> "${A733_OUT}/aic8800_fdrv.build.log" 2>&1 || \
			die "编译 aic8800_fdrv 失败（见 out/a733/aic8800_fdrv.build.log）"
		rel=$(cat "${k}/include/config/kernel.release")
		dst="${rootdir}/lib/modules/${rel}/extra"
		run_root mkdir -p "${dst}"
		run_root cp -f "${work}/aic_load_fw/aic_load_fw.ko" "${dst}/"
		run_root cp -f "${work}/aic8800_fdrv/aic8800_fdrv.ko" "${dst}/"
		# 蓝牙：aic_btusb（BlueZ 模式，接 8d81 的 BT 接口 e0/01/01）
		if [[ -d "${work}/aic_btusb" ]]; then
			make -C "${k}" M="${work}/aic_btusb" ARCH=arm64 \
				CROSS_COMPILE="${A733_CROSS_COMPILE}" \
				CONFIG_PLATFORM_UBUNTU=y modules \
				> "${A733_OUT}/aic_btusb.build.log" 2>&1 || \
				die "编译 aic_btusb 失败（见 out/a733/aic_btusb.build.log）"
			run_root cp -f "${work}/aic_btusb/aic_btusb.ko" "${dst}/"
		fi
		depmod -b "${rootdir}" -a "${rel}" >/dev/null 2>&1 || true
		info "安装 Radxa WiFi/BT 驱动: aic_load_fw + aic8800_fdrv + aic_btusb (${rel}/extra)"
	}
	a733_build_aic8800_usb

	# 精简 rootfs 里没有把 busybox 的 applet 建成独立命令，导致
	# udhcpc / ping / ps / killall 都 "command not found"。
	# 这里补软链接（只在该命令确实不存在时创建）。
	a733_busybox_applets() {
		local bb=""
		for c in /bin/busybox /usr/bin/busybox /sbin/busybox /usr/sbin/busybox; do
			[[ -x "${rootdir}${c}" ]] && { bb="${c}"; break; }
		done
		[[ -n "${bb}" ]] || return 0
		local dst link
		for dst in /usr/sbin/udhcpc /usr/sbin/udhcpc6 /bin/ping /bin/ping6 \
			   /bin/ps /usr/bin/killall /bin/killall \
			   /usr/bin/hexdump /bin/hexdump /usr/bin/od /bin/od /usr/bin/free; do
			link="${rootdir}${dst}"
			[[ -e "${link}" ]] && continue
			run_root mkdir -p "$(dirname "${link}")"
			run_root ln -sf "${bb}" "${link}"
		done
		info "补齐 busybox applet: udhcpc/ping/ps/killall"
	}
	a733_busybox_applets

	# WiFi/BT（aic8800）需要 /lib/firmware/aic8800dc 与 aic8800d80 下的固件，
	# 厂商 BSP 不带这些 bin，这里从 vendor/a733/firmware 铺进 rootfs。
	a733_install_firmware() {
		local fw="${BSP_ROOT}/vendor/a733/firmware"
		[[ -d "${fw}" ]] || return 0
		run_root mkdir -p "${rootdir}/lib/firmware"
		run_root cp -a "${fw}/." "${rootdir}/lib/firmware/"
		# aic8800_fw_alias_lowercase: 仓库目录名是 Radxa 驱动要求的大写
		# (aic8800D80/aic8800DC)，但 BSP 那版驱动用小写；ext4 大小写敏感，
		# 这里在镜像里再生成一份小写别名，两代驱动都能找到固件。
		a733_fw_alias_lowercase() {
			local base="${rootdir}/lib/firmware" up low
			for up in aic8800D80 aic8800DC; do
				low=$(echo "${up}" | tr 'A-Z' 'a-z')
				[[ -d "${base}/${up}" ]] || continue
				[[ -d "${base}/${low}" ]] && continue
				run_root cp -a "${base}/${up}" "${base}/${low}"
			done
		}
		a733_fw_alias_lowercase
		info "安装 aic8800 固件: $(run_root find "${rootdir}/lib/firmware" -type f | wc -l) 个文件"
	}
	a733_install_firmware

	info "安装内核与启动脚本到 rootfs /boot"
	run_root mkdir -p "${rootdir}/boot/extlinux" "${rootdir}/etc/kernel" "${rootdir}/config"
	run_root cp -f "${kernel}" "${rootdir}/boot/Image"
	run_root cp -f "${dtb}" "${rootdir}/boot/${A733_DTS_NAME}.dtb"

	sed -e "s|@BOOTARGS@|${bootargs}|" \
		-e "s|@DTB@|${A733_DTS_NAME}.dtb|" \
		"${BSP_ROOT}/vendor/a733/boot.cmd" > "${A733_OUT}/boot.cmd"
	"${mkimage_bin}" -C none -A arm64 -T script -d "${A733_OUT}/boot.cmd" \
		"${rootdir}/boot/boot.scr" >/dev/null || die "生成 boot.scr 失败"

	# extlinux.conf：u-boot 的 pxe/extlinux 解析器在没有 "menu title" 时不会画菜单，
	# 只按 default + timeout 直接启动；timeout 0 = 立刻启动，不需要按键选择。
	# 注意：本 u-boot 的 bootcmd 是 distro_bootcmd，先扫 USB 再扫 mmc，
	# 所以这里必须是"无菜单 + 0 延时"，否则每次上电都要等交互。
	cat > "${A733_OUT}/extlinux.conf" <<EOF
default l0
timeout 0
label l0
	linux /boot/Image
	fdt /boot/${A733_DTS_NAME}.dtb
	append ${bootargs}
EOF
	run_root cp -f "${A733_OUT}/extlinux.conf" "${rootdir}/boot/extlinux/extlinux.conf"
	printf '%s\n' "${bootargs}" > "${A733_OUT}/cmdline"
	run_root cp -f "${A733_OUT}/cmdline" "${rootdir}/etc/kernel/cmdline"

	# 镜像身份标记：刷完机 `cat /etc/microduck/build-info` 就能确认跑的是哪一版。
	# 排查"刷错镜像/旧镜像"时非常重要——内核版本号相同但 DTS/配置不同的情况很常见。
	{
		printf 'image      : %s\n' "${A733_IMAGE_NAME}"
		printf 'built_utc  : %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
		printf 'git        : %s\n' "$(git -C "${BSP_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
		printf 'git_subject: %s\n' "$(git -C "${BSP_ROOT}" log -1 --pretty=%s 2>/dev/null || echo unknown)"
		printf 'kernel     : %s\n' "$(cat "${A733_KERNEL_DIR}/include/config/kernel.release" 2>/dev/null)"
		printf 'dtb        : %s\n' "${A733_DTS_NAME}.dtb"
		printf 'debug_uart : %s\n' "${A733_DEBUG_UART:-none}"
		printf 'console    : %s\n' "${bootargs}"
	} > "${A733_OUT}/build-info"
	run_root mkdir -p "${rootdir}/etc/microduck"
	run_root cp -f "${A733_OUT}/build-info" "${rootdir}/etc/microduck/build-info"

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
	# 尺寸 = 内容 + inode 表开销 + 一张很小的余量；以前是 +64MB 再 +10%，
	# 在 300MB 级 rootfs 上会白占 ~100MB（mkfs 出来一半是空的）。
	fs_mb=$(( fs_mb + file_count * 4 / 1024 + 24 ))
	fs_mb=$(( fs_mb * 104 / 100 ))
	info "rootfs.ext4: ${fs_mb} MiB，UUID=${rootfs_uuid}"
	run_root rm -f "${OUT_DIR}/rootfs.ext4"
	# -m 0：不留 5% 的 root 保留块（A7Z 的 rootfs 不会满到需要它）
	run_root mkfs.ext4 -m 0 -d "${rootdir}" -L rootfs -U "${rootfs_uuid}" \
		"${OUT_DIR}/rootfs.ext4" "${fs_mb}M" >/dev/null || die "mkfs.ext4 失败"
	# 镜像大小按"实际生成的 rootfs.ext4"算，再留 8 MiB 给磁盘末尾的 GPT 备份
	# 头/分区表（34 个扇区）。少了这段余量，p2 会比文件系统小几块，内核报
	# "EXT4-fs: bad geometry: block count ... exceeds size of device"，rootfs 挂不上。
	local fs_bytes
	fs_bytes=$(run_root stat -c%s "${OUT_DIR}/rootfs.ext4")
	img_size=$(( root_start * 512 + fs_bytes + 8 * 1048576 ))
	img_size=$(( (img_size + 1048576 - 1) / 1048576 * 1048576 ))

	# mkfs -d 的尺寸是估算的，实际会空出几十 MB。用 resize2fs -M 缩到最小，
	# 再补 16 MiB 余量，镜像长度按真实文件大小算，省掉这块空白。
	run_root e2fsck -fy "${OUT_DIR}/rootfs.ext4" >/dev/null 2>&1 || true
	if run_root resize2fs -M "${OUT_DIR}/rootfs.ext4" >/dev/null 2>&1; then
		local fs_blocks
		fs_blocks="$(run_root dumpe2fs -h "${OUT_DIR}/rootfs.ext4" 2>/dev/null |
			awk -F: '/Block count/{gsub(/[ \t]/,"",$2); print $2}')"
		if [[ -n "${fs_blocks}" ]]; then
			run_root resize2fs "${OUT_DIR}/rootfs.ext4" $(( fs_blocks + 4096 )) \
				>/dev/null 2>&1 || true
		fi
		info "rootfs.ext4 收缩到 $(run_root du -sm "${OUT_DIR}/rootfs.ext4" | cut -f1) MiB（+16 MiB 余量）"
	fi
	fs_bytes="$(run_root stat -c%s "${OUT_DIR}/rootfs.ext4")"
	# 关键：镜像必须比"root_start + rootfs 大小"再多留一段。
	# GPT 的备份头 + 备份表项放在磁盘最后 34 个扇区，sfdisk 会把 p2 的结束位置
	# 卡在 last_usable_lba 上；如果这里不留余量，p2 就会比 rootfs 小 33 个扇区，
	# 内核报 "EXT4-fs (mmcblk0p2): bad geometry: block count ... exceeds size of
	# device" 而挂不上 rootfs。留 8 MiB 余量 + 1 MiB 对齐。
	img_size=$(( root_start * 512 + fs_bytes + 8 * 1048576 ))
	img_size=$(( (img_size + 1048576 - 1) / 1048576 * 1048576 ))

	# 3) config 分区（16 MiB FAT）
	tmp_cfg="${A733_OUT}/config.fat"
	run_root rm -f "${tmp_cfg}"
	run_root mkfs.vfat -F 16 -n config -i "${cfg_id}" -C "${tmp_cfg}" \
		"$(( cfg_size / 2 ))" >/dev/null || die "mkfs.vfat 失败"

	# 4) 组镜像
	info "生成镜像: ${img}（GPT 56 项；config@16MiB、rootfs@32MiB）"
	run_root mkdir -p "${A733_OUT}"
	run_root rm -f "${img}"
	run_root truncate -s "${img_size}" "${img}"
	run_root dd if="${boot0}" of="${img}" bs=512 seek=256 conv=notrunc status=none
	if [[ -f "${boot0ufs}" ]]; then
		# setup.sh 同时写一份 UFS 用的 boot0（seek=2064），照做
		run_root dd if="${boot0ufs}" of="${img}" bs=512 seek=2064 conv=notrunc status=none
	fi
	run_root dd if="${pkg}" of="${img}" bs=512 seek=24576 conv=notrunc status=none
	# 不用 conv=sparse：分区表/裸区必须是实打实的字节
	run_root dd if="${tmp_cfg}" of="${img}" bs=512 seek="${cfg_start}" conv=notrunc status=none
	run_root dd if="${OUT_DIR}/rootfs.ext4" of="${img}" bs=512 seek="${root_start}" \
		conv=notrunc status=none

	# 5) 分区表：MBR（不是 GPT）
	# 这颗 u-boot（2018.07 + sunxi）的 GPT 解析在这块 SD 卡上不可靠：
	#   - Kconfig 里 EFI_PARTITION_ENTRIES_NUMBERS 默认 56，sfdisk 写 128 项，
	#     缓冲区/CRC 长度对不上 → 每次都 "Entry Array CRC is wrong"；
	#   - 失败后它回退去读「设备最后一块」的备份 GPT（30 GB 卡末尾），必失败。
	# 而 MBR 解析是单块读，稳定；内核也认。p2 打 bootable 标志，
	# u-boot 的 `part list mmc 0 -bootable` 才能列出 2 号分区。
	pt="$(mktemp)"
	{
		echo "label: gpt"
		echo "unit: sectors"
		echo
		echo "start=${cfg_start}, size=${cfg_size}, name=\"config\""
		echo "start=${root_start}, name=\"rootfs\", attrs=\"LegacyBIOSBootable\""
	} > "${pt}"
	run_root sfdisk --no-tell-kernel --force --quiet "${img}" < "${pt}" || die "写 GPT 失败"
	rm -f "${pt}"

	# 官方 u-boot 的 CONFIG_EFI_PARTITION_ENTRIES_NUMBERS 是 56（ARCH_SUNXI 默认），
	# 而 sfdisk 写 128 项：u-boot 只读 56 项却按 128 项算 CRC，尾巴是未初始化内存，
	# 于是每次都报 "Entry Array CRC is wrong"。这里把 GPT 头改成 56 项并重算
	# 表项 CRC / header CRC（主+备），官方 u-boot 就能稳定解析。
	cat > "${A733_OUT}/gpt56.py" <<'PYEOF'
import struct, sys, zlib
path = sys.argv[1]
NE = 56
f = open(path, 'r+b')
def rd(lba, n):
    f.seek(lba * 512)
    return f.read(n)
def patch(off):
    h = bytearray(rd(off, 92))
    assert h[:8] == b'EFI PART', "not GPT"
    ent_lba = struct.unpack_from('<Q', h, 72)[0]
    ents = rd(ent_lba, NE * 128)
    ecrc = zlib.crc32(ents) & 0xffffffff
    struct.pack_into('<I', h, 80, NE)
    struct.pack_into('<I', h, 88, ecrc)
    struct.pack_into('<I', h, 16, 0)
    struct.pack_into('<I', h, 16, zlib.crc32(bytes(h)) & 0xffffffff)
    f.seek(off * 512)
    f.write(h)
    return ent_lba, ecrc
p_lba, p_crc = patch(1)
alt = struct.unpack_from('<Q', rd(1, 92), 32)[0]
b_lba, b_crc = patch(alt)
f.close()
print(f"GPT->56 entries: primary ent@{p_lba} crc={p_crc:#x}, backup ent@{b_lba} crc={b_crc:#x}")
PYEOF
	run_root python3 "${A733_OUT}/gpt56.py" "${img}" | sed 's/^/  /'

	info "镜像: ${img}"
	ls -lh "${img}"
	sfdisk -d "${img}" 2>/dev/null | sed 's/^/  /'
	info "boot0@128KiB、boot0_ufs@2064 扇区、boot_package.fex@12MiB"
	info "p1 config(FAT)@16MiB、p2 rootfs(ext4)@32MiB（GPT，p2 bootable）"
	info "官方 u-boot 走 extlinux（/boot/extlinux/extlinux.conf），内核 root=/dev/mmcblk0p2"
}


