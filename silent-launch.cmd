@echo off
chcp 65001 >nul
rem Privacy Screen - Silent launcher (fallback, prefer silent-launch.exe)
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0privacy-screen.ps1" -HideConsole
