@echo off
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0..\..\Core\Run-Module.ps1" -Module "Install-Drivers" %*
