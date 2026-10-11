<#
.SYNOPSIS
    验证一加 7 Pro 的 bootloader 解锁状态
    Verify the OnePlus 7 Pro bootloader unlock state

.DESCRIPTION
    依次检查系统层、bootloader 层、以及解锁后的系统属性。
    Checks the system layer, the bootloader layer, and post-unlock properties.

.EXAMPLE
    .\verify-unlock.ps1
    .\verify-unlock.ps1 -Adb "C:\platform-tools\adb.exe"
#>

param(
    [string]$Adb = "adb",
    [string]$Fastboot = "fastboot"
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Line($n = 60) { Write-Host ("-" * $n) }
function Sh($cmd) {
    $r = & $Adb shell $cmd 2>&1
    return ($r | Out-String).Trim()
}
function Fb($cmd) {
    $r = & $Fastboot $cmd 2>&1
    return (($r | Out-String) -replace '^.*?:\s*', '' -replace '\s+Finished.*', '').Trim()
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OnePlus 7 Pro — Bootloader Unlock Verification" -ForegroundColor Cyan
Write-Host "  一加 7 Pro — 解锁状态验证" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------ 设备检测
Write-Host "`n[1] 设备检测 / Device detection"
Line
$adbDevs = (& $Adb devices 2>&1) -join "`n"
$fbDevs  = (& $Fastboot devices 2>&1) -join "`n"

$hasAdb = $adbDevs -match '\S+\s+device'
$hasFb  = $fbDevs  -match '\S+\s+fastboot'

if ($hasAdb) { Write-Host "  adb      : OK"      -ForegroundColor Green }
else         { Write-Host "  adb      : 未连接 / not connected" -ForegroundColor DarkGray }
if ($hasFb)  { Write-Host "  fastboot : OK"      -ForegroundColor Green }
else         { Write-Host "  fastboot : 未连接 / not connected" -ForegroundColor DarkGray }

if (-not $hasAdb -and -not $hasFb) {
    Write-Host "`n  请连接手机 / Connect the phone first" -ForegroundColor Yellow
    exit 1
}

# ------------------------------------------------------------------ 系统层
if ($hasAdb) {
    Write-Host "`n[2] 系统层 / System layer"
    Line
    $oem  = Sh 'getprop sys.oem_unlock_allowed'
    $lock = Sh 'getprop ro.boot.flash.locked'
    $vbs  = Sh 'getprop ro.boot.verifiedbootstate'
    $rel  = Sh 'getprop ro.build.version.release'
    $os   = Sh 'getprop ro.lineage.version'
    if (-not $os) { $os = Sh 'getprop ro.build.version.ota' }

    $mark = if ($oem -eq '1') { 'OK  ' } else { 'FAIL' }
    $color = if ($oem -eq '1') { 'Green' } else { 'Red' }
    Write-Host ("  sys.oem_unlock_allowed      = {0,-6} [{1}]" -f $oem, $mark) -ForegroundColor $color
    Write-Host ("  ro.boot.flash.locked        = {0,-6} {1}" -f $lock, $(if ($lock -eq '0') { '[OK]' } else { '' }))
    Write-Host ("  ro.boot.verifiedbootstate   = {0,-6} {1}" -f $vbs, $(if ($vbs -eq 'orange') { '[OK]' } else { '' }))
    Write-Host ("  Android                     = $rel")
    Write-Host ("  ROM                         = $os")
}

# ------------------------------------------------------------------ bootloader 层
Write-Host "`n[3] Bootloader 层 / Bootloader layer"
Line
if (-not $hasFb) {
    Write-Host "  需要进入 fastboot 模式 / Enter fastboot mode:" -ForegroundColor Yellow
    Write-Host "    adb reboot bootloader" -ForegroundColor Yellow
    if ($hasAdb) {
        $ans = Read-Host "  现在自动重启到 fastboot？/ Reboot to fastboot now? (y/N)"
        if ($ans -eq 'y') {
            & $Adb reboot bootloader | Out-Null
            Write-Host "  等待 / waiting..." -ForegroundColor DarkGray
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Seconds 2
                if (((& $Fastboot devices 2>&1) -join '') -match 'fastboot') { $hasFb = $true; break }
            }
        }
    }
}

if ($hasFb) {
    $unlocked = Fb 'getvar unlocked'
    $ability  = ((& $Fastboot flashing get_unlock_ability 2>&1) -join ' ')
    $ability  = ($ability -replace '^.*?:\s*', '' -replace '\s+Finished.*', '').Trim()

    Write-Host ("  unlocked                    = {0}" -f $unlocked) `
        -ForegroundColor $(if ($unlocked -match 'yes') { 'Green' } else { 'Red' })
    Write-Host ("  get_unlock_ability          = {0}" -f $ability) `
        -ForegroundColor $(if ($ability -eq '1') { 'Green' } else { 'Red' })

    Write-Host "`n  oem device-info:"
    (& $Fastboot oem device-info 2>&1) | Select-Object -First 4 | ForEach-Object { Write-Host "    $_" }
}

# ------------------------------------------------------------------ 结论
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  结论 / Conclusion"
Write-Host "============================================================" -ForegroundColor Cyan

$unlockedOk = $hasFb -and ((Fb 'getvar unlocked') -match 'yes')
$flagOk     = $hasAdb -and ((Sh 'getprop sys.oem_unlock_allowed') -eq '1')

if ($unlockedOk) {
    Write-Host "  ★★★ BOOTLOADER 已解锁 / BOOTLOADER IS UNLOCKED" -ForegroundColor Green
} elseif ($flagOk) {
    Write-Host "  标志位已设置 (sys.oem_unlock_allowed = 1)" -ForegroundColor Yellow
    Write-Host "  但 bootloader 还没解锁 / but the bootloader is not unlocked yet" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  下一步 / Next:" -ForegroundColor Cyan
    Write-Host "    fastboot flashing unlock" -ForegroundColor White
    Write-Host "    ★ 然后在手机屏幕上按音量键选择、电源键确认" -ForegroundColor Yellow
    Write-Host "    ★ Then confirm ON THE PHONE with volume/power keys" -ForegroundColor Yellow
} else {
    Write-Host "  尚未解锁 / Not unlocked yet" -ForegroundColor Red
    Write-Host "  请先用 patch-ops-for-unlock.ps1 打补丁并刷入" -ForegroundColor Yellow
    Write-Host "  Run patch-ops-for-unlock.ps1 first, then flash" -ForegroundColor Yellow
}
Write-Host ""
