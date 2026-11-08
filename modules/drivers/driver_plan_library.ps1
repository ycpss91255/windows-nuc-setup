#Requires -Version 5.1
function Get-SetupDriverTargetPlan {
 param([Parameter(Mandatory=$true)]$Target,[object[]]$Devices=@(),[int]$Build,[string]$Architecture)
 $matches=@($Devices|Where-Object {$ids=@($_.HardwareIds);@($Target.HardwareIds|Where-Object {$_ -in $ids}).Count -gt 0})
 $status='';$reason=''
 if($Build -lt $Target.MinimumBuild -or $Architecture -ne $Target.Architecture){$status='NotApplicable';$reason='作業系統或架構不適用'}
 elseif(-not $matches){
  $possibleErrors=@($Devices|Where-Object {
   if(-not $_.HardwareIdsReadError){return $false}
   $instance=[string]$_.InstanceId
   @($Target.HardwareIds|Where-Object {$instance.StartsWith(($_+'\'),[StringComparison]::OrdinalIgnoreCase) -or $instance.StartsWith(($_+'&'),[StringComparison]::OrdinalIgnoreCase)}).Count -gt 0
  })
  if($possibleErrors.Count){$status='Unverified';$reason='相符裝置硬體屬性未能讀取'}else{$status='Absent';$reason='未枚舉相符硬體'}
 }
 if($status){return [pscustomobject]@{InstanceId='';InfPath=$Target.InfPath;Status=$status;Reason=$reason;CurrentVersion='';TargetVersion=$Target.DriverVersion;TargetProvider=$Target.Provider;ProviderAliases=@($Target.ProviderAliases)}}
 foreach($device in $matches){
  $current=$null;$desired=$null
  $comparable=($device.DriverProvider -eq $Target.Provider -or $device.DriverProvider -in @($Target.ProviderAliases))
  if(-not [version]::TryParse([string]$Target.DriverVersion,[ref]$desired)){throw '目標驅動版本無法解析。'}
  if($device.DriverProvider -eq 'Microsoft' -and $Target.Provider -ne 'Microsoft'){$status='UpdateRequired';$reason='原廠目標取代通用驅動'}
  elseif(-not $comparable -or -not [version]::TryParse([string]$device.DriverVersion,[ref]$current)){$status='Unverified';$reason='目前供應商或版本無法安全比較'}
  elseif($current -ge $desired -and $device.Status -ne 'OK'){$status='Unverified';$reason='版本已達目標但裝置狀態異常'}
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
function Get-SetupDriverDeviceInventory {
 $signed=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)
 foreach($device in @(Get-PnpDevice -PresentOnly -ErrorAction Stop)){
  $driver=@($signed|Where-Object DeviceID -eq $device.InstanceId|Select-Object -First 1)
  $ids=@();$readError=''
  try{$ids=@((Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_HardwareIds -ErrorAction Stop).Data)}catch{$readError=$_.Exception.Message}
  [pscustomobject]@{InstanceId=$device.InstanceId;Name=$device.FriendlyName;HardwareIds=$ids;HardwareIdsReadError=$readError;Status=$device.Status;DriverProvider=[string]$driver.DriverProviderName;DriverVersion=[string]$driver.DriverVersion}
 }
}
function Get-SetupDriverPnpTool {
 return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'pnputil.exe'
}
function Invoke-SetupDriverInfInstall {
 param([Parameter(Mandatory=$true)][string]$InfPath,[Parameter(Mandatory=$true)][string]$LogPath)
 $output=& (Get-SetupDriverPnpTool) /add-driver $InfPath /install 2>&1
 $code=$LASTEXITCODE
 $output|Out-File -LiteralPath $LogPath -Append -Encoding utf8
 [pscustomobject]@{ExitCode=$code}
}
function Invoke-SetupDriverTarget {
 param([Parameter(Mandatory=$true)]$Target,[Parameter(Mandatory=$true)][string]$Root,[int]$Build,[string]$Architecture,[string]$LogPath)
 $null=Assert-SetupDriverTargetIntegrity -Target $Target -Root $Root
 $plans=@(Get-SetupDriverTargetPlan -Target $Target -Devices @(Get-SetupDriverDeviceInventory) -Build $Build -Architecture $Architecture)
 $failures=@();$reboot=$false;$results=@()
 if(@($plans|Where-Object Status -eq 'UpdateRequired').Count){
  $native=Invoke-SetupDriverInfInstall -InfPath (Join-Path $Root $Target.InfPath) -LogPath $LogPath
  if($native.ExitCode -eq 3010){$reboot=$true}
  elseif($native.ExitCode -notin @(0,259)){$failures+=($Target.InfPath+': '+$native.ExitCode)}
  $after=@(Get-SetupDriverDeviceInventory)
  foreach($plan in $plans){
   if($plan.Status -eq 'UpdateRequired'){$result=Get-SetupDriverReadback -Plan $plan -Devices $after;$results+=$result;if($result.Status -eq 'Unverified'){$failures+=($Target.InfPath+': 安裝後版本尚未核實')}}
   else{$results+=$plan}
  }
 }else{$results=$plans}
 foreach($result in $results){if($result.Status -eq 'Unverified' -and -not $failures){$failures+=($Target.InfPath+': '+$result.Reason)}}
 [pscustomobject]@{Results=@($results);RebootRequired=$reboot;Failures=@($failures)}
}
function New-SetupDriverExtractionRoot {
 . (Join-Path $PSScriptRoot '../updates/update_stage_library.ps1')
 $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
 Assert-SetupUpdateAncestors -CommonDataRoot $common
 $parent=Join-Path $common 'windows_setup_driver_cache'
 New-SetupUpdateProtectedDirectory -Path $parent
 $stage=Join-Path $parent ([guid]::NewGuid().ToString('N'))
 New-SetupUpdateProtectedDirectory -Path $stage
 return $stage
}
function Assert-SetupDriverPayloadFiles {
 param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)][string]$Root)
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 $files=@($Entry.Files)
 if(-not $files.Count -or @($files.Path|Select-Object -Unique).Count -ne $files.Count){throw '版本2必須提供不重複的完整 payload hash 清單。'}
 foreach($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'payload 不可包含重新解析點。'}}
 $actual=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop)
 if($actual.Count -ne $files.Count){throw '展開 payload 數量與釘選清單不符。'}
 foreach($file in $files){
  if(-not $file.Path -or [IO.Path]::IsPathRooted($file.Path) -or $file.Path -match '(^|[\\/])\.\.([\\/]|$)' -or $file.SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'payload 路徑或 SHA256 不合法。'}
  $path=[IO.Path]::GetFullPath((Join-Path $base $file.Path))
  if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $file.SHA256){throw ('payload SHA256 不符：'+$file.Path)}
 }
}
function Invoke-SetupOfficialDriverPackage {
 param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)][string]$Archive,[int]$Build,[string]$LogPath)
 if((Get-FileHash -LiteralPath $Archive -Algorithm SHA256 -ErrorAction Stop).Hash -ne $Entry.SHA256){throw '官方驅動封存檔 SHA256 不符。'}
 $stage=New-SetupDriverExtractionRoot
 Expand-DriverArchive -Archive $Archive -Destination $stage
 Assert-SetupDriverPayloadFiles -Entry $Entry -Root $stage
 $results=@();$failures=@();$reboot=$false
 foreach($target in $Entry.Drivers){
  $outcome=Invoke-SetupDriverTarget -Target $target -Root $stage -Build $Build -Architecture 'amd64' -LogPath $LogPath
  $results+=@($outcome.Results);$failures+=@($outcome.Failures);$reboot=$reboot -or $outcome.RebootRequired
 }
 [pscustomobject]@{PackageId=$Entry.Id;Results=@($results);Failures=@($failures);RebootRequired=$reboot;ExtractionRoot=$stage}
}
