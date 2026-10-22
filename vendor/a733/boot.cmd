# Cubie A7Z（A733）u-boot 启动脚本
# boot 分区是第 3 个分区（boot-resource=1, env=2, boot=3, rootfs=4）
#
# UART0（PB9/PB10 = pin 8/10）留给舵机总线，所以 console 不放在串口上：
#   - 默认 tty1（本机无显示时看不到，但不会占用 UART0）
#   - 需要串口调试时改成 console=ttyGS0,115200（USB gadget 串口）或换一路 UART
setenv bootargs console=tty1 root=/dev/mmcblk0p4 rootwait rw cma=8M loglevel=3

fatload mmc 0:3 ${kernel_addr_r} Image
fatload mmc 0:3 ${fdt_addr_r} sun60i-a733-cubie-a7z.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
