#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1')
function Assert([bool]$condition,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$condition}|ConvertTo-Json -Compress));if(-not $condition){throw $name}}
$helperBytes=[IO.File]::ReadAllBytes((Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1'))
Assert ($helperBytes.Length -ge 3 -and $helperBytes[0] -eq 0xEF -and $helperBytes[1] -eq 0xBB -and $helperBytes[2] -eq 0xBF) 'shared PowerShell helper uses UTF-8 BOM'
$parent=Join-Path ([IO.Path]::GetTempPath()) ('bundle_helper_contract_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($parent)
$beforeLocation=(Get-Location).Path;$beforeEnv=$env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR
try {
 $result=New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'fixture')
 Assert ($result.Metadata.kind -ceq 'Synthetic' -and (Test-Path -LiteralPath $result.Source -PathType Container) -and (Test-Path -LiteralPath $result.Archive -PathType Leaf) -and (Test-Path -LiteralPath $result.BundleTool -PathType Leaf) -and (Test-Path -LiteralPath $result.CoverageTool -PathType Leaf)) 'fixture includes synthetic metadata, source, archive, and real tools'
 Assert ((Get-Location).Path -ceq $beforeLocation -and $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR -ceq $beforeEnv) 'restores process environment and location'
 $rejected=$false;try{New-TestReportBundleFixture -RepositoryRoot $root -Destination $result.Root|Out-Null}catch{$rejected=$true}
 Assert $rejected 'rejects existing destination'
 $meta=$result.Metadata
 & $result.BundleTool verify --historical --archive $result.Archive --archive-sha256 $meta.sha256 --archive-size ([string]$meta.size) --source-root $result.Source --version $meta.version --commit $meta.commit | Out-Null
 Assert ($LASTEXITCODE -eq 0) 'real verifier accepts generated archive'
 $oldPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue'; & $result.BundleTool verify --historical --archive $result.Archive --archive-sha256 ('0'*64) --archive-size ([string]$meta.size) --source-root $result.Source --version $meta.version --commit $meta.commit 2>$null | Out-Null; $badExit=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 Assert ($badExit -ne 0) 'real verifier rejects invalid digest'
 function go.exe { $global:LASTEXITCODE=1 }
 $failed=$false;try{New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'failed')|Out-Null}catch{$failed=$true}finally{Remove-Item Function:\go.exe}
 Assert ($failed -and (Get-Location).Path -ceq $beforeLocation -and $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR -ceq $beforeEnv) 'failure restores environment and location'

}finally {Set-Location -LiteralPath $beforeLocation; $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=$beforeEnv}
