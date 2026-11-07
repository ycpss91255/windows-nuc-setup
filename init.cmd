@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0modules\init\initialize_nuc.ps1" -SshScriptPath "%~dp0modules\ssh\apply_ssh_settings.ps1"
