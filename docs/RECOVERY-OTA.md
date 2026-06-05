# Recovery OTA（泰山派 / RK3576）

## 架构

1. **Debian 正常运行**：`tspi-ota apply` → 写 **misc** → 重启  
2. **U-Boot**：读 misc `boot-recovery` → 加载 **recovery.img**  
3. **Recovery (Buildroot)**：`rkupdate` 刷 **ota.img** 里的 boot/rootfs  
4. 重启进新系统  

## SDK 侧（主机）

```bash
# 在 config.env 中设置 TSPI_SDK_ROOT
./scripts/build-recovery-ota.sh
```

或手动：

```bash
cd TaishanPi-3-Linux
./build.sh tspi_3m_rk3576_debian_bookworm_desktop_defconfig recovery ota-updateimg
```

产物：

| 文件 | 用途 |
|------|------|
| `output/firmware/recovery.img` | 首次需烧 **recovery 分区** |
| `output/firmware/ota.img` | Recovery OTA 升级包 |

`ota-package-file` 默认只含 **boot.img + rootfs.img**（不含 uboot）。

## 首次烧录

除常规 firmware 外，需包含 **recovery.img**：

```bash
./build.sh <defconfig> firmware   # 含 recovery（RK_RECOVERY=y）
# 或单独
./device/rockchip/common/scripts/rkflash.sh recovery
```

## 板端（Debian）

```bash
# 复制 OTA 包
scp ota.img board:/userdata/update.img

# 触发 Recovery OTA
sudo tspi-ota apply
# 或指定路径
sudo tspi-ota apply /userdata/ota.img

# 查看状态
tspi-ota status
```

依赖：

- `/usr/bin/update`（rktoolkit deb，SDK 编 Debian 时已装）
- `/dev/block/by-name/*`（`S02rockchip-partnames` 启动脚本）

## 维护分工

| 组件 | 维护方 |
|------|--------|
| recovery.img | SDK `./build.sh recovery` |
| ota.img | SDK `./build.sh ota-updateimg` |
| Debian rootfs | `./build.sh` debian/rootfs |
| boot.img | `./build.sh kernel` |

## 配置项（已写入 tspi defconfig）

```
RK_RECOVERY=y
RK_MISC_BLANK=y
RK_OTA_PACKAGE_FILE="ota-package-file"
```

## 注意

- Recovery 是 **Buildroot**，与 Debian 是两套系统；OTA 只更新 **boot/rootfs 分区**。  
- **/home 在 userdata** 时不会被 OTA 覆盖（rootfs 镜像不含 home 时）。  
- 修改 `ota-package-file` 可增减 OTA 分区（慎加 uboot）。  
