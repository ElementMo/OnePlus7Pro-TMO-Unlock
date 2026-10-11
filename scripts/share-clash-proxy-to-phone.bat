@echo off
chcp 65001 >nul
title 开放 Clash 代理给局域网（手机用）

:: ============================================================
::  自动提权：如果没有管理员权限，重新以管理员身份启动自己
:: ============================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   正在请求管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo ============================================================
echo   开放 Clash 代理端口给局域网
echo ------------------------------------------------------------
echo   端口    : TCP 7897
echo   用途    : 让手机走电脑的 Clash 代理上网
echo   范围    : 仅本地局域网（192.168.x.x / 10.x.x.x）
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "Get-NetFirewallRule -DisplayName 'Clash Proxy 7897*' | Remove-NetFirewallRule;" ^
  "$r = New-NetFirewallRule -DisplayName 'Clash Proxy 7897 (LAN)' -Description 'Allow LAN devices to use Clash HTTP/SOCKS proxy on 7897' -Direction Inbound -Protocol TCP -LocalPort 7897 -Action Allow -Profile Any -RemoteAddress LocalSubnet;" ^
  "if ($r) { Write-Host ''; Write-Host '  [OK] 防火墙规则已添加:' -ForegroundColor Green; Write-Host ('       ' + $r.DisplayName + '  [' + $r.Action + ']  ' + $r.Direction); Write-Host ''; Write-Host '  现在手机可以连 192.168.31.194:7897 了' -ForegroundColor Green }" ^
  "else { Write-Host '  [失败] 规则没加上' -ForegroundColor Red }"

echo.
echo ============================================================
echo   接下来的手机端设置
echo ------------------------------------------------------------
echo   1) 设置 - 网络和互联网 - 互联网
echo      点 WLAN 名称右边的齿轮 - 右上角编辑 - 高级选项
echo      代理 - 手动
echo          主机名: 192.168.31.194
echo          端口  : 7897
echo      保存
echo.
echo   2) 浏览器打开 google.com 验证
echo ============================================================
echo.
pause
