#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$folder=Join-Path $env:LOCALAPPDATA 'NUC8-Setup\TerminalHotkey'
$listener=Join-Path $folder 'terminal_hotkey_listener.ps1'
$log=Join-Path $folder 'status.log'
$startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'Terminal Hotkey.lnk'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$taskName='NUC8-TerminalHotkey-'+$identity.User.Value
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argsText='-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$listener+'"'
if(-not $VerifyOnly){
 if(-not(Get-Command wt.exe -ErrorAction SilentlyContinue)){throw '找不到 Windows Terminal，請先安裝。'}
 New-Item -ItemType Directory $folder -Force|Out-Null
 Copy-Item (Join-Path $PSScriptRoot 'terminal_hotkey_listener.ps1') $listener -Force
 $shell=New-Object -ComObject WScript.Shell
 $link=$shell.CreateShortcut($startup)
 $link.TargetPath=$exe;$link.Arguments=$argsText;$link.WorkingDirectory=$env:USERPROFILE;$link.WindowStyle=7;$link.Hotkey='';$link.Save()
 $action=New-ScheduledTaskAction -Execute $exe -Argument $argsText
 $principal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if(-not $task -or $task.State -ne 'Running'){
  Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force|Out-Null
  Start-ScheduledTask $taskName
 }
 for($i=0;$i -lt 20;$i++){if((Test-Path $log) -and ([IO.File]::ReadAllText($log)) -match 'REGISTERED|FAILED'){break};Start-Sleep -Seconds 1}
}
$text=if(Test-Path $log){[IO.File]::ReadAllText($log)}else{''}
$running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($listener) -and $_.SessionId -gt 0})
$linkOK=$false
if(Test-Path $startup){$link=(New-Object -ComObject WScript.Shell).CreateShortcut($startup);$linkOK=$link.Arguments.Contains($listener)}
$success=($text -match '^REGISTERED:' -and $text -notmatch 'FAILED' -and $running.Count -gt 0 -and $linkOK)
$root=Join-Path $env:ProgramData 'NUC8-Setup';New-Item -ItemType Directory $root -Force|Out-Null
[ordered]@{Success=$success;User=$identity.Name;Shortcut='Ctrl+Alt+T';StartupLink=$startup;ListenerPath=$listener;ProcessIDs=@($running.ProcessId);Log=$text;CheckedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'TerminalHotkey-Result.json') -Encoding UTF8
if(-not $success){throw ('Terminal 快捷鍵未成功註冊：'+$text)}
Write-Host 'Ctrl + Alt + T 已註冊，登入後自動啟用，以一般使用者權限開啟 Terminal。' -ForegroundColor Green

