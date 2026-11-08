#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$collector=Join-Path $root 'script/test/powershell_coverage.ps1'
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$temp=Join-Path $env:TEMP ('worker_encoding_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
function Write-Fixture($Name,$Text){[IO.File]::WriteAllText((Join-Path $temp $Name),$Text,[Text.UTF8Encoding]::new($true))}
Write-Fixture 'logic.ps1' "function Get-FixtureText { '設定包不存在或超過' }"
Write-Fixture 'error_cli.ps1' "throw '設定包不存在或超過 1 MiB，未執行抽取。'"
Write-Fixture 'warm.Tests.ps1' @'
BeforeAll { . (Join-Path $PSScriptRoot 'logic.ps1') }
Describe 'verified Pester preparation' { It 'uses original one-line fixture' {Get-FixtureText|Should-Be '設定包不存在或超過';[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pester_path.txt'),(Join-Path (Get-Module Pester).ModuleBase 'Pester.psd1'))} }
'@
Write-Fixture 'native.Tests.ps1' @'
BeforeAll { . (Join-Path $PSScriptRoot 'logic.ps1') }
Describe 'native Chinese diagnostics' { It 'keeps actual CLI failure text under an OEM parent' {
 Get-FixtureText|Should-Be '設定包不存在或超過'
 $log=Join-Path $PSScriptRoot 'native.private.log';$prior=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'error_cli.ps1') *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
 $code|Should-Be 1
 ([IO.File]::ReadAllText($log) -match '設定包不存在或超過')|Should-Be $true
} }
'@
$manifest=@{SourceRoot=$temp;Sources=@('logic.ps1');Tests=@('warm.Tests.ps1')}
$warm=Join-Path $temp 'warm.json';$manifest|ConvertTo-Json|Set-Content $warm -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $warm -OutputDirectory (Join-Path $temp 'warm_output') *> (Join-Path $temp 'warm.private.log')
Assert ($LASTEXITCODE -eq 0) '以正式collector準備已核對Pester，僅一行真source不遞迴全repo'
$pester=[IO.File]::ReadAllText((Join-Path $temp 'pester_path.txt'))
$manifest.Tests=@('native.Tests.ps1');$target=Join-Path $temp 'target.json';$manifest|ConvertTo-Json|Set-Content $target -Encoding UTF8
$output=Join-Path $temp 'target_output';[void][IO.Directory]::CreateDirectory($output)
function Quote-Path([string]$Value){return "'"+$Value.Replace("'","''")+"'"}
$body='$env:PSModulePath=($env:ProgramFiles+''\WindowsPowerShell\Modules;''+$env:WINDIR+''\System32\WindowsPowerShell\v1.0\Modules'')'+"`n"+'[Console]::OutputEncoding=[Text.Encoding]::GetEncoding(437)'+"`n"+'$global:OutputEncoding=[Text.Encoding]::GetEncoding(437)'+"`n"+'& '+(Quote-Path $collector)+' -ManifestPath '+(Quote-Path $target)+' -OutputDirectory '+(Quote-Path $output)+' -WorkerIndex 0 -PesterModule '+(Quote-Path $pester)
Write-Fixture 'cp437.ps1' $body
$shell=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/WindowsPowerShell/v1.0/powershell.exe'
$process=Start-Process -FilePath $shell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $temp 'cp437.ps1')+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $temp 'cp437.private.stdout.log') -RedirectStandardError (Join-Path $temp 'cp437.private.stderr.log')
try{$null=$process.Handle;$process.WaitForExit();$code=$process.ExitCode}finally{$process.Dispose()}
Assert ($code -eq 0 -and (Test-Path (Join-Path $output 'worker_0.json'))) '獨立CP437真coverage worker保留原生CLI中文錯誤契約'
Write-Host 'ALL PASS: actual bounded worker under OEM437; no global code-page or host settings changed'
