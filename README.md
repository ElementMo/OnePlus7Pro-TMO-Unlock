<div align="center">

# Unlocking the Carrier-Locked T-Mobile OnePlus 7 Pro

**OnePlus 7 Pro `GM1915` · bootloader unlock without SIM unlock, without carrier cooperation**

[![Device](https://img.shields.io/badge/device-OnePlus%207%20Pro%20GM1915-red?style=flat-square)](https://www.oneplus.com/7pro)
[![Status](https://img.shields.io/badge/status-verified%20working-success?style=flat-square)](#verification)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20PowerShell-blue?style=flat-square)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-EN%20%7C%20%E4%B8%AD%E6%96%87-orange?style=flat-square)](README.zh-CN.md)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## The problem

Every OnePlus 7 Pro unlock guide assumes your **OEM unlocking toggle is tappable**. On a carrier-locked T-Mobile `GM1915`, it is **greyed out entirely**:

```
Settings → Developer options → OEM unlocking      ← GREYED, untappable
fastboot flashing unlock                          → FAILED (remote: 'Flashing Unlock is not allowed')
fastboot oem unlock                               → FAILED (remote: 'Flashing Unlock is not allowed')
```

…and it stays that way **no matter what you flash**:

| Method | What it actually fixes | Why it fails here |
|---|---|---|
| Convert to Global firmware | Carrier config (`ro.boot.opcarrier` → `none`) | Never touches the unlock flag |
| "Flash Android Q" trick (2019 XDA article) | Sometimes makes the toggle tappable | Doesn't bypass the carrier restriction itself |
| Update to Android 12 | Makes the toggle tappable | OnePlus's Android 12 bootloader has a bug: even at `get_unlock_ability=1` it refuses with *"technical reason"* |
| Downgrade to Android 11 | Removes the Android 12 bug | On a locked unit the toggle is greyed again — you can never *set* the flag |
| T-Mobile Device Unlock app | Everything | Needs an active, eligible T-Mobile account. Dead end for second-hand devices. |

**This problem was first reported in September 2019** — XDA thread ["One Plus 7 Pro - Flashed, still can't enable OEM UNLOCK"](https://xdaforums.com/t/one-plus-7-pro-flashed-still-cant-enable-oem-unlock.3965981/). Every reply was *"call T-Mobile"* or *"get a SIM unlock"*. **The thread has no ending. Six years later there is still no technical solution published.**

---

## The solution

The OEM-unlock state lives in **one byte** — the last byte of the **`config`** partition (Android's persistent data block). The MSM unbrick package **flashes that partition**, and it is **not protected by AVB**.

> ### Patch that byte inside the `.ops`, flash it back, and the bootloader accepts the unlock.

```
adb shell getprop sys.oem_unlock_allowed     →  1     ✓
fastboot flashing get_unlock_ability         →  1     ✓
fastboot flashing unlock                     →  OKAY  ✓
```

**No SIM unlock. No carrier cooperation. No paid tool.**

---

## Quick start

```powershell
# 1. One-time setup (installs Python deps, fetches oppo_decrypt)
.\scripts\00-setup.ps1

# 2. Patch your MSM package
.\scripts\patch-ops-for-unlock.ps1 -OpsPath "D:\fw\guacamole_21.O.09_190516.ops"

# 3. Flash the produced *_UNLOCK.ops with the MSM tool, then:
adb reboot bootloader
fastboot flashing unlock
```

> **⚠️ `fastboot flashing unlock` shows a confirmation screen ON THE PHONE.**
> Select with the **volume keys**, confirm with the **power key**.
> The command returning `OKAY` only means it was *accepted* — it has not executed yet.

Then verify:

```powershell
.\scripts\verify-unlock.ps1
```

---

## What makes this different

Most of the work here is **not** the idea — it's the four things that make the idea actually function, none of which were documented:

**1. The real offset, not a derived one**
`settings.xml` inside the `.ops` carries the exact in-package offset of every image. The unit is **512-byte sectors** (`FileOffsetInSrc × 0x200`), and this is undocumented — it's only discoverable by reading `opscrypto.py`'s source.
> *I initially derived the offset from the GPT plus image ordering and got `36,004,864` — wrong by 3.5 MB, which landed inside `param.bin`. Two flashes wasted.*

**2. The digest is prefixed with 32 zero bytes**
AOSP's reader does `md.update(data, 0, DIGEST_SIZE_BYTES)` where `data` is a freshly allocated zero array. So the digest is `SHA256( 32×0x00 ‖ block[32:] )`, **not** `SHA256(block[32:])`.
> And the failure mode is **silent**: the system detects the bad checksum at boot and reformats the block, clearing your flag. No error, just "it didn't work".

**3. The repack is mandatory, not optional**
`config.bin` is plaintext inside the `.ops`, but `settings.xml` records its SHA256 and the MSM tool verifies it (`SkipImgSHA256Check="false"`). `settings.xml` lives in the **encrypted** region — so you must extract → patch both → repack.

**4. The `config` partition is the only viable target**
It is simultaneously (a) flashed by the package, (b) the home of the unlock flag, and (c) outside the AVB hash chain. `devinfo`, `frp`, `persist` and `modemst` all fail one of those three — they aren't even in the flash list.

---

## Requirements

- OnePlus 7 Pro **T-Mobile `GM1915`**
- Windows 10/11 + Python 3.8+
- A good USB cable, plugged **directly into a rear motherboard port** — no hubs. EDL is extremely sensitive to USB link quality.
- **MSM package + login-free MSM tool** — e.g. `Conversion_Tool_To_9.5.6.GM21AA.zip` from the [OnePlus community server](https://onepluscommunityserver.com/list/Unbrick_Tools/OnePlus_7_Pro/)
- Qualcomm 9008 driver (`qcser.inf`) + Google USB driver (for fastboot)

> **⚠️ Never let this phone take an official system update.**
> On some OPPO/OnePlus models, updates permanently blow the EDL no-auth fuse. This method depends on EDL — once fused, you can never flash it back.

See [tools/TOOL-SOURCES.md](tools/TOOL-SOURCES.md) for where to get everything.

---

## Repository layout

```
.
├── README.md                       this file (English)
├── README.zh-CN.md                 简体中文文档
├── LICENSE                         MIT + flashing-risk notice
├── bin/
│   ├── config_patched.bin          pre-built FRP block, OEM-unlock bit = 1 (512 KB)
│   └── config_stock_allzero.bin    stock state for comparison (all zeros, 512 KB)
├── scripts/
│   ├── 00-setup.ps1                one-time setup: Python deps + oppo_decrypt
│   ├── patch-ops-for-unlock.ps1    ★ all-in-one patcher
│   ├── verify-unlock.ps1           check the unlock state
│   └── share-clash-proxy-to-phone.bat
│                                   bonus: share the PC's Clash proxy with the phone
└── docs/
    ├── TECHNICAL.md                deep dive: AOSP references, format analysis, pitfall log
    └── settings.xml.sample         a real extracted index, for field-format reference
```

> `bin/config_patched.bin` is a generic, valid 512 KB FRP block — but **different models may have a different `config` partition size**. Verify yours, and regenerate with `patch-ops-for-unlock.ps1` if it differs.

---

## Verification

```bash
# system layer
adb shell getprop sys.oem_unlock_allowed      # 1
adb shell getprop ro.boot.flash.locked        # 0
adb shell getprop ro.boot.verifiedbootstate   # orange

# bootloader layer
fastboot getvar unlocked                      # unlocked: yes
fastboot oem device-info                      # Device unlocked: true
fastboot flashing get_unlock_ability          # 1
```

**Note:** afterwards the OEM unlocking toggle may still show **greyed out but ON**. **That is normal and expected** — the grey comes from the carrier check (UI layer), the flag comes from the FRP (low level). The bootloader only reads the flag.

**Verified configuration:** LineageOS 23.2 (Android 16) + MindTheGapps 16.0 arm64 + Magisk 30.7, `verifiedbootstate = orange`, Magisk mounts active.

---

## Documentation

| Document | Contents |
|---|---|
| [README.zh-CN.md](README.zh-CN.md) | 完整中文文档：原理、前置条件、流程、常见问题 |
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | Deep dive — AOSP source walkthrough, `.ops` container format, MSM workflow, full pitfall log |
| [tools/TOOL-SOURCES.md](tools/TOOL-SOURCES.md) | Where to obtain every required tool |

---

## Troubleshooting

**`sys.oem_unlock_allowed` is still 0 after flashing**
Your offset is wrong. Re-check that the SHA256 of the data at your computed offset matches the `Sha256` field in `settings.xml`.

**"Load profile failed" in the MSM tool**
Package/tool version mismatch. The 2019 patched tool (V4.0.88) can't read 2021+ packages; the 2022 factory tool (V5.1.70) wants a login.

**"Image does not match device" / model check failed**
The tool reads the **hardware PCBA parameter** over Firehose. Changing software properties (`ro.boot.prj_version`) does nothing. You need a package whose project ID matches your hardware — **18831** for the T-Mobile variant, 18821 for Global.

**Sahara communication failed (PBL:6) / Get Param PCBA failed**
Almost always USB. Remove any hub; use a rear USB 2.0 (black) port. Also check ordering: **the tool must be waiting *before* the phone enters EDL** — an EDL session goes stale in about a minute.

**Android 12: `get_unlock_ability = 1` but the unlock still fails with "technical reason"**
OnePlus's Android 12 bootloader bug. You need Android 11 or earlier — but there the toggle is greyed again, which is precisely why the FRP patch is required: it sets the flag *without* the toggle.

More in [docs/TECHNICAL.md](docs/TECHNICAL.md).

---

## Credits

| Project | Author | Role |
|---|---|---|
| [oppo_decrypt](https://github.com/bkerler/oppo_decrypt) | [bkerler](https://github.com/bkerler) | `.ops` decrypt / repack — without this, the package is a black box |
| MSM Download Tool | OnePlus / Qualcomm | EDL flashing |
| [PersistentDataBlockService.java](https://android.googlesource.com/platform/frameworks/base/) | AOSP | the persistent data block format |
| [LineageOS](https://lineageos.org/) · [MindTheGapps](https://wiki.lineageos.org/gapps/) · [Magisk](https://github.com/topjohnwu/Magisk) | respective teams | the OS, GApps, root |
| [CSDN writeup by muhe](https://blog.csdn.net/2301_80127209/article/details/133791777) | muhe | earliest article I found extracting the firehose programmer from a OnePlus `.ops` — it pointed me in the right direction |

---

## Disclaimer

Use this only on devices **you own and are authorized to modify**. Flashing carries a real risk of bricking. Back up your data first. Check whether your model fuses EDL on system updates before you start. See **[DISCLAIMER.md](DISCLAIMER.md)** for the full risk notice and third-party attributions.

---

## Contributing

**Tried this on a different OPPO / OnePlus / Realme model?** Please open an issue with your model, package name, and result. The method should generalise to any device using `.ops` + an FRP persistent data block, and the offset/digest logic is model-independent — only the partition size and crypt key version vary.

Pull requests for other package versions, other crypt keys (`MBox5` / `MBox6`), or a cross-platform (Python) port of the patcher are very welcome.
