#!/usr/bin/env python3
"""生成 Allwinner boot_package.fex（TOC1 + spare_boot_head + u-boot 载荷）

格式取自 device/bin 里随板的 boot0 与 Radxa 官方 boot_package.fex 的实测结构：

  0x000  TOC1 头（"sunxi-package"，magic 0x89119800）
  0x040  条目表，每项 80 字节：name[64] + data_offset + data_len + encrypt + type
  0x800  条目数据：spare_boot_head（1024 字节）+ u-boot 载荷
         head 里 check_sum 是固定戳 0x5F0A6C39（不是校验和）

用法：
  mk_boot_package.py <u-boot.bin> <u-boot.dtb> <out.fex> [--text-base 0x4a000000]
"""

import argparse
import struct
import sys

STAMP = 0x5F0A6C39        # spare_boot_head.check_sum：Allwinner 的固定戳
TOC_MAGIC = 0x89119800
TOC_END = 0x3B45494D
HEAD_SIZE = 0x400         # spare_boot_head
ITEMS_OFF = 0x800         # 条目数据起点
ITEM_SIZE = 80            # name[64] + 4*u32
TOTAL_ALIGN = 0x80000     # 参考包按 512K 对齐


def build(payload: bytes, text_base: int = 0x4A000000,
          version: bytes = b"4.0.0", platform: bytes = b"2.0.0",
          items_nr: int = 3, name: bytes = b"u-boot") -> bytes:
    head = bytearray(HEAD_SIZE)
    struct.pack_into("<I", head, 0, 0xEA00018E)          # jump over head
    head[4:12] = b"uboot\x00\x00\x00"                    # magic
    struct.pack_into("<I", head, 12, STAMP)              # check_sum
    struct.pack_into("<I", head, 16, 0x4000)             # align_size
    struct.pack_into("<I", head, 20, 0)                  # length（参考包为 0）
    struct.pack_into("<I", head, 24, 0)                  # uboot_length（同）
    head[28:36] = version.ljust(8, b"\x00")
    head[36:44] = platform.ljust(8, b"\x00")
    struct.pack_into("<I", head, 44, text_base & 0xFFFFFFFF)

    blob = bytes(head) + payload
    total = (ITEMS_OFF + len(blob) + TOTAL_ALIGN - 1) // TOTAL_ALIGN * TOTAL_ALIGN
    img = bytearray(total)
    img[ITEMS_OFF:ITEMS_OFF + len(blob)] = blob

    # TOC1 头
    img[0:16] = b"sunxi-package".ljust(16, b"\x00")
    struct.pack_into("<I", img, 16, TOC_MAGIC)
    struct.pack_into("<I", img, 32, items_nr)
    struct.pack_into("<I", img, 36, total)               # valid_len
    struct.pack_into("<I", img, 60, TOC_END)

    # 条目表
    img[0x40:0x40 + 64] = name.ljust(64, b"\x00")
    struct.pack_into("<I", img, 0x40 + 64, ITEMS_OFF)
    struct.pack_into("<I", img, 0x40 + 68, len(blob))
    struct.pack_into("<I", img, 0x40 + 72, 0)            # encrypt: 0
    struct.pack_into("<I", img, 0x40 + 76, 3)            # type: 3 = bin file

    # add_sum：Allwinner 用整包字节和；非安全启动下 boot0 不校验
    struct.pack_into("<I", img, 20, sum(img) & 0xFFFFFFFF)
    return bytes(img)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("uboot")
    ap.add_argument("dtb", nargs="?")
    ap.add_argument("out")
    ap.add_argument("--text-base", default="0x4a000000")
    ap.add_argument("--no-dtb", action="store_true")
    args = ap.parse_args()

    payload = open(args.uboot, "rb").read()
    # Allwinner 的载荷是 u-boot-dtb.bin：u-boot.bin + dtb（若还没内嵌）
    if args.dtb and not args.no_dtb and b"\xd0\x0d\xfe\xed" not in payload[-0x40000:]:
        payload += open(args.dtb, "rb").read()

    img = build(payload, text_base=int(args.text_base, 0))
    with open(args.out, "wb") as f:
        f.write(img)
    print(f"boot_package: {args.out} ({len(img)} bytes, payload {len(payload)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
