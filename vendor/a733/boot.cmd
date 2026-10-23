# Cubie A7Z（A733）u-boot 启动脚本
#
# 布局与 rsdk 官方镜像一致：boot0@128KiB + boot_package.fex@12MiB，
# p1 = config(FAT, 16MiB)，p2 = rootfs(ext4, 32MiB 起)，内核/设备树在
# rootfs 的 /boot 下。u-boot 是 CONFIG_BOOTCOMMAND="run distro_bootcmd"，
# 这颗 u-boot 没有 sysboot/extlinux 支持，所以 distro_bootcmd 会扫到
# 分区根目录的 /boot.scr 再 source 它（本文件由 ./bsp pack 生成）。
#
# console 用 tty1：UART0（PB9/PB10 = 排针 8/10）留给舵机总线。
# 需要串口调试时改成 console=ttyGS0,115200（USB gadget）或换一路 UART。
setenv bootargs @BOOTARGS@

load mmc 0:2 ${kernel_addr_r} /boot/Image
load mmc 0:2 ${fdt_addr_r} /boot/@DTB@
booti ${kernel_addr_r} - ${fdt_addr_r}
