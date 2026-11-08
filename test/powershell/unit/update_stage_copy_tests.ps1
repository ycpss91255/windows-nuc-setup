#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name,[string]$Expected){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and -not($failure.Exception -is [Management.Automation.ParameterBindingException]) -and $failure.Exception.Message.Contains($Expected)) $Name}
. (Join-Path $root 'modules/updates/update_stage_library.ps1')
Assert ([bool](Get-Command New-SetupUpdateStage -ErrorAction SilentlyContinue)) 'stage複製與驗證有具名入口'
$d=Join-Path ([IO.Path]::GetTempPath()) ('stage_copy_'+[guid]::NewGuid().ToString('N'));$source=Join-Path $d 'source';$common=Join-Path $d 'programdata';[void][IO.Directory]::CreateDirectory((Join-Path $source 'native'));[void][IO.Directory]::CreateDirectory($common)
foreach($name in @('install_windows_updates.ps1','update_progress_library.ps1','update_worker_library.ps1','update_stage_library.ps1','native/update_callback.cs')){[IO.File]::WriteAllText((Join-Path $source $name),'fixture '+$name)}
# Only ACL/native-create boundaries are mocked below. Actual paths, file copy, SHA256 and file locking remain real TEMP operations.
function Assert-SetupUpdateAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $common){throw 'test guard'};Assert-SetupUpdatePlainPath $CommonDataRoot}
function New-SetupUpdateProtectedDirectory {param($Path) if(-not $Path.StartsWith($common+'\')){throw 'test guard'};Assert-SetupUpdatePlainPath $Path;[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupUpdateProtectedPath {param($Path,[switch]$Directory) if(-not $Path.StartsWith($common+'\')){throw 'test guard'};Assert-SetupUpdatePlainPath $Path;if(-not(Test-Path $Path)){throw 'missing fixture'}}
$call=@{SourceRoot=$source;CommonDataRoot=$common;UserSid='S-1-5-21-1-2-3-1001';Computer='fixture-pc'}
$stage=New-SetupUpdateStage @call
try{
 Assert ($stage.Path -eq (Join-Path $common 'windows_setup_update')) 'SYSTEM來源直接使用獨立專用root而非舊父目錄'
 Assert ($stage.Context.Files.Count -eq 5 -and $stage.Context.RunId) '五個runtime依賴全部記錄SHA與本輪ID'
 Assert (@($stage.Context.Files|Where-Object {(Get-FileHash (Join-Path $stage.Path $_.Name)).Hash -ine $_.SHA256}).Count -eq 0) '真複製後hash逐項核對'
 Reject {New-SetupUpdateStage @call} '並行stage寫入遭獨占鎖拒絕' '已被另一個'
 $context=Read-SetupUpdateContext -StageRoot $stage.Path
 Assert ($context.UserSID -eq $call.UserSid -and $context.Computer -eq 'fixture-pc') '工作context保留啟動者而非SYSTEM帳號'
 $target=Join-Path $stage.Path 'Update-Worker.ps1';[IO.File]::WriteAllText($target,'tampered')
 Reject {Read-SetupUpdateContext -StageRoot $stage.Path} '複製後執行來源遭改動拒絕' '雜湊'
}finally{$stage.Lock.Dispose()}
$stage=New-SetupUpdateStage @call
try{
 $result=@{RunId=$stage.Context.RunId;Computer=$call.Computer;UserSID=$call.UserSid;Selected=0;Updates=@();CompletedAt='fixture'}
 $result|ConvertTo-Json|Set-Content (Join-Path $stage.Path 'WindowsUpdate-Result.json') -Encoding UTF8
 $r=Read-SetupUpdateResult -CommonDataRoot $common -LegacyRoot (Join-Path $d 'legacy') -UserSid $call.UserSid -Computer $call.Computer
  Assert ($r.RunId -eq $stage.Context.RunId) '結果只接受本機本帳號與受保護context本輪ID'
 $result.SearchResultCode=4;$result|ConvertTo-Json|Set-Content (Join-Path $stage.Path 'WindowsUpdate-Result.json') -Encoding UTF8
 Reject {Read-SetupUpdateResult -CommonDataRoot $common -LegacyRoot (Join-Path $d 'legacy') -UserSid $call.UserSid -Computer $call.Computer} '搜尋失敗的零項結果不可在總驗證變成成功' '搜尋'
 $result.SearchResultCode=2
 $result.RunId=[guid]::NewGuid().ToString();$result|ConvertTo-Json|Set-Content (Join-Path $stage.Path 'WindowsUpdate-Result.json') -Encoding UTF8
 Reject {Read-SetupUpdateResult -CommonDataRoot $common -LegacyRoot (Join-Path $d 'legacy') -UserSid $call.UserSid -Computer $call.Computer} '舊輪成功結果不得混用' '身分或本輪'
}finally{$stage.Lock.Dispose()}
Assert (Test-Path (Join-Path $stage.Path 'Update-Worker.ps1')) '完成測試保留stage不遞迴刪除資料'
$verifyText=Get-Content (Join-Path $root 'core/verification_library.ps1') -Raw
Assert ($verifyText.Contains('Read-SetupUpdateResult')) '正式總驗證使用受保護context讀取更新結果'
$auditText=Get-Content (Join-Path $root 'core/audit_nuc.ps1') -Raw
Assert ($auditText.Contains('Read-SetupUpdateResult')) '稽核使用相同更新結果身分核對'
