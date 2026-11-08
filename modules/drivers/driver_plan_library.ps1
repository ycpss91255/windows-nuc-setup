#Requires -Version 5.1
function Get-SetupDriverTargetPlan {
 param([Parameter(Mandatory=$true)]$Target,[object[]]$Devices=@(),[int]$Build,[string]$Architecture)
 $matches=@($Devices|Where-Object {$ids=@($_.HardwareIds);@($Target.HardwareIds|Where-Object {$_ -in $ids}).Count -gt 0})
 $status='';$reason=''
 if($Build -lt $Target.MinimumBuild -or $Architecture -ne $Target.Architecture){$status='NotApplicable';$reason='作業系統或架構不適用'}
 elseif(-not $matches){$status='Absent';$reason='未枚舉相符硬體'}
 if($status){return [pscustomobject]@{InstanceId='';InfPath=$Target.InfPath;Status=$status;Reason=$reason;CurrentVersion='';TargetVersion=$Target.DriverVersion;TargetProvider=$Target.Provider;ProviderAliases=@($Target.ProviderAliases)}}
 foreach($device in $matches){
  $current=$null;$desired=$null
  $comparable=($device.DriverProvider -eq $Target.Provider -or $device.DriverProvider -in @($Target.ProviderAliases))
  if(-not [version]::TryParse([string]$Target.DriverVersion,[ref]$desired)){throw '目標驅動版本無法解析。'}
  if($device.DriverProvider -eq 'Microsoft' -and $Target.Provider -ne 'Microsoft'){$status='UpdateRequired';$reason='原廠目標取代通用驅動'}
  elseif(-not $comparable -or -not [version]::TryParse([string]$device.DriverVersion,[ref]$current)){$status='Unverified';$reason='目前供應商或版本無法安全比較'}
  elseif($current -gt $desired){$status='NewerInstalled';$reason='保留目前較新版本'}
  elseif($current -eq $desired){$status='Current';$reason='已符合目標版本'}
  else{$status='UpdateRequired';$reason='目前版本低於已核目標'}
  [pscustomobject]@{InstanceId=[string]$device.InstanceId;InfPath=[string]$Target.InfPath;Status=$status;Reason=$reason;CurrentVersion=[string]$device.DriverVersion;CurrentProvider=[string]$device.DriverProvider;TargetVersion=[string]$Target.DriverVersion;TargetProvider=[string]$Target.Provider;ProviderAliases=@($Target.ProviderAliases)}
 }
}
function Get-SetupDriverReadback {
 param([Parameter(Mandatory=$true)]$Plan,[object[]]$Devices=@())
 $device=@($Devices|Where-Object InstanceId -eq $Plan.InstanceId)
 $status='Unverified';$version='';$reason='安裝後未讀回唯一正常裝置與目標版本'
 if($device.Count -eq 1){
  $version=[string]$device[0].DriverVersion;$current=$null;$target=$null
  $providerMatches=($device[0].DriverProvider -eq $Plan.TargetProvider -or $device[0].DriverProvider -in @($Plan.ProviderAliases))
  if($device[0].Status -eq 'OK' -and $providerMatches -and [version]::TryParse($version,[ref]$current) -and [version]::TryParse([string]$Plan.TargetVersion,[ref]$target)){
   if($current -gt $target){$status='NewerInstalled';$reason='讀回較新版本，沒有降版'}
   elseif($current -eq $target){$status=if($Plan.Status -eq 'UpdateRequired'){'Updated'}else{'Current'};$reason='已讀回正常裝置及目標版本'}
  }
 }
 [pscustomobject]@{InstanceId=$Plan.InstanceId;InfPath=$Plan.InfPath;Status=$status;Reason=$reason;PreviousVersion=$Plan.CurrentVersion;CurrentVersion=$version;TargetVersion=$Plan.TargetVersion;Provider=$Plan.TargetProvider}
}