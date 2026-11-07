@echo off
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0..\..\core\Run-Module.ps1" -Module "Apply-HostsSync" -SyncOnly -Mode SSH %*

