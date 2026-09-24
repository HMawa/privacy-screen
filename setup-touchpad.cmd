@echo off
chcp 65001 >nul
echo === Privacy Screen: Configure touchpad device-level blocking (UAC prompt will appear) ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0privacy-screen.ps1" -SetupTouchpadDevice
echo.
pause
