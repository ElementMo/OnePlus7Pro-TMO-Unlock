# Disclaimer & Third-Party Notices

## Flashing risk

This project modifies firmware packages and instructs the user to flash a
device via Qualcomm EDL (Emergency Download mode).

**Flashing carries a real risk of rendering a device unbootable ("hard brick").**

On some OPPO / OnePlus models, official system updates **permanently blow the
EDL no-auth fuse**. This is irreversible. This method depends on EDL — once
fused, you can never flash the device back.

**USE AT YOUR OWN RISK.** The author accepts no liability for damaged or
bricked devices, lost data, voided warranties, or violated carrier agreements.

Before you start:

- Back up everything you care about.
- Confirm your device model and the `config` partition size.
- Check whether your model fuses EDL on system updates.
- Make sure you are authorized to modify the device you are working on.

---

## 免责声明（中文）

本项目会修改固件包，并指导用户通过高通 EDL（Emergency Download）模式刷写设备。

**刷机存在真实的"硬砖"风险。**

部分 OPPO / 一加 机型的官方系统更新会**永久熔断 EDL 免授权**，不可逆。
本方案依赖 EDL —— 一旦熔断，设备就再也刷不回来了。

**使用风险自负。** 作者不对设备损坏、变砖、数据丢失、保修失效或违反运营商协议承担任何责任。

开始之前请确认：

- 备份所有重要数据
- 确认设备型号和 `config` 分区大小
- 确认你的机型是否会在系统更新时熔断 EDL
- 确认你有权修改手上的这台设备

---

## Third-party components / 第三方组件

This repository **does not bundle** third-party tools. It downloads or
references them. All rights belong to their respective authors.

本仓库**不内嵌**第三方工具，只做下载或引用。版权归各自作者所有。

| Component | Author | License / Notes |
|---|---|---|
| [oppo_decrypt](https://github.com/bkerler/oppo_decrypt) | [bkerler](https://github.com/bkerler) | Author states: *"Share, modify and use as you like, but refer the original author!"* |
| MSM Download Tool | OnePlus / Qualcomm | Proprietary — **not redistributed** here |
| `PersistentDataBlockService.java` | AOSP | Apache-2.0 |
| Qualcomm 9008 / Google USB drivers | Qualcomm / Google | Vendor-supplied — **not redistributed** here |

### What IS included in this repository

- `bin/config_patched.bin` — a 512 KB block constructed from scratch following
  the AOSP persistent data block specification. No vendor data.
- `bin/config_stock_allzero.bin` — 512 KB of zeros (the factory state).
- `docs/settings.xml.sample` — an index file extracted from a publicly
  distributed OnePlus MSM package, included for **field-format reference only**.
  It contains no user data, no credentials, and no signing keys.

---

## Credits

| Project | Author | Role |
|---|---|---|
| [oppo_decrypt](https://github.com/bkerler/oppo_decrypt) | bkerler | `.ops` decrypt / repack |
| AOSP | Google | the persistent data block format |
| [LineageOS](https://lineageos.org/) | LineageOS team | the OS |
| [MindTheGapps](https://wiki.lineageos.org/gapps/) | MindTheGapps team | Google apps |
| [Magisk](https://github.com/topjohnwu/Magisk) | topjohnwu | root |
| [CSDN writeup](https://blog.csdn.net/2301_80127209/article/details/133791777) | muhe | earliest article extracting the firehose programmer from a OnePlus `.ops` |