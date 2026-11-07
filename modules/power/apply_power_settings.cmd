@echo off
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0..\..\core\run_module.ps1" -Module "Apply-PowerSettings" %*
