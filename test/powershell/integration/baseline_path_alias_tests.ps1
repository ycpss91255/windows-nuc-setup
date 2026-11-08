#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('baseline_alias_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source directory long'
foreach($dir in @('core','test/powershell/unit','test/powershell/integration','test/powershell/coverage')){[void][IO.Directory]::CreateDirectory((Join-Path $source $dir))}
[IO.File]::WriteAllText((Join-Path $source 'core/example.ps1'),'function Example {return 1}')
foreach($layer in @('unit','integration')){[IO.File]::WriteAllText((Join-Path $source ('test/powershell/'+$layer+'/example_tests.ps1')),'# safe fixture')}
Copy-Item -LiteralPath (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -Destination (Join-Path $source 'test/powershell/coverage/safe_suite.ps1')
& git -C $source init --quiet;& git -C $source add .;& git -C $source -c user.name=CoverageFixture -c user.email=fixture@example.invalid commit --quiet -m fixture
if($LASTEXITCODE){throw 'isolated source git preparation failed'}
$long=(Get-ChildItem -LiteralPath $fixture -Directory|Where-Object Name -ceq 'source directory long').FullName
$filesystem=New-Object -ComObject Scripting.FileSystemObject
$short=$filesystem.GetFolder($long).ShortPath
$inputs=@($long);if($short -cne $long){$inputs+=@($short)}
$baseline=@();$i=0
foreach($path in $inputs){
 $output=Join-Path $fixture ('manifest_'+$i+'.json');$i++
 & (Join-Path $root 'test/powershell/coverage/create_baseline_manifest.ps1') -SourceRoot $path -OutputPath $output
 $m=Get-Content -LiteralPath $output -Raw -Encoding UTF8|ConvertFrom-Json
 Assert (($m.Tests -join ',') -ceq 'test/powershell/integration/example_tests.ps1,test/powershell/unit/example_tests.ps1') '同一原生來源的長或短別名保留完整互斥安全suite集合'
 Assert (($m.Sources -join ',') -ceq 'core/example.ps1' -and $m.Wrapper -ceq 'test/powershell/coverage/safe_suite.ps1') '別名不改來源分母或實際wrapper'
 $baseline+=@($m)
}
Assert ($baseline.Count -eq $inputs.Count) '可用原生8.3別名均實際驗證，不修改OS短檔名設定'
$literal=Join-Path $fixture 'source [literal] 中文';Copy-Item -LiteralPath $long -Destination $literal -Recurse
$literalOutput=Join-Path $fixture 'literal.json'
& (Join-Path $root 'test/powershell/coverage/create_baseline_manifest.ps1') -SourceRoot $literal -OutputPath $literalOutput
$literalManifest=Get-Content -LiteralPath $literalOutput -Raw -Encoding UTF8|ConvertFrom-Json
Assert (($literalManifest.Tests -join ',') -ceq ($baseline[0].Tests -join ',') -and ($literalManifest.Sources -join ',') -ceq ($baseline[0].Sources -join ',')) '字面括號、中文及空白來源路徑仍完整枚舉，不把名稱當wildcard'
$global:LASTEXITCODE=0
