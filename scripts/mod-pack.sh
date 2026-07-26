#!/bin/bash
# 固件收集与 update.img 打包、afptool 下载

_PACK_DEFAULT_MIRRORS=(
	"https://cdn.jsdelivr.net/gh/vicharak-in/rockchip-linux-tools@master/linux/Linux_Pack_Firmware/rockdev"
	"https://ghproxy.net/https://raw.githubusercontent.com/vicharak-in/rockchip-linux-tools/master/linux/Linux_Pack_Firmware/rockdev"
	"https://raw.githubusercontent.com/vicharak-in/rockchip-linux-tools/master/linux/Linux_Pack_Firmware/rockdev"
)

pack_is_elf() {
	[[ -f "$1" ]] && [[ "$(od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \n')" == "7f454c46" ]]
}

pack_tools_ready() {
	local dest="${PACK_TOOLS_DIR:-${BSP_ROOT}/vendor/tools/pack-firmware}"
	[[ -x "${dest}/afptool" ]] && [[ -x "${dest}/rkImageMaker" ]] && \
		pack_is_elf "${dest}/afptool" && pack_is_elf "${dest}/rkImageMaker"
}

pack_mirror_list() {
	local -a m
	if [[ -n "${PACK_TOOLS_DOWNLOAD_MIRRORS:-}" ]]; then
		# shellcheck disable=SC2206
		m=(${PACK_TOOLS_DOWNLOAD_MIRRORS})
	elif [[ -n "${PACK_TOOLS_DOWNLOAD_BASE:-}" ]]; then
		m=("${PACK_TOOLS_DOWNLOAD_BASE}" "${_PACK_DEFAULT_MIRRORS[@]}")
	else
		m=("${_PACK_DEFAULT_MIRRORS[@]}")
	fi
	local -A seen=()
	local x
	for x in "${m[@]}"; do
		[[ -n "${x}" ]] || continue
		[[ -n "${seen[$x]:-}" ]] && continue
		seen[$x]=1
		echo "${x}"
	done
}

pack_http_get() {
	local url="$1" out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 2 --connect-timeout 20 --max-time 180 -o "${out}" "${url}"
	elif command -v wget >/dev/null 2>&1; then
		wget -q --tries=2 --timeout=20 -O "${out}" "${url}"
	else
		die "需要 curl 或 wget 以下载打包工具"
	fi
}

pack_download_one() {
	local dest="$1" name="$2"
	local tmp="${dest}/${name}.tmp" base url
	rm -f "${tmp}"
	while IFS= read -r base; do
		url="${base%/}/${name}"
		info "下载 ${name} <- ${url}"
		if pack_http_get "${url}" "${tmp}" && pack_is_elf "${tmp}"; then
			chmod 755 "${tmp}"
			mv -f "${tmp}" "${dest}/${name}"
			return 0
		fi
		warn "失败，尝试下一镜像: ${name}"
		rm -f "${tmp}"
	done < <(pack_mirror_list)
	die "无法下载 ${name}，请设置 PACK_TOOLS_SRC 或检查网络"
}

cmd_tools_pack() {
	local dest="${PACK_TOOLS_DIR:-${BSP_ROOT}/vendor/tools/pack-firmware}"
	mkdir -p "${dest}"

	if pack_tools_ready; then
		info "打包工具已存在: ${dest}"
		return 0
	fi

	local src="${PACK_TOOLS_SRC:-}"
	if [[ -z "${src}" ]]; then
		while IFS= read -r d; do
			if [[ -x "${d}/afptool" ]] && [[ -x "${d}/rkImageMaker" ]]; then
				src="${d}"
				break
			fi
		done < <(find "${BSP_ROOT}/.." /opt -path '*/Linux_Pack_Firmware/rockdev' -type d 2>/dev/null | head -20)
	fi

	if [[ -n "${src}" ]]; then
		info "从本机复制: ${src}"
		install -m 755 "${src}/afptool" "${src}/rkImageMaker" "${dest}/"
	else
		info "本机未找到 SDK 打包工具，从网络下载..."
		pack_download_one "${dest}" afptool
		pack_download_one "${dest}" rkImageMaker
	fi

	pack_tools_ready || die "打包工具安装失败: ${dest}"
	info "已安装打包工具到 ${dest}"
	ls -lh "${dest}/afptool" "${dest}/rkImageMaker"
}

mk_misc_img() {
	local misc_img="${OUT_DIR}/firmware/misc.img"
	mkdir -p "${OUT_DIR}/firmware"
	truncate -s 48k "${misc_img}"
	info "已生成空白 misc.img: ${misc_img}"
}

fw_link_or_copy() {
	local src="$1" dst="$2"
	if [[ "$(readlink -f "${src}")" == "$(readlink -f "${dst}" 2>/dev/null || true)" ]]; then
		return 0
	fi
	rm -f "${dst}"
	ln -rsf "${src}" "${dst}"
}

cmd_stage() {
	local fw_dir parameter_src loader
	fw_dir="${OUT_DIR}/firmware"
	parameter_src="${FIRMWARE_PARAMETER:-${BSP_ROOT}/vendor/firmware/parameter.txt}"
	mkdir -p "${fw_dir}"

	[[ -d "${UBOOT_DIR}" ]] || die "请先 ./bsp setup uboot && ./bsp uboot"

	loader="$(find "${UBOOT_DIR}" -maxdepth 1 -name 'rk3576_spl_loader_*.bin' | head -1)"
	[[ -n "${loader}" ]] || die "未找到 rk3576_spl_loader_*.bin，请先 ./bsp uboot"
	[[ -f "${UBOOT_DIR}/uboot.img" ]] || die "未找到 uboot.img"

	info "收集固件到 ${fw_dir}/"
	fw_link_or_copy "${loader}" "${fw_dir}/MiniLoaderAll.bin"
	fw_link_or_copy "${UBOOT_DIR}/uboot.img" "${fw_dir}/uboot.img"
	install -m 644 "${parameter_src}" "${fw_dir}/parameter.txt"

	if [[ ! -f "${fw_dir}/misc.img" ]]; then
		mk_misc_img
	fi

	if [[ -f "${OUT_DIR}/boot.img" ]]; then
		fw_link_or_copy "${OUT_DIR}/boot.img" "${fw_dir}/boot.img"
	else
		warn "缺少 out/boot.img，请先 ./bsp bootimg"
	fi

	if [[ -f "${OUT_DIR}/rootfs.ext4" ]]; then
		fw_link_or_copy "${OUT_DIR}/rootfs.ext4" "${fw_dir}/rootfs.img"
	elif [[ -f "${OUT_DIR}/rootfs/rootfs.img" ]]; then
		fw_link_or_copy "${OUT_DIR}/rootfs/rootfs.img" "${fw_dir}/rootfs.img"
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

	local pack_dir package_file work update_img
	pack_dir="${PACK_TOOLS_DIR:-${BSP_ROOT}/vendor/tools/pack-firmware}"
	package_file="${FIRMWARE_PACKAGE_FILE:-${BSP_ROOT}/vendor/firmware/package-file}"
	work="${OUT_DIR}/firmware-pack"
	update_img="${OUT_DIR}/update.img"

	if ! bsp_want_force && have_pack_artifacts; then
		info "已有 update.img，跳过打包（加 --clean 强制重做）"
		ls -lh "${update_img}"
		return 0
	fi

	cmd_tools_pack
	[[ -x "${pack_dir}/afptool" ]] || die "缺少 ${pack_dir}/afptool"
	[[ -x "${pack_dir}/rkImageMaker" ]] || die "缺少 ${pack_dir}/rkImageMaker"

	cmd_stage

	[[ -f "${OUT_DIR}/firmware/MiniLoaderAll.bin" ]] || die "缺少 MiniLoaderAll.bin"
	[[ -f "${OUT_DIR}/firmware/parameter.txt" ]] || die "缺少 parameter.txt"
	[[ -f "${OUT_DIR}/firmware/uboot.img" ]] || die "缺少 uboot.img"
	[[ -f "${OUT_DIR}/firmware/boot.img" ]] || die "缺少 boot.img"

	rm -rf "${work}"
	mkdir -p "${work}/Image"

	local _oldpwd name line pkg_name img_path tag
	_oldpwd="$(pwd)"
	cd "${work}"

	install -m 644 "${package_file}" package-file
	for name in MiniLoaderAll.bin parameter.txt uboot.img misc.img boot.img rootfs.img; do
		[[ -f "${OUT_DIR}/firmware/${name}" ]] || continue
		ln -rsf "${OUT_DIR}/firmware/${name}" "Image/${name}"
	done

	{
		while IFS= read -r line || [[ -n "${line}" ]]; do
			[[ "${line}" =~ ^[[:space:]]*# ]] && continue
			[[ -z "${line//[[:space:]]/}" ]] && continue
			pkg_name="${line%%[[:space:]]*}"
			img_path="${line##*[[:space:]]}"
			case "${pkg_name}" in
				package-file|backup|RESERVED)
					echo -e "${pkg_name}\t${img_path}"
					;;
				*)
					if [[ -f "${img_path}" ]]; then
						echo -e "${pkg_name}\t${img_path}"
					else
						warn "package-file 跳过缺失镜像: ${pkg_name} -> ${img_path}"
					fi
					;;
			esac
		done
	} < package-file > package-file.filtered
	mv package-file.filtered package-file

	info "package-file:"
	cat package-file

	"${pack_dir}/afptool" -pack ./ "${work}/update.raw.img"
	tag="RK$(dd if=Image/MiniLoaderAll.bin bs=1 count=4 skip=21 status=none | rev)"
	"${pack_dir}/rkImageMaker" "-${tag}" Image/MiniLoaderAll.bin \
		"${work}/update.raw.img" "${update_img}" -os_type:androidos

	cd "${_oldpwd}"

	info "完成: ${update_img}"
	ls -lh "${update_img}"
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

	info "全量编译（缓存：有则跳过；--clean 强制重编；--update 拉取源码）"
	cmd_setup_uboot_sources
	cmd_uboot
	cmd_setup_kernel_sources
	cmd_kernel
	cmd_bootimg

	if [[ "${skip_rootfs}" != "y" ]]; then
		cmd_rootfs
	fi

	if [[ "${skip_pack}" != "y" ]]; then
		if cmd_tools_pack 2>/dev/null; then
			cmd_pack || warn "pack 失败（可能缺少 rootfs 或打包工具）"
		else
			warn "跳过 update.img 打包（./bsp pack 可重试）"
		fi
	fi

	info "全量编译完成。产物: out/ 与 sources/u-boot/"
}
