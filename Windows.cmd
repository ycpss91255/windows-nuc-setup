@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0core\Start-Windows.ps1" %*
