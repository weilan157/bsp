#!/bin/bash
# Ky X1 SD / eMMC 打包与安装（参考 orangepi-build write_uboot_platform）

# dd bootloader 到 SD/镜像用户区（扇区单位，bs=512）
# bootinfo_sd @0, FSBL @256, env @768, u-boot-opensbi.itb @1664
write_uboot_to_device() {
	local src_dir="$1" dest="$2"
	[[ -f "${src_dir}/bootinfo_sd.bin" ]] || die "缺少 bootinfo_sd.bin"
	[[ -f "${src_dir}/FSBL.bin" ]] || die "缺少 FSBL.bin"
	[[ -f "${src_dir}/u-boot-env-default.bin" ]] || die "缺少 u-boot-env-default.bin"
	[[ -f "${src_dir}/u-boot-opensbi.itb" ]] || die "缺少 u-boot-opensbi.itb"

	info "写入 U-Boot 用户区 -> ${dest}"
	run_root dd if="${src_dir}/bootinfo_sd.bin" of="${dest}" seek=0 conv=notrunc status=none
	run_root dd if="${src_dir}/FSBL.bin" of="${dest}" seek=256 conv=notrunc status=none
	run_root dd if="${src_dir}/u-boot-env-default.bin" of="${dest}" seek=768 conv=notrunc status=none
	run_root dd if="${src_dir}/u-boot-opensbi.itb" of="${dest}" seek=1664 conv=notrunc status=none
	sync
}

# eMMC：先写 boot0（bootinfo_emmc + FSBL），再写用户区（与 SD 相同扇区布局）
# 对齐 orangepi-build ky.conf write_uboot_platform
write_uboot_to_emmc() {
	local src_dir="$1" mmc="$2"
	local boot0="${mmc}boot0"
	local sys_boot0

	[[ -b "${mmc}" ]] || die "不是块设备: ${mmc}"
	[[ -b "${boot0}" ]] || die "缺少 ${boot0}（该设备不像带 boot 分区的 eMMC）"
	[[ -f "${src_dir}/bootinfo_emmc.bin" ]] || die "缺少 bootinfo_emmc.bin，请先 ./bsp uboot"
	[[ -f "${src_dir}/FSBL.bin" ]] || die "缺少 FSBL.bin"

	sys_boot0="/sys/block/$(basename "${mmc}")/$(basename "${boot0}")/force_ro"
	[[ -e "${sys_boot0}" ]] || die "缺少 ${sys_boot0}"

	info "写入 eMMC boot0 -> ${boot0}"
	run_root bash -c "echo 0 > '${sys_boot0}'"
	run_root dd if="${src_dir}/bootinfo_emmc.bin" of="${boot0}" status=none
	# 官方：seek=512 bs=1（字节偏移）
	run_root dd if="${src_dir}/FSBL.bin" of="${boot0}" seek=512 bs=1 conv=notrunc status=none
	sync
	run_root bash -c "echo 1 > '${sys_boot0}'"

	write_uboot_to_device "${src_dir}" "${mmc}"
}

emmc_resolve_parts() {
	local mmc="$1"
	if [[ -b "${mmc}p1" ]]; then
		EMMC_BOOT_PART="${mmc}p1"
		EMMC_ROOT_PART="${mmc}p2"
	elif [[ -b "${mmc}1" ]]; then
		EMMC_BOOT_PART="${mmc}1"
		EMMC_ROOT_PART="${mmc}2"
	else
		EMMC_BOOT_PART="${mmc}p1"
		EMMC_ROOT_PART="${mmc}p2"
	fi
}

emmc_wait_parts() {
	local i
	for i in $(seq 1 30); do
		emmc_resolve_parts "$1"
		[[ -b "${EMMC_BOOT_PART}" && -b "${EMMC_ROOT_PART}" ]] && return 0
		run_root partprobe "$1" 2>/dev/null || true
		sleep 0.3
	done
	die "分区节点未出现（期望 ${1}p1 / ${1}p2）"
}

partition_gpt_boot_root() {
	local dest="$1"
	local offset_mib="${SD_OFFSET_MIB}"
	local boot_mib="${SD_BOOT_MIB}"

	info "分区 ${dest}: GPT offset=${offset_mib}MiB boot=${boot_mib}MiB root=剩余"
	run_root sfdisk "${dest}" <<EOF
label: gpt
unit: sectors
first-lba: 34

1 : start=${offset_mib}MiB, size=${boot_mib}MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="bootfs"
2 : start=$((offset_mib + boot_mib))MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
EOF
	run_root partprobe "${dest}" 2>/dev/null || true
	sync
}

# 对齐 orangepi-build：镜像/设备上的 orangepiEnv.txt 必须带 rootdev=UUID=...
set_orangepi_env_rootdev() {
	local env_file="$1" root_uuid="$2"
	[[ -f "${env_file}" ]] || die "缺少 ${env_file}，无法写入 rootdev"
	[[ -n "${root_uuid}" ]] || die "rootfs UUID 为空"
	if grep -q '^rootdev=' "${env_file}"; then
		run_root sed -i "s|^rootdev=.*|rootdev=UUID=${root_uuid}|" "${env_file}"
	else
		run_root bash -c "echo 'rootdev=UUID=${root_uuid}' >> '${env_file}'"
	fi
	if grep -q '^rootfstype=' "${env_file}"; then
		run_root sed -i "s|^rootfstype=.*|rootfstype=ext4|" "${env_file}"
	else
		run_root bash -c "echo 'rootfstype=ext4' >> '${env_file}'"
	fi
	info "orangepiEnv rootdev=UUID=${root_uuid}"
}

flash_boot_root_parts() {
	local boot_dev="$1" root_dev="$2"
	local mnt

	[[ -f "${OUT_DIR}/boot.img" ]] || die "缺少 out/boot.img，请先 ./bsp bootimg"
	[[ -f "${OUT_DIR}/rootfs.ext4" ]] || die "缺少 out/rootfs.ext4，请先 ./bsp rootfs"

	info "写入 boot 分区 ${boot_dev}..."
	run_root dd if="${OUT_DIR}/boot.img" of="${boot_dev}" bs=1M status=progress conv=fsync
	sync

	info "写入 rootfs 分区 ${root_dev}..."
	run_root dd if="${OUT_DIR}/rootfs.ext4" of="${root_dev}" bs=1M status=progress conv=fsync
	run_root e2fsck -fy "${root_dev}" >/dev/null 2>&1 || true
	run_root resize2fs "${root_dev}" >/dev/null 2>&1 || true
	sync

	mnt="$(mktemp -d)"
	cleanup_flash_mnt() {
		run_root umount "${mnt}/boot" 2>/dev/null || true
		run_root umount "${mnt}" 2>/dev/null || true
		rmdir "${mnt}" 2>/dev/null || true
	}
	trap cleanup_flash_mnt EXIT

	run_root mount "${root_dev}" "${mnt}"
	mkdir -p "${mnt}/boot"
	run_root mount "${boot_dev}" "${mnt}/boot"

	local boot_uuid root_uuid
	boot_uuid="$(blkid -s UUID -o value "${boot_dev}")"
	root_uuid="$(blkid -s UUID -o value "${root_dev}")"
	[[ -n "${root_uuid}" ]] || die "无法读取 ${root_dev} 的 UUID"
	[[ -n "${boot_uuid}" ]] || die "无法读取 ${boot_dev} 的 UUID"
	info "写入 fstab: root=${root_uuid} boot=${boot_uuid}"
	run_root tee "${mnt}/etc/fstab" >/dev/null <<EOF
UUID=${root_uuid} / ext4 defaults,noatime 0 1
UUID=${boot_uuid} /boot vfat defaults,sync,utf8,flush 0 2
EOF
	# 禁止把占位符带进镜像
	if grep -qE 'BOOTFS|ROOTFS|mmcblk0p' "${mnt}/etc/fstab"; then
		die "fstab 仍含占位符/mmcblk0，请检查 pack 逻辑"
	fi
	set_orangepi_env_rootdev "${mnt}/boot/orangepiEnv.txt" "${root_uuid}"
	# 同步写入 rootfs.ext4 源树旁注：下次直接 dd 也应用本镜像内已改的 fstab
	info "fstab 与 orangepiEnv 已按 UUID 更新"
	sync
	cleanup_flash_mnt
	trap - EXIT
}

cmd_stage() {
	local fw_dir uboot_src
	fw_dir="${OUT_DIR}/firmware"
	mkdir -p "${fw_dir}"

	[[ -d "${UBOOT_DIR}" ]] || die "请先 ./bsp setup uboot && ./bsp uboot"
	have_uboot_artifacts || die "缺少 U-Boot 产物，请先 ./bsp uboot"

	uboot_src="${OUT_DIR}/uboot"
	if [[ ! -f "${uboot_src}/u-boot-opensbi.itb" ]]; then
		uboot_src="${UBOOT_DIR}"
	fi

	info "收集固件到 ${fw_dir}/"
	local f
	for f in bootinfo_sd.bin bootinfo_emmc.bin bootinfo_spinor.bin \
		FSBL.bin u-boot-env-default.bin u-boot-opensbi.itb; do
		[[ -f "${uboot_src}/${f}" ]] || continue
		install -m 644 "${uboot_src}/${f}" "${fw_dir}/${f}"
	done

	if [[ -f "${OUT_DIR}/boot.img" ]]; then
		install -m 644 "${OUT_DIR}/boot.img" "${fw_dir}/boot.img"
	else
		warn "缺少 out/boot.img，请先 ./bsp bootimg"
	fi
	if [[ -d "${OUT_DIR}/boot" ]]; then
		rm -rf "${fw_dir}/boot"
		cp -a "${OUT_DIR}/boot" "${fw_dir}/boot"
	fi

	if [[ -f "${OUT_DIR}/rootfs.ext4" ]]; then
		install -m 644 "${OUT_DIR}/rootfs.ext4" "${fw_dir}/rootfs.ext4"
	else
		warn "缺少 rootfs.ext4，请先 ./bsp rootfs"
	fi

	info "固件目录就绪:"
	ls -lh "${fw_dir}/"
}

cmd_pack() {
	local stage_only=0
	local arg
	for arg in "$@"; do
		case "${arg}" in
			--stage-only) stage_only=1 ;;
			--clean|--force) export BSP_FORCE=1 ;;
			--update) export BSP_UPDATE=1 ;;
			*) die "pack 未知选项: ${arg}" ;;
		esac
	done

	if [[ "${stage_only}" -eq 1 ]]; then
		cmd_stage
		return
	fi

	local sd_img
	sd_img="$(sd_image_path)"

	if ! bsp_want_force && have_pack_artifacts; then
		info "已有 SD 镜像，跳过打包（加 --clean 强制重做）"
		ls -lh "${sd_img}"
		return 0
	fi

	cmd_stage

	[[ -f "${OUT_DIR}/boot.img" ]] || die "缺少 out/boot.img"
	[[ -f "${OUT_DIR}/rootfs.ext4" ]] || die "缺少 out/rootfs.ext4"
	[[ -f "${OUT_DIR}/firmware/bootinfo_sd.bin" ]] || die "缺少 bootloader 产物"

	local offset_mib boot_mib root_mib total_mib root_bytes
	offset_mib="${SD_OFFSET_MIB}"
	boot_mib="${SD_BOOT_MIB}"
	root_bytes="$(stat -c%s "${OUT_DIR}/rootfs.ext4")"
	root_mib=$(( (root_bytes + 1024*1024 - 1) / (1024*1024) + SD_ROOTFS_EXTRA_MIB ))
	total_mib=$(( offset_mib + boot_mib + root_mib + 16 ))

	info "创建 SD 镜像 ${sd_img} (${total_mib}MiB: offset=${offset_mib} boot=${boot_mib} root≈${root_mib})"
	rm -f "${sd_img}"
	truncate -s "${total_mib}M" "${sd_img}"

	# 镜像文件：直接 sfdisk（不必 sudo）
	sfdisk "${sd_img}" <<EOF
label: gpt
unit: sectors
first-lba: 34

1 : start=${offset_mib}MiB, size=${boot_mib}MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="bootfs"
2 : start=$((offset_mib + boot_mib))MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
EOF

	write_uboot_to_device "${OUT_DIR}/firmware" "${sd_img}"

	local loop boot_dev root_dev
	loop="$(run_root losetup -f --show -P "${sd_img}")"
	boot_dev="${loop}p1"
	root_dev="${loop}p2"
	local i
	for i in $(seq 1 20); do
		[[ -b "${boot_dev}" && -b "${root_dev}" ]] && break
		sleep 0.2
	done
	[[ -b "${boot_dev}" ]] || die "未出现 ${boot_dev}"
	[[ -b "${root_dev}" ]] || die "未出现 ${root_dev}"

	flash_boot_root_parts "${boot_dev}" "${root_dev}"
	run_root losetup -d "${loop}" 2>/dev/null || true

	install_emmc_helper_script

	info "完成: ${sd_img}"
	info "烧录 SD: sudo dd if=${sd_img} of=/dev/sdX bs=4M status=progress conv=fsync"
	info "安装 eMMC: ./bsp emmc /dev/mmcblkX --yes  或板上 out/firmware/install-emmc.sh"
	ls -lh "${sd_img}"
}

install_emmc_helper_script() {
	local helper="${OUT_DIR}/install-emmc.sh"
	cat > "${helper}" <<'HELPER'
#!/bin/bash
# 在已启动的 Orange Pi R2S 上，把当前目录固件写入 eMMC
# 用法: sudo ./install-emmc.sh /dev/mmcblk1 [--yes]
# 同目录需有: bootinfo_emmc.bin FSBL.bin bootinfo_sd.bin
#   u-boot-env-default.bin u-boot-opensbi.itb boot.img rootfs.ext4
set -euo pipefail
MMC="${1:-}"
YES="${2:-}"
[[ -n "${MMC}" ]] || { echo "用法: $0 /dev/mmcblkX [--yes]"; exit 1; }
[[ -b "${MMC}" ]] || { echo "不是块设备: ${MMC}"; exit 1; }
BOOT0="${MMC}boot0"
[[ -b "${BOOT0}" ]] || { echo "缺少 ${BOOT0}"; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
for f in bootinfo_emmc.bin FSBL.bin bootinfo_sd.bin u-boot-env-default.bin u-boot-opensbi.itb boot.img rootfs.ext4; do
	[[ -f "${DIR}/${f}" ]] || { echo "缺少 ${DIR}/${f}"; exit 1; }
done
if [[ "${YES}" != "--yes" ]]; then
	echo "将清空并安装系统到 ${MMC}（含 boot0）"
	read -r -p "输入 YES 继续: " ans
	[[ "${ans}" == "YES" ]] || exit 1
fi
OFFSET_MIB="${OFFSET_MIB:-30}"
BOOT_MIB="${BOOT_MIB:-256}"
SYS_BOOT0="/sys/block/$(basename "${MMC}")/$(basename "${BOOT0}")/force_ro"
echo 0 > "${SYS_BOOT0}"
dd if="${DIR}/bootinfo_emmc.bin" of="${BOOT0}" status=none
dd if="${DIR}/FSBL.bin" of="${BOOT0}" seek=512 bs=1 conv=notrunc status=none
sync
echo 1 > "${SYS_BOOT0}"
sfdisk "${MMC}" <<EOF
label: gpt
unit: sectors
first-lba: 34

1 : start=${OFFSET_MIB}MiB, size=${BOOT_MIB}MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="bootfs"
2 : start=$((OFFSET_MIB + BOOT_MIB))MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
EOF
partprobe "${MMC}" || true
dd if="${DIR}/bootinfo_sd.bin" of="${MMC}" seek=0 conv=notrunc status=none
dd if="${DIR}/FSBL.bin" of="${MMC}" seek=256 conv=notrunc status=none
dd if="${DIR}/u-boot-env-default.bin" of="${MMC}" seek=768 conv=notrunc status=none
dd if="${DIR}/u-boot-opensbi.itb" of="${MMC}" seek=1664 conv=notrunc status=none
sync
BOOT_PART="${MMC}p1"; ROOT_PART="${MMC}p2"
[[ -b "${BOOT_PART}" ]] || BOOT_PART="${MMC}1"
[[ -b "${ROOT_PART}" ]] || ROOT_PART="${MMC}2"
dd if="${DIR}/boot.img" of="${BOOT_PART}" bs=1M status=progress conv=fsync
dd if="${DIR}/rootfs.ext4" of="${ROOT_PART}" bs=1M status=progress conv=fsync
e2fsck -fy "${ROOT_PART}" || true
resize2fs "${ROOT_PART}" || true
MNT="$(mktemp -d)"
mount "${ROOT_PART}" "${MNT}"
mkdir -p "${MNT}/boot"
mount "${BOOT_PART}" "${MNT}/boot"
BUUID="$(blkid -s UUID -o value "${BOOT_PART}")"
RUUID="$(blkid -s UUID -o value "${ROOT_PART}")"
[[ -n "${RUUID}" ]] || { echo "无法读取 rootfs UUID"; exit 1; }
[[ -n "${BUUID}" ]] || { echo "无法读取 boot UUID"; exit 1; }
cat > "${MNT}/etc/fstab" <<EOF
UUID=${RUUID} / ext4 defaults,noatime 0 1
UUID=${BUUID} /boot vfat defaults,sync,utf8,flush 0 2
EOF
grep -qE 'BOOTFS|ROOTFS|mmcblk0p' "${MNT}/etc/fstab" && { echo "fstab 仍含占位符"; exit 1; }
ENV="${MNT}/boot/orangepiEnv.txt"
[[ -f "${ENV}" ]] || { echo "缺少 ${ENV}"; exit 1; }
if grep -q '^rootdev=' "${ENV}"; then
	sed -i "s|^rootdev=.*|rootdev=UUID=${RUUID}|" "${ENV}"
else
	echo "rootdev=UUID=${RUUID}" >> "${ENV}"
fi
if grep -q '^rootfstype=' "${ENV}"; then
	sed -i "s|^rootfstype=.*|rootfstype=ext4|" "${ENV}"
else
	echo "rootfstype=ext4" >> "${ENV}"
fi
echo "orangepiEnv rootdev=UUID=${RUUID}"
echo "fstab root=${RUUID} boot=${BUUID}"
sync
umount "${MNT}/boot" || true
umount "${MNT}" || true
rmdir "${MNT}" || true
echo "eMMC 安装完成。拔掉 SD 后从 eMMC 启动。"
HELPER
	chmod +x "${helper}"
	local fw="${OUT_DIR}/firmware"
	if [[ -d "${fw}" ]]; then
		install -m 755 "${helper}" "${fw}/install-emmc.sh"
	fi
	info "已生成 eMMC 安装脚本: ${helper}"
}

# 用法: ./bsp emmc /dev/mmcblk1 [--yes] [--uboot-only]
cmd_emmc() {
	local mmc="" uboot_only=0 yes=0
	local arg
	for arg in "$@"; do
		case "${arg}" in
			--uboot-only) uboot_only=1 ;;
			--yes|-y) yes=1 ;;
			--clean|--force) export BSP_FORCE=1 ;;
			/dev/mmcblk[0-9]*) mmc="${arg}" ;;
			*)
				die "emmc 未知选项: ${arg}（用法: ./bsp emmc /dev/mmcblkX [--yes] [--uboot-only]）"
				;;
		esac
	done

	[[ -n "${mmc}" ]] || die "请指定 eMMC 设备，例如: ./bsp emmc /dev/mmcblk1 --yes"
	[[ "${mmc}" =~ ^/dev/mmcblk[0-9]+$ ]] || die "设备名无效（仅允许 /dev/mmcblkN）: ${mmc}"
	[[ -b "${mmc}" ]] || die "设备不存在: ${mmc}"
	[[ -b "${mmc}boot0" ]] || die "缺少 ${mmc}boot0，确认是 eMMC 且已插入"

	local root_src
	root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
	if [[ -n "${root_src}" && "${root_src}" == "${mmc}"* ]]; then
		die "拒绝：当前根文件系统在 ${mmc} 上（${root_src}）。请从 SD 启动后再装 eMMC。"
	fi

	if [[ "${yes}" -ne 1 ]]; then
		warn "即将写入 ${mmc}（含 ${mmc}boot0），原数据会丢失"
		read -r -p "输入 YES 继续: " ans
		[[ "${ans}" == "YES" ]] || die "已取消"
	fi

	cmd_stage
	[[ -f "${OUT_DIR}/firmware/bootinfo_emmc.bin" ]] || die "缺少 bootinfo_emmc.bin"

	if [[ "${uboot_only}" -eq 1 ]]; then
		write_uboot_to_emmc "${OUT_DIR}/firmware" "${mmc}"
		info "仅 bootloader 已写入 ${mmc}"
		return 0
	fi

	[[ -f "${OUT_DIR}/boot.img" ]] || die "缺少 out/boot.img"
	[[ -f "${OUT_DIR}/rootfs.ext4" ]] || die "缺少 out/rootfs.ext4"

	partition_gpt_boot_root "${mmc}"
	write_uboot_to_emmc "${OUT_DIR}/firmware" "${mmc}"
	emmc_wait_parts "${mmc}"
	flash_boot_root_parts "${EMMC_BOOT_PART}" "${EMMC_ROOT_PART}"
	install_emmc_helper_script

	info "eMMC 安装完成: ${mmc}"
	info "拔掉 SD 卡后上电，应从 eMMC 启动"
}

cmd_all() {
	local skip_rootfs="${SKIP_ROOTFS:-}"
	local skip_pack="${SKIP_PACK:-}"
	local arg
	for arg in "$@"; do
		case "${arg}" in
			--skip-rootfs) skip_rootfs=y ;;
			--skip-pack) skip_pack=y ;;
			--clean|--force) export BSP_FORCE=1 ;;
			--update) export BSP_UPDATE=1 ;;
			*) die "all 未知选项: ${arg}" ;;
		esac
	done

	if [[ "${skip_rootfs}" != "y" ]]; then
		if ! command -v debootstrap >/dev/null 2>&1; then
			warn "未安装 debootstrap，跳过 rootfs（可先 ./bsp env）"
			skip_rootfs=y
		fi
	fi

	info "全量编译 BOARD=${BOARD}（缓存：有则跳过；--clean 强制重编；--update 拉取源码）"
	cmd_setup_uboot_sources
	cmd_uboot
	cmd_setup_kernel_sources
	cmd_kernel
	cmd_bootimg

	if [[ "${skip_rootfs}" != "y" ]]; then
		cmd_rootfs
	fi

	if [[ "${skip_pack}" != "y" ]]; then
		cmd_pack || warn "pack 失败（可能缺少 rootfs）"
	fi

	info "全量编译完成。产物: out/ 与 sources/u-boot/"
}
