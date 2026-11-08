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
function Assert-SetupDriverTargetIntegrity {
 param([Parameter(Mandatory=$true)]$Target,[Parameter(Mandatory=$true)][string]$Root)
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 foreach($kind in @('Inf','Catalog')){
  $relative=[string]$Target.($kind+'Path');$expected=[string]$Target.($kind+'SHA256')
  if(-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $expected -notmatch '^[A-Fa-f0-9]{64}$'){throw 'INF/CAT 需要安全相對路徑及有效釘選 hash。'}
  $file=[IO.Path]::GetFullPath((Join-Path $base $relative))
  if(-not $file.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'INF/CAT 超出驅動目錄。'}
  $walk=Get-Item -LiteralPath $file -ErrorAction Stop
  while($walk -and $walk.FullName.Length -ge $base.TrimEnd('\').Length){if($walk.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '驅動內容不可透過重新解析點。'};$walk=if($walk -is [IO.FileInfo]){$walk.Directory}else{$walk.Parent}}
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash -ne $expected){throw ($kind+' SHA256 不符。')}
 }
 $catalog=Join-Path $base $Target.CatalogPath
 $signature=Get-AuthenticodeSignature -LiteralPath $catalog -ErrorAction Stop
 if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Windows Hardware Compatibility Publisher(,|$)'){throw 'CAT 未通過 Microsoft 硬體相容簽章驗證。'}
 return $true
}