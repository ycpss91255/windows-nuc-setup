#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$temp=Join-Path $env:TEMP ('rollup_boundary_'+[guid]::NewGuid().ToString('N'))
foreach($dir in @('.github/workflows','test/powershell/integration','script/test')){[void][IO.Directory]::CreateDirectory((Join-Path $temp $dir))}
try {
 $source=[IO.File]::ReadAllText((Join-Path $root 'test/powershell/integration/ci_quality_summary_workflow_tests.ps1'))
 $anchor='$step=[regex]::Match'
 Assert ($source.Contains($anchor)) '實際 workflow 測試擷取入口存在'
 Copy-Item -LiteralPath (Join-Path $root 'script/test/ci_quality_summary.ps1') -Destination (Join-Path $temp 'script/test/ci_quality_summary.ps1')
 Copy-Item -LiteralPath (Join-Path $root 'script/test/ci_tasks.ps1') -Destination (Join-Path $temp 'script/test/ci_tasks.ps1')
 $workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
 foreach($id in @('_Next_job','Next_Job')){
  $fixture=$workflow.Replace('cache-diagnostic-prime',$id)
  Assert ($fixture -cne $workflow) '樣本實際更改緊接 rollup 的 job ID'
  [IO.File]::WriteAllText((Join-Path $temp '.github/workflows/windows_tests.yml'),$fixture,[Text.UTF8Encoding]::new($false))
  $probe="if (`$rollup -match '(?m)^  $($id):') {throw 'rollup included next job'}`n"
  $script=$source.Replace($anchor,$probe+$anchor)
  $path=Join-Path $temp 'test/powershell/integration/ci_quality_summary_workflow_tests.ps1'
  [IO.File]::WriteAllText($path,$script,[Text.UTF8Encoding]::new($true))
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$result=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($code -ne 0 -and ($result -join "`n") -match 'rollup included next job'){Write-Host 'fixture detected rollup included next job'}
  if($code -ne 0){$result | Select-Object -Last 8 | ForEach-Object {Write-Host $_}}
  Assert ($code -eq 0 -and ($result -join "`n") -match '實際 rollup 失敗時明示未完整量測且保留失敗') ('合法後續 job ID 不可進入 rollup，且原測試完整通過：'+$id)
  $oobe=[IO.File]::ReadAllText((Join-Path $root 'test/powershell/integration/oobe_workflow_tests.ps1'))
  $oobeAnchor='$scriptText='
  Assert ($oobe.Contains($oobeAnchor)) '實際 OOBE workflow 測試擷取入口存在'
  $oobe=$oobe.Replace($oobeAnchor,$probe+$oobeAnchor)
  $oobePath=Join-Path $temp 'test/powershell/integration/oobe_workflow_tests.ps1'
  [IO.File]::WriteAllText($oobePath,$oobe,[Text.UTF8Encoding]::new($true))
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$oobeResult=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oobePath 2>&1);$oobeCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($oobeCode -ne 0){$oobeResult | Select-Object -Last 8 | ForEach-Object {Write-Host $_}}
  Assert ($oobeCode -eq 0 -and ($oobeResult -join "`n") -match 'ALL PASS: 16 workflow contract assertions') ('合法後續 job ID 不可影響 OOBE 全部原斷言：'+$id)
 }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
$global:LASTEXITCODE=0
