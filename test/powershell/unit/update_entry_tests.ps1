#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/updates/update_entry_library.ps1'
Assert (Test-Path -LiteralPath $library) 'WU既有控制器提供可隔離執行的正式具名來源'
. $library
$fixture=Join-Path $env:TEMP ('update_entry_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
function Get-SetupWindowsUpdateCommonDataRoot {$global:UpdateFixture.Common}
function Get-ScheduledTask {param($TaskName,$ErrorAction) $global:UpdateFixture.TaskReads++;[pscustomobject]@{State=$(if($global:UpdateFixture.Mode -eq 'initial_running' -or ($global:UpdateFixture.Mode -eq 'race_running' -and $global:UpdateFixture.TaskReads -gt 1) -or ($global:UpdateFixture.Mode -eq 'timeout' -and $global:UpdateFixture.TaskReads -ge 3) -or $global:UpdateFixture.TaskReads -eq 3){'Running'}else{'Ready'})}}
function Get-ScheduledTaskInfo {param($TaskName) [pscustomobject]@{LastRunTime=$global:UpdateFixture.BaseDate.AddSeconds(1);LastTaskResult=$(if($global:UpdateFixture.Mode -eq 'native_failure'){5}else{0})}}
function New-ScheduledTaskAction {param($Execute,$Argument) $global:UpdateFixture.Action=@{Execute=$Execute;Argument=$Argument};'action'}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) $global:UpdateFixture.Principal=@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel};'principal'}
function New-ScheduledTaskSettingsSet {param($ExecutionTimeLimit,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) 'settings'}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$Settings,[switch]$Force) $global:UpdateFixture.Registered++}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm) $global:UpdateFixture.Unregistered++}
function Start-ScheduledTask {param($TaskName) $global:UpdateFixture.Started++;if($global:UpdateFixture.Mode -ne 'missing_result'){[IO.File]::WriteAllText((Join-Path $global:UpdateFixture.Stage 'WindowsUpdate-Result.json'),'{"Success":true}')} ;[IO.File]::WriteAllText((Join-Path $global:UpdateFixture.Stage 'Update-Progress.json'),'{"Stage":"download","Detail":"fixture item","UpdatedAt":"fixture heartbeat","PercentComplete":37}');[IO.File]::WriteAllText((Join-Path $global:UpdateFixture.Stage 'WindowsUpdate-fixture.log'),'log')}
function Start-Sleep {param($Seconds) $global:UpdateFixture.Sleeps.Add($Seconds)}
function Get-Date {param($Format) $global:UpdateFixture.ClockReads++;$date=if($global:UpdateFixture.Mode -eq 'timeout' -and $global:UpdateFixture.ClockReads -gt 2){$global:UpdateFixture.BaseDate.AddHours(3)}else{$global:UpdateFixture.BaseDate};if($Format){$date.ToString($Format)}else{$date}}
function Write-Progress {param($Id,$Activity,$Status,$CurrentOperation,$PercentComplete,[switch]$Completed) if(-not $Completed){$global:UpdateFixture.Progress.Add([int]$PercentComplete)}}
$stageLibrary=@'
function New-SetupUpdateStage {
 param($SourceRoot,$CommonDataRoot,$UserSid,$Computer)
 $global:UpdateFixture.Created++;$global:UpdateFixture.SourceRoot=$SourceRoot;$global:UpdateFixture.UserSID=$UserSid;$global:UpdateFixture.Computer=$Computer
 $lock=[pscustomobject]@{};$lock|Add-Member ScriptMethod Dispose {$global:UpdateFixture.Disposed=$true}
 [pscustomobject]@{Path=$global:UpdateFixture.Stage;Lock=$lock}
}
function Assert-SetupUpdateProtectedPath {param($Path)}
function Assert-SetupUpdateAncestors {param($CommonDataRoot) $global:UpdateFixture.Ancestors++}
function Read-SetupUpdateContext {param($StageRoot) $global:UpdateFixture.ContextReads++;if($global:UpdateFixture.Mode -eq 'bad_context'){throw 'fixture foreign context'};[pscustomobject]@{RunId='fixture-run';Root=$StageRoot}}
'@
try{
 foreach($mode in @('success','initial_running','race_running','native_failure','missing_result','timeout','bad_context','worker','worker_bad_root')){
  $case=Join-Path $fixture $mode;$moduleRoot=Join-Path $case 'modules/updates';$common=Join-Path $case 'common';$stage=Join-Path $common 'windows_setup_update'
  foreach($path in @($moduleRoot,$stage)){[void][IO.Directory]::CreateDirectory($path)}
  $global:UpdateFixture=@{Mode=$mode;Common=$common;Stage=$stage;BaseDate=[datetime]::Now;TaskReads=0;ClockReads=0;Registered=0;Unregistered=0;Started=0;Created=0;Disposed=$false;ContextReads=0;Ancestors=0;WorkerCalls=0;Sleeps=[Collections.Generic.List[int]]::new();Progress=[Collections.Generic.List[int]]::new()}
  foreach($path in @($moduleRoot,$stage)){
   [IO.File]::WriteAllText((Join-Path $path 'update_stage_library.ps1'),$stageLibrary,[Text.UTF8Encoding]::new($true))
   [IO.File]::WriteAllText((Join-Path $path 'update_progress_library.ps1'),'# definitions only',[Text.UTF8Encoding]::new($true))
   [IO.File]::WriteAllText((Join-Path $path 'update_worker_library.ps1'),'function Invoke-SetupWindowsUpdateWorker {param($StateRoot,$Context) $global:UpdateFixture.WorkerCalls++;$global:UpdateFixture.WorkerRoot=$StateRoot;$global:UpdateFixture.WorkerContext=$Context}',[Text.UTF8Encoding]::new($true))
  }
  if($mode -eq 'success'){[IO.File]::WriteAllText((Join-Path $stage 'WindowsUpdate-Result.json'),'old result')}
  $worker=$mode -like 'worker*';$callRoot=if($mode -eq 'worker'){$stage}else{$moduleRoot}
  $caught='';try{Invoke-SetupWindowsUpdateEntry -EntryPath (Join-Path $callRoot 'install_windows_updates.ps1') -ModuleRoot $callRoot -Worker:$worker}catch{$caught=$_.Exception.Message}
  if($worker){Assert (($global:UpdateFixture.WorkerCalls -eq 1) -eq ($mode -eq 'worker')) ('只有受保護stage worker才進正式worker路由 '+$mode);if($mode -eq 'worker'){Assert ($global:UpdateFixture.WorkerRoot -eq $stage -and $global:UpdateFixture.WorkerContext.RunId -eq 'fixture-run' -and $global:UpdateFixture.Ancestors -eq 1) 'worker明傳stage根目錄與受驗context'}else{Assert ($caught -like '*只能從本機受保護stage*' -and $global:UpdateFixture.ContextReads -eq 0) '外部worker在context與原生操作前拒絕'};continue}
  Assert (($caught -eq '') -eq ($mode -eq 'success')) ('WU控制器結果保留真失敗 '+$mode)
  Assert ($global:UpdateFixture.Disposed -eq ($mode -ne 'initial_running')) ('所有已取lease路徑finally釋放 '+$mode)
  if($mode -in @('initial_running','race_running','bad_context')){Assert ($global:UpdateFixture.Registered -eq 0 -and $global:UpdateFixture.Started -eq 0) ('既有工作與不可信context不註冊或啟動 '+$mode)}
  if($mode -eq 'success'){Assert ($global:UpdateFixture.SourceRoot -eq $moduleRoot -and $global:UpdateFixture.UserSID -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $global:UpdateFixture.Computer -eq $env:COMPUTERNAME) 'stage取動態模組根目錄與同機SID';Assert ($global:UpdateFixture.Progress.Contains(37) -and $global:UpdateFixture.Sleeps.Contains(15)) '真API百分比與心跳輪詢保留';Assert ((Test-Path (Join-Path $moduleRoot 'WindowsUpdate-Result.json')) -and (Test-Path (Join-Path $moduleRoot 'WindowsUpdate-fixture.log')) -and @(Get-ChildItem $stage -Filter 'Previous-*.json').Count -eq 1) '結果與log複製到傳入模組位置並保留前輪結果';Assert ($global:UpdateFixture.Unregistered -eq 1 -and $global:UpdateFixture.Principal.UserId -eq 'SYSTEM' -and $global:UpdateFixture.Action.Argument -like '*Update-Worker.ps1* -Worker') '排程身分與worker路由保持'}
  if($mode -in @('native_failure','missing_result')){Assert ($global:UpdateFixture.Unregistered -eq 1 -and $caught -like '*未完全成功*') ('原生非零或缺結果不冒稱成功 '+$mode)}
  if($mode -eq 'timeout'){Assert ($caught -like '*更新尚未完成*' -and $global:UpdateFixture.Unregistered -eq 0) '超時保留診斷與執行中工作，不假完成'}
 }
}finally{Remove-Variable UpdateFixture -Scope Global -ErrorAction SilentlyContinue}
