<#
.SYNOPSIS
    FRP 持久化数据块 —— 回归测试
    FRP persistent data block — regression test

.DESCRIPTION
    校验 patch-ops-for-unlock.ps1 构造的 config 分区镜像是否符合：
      1. AOSP PersistentDataBlockService 的分区布局
      2. README 中公布的 config_patched.bin 的 SHA256

    这个测试是为了锁住一个曾经出现过的 bug：
    把 FRP 块的【内部摘要】(block[0:32]) 当成了【整个文件的 SHA256】
    写进 settings.xml，导致 MSM 工具 (SkipImgSHA256Check="false") 拒绝刷写。

    This test guards a real bug: the FRP block's INTERNAL digest
    (block[0:32]) was mistakenly written into settings.xml as the FILE
    hash, making the MSM tool reject the image.

.EXAMPLE
    .\test-frp-block.ps1
#>

$ErrorActionPreference = 'Stop'

# README「文件清单」里公布的 config_patched.bin 哈希 / documented in README
$EXPECTED_FILE_SHA256 = 'fc7dde40d5f1392c83606c94d1c60f057e6d99a9d538298ec2e725a002534ee0'
$SIZE = 524288   # guacamole config 分区大小 / guacamole config partition size

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $name  $detail" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host ""
Write-Host "=== FRP block regression test ===" -ForegroundColor Cyan

# ---- 1. 构造块（与 patch-ops-for-unlock.ps1 第 3 步一致） ----
$block = New-Object byte[] $SIZE
$block[32] = 0x73; $block[33] = 0x18; $block[34] = 0x90; $block[35] = 0x19
$block[36] = 0; $block[37] = 0; $block[38] = 0; $block[39] = 0
$block[$SIZE - 1] = 0x01

$tail = New-Object byte[] ($SIZE - 32)
[Array]::Copy($block, 32, $tail, 0, $SIZE - 32)
$input = New-Object byte[] $SIZE
[Array]::Copy($tail, 0, $input, 32, $tail.Length)

$sha = [System.Security.Cryptography.SHA256]::Create()
$digest = $sha.ComputeHash($input)
$sha.Dispose()
[Array]::Copy($digest, 0, $block, 0, 32)

$digestHex = ($digest | ForEach-Object { '{0:x2}' -f $_ }) -join ''

$sha = [System.Security.Cryptography.SHA256]::Create()
$fileDigest = $sha.ComputeHash($block)
$sha.Dispose()
$fileHex = ($fileDigest | ForEach-Object { '{0:x2}' -f $_ }) -join ''

# ---- 2. 布局校验 ----
Check 'marker @32 = 0x19901873 (LE)' `
      ($block[32] -eq 0x73 -and $block[33] -eq 0x18 -and $block[34] -eq 0x90 -and $block[35] -eq 0x19) `
      ("got {0:x2} {1:x2} {2:x2} {3:x2}" -f $block[32], $block[33], $block[34], $block[35])

Check 'FRP data length @36 = 0' `
      ($block[36] -eq 0 -and $block[37] -eq 0 -and $block[38] -eq 0 -and $block[39] -eq 0) ''

Check 'OEM unlock bit (last byte) = 1' ($block[$SIZE - 1] -eq 1) "got $($block[$SIZE-1])"

# ---- 3. 摘要自校验（AOSP 读法：跳过 32 字节摘要，对剩余部分 + 32 个零字节重算） ----
$chk = New-Object byte[] $SIZE
$t2 = New-Object byte[] ($SIZE - 32)
[Array]::Copy($block, 32, $t2, 0, $SIZE - 32)
[Array]::Copy($t2, 0, $chk, 32, $t2.Length)
$sha = [System.Security.Cryptography.SHA256]::Create()
$recalc = $sha.ComputeHash($chk)
$sha.Dispose()
$storedHex = ($block[0..31] | ForEach-Object { '{0:x2}' -f $_ }) -join ''

Check 'internal digest self-check' ($storedHex -eq (($recalc | ForEach-Object { '{0:x2}' -f $_ }) -join '')) ''

# ---- 4. ★ 核心回归：文件哈希必须等于 README 公布值 ----
Check 'file SHA256 == README documented value' ($fileHex -eq $EXPECTED_FILE_SHA256) `
      "expected $EXPECTED_FILE_SHA256, got $fileHex"

# ---- 5. ★ 核心回归：internal digest 与 file hash 必须不同 ----
Check 'internal digest != file SHA256 (the bug)' ($digestHex -ne $fileHex) `
      'they are equal — settings.xml would get the wrong hash'

# ---- 6. 非零字节数量应为 32 + 4 + 1 = 37 ----
$nonzero = 0
foreach ($b in $block) { if ($b -ne 0) { $nonzero++ } }
Check 'non-zero byte count = 37' ($nonzero -eq 37) "got $nonzero"

Write-Host ""
if ($fail -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host "  file SHA256     = $fileHex"
    Write-Host "  internal digest = $digestHex"
    exit 0
} else {
    Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red
    exit 1
}
