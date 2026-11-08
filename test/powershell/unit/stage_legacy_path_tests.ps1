#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('legacy_stage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
$legacy=Join-Path $fixture 'legacy_child.ps1';$runner=Join-Path $fixture 'runner.ps1';$trace=Join-Path $fixture 'trace.private.json';$log=Join-Path $fixture 'parent.private.log'
$child=@'
param([string]$InnerFile,[string]$SuitePath,[string]$SourceRoot)
$ErrorActionPreference='Stop'
$global:legacyDirs=0;$global:legacyFiles=0;$global:legacyObserved=0;$global:legacyRejected=$false
function global:Get-LegacyItemBoundary {
 param($Path,$LiteralPath,[switch]$Force,$ErrorAction)
 $result=Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
 foreach($item in @($result)){
  $length=([IO.Path]::GetFullPath($item.FullName)).Length;$global:legacyObserved++
  if($item.PSIsContainer){$global:legacyDirs=[math]::Max($global:legacyDirs,$length);$budget=248}else{$global:legacyFiles=[math]::Max($global:legacyFiles,$length);$budget=260}
  if($length -ge $budget){$global:legacyRejected=$true;throw [IO.DirectoryNotFoundException]::new('controlled legacy filesystem path budget exceeded')}
 }
 return $result
}
Set-Alias -Name Get-Item -Value Get-LegacyItemBoundary -Scope Global
try{& $InnerFile -SuitePath $SuitePath -SourceRoot $SourceRoot}finally{[IO.File]::WriteAllText('__TRACE__',(@{DirectoryLength=$global:legacyDirs;FileLength=$global:legacyFiles;Observed=$global:legacyObserved;Rejected=$global:legacyRejected}|ConvertTo-Json -Compress))}
'@
[IO.File]::WriteAllText($legacy,$child.Replace('__TRACE__',$trace.Replace("'","''")),[Text.UTF8Encoding]::new($true))
$launch=@'
$ErrorActionPreference='Stop'
$native=(Get-Command powershell.exe -CommandType Application).Source
function powershell.exe {
 param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
 $a=@($Arguments);$at=[array]::IndexOf($a,'-SuitePath')
 if($at -ge 0 -and [IO.Path]::GetFileName([string]$a[$at+1]) -ceq 'stage_runtime_gap_tests.ps1'){
  $file=[array]::IndexOf($a,'-File');$inner=$a[$file+1];$a[$file+1]='__LEGACY__';$a+=@('-InnerFile',$inner)
 }
 & $native @a;$global:LASTEXITCODE=$LASTEXITCODE
}
& '__SUITE__'
'@
$launch=$launch.Replace('__LEGACY__',$legacy.Replace("'","''")).Replace('__SUITE__',(Join-Path $root 'test/powershell/integration/short_temp_fixture_tests.ps1').Replace("'","''"))
[IO.File]::WriteAllText($runner,$launch,[Text.UTF8Encoding]::new($true))
$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
$facts=if(Test-Path -LiteralPath $trace){Get-Content -LiteralPath $trace -Raw|ConvertFrom-Json}else{$null}
$passed=($code -eq 0 -and $facts -and $facts.Observed -gt 0 -and -not $facts.Rejected -and $facts.DirectoryLength -lt 248 -and $facts.FileLength -lt 260)
Write-Host ('@@ASSERT@@'+(@{Name=('原完整短TEMP與stage保護案例在legacy native路徑邊界全過；native='+$code+'; dir='+$facts.DirectoryLength+'; file='+$facts.FileLength+'; observed='+$facts.Observed+'; rejected='+$facts.Rejected);Passed=$passed}|ConvertTo-Json -Compress))
if(-not $passed){throw 'Original nested fixture must use bounded paths without changing production guards or OS long-path policy.'}
