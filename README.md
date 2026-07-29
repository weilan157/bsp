# Orange Pi R2S BSP（Ky X1）

独立仓库：从 GitHub 拉取 Orange Pi **R2S**（Ky X1）的 U-Boot、内核，在主机上交叉编译并打包 **Debian riscv64** 根文件系统与 SD 卡镜像。

统一入口：仓库根目录 **`./bsp`**。

参考：

- [orangepi-build (next)](https://github.com/orangepi-xunlong/orangepi-build/tree/next) — `orangepir2s`，family `ky`
- 内核：[linux-orangepi `orange-pi-6.6-ky`](https://github.com/orangepi-xunlong/linux-orangepi/tree/orange-pi-6.6-ky) — DTS `x1_orangepi-r2s.dts`
- U-Boot：[u-boot-orangepi `v2022.10-ky`](https://github.com/orangepi-xunlong/u-boot-orangepi/tree/v2022.10-ky)
- 工具链：`riscv64-unknown-linux-gnu-`（`ky-toolchain-linux-glibc-x86_64-v1.0.1`）

## 目录结构

```
rockchip-bsp/
├── bsp                      # 唯一构建入口
├── config.env.example
├── vendor/
│   ├── boot/                # boot-ky.cmd / orangepiEnv.txt
│   ├── kernel-config/       # 官方 linux-ky-current.config + slim.config（R2S 精简）
│   ├── firmware/ky/         # esos.elf
│   └── rootfs/              # debootstrap overlay + chroot 配置
├── scripts/
│   ├── lib.sh
│   ├── mod-env.sh           # 含 Ky toolchain 下载
│   ├── mod-sources.sh
│   ├── mod-uboot.sh
│   ├── mod-kernel.sh
│   ├── mod-rootfs.sh
│   └── mod-pack.sh          # SD 整盘镜像（非 Rockchip update.img）
├── out/                     # 产物（不入库）
├── toolchains/              # Ky 交叉工具链（./bsp env 下载）
└── sources/                 # 克隆的源码（不入库）
```

## 快速开始

```bash
cp config.env.example config.env   # 或 ./bsp config 自动创建
./bsp env                          # 主机依赖 + Ky toolchain（~610MB）
./bsp setup all                    # 克隆 u-boot / kernel
./bsp uboot
./bsp kernel
./bsp bootimg                      # FAT boot.img → out/boot.img
./bsp rootfs                       # Debian minbase riscv64 → out/rootfs.ext4
./bsp pack                         # out/orangepir2s.img
```

一键全流程：

```bash
./bsp env
./bsp all                  # 有源码/产物缓存则跳过
./bsp all --clean          # 强制重编全部构建缓存（不重新下载）
./bsp all --update         # 刷新 toolchain/源码/RT补丁，并重建
./bsp all --skip-rootfs -j 8
```

缓存语义：

| 选项 | 作用 |
|------|------|
| （默认） | 有下载/产物则复用 |
| `--clean` | 强制重做 uboot/kernel/bootimg/rootfs/pack |
| `--update` | 重下 toolchain、git 源码、RT 补丁，并重建衍生产物 |
| `./bsp clean all` | 清 out/、构建产物、`dl/`（保留 sources、toolchain） |

固定板型：`BOARD=orangepir2s`，`KERNEL_DTS_NAME=x1_orangepi-r2s`。

## 编译产物

| 命令 | 产物 |
|------|------|
| `./bsp uboot` | `out/uboot/`：`FSBL.bin`、`bootinfo_sd.bin`、`u-boot-opensbi.itb` 等 |
| `./bsp kernel` | `out/kernel/Image`、`out/kernel/x1_orangepi-r2s.dtb` |
| `./bsp bootimg` | `out/boot/`、`out/boot.img`（FAT：Image + dtb + boot.scr） |
| `./bsp rootfs` | `out/rootfs/`、`out/rootfs.ext4` |
| `./bsp pack` | `out/orangepir2s.img`（可 `dd` 到 microSD） |
| `./bsp emmc` | 写入板载 eMMC（boot0 + 分区 + 系统） |

烧录 SD：

```bash
sudo dd if=out/orangepir2s.img of=/dev/sdX bs=4M status=progress conv=fsync
```

安装 eMMC（先用 SD 启动，确认设备名，常见为 `mmcblk1`）：

```bash
# 主机交叉编译产物齐全后，在板子上：
./bsp emmc /dev/mmcblk1 --yes

# 或只更新 bootloader：
./bsp emmc /dev/mmcblk1 --yes --uboot-only

# 也可把 out/firmware/ 拷到板子后执行：
sudo ./install-emmc.sh /dev/mmcblk1 --yes
```

eMMC 引导对齐官方 orangepi-build：`bootinfo_emmc` + `FSBL` 写入 **`mmcblkXboot0`**，用户区扇区布局与 SD 相同。

串口：`115200 8N1`，设备 `ttyS0`。

## Bootloader 布局（与 orangepi-build 一致）

写入 SD 卡原始扇区（512 字节）：

| 文件 | seek（扇区） |
|------|----------------|
| `bootinfo_sd.bin` | 0 |
| `FSBL.bin` | 256 |
| `u-boot-env-default.bin` | 768 |
| `u-boot-opensbi.itb` | 1664 |

分区：`OFFSET=30MiB` 起 GPT — `p1` boot（FAT）、`p2` rootfs（ext4）。

## Debian rootfs

官方 **debootstrap minbase**（无桌面），架构 **riscv64**。

默认用户：`weiqi` / `321`，root：`root` / `root`。

## 分支

- `main`：仓库骨架  
- `rk3576`：历史 Rockchip RK3576 分支  
- `OrangePi-kyX1`：本分支（Orange Pi R2S / Ky X1）
