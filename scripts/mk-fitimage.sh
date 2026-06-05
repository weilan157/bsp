#!/bin/bash
# 打包 Rockchip FIT boot 镜像（boot.img）

set -euo pipefail

TARGET_IMG="$1"
ITS="$2"
KERNEL_IMG="$3"
KERNEL_DTB="$4"
RESOURCE_IMG="$5"

[[ -f "${ITS}" ]] || { echo "ITS 不存在: ${ITS}" >&2; exit 1; }
for f in "${KERNEL_IMG}" "${KERNEL_DTB}" "${RESOURCE_IMG}"; do
	[[ -f "${f}" ]] || { echo "缺少文件: ${f}" >&2; exit 1; }
done

TMP_ITS="$(mktemp)"
cp "${ITS}" "${TMP_ITS}"

sed -i \
	-e "s~@KERNEL_DTB@~$(realpath -q "${KERNEL_DTB}")~" \
	-e "s~@KERNEL_IMG@~$(realpath -q "${KERNEL_IMG}")~" \
	-e "s~@RESOURCE_IMG@~$(realpath -q "${RESOURCE_IMG}")~" \
	"${TMP_ITS}"

# shellcheck disable=SC2086
"${MKIMAGE}" -f "${TMP_ITS}" -E -p 0x800 "${TARGET_IMG}"
rm -f "${TMP_ITS}"
