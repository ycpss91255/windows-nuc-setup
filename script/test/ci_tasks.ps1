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
