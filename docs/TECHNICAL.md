# 技术深挖 / Technical Deep Dive

一加 7 Pro T-Mobile 解锁方案的完整技术分析。
Full technical analysis of the OnePlus 7 Pro T-Mobile unlock method.

---

## 1. 问题的本质 / The nature of the problem

### 1.1 两道独立的锁 / Two independent locks

T-Mobile 版一加 7 Pro 有两道锁，**互不相关**，很容易混淆：

| | 运营商锁 / Carrier lock | Bootloader 锁 / Bootloader lock |
|---|---|---|
| **管什么** | 能不能用别家运营商的 SIM | 能不能刷第三方固件 |
| **存在哪** | `modemst1/2` + `ocdt` + 运营商标记 | `config`（持久化数据块）+ `devinfo` |
| **谁执行** | 基带 + 运营商配置 | bootloader（ABL）|
| **本方案** | 顺带解决 | **主要目标** |

**关键**：刷国际版固件能改运营商配置，但**改不了 bootloader 的解锁标志位** —— 那在 `config` 分区里。

### 1.2 为什么固件层的改动无效

```
Android 系统 → 写 config 分区 → bootloader 读 config 分区
                    ↑
              唯一的通道，而且必须写入【合法的】数据块
```

- **只能通过系统写入** → 需要 UI 开关可点 → 但开关被运营商检查灰掉了
- **`config` 分区被 MSM 包刷写** → 每次从 MSM 刷机都会重置

**死循环**：想解锁 → 需要设标志位 → 需要 UI 开关 → UI 开关被锁 → 想解锁……

**破局点**：直接从 MSM 包里改 `config.bin`，绕过整个系统层。

---

## 2. AOSP 持久化数据块格式 / AOSP persistent data block format

### 2.1 源码位置 / Source

```
frameworks/base/services/core/java/com/android/server/PersistentDataBlockService.java
```

### 2.2 完整布局 / Full layout

```
| ---------BEGINNING OF PARTITION-------------|
| Partition digest (32 bytes)                 |
| --------------------------------------------|
| PARTITION_TYPE_MARKER (4 bytes)             |
| --------------------------------------------|
| FRP data block length (4 bytes)             |
| --------------------------------------------|
| FRP data (variable length)                  |
| | ...                                       |
| --------------------------------------------|
| Test mode data block (10000 bytes)          |
| --------------------------------------------|
|     | Test mode data length (4 bytes)       |
| --------------------------------------------|
|     | Test mode data (variable length)      |
| --------------------------------------------|
| FRP credential handle block (1000 bytes)    |
| --------------------------------------------|
|     | FRP credential handle length (4 bytes)|
| --------------------------------------------|
|     | FRP credential data (variable length) |
| --------------------------------------------|
| OEM Unlock bit (1 byte)                     |  ← ★★★
| --------------------------------------------|
```

### 2.3 常量 / Constants

```java
private static final int HEADER_SIZE = 8;                      // marker(4) + data_len(4)
private static final int PARTITION_TYPE_MARKER = 0x19901873;
public  static final int DIGEST_SIZE_BYTES = 32;
private static final int FRP_CREDENTIAL_RESERVED_SIZE = 1000;
private static final int MAX_FRP_CREDENTIAL_HANDLE_SIZE = 996;
private static final int TEST_MODE_RESERVED_SIZE = 10000;
private static final int MAX_TEST_MODE_DATA_SIZE = 9996;
private static final int MAX_DATA_BLOCK_SIZE = 1024 * 100;     // 102400
private static final String OEM_UNLOCK_PROP = "sys.oem_unlock_allowed";
private static final String PERSISTENT_DATA_BLOCK_PROP = "ro.frp.pst";
```

### 2.4 读取 OEM 解锁位 / Reading the unlock bit

```java
private boolean doGetOemUnlockEnabled() {
    DataInputStream inputStream;
    try {
        inputStream = new DataInputStream(new FileInputStream(new File(mDataBlockFile)));
    } catch (FileNotFoundException e) {
        Slog.e(TAG, "partition not available");
        return false;                                   // 分区打不开 = 未启用
    }
    try {
        synchronized (mLock) {
            inputStream.skip(getBlockDeviceSize() - 1);  // ★ 跳到分区最后一个字节
            return inputStream.readByte() != 0;          // ★ 非零 = 已启用
        }
    } ...
}
```

**→ 解锁位 = `config` 分区的第 `size-1` 个字节。**

### 2.5 写入 OEM 解锁位 / Writing it

```java
private void doSetOemUnlockEnabledLocked(boolean enabled) {
    ...
    FileChannel channel = outputStream.getChannel();
    channel.position(getBlockDeviceSize() - 1);          // ★ 定位到最后一个字节
    ByteBuffer data = ByteBuffer.allocate(1);
    data.put(enabled ? (byte) 1 : (byte) 0);
    data.flip();
    channel.write(data);
    outputStream.flush();
    ...
    SystemProperties.set(OEM_UNLOCK_PROP, enabled ? "1" : "0");
}
```

### 2.6 摘要算法 / The digest — **最容易错的地方**

```java
private byte[] computeDigestLocked(byte[] storedDigest) {
    ...
    if (storedDigest != null && storedDigest.length == DIGEST_SIZE_BYTES) {
        inputStream.read(storedDigest);                  // 跳过前 32 字节
    } else {
        inputStream.skipBytes(DIGEST_SIZE_BYTES);
    }

    int read;
    byte[] data = new byte[1024];                        // ★ 全新数组 = 全零
    md.update(data, 0, DIGEST_SIZE_BYTES);               // ★★★ 先喂进 32 个零字节！
    while ((read = inputStream.read(data)) != -1) {
        md.update(data, 0, read);                        // 再喂 [32:] 的剩余内容
    }
    return md.digest();
}
```

**★★★ 摘要 = `SHA256( 32个零字节 ‖ 分区[32:] )`**

**不是** `SHA256(分区[32:])`！少了那 32 个零字节，摘要就错了。

### 2.7 无效块的后果 / Consequence of an invalid block

```java
private void enforceChecksumValidity() {
    ...
    byte[] storedDigest = new byte[DIGEST_SIZE_BYTES];
    byte[] digest = computeDigestLocked(storedDigest);
    if (digest == null || !Arrays.equals(storedDigest, digest)) {
        // 摘要不匹配 → 重新格式化，把 OEM 解锁位清成 0
        formatPartitionLocked(false);                    // ★ 标志位被清零！
    }
    ...
}
```

**→ 摘要算错 = 白干**（系统启动时会静默把你的补丁清掉）。

### 2.8 格式的版本一致性 / Version consistency

我们比对了四个 AOSP 分支的源码：

| 分支 | `md.update(data, 0, DIGEST_SIZE_BYTES)` |
|---|---|
| `android-9.0.0_r1` | ✅ 有 |
| `android-9.0.0_r61` | ✅ 有 |
| `android-10.0.0_r47` | ✅ 有 |
| `android11-release` | ✅ 有 |

**四个版本完全一致** —— 所以本方案在 Android 9 / 10 / 11 / 12 上都适用。

---

## 3. `.ops` 容器格式 / The `.ops` container

### 3.1 整体结构 / Overall structure

```
┌─────────────────────────────────────────────┐
│ 加密文件头 / Encrypted header                │
│   MagicNumber / MetadataVersion / CryptVersion
│   ProfileFirstSector / profilesize           │
│   m_bIsPackImage                             │
├─────────────────────────────────────────────┤
│ 明文镜像区 / Plaintext image region          │
│   prog_firehose_ddr.elf      ← 加密 / encrypted
│   prog_firehose_lite.elf     ← 加密 / encrypted
│   provision_*.xml            ← 明文 / plaintext
│   persist.img                ← 明文
│   param.bin                  ← 明文
│   op2.img                    ← 明文
│   dynamic_nvbk.bin           ← 明文
│   static_nvbk.bin            ← 明文
│   config.bin                 ← ★ 明文！/ PLAINTEXT
│   system.img / odm.img / ... ← 明文
│   gpt_main*.bin / gpt_backup* ← 明文
│   xbl.elf / tz.mbn / ...    ← 明文
├─────────────────────────────────────────────┤
│ 加密索引区 / Encrypted index region          │
│   settings.xml               ← 加密 / encrypted
│   校验信息 / checksums                       │
└─────────────────────────────────────────────┘
```

### 3.2 为什么必须重打包 / Why repacking is mandatory

`config.bin` 是明文（可以原地改），**但**：

1. `settings.xml` 里记录了它的 SHA256
2. MSM 工具的 `SkipImgSHA256Check="false"` → **会校验**
3. `settings.xml` 在**加密区**

**→ 必须完整解包 → 改两处 → 重打包。**

### 3.3 偏移单位 / Offset units

`opscrypto.py` 源码：

```python
start = int(item.attrib["FileOffsetInSrc"]) * 0x200        # × 512
length = int(item.attrib["SizeInByteInSrc"])
```

**`FileOffsetInSrc` 的单位是 512 字节扇区。**

### 3.4 加密密钥版本 / Crypt key versions

`opscrypto.py` 里有三套密钥：

```python
mbox5 = [...]      # 默认
mbox6 = [...]
mbox4 = [...]
```

解包时脚本会依次尝试，并打印命中的版本：

```
MBox5   ← 先试这个
MBox6   ← 再试这个
MBox4   ← 最后试这个
```

**我们的一加 7 Pro Android 9 转换包用的是 `MBox4`** —— 重打包时必须指定 `--mbox=4`。

**如果打错密钥，MSM 工具会报 `Load profile failed`。**

---

## 4. MSM 工具的工作流程 / MSM tool workflow

### 4.1 完整阶段 / Full sequence

```
① 检测 9008 端口（Qualcomm HS-USB QDLoader 9008）
        ↓
② Sahara 协议握手 → 发送编程器（prog_firehose_ddr.elf）
        ↓
③ 进入 Firehose 模式 → 读取 UFS 信息
        ↓
④ Get Param PCBA  →  读取硬件参数
        ↓
⑤ 型号校验（项目号对比）     ← 不匹配就报"映像与装置不匹配"
        ↓
⑥ 读取 settings.xml 的索引 → 按 FileOffsetInSrc 逐个读镜像 → 写入设备
        ↓
⑦ 每个分区写完后 Readback 回读校验 SHA256
```

### 4.2 型号校验的本质 / The nature of the model check

日志：

```
[9472] CID = -1
[9472] Non TMO group
[9472] [Firehose] HwVersion = 21
[9472] [Firehose] RfVersion = 2
[9472] [Firehose] PrjVersion = 1
[9472] Get Param PCBA failed
[9472] model check failed 0, 1
[9472] [FH] Send PJ Model Failed. (1)
```

**关键**：校验读的是 **硬件 PCBA 参数**（通过 Firehose 从设备读），**不是软件属性**。

所以：
- ✅ 改 `ro.boot.prj_version` 属性 → **无效**
- ✅ 用错误项目号的包 → **会被拒**
- ✅ 用匹配的包（T-Mobile 变种包 = 18831）→ **通过**

### 4.3 USB 敏感性 / USB sensitivity

日志里常见：

```
[4] [SP][195] Check cmd done status failed. 1
[4] [SP][208] Reset Sahara
Get Param PCBA failed
```

**这些不是真的硬件问题，而是 USB 通信不稳。**

**实测结论**：
- ❌ 经过 USB Hub → Sahara 握手失败率高
- ❌ 前面板 USB 口 → 同上
- ✅ 直插主板后置 USB 2.0 口（**黑色**）→ 稳定

**还有一个关键时序**：

```
❌ 错误：先把手机送进 EDL，再打开工具 → 工具找到端口时 EDL 会话已老化 → Sahara 失败
✅ 正确：先开工具点 Start 等待 → 再送手机进 EDL → 几秒内握手 → 成功
```

---

## 5. 完整命令参考 / Full command reference

### 5.1 解包 / Extract

```bash
cd oppo_decrypt-master
python opscrypto.py decrypt /path/to/guacamole_21.O.09_190516.ops
# 输出到 .ops 同目录的 extract/
```

关键输出：

```
Oneplus CryptTools V1.4 (c) B. Kerler 2019-2021
MBox4                                   ← ★ 记住这个密钥版本
Extracting prog_firehose_ddr.elf
Extracting prog_firehose_lite.elf
Extracting config.bin
...
Done. Extracted files to .../extract
```

### 5.2 读偏移 / Read the offset

```powershell
$xml = [System.IO.File]::ReadAllText("extract/settings.xml")
$m = [regex]::Match($xml, '<program[^>]*filename="config\.bin"[^>]*/>')
$m.Value
# → <program ... FileOffsetInSrc="77095" SizeInByteInSrc="524288" Sha256="0785..." />

$byteOffset = 77095 * 512        # = 39472640
```

### 5.3 验证偏移 / Verify the offset

```powershell
# 从 .ops 里读出该位置的数据，算 SHA256，和 settings.xml 里的对比
$fs = [System.IO.File]::OpenRead($opsPath)
$fs.Seek(39472640, 'Begin') | Out-Null
$data = New-Object byte[] 524288
$fs.Read($data, 0, 524288) | Out-Null
$fs.Close()

$sha = [System.Security.Cryptography.SHA256]::Create()
($sha.ComputeHash($data) | ForEach-Object { '{0:x2}' -f $_ }) -join ''
# → 应该等于 07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541
```

**★ 这一步是决定性的** —— 对得上说明偏移正确，对不上说明算错了。

### 5.4 构造 FRP 块 / Build the FRP block

```powershell
$size = 524288
$block = New-Object byte[] $size

# 魔数 0x19901873 小端
$block[32] = 0x73; $block[33] = 0x18; $block[34] = 0x90; $block[35] = 0x19

# FRP 数据长度 = 0（[36..39] 已经是零）

# ★ OEM 解锁位 = 1
$block[$size - 1] = 0x01

# 摘要输入 = 32 个零字节 + block[32:]
$tail  = New-Object byte[] ($size - 32)
[Array]::Copy($block, 32, $tail, 0, $size - 32)
$input = New-Object byte[] $size
[Array]::Copy($tail, 0, $input, 32, $tail.Length)     # 前 32 字节保持零

$sha = [System.Security.Cryptography.SHA256]::Create()
$digest = $sha.ComputeHash($input)
$sha.Dispose()
[Array]::Copy($digest, 0, $block, 0, 32)

[System.IO.File]::WriteAllBytes("config.bin", $block)
```

### 5.5 更新 settings.xml / Update settings.xml

```powershell
$newHash = ($digest | ForEach-Object { '{0:x2}' -f $_ }) -join ''
$entry   = $m.Value
$newEntry = [regex]::Replace($entry, 'Sha256="[0-9a-fA-F]+"', "Sha256=`"$newHash`"")
$newXml  = $xml.Replace($entry, $newEntry)
[System.IO.File]::WriteAllText("extract/settings.xml", $newXml, [System.Text.UTF8Encoding]::new($false))
```

### 5.6 重打包 / Repack

```bash
cd oppo_decrypt-master
python opscrypto.py encrypt /path/to/extract \
    --projid=18831 \
    --mbox=4 \
    --savename=guacamole_UNLOCK.ops
```

参数说明：
- `--projid` — 项目号，**必须和设备匹配**（T-Mobile 变种包 = `18831`）
- `--mbox` — 加密密钥版本，**用解包时打印的那个**（我们是 `4`）
- `--savename` — 输出文件名

### 5.7 刷入 / Flash

```
1. 把 _UNLOCK.ops 放进一个干净目录（只放 MSM 工具和这一个 .ops）
2. 手机 → EDL
3. MSM 工具 → Start
4. 等 3-8 分钟
```

### 5.8 解锁 / Unlock

```bash
fastboot flashing get_unlock_ability      # 期望 1
fastboot flashing unlock
# ★ 手机屏幕上按音量键选择、电源键确认
fastboot getvar unlocked                  # 期望 yes
```

---

## 6. 踩坑记录 / Pitfall log

按我们实际踩的顺序：

### 坑 1：靠推算定位偏移 ✗

**做法**：解析 `.ops` 里的 GPT 分区表 → 按镜像顺序推算 `config.bin` 的位置 → 得到偏移 `36,004,864`

**结果**：`get_unlock_ability` 依然是 `0`，两次都失败。

**原因**：
1. 解析到的那个 GPT **不是这台机器的主分区表**（`system_a` 显示 434 MB，而实际约 3.35 GB）
2. 实际偏移是 `39,472,640`，**差了 3.5 MB** —— 补丁打进了 `param.bin`

**教训**：**`settings.xml` 里有精确偏移，别猜。**

### 坑 2：摘要算法漏了 32 个零字节 ✗

**做法**：`digest = SHA256(block[32:])`

**结果**：块被系统判定无效 → `enforceChecksumValidity()` 触发重格式化 → 标志位被清零

**原因**：AOSP 源码里是 `md.update(data, 0, DIGEST_SIZE_BYTES)`，其中 `data` 是**新建的零数组** → 哈希输入前面有 32 个零字节

**教训**：**逐行读源码，别凭直觉。**

### 坑 3：EDL 时序错 ✗

**做法**：先把手机送进 EDL，再打开工具

**结果**：`Sahara通信失败 (PBL:6)` / `Get Param PCBA failed`

**原因**：工具找到端口时，EDL 会话已经老化了

**教训**：**先让工具 Start 等待，再送手机进 EDL，中间只隔几秒。**

### 坑 4：USB Hub ✗

**现象**：Sahara 握手随机失败、`model check failed`

**原因**：EDL 对 USB 链路质量极敏感（OplusEdlTool 的 issue 里也有 "usb3.0和usb2.0兼容性问题"）

**教训**：**直插主板后置 USB 2.0 口。**

### 坑 5：Android 12 的 bootloader bug ✗

**现象**：`get_unlock_ability = 1` 但解锁报 `Device cannot be unlocked for technical reason.`

**原因**：一加在 Android 12 的 ABL 里引入的 bug

**教训**：**回滚到 Android 11 或更早。** Android 9 的报错是标准的 `Flashing Unlock is not allowed`（说明标志位没设），不是这个 bug。

### 坑 6：以为改了开关就完事 ✗

**现象**：`fastboot flashing unlock` 返回 `OKAY`，但 `getvar unlocked` 还是 `no`

**原因**：**一加/高通设备需要手机屏幕上确认！** `OKAY` 只表示命令被接受

**教训**：**解锁时盯着手机屏幕，按音量键选择 + 电源键确认。**

---

## 7. 为什么这个方案之前没人做 / Why this wasn't done before

1. **`.ops` 是加密的** —— 直到 `oppo_decrypt` 出现，社区才有工具能解开
2. **`settings.xml` 的偏移字段没有文档** —— 需要读 `opscrypto.py` 源码才知道单位是 512 字节
3. **FRP 格式埋在 AOSP 的 Java 源码里** —— 而且摘要算法有个反直觉的"32 个零字节"，看漏了就失败
4. **失败是静默的** —— 摘要错了系统会自动重格式化，你看不到任何报错，只会觉得"怎么没效果"
5. **硬件项目号校验** —— 让人以为是"包不对"，实际上要的是**匹配项目号的包**

**这个方案的价值在于把上面 5 点全部打通并记录下来。**

---

## 8. 参考 / References

### AOSP 源码
- [`PersistentDataBlockService.java` — android11-release](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/PersistentDataBlockService.java)
- [`PersistentDataBlockService.java` — android-9.0.0_r61](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r61/services/core/java/com/android/server/PersistentDataBlockService.java)
- [`OemLockService.java` — android-9.0.0_r1](https://cs.android.com/android/platform/superproject/+/android-9.0.0_r1:frameworks/base/services/core/java/com/android/server/oemlock/OemLockService.java)

### 工具
- [oppo_decrypt — bkerler](https://github.com/bkerler/oppo_decrypt)
- [OplusEdlTool](https://github.com/salokrwhite/OplusEdlTool)
- [Magisk — topjohnwu](https://github.com/topjohnwu/Magisk)

### 社区资料
- [OnePlus 7 Pro unlock bootloader does not work [SOLVED] — /e/OS community](https://community.e.foundation/t/oneplus-7-pro-unlock-bootloader-does-not-work-solved/73634)
  （Android 12 bootloader bug 的记录）
- [AdaUnlocked/Oplus-Qualcomm-Unlock-2026-Universal-Guide](https://github.com/AdaUnlocked/Oplus-Qualcomm-Unlock-2026-Universal-Guide)
- [Qual+Android方案Unlock学习 以Oneplus7Pro为例 — CSDN](https://blog.csdn.net/2301_80127209/article/details/133791777)
  （最早记录"从 .ops 里提取 firehose"的中文文章）

---

*最后更新 / Last updated: 2026-10-11*
