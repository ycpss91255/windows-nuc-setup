#Requires -Version 5.1
# Named runtime implementation: dot-sourcing defines functions without changing Windows.
function Get-SetupTerminalKnownFolder {
 param([Environment+SpecialFolder]$Folder,[Environment+SpecialFolderOption]$Option=[Environment+SpecialFolderOption]::None)
 [Environment]::GetFolderPath($Folder,$Option)
}
function Get-SetupTerminalContext {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 [pscustomobject]@{Folder=(Join-Path $env:LOCALAPPDATA 'NUC8-Setup\TerminalHotkey');Startup=(Join-Path (Get-SetupTerminalKnownFolder -Folder Startup) 'Terminal Hotkey.lnk');IdentityName=$identity.Name;UserSID=$identity.User.Value;UserHome=$env:USERPROFILE;PowerShell=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe');ReportPath=(Join-Path $env:ProgramData 'NUC8-Setup/TerminalHotkey-Result.json')}
}
function New-SetupTerminalShell {New-Object -ComObject WScript.Shell}
function Copy-SetupTerminalFiles {
 param([string]$ModuleRoot,[string]$DestinationRoot)
 . (Join-Path $ModuleRoot '../native/managed_source_library.ps1')
 foreach($name in @('terminal_hotkey_listener.ps1','terminal_hotkey_library.ps1')){Copy-Item -LiteralPath (Join-Path $ModuleRoot $name) -Destination (Join-Path $DestinationRoot $name) -Force}
 $null=Copy-SetupManagedSource -SourceRoot $ModuleRoot -DestinationRoot $DestinationRoot -FileName 'terminal_hotkey.cs'
}
function Invoke-SetupTerminalHotkey {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 $context=Get-SetupTerminalContext
 $folder=$context.Folder;$listener=Join-Path $folder 'terminal_hotkey_listener.ps1';$log=Join-Path $folder 'status.log';$startup=$context.Startup
 $taskName='NUC8-TerminalHotkey-'+$context.UserSID;$exe=$context.PowerShell
$argsText='-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$listener+'"'
if(-not $VerifyOnly){
 if(-not(Get-Command wt.exe -ErrorAction SilentlyContinue)){throw '找不到 Windows Terminal，請先安裝。'}
 New-Item -ItemType Directory $folder -Force|Out-Null
 Copy-SetupTerminalFiles -ModuleRoot $ModuleRoot -DestinationRoot $folder
 $shell=New-SetupTerminalShell
 $link=$shell.CreateShortcut($startup)
 $link.TargetPath=$exe;$link.Arguments=$argsText;$link.WorkingDirectory=$context.UserHome;$link.WindowStyle=7;$link.Hotkey='';$link.Save()
 $action=New-ScheduledTaskAction -Execute $exe -Argument $argsText
 $principal=New-ScheduledTaskPrincipal -UserId $context.IdentityName -LogonType Interactive -RunLevel Limited
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
if(Test-Path $startup){$link=(New-SetupTerminalShell).CreateShortcut($startup);$linkOK=$link.Arguments.Contains($listener)}
$success=($text -match '^REGISTERED:' -and $text -notmatch 'FAILED' -and $running.Count -gt 0 -and $linkOK)
New-Item -ItemType Directory (Split-Path $context.ReportPath) -Force|Out-Null
[ordered]@{Success=$success;User=$context.IdentityName;Shortcut='Ctrl+Alt+T';StartupLink=$startup;ListenerPath=$listener;ProcessIDs=@($running.ProcessId);Log=$text;CheckedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 4|Set-Content $context.ReportPath -Encoding UTF8
if(-not $success){throw ('Terminal 快捷鍵未成功註冊：'+$text)}
Write-Host 'Ctrl + Alt + T 已註冊，登入後自動啟用，以一般使用者權限開啟 Terminal。' -ForegroundColor Green
}
function New-SetupTerminalMutex {New-Object Threading.Mutex($false,'Local\NUC8TerminalHotkey')}
function Invoke-SetupTerminalNative {
 param([string]$ModuleRoot,[string]$Terminal,[string]$LogPath,[string]$UserHome)
 Add-Type -Path (Join-Path $ModuleRoot 'native/terminal_hotkey.cs')
 [NucTerminalHotkey]::Run($Terminal,$LogPath,$UserHome)
}
function Invoke-SetupTerminalListener {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot)
 $ErrorActionPreference='Stop'
 $context=Get-SetupTerminalContext;$log=Join-Path $context.Folder 'status.log'
 New-Item -ItemType Directory $context.Folder -Force|Out-Null
 $mutex=New-SetupTerminalMutex;$owned=$false
 try{
  $owned=$mutex.WaitOne(0)
  if(-not $owned){return}
  Invoke-SetupTerminalNative -ModuleRoot $ModuleRoot -Terminal (Get-Command wt.exe -ErrorAction Stop).Source -LogPath $log -UserHome $context.UserHome
 }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
