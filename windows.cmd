@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0core\start_windows.ps1" %*
