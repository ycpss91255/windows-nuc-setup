#Requires -Version 5.1
function Invoke-CINative {
 param([Parameter(Mandatory=$true)][string]$File,[string[]]$Arguments=@())
 $previous=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';$global:LASTEXITCODE=0;& $File @Arguments;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 if($code -ne 0){$failure=[Exception]::new(('CI command failed: '+$File+' / '+$code));$failure.Data['ExitCode']=$code;throw $failure}
}
function Assert-CIResults {
 param([hashtable]$Results)
 foreach($name in @('Tests','Requirements','Docker','Payload')){if(-not $Results.ContainsKey($name) -or $Results[$name] -cne 'success'){throw ('必要工作失敗、取消或跳過：'+$name)}}
}
function Assert-CIRequiredTools {
 param([switch]$Managed)
 foreach($tool in @('powershell.exe','cmd.exe','git.exe','go.exe')){Get-Command $tool -CommandType Application -ErrorAction Stop|Out-Null}
 Invoke-CINative -File git.exe -Arguments @('--version')
 Invoke-CINative -File go.exe -Arguments @('version')
 if($Managed){
  foreach($tool in @('pwsh.exe','dotnet.exe')){Get-Command $tool -CommandType Application -ErrorAction Stop|Out-Null}
  $version=@(Invoke-CINative -File pwsh.exe -Arguments @('-NoProfile','-Command','$PSVersionTable.PSVersion.ToString()'))
  if(($version -join '').Trim() -cne '7.6.9'){throw 'Pinned PowerShell 7.6.9 required.'}
  $sdk=@(Invoke-CINative -File dotnet.exe -Arguments @('--version'))
  if(($sdk -join '').Trim() -cne '10.0.300'){throw 'Pinned managed SDK 10.0.300 required.'}
 }
}
function Assert-CIDockerFailure {
 param([Parameter(Mandatory=$true)][string]$Image)
 $observed=0
 try{Invoke-CINative -File docker.exe -Arguments @('run','--rm','--isolation','process','--network','none','--entrypoint','powershell.exe',$Image,'-NoProfile','-Command','exit 23')}
 catch{if(-not $_.Exception.Data.Contains('ExitCode')){throw};$observed=[int]$_.Exception.Data['ExitCode']}
 if($observed -ne 23){throw ('Expected real container exit 23; observed '+$observed)}
 $global:LASTEXITCODE=0
}
function Assert-CIContainerReport {
 param([Parameter(Mandatory=$true)][string]$Directory)
 $report=Get-Content -LiteralPath (Join-Path $Directory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($report.Environment -notmatch 'Windows container'){throw '報告未標示實際 Windows 容器環境。'}
}
function Get-CIPortalParameters {
 param([string]$Repository,[string]$OutputDirectory,[string]$EventRef,[string]$RunId)
 $parameters=@{Repository=$Repository;OutputDirectory=$OutputDirectory}
 if($EventRef -eq 'refs/heads/main'){$parameters.MainRunId=$RunId}
 return $parameters
}

function Write-CIFailureDiagnostics {
 param([Parameter(Mandatory=$true)][string]$ReportDirectory,[ValidateSet('Unit.uac_helpers','Integration.managed_catalog','Integration.collector_self_coverage','Integration.driver_source_coverage','Integration.network_helpers_coverage','Integration.powershell_coverage','Integration.powershell_engine','Integration.uac_updates_coverage','Integration.verification_coverage')][string[]]$SuiteNames=@('Unit.uac_helpers','Integration.managed_catalog'))
 $directory=[IO.Path]::GetFullPath($ReportDirectory)
 if((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Diagnostic report directory cannot be a reparse point.'}
 foreach($suite in $SuiteNames){
  $name=$suite+'.log';$path=Join-Path $directory $name
  Write-Output ('CI diagnostic: '+$name)
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Write-Output '    unavailable';continue}
  if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic suite log cannot be a reparse point.'}
  foreach($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -Tail 80)){Write-Output ('    '+$line)}
 }
}
function Write-CIContainerFailureDiagnostics {
 param([Parameter(Mandatory=$true)][string]$ReportDirectory)
 $summary=Join-Path $ReportDirectory 'public/summary.json'
 if(-not(Test-Path -LiteralPath $summary -PathType Leaf)){Write-Output 'Container failure diagnostics unavailable before report generation.';return}
 if((Get-Item -LiteralPath $summary -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Container diagnostic summary cannot be a reparse point.'}
 $report=Get-Content -LiteralPath $summary -Raw -Encoding UTF8|ConvertFrom-Json
 $approved=@('Integration.collector_self_coverage','Integration.driver_source_coverage','Integration.network_helpers_coverage','Integration.powershell_coverage','Integration.powershell_engine','Integration.uac_updates_coverage','Integration.verification_coverage')
 $failed=@($report.Checks|Where-Object {$_.Name -cin $approved -and $_.Passed -eq $false}|ForEach-Object Name|Select-Object -Unique)
 if($failed.Count){Write-CIFailureDiagnostics -ReportDirectory $ReportDirectory -SuiteNames $failed}
}
