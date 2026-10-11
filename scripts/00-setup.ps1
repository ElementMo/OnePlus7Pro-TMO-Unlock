<#
.SYNOPSIS
    One-time setup: installs Python dependencies and fetches oppo_decrypt.
    一次性环境准备：安装 Python 依赖并下载 oppo_decrypt。

.DESCRIPTION
    Run this once before using patch-ops-for-unlock.ps1.
    首次使用前运行一次。

.EXAMPLE
    .\scripts\00-setup.ps1
    .\scripts\00-setup.ps1 -ToolsDir "D:\tools"
#>

[CmdletBinding()]
param(
    # Where to put oppo_decrypt. Defaults to <repo>/tools/oppo_decrypt
    # oppo_decrypt 的存放位置，默认放在仓库的 tools/oppo_decrypt
    [string]$ToolsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "tools\oppo_decrypt")
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Ok($m)   { Write-Host "  [OK] $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m"   -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [X]  $m"   -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OnePlus 7 Pro TMO Unlock — Setup" -ForegroundColor Cyan
Write-Host "  一加 7 Pro TMO 解锁 — 环境准备" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. Python
Write-Host "`n[1/3] 检查 Python / Checking Python"
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) {
    Die @"
找不到 Python。请先安装 Python 3.8+ 并加入 PATH。
Python not found. Install Python 3.8+ and add it to PATH.
  https://www.python.org/downloads/
"@
}
$ver = (& $py.Source --version 2>&1) -join ''
Ok "$ver  ($($py.Source))"

# ---------------------------------------------------------------- 2. Deps
Write-Host "`n[2/3] 安装 Python 依赖 / Installing Python dependencies"
$deps = @('pycryptodome', 'pycryptodomex', 'docopt')

& $py.Source -c "import Crypto, Cryptodome, docopt" 2>$null
if ($LASTEXITCODE -eq 0) {
    Ok "依赖已就绪 / dependencies already present"
} else {
    Write-Host "  正在安装: $($deps -join ', ')" -ForegroundColor DarkGray
    & $py.Source -m pip install --quiet --disable-pip-version-check @deps
    if ($LASTEXITCODE -ne 0) {
        Warn "pip 安装可能失败，尝试继续 / pip may have failed, continuing"
    }
    & $py.Source -c "import Crypto, Cryptodome, docopt" 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "依赖安装完成 / dependencies installed" }
    else { Die "依赖安装失败，请手动执行: pip install pycryptodome pycryptodomex docopt" }
}

# ---------------------------------------------------------------- 3. oppo_decrypt
Write-Host "`n[3/3] 获取 oppo_decrypt / Fetching oppo_decrypt"
$opsCrypto = Join-Path $ToolsDir "opscrypto.py"

if (Test-Path $opsCrypto) {
    Ok "已存在 / already present: $opsCrypto"
} else {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zip = Join-Path $env:TEMP "oppo_decrypt.zip"
    $url = "https://github.com/bkerler/oppo_decrypt/archive/refs/heads/master.zip"

    Write-Host "  下载 / downloading: $url" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 180
    } catch {
        # 有些环境 TLS 吊销检查会失败，退回到 curl
        Warn "Invoke-WebRequest 失败，改用 curl / falling back to curl"
        & curl.exe -sL --ssl-no-revoke --max-time 180 -o $zip $url
    }
    if (-not (Test-Path $zip)) { Die "下载失败 / download failed" }
    Ok "已下载 $([math]::Round((Get-Item $zip).Length/1KB,1)) KB"

    $tmp = Join-Path $env:TEMP "oppo_decrypt_extract"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)

    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $inner) { Die "解压失败 / extraction failed" }

    Get-ChildItem $inner.FullName -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $ToolsDir $_.Name) -Force
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    if (Test-Path $opsCrypto) { Ok "已安装 / installed: $opsCrypto" }
    else { Die "安装失败 / install failed" }
}

# ---------------------------------------------------------------- 完成
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup complete / 环境准备完成" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next / 下一步:" -ForegroundColor Cyan
Write-Host "    .\scripts\patch-ops-for-unlock.ps1 -OpsPath <your.ops>"
Write-Host ""
Write-Host "  oppo_decrypt is by bkerler — https://github.com/bkerler/oppo_decrypt" -ForegroundColor DarkGray
Write-Host ""
