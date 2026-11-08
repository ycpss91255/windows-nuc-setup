#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$collector=Join-Path $root 'script/test/powershell_coverage.ps1'
Assert (Test-Path -LiteralPath $collector) '提供原始 PowerShell 檔案的真覆蓋率收集器'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ps coverage 中文 '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
function WriteFixture($Name,$Text){[IO.File]::WriteAllText((Join-Path $fixture $Name),$Text,[Text.UTF8Encoding]::new($true))}
WriteFixture 'branch.ps1' @'
function Select-Value([bool]$Positive){
 if($Positive){
  return 'positive'
 }
 return 'negative'
}
'@
WriteFixture 'never.ps1' @'
function Never-Called {
 return 'unused'
}
'@
foreach($side in @('positive','negative')){
 $value=if($side -eq 'positive'){'$true'}else{'$false'}
 WriteFixture ($side+'.Tests.ps1') ("BeforeAll { . (Join-Path `$PSScriptRoot 'branch.ps1') }`nDescribe 'original source' { It 'selects value' { Select-Value $value | Should-Be '$side' } }")
}
$manifest=Join-Path $fixture 'manifest.json'
$input=[ordered]@{SourceRoot=$fixture;Sources=@('branch.ps1','never.ps1');Tests=@('positive.Tests.ps1','negative.Tests.ps1')}
[IO.File]::WriteAllText($manifest,($input|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$out=Join-Path $fixture 'coverage'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory $out *> (Join-Path $fixture 'collector.log')
Assert ($LASTEXITCODE -eq 0) ('PS5.1 子程序真收集成功，診斷 '+$fixture)
[xml]$merged=Get-Content (Join-Path $out 'coverage.xml') -Raw
$classes=@($merged.coverage.packages.package.classes.class)
Assert (@($classes|Where-Object filename -ceq 'never.ps1').Count -eq 1) '完全未執行檔仍在分母'
$never=@(($classes|Where-Object filename -ceq 'never.ps1').lines.line)
Assert ($never.Count -gt 0 -and @($never|Where-Object {[int]$_.hits -ne 0}).Count -eq 0) '未執行來源保留零命中'
$branch=@(($classes|Where-Object filename -ceq 'branch.ps1').lines.line)
Assert (@($branch|Where-Object {[int]$_.number -eq 3 -and [int]$_.hits -gt 0}).Count -eq 1) '原檔第3行 positive 分支命中'
Assert (@($branch|Where-Object {[int]$_.number -eq 5 -and [int]$_.hits -gt 0}).Count -eq 1) '第二子程序原檔第5行命中合併'
[xml]$first=Get-Content (Join-Path $out 'worker_0.xml') -Raw
$firstBranch=@(($first.coverage.packages.package.classes.class|Where-Object filename -eq 'branch.ps1').lines.line)
Assert (@($firstBranch|Where-Object {[int]$_.number -eq 5 -and [int]$_.hits -eq 0}).Count -eq 1) '首子程序未執行分支真顯示未命中'
$evidence=Get-Content (Join-Path $out 'evidence.json') -Raw|ConvertFrom-Json
Assert ($evidence.Workers.Count -eq 2 -and @($evidence.Workers.ProcessId|Select-Object -Unique).Count -eq 2) '每套測試由獨立程序收集'
Assert ($evidence.Sources.Count -eq 2 -and $evidence.PesterVersion -eq '6.0.0') '來源清單及固定工具版本保留'
foreach($case in @('missing','empty','outside','failed_test')){
 $bad=[ordered]@{SourceRoot=$fixture;Sources=@('branch.ps1','never.ps1');Tests=@('positive.Tests.ps1')}
 switch($case){missing{$bad.Sources+=@('missing.ps1')} empty{$bad.Sources=@()} outside{$bad.Sources=@('../outside.ps1')} failed_test{WriteFixture 'failed.Tests.ps1' "Describe 'bad' { It 'fails' { 1 | Should-Be 2 } }";$bad.Tests=@('failed.Tests.ps1')}}
 $badPath=Join-Path $fixture ($case+'.json');[IO.File]::WriteAllText($badPath,($bad|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $badPath -OutputDirectory (Join-Path $fixture $case) *> (Join-Path $fixture ($case+'.log'))
 $ErrorActionPreference='Stop'
 Assert ($LASTEXITCODE -ne 0) ('拒絕不完整證據：'+$case)
 Assert (-not(Test-Path (Join-Path (Join-Path $fixture $case) 'coverage.xml'))) ('失敗不發布總報告：'+$case)
}
