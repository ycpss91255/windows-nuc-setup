#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('pester_registry_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
. (Join-Path $root 'script/docker/install_managed_tools.ps1')
$artifact=Get-ContainerPesterArtifact
$package=if($env:WINDOWS_SETUP_PESTER_PACKAGE_PATH){$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH}else{Join-Path ([IO.Path]::GetTempPath()) 'windows_setup_pester_6_0_0/pester.zip'}
if(-not(Test-Path -LiteralPath $package -PathType Leaf)){$package=Join-Path $fixture 'pester.zip';Invoke-ContainerOfficialDownload -Uri $artifact.Uri -OutFile $package}
$hash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($package)))
Assert ($hash -ceq $artifact.Hash) '使用與正式collector相同官方Pester套件雜湊，不修改vendor'
$moduleRoot=Join-Path $fixture 'pinned';Expand-Archive -LiteralPath $package -DestinationPath $moduleRoot
$source=Join-Path $fixture 'source'
foreach($directory in @('core','test/powershell/unit','test/powershell/coverage')){[void][IO.Directory]::CreateDirectory((Join-Path $source $directory))}
[IO.File]::WriteAllText((Join-Path $source 'core/example.ps1'),'function Example { return 7 }',[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $source 'test/powershell/unit/safe_tests.ps1'),'. (Join-Path $PSScriptRoot ''../../../core/example.ps1'');if((Example) -ne 7){throw ''wrong fixture result''};Write-Host ''@@ASSERT@@{"Name":"owned safe suite executed","Passed":true}''',[Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -Destination (Join-Path $source 'test/powershell/coverage/safe_suite.ps1')
$collector=Join-Path $root 'script/test/powershell_coverage.ps1';$launcher=Join-Path $root 'test/powershell/support/pester_registry_worker.ps1'
$engines=@(@{Name='powershell';Path=(Get-Command powershell.exe -CommandType Application|Select-Object -First 1).Source},@{Name='pwsh';Path=(Get-Command pwsh.exe -CommandType Application|Select-Object -First 1).Source})
$outcomes=@()
foreach($engine in $engines){
 $manifest=Join-Path $fixture ($engine.Name+'.json');$output=Join-Path $fixture $engine.Name;$profile=Join-Path $fixture ($engine.Name+'.profile.json')
 $value=@{SourceRoot=$source;Sources=@('core/example.ps1');Tests=@('test/powershell/unit/safe_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1';TestEngines=@{'test/powershell/unit/safe_tests.ps1'=$engine.Name}}
 [IO.File]::WriteAllText($manifest,($value|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));[void][IO.Directory]::CreateDirectory($output)
 $stdout=Join-Path $fixture ($engine.Name+'.private.stdout.log');$stderr=Join-Path $fixture ($engine.Name+'.private.stderr.log')
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Collector',$collector,'-Manifest',$manifest,'-Output',$output,'-PesterModule',(Join-Path $moduleRoot 'Pester.psd1'),'-ObservationPath',$profile)
 $process=Start-Process -FilePath $engine.Path -ArgumentList @($arguments|ForEach-Object {'"'+$_+'"'}) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $null=$process.Handle
 if(-not $process.WaitForExit(120000)){$process.Kill();[void]$process.WaitForExit(5000);throw 'Pester registry fixture exceeded its bounded native deadline.'}
 $observed=Get-Content -LiteralPath $profile -Raw -Encoding UTF8|ConvertFrom-Json
 $text=[IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8)+[IO.File]::ReadAllText($stderr,[Text.Encoding]::UTF8)
 $proof=Join-Path $output 'worker_0.json'
 if($process.ExitCode -ne 0){
  Assert ($observed.ParentCreateAttempts -gt 0 -and $text.Contains('Was not able to create a Pester Registry key')) ($engine.Name+' 確認非環境故障而是官方共享scratch建構失敗')
  Assert (-not $text.Contains('@@ASSERT@@') -and -not(Test-Path -LiteralPath $proof) -and -not(Test-Path -LiteralPath (Join-Path $output 'evidence.json'))) ($engine.Name+' 建構失敗先於自有斷言且無完整證據')
 }
 $outcomes+=@{Engine=$engine.Name;Code=$process.ExitCode;Observed=$observed;Text=$text;Proof=$proof}
}
Assert (@($outcomes|Where-Object Code -ne 0).Count -eq 0) '兩個實際collector引擎均須避開未使用的共享Registry plugin並正常完成'
foreach($result in $outcomes){
 Assert (-not $result.Observed.Observed.TestRegistryEnabled -and $result.Observed.ParentCreateAttempts -eq 0 -and $result.Observed.UnexpectedRegistryMutationCalls -eq 0) ($result.Engine+' 真config停用TestRegistry且不存取真機碼')
 Assert ($result.Observed.Observed.TestDriveEnabled -and $result.Observed.Observed.CodeCoverageEnabled -and $result.Observed.Observed.CoveragePathCount -eq 1 -and $result.Observed.Observed.PassThru) ($result.Engine+' 原TestDrive與完整覆蓋率設定保留')
 Assert ($result.Text.Contains('@@ASSERT@@{"Name":"owned safe suite executed","Passed":true}') -and (Test-Path -LiteralPath $result.Proof)) ($result.Engine+' 原safe_suite確實執行自有斷言並留下原生證據')
 $worker=Get-Content -LiteralPath $result.Proof -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($worker.Engine -ceq $result.Engine -and $worker.Sources.Count -eq 1 -and @($worker.Commands|Where-Object Hit).Count -gt 0) ($result.Engine+' 證據保留實際引擎來源分母及命中')
}
