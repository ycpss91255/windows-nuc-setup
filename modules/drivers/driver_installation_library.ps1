#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'driver_archive_library.ps1')
. (Join-Path $PSScriptRoot 'driver_plan_library.ps1')
function Invoke-SetupLegacyDriverPackages {
 param([object[]]$Entries,[string]$DriverRoot,[string]$LogDirectory,[string]$Stamp)

$reboot=$false
$failed=@()
foreach($entry in $Entries){
 Write-Host ('=== 驅動套件：'+$entry.File+' ===') -ForegroundColor Cyan
 $dest=New-SetupDriverExtractionRoot
 Expand-DriverArchive -Archive (Join-Path $DriverRoot $entry.File) -Destination $dest
 $infFiles=@()
 if($entry.File -like 'Chipset*'){$infFiles=@(Get-ChildItem $dest -Recurse -Filter '*.inf'|Where-Object FullName -match 'Windows10-x64')}
 elseif($entry.File -like 'SerialIO*'){$infFiles=@(Get-ChildItem $dest -Recurse -Filter '*.inf')}
 elseif($entry.File -like 'UCM*'){$infFiles=@(Get-ChildItem $dest -Recurse -Filter 'TPS659xx.inf')}
 elseif($entry.File -like 'GFX-Radeon*'){
  $amd=@(Get-PnpDevice -Class Display -PresentOnly|Where-Object InstanceId -match 'VEN_1002&DEV_694[CE]')
  if(-not $amd){Write-Host '未偵測到相符的 Radeon Vega M，略過 AMD 顯示驅動。';continue}
  $infFiles=@(Get-ChildItem $dest -Recurse -File|Where-Object Name -in @('u0393589.inf','AtihdWT6.inf'))
 }
 if(-not $infFiles){throw ('找不到預期的 INF：'+$entry.File)}
 # 僅加入與本機硬體 ID 相符的 INF，避免佈建其他平台的晶片組套件。
 $ids=@(Get-PnpDevice -PresentOnly | Get-PnpDeviceProperty -KeyName @('DEVPKEY_Device_HardwareIds','DEVPKEY_Device_CompatibleIds') -ErrorAction SilentlyContinue | ForEach-Object Data | Where-Object { $_ -and $_ -match '^(PCI|ACPI|HDAUDIO)\\' })
 $infFiles=@($infFiles|Where-Object {
   $text=[IO.File]::ReadAllText($_.FullName)
   $match=$false
   foreach($id in $ids){if($text.IndexOf($id,[StringComparison]::OrdinalIgnoreCase) -ge 0){$match=$true;break}}
   $match
 })
 if(-not $infFiles){Write-Host ('未偵測到相符硬體，略過：'+$entry.File);continue}
 $infIndex=0
 foreach($inf in $infFiles){
  $infIndex++
  Write-Progress -Id 3 -Activity '安裝匹配的驅動' -Status ($infIndex.ToString()+'/'+$infFiles.Count+'：'+$inf.Name) -PercentComplete ([int](100*($infIndex-1)/$infFiles.Count))
  Write-Host ('安裝相符裝置驅動：'+$inf.Name)
  $native=Invoke-SetupDriverInfInstall -InfPath $inf.FullName -LogPath (Join-Path $LogDirectory ('pnputil-'+$Stamp+'.log'))
  $code=$native.ExitCode
  if($code -eq 3010){$reboot=$true}elseif($code -notin @(0,259)){$failed+=($inf.Name+': '+$code)}
 }
}
 [pscustomobject]@{Failures=@($failed);RebootRequired=$reboot;Results=@()}
}
function Invoke-SetupDriverInstallation {
 param([Parameter(Mandatory=$true)][string]$DriverRoot,[Parameter(Mandatory=$true)][string]$LogDirectory)
 $raw=Get-Content -LiteralPath (Join-Path $DriverRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $entries=@(Get-SetupDriverManifestEntries -Manifest $raw)
 foreach($entry in $entries){if((Get-FileHash -LiteralPath (Join-Path $DriverRoot $entry.File) -Algorithm SHA256 -ErrorAction Stop).Hash -ne $entry.SHA256){throw ('驅動封存檔 SHA256 不符：'+$entry.File)}}
 [void][IO.Directory]::CreateDirectory($LogDirectory)
 $stamp=Get-Date -Format yyyyMMdd-HHmmss
 $nativeLog=Join-Path $LogDirectory ('pnputil-'+$stamp+'.log')
 $before=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)
 $before|Select-Object DeviceName,DeviceID,DriverVersion,InfName|Export-Csv -LiteralPath (Join-Path $LogDirectory ('before-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8
 $failures=@();$targets=@();$reboot=$false
 if($raw.SchemaVersion -eq 2){
  $build=[int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber
  foreach($entry in $entries){
   Write-Host ('=== 官方驅動套件：'+$entry.Id+' / '+$entry.PackageVersion+' ===') -ForegroundColor Cyan
   try{$outcome=Invoke-SetupOfficialDriverPackage -Entry $entry -Archive (Join-Path $DriverRoot $entry.File) -Build $build -LogPath $nativeLog;$targets+=@($outcome.Results);$failures+=@($outcome.Failures);$reboot=$reboot -or $outcome.RebootRequired}
   catch{$failures+=($entry.Id+'：'+$_.Exception.Message);Write-Warning $failures[-1]}
  }
 }else{
  $outcome=Invoke-SetupLegacyDriverPackages -Entries $entries -DriverRoot $DriverRoot -LogDirectory $LogDirectory -Stamp $stamp
  $failures+=@($outcome.Failures);$reboot=$outcome.RebootRequired
 }
 $problems=@(Get-PnpDevice -PresentOnly -ErrorAction Stop|Where-Object Status -ne 'OK')
 $problems|Select-Object Status,Class,FriendlyName,InstanceId|Export-Csv -LiteralPath (Join-Path $LogDirectory ('problems-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8
 @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)|Select-Object DeviceName,DeviceID,DriverVersion,InfName|Export-Csv -LiteralPath (Join-Path $LogDirectory ('after-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8
 $display=@(Get-CimInstance Win32_VideoController -ErrorAction Stop|Select-Object Name,DriverVersion,ConfigManagerErrorCode)
 $result=[pscustomobject]@{Success=($failures.Count -eq 0 -and $problems.Count -eq 0);SchemaVersion=2;ManifestSchemaVersion=$raw.SchemaVersion;Computer=[Environment]::MachineName;Targets=@($targets);Displays=$display;ProblemCount=$problems.Count;ProblemDevices=@($problems|Select-Object Status,Class,FriendlyName,InstanceId);RebootRequired=$reboot;Failures=@($failures);CompletedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $LogDirectory 'driver_result.json') -Encoding UTF8
 Write-Host ('驅動檢查結果：'+$targets.Count+' 個目標；異常裝置 '+$problems.Count+'；需重開 '+$reboot)
 foreach($target in $targets){Write-Host ($target.InfPath+'：'+$target.Status+'；目前 '+$target.CurrentVersion+'；目標 '+$target.TargetVersion)}
 return $result
}