# NPU：现状与怎么开

## 结论

- **A733 有 NPU**（DT 里 `npu@3600000`，`compatible = "allwinner,npu"`，
  board.dts 里 `npu-supply = <&reg_dcdc2>`、`status = "okay"`）。
- **但我们的镜像里没有 NPU 驱动**：BSP 的 `CONFIG_AW_NNA_VIP` /
  `CONFIG_AW_NNA_GALCORE` 都是 `default n`，官方 A733 的
  `sun60iw2p1_min_defconfig` 也明确写着两行 `is not set`；我们的 fragment 没有加。
  所以现在 `/dev/vipcore`（或 `/dev/galcore`）不存在，NPU 用不了。
- 驱动有两套，**都 match `allwinner,npu`，只能二选一**：
  - `aw_nna_vip`（VIP9000，源码 2.5 MB，A733 对应 `vip2`，驱动里有 `sun60iw2` 分支）；
  - `aw_nna_galcore`（Vivante GC，源码 28 MB，给别的 SoC 的 NPU/GPU 用）。

## 怎么开

```bash
./bsp config A733_WITH_NPU=y
./bsp kernel && ./bsp pack
```

`./bsp kernel` 会往 fragment 里追加：

```
CONFIG_AW_NNA_VIP=y
CONFIG_NNA_VIP2=y
# CONFIG_NNA_VIP1 is not set
# CONFIG_AW_NNA_GALCORE is not set
CONFIG_DEBUG_FS=y
CONFIG_NPU_SET_CLK_VOL=y
```

后两项是踩出来的：6.6 BSP 的 VIP2 代码在 `CONFIG_DEBUG_FS=n` 时编不过
（`label 'flush_buffer' used but not defined`、`clk_freq_show undeclared`），
`NPU_SET_CLK_VOL` 打开时钟/电压的 sysfs 节点。

上板验证：

```bash
ls /dev/vipcore            # 或 /dev/vip
dmesg | grep -i vip        # vipcore probe 日志
cat /sys/kernel/debug/vip/...   # DEBUG_FS 打开后能看到频率等
```

`./bsp hal` 在 `A733_WITH_NPU=y` 时会多检查一项：dtb 里的 `npu@3600000` 节点。

## 还缺什么（重要）

内核驱动只是第一步，**用户态 runtime 不在 Debian 里**：

- Allwinner 的 NPU 软件栈（Acuity Toolkit / `libvip` / `awnn`）是厂商 SDK 的一部分，
  需要把对应的 `libvip.so`、`/usr/bin` 工具和模型转换后的 `.nb` 文件放进 rootfs；
- 没有这套 runtime，`/dev/vipcore` 只能做底层 ioctl 测试，跑不了模型；
- 模型要先在 PC 上用 Acuity 量化/转换（ONNX → `.nb`），再拷到板子上。

## 体积影响

- VIP 驱动编进 Image（`=y`）：预计 Image 增加几 MB（编译产物在
  `bsp/drivers/npu/aw_nna_vip/vip2/`，源码 2.5 MB）；
- 如果改 `=m`，模块本身约 1–2 MB，但要注意 `MICRODUCK_MIN_MODULES` 的裁剪规则
  不碰 `npu` 路径，不会被误删；
- galcore（28 MB 源码）体积更大，默认不选。

## 已验证 / 未验证

- 已验证（本机 6.6 内核树）：
  - 配置解析正确（`AW_NNA_VIP=y`、`NNA_VIP2=y`、`DEBUG_FS=y`、`NPU_SET_CLK_VOL=y`）；
  - `bsp/drivers/npu/` 在 VIP2 与 VIP1 两种选择下都能编译通过；
  - vip2 在缺 `DEBUG_FS`/`NPU_SET_CLK_VOL` 时会报上面那两处错误。
- 未验证：上板 probe、`/dev/vipcore` 实际推理（缺用户态 runtime）。

## 建议

- 产品不用 NPU：保持默认（不开），镜像最小；
- 要用 NPU：先向 Radxa/Allwinner 要 A733 的 NPU runtime 包（libvip + Acuity 输出），
  再开 `A733_WITH_NPU=y`；如果 runtime 只支持 galcore，就把 fragment 换成
  `CONFIG_AW_NNA_GALCORE=y` 并关掉 VIP（两者不能同时 probe 同一个 DT 节点）。
