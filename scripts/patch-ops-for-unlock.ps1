<#
.SYNOPSIS
    一加 7 Pro (T-Mobile GM1915) Bootloader 解锁 —— 一体化补丁脚本
    OnePlus 7 Pro (T-Mobile GM1915) Bootloader Unlock — All-in-one patcher

.DESCRIPTION
    本脚本对 MSM 救砖包 (.ops) 做两处修改，使刷入后 bootloader 的
    OEM 解锁标志位变为 1，从而让 `fastboot flashing unlock` 被接受。

    This script patches an MSM unbrick package (.ops) in two places so that
    after flashing, the bootloader's OEM-unlock flag is set to 1,
    allowing `fastboot flashing unlock` to succeed.

    原理 / How it works:
      1. .ops 里的 config.bin 就是 Android 的持久化数据块分区 (ro.frp.pst)
         config.bin in the .ops is Android's persistent data block partition
      2. bootloader 从该分区最后一个字节读取 OEM 解锁位
         The bootloader reads the OEM-unlock bit from the LAST byte of that partition
      3. config 分区不在 AVB 校验范围内，改它不会破坏 verified boot
         The config partition is NOT covered by AVB — patching it won't break verified boot

.PARAMETER OpsPath
    原始 .ops 文件路径 / Path to the original .ops file

.PARAMETER WorkDir
    工作目录（存放解包结果和新包）/ Working directory

.PARAMETER OppoDecryptDir
    oppo_decrypt 工具目录（含 opscrypto.py）/ oppo_decrypt tool directory

.PARAMETER ProjectId
    包的项目号。T-Mobile 变种包用 18831；国际版用 18821
    Project ID. T-Mobile conversion package uses 18831; global uses 18821

.EXAMPLE
    .\patch-ops-for-unlock.ps1 -OpsPath "D:\fw\guacamole_21.O.09_190516.ops"

.NOTES
    仅适用于你有权修改的自己拥有的设备。
    For use only on devices you own and are authorized to modify.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OpsPath,

    [string]$WorkDir = "$PSScriptRoot\work",

    [string]$OppoDecryptDir = "$PSScriptRoot\..\..\oppo_decrypt\oppo_decrypt-master",

    [int]$ProjectId = 18831,

    [string]$MBox = "4"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Info($m) { Write-Host "  $m" }
function Ok($m)   { Write-Host "  [OK] $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m"   -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [X]  $m"   -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OnePlus 7 Pro (GM1915) Bootloader Unlock Patcher" -ForegroundColor Cyan
Write-Host "  一加 7 Pro 解锁补丁工具" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 0. 检查
Write-Host "`n[0/6] 环境检查 / Environment check"
if (-not (Test-Path $OpsPath)) { Die "找不到 .ops 文件 / .ops not found: $OpsPath" }
$OpsPath = (Resolve-Path $OpsPath).Path
$opsName = [System.IO.Path]::GetFileNameWithoutExtension($OpsPath)
Info "输入包 / Input : $OpsPath"
Info "大小   / Size  : $([math]::Round((Get-Item $OpsPath).Length/1MB,1)) MB"

$opsCrypto = Join-Path $OppoDecryptDir "opscrypto.py"
if (-not (Test-Path $opsCrypto)) { Die "找不到 opscrypto.py / not found: $opsCrypto" }
Info "解密工具 / Tool: $opsCrypto"

& python -c "import docopt, Crypto" 2>$null
if ($LASTEXITCODE -ne 0) {
    Warn "缺少 Python 依赖，正在安装 / Installing Python deps..."
    & python -m pip install --quiet pycryptodome pycryptodomex docopt
}
Ok "Python 环境就绪 / Python ready"

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$extractDir = Join-Path $WorkDir "extract"

# ---------------------------------------------------------------- 1. 解包
Write-Host "`n[1/6] 解包 .ops / Extracting .ops"
Write-Host "      (4-5 GB 的包，需要几分钟 / takes a few minutes for a 4-5 GB package)"

if (Test-Path (Join-Path $extractDir "settings.xml")) {
    Ok "已有解包结果，跳过 / Already extracted, skipping"
} else {
    Push-Location $OppoDecryptDir
    try {
        # opscrypto.py 会在 .ops 所在目录下建 extract/
        & python opscrypto.py decrypt $OpsPath 2>&1 | ForEach-Object { Write-Host "      $_" }
    } finally { Pop-Location }

    $autoExtract = Join-Path (Split-Path $OpsPath -Parent) "extract"
    if (Test-Path $autoExtract) {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Move-Item $autoExtract $extractDir
    }
}
if (-not (Test-Path (Join-Path $extractDir "settings.xml"))) { Die "解包失败，找不到 settings.xml / extraction failed" }
Ok "解包完成 / Extracted to $extractDir"

# ---------------------------------------------------------------- 2. 读偏移
Write-Host "`n[2/6] 从 settings.xml 读取 config.bin 的真实位置"
Write-Host "      Reading the REAL offset of config.bin from settings.xml"

$settingsPath = Join-Path $extractDir "settings.xml"
$xml = [System.IO.File]::ReadAllText($settingsPath)

# <program ... filename="config.bin" ... FileOffsetInSrc="N" SizeInByteInSrc="M" Sha256="..." />
$pattern = '<program[^>]*filename="config\.bin"[^>]*/>'
$m = [regex]::Match($xml, $pattern)
if (-not $m.Success) { Die "settings.xml 里找不到 config.bin 条目 / config.bin entry not found" }

$entry = $m.Value
function Get-Attr($tag, $name) {
    $mm = [regex]::Match($tag, "$name=`"([^`"]*)`"")
    if ($mm.Success) { return $mm.Groups[1].Value } else { return $null }
}

$offsetSectors = [int64](Get-Attr $entry 'FileOffsetInSrc')
$sizeBytes     = [int64](Get-Attr $entry 'SizeInByteInSrc')
$oldSha        = Get-Attr $entry 'Sha256'
$startSector   = Get-Attr $entry 'start_sector'

if (-not $offsetSectors) { Die "读不到 FileOffsetInSrc" }
if (-not $sizeBytes)     { Die "读不到 SizeInByteInSrc" }

# ★ 关键：FileOffsetInSrc 的单位是 512 字节扇区
# ★ KEY: FileOffsetInSrc is in 512-byte sectors
$byteOffset = $offsetSectors * 512

Info "  start_sector      = $startSector   (设备上的分区起始扇区)"
Info "  FileOffsetInSrc   = $offsetSectors  (包内位置，单位 512 字节)"
Info "  ★ 包内字节偏移     = $byteOffset"
Info "  ★ 分区大小         = $sizeBytes 字节 ($([math]::Round($sizeBytes/1KB,1)) KB)"
Info "  原 SHA256         = $oldSha"

# 校验：把原始 config 从 .ops 里读出来，比对 SHA256
$fs = [System.IO.File]::OpenRead($OpsPath)
$fs.Seek($byteOffset, 'Begin') | Out-Null
$orig = New-Object byte[] $sizeBytes
$fs.Read($orig, 0, $sizeBytes) | Out-Null
$fs.Close()

$sha = [System.Security.Cryptography.SHA256]::Create()
$origHash = ($sha.ComputeHash($orig) | ForEach-Object { '{0:x2}' -f $_ }) -join ''
$sha.Dispose()

Info "  实际读取的 SHA256 = $origHash"
if ($origHash -eq $oldSha) {
    Ok "★ 偏移验证通过！settings.xml 的偏移与实际数据完全吻合"
    Ok "★ OFFSET VERIFIED — settings.xml offset matches the actual data"
} else {
    Warn "SHA256 不匹配 — 偏移可能有误，请确认包版本"
    Warn "SHA256 mismatch — offset may be wrong for this package"
    $ans = Read-Host "  仍然继续？/ Continue anyway? (y/N)"
    if ($ans -ne 'y') { exit 1 }
}

# ---------------------------------------------------------------- 3. 构造 FRP 块
Write-Host "`n[3/6] 构造合法的 Android 持久化数据块 (FRP)"
Write-Host "      Building a valid Android persistent data block"

# 布局 / Layout (AOSP PersistentDataBlockService):
#   [0    .. 31]     SHA256( 32 个零字节 || block[32:] )
#   [32   .. 35]     PARTITION_TYPE_MARKER = 0x19901873 (小端 / little endian)
#   [36   .. 39]     FRP 数据长度 = 0 / FRP data length = 0
#   [40   .. N-2]    零 / zeros
#   [N-1]            ★ OEM 解锁位 = 1 / OEM unlock bit = 1

$block = New-Object byte[] $sizeBytes
$block[32] = 0x73; $block[33] = 0x18; $block[34] = 0x90; $block[35] = 0x19   # marker
$block[36] = 0;    $block[37] = 0;    $block[38] = 0;    $block[39] = 0        # data len = 0
$block[$sizeBytes - 1] = 0x01                                                  # ★ unlock bit

# 摘要输入 = 32 个零字节 + block[32:]
$tail  = New-Object byte[] ($sizeBytes - 32)
[Array]::Copy($block, 32, $tail, 0, $sizeBytes - 32)
$input = New-Object byte[] $sizeBytes
[Array]::Copy($tail, 0, $input, 32, $tail.Length)   # 前 32 字节保持 0

$sha = [System.Security.Cryptography.SHA256]::Create()
$digest = $sha.ComputeHash($input)
$sha.Dispose()
[Array]::Copy($digest, 0, $block, 0, 32)

$newSha = ($digest | ForEach-Object { '{0:x2}' -f $_ }) -join ''
$marker = ($block[32..35] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '

Info "  魔数      / marker    = $marker  (0x19901873 小端)"
Info "  新 SHA256 / new hash  = $newSha"
Info "  ★ OEM 解锁位 / unlock = 0x$('{0:X2}' -f $block[$sizeBytes-1])"

# 自校验 / self-check
$chk = New-Object byte[] $sizeBytes
$t2 = New-Object byte[] ($sizeBytes - 32); [Array]::Copy($block, 32, $t2, 0, $sizeBytes - 32)
[Array]::Copy($t2, 0, $chk, 32, $t2.Length)
$sha = [System.Security.Cryptography.SHA256]::Create()
$d2 = $sha.ComputeHash($chk); $sha.Dispose()
$stored = ($block[0..31] | ForEach-Object { '{0:x2}' -f $_ }) -join ''
$calc   = ($d2 | ForEach-Object { '{0:x2}' -f $_ }) -join ''
if ($stored -ne $calc) { Die "自校验失败 / self-check failed" }
Ok "摘要自校验通过 / digest self-check passed"

# ---------------------------------------------------------------- 4. 写入
Write-Host "`n[4/6] 写入解包目录 / Writing into the extracted directory"

$configPath = Join-Path $extractDir "config.bin"
if (-not (Test-Path $configPath)) { Die "找不到 $configPath" }
Copy-Item $configPath "$configPath.orig" -Force
[System.IO.File]::WriteAllBytes($configPath, $block)
Ok "config.bin 已替换（原文件备份为 config.bin.orig）"
Ok "config.bin replaced (original backed up as config.bin.orig)"

# 更新 settings.xml 里的 SHA256 —— MSM 工具会校验这个值
# Update the SHA256 in settings.xml — the MSM tool verifies this
$newEntry = [regex]::Replace($entry, 'Sha256="[0-9a-fA-F]+"', "Sha256=`"$newSha`"")
$newXml   = $xml.Replace($entry, $newEntry)
if ($newXml -eq $xml) { Die "settings.xml 更新失败 / failed to update settings.xml" }
[System.IO.File]::WriteAllText($settingsPath, $newXml, [System.Text.UTF8Encoding]::new($false))
Ok "settings.xml 的 Sha256 已同步更新（否则 MSM 工具会拒绝）"
Ok "settings.xml SHA256 updated (otherwise the MSM tool will reject it)"

# ---------------------------------------------------------------- 5. 重打包
Write-Host "`n[5/6] 重新打包为 .ops / Repacking into a new .ops"
$outName = "$($opsName)_UNLOCK.ops"

Push-Location $OppoDecryptDir
try {
    & python opscrypto.py encrypt $extractDir --projid=$ProjectId --mbox=$MBox --savename=$outName 2>&1 |
        Select-Object -Last 6 | ForEach-Object { Write-Host "      $_" }
} finally { Pop-Location }

$outOps = Join-Path (Split-Path $extractDir -Parent) $outName
if (-not (Test-Path $outOps)) {
    # 有时会输出到 extract 的父目录
    $alt = Join-Path (Split-Path $extractDir -Parent) $outName
    if (Test-Path $alt) { $outOps = $alt } else { Die "重打包失败，找不到输出文件 / repack failed" }
}
Ok "新包 / New package: $outOps  ($([math]::Round((Get-Item $outOps).Length/1MB,1)) MB)"

# ---------------------------------------------------------------- 6. 验证
Write-Host "`n[6/6] 验证新包 / Verifying the new package"
$fs = [System.IO.File]::OpenRead($outOps)
$fs.Seek($byteOffset, 'Begin') | Out-Null
$vf = New-Object byte[] $sizeBytes
$fs.Read($vf, 0, $sizeBytes) | Out-Null
$fs.Close()

$vMark = ($vf[32..35] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
Info "  偏移 $byteOffset 处:"
Info "    魔数     = $vMark"
Info "    末字节   = 0x$('{0:X2}' -f $vf[$sizeBytes-1])"
if ($vf[$sizeBytes-1] -eq 1 -and $vMark -eq '73 18 90 19') {
    Ok "★★★ 新包已就绪，OEM 解锁位 = 1"
    Ok "★★★ Package ready, OEM-unlock bit = 1"
} else {
    Die "验证失败 / verification failed"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  完成 / DONE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  新包位置 / Output:" -ForegroundColor Cyan
Write-Host "    $outOps"
Write-Host ""
Write-Host "  下一步 / Next steps:" -ForegroundColor Cyan
Write-Host "    1. 把新包放到 MSM 工具同目录（该目录只放这一个 .ops）"
Write-Host "       Put the new .ops next to the MSM tool (only ONE .ops in that folder)"
Write-Host "    2. 手机进 EDL（关机后按住 音量上+音量下+电源）"
Write-Host "       Boot the phone into EDL (power off, hold Vol+ & Vol- & Power)"
Write-Host "    3. MSM 工具点 Start，刷入"
Write-Host "       Click Start in the MSM tool"
Write-Host "    4. 刷完后开机，检查："
Write-Host "       After flashing, boot up and check:"
Write-Host "         adb shell getprop sys.oem_unlock_allowed     -> 1"
Write-Host "    5. fastboot flashing unlock  （手机上按音量键确认）"
Write-Host ""
