#Requires -Version 5.1
param([string]$DriverPackagePath,[switch]$PackageOnly)
$ErrorActionPreference='Stop'
if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath)}
. (Join-Path $PSScriptRoot '..\..\core\hardware.ps1')
$ProgressPreference='SilentlyContinue'
function Expand-DriverArchive {
 param([string]$Archive,[string]$Destination)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
 $root=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
 $total=[double](($zip.Entries|Measure-Object Length -Sum).Sum)
 $done=0.0;$timer=[Diagnostics.Stopwatch]::StartNew();$lastUi=-1;$lastText=-10
 $buffer=New-Object byte[] (1024*1024)
 try{
  foreach($entry in $zip.Entries){
   $target=[IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
   if(-not $target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw '封存檔包含不合法路徑。'}
   if($entry.FullName.EndsWith('/')){[void][IO.Directory]::CreateDirectory($target);continue}
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   $inputStream=$entry.Open();$outputStream=[IO.File]::Open($target,[IO.FileMode]::Create,[IO.FileAccess]::Write)
   try{
    while(($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
     $outputStream.Write($buffer,0,$read);$done+=$read
     $percent=if($total -gt 0){[math]::Min(100,[int]($done*100/$total))}else{100}
     if($timer.ElapsedMilliseconds-$lastUi -ge 250){
      Write-Progress -Id 2 -Activity ('驅動解壓縮：'+[IO.Path]::GetFileName($Archive)) -Status ($percent.ToString()+'%') -PercentComplete $percent -CurrentOperation $entry.Name
      $lastUi=$timer.ElapsedMilliseconds
     }
     if($timer.Elapsed.TotalSeconds-$lastText -ge 10){Write-Host ('解壓縮進度：'+$percent+'%；已處理 '+[math]::Round($done/1MB)+' / '+[math]::Round($total/1MB)+' MB');$lastText=$timer.Elapsed.TotalSeconds}
    }
   }finally{$outputStream.Dispose();$inputStream.Dispose()}
  }
  Write-Host '解壓縮進度：100%'
 }finally{$zip.Dispose();Write-Progress -Id 2 -Activity '驅動解壓縮' -Completed}
}
function Expand-CachedDriverArchive {
 param([string]$Archive,[string]$CacheRoot,[string]$SHA256)
 if($SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw '驅動快取需要有效的 SHA256。'}
 $dest=Join-Path $CacheRoot (([IO.Path]::GetFileNameWithoutExtension($Archive))+'-'+$SHA256.ToLowerInvariant())
 $marker=Join-Path $dest '.archive-sha256'
 if(-not(Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne $SHA256){
  Write-Host ('正在解壓縮：'+[IO.Path]::GetFileName($Archive)) -ForegroundColor Cyan
  New-Item -ItemType Directory -Path $dest -Force|Out-Null
  Expand-DriverArchive -Archive $Archive -Destination $dest
  Set-Content -LiteralPath $marker -Value $SHA256 -Encoding ascii
 }
 return $dest
}
$hardware=if($PackageOnly){Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB' -DriverPackagePath $DriverPackagePath}else{Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath}
$decision=Get-SetupModuleDecision -Module 'install_drivers.ps1' -Hardware $hardware
if(-not $decision.Applicable){Write-Host ('[略過] '+$decision.Reason);$decision;return}
$payload=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $DriverPackagePath
if($PackageOnly){$payload;return}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -DriverPackagePath '"+$DriverPackagePath.Replace("'","''")+"'"
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
 return
}
if(-not [Environment]::Is64BitOperatingSystem){throw '僅支援 64 位元 Windows。'}
$driverRoot=$DriverPackagePath
$manifest=Get-Content (Join-Path $driverRoot 'manifest.json') -Raw|ConvertFrom-Json
foreach($entry in $manifest){
 $file=Join-Path $driverRoot $entry.File
 if((Get-FileHash -LiteralPath $file).Hash -ne $entry.SHA256){throw ('驅動封存檔驗證失敗：'+$entry.File)}
}
$logDir=Join-Path $PSScriptRoot 'driver_logs'
New-Item -ItemType Directory -Path $logDir -Force|Out-Null
$stamp=Get-Date -Format yyyyMMdd-HHmmss
Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName,DeviceID,DriverVersion,InfName | Export-Csv (Join-Path $logDir "Before-$stamp.csv") -NoTypeInformation -Encoding UTF8
$cache=Join-Path $env:ProgramData 'NUC8-Setup\DriverCache'
New-Item -ItemType Directory -Path $cache -Force|Out-Null
$reboot=$false
$failed=@()
foreach($entry in $manifest){
 Write-Host ('=== 驅動套件：'+$entry.File+' ===') -ForegroundColor Cyan
 $dest=Expand-CachedDriverArchive -Archive (Join-Path $driverRoot $entry.File) -CacheRoot $cache -SHA256 $entry.SHA256
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
  $output=& "$env:SystemRoot\System32\pnputil.exe" /add-driver $inf.FullName /install 2>&1
  $code=$LASTEXITCODE
  $output|Out-File (Join-Path $logDir "PnPUtil-$stamp.log") -Append -Encoding utf8
  if($code -eq 3010){$reboot=$true}elseif($code -notin @(0,259)){$failed+=($inf.Name+': '+$code);Write-Warning ($output -join "`n")}
 }
}
Write-Progress -Id 3 -Activity '安裝匹配的驅動' -Completed
& "$env:SystemRoot\System32\pnputil.exe" /scan-devices | Out-File (Join-Path $logDir "PnPUtil-$stamp.log") -Append -Encoding utf8
Start-Sleep -Seconds 5
$problems=@(Get-PnpDevice -PresentOnly|Where-Object Status -ne 'OK')
$problems|Select-Object Status,Class,FriendlyName,InstanceId|Export-Csv (Join-Path $logDir "Problems-$stamp.csv") -NoTypeInformation -Encoding UTF8
Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName,DeviceID,DriverVersion,InfName | Export-Csv (Join-Path $logDir "After-$stamp.csv") -NoTypeInformation -Encoding UTF8
$display=@(Get-CimInstance Win32_VideoController|Select-Object Name,DriverVersion,ConfigManagerErrorCode)
$display|Format-Table|Out-Host
$result=[ordered]@{Computer=$env:COMPUTERNAME;Displays=$display;ProblemCount=$problems.Count;ProblemDevices=@($problems|Select-Object Status,Class,FriendlyName,InstanceId);RebootRequired=$reboot;Failures=$failed;CompletedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'Driver-Result.json') -Encoding utf8
Write-Host ('目前仍有異常的裝置數：'+$problems.Count)
$problems|Select-Object Status,Class,FriendlyName,InstanceId|Format-List|Out-Host
Write-Host ('需要重新啟動（安裝程式回報）：'+$reboot)
Write-Host ('驅動紀錄：'+$logDir)
if($failed.Count){throw ('部分 INF 安裝失敗，請檢查紀錄：'+($failed -join ', '))}
if($problems.Count){throw '仍有異常裝置，請查看紀錄；部分裝置可能需要重新開機後再次檢查。'}
Write-Host '驅動處理完成；本工具不會自動重新開機。' -ForegroundColor Green