# NPU（VeriSilicon VIPLite）：驱动 + 用户态 + 冒烟测试

参考：[jackhe183/radxa-dev](https://github.com/jackhe183/radxa-dev)（A7Z NPU 实战指南）。
A733 的 NPU 是 **VeriSilicon VIPLite（3 TOPS）**，驱动节点是 **`/dev/vipcore`**
（不是 `/dev/galcore`、也不是 RKNN）。

## 一、内核驱动

DT 里 `npu@3600000`（`compatible = "allwinner,npu"`，board.dts 里 `npu-supply` 和
`status = "okay"` 都有），但 BSP 驱动默认是关的：

| 配置 | 作用 |
|---|---|
| `CONFIG_AW_NNA_VIP=y` | VIPLite 驱动（`aw_nna_vip`） |
| `CONFIG_NNA_VIP2=y` | A733 用 vip2（驱动里有 `sun60iw2` 分支） |
| `CONFIG_DEBUG_FS=y` | vip2 的 debugfs 代码必需，否则编不过 |
| `CONFIG_NPU_SET_CLK_VOL=y` | 时钟/电压 sysfs 节点 |
| `# CONFIG_AW_NNA_GALCORE is not set` | 另一套（Vivante），和 VIP 抢同一个 DT 节点 |

`./bsp kernel` 在 `A733_WITH_NPU=y`（默认）时自动追加这几行。实测全量 Image
38,482,432 字节，比不开 NPU 多约 0.7 MB。

## 二、用户态 runtime（VIPLite + vpm_run）

`vendor/a733/npu/fetch-runtime.sh` 会：

1. sparse 克隆 `jackhe183/radxa-dev`（`A733_NPU_SDK_REPO` 可换），只取
   `npu_test/ai-sdk/{viplite-tina,examples/vpm_run,machinfo}`；
2. 用 `aarch64-linux-gnu-gcc` 交叉编译 `vpm_run`
   （`make AI_SDK_PLATFORM=a733 NPU_SW_VERSION=v2.0`）；
3. 把 `libNBGlinker.so`、`libVIPhal.so`、`vpm_run`、LeNet 样例（`.nb` + `.dat`）
   stage 到一个目录。

`./bsp rootfs` 在 `A733_WITH_NPU=y && A733_NPU_RUNTIME=y`（都是默认）时把它们装进镜像：

```
/usr/lib/viplite/libNBGlinker.so   (171 KB)
/usr/lib/viplite/libVIPhal.so      ( 39 KB)
/usr/bin/vpm_run                   ( 85 KB，strip 后)
/usr/share/npu/lenet.nb            (434 KB)
/usr/share/npu/lenet.dat
/usr/share/npu/sample_lenet.txt
/etc/profile.d/viplite.sh          # LD_LIBRARY_PATH=/usr/lib/viplite
/usr/sbin/microduck-npu            # 冒烟测试脚本
```

合计约 0.7 MB。拉不到 SDK 时只 warn，镜像仍能启动（有 `/dev/vipcore`，没有 `vpm_run`）。

## 三、验证

板端：

```bash
ls -l /dev/vipcore          # crw-rw-rw-
microduck-npu               # 跑 LeNet，打印 Top5
# 或手动：
export LD_LIBRARY_PATH=/usr/lib/viplite
cd /usr/share/npu && vpm_run -s sample_lenet.txt -l 1 --show_top5 1 -b 0
```

预期看到 `VIPLite driver software version 2.0.x`，`run time ... us`，Top5 里
`0: 1.000000`（手写数字 1）。

本机已验证（qemu 无 NPU）：

- `vpm_run` 能加载 VIPLite 库并打印版本，然后在 `open /dev/vipcore` 处失败——
  说明用户态链路 OK，缺的只是板上的驱动/节点；
- 内核配置与 `bsp/drivers/npu/` 编译通过（VIP2 选择），无 `DEBUG_FS` 时复现过
  `flush_buffer` / `clk_freq_show` 编译错误。

## 四、跑自己的模型

1. PC 上用 **Acuity Toolkit**（Allwinner 的 Docker 镜像）把 ONNX 转成 `.nb`；
2. 模型按 vpm_run 的 `[network]` / `[input]` 配置格式写一个 txt；
3. 拷到板子，`vpm_run -s your.txt -l 1 --show_top5 1 -b 0`。

换模型只涉及 `.nb` + 输入数据 + 配置，不需要重编内核。

## 五、开关

```bash
A733_WITH_NPU=n ./bsp kernel        # 不要 NPU 驱动
A733_NPU_RUNTIME=n ./bsp rootfs     # 只要驱动，不装 vpm_run
```

两处都关掉时，镜像回到之前的纯 CPU 版本。
