# 一加 7 Pro (T-Mobile GM1915) Bootloader 解锁完整方案

> **English version: [README.md](README.md)**

**适用机型**：OnePlus 7 Pro T-Mobile 版（`GM1915`，代号 `guacamole`）
**目标**：绕过 T-Mobile 运营商锁，让 `fastboot flashing unlock` 成功执行
**验证环境**：Windows 10/11 + 一加 7 Pro GM1915（已变种为国际版）

---

## 目录

- [0. 这个方案解决什么问题](#0-这个方案解决什么问题)
- [1. 原理（为什么能成）](#1-原理为什么能成)
- [2. 前置条件](#2-前置条件)
- [3. 完整流程](#3-完整流程)
- [4. 验证解锁是否成功](#4-验证解锁是否成功)
- [5. 常见问题](#5-常见问题)
- [6. 技术细节](#6-技术细节)
- [7. 文件清单](#7-文件清单)
- [8. 鸣谢与免责](#8-鸣谢与免责)

---

## 0. 这个方案解决什么问题

T-Mobile 版一加 7 Pro（GM1915）有一道**运营商锁**，导致：

```
设置 → 开发者选项 → OEM 解锁     ← 灰色，点不动
fastboot flashing unlock         → FAILED (remote: 'Flashing Unlock is not allowed')
fastboot oem unlock              → FAILED
```

即使刷了国际版固件、`ro.boot.opcarrier` 已变成 `none`，**这个开关依然是灰的** —— 因为它由底层 **FRP（持久化数据块）分区**里的一个**字节**控制，固件层改不动它。

**本方案的做法**：直接在 MSM 救砖包（`.ops`）里，把那个字节改成 `1`，然后刷回去。

刷完之后：

| 表现 | 状态 |
|---|---|
| `sys.oem_unlock_allowed` | `1` ✅ |
| `fastboot flashing get_unlock_ability` | `1` ✅ |
| 开发者选项里的 OEM 解锁开关 | **仍是灰色，但处于【开启】状态** ← 正常现象 |
| `fastboot flashing unlock` | **OKAY** ✅ |

> ⚠️ **开关"灰但开着"是正常的** —— 灰色来自运营商检查（UI 层），标志位来自 FRP（底层）。**bootloader 只看标志位，不看 UI。**

---

## 1. 原理（为什么能成）

### 1.1 三个关键事实

**① MSM 救砖包会刷写 `config` 分区**

MSM 工具的日志里明确列出：

```
[2] Downloading rawprogram0 Label: config FileName: config.bin
[2] Readback Sha256 verify ok, config.bin
```

**② `config` 分区就是 Android 的持久化数据块**

```
$ adb shell getprop ro.frp.pst
/dev/block/bootdevice/by-name/config
```

**③ bootloader 从该分区最后一个字节读取 OEM 解锁位**

AOSP 源码 `PersistentDataBlockService.java` 里的布局：

```
| ---------BEGINNING OF PARTITION-------------|
| Partition digest (32 bytes)                 |
| PARTITION_TYPE_MARKER (4 bytes)  = 0x19901873
| FRP data block length (4 bytes)             |
| FRP data (variable length)                  |
| Test mode data block (10000 bytes)          |
| FRP credential handle block (1000 bytes)    |
| OEM Unlock bit (1 byte)          ← ★ 就是它
| --------------------------------------------|
```

读取代码（AOSP）：

```java
private boolean doGetOemUnlockEnabled() {
    inputStream.skip(getBlockDeviceSize() - 1);   // 跳到分区最后一个字节
    return inputStream.readByte() != 0;           // 非零 = 已启用
}
```

### 1.2 为什么改 `config` 不会变砖

**`config` 分区不在 AVB（Android Verified Boot）校验范围内。** 它既不参与 dm-verity，也不在 `vbmeta` 的哈希链里 —— 它本来就是设计成"可以随时被系统和 bootloader 改写的状态区"。

所以改它**不会触发 verified boot 失败**，也不会变砖。

### 1.3 为什么必须"重打包"而不是"原地改"

`.ops` 是个**混合容器**：

| 内容 | 存储方式 |
|---|---|
| `prog_firehose_*.elf`（编程器） | **加密** |
| `settings.xml`（索引表） | **加密** |
| 各分区镜像（`config.bin`、`system.img`…） | **明文** |

`config.bin` 虽然是明文（理论上能原地改），**但 `settings.xml` 里记录了它的 SHA256，MSM 工具会校验**（`SkipImgSHA256Check="false"`）。

而 `settings.xml` 是加密的 → **必须解包 → 改两个地方 → 重打包**。

---

## 2. 前置条件

### 2.1 硬件 / 软件

- 一加 7 Pro T-Mobile 版（`GM1915`）
- Windows 10/11 电脑
- 原装数据线，**直插主板 USB 口**（不要用 Hub —— EDL 对 USB 链路非常敏感）
- Python 3.8+

### 2.2 需要的文件

| 文件 | 说明 | 获取方式 |
|---|---|---|
| **MSM 救砖包** `.ops` | 推荐 T-Mobile 变种包<br>`Conversion_Tool_To_9.5.6.GM21AA.zip`<br>内含 `guacamole_21.O.09_190516.ops` | 一加社区服务器<br>`onepluscommunityserver.com` |
| **MSM 工具** | 免登录的 Patched 版<br>`MsmDownloadTool+V4.0-Patched_Alpha_3.exe` | 同上（在转换包内） |
| **oppo_decrypt** | `.ops` 解密/重打包工具 | `github.com/bkerler/oppo_decrypt` |
| **Qualcomm 9008 驱动** | `qcser.inf` 等 | 一加官方驱动包 |
| **Google USB 驱动** | 用于 fastboot（`VID_18D1&PID_D00D`） | Google 官方 |

### 2.3 环境准备

```powershell
# Python 依赖
pip install pycryptodome pycryptodomex docopt

# 下载 oppo_decrypt
curl -L -o oppo_decrypt.zip https://github.com/bkerler/oppo_decrypt/archive/refs/heads/master.zip
```

### 2.4 ⚠️ 重要警告

> **永远不要让这台手机做官方系统更新。**
>
> 部分 OPPO/一加 机型的系统更新会**永久熔断 EDL 免授权**（e-fuse），不可逆。本方案依赖 EDL，一旦熔断就再也刷不回去了。

---

## 3. 完整流程

### 步骤总览

```
① 变种为国际版（MSM 刷转换包）          ← 如果还没做
② 一路 OTA 升到 Android 12               ← 目的是让 OEM 解锁开关变成"可点"
③ 解包 .ops
④ 构造 FRP 块 + 打补丁 + 重打包          ← 本方案核心
⑤ MSM 刷入打过补丁的包
⑥ fastboot flashing unlock（手机上确认）
```

**为什么需要第 ② 步？** 因为 T-Mobile 原厂 Android 9 固件的运营商检查极其严格，连"开启"这个动作都做不了。升到国际版 Android 12 后，运营商检查放松，开关至少变成"可点"状态。

---

### 步骤 ① 变种为国际版

如果手机还是 T-Mobile 原厂固件，先用转换包刷成国际版：

```
1. 手机 → EDL 模式（关机后按住 音量上 + 音量下 + 电源 约 10-15 秒）
2. MSM 工具（Patched 版）→ Start
3. 刷入 guacamole_21.O.09_190516.ops
```

> 💡 **EDL 小技巧**：如果 `adb reboot edl` 可用就用它，比按键组合可靠。EDL 会话大约 1 分钟后会超时，所以**先让工具点 Start 处于等待状态，再送手机进 EDL**。

---

### 步骤 ② 升级到 Android 12

用手机自带的 OTA 本地升级（不需要解锁 bootloader）：

```
1. 把官方 OTA 包放到手机内置存储根目录
2. 设置 → 系统更新 → 右上角齿轮 → 本地升级
3. 选择那个 zip → 立即安装
```

或者用 ADB 直接驱动（如果 `com.oneplus.opbackup` 还可用）：

```bash
adb shell am start -n com.oneplus.opbackup/.CheckUpdateActivity2
# 然后点：右上角齿轮 → 本地升级 → 选包 → 立即安装
```

---

### 步骤 ③④⑤⑥ 打补丁 + 刷入 + 解锁

**直接用本仓库的脚本：**

```powershell
.\scripts\patch-ops-for-unlock.ps1 -OpsPath "D:\fw\guacamole_21.O.09_190516.ops"
```

脚本会自动完成：

| 阶段 | 做什么 |
|---|---|
| 0/6 | 检查环境、Python 依赖 |
| 1/6 | 用 `opscrypto.py decrypt` 解包 `.ops` |
| 2/6 | **从 `settings.xml` 读取 `config.bin` 的真实偏移**，并用 SHA256 验证偏移正确性 |
| 3/6 | 构造合法的 FRP 块（含正确的 SHA256 摘要 + OEM 解锁位 = 1） |
| 4/6 | 替换 `config.bin`，**同步更新 `settings.xml` 里的 SHA256** |
| 5/6 | 用 `opscrypto.py encrypt` 重打包 |
| 6/6 | 验证新包（检查魔数和末字节） |

**然后刷入：**

```
1. 把新包 (_UNLOCK.ops) 放到一个干净目录，和 MSM 工具放一起
   ⚠️ 该目录里只能有一个 .ops，否则工具可能选错
2. 手机进 EDL
3. MSM 工具 → Start
4. 等 3-8 分钟刷完
5. 手机自动重启进系统
```

**最后解锁：**

```bash
adb reboot bootloader
fastboot flashing get_unlock_ability     # 应该显示 1
fastboot flashing unlock
```

> **⚠️ 关键**：`fastboot flashing unlock` 会在**手机屏幕上弹出确认界面**，需要你**按音量键选择、按电源键确认**。
> 命令返回 `OKAY` **只代表命令被接受**，还没真正执行 —— 必须在手机上确认！

---

## 4. 验证解锁是否成功

### 系统层（手机开机状态）

```bash
adb shell getprop sys.oem_unlock_allowed      # 期望: 1
```

### Bootloader 层（fastboot 模式）

```bash
fastboot getvar unlocked                      # 期望: unlocked: yes
fastboot oem device-info                      # 期望: Device unlocked: true
fastboot flashing get_unlock_ability          # 期望: 1
```

### 解锁后的系统属性

```bash
adb shell getprop ro.boot.flash.locked        # 期望: 0
adb shell getprop ro.boot.verifiedbootstate   # 期望: orange
```

**`verifiedbootstate = orange`** 是解锁后的标志性状态（黄色警告屏）。

---

## 5. 常见问题

### Q1: 刷完 `sys.oem_unlock_allowed` 还是 0

**A**：八成是偏移算错了。检查：

1. `settings.xml` 里 `config.bin` 的 `FileOffsetInSrc` 是多少？
2. 乘 512 得到的字节偏移，读出来的数据 SHA256 **是否等于** `settings.xml` 里记录的 `Sha256`？

**如果 SHA256 对不上，说明偏移错了，补丁打到了别的地方。**

> 我们的踩坑记录：一开始靠"GPT 分区表 + 镜像顺序"推算偏移，得到 36,004,864 —— **错了 3.5 MB**，实际打进了 `param.bin`。
> **教训：不要推算，直接读 `settings.xml`。**

### Q2: MSM 工具报 "Load profile failed / 读取配置文件失败"

**A**：包和工具版本不匹配。

- 2019 年的 Patched 工具（V4.0.88）读不了 2021+ 的包
- 2022 年的工厂版工具（V5.1.70）需要登录

**配对参考**：

| 工具版本 | 能读的包 |
|---|---|
| V4.0.88（Patched，免登录） | ≤ 2019 年的包 |
| V5.0.15（免登录） | 2021 年的包 |
| V5.1.70（要登录） | 2022 年的包 |

### Q3: MSM 工具报 "映像与装置不匹配"

**A**：包的项目号和设备的硬件项目号不匹配。

MSM 工具通过 Firehose 读取**硬件 PCBA 参数**来校验，改软件属性（`ro.boot.prj_version`）无效。

**查看方法**：MSM 工具窗口顶部会显示 `项目: xxxxx`
**设备项目号**：从日志里的 `project xxxxx` 或 `Get Param PCBA` 看

T-Mobile 变种包是 **18831**，国际版包是 **18821** —— 所以重打包时 `--projid` 要对应填。

### Q4: `fastboot flashing unlock` 返回 OKAY 但设备还是锁着

**A**：**需要在手机上确认！**

一加/高通设备执行解锁时会在屏幕上弹出确认界面。命令返回 OKAY 只表示"命令被接受"，实际执行要等你按音量键选择、电源键确认。

### Q5: Android 12 上 `get_unlock_ability = 1` 但解锁还是失败

**A**：这是**一加在 Android 12 引入的 bootloader bug**。

```
FAILED (remote: 'Device cannot be unlocked for technical reason.')
```

**唯一解法：回滚到 Android 11 或更早**，用那个版本的 bootloader。

- 降级包：`OnePlus7ProOxygen_21.E.41_OTA_0410_all_2112101752_downgrade_*.zip`
- 官方地址：`https://s3.amazonaws.com/oxygenos.oneplus.net/`
- 用 OTA 本地升级刷入

> 而 Android 9 的 bootloader **没有**这个 bug，报错是标准的 `Flashing Unlock is not allowed` —— 意思是"标志位是 0"，而不是"技术原因拒绝"。

### Q6: EDL 通信失败 / Sahara 握手超时

**A**：三个原因，按顺序排查：

1. **USB 口不稳** —— 拔掉 Hub，直插主板后置 USB 2.0 口（**黑色**那个，不是蓝色）
2. **EDL 会话超时** —— 必须先让工具 Start 等待，再送手机进 EDL，中间只隔几秒
3. **手机在 EDL 里待太久** —— 会话失效，断电重启再试

---

## 6. 技术细节

### 6.1 `.ops` 文件结构

```
偏移 0                    ← 加密的文件头
偏移 A                    ← 明文镜像区（按 settings.xml 的 FileOffsetInSrc 排布）
                            prog_firehose_*.elf   ← 加密
                            persist.img / param.bin / config.bin / system.img ...  ← 明文
偏移 B                    ← 加密的 settings.xml（索引表）+ 校验信息
```

**偏移单位**：`FileOffsetInSrc` 的单位是 **512 字节扇区**（源码里 `× 0x200`）。

### 6.2 `settings.xml` 关键字段

```xml
<BasicInfo Project="18821" TargetName="SM8105"
           CheckHwVersion="true" CheckProjectVersion="true"
           SkipImgSHA256Check="false" />

<SAHARA>
  <File Id="13" isLite="false" Path="prog_firehose_ddr.elf"
        FileOffsetInSrc="0" SizeInByteInSrc="727232" />
  <File Id="13" isLite="true"  Path="prog_firehose_lite.elf"
        FileOffsetInSrc="1421" SizeInByteInSrc="727168" />
</SAHARA>

<Program0>
  <program filename="config.bin" label="config"
           num_partition_sectors="128" size_in_KB="512.0"
           start_sector="80136"
           FileOffsetInSrc="77095" SizeInByteInSrc="524288"
           Sha256="07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541" />
  ...
</Program0>
```

**`FileOffsetInSrc="77095"` × 512 = `39472640`** ← 这就是 `config.bin` 在包里的真实位置。

### 6.3 FRP 块的构造算法

```python
size = 524288                        # config 分区大小
block = bytearray(size)              # 全零

# 1) 魔数（小端）
block[32:36] = bytes([0x73, 0x18, 0x90, 0x19])   # 0x19901873

# 2) FRP 数据长度 = 0
block[36:40] = bytes([0, 0, 0, 0])

# 3) ★ OEM 解锁位 = 1（分区最后一个字节）
block[size-1] = 1

# 4) 摘要 = SHA256( 32 个零字节 ‖ block[32:] )
#    ★ 注意前面要拼 32 个零字节 —— AOSP 源码里是
#      md.update(data, 0, DIGEST_SIZE_BYTES)  // data 是新建的零数组
import hashlib
digest_input = bytes(32) + bytes(block[32:])
block[0:32] = hashlib.sha256(digest_input).digest()
```

> **⚠️ 最容易踩的坑**：摘要输入要**先拼 32 个零字节**。
> 直接算 `SHA256(block[32:])` 是**错的** —— 系统会判定块无效并重新格式化（标志位被清零）。

这个算法在 Android 9 / 10 / 11 上完全一致（已比对四个版本的 AOSP 源码）。

### 6.4 完整的 MSM 刷写分区清单

MSM 包会刷 53 个分区，**这些都在其中**：

```
✅ 会刷（可被我们影响）
   config            ← ★ 我们的目标
   op2 / oem_stanvbk / system_a / odm_a / metadata / userdata
   xbl_a / xbl_config_a / aop_a / tz_a / hyp_a / modem_a
   bluetooth_a / abl_a / dsp_a / keymaster_a / boot_a
   cmnlib_a / cmnlib64_a / devcfg_a / qupfw_a / vendor_a
   vbmeta_a / dtbo_a / uefi_sec* / imagefv* / LOGO_a
   fw_ufs1/2 / multiimgoem_a / aging / aging_mod
   apdp / msadp / logfs / storsec_a / secdata / reserve2
   PrimaryGPT / BackupGPT (6 个 LUN)

❌ 不刷（所以这些数据会保留）
   devinfo       ← Qualcomm 的 bootloader 标志
   frp           ← 独立的 FRP 分区
   persist       ← 传感器校准
   modemst1/2    ← SIM 网络锁
   ocdt          ← OnePlus 配置数据
```

**这就是为什么改 `config` 有效**：它是唯一一个"既被刷写、又存着解锁标志、又不受 AVB 保护"的分区。

### 6.5 完整时间线（我们的实测记录）

```
T+0      手机：T-Mobile GM1915，Android 9，OEM 开关灰色
T+1      MSM 刷转换包（项目 18831）→ 国际版 Android 9
T+2      OTA 本地升级 → Android 12（H 分支，GM1917 标识）
T+3      ├─ OEM 解锁开关变成【可点】✓
         └─ 打开开关 → get_unlock_ability = 1 ✓
            但 fastboot flashing unlock 报 "technical reason" ✗
T+4      OTA 降级到 Android 11 → 报错变成标准的 "Flashing Unlock is not allowed"
T+5      MSM 刷回 Android 9 → 标志位被 config.bin（全零）重置为 0 ✗
T+6      解包 .ops，拿到 settings.xml 和 prog_firehose_ddr.elf
T+7      构造 FRP 块，改 config.bin，更新 settings.xml，重打包
T+8      MSM 刷入新包
         → sys.oem_unlock_allowed = 1 ★★★
         → OEM 开关【灰但开着】✓
T+9      fastboot flashing unlock → OKAY
         手机上按音量键确认 → ★★★ 解锁成功 ★★★
T+10     刷入 LineageOS 23.2 (Android 16) + MindTheGapps + Magisk 30.7
```

---

## 7. 文件清单

```
RELEASE-OnePlus7Pro-TMO-Unlock/
├── README.md                      中文文档（本文件）
├── README.md                   英文文档
├── bin/
│   ├── config_patched.bin         ★ 已构造好的 FRP 块（OEM 解锁位 = 1，512 KB）
│   │                                SHA256 fc7dde40d5f1392c83606c94d1c60f057e6d99a9d538298ec2e725a002534ee0
│   └── config_stock_allzero.bin   出厂原始状态（全零，512 KB）
│                                   SHA256 07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541
├── scripts/
│   ├── patch-ops-for-unlock.ps1   ★ 一体化补丁脚本（解包→改→重打包→验证）
│   └── verify-unlock.ps1          解锁状态验证脚本
├── tools/
│   ├── oppo_decrypt/              ★ .ops 解密/重打包工具（bkerler 开源，已内含）
│   │   ├── opscrypto.py              OnePlus .ops 解密 / 重打包
│   │   ├── ofp_qc_decrypt.py         OPPO .ofp（高通）解密
│   │   ├── ofp_mtk_decrypt.py        OPPO .ofp（联发科）解密
│   │   └── backdoor.py               开启 MSM 工具隐藏 readback
│   └── TOOL-SOURCES.md            需要自行下载的工具清单 + 来源
└── docs/
    ├── settings.xml.sample        从真实 .ops 解出的索引表样本（供参考字段格式）
    └── TECHNICAL.md               技术深挖（AOSP 源码引用、格式分析、踩坑记录）
```

> **注意**：`config_patched.bin` 是**通用**的（512 KB 的合法 FRP 块），
> 但**不同机型的 config 分区大小可能不同**，使用前请确认你的分区大小。
> 如果大小不同，请用 `patch-ops-for-unlock.ps1` 重新生成。

---

## 8. 鸣谢与免责

### 鸣谢

| 项目 | 作者 | 用途 |
|---|---|---|
| **oppo_decrypt** | [bkerler](https://github.com/bkerler/oppo_decrypt) | `.ops` 解密/重打包 |
| **MSM Download Tool** | OnePlus / Qualcomm | EDL 刷写 |
| **AOSP** | Google | 持久化数据块格式（`PersistentDataBlockService.java`） |
| **LineageOS** | LineageOS 团队 | 系统 |
| **MindTheGapps** | MindTheGapps 团队 | Google 服务 |
| **Magisk** | [topjohnwu](https://github.com/topjohnwu/Magisk) | root |

### 免责声明

- **本方案仅用于你有权修改的、自己拥有的设备。**
- 刷机有风险，**变砖自负**。请务必先完整备份数据。
- 部分机型的系统更新会**永久熔断 EDL 免授权**，操作前请确认。
- 本方案涉及修改固件包，可能违反设备的保修条款或运营商协议，请自行评估。

### 已知适用范围

- ✅ 实测通过：OnePlus 7 Pro T-Mobile `GM1915`（本项目）
- ⚠️ 理论适用：其它用 `.ops` 格式 + FRP 持久化数据块的 OPPO/一加/真我 高通机型
- ❌ 不适用：用 `.ofp` 格式的机型需改用 `ofp_qc_decrypt.py`；联发科平台不适用

**欢迎在评论区反馈你的机型和结果。**

---

*最后更新：2026-10-11*
