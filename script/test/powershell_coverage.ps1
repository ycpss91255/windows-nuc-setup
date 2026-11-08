#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManifestPath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[int]$WorkerIndex=-1,[string]$PesterModule)
$ErrorActionPreference='Stop'
$version='6.0.0'
# SHA512 from the official Gallery version metadata, not from a local binary.
$packageHash='AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA=='
function Write-Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function Get-PinnedPester {
 $cache=Join-Path ([IO.Path]::GetTempPath()) 'windows_setup_pester_6_0_0'
 [void][IO.Directory]::CreateDirectory($cache)
 $zip=Join-Path $cache 'pester.zip'
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
if($PSVersionTable.PSVersion.Major -ne 5){throw '此收集器要求 Windows PowerShell 5.1。'}
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
if(-not $sources.Count -or -not $tests.Count -or @($sources|Select-Object -Unique).Count -ne $sources.Count -or @($tests|Select-Object -Unique).Count -ne $tests.Count){throw '來源或測試清單不可空白或重複。'}
if(@($sources|Where-Object {$_ -in $tests -or [IO.Path]::GetExtension($_) -ine '.ps1'}).Count){throw '正式來源必須為 PS1，且不可與測試重疊。'}
$hashes=@($sources|ForEach-Object {[pscustomobject]@{File=$_.Substring($source.Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($WorkerIndex -ge 0){
 if($WorkerIndex -ge $tests.Count -or -not(Test-Path -LiteralPath $PesterModule -PathType Leaf)){throw '子程序參數不完整。'}
 Import-Module -Name $PesterModule -Force
 if((Get-Module Pester).Version.ToString() -cne $version){throw 'Pester 版本不符。'}
 $config=New-PesterConfiguration
 $config.Run.Path=@($tests[$WorkerIndex]);$config.Run.RepoRoot=$source;$config.Run.PassThru=$true
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
 Write-Json (Join-Path $output ('worker_'+$WorkerIndex+'.json')) ([ordered]@{ProcessId=$PID;PesterVersion=$version;Sources=$hashes;Commands=$rows})
 exit 0
}
if(Test-Path -LiteralPath $output){throw '輸出目錄必須是全新目錄。'}
[void][IO.Directory]::CreateDirectory($output)
$module=Get-PinnedPester
$workers=@();$merged=@{};$expectedKeys=$null
for($i=0;$i -lt $tests.Count;$i++){
 & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ManifestPath $ManifestPath -OutputDirectory $output -WorkerIndex $i -PesterModule $module
 if($LASTEXITCODE -ne 0){throw ('PowerShell 覆蓋率子程序失敗：'+$i)}
 $worker=Get-Content -LiteralPath (Join-Path $output ('worker_'+$i+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 if(($worker.Sources|ConvertTo-Json -Compress) -cne ($hashes|ConvertTo-Json -Compress)){throw '子程序來源雜湊不一致。'}
 $keys=@(foreach($row in $worker.Commands){$key=$row.File+':'+$row.Line+':'+$row.Column+':'+$row.EndLine+':'+$row.EndColumn;if(-not $merged.ContainsKey($key)){$merged[$key]=$row}else{$merged[$key].Hit=$merged[$key].Hit -or $row.Hit};$key})|Sort-Object
 if($null -eq $expectedKeys){$expectedKeys=$keys}elseif(($keys -join "`n") -cne ($expectedKeys -join "`n")){throw '子程序命令分母不一致。'}
 $workers+=@([pscustomobject]@{Index=$i;ProcessId=$worker.ProcessId;Evidence=('worker_'+$i+'.json')})
}
foreach($item in $hashes){if((Get-FileHash -LiteralPath (Join-Path $source $item.File)).Hash.ToLowerInvariant() -cne $item.SHA256){throw '量測期間來源變更。'}}
$xml=[xml]'<?xml version="1.0" encoding="utf-8"?><coverage version="1" lines-covered="0" lines-valid="0" line-rate="0"><sources><source>.</source></sources><packages><package name="PowerShell"><classes /></package></packages></coverage>'
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
$xml.coverage.SetAttribute('lines-covered',$covered.ToString());$xml.coverage.SetAttribute('lines-valid',$total.ToString());$xml.coverage.SetAttribute('line-rate',($covered/[double]$total).ToString([Globalization.CultureInfo]::InvariantCulture))
Write-Json (Join-Path $output 'evidence.json') ([ordered]@{SchemaVersion=1;PesterVersion=$version;PackageSHA512=$packageHash;Sources=$hashes;Workers=$workers;Metric='FullyCoveredCommandStartLines';Covered=$covered;Total=$total})
$xml.Save((Join-Path $output 'coverage.xml'))
Write-Host ('PowerShell 原檔可執行行覆蓋率：'+$covered+'/'+$total+'；僅此清單範圍，不是整個儲存庫。')
