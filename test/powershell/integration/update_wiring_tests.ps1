#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$s=[IO.File]::ReadAllText((Join-Path $root 'modules/updates/install_windows_updates.ps1'))
Assert ($s.Contains('Invoke-SetupWindowsUpdateEntry') -and $s.Contains('-EntryPath $PSCommandPath -ModuleRoot $PSScriptRoot')) '薄入口明傳原始位置及執行模式'
$s+=[IO.File]::ReadAllText((Join-Path $root 'modules/updates/update_entry_library.ps1'))
Assert ($s.Contains('Invoke-SetupWindowsUpdateWorker')) '排程worker入口呼叫已驗證具名worker'
$stageSource=[IO.File]::ReadAllText((Join-Path $root 'modules/updates/update_stage_library.ps1'))
foreach($name in @('update_entry_library.ps1','update_stage_library.ps1','update_progress_library.ps1','update_worker_library.ps1','native/update_callback.cs')){Assert ($stageSource.Contains($name)) ('排程copy完整runtime相依 '+$name)}
Assert ($s.IndexOf("`$existing -and `$existing.State -eq 'Running'") -lt $s.IndexOf('New-SetupUpdateStage')) '拒絕執行中工作早於覆寫worker檔案'
Assert ($s.Contains('PercentComplete') -and $s.Contains('UpdatedAt')) '父視窗使用真百分比與heartbeat'
Assert (-not $s.Contains('Windows 未提供即時百分比')) '移除錯誤的Windows不提供百分比說明'
. (Join-Path $root 'core/paths.ps1')
$stageSource=[IO.File]::ReadAllText((Join-Path $root 'modules/updates/update_stage_library.ps1'))
foreach($name in @('update_entry_library.ps1','update_stage_library.ps1','update_progress_library.ps1','update_worker_library.ps1','update_callback.cs')){Assert (Test-Path (Resolve-NucPath $name)) ('依賴可攜路徑可解析 '+$name)}
$required=Get-Content (Join-Path $root 'core/test_setup_prerequisites.ps1') -Raw
Assert ($required.Contains("'update_progress_library.ps1'") -and $required.Contains("'update_worker_library.ps1'") -and $required.Contains("'update_callback.cs'")) 'PackageOnly檢查更新的新runtime依賴'
Write-Host 'ALL PASS: update wiring contracts; no scheduled tasks executed'