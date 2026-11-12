#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1')
function Assert([bool]$condition,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$condition}|ConvertTo-Json -Compress));if(-not $condition){throw $name}}
$parent=Join-Path ([IO.Path]::GetTempPath()) ('bundle_helper_contract_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($parent)
$beforeLocation=(Get-Location).Path;$beforeEnv=$env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR
try {
 $result=New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'fixture')
 Assert ($result.Metadata.kind -ceq 'Synthetic' -and (Test-Path -LiteralPath $result.Source -PathType Container) -and (Test-Path -LiteralPath $result.Archive -PathType Leaf) -and (Test-Path -LiteralPath $result.BundleTool -PathType Leaf) -and (Test-Path -LiteralPath $result.CoverageTool -PathType Leaf)) 'fixture includes synthetic metadata, source, archive, and real tools'
 Assert ((Get-Location).Path -ceq $beforeLocation -and $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR -ceq $beforeEnv) 'restores process environment and location'
 $rejected=$false;try{New-TestReportBundleFixture -RepositoryRoot $root -Destination $result.Root|Out-Null}catch{$rejected=$true}
 Assert $rejected 'rejects existing destination'
}finally {Set-Location -LiteralPath $beforeLocation; $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=$beforeEnv}
