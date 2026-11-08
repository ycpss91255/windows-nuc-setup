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
   $software=$_.Class -eq 'SoftwareComponent' -or $instance.StartsWith('SWD\DRIVERENUM\',[StringComparison]::OrdinalIgnoreCase)
   @($Target.HardwareIds|Where-Object {($_ -like 'SWC\*' -and $software) -or $instance.StartsWith(($_+'\'),[StringComparison]::OrdinalIgnoreCase) -or $instance.StartsWith(($_+'&'),[StringComparison]::OrdinalIgnoreCase)}).Count -gt 0
  })
  if($possibleErrors.Count){$status='Unverified';$reason='相符裝置硬體屬性未能讀取'}else{$status='Absent';$reason='未枚舉相符硬體'}
 }
 if($status){return [pscustomobject]@{InstanceId='';InfPath=$Target.InfPath;Status=$status;Reason=$reason;CurrentVersion='';TargetVersion=$Target.DriverVersion;TargetProvider=$Target.Provider;ProviderAliases=@($Target.ProviderAliases)}}
 foreach($device in $matches){
  $current=$null;$desired=$null
  $comparable=($device.DriverProvider -eq $Target.Provider -or $device.DriverProvider -in @($Target.ProviderAliases))
  if(-not [version]::TryParse([string]$Target.DriverVersion,[ref]$desired)){throw '目標驅動版本無法解析。'}
  if($device.HardwareIdsReadError){$status='Unverified';$reason='目標硬體屬性讀取失敗'}
  elseif($device.PSObject.Properties['DriverSigned'] -and -not $device.DriverSigned){$status='Unverified';$reason='目前已載入驅動未確認簽章'}
  elseif($device.DriverProvider -eq 'Microsoft' -and $Target.Provider -ne 'Microsoft'){$status='UpdateRequired';$reason='原廠目標取代通用驅動'}
  elseif(-not $comparable -or -not [version]::TryParse([string]$device.DriverVersion,[ref]$current)){$status='Unverified';$reason='目前供應商或版本無法安全比較'}
  elseif($current -ge $desired -and $device.Status -ne 'OK'){$status='Unverified';$reason='版本已達目標但裝置狀態異常'}
  elseif($current -gt $desired){$status='NewerInstalled';$reason='保留目前較新版本'}
  elseif($current -eq $desired){$status='Current';$reason='已符合目標版本'}
  else{$status='UpdateRequired';$reason='目前版本低於已核目標'}
  [pscustomobject]@{InstanceId=[string]$device.InstanceId;InfPath=[string]$Target.InfPath;Status=$status;Reason=$reason;CurrentVersion=[string]$device.DriverVersion;CurrentProvider=[string]$device.DriverProvider;DriverSigned=$device.DriverSigned;TargetVersion=[string]$Target.DriverVersion;TargetProvider=[string]$Target.Provider;ProviderAliases=@($Target.ProviderAliases)}
 }
}
function Get-SetupDriverReadback {
 param([Parameter(Mandatory=$true)]$Plan,[object[]]$Devices=@())
 $device=@($Devices|Where-Object InstanceId -eq $Plan.InstanceId)
 $status='Unverified';$version='';$reason='安裝後未讀回唯一正常裝置與目標版本'
 if($device.Count -eq 1){
  $version=[string]$device[0].DriverVersion;$current=$null;$target=$null
  $providerMatches=($device[0].DriverProvider -eq $Plan.TargetProvider -or $device[0].DriverProvider -in @($Plan.ProviderAliases))
  $signed=(-not $device[0].PSObject.Properties['DriverSigned'] -or $device[0].DriverSigned)
  if($device[0].Status -eq 'OK' -and $signed -and $providerMatches -and [version]::TryParse($version,[ref]$current) -and [version]::TryParse([string]$Plan.TargetVersion,[ref]$target)){
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
 param([object[]]$Targets=@())
 $signed=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)
 foreach($device in @(Get-PnpDevice -PresentOnly -ErrorAction Stop)){
  if($Targets.Count){
   $candidate=$false;$instance=[string]$device.InstanceId
   foreach($id in @($Targets|ForEach-Object HardwareIds)){
    $baseId=([string]$id -replace '&REV_[0-9A-F]+$','')
    if(($id -like 'SWC\*' -and ($device.Class -eq 'SoftwareComponent' -or $instance.StartsWith('SWD\DRIVERENUM\',[StringComparison]::OrdinalIgnoreCase))) -or $instance.StartsWith(($baseId+'\'),[StringComparison]::OrdinalIgnoreCase) -or $instance.StartsWith(($baseId+'&'),[StringComparison]::OrdinalIgnoreCase)){$candidate=$true;break}
   }
   if(-not $candidate){continue}
  }
  $driver=@($signed|Where-Object DeviceID -eq $device.InstanceId|Select-Object -First 1)
  $ids=@();$readError=''
  foreach($key in @('DEVPKEY_Device_HardwareIds','DEVPKEY_Device_CompatibleIds')){
   try{$ids+=@((Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName $key -ErrorAction Stop).Data)}catch{$readError=$_.Exception.Message}
  }
  $ids=@($ids|Where-Object {$_}|Select-Object -Unique)
  [pscustomobject]@{InstanceId=$device.InstanceId;Name=$device.FriendlyName;Class=$device.Class;HardwareIds=$ids;HardwareIdsReadError=$readError;Status=$device.Status;DriverProvider=[string]$driver.DriverProviderName;DriverVersion=[string]$driver.DriverVersion;DriverSigned=[bool]$driver.IsSigned}
 }
}
function Get-SetupDriverPnpTool {
 return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'pnputil.exe'
}
function Get-SetupDriverExtensionInventory {
 $output=& (Get-SetupDriverPnpTool) /enum-drivers /devices /format xml 2>&1
 if($LASTEXITCODE -ne 0){throw ('原生延伸驅動XML盤點失敗：'+$LASTEXITCODE+'；不能以僅存在DriverStore當作已套用。')}
 $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=52428800
 $reader=[Xml.XmlReader]::Create([IO.StringReader]::new(($output -join "`n")),$settings)
 try{$document=New-Object Xml.XmlDocument;$document.XmlResolver=$null;$document.Load($reader)}finally{$reader.Dispose()}
 if($document.DocumentElement.LocalName -cne 'pnputil'){throw '原生延伸驅動盤點不是預期XML。'}
 return $document
}
function Get-SetupDriverExtensionReadback {
 param([Parameter(Mandatory=$true)]$Target,[object[]]$Devices=@(),[Parameter(Mandatory=$true)][Xml.XmlDocument]$Inventory,[int]$Build)
 $matches=@($Devices|Where-Object {$ids=@($_.HardwareIds);@($Target.HardwareIds|Where-Object {$_ -in $ids}).Count -gt 0})
 if($Build -lt $Target.MinimumBuild -or $Target.Architecture -ne 'amd64'){return [pscustomobject]@{InfPath=$Target.InfPath;Status='NotApplicable';Association='None';InstanceId='';TargetVersion=$Target.DriverVersion}}
 if(-not $matches){return [pscustomobject]@{InfPath=$Target.InfPath;Status='Absent';Association='None';InstanceId='';TargetVersion=$Target.DriverVersion}}
 $lineage=@($Inventory.SelectNodes('/pnputil/driver')|Where-Object {[string]$_.ClassGuid -ieq '{e2f84ce7-8efa-411c-aa69-97454ca4cb57}' -and [string]$_.ExtensionId -ieq $Target.ExtensionId -and [string]$_.OriginalName -ieq [IO.Path]::GetFileName($Target.InfPath)})
 $candidates=@($lineage|Where-Object {[string]$_.ProviderName -eq $Target.Provider -or [string]$_.ProviderName -in @($Target.ProviderAliases)})
 $targetDate=[datetime]::MinValue
 if(-not [datetime]::TryParseExact([string]$Target.DriverDate,'MM/dd/yyyy',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$targetDate)){throw '延伸驅動目標缺少可信DriverVer日期。'}
 foreach($device in $matches){
  $active=@(foreach($candidate in $candidates){
   $associated=@($candidate.SelectNodes('Devices/Device')|Where-Object {$_.GetAttribute('InstanceId') -ieq $device.InstanceId})
   $match=[regex]::Match([string]$candidate.DriverVersion,'^(\d{2}/\d{2}/\d{4})\s+(\d+\.\d+\.\d+\.\d+)$')
   $date=[datetime]::MinValue;$version=$null
   if($associated.Count -and $match.Success -and [datetime]::TryParseExact($match.Groups[1].Value,'MM/dd/yyyy',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date) -and [version]::TryParse($match.Groups[2].Value,[ref]$version)){[pscustomobject]@{Date=$date;Version=$version;PublishedName=$candidate.GetAttribute('DriverName')}}
  })
  $best=@($active|Sort-Object -Property Date,Version -Descending|Select-Object -First 1)
  $status='Unverified';$association='None';$current='';$reason='沒有可信且已關聯的延伸驅動套件';$canInstall=($lineage.Count -eq 0)
  if($device.Status -ne 'OK' -or $device.HardwareIdsReadError -or ($device.PSObject.Properties['DriverSigned'] -and -not $device.DriverSigned)){$reason='所綁裝置異常、識別不可讀或簽章未確認';$canInstall=$false}
  elseif($best.Count){
   $association='Active';$current=$best[0].Version.ToString();$desired=[version]$Target.DriverVersion
   if($best[0].Date -gt $targetDate -or ($best[0].Date -eq $targetDate -and $best[0].Version -gt $desired)){$status='NewerInstalled';$reason='同ExtensionId較新DriverVer已關聯，保留原生排名'}
   elseif($best[0].Date -eq $targetDate -and $best[0].Version -eq $desired){$status='Current';$reason='已核版本精確關聯本輪裝置'}
   else{$status='UpdateRequired';$reason='目前已關聯的延伸DriverVer早於已核目標';$canInstall=$true}
  }elseif($candidates.Count){$status='Staged';$association='Staged';$reason='套件只在DriverStore，未關聯本輪裝置';$canInstall=$true}
  [pscustomobject]@{InfPath=$Target.InfPath;InstanceId=$device.InstanceId;Status=$status;Association=$association;CurrentVersion=$current;TargetVersion=$Target.DriverVersion;ExtensionId=$Target.ExtensionId;CanInstall=$canInstall;Reason=$reason}
 }
}
function Invoke-SetupDriverInfInstall {
 param([Parameter(Mandatory=$true)][string]$InfPath,[Parameter(Mandatory=$true)][string]$LogPath,[switch]$StageOnly)
 $arguments=@('/add-driver',$InfPath);if(-not $StageOnly){$arguments+='/install'}
 $output=& (Get-SetupDriverPnpTool) @arguments 2>&1
 $code=$LASTEXITCODE
 $output|Out-File -LiteralPath $LogPath -Append -Encoding utf8
 [pscustomobject]@{ExitCode=$code}
}
function Invoke-SetupDriverPnpRescan {
 $output=& (Get-SetupDriverPnpTool) /scan-devices 2>&1
 [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=@($output)}
}
function Invoke-SetupDriverTarget {
 param([Parameter(Mandatory=$true)]$Target,[Parameter(Mandatory=$true)][string]$Root,[int]$Build,[string]$Architecture,[string]$LogPath,[switch]$RequiredPresent)
 $null=Assert-SetupDriverTargetIntegrity -Target $Target -Root $Root
 $plans=@(Get-SetupDriverTargetPlan -Target $Target -Devices @(Get-SetupDriverDeviceInventory -Targets @($Target)) -Build $Build -Architecture $Architecture)
 if($RequiredPresent){foreach($plan in $plans){if($plan.Status -eq 'Absent'){$plan.Status='Unverified';$plan.Reason='必需子元件尚未枚舉，需續跑核實'}}}
 $failures=@();$reboot=$false;$results=@()
 if(@($plans|Where-Object Status -eq 'UpdateRequired').Count){
  $native=Invoke-SetupDriverInfInstall -InfPath (Join-Path $Root $Target.InfPath) -LogPath $LogPath
  if($native.ExitCode -eq 3010){$reboot=$true}
  elseif($native.ExitCode -notin @(0,259)){$failures+=($Target.InfPath+': '+$native.ExitCode)}
  $after=@(Get-SetupDriverDeviceInventory -Targets @($Target))
  foreach($plan in $plans){
   if($plan.Status -eq 'UpdateRequired'){$result=Get-SetupDriverReadback -Plan $plan -Devices $after;$results+=$result;if($result.Status -eq 'Unverified'){$failures+=($Target.InfPath+': 安裝後版本尚未核實')}}
   else{$results+=$plan}
  }
 }else{$results=$plans}
 foreach($result in $results){if($result.Status -eq 'Unverified' -and -not $failures){$failures+=($Target.InfPath+': '+$result.Reason)}}
 [pscustomobject]@{Results=@($results);RebootRequired=$reboot;Failures=@($failures)}
}
function Invoke-SetupDriverExtensionTarget {
 param([Parameter(Mandatory=$true)]$Target,[Parameter(Mandatory=$true)][string]$Root,[int]$Build,[string]$LogPath)
 $null=Assert-SetupDriverTargetIntegrity -Target $Target -Root $Root
 $devices=@(Get-SetupDriverDeviceInventory -Targets @($Target))
 $match=@($devices|Where-Object {$ids=@($_.HardwareIds);@($Target.HardwareIds|Where-Object {$_ -in $ids}).Count -gt 0})
 $xml=if($match.Count){Get-SetupDriverExtensionInventory}else{[xml]'<pnputil />'}
 $results=@(Get-SetupDriverExtensionReadback -Target $Target -Devices $devices -Inventory $xml -Build $Build)
 $failures=@();$reboot=$false
 if(@($results|Where-Object CanInstall -eq $true).Count){
  Write-Host ('安裝相符延伸INF：'+$Target.InfPath+'；保留Windows原生排名')
  $native=Invoke-SetupDriverInfInstall -InfPath (Join-Path $Root $Target.InfPath) -LogPath $LogPath
  if($native.ExitCode -eq 3010){$reboot=$true}elseif($native.ExitCode -notin @(0,259)){$failures+=($Target.InfPath+': '+$native.ExitCode)}
  $devices=@(Get-SetupDriverDeviceInventory -Targets @($Target));$xml=Get-SetupDriverExtensionInventory
  $results=@(Get-SetupDriverExtensionReadback -Target $Target -Devices $devices -Inventory $xml -Build $Build)
  foreach($result in $results){if($result.Status -eq 'Current' -and $failures.Count -eq 0){$result.Status='Updated'}}
 }
 foreach($result in $results){if($result.Status -notin @('Current','Updated','NewerInstalled','Absent','NotApplicable')){$failures+=($Target.InfPath+': '+$result.Status+' / '+$result.Reason)}}
 [pscustomobject]@{Results=@($results);Failures=@($failures);RebootRequired=$reboot}
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
function Test-SetupDriverScopeAbsent {
 param($Entry,[object[]]$Devices,[int]$Build)
 if(-not $Entry.ScopeTarget){return $false}
 $scope=@($Entry.Drivers|Where-Object Id -CEQ $Entry.ScopeTarget)
 if($scope.Count -ne 1){throw '驅動包 ScopeTarget 不是唯一已宣告目標。'}
 $plans=@(Get-SetupDriverTargetPlan -Target $scope[0] -Devices $Devices -Build $Build -Architecture amd64)
 return (@($plans|Where-Object Status -notin @('Absent','NotApplicable')).Count -eq 0)
}
function New-SetupDriverScopeSkippedResult {
 param($Target)
 Write-Host ($Target.InfPath+'：NotApplicable；限定的父硬體未枚舉或OS不適用')
 [pscustomobject]@{InfPath=$Target.InfPath;InstanceId='';Status='NotApplicable';Reason='限定的父硬體未枚舉或OS不適用，未處理此包';CurrentVersion='';TargetVersion=$Target.DriverVersion}
}
function Invoke-SetupOfficialDriverPackage {
 param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)][string]$Archive,[int]$Build,[string]$LogPath)
 if((Get-FileHash -LiteralPath $Archive -Algorithm SHA256 -ErrorAction Stop).Hash -ne $Entry.SHA256){throw '官方驅動封存檔 SHA256 不符。'}
 if($Entry.ScopeTarget -and (Test-SetupDriverScopeAbsent -Entry $Entry -Devices @(Get-SetupDriverDeviceInventory -Targets @($Entry.Drivers)) -Build $Build)){
  return [pscustomobject]@{PackageId=$Entry.Id;Results=@($Entry.Drivers|ForEach-Object {New-SetupDriverScopeSkippedResult -Target $_});Failures=@();RebootRequired=$false;ExtractionRoot=''}
 }
 $stage=New-SetupDriverExtractionRoot
 Expand-DriverArchive -Archive $Archive -Destination $stage
 Assert-SetupDriverPayloadFiles -Entry $Entry -Root $stage
 $results=@();$failures=@();$reboot=$false
 foreach($target in @($Entry.Drivers)+@($Entry.Extensions)) {if($target){$null=Assert-SetupDriverTargetIntegrity -Target $target -Root $stage}}
 foreach($target in @($Entry.Drivers|Where-Object {-not $_.ParentTarget})){
  $children=@($Entry.Drivers|Where-Object {$_.ParentTarget -and $_.ParentTarget -ceq $target.Id})
  $parentAvailable=$false
  if($children.Count){$parentPlan=@(Get-SetupDriverTargetPlan -Target $target -Devices @(Get-SetupDriverDeviceInventory -Targets @($target)) -Build $Build -Architecture amd64);$parentAvailable=@($parentPlan|Where-Object Status -in @('UpdateRequired','Current','NewerInstalled')).Count -gt 0}
  $dependencyFailed=$false
  if($parentAvailable){foreach($child in $children){
   if($Build -lt $child.MinimumBuild -or $child.Architecture -ne 'amd64'){$failures+=($child.InfPath+': 必需元件不適用目前OS');$dependencyFailed=$true;continue}
   $native=Invoke-SetupDriverInfInstall -InfPath (Join-Path $stage $child.InfPath) -LogPath $LogPath -StageOnly
   if($native.ExitCode -eq 3010){$reboot=$true}elseif($native.ExitCode -notin @(0,259)){$failures+=($child.InfPath+': 子元件預先加入失敗 '+$native.ExitCode);$dependencyFailed=$true}
  }}
  if($dependencyFailed){$results+=[pscustomobject]@{InfPath=$target.InfPath;Status='Unverified';Reason='必需元件預先加入失敗，未更新父裝置';TargetVersion=$target.DriverVersion};continue}
  $outcome=Invoke-SetupDriverTarget -Target $target -Root $stage -Build $Build -Architecture 'amd64' -LogPath $LogPath
  $results+=@($outcome.Results);$failures+=@($outcome.Failures);$reboot=$reboot -or $outcome.RebootRequired
  if($children.Count -and $parentAvailable){$scan=Invoke-SetupDriverPnpRescan;if($scan.ExitCode -ne 0){$failures+=('子元件重新枚舉失敗：'+$scan.ExitCode)}}
  foreach($child in $children){
   if($parentAvailable){$childOutcome=Invoke-SetupDriverTarget -Target $child -Root $stage -Build $Build -Architecture amd64 -LogPath $LogPath -RequiredPresent;$results+=@($childOutcome.Results);$failures+=@($childOutcome.Failures);$reboot=$reboot -or $childOutcome.RebootRequired}
   else{$results+=@(Get-SetupDriverTargetPlan -Target $child -Devices @() -Build $Build -Architecture amd64)}
  }
 }
 foreach($extension in @($Entry.Extensions|Where-Object {$_})){
  try{$outcome=Invoke-SetupDriverExtensionTarget -Target $extension -Root $stage -Build $Build -LogPath $LogPath;$results+=@($outcome.Results);$failures+=@($outcome.Failures);$reboot=$reboot -or $outcome.RebootRequired}
  catch{$results+=[pscustomobject]@{InfPath=$extension.InfPath;Status='Unverified';Association='Unknown';Reason=$_.Exception.Message};$failures+=($extension.InfPath+': '+$_.Exception.Message)}
 }
 [pscustomobject]@{PackageId=$Entry.Id;Results=@($results);Failures=@($failures);RebootRequired=$reboot;ExtractionRoot=$stage}
}
