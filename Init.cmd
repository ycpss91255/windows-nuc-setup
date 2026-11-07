@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0modules\init\Initialize-NUC.ps1" -SshScriptPath "%~dp0modules\ssh\Apply-SSHSettings.ps1"
