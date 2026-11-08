#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$lib=Join-Path $root 'modules/updates/update_worker_library.ps1'
Assert (Test-Path $lib) '真更新worker可安全呼叫具名來源'
. (Join-Path $root 'modules/updates/update_progress_library.ps1');. $lib
function Start-Transcript {param($Path)};function Stop-Transcript {}
function Restart-Computer {throw '禁止重開機'}
$script:ops=@();$script:failInstall=$false;$script:downloaded=$true
$script:update=[pscustomobject]@{Title='fixture update';InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$false};EulaAccepted=$true;IsDownloaded=$true}
$script:searcher=New-Object PSObject;$script:searcher|Add-Member ScriptMethod Search {param($query) [pscustomobject]@{Updates=@($script:update)}}
$script:session=[pscustomobject]@{ClientApplicationID=''};$script:session|Add-Member ScriptMethod CreateUpdateSearcher {$script:searcher};$script:session|Add-Member ScriptMethod CreateUpdateDownloader {[pscustomobject]@{Updates=$null}};$script:session|Add-Member ScriptMethod CreateUpdateInstaller {[pscustomobject]@{Updates=$null}}
function New-Object {param([Parameter(Position=0)]$TypeName,[Parameter(Position=1)]$ArgumentList,$ComObject) if($ComObject){switch($ComObject){'Microsoft.Update.Session'{return $script:session};'Microsoft.Update.UpdateColl'{return ,(New-Object Collections.ArrayList)};'Microsoft.Update.SystemInfo'{return [pscustomobject]@{RebootRequired=$true}};default{throw '禁止未知COM'}}};Microsoft.PowerShell.Utility\New-Object @PSBoundParameters}
function Invoke-SetupUpdateOperation {param($Operation,$Client,$Titles,$ProgressPath) $script:ops+=@($Operation);if($Operation -eq 'Download'){return [pscustomobject]@{ResultCode=2}};$o=[pscustomobject]@{RebootRequired=$true};$o|Add-Member ScriptMethod GetUpdateResult {param($Index) [pscustomobject]@{ResultCode=$(if($script:failInstall){4}else{2});HResult=0}};return $o}
$d=Join-Path ([IO.Path]::GetTempPath()) ('update_worker_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d)
Invoke-SetupWindowsUpdateWorker -StateRoot $d
$r=Get-Content (Join-Path $d 'WindowsUpdate-Result.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert (($script:ops -join ',') -eq 'Download,Install') '真worker下載安裝都呼叫非同步進度helper'
Assert ($r.Selected -eq 1 -and $r.Updates.Count -eq 1 -and $r.RebootRequired) '保留每項結果與需要重開機但不重開'
$p=Get-Content (Join-Path $d 'Update-Progress.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($p.Stage -eq '本輪完成' -and $p.UpdatedAt -and $null -eq $p.PercentComplete) '非下載安裝階段不製造百分比並含heartbeat'
$script:failInstall=$true;$failed=$false;try{Invoke-SetupWindowsUpdateWorker -StateRoot $d}catch{$failed=$true}
Assert $failed '更新結果失敗不能假完成'
$p=Get-Content (Join-Path $d 'Update-Progress.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($p.Stage -eq '更新未完成') '失敗仍留下可讀進度log'
$script:failInstall=$false;$script:update.IsDownloaded=$false;$script:ops=@();$failed=$false;try{Invoke-SetupWindowsUpdateWorker -StateRoot $d}catch{$failed=$true}
Assert ($failed -and ($script:ops -join ',') -eq 'Download') '未下載完成不啟動安裝且結果失敗'
Write-SetupUpdateProgress -Path (Join-Path $d 'progress.json') -Stage '下載更新' -Detail test -PercentComplete 47 -CurrentUpdate 2 -TotalUpdates 4 -CurrentTitle '真標題' -CurrentPercent 53
$p=Get-Content (Join-Path $d 'progress.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($p.PercentComplete -eq 47 -and $p.CurrentUpdate -eq 2 -and $p.TotalUpdates -eq 4 -and $p.CurrentTitle -eq '真標題' -and $p.CurrentPercent -eq 53 -and $p.UpdatedAt) '原子進度JSON保存真值與心跳'
Write-Host 'ALL PASS: original worker with mocked COM only'