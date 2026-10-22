# Cubie A7Z（A733）u-boot 启动脚本
# boot 分区是第 3 个分区（boot-resource=1, env=2, boot=3, rootfs=4）
# 与 vendor/a733/env.cfg 里的 console/earlyprintk 保持一致
setenv bootargs console=ttyS0,115200 earlyprintk=sunxi-uart,0x02500000 root=/dev/mmcblk0p4 rootwait rw cma=8M loglevel=3

fatload mmc 0:3 ${kernel_addr_r} Image
fatload mmc 0:3 ${fdt_addr_r} sun60i-a733-cubie-a7z.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
