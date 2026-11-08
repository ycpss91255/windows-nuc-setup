#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Describe {param($Name,[scriptblock]$Body) & $Body}
function It {param($Name,[scriptblock]$Body) & $Body}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('coverage_cwd_'+[guid]::NewGuid().ToString('N'));$testDir=Join-Path $fixture 'test/powershell/unit';[void][IO.Directory]::CreateDirectory($testDir)
[IO.File]::WriteAllText((Join-Path $fixture 'marker.ps1'),'$global:CoverageCwdMarker=$PWD.Path')
$suite=Join-Path $testDir 'relative_tests.ps1';[IO.File]::WriteAllText($suite,". .\marker.ps1")
$caller=(Get-Location).Path
& (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -SuitePath $suite -SourceRoot $fixture
Assert ($global:CoverageCwdMarker -eq $fixture) '安全suite使用真SourceRoot解析相對workflow路徑'
Assert ((Get-Location).Path -eq $caller) '成功後還原呼叫端目錄'
[IO.File]::WriteAllText($suite,"throw 'fixture suite failed'")
$failed=$false;try{& (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -SuitePath $suite -SourceRoot $fixture}catch{$failed=$_.Exception.Message -eq 'fixture suite failed'}
Assert $failed '原suite失敗如實傳遞'
Assert ((Get-Location).Path -eq $caller) '失敗後仍還原呼叫端目錄'
foreach($layer in @('unit','integration')){
 $directory=Join-Path $fixture ('test/powershell/'+$layer);[void][IO.Directory]::CreateDirectory($directory)
 $numeric=Join-Path $directory 'driver_manifest_v2_tests.ps1'
 [IO.File]::WriteAllText($numeric,('$global:CoverageCwdMarker='''+$layer+'2'''))
 & (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -SuitePath $numeric -SourceRoot $fixture
 Assert ($global:CoverageCwdMarker -ceq ($layer+'2') -and (Get-Location).Path -eq $caller) ('合法數字 '+$layer+' suite 原樣執行並還原工作目錄')
}
Remove-Variable CoverageCwdMarker -Scope Global -ErrorAction SilentlyContinue
