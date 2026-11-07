#Requires -Version 5.1
#Requires -RunAsAdministrator
param([string]$WindowsPath=$env:WINDIR)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'oobe_library.ps1')
$statePath=Join-Path $PSScriptRoot 'state.json'
Assert-InitPlainPath $PSScriptRoot
Assert-InitPlainPath $statePath
$state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
if($state.Marker -notmatch '^NUC-INIT-[a-f0-9]{32}$'){throw 'Init 清理標記無效。'}
$removed=@();$errors=@()
$candidates=@((Join-Path $PSScriptRoot 'answer.xml'))+@(Get-InitAnswerCandidates -WindowsPath $WindowsPath)
foreach($path in $candidates){
 try{
  Assert-InitPlainPath $path
  if(Test-Path -LiteralPath $path -PathType Leaf){
   $text=[IO.File]::ReadAllText($path)
   if($text.Contains([string]$state.Marker)){Remove-Item -LiteralPath $path -Force;$removed+=$path}
  }
 }catch{$errors+=('暫存檔清理失敗：'+$path)}
}
$report=[ordered]@{Success=($errors.Count -eq 0 -and -not(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'answer.xml')));UserName=$state.UserName;CheckedAt=(Get-Date).ToString('o');Removed=$removed;Errors=$errors}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'cleanup-result.json'),($report|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
if(-not $report.Success){throw 'Init 暫存檔未完全清理，請查看受保護資料夾內 cleanup-result.json。'}
