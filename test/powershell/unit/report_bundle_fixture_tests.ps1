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
 $meta=$result.Metadata
 & $result.BundleTool verify --historical --archive $result.Archive --archive-sha256 $meta.sha256 --archive-size ([string]$meta.size) --source-root $result.Source --version $meta.version --commit $meta.commit | Out-Null
 Assert ($LASTEXITCODE -eq 0) 'real verifier accepts generated archive'
 $oldPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue'; & $result.BundleTool verify --historical --archive $result.Archive --archive-sha256 ('0'*64) --archive-size ([string]$meta.size) --source-root $result.Source --version $meta.version --commit $meta.commit 2>$null | Out-Null; $badExit=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 Assert ($badExit -ne 0) 'real verifier rejects invalid digest'
 function go.exe { $global:LASTEXITCODE=1 }
 $failed=$false;try{New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'failed')|Out-Null}catch{$failed=$true}finally{Remove-Item Function:\go.exe}
 Assert ($failed -and (Get-Location).Path -ceq $beforeLocation -and $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR -ceq $beforeEnv) 'failure restores environment and location'
 function go.exe { Write-Output 'PRIVATE-CREDENTIAL-SENTINEL C:\Users\private\secret';$global:LASTEXITCODE=1 }
 $failureOutput=@(& {try{New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'failed_diagnostic')|Out-Null}catch{}} 6>&1)
 Remove-Item Function:\go.exe
 $rendered=($failureOutput|ForEach-Object {$_.ToString()}) -join "`n"
 Assert ($rendered.Contains('@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed')) 'fixture 失敗輸出固定允許的階段與原因'
 Assert (-not $rendered.Contains('PRIVATE-CREDENTIAL-SENTINEL') -and -not $rendered.Contains('C:\Users\private')) 'fixture 原始輸出不公開私人內容'

}finally {Set-Location -LiteralPath $beforeLocation; $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=$beforeEnv}
