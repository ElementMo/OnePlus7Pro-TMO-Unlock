# 第三方工具来源 / Third-party tool sources

本目录下的工具均为第三方开源项目，版权归原作者所有。
Tools in this directory are third-party open-source projects; all rights belong to their original authors.

---

## tools/oppo_decrypt/

**项目 / Project**: [bkerler/oppo_decrypt](https://github.com/bkerler/oppo_decrypt)
**用途 / Purpose**: OnePlus `.ops` 固件包的解密与重打包 / decrypt & repack OnePlus `.ops` packages
**作者授权 / License note**: 原作者声明 "Share, modify and use as you like, but refer the original author!"

```
opscrypto.py            OnePlus .ops 解密/重打包 / decrypt & repack
ofp_qc_decrypt.py       OPPO .ofp（高通平台）解密 / decrypt .ofp (Qualcomm)
ofp_mtk_decrypt.py      OPPO .ofp（联发科平台）解密 / decrypt .ofp (MediaTek)
backdoor.py             开启 MSM 工具的隐藏 readback 功能 / enable hidden readback in the MSM tool
```

**依赖 / Dependencies**:
```bash
pip install pycryptodome pycryptodomex docopt
```

---

## 需要自行下载的工具 / Tools you must obtain yourself

以下工具**未包含**在本包中（体积较大或为厂商专有），请从官方渠道获取。
The following tools are **NOT** bundled (large, or vendor-proprietary). Get them from official sources.

### 1. MSM Download Tool（EDL 刷写工具）

| 版本 | 特点 | 适用 |
|---|---|---|
| `MsmDownloadTool+V4.0-Patched_Alpha_3.exe` | V4.0.88，**免登录** | ≤ 2019 年的 .ops 包 |
| `MsmDownloadTool V4.0.exe`（V5.0.15） | **免登录** | 2021 年的 .ops 包 |

**获取 / Where**: 一加社区服务器
`https://onepluscommunityserver.com/list/Unbrick_Tools/OnePlus_7_Pro/`

推荐用 **T-Mobile 转换包**（内含免登录的 Patched 工具 + 项目号 18831 的 .ops）：
```
T-Mobile_GM31CB/Conversion_Tool/Conversion_Tool_To_9.5.6.GM21AA.zip
```

### 2. 高通 9008 驱动 / Qualcomm 9008 driver

一加官方驱动包，或任何包含 `qcser.inf` 的 Qualcomm 驱动。
OnePlus official driver package, or any Qualcomm driver containing `qcser.inf`.

必须支持：`USB\VID_05C6&PID_9008`（Qualcomm HS-USB QDLoader 9008）
Must support: `USB\VID_05C6&PID_9008`

### 3. Google USB Driver（fastboot 用）

用于 `USB\VID_18D1&PID_D00D`（Android Bootloader Interface）。
For `USB\VID_18D1&PID_D00D` (Android Bootloader Interface).

> 💡 如果 `android_winusb.inf` 里没有 `D00D` 条目，可以手动加两行再安装。
> 必要时需要在"禁用驱动程序强制签名"的 Windows 启动会话里安装。

### 4. 可选：LineageOS / Magisk

- LineageOS: https://download.lineageos.org/guacamole
- Magisk: https://github.com/topjohnwu/Magisk/releases

---

## 校验值 / Checksums

本包内所有文件的 SHA256 见 zip 内 `CHECKSUMS.txt`（如有）或自行计算。
See `CHECKSUMS.txt` inside the zip, or compute them yourself.