#Requires -Version 5.1
param([string]$DriverPackagePath,[switch]$PackageOnly,[string]$ConfirmedBoard,[string]$ConfirmationComputer,[switch]$NonInteractive,[switch]$VerifyOnly,[string]$VerificationRunId=([guid]::NewGuid().ToString()))
$ErrorActionPreference='Stop'
if($PackageOnly -and ($ConfirmedBoard -or $ConfirmationComputer)){throw 'PackageOnly 離線驗包不可混用手動實機確認。'}
if($PackageOnly -and $VerifyOnly){throw 'PackageOnly 與 VerifyOnly 不可混用。'}
if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath)}
. (Join-Path $PSScriptRoot '..\..\core\hardware.ps1')
$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'driver_archive_library.ps1')
if($PackageOnly -and -not $DriverPackagePath){[pscustomobject]@{Applicable=$false;Status='Skipped';Reason='未指定獨立驅動包，略過離線驗包。'};return}
if(-not $PackageOnly){
 $request=Select-SetupDriverRequest -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -DriverPackagePath $DriverPackagePath -PathSpecified:$PSBoundParameters.ContainsKey('DriverPackagePath') -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer -Interactive:((Test-SetupInteractiveHost) -and -not $NonInteractive -and -not $VerifyOnly)
 $DriverPackagePath=$request.DriverPackagePath;$ConfirmedBoard=$request.ConfirmedBoard;$ConfirmationComputer=$request.ConfirmationComputer
}
if($PackageOnly){
 $identity=Get-Content -LiteralPath (Join-Path $DriverPackagePath 'package.json') -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
 $board='NUC8i7HVB'
 if($identity.SchemaVersion -eq 2){
  $profile=Get-SetupDriverProfile -ProfileId $identity.ProfileId
  if(-not $profile){throw '獨立包指定的機型不在可信設定檔清單。'}
  $board=$profile.SupportedBoards[0]
 }
 $hardware=Get-SetupHardwareProfile -BoardProduct $board -DriverPackagePath $DriverPackagePath
}else{$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer}
$decision=Get-SetupModuleDecision -Module 'install_drivers.ps1' -Hardware $hardware
if(-not $decision.Applicable){Write-Host ('[略過] '+$decision.Reason);$decision;return}
$payload=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $DriverPackagePath
if($PackageOnly){$payload;return}
if($VerifyOnly){
 . (Join-Path $PSScriptRoot 'driver_installation_library.ps1')
 $result=Invoke-SetupDriverVerification -DriverRoot $DriverPackagePath -VerificationRunId $VerificationRunId
 $result
 if(-not $result.Success){throw '驅動唯讀驗證尚未通過；請依各目標目前版本及狀態處理。'}
 return
}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -NonInteractive -DriverPackagePath '"+$DriverPackagePath.Replace("'","''")+"'"
 if($ConfirmedBoard){$command+=" -ConfirmedBoard '"+$ConfirmedBoard.Replace("'","''")+"' -ConfirmationComputer '"+$ConfirmationComputer.Replace("'","''")+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
 return
}
if(-not [Environment]::Is64BitOperatingSystem){throw '僅支援 64 位元 Windows。'}
. (Join-Path $PSScriptRoot 'driver_installation_library.ps1')
$result=Invoke-SetupDriverInstallation -DriverRoot $DriverPackagePath -LogDirectory (Join-Path $PSScriptRoot 'driver_logs')
if(-not $result.Success){throw '驅動未全部通過；請查看 driver_logs/driver_result.json 的逐裝置結果。'}
Write-Host '驅動處理完成；本工具不會自動重新開機。' -ForegroundColor Green
