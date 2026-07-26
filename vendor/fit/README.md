# FIT boot.img

`boot.its` 描述 FIT 内容：

- **kernel** — `out/kernel/Image`
- **fdt** — `out/kernel/<dts>.dtb`
- **resource** — `out/kernel/resource.img`（`resource_tool` 由 dtb + 可选 logo 生成）

打包：`./bsp bootimg` → `out/boot.img`

未启用 AVB 签名（无 `signature` 节点），适用于开发板常规启动。
