#!/bin/bash
# 外置官方 IgH EtherCAT（stable-1.6）：交叉编译模块 + 用户态工具

have_ethercat_artifacts() {
	[[ -f "${OUT_DIR}/ethercat/modules/ec_master.ko" ]] || return 1
	{ [[ -x "${OUT_DIR}/ethercat/usr/bin/ethercat" ]] || \
	  [[ -x "${OUT_DIR}/ethercat/usr/sbin/ethercat" ]]; } || return 1
	case "${ETHERCAT_DEVICE_MODULE:-r8169}" in
		r8169)
			[[ -f "${OUT_DIR}/ethercat/modules/ec_r8169.ko" ]] || return 1
			;;
		generic)
			[[ -f "${OUT_DIR}/ethercat/modules/ec_generic.ko" ]] || return 1
			;;
		*)
			# 同时需要两者时至少有一个设备模块
			[[ -f "${OUT_DIR}/ethercat/modules/ec_r8169.ko" ]] || \
				[[ -f "${OUT_DIR}/ethercat/modules/ec_generic.ko" ]] || return 1
			;;
	esac
	return 0
}

cmd_setup_ethercat_sources() {
	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		info "KERNEL_ETHERCAT=${KERNEL_ETHERCAT}，跳过 IgH 源码"
		return 0
	fi
	mkdir -p "${SOURCES_DIR}" "${DL_DIR}"

	if [[ "${ETHERCAT_SOURCE}" == "git" ]]; then
		clone_or_update "${ETHERCAT_REPO}" "${ETHERCAT_BRANCH}" "${ETHERCAT_DIR}"
		if [[ ! -f "${ETHERCAT_DIR}/configure" ]]; then
			if command -v autoconf >/dev/null 2>&1 && [[ -x "${ETHERCAT_DIR}/bootstrap" ]]; then
				info "bootstrap IgH（git 树）..."
				( cd "${ETHERCAT_DIR}" && ./bootstrap )
			else
				warn "git 树无 configure 且无 autoconf，回退下载官方 dist ${ETHERCAT_VERSION}"
				ETHERCAT_SOURCE=dist ensure_ethercat_dist_tree
			fi
		fi
	else
		ensure_ethercat_dist_tree
	fi

	[[ -f "${ETHERCAT_DIR}/configure" ]] || die "IgH 源码缺少 configure: ${ETHERCAT_DIR}"
	BSP_SETUP_ETHERCAT_DONE=1
	info "IgH EtherCAT 源码就绪: ${ETHERCAT_DIR} (${ETHERCAT_SOURCE}/${ETHERCAT_VERSION:-${ETHERCAT_BRANCH}})"
}

ensure_ethercat_dist_tree() {
	local tarball="${DL_DIR}/ethercat-${ETHERCAT_VERSION}.tar.gz"
	local marker="${ETHERCAT_DIR}/.bsp-ethercat-dist"

	if bsp_want_update; then
		bsp_refresh_download "${tarball}"
		rm -rf "${ETHERCAT_DIR}"
	fi

	if [[ -f "${marker}" ]] && [[ "$(cat "${marker}" 2>/dev/null)" == "${ETHERCAT_VERSION}" ]] && \
		[[ -f "${ETHERCAT_DIR}/configure" ]]; then
		info "已有 IgH dist ${ETHERCAT_VERSION}，跳过下载（加 --update 可刷新）"
		return 0
	fi

	if [[ ! -f "${tarball}" ]]; then
		info "下载 IgH EtherCAT ${ETHERCAT_VERSION}: ${ETHERCAT_DIST_URL}"
		if command -v curl >/dev/null 2>&1; then
			curl -fL --retry 3 --connect-timeout 30 -o "${tarball}.partial" "${ETHERCAT_DIST_URL}"
			mv -f "${tarball}.partial" "${tarball}"
		elif command -v wget >/dev/null 2>&1; then
			wget -O "${tarball}.partial" "${ETHERCAT_DIST_URL}"
			mv -f "${tarball}.partial" "${tarball}"
		else
			die "需要 curl 或 wget 以下载 IgH dist"
		fi
	fi

	info "解压 ${tarball} -> ${ETHERCAT_DIR}"
	local staging="${SOURCES_DIR}/.ethercat-dist-staging"
	rm -rf "${staging}"
	mkdir -p "${staging}"
	tar -C "${staging}" -xzf "${tarball}"
	local extracted=""
	if [[ -d "${staging}/ethercat-${ETHERCAT_VERSION}" ]]; then
		extracted="${staging}/ethercat-${ETHERCAT_VERSION}"
	else
		extracted="$(find "${staging}" -mindepth 1 -maxdepth 1 -type d | head -1)"
	fi
	[[ -n "${extracted}" && -d "${extracted}" ]] || die "解压后未找到 ethercat-${ETHERCAT_VERSION}"
	# 替换旧树（可能含只读 .git hooks）
	if [[ -e "${ETHERCAT_DIR}" ]]; then
		rm -rf "${ETHERCAT_DIR}" 2>/dev/null || mv -f "${ETHERCAT_DIR}" "${ETHERCAT_DIR}.old.$$" || true
		rm -rf "${ETHERCAT_DIR}.old."* 2>/dev/null || true
	fi
	mv "${extracted}" "${ETHERCAT_DIR}"
	rm -rf "${staging}"
	[[ -f "${ETHERCAT_DIR}/configure" ]] || die "dist 缺少 configure"
	printf '%s\n' "${ETHERCAT_VERSION}" > "${marker}"
}

# 内核侧：仅保留 r8125 内置补丁；去掉内嵌 EC DTS；不打 0100–0104
apply_kernel_ethercat_patches() {
	[[ -d "${KERNEL_DIR}" ]] || die "请先运行 ./bsp setup kernel"
	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		info "KERNEL_ETHERCAT=${KERNEL_ETHERCAT}，跳过 EtherCAT 相关内核补丁"
		return 0
	fi

	local marker="${KERNEL_DIR}/.bsp-ethercat-applied"
	local want_marker="igh-oot-generic-v1"
	local dts="${KERNEL_DIR}/arch/${KERNEL_ARCH}/boot/dts/${KERNEL_DTS_SUBDIR}/x1_orangepi-r2s.dts"
	local r8125_mk="${KERNEL_DIR}/drivers/net/ethernet/realtek/r8125/Makefile"

	if [[ -f "${marker}" ]] && [[ "$(cat "${marker}" 2>/dev/null)" == "${want_marker}" ]] && \
		grep -q 'obj-$(CONFIG_R8125)' "${r8125_mk}" 2>/dev/null && \
		! grep -q 'ec-mac-main\|ky,x1-ec-emac' "${dts}" 2>/dev/null; then
		info "EtherCAT 内核准备已完成 ($(cat "${marker}"))"
		return 0
	fi
	if [[ -f "${marker}" ]]; then
		warn "EtherCAT 内核标记过期，重新准备..."
		rm -f "${marker}"
	fi

	command -v patch >/dev/null 2>&1 || die "需要 patch 命令（apt install patch）"

	# 只打 r8125 内置修复（外置 IgH 依赖普通 r8125 netdev）
	local p105="${BSP_ROOT}/vendor/patches/kernel/0105-r8125-honor-config-builtin.patch"
	[[ -f "${p105}" ]] || die "缺少 ${p105}"
	patch_forward_or_skip "${p105}" "$(basename "${p105}")" || die "应用 ${p105} 失败"

	# 去掉内嵌 ec_master / 广播 MAC 节点（若曾打过旧 0101）
	if [[ -f "${dts}" ]] && grep -q 'ec-mac-main\|ec_master\|ky,x1-ec-emac' "${dts}"; then
		info "移除 DTS 中内嵌 IgH ec_master / ec-mac-* 节点"
		python3 - "${dts}" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
orig = text
# Strip trailing IgH block(s) after &rcpu
for pat in (
    r"\n/\*\s*\n \* IgH EtherCAT.*?\n&ec_master \{.*?\n\};\s*\Z",
    r"\n/\* IgH EtherCAT: dual EMAC.*?\n&ec_master \{\s*status = \"okay\";\s*\};\s*\Z",
):
    text = re.sub(pat, "\n", text, count=1, flags=re.S)
if text == orig and ("ec-mac-main" in orig or "ky,x1-ec-emac" in orig or "ec_master" in orig):
    for needle in ("\n/*\n * IgH EtherCAT", "\n/* IgH EtherCAT", "\nec_master:", "\nec-mac-main"):
        idx = orig.find(needle)
        if idx >= 0 and ("IgH" in orig[idx:idx+80] or "ec_master" in orig[idx:idx+200] or "ec-mac" in orig[idx:idx+200]):
            # Prefer comment start
            for n2 in ("\n/*\n * IgH EtherCAT", "\n/* IgH EtherCAT"):
                i2 = orig.find(n2)
                if i2 >= 0:
                    idx = i2
                    break
            text = orig[:idx].rstrip() + "\n"
            break
if text != orig:
    open(path, "w", encoding="utf-8").write(text)
    print("dts cleaned", file=sys.stderr)
else:
    print("dts unchanged", file=sys.stderr)
PY
	fi

	grep -q 'obj-$(CONFIG_R8125)' "${r8125_mk}" || \
		die "r8125 Makefile 未按 CONFIG_R8125 编译"
	if grep -q 'ec-mac-main\|ky,x1-ec-emac' "${dts}" 2>/dev/null; then
		die "DTS 仍含内嵌 EtherCAT 节点，请检查清理逻辑"
	fi

	printf '%s\n' "${want_marker}" > "${marker}"
	info "EtherCAT 内核准备完成: 关闭内嵌 EC，r8125 内置 ($(cat "${marker}"))"
}

cmd_ethercat() {
	parse_build_flags "$@"
	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		info "KERNEL_ETHERCAT=${KERNEL_ETHERCAT}，跳过外置 IgH 构建"
		return 0
	fi

	if ! bsp_want_rebuild && have_ethercat_artifacts; then
		info "已有 out/ethercat 产物，跳过（加 --clean/--update 强制重做）"
		ls -lh "${OUT_DIR}/ethercat/modules/"*.ko "${OUT_DIR}/ethercat/usr/bin/ethercat" 2>/dev/null || true
		return 0
	fi

	cmd_setup_ethercat_sources
	[[ -d "${ETHERCAT_DIR}" ]] || die "缺少 ${ETHERCAT_DIR}"
	[[ -d "${KERNEL_DIR}" ]] || die "请先 ./bsp setup kernel && ./bsp kernel"
	[[ -f "${KERNEL_DIR}/.config" ]] || die "内核未配置，请先 ./bsp kernel"

	setup_cross_compile
	local jobs
	jobs="$(job_count)"
	local cc ld ar
	cc="${CROSS_COMPILE}gcc"
	ld="${CROSS_COMPILE}ld"
	ar="${CROSS_COMPILE}ar"
	local host_triplet="${CROSS_COMPILE_PREFIX%-}"

	for t in pkg-config; do
		command -v "${t}" >/dev/null 2>&1 || \
			die "缺少 ${t}，请 ./bsp env 或 apt install pkg-config"
	done
	# dist 源已含 configure；仅 git 源在无 configure 时需要 autoconf（setup 已处理）

	info "准备内核 modules_prepare（供外置模块）..."
	local kmake=(make -C "${KERNEL_DIR}" ARCH="${KERNEL_ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"${jobs}")
	"${kmake[@]}" modules_prepare
	# 外置模块 modpost 需要 Module.symvers（仅 Image 不够）
	if [[ ! -f "${KERNEL_DIR}/Module.symvers" ]]; then
		info "缺少 Module.symvers，编译内核 modules..."
		# 基线里 husb239=m 在 slim 下常缺符号，关掉以免卡死 modules
		if [[ -x "${KERNEL_DIR}/scripts/config" ]]; then
			( cd "${KERNEL_DIR}" && ./scripts/config --disable TYPEC_HUSB239 || true )
			"${kmake[@]}" olddefconfig >/dev/null
		fi
		# 个别树内模块仍可能缺符号；WARN 足以产出 Module.symvers 供外置 IgH
		KBUILD_MODPOST_WARN=1 "${kmake[@]}" modules
	fi
	[[ -f "${KERNEL_DIR}/Module.symvers" ]] || die "仍无 ${KERNEL_DIR}/Module.symvers"

	local sysroot=""
	if [[ -d "${TOOLCHAIN_DIR}/sysroot" ]]; then
		sysroot="${TOOLCHAIN_DIR}/sysroot"
	elif [[ -d "${TOOLCHAIN_DIR}/${CROSS_COMPILE_PREFIX%-}/sysroot" ]]; then
		sysroot="${TOOLCHAIN_DIR}/${CROSS_COMPILE_PREFIX%-}/sysroot"
	fi

	pushd "${ETHERCAT_DIR}" >/dev/null
	[[ -f configure ]] || die "缺少 configure（请 ./bsp setup ethercat）"

	if bsp_want_rebuild; then
		make distclean >/dev/null 2>&1 || true
	fi

	info "configure 外置 IgH（${ETHERCAT_DEVICE_MODULE}，交叉 ${host_triplet}）..."
	local conf=(
		./configure
		"--host=${host_triplet}"
		"--with-linux-dir=${KERNEL_DIR}"
		"--prefix=/usr"
		"--sysconfdir=/etc"
		"--with-devices=2"
		"--enable-kernel"
		"--enable-tool"
		"--enable-userlib"
		"--disable-8139too"
		"--disable-e100"
		"--disable-e1000"
		"--disable-e1000e"
		"--disable-igb"
		"--disable-igc"
		"--disable-ccat"
		"--disable-genet"
		"--disable-macb"
		"--disable-stmmac-pci"
		"--disable-dwmac-intel"
		"--disable-rtdm"
		"CC=${cc}"
		"LD=${ld}"
		"AR=${ar}"
	)
	# 默认编 r8169（RTL8125）+ generic（回退）；按 ETHERCAT_DEVICE_MODULE 也可只编一侧
	case "${ETHERCAT_DEVICE_MODULE}" in
		r8169)
			conf+=("--enable-r8169" "--with-r8169-kernel=${ETHERCAT_R8169_KERNEL}" "--enable-generic")
			;;
		generic)
			conf+=("--disable-r8169" "--enable-generic")
			;;
		*)
			conf+=("--enable-r8169" "--with-r8169-kernel=${ETHERCAT_R8169_KERNEL}" "--enable-generic")
			;;
	esac
	if [[ -n "${sysroot}" ]]; then
		conf+=("CFLAGS=--sysroot=${sysroot}" "LDFLAGS=--sysroot=${sysroot}")
	fi
	"${conf[@]}"

	# 不编 examples/mini 内核模块（避免多余依赖与失败）
	if [[ -f Kbuild ]] && grep -q 'examples/' Kbuild; then
		sed -i 's|obj-m := examples/ master/ devices/|obj-m := master/ devices/|' Kbuild
	fi

	info "编译 IgH modules + userspace (jobs=${jobs})..."
	make -j"${jobs}" all modules

	local dest="${OUT_DIR}/ethercat"
	rm -rf "${dest}"
	mkdir -p "${dest}/modules" "${dest}/usr"

	make DESTDIR="${dest}" install
	# 模块单独收集到固定路径，便于 rootfs 安装与产物检测
	local ko
	while IFS= read -r -d '' ko; do
		install -m 644 "${ko}" "${dest}/modules/"
	done < <(find . -name 'ec_*.ko' -print0 2>/dev/null)

	popd >/dev/null

	have_ethercat_artifacts || die "IgH 产物不完整，请检查 ${dest}"
	info "IgH EtherCAT 完成:"
	ls -lh "${dest}/modules/"*.ko
	ls -lh "${dest}/usr/bin/ethercat" "${dest}/usr/sbin/ethercatctl" 2>/dev/null || true
}

# 安装到 rootfs
install_ethercat_oot() {
	local root="$1"
	if [[ "${KERNEL_ETHERCAT}" != "y" && "${KERNEL_ETHERCAT}" != "1" ]]; then
		return 0
	fi
	if ! have_ethercat_artifacts; then
		warn "缺少 out/ethercat，尝试构建..."
		cmd_ethercat
	fi
	have_ethercat_artifacts || { warn "仍无 IgH 产物，跳过安装"; return 0; }

	info "安装 IgH 用户态 -> ${root}/usr"
	if [[ -d "${OUT_DIR}/ethercat/usr" ]]; then
		run_root rsync -a "${OUT_DIR}/ethercat/usr/" "${root}/usr/"
	fi
	if [[ -d "${OUT_DIR}/ethercat/etc" ]]; then
		run_root rsync -a --exclude='ethercat.conf' "${OUT_DIR}/ethercat/etc/" "${root}/etc/" 2>/dev/null || \
			run_root rsync -a "${OUT_DIR}/ethercat/etc/" "${root}/etc/"
	fi
	# overlay 的 ethercat.conf / ethercat.service 优先
	if [[ -f "${BSP_ROOT}/vendor/rootfs/overlay/etc/ethercat.conf" ]]; then
		run_root cp -a "${BSP_ROOT}/vendor/rootfs/overlay/etc/ethercat.conf" "${root}/etc/ethercat.conf"
	fi
	if [[ -f "${BSP_ROOT}/vendor/rootfs/overlay/etc/systemd/system/ethercat.service" ]]; then
		run_root mkdir -p "${root}/etc/systemd/system"
		run_root cp -a "${BSP_ROOT}/vendor/rootfs/overlay/etc/systemd/system/ethercat.service" \
			"${root}/etc/systemd/system/ethercat.service"
	fi
	run_root chmod 755 "${root}/usr/sbin/ethercatctl" 2>/dev/null || true
	run_root chmod 755 "${root}/usr/bin/ethercat" 2>/dev/null || true

	local krel dest_mod
	krel="$(cat "${KERNEL_DIR}/include/config/kernel.release" 2>/dev/null || true)"
	if [[ -z "${krel}" ]] && [[ -f "${KERNEL_DIR}/Makefile" ]]; then
		krel="$(make -s -C "${KERNEL_DIR}" ARCH="${KERNEL_ARCH}" CROSS_COMPILE="${CROSS_COMPILE:-}" kernelrelease 2>/dev/null | tail -n1 || true)"
	fi
	if [[ -z "${krel}" ]]; then
		warn "尚无 kernel.release，暂缓安装 IgH .ko（等内核模块阶段）"
		return 0
	fi
	dest_mod="${root}/lib/modules/${krel}/extra"
	info "安装外置 IgH 模块 -> ${dest_mod}"
	run_root mkdir -p "${dest_mod}"
	run_root cp -a "${OUT_DIR}/ethercat/modules/"*.ko "${dest_mod}/"

	install_ethercat_rtl8125_firmware "${root}"
}

# RTL8125B 固件（ec_r8169 的 VER_63 会 request_firmware）
install_ethercat_rtl8125_firmware() {
	local root="$1"
	local fw_dir="${DL_DIR}/firmware/rtl_nic"
	local dest_dir="${root}/lib/firmware/rtl_nic"
	local name url path

	mkdir -p "${fw_dir}"
	run_root mkdir -p "${dest_dir}"

	# 8125A / 8125B 固件都装上（ec_r8169 按芯片版本选择）
	for name in rtl8125b-2.fw rtl8125a-3.fw; do
		path="${fw_dir}/${name}"
		url="https://raw.githubusercontent.com/armbian/firmware/master/rtl_nic/${name}"
		if [[ "${name}" == "${ETHERCAT_RTL8125_FW_NAME}" ]]; then
			url="${ETHERCAT_RTL8125_FW_URL}"
		fi
		if bsp_want_update; then
			bsp_refresh_download "${path}"
		fi
		if [[ ! -f "${path}" ]]; then
			info "下载 ${name}..."
			if command -v curl >/dev/null 2>&1; then
				curl -fL --retry 3 --connect-timeout 30 -o "${path}.partial" "${url}" && \
					mv -f "${path}.partial" "${path}" || warn "下载失败: ${name}"
			elif command -v wget >/dev/null 2>&1; then
				wget -O "${path}.partial" "${url}" && mv -f "${path}.partial" "${path}" || \
					warn "下载失败: ${name}"
			else
				warn "无法下载 ${name}（无 curl/wget）"
				continue
			fi
		fi
		[[ -s "${path}" ]] || continue
		run_root cp -a "${path}" "${dest_dir}/${name}"
	done
	info "固件已安装到 ${dest_dir}/"
}
