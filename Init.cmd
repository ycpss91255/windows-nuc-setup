@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Modules\Init\Initialize-NUC.ps1" -SshScriptPath "%~dp0Modules\SSH\Apply-SSHSettings.ps1"
