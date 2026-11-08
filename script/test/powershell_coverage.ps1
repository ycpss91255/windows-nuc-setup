#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManifestPath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[int]$WorkerIndex=-1,[string]$PesterModule,[string]$PwshPath)
$ErrorActionPreference='Stop'
$version='6.0.0'
# SHA512 from the official Gallery version metadata, not from a local binary.
$packageHash='AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA=='
function Write-Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function Get-PinnedPester {
 $cache=Join-Path ([IO.Path]::GetTempPath()) 'windows_setup_pester_6_0_0'
 [void][IO.Directory]::CreateDirectory($cache)
 $zip=Join-Path $cache 'pester.zip'
 if($env:WINDOWS_SETUP_PESTER_PACKAGE_PATH){
  $zip=[IO.Path]::GetFullPath($env:WINDOWS_SETUP_PESTER_PACKAGE_PATH)
  if(-not(Test-Path -LiteralPath $zip -PathType Leaf)){throw '預備的 Pester 套件不存在，拒絕退回網路或使用者快取。'}
 }
 if(-not(Test-Path -LiteralPath $zip)){
  $download=Join-Path $cache ([guid]::NewGuid().ToString('N')+'.download')
  $tls=[Net.ServicePointManager]::SecurityProtocol
  try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest -Uri 'https://www.powershellgallery.com/api/v2/package/Pester/6.0.0' -OutFile $download -UseBasicParsing}finally{[Net.ServicePointManager]::SecurityProtocol=$tls}
  $hash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($download)))
  if($hash -cne $packageHash){throw 'Pester 官方套件 SHA512 不符。'}
  [IO.File]::Copy($download,$zip,$true)
 }
 $hash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($zip)))
 if($hash -cne $packageHash){throw 'Pester 快取 SHA512 不符，拒絕載入。'}
 $module=Join-Path $cache ([guid]::NewGuid().ToString('N'))
 Expand-Archive -LiteralPath $zip -DestinationPath $module
 return Join-Path $module 'Pester.psd1'
}
if($WorkerIndex -lt 0 -and $PSVersionTable.PSVersion.Major -ne 5){throw '收集管理程序要求 Windows PowerShell 5.1。'}
$manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$source=[IO.Path]::GetFullPath([string]$manifest.SourceRoot).TrimEnd('\','/')
if(-not(Test-Path -LiteralPath $source -PathType Container)){throw '來源根目錄不存在。'}
function Resolve-InputFile([string]$Relative){
 if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)){throw '必須使用來源根目錄內的相對檔名。'}
 $path=[IO.Path]::GetFullPath((Join-Path $source $Relative))
 if(-not $path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('來源遺失或越界：'+$Relative)}
 return $path
}
$sources=@($manifest.Sources|ForEach-Object {Resolve-InputFile $_})
$tests=@($manifest.Tests|ForEach-Object {Resolve-InputFile $_})
$wrapper=if($manifest.Wrapper){Resolve-InputFile $manifest.Wrapper}else{$null}
if(-not $sources.Count -or -not $tests.Count -or @($sources|Select-Object -Unique).Count -ne $sources.Count -or @($tests|Select-Object -Unique).Count -ne $tests.Count){throw '來源或測試清單不可空白或重複。'}
if(@($sources|Where-Object {$_ -in $tests -or [IO.Path]::GetExtension($_) -ine '.ps1'}).Count){throw '正式來源必須為 PS1，且不可與測試重疊。'}
$engines=@{}
if($null -ne $manifest.TestEngines){
 if($manifest.TestEngines -isnot [pscustomobject]){throw 'TestEngines 必須為 suite 到引擎的對照物件。'}
 foreach($property in $manifest.TestEngines.PSObject.Properties){
  if($property.Name -cnotin @($manifest.Tests) -or $property.Value -isnot [string] -or $property.Value -cnotin @('powershell','pwsh')){throw 'TestEngines 包含未知 suite 或不支援的引擎。'}
  $engines[$property.Name]=$property.Value
 }
}
function Get-TestEngine([int]$Index){$name=[string]$manifest.Tests[$Index];if($engines.ContainsKey($name)){return $engines[$name]};return 'powershell'}
function Test-EngineVersion([string]$Engine,[string]$Version){
 $actual=[version]$Version
 if($Engine -eq 'pwsh'){return $actual.Major -eq 7 -and $actual -ge [version]'7.4'}
 return $actual.Major -eq 5 -and $actual.Minor -eq 1
}
$hashes=@($sources|ForEach-Object {[pscustomobject]@{File=$_.Substring($source.Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($WorkerIndex -ge 0){
 if($WorkerIndex -ge $tests.Count -or -not(Test-Path -LiteralPath $PesterModule -PathType Leaf)){throw '子程序參數不完整。'}
 $engine=Get-TestEngine $WorkerIndex
 if(-not(Test-EngineVersion $engine $PSVersionTable.PSVersion.ToString())){throw '子程序實際引擎不符合指定版本；pwsh 必須為 7.4 以上的 7.x。'}
 $engineExecutable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
 $engineHash=(Get-FileHash -LiteralPath $engineExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
 Import-Module -Name $PesterModule -Force
 if((Get-Module Pester).Version.ToString() -cne $version){throw 'Pester 版本不符。'}
 $config=New-PesterConfiguration
 $config.Run.Path=@($tests[$WorkerIndex]);$config.Run.RepoRoot=$source;$config.Run.PassThru=$true
 if($wrapper){$config.Run.Path=@();$config.Run.Container=@(New-PesterContainer -Path $wrapper -Data @{SuitePath=$tests[$WorkerIndex];SourceRoot=$source})}
 $config.CodeCoverage.Enabled=$true;$config.CodeCoverage.Path=$sources;$config.CodeCoverage.ExcludeTests=$false
 $config.CodeCoverage.OutputFormat='Cobertura';$config.CodeCoverage.OutputPath=Join-Path $output ('worker_'+$WorkerIndex+'.xml')
 $config.CodeCoverage.CoveragePercentTarget=0
 $result=Invoke-Pester -Configuration $config
 if($result.FailedCount -gt 0 -or $result.PassedCount -lt 1 -or $result.Result -ne 'Passed'){throw 'Pester 測試未全部成功。'}
 $commands=@($result.CodeCoverage.CommandsExecuted)+@($result.CodeCoverage.CommandsMissed)
 if(-not $commands.Count){throw '沒有真實命令覆蓋率證據。'}
 $rows=@(foreach($command in $commands){
  $file=[IO.Path]::GetFullPath([string]$command.File)
  if($file -notin $sources -or $command.StartLine -lt 1 -or $command.StartColumn -lt 1){throw 'Pester 證據來源不符。'}
  [pscustomobject]@{File=$file.Substring($source.Length+1).Replace('\','/');Line=[int]$command.StartLine;Column=[int]$command.StartColumn;EndLine=[int]$command.EndLine;EndColumn=[int]$command.EndColumn;Hit=([int]$command.HitCount -gt 0)}
 })
 foreach($expected in $hashes){if($expected.File -notin $rows.File){throw ('Pester 未提供完整來源分母：'+$expected.File)}}
 Write-Json (Join-Path $output ('worker_'+$WorkerIndex+'.json')) ([ordered]@{ProcessId=$PID;PesterVersion=$version;Engine=$engine;EngineVersion=$PSVersionTable.PSVersion.ToString();EngineSHA256=$engineHash;Sources=$hashes;Commands=$rows})
 exit 0
}
if(Test-Path -LiteralPath $output){throw '輸出目錄必須是全新目錄。'}
[void][IO.Directory]::CreateDirectory($output)
$module=Get-PinnedPester
$launchers=@{powershell=(Join-Path $PSHOME 'powershell.exe')}
if(@($engines.Values|Where-Object {$_ -eq 'pwsh'}).Count){
 if(-not $PwshPath){$PwshPath=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source}
 $PwshPath=[IO.Path]::GetFullPath($PwshPath)
 if(-not(Test-Path -LiteralPath $PwshPath -PathType Leaf)){throw '找不到指定的 pwsh；不會降級為 Windows PowerShell。'}
 $launchers.pwsh=$PwshPath
}
$workers=@();$merged=@{};$expectedKeys=$null
for($i=0;$i -lt $tests.Count;$i++){
 $requestedEngine=Get-TestEngine $i;$launcher=$launchers[$requestedEngine]
 $launcherHash=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToLowerInvariant()
 & $launcher -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ManifestPath $ManifestPath -OutputDirectory $output -WorkerIndex $i -PesterModule $module
 if($LASTEXITCODE -ne 0){throw ('PowerShell 覆蓋率子程序失敗：'+$i)}
 $worker=Get-Content -LiteralPath (Join-Path $output ('worker_'+$i+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 if($worker.Engine -cne $requestedEngine -or $worker.EngineSHA256 -cne $launcherHash -or -not(Test-EngineVersion $requestedEngine $worker.EngineVersion)){throw '子程序引擎版本或執行檔雜湊不一致。'}
 if(($worker.Sources|ConvertTo-Json -Compress) -cne ($hashes|ConvertTo-Json -Compress)){throw '子程序來源雜湊不一致。'}
 $keys=@(foreach($row in $worker.Commands){$key=$row.File+':'+$row.Line+':'+$row.Column+':'+$row.EndLine+':'+$row.EndColumn;if(-not $merged.ContainsKey($key)){$merged[$key]=$row}else{$merged[$key].Hit=$merged[$key].Hit -or $row.Hit};$key})
 [Array]::Sort($keys,[StringComparer]::Ordinal)
 if($null -eq $expectedKeys){$expectedKeys=$keys}elseif(($keys -join "`n") -cne ($expectedKeys -join "`n")){throw '子程序命令分母不一致。'}
 $workers+=@([pscustomobject]@{Index=$i;ProcessId=$worker.ProcessId;Engine=$worker.Engine;EngineVersion=$worker.EngineVersion;EngineSHA256=$worker.EngineSHA256;Evidence=('worker_'+$i+'.json')})
}
foreach($item in $hashes){if((Get-FileHash -LiteralPath (Join-Path $source $item.File)).Hash.ToLowerInvariant() -cne $item.SHA256){throw '量測期間來源變更。'}}
$xml=[xml]'<?xml version="1.0" encoding="utf-8"?><coverage version="1" lines-covered="0" lines-valid="0" line-rate="0"><sources><source>.</source></sources><packages><package name="PowerShell"><classes /></package></packages></coverage>'
$xml.coverage.SetAttribute('coverage-metric','complete-executable-lines-v1')
$xml.coverage.SetAttribute('coverage-schema','1')
$total=0;$covered=0
foreach($item in $hashes){
 $class=$xml.CreateElement('class');$class.SetAttribute('name',$item.File);$class.SetAttribute('filename',$item.File)
 $lines=$xml.CreateElement('lines');[void]$class.AppendChild($lines)
 foreach($group in @($merged.Values|Where-Object File -ceq $item.File|Group-Object Line|Sort-Object {[int]$_.Name})){
  $hit=@($group.Group|Where-Object {-not $_.Hit}).Count -eq 0
  $line=$xml.CreateElement('line');$line.SetAttribute('number',$group.Name);$line.SetAttribute('hits',([int]$hit).ToString());[void]$lines.AppendChild($line)
  $total++;if($hit){$covered++}
 }
 [void]$xml.SelectSingleNode('/coverage/packages/package/classes').AppendChild($class)
}
if(-not $total){throw '可執行行分母為空。'}
foreach($item in $hashes){$item|Add-Member -NotePropertyName ExpectedLines -NotePropertyValue @($merged.Values|Where-Object File -ceq $item.File|Select-Object -ExpandProperty Line -Unique|Sort-Object)}
$xml.coverage.SetAttribute('lines-covered',$covered.ToString());$xml.coverage.SetAttribute('lines-valid',$total.ToString());$xml.coverage.SetAttribute('line-rate',($covered/[double]$total).ToString([Globalization.CultureInfo]::InvariantCulture))
Write-Json (Join-Path $output 'evidence.json') ([ordered]@{SchemaVersion=1;PesterVersion=$version;PackageSHA512=$packageHash;Sources=$hashes;Workers=$workers;Metric='FullyCoveredCommandStartLines';Covered=$covered;Total=$total})
$xml.Save((Join-Path $output 'coverage.xml'))
Write-Host ('PowerShell 原檔可執行行覆蓋率：'+$covered+'/'+$total+'；僅此清單範圍，不是整個儲存庫。')
