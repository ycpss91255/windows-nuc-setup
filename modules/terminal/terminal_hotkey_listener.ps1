$ErrorActionPreference='Stop'
$folder=Join-Path $env:LOCALAPPDATA 'NUC8-Setup\TerminalHotkey'
$log=Join-Path $folder 'status.log'
New-Item -ItemType Directory $folder -Force|Out-Null
$mutex=New-Object Threading.Mutex($false,'Local\NUC8TerminalHotkey')
if(-not $mutex.WaitOne(0)){exit}
try{
Add-Type -Path (Join-Path $PSScriptRoot 'native/terminal_hotkey.cs')
[NucTerminalHotkey]::Run((Get-Command wt.exe -ErrorAction Stop).Source,$log,$env:USERPROFILE)
}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
