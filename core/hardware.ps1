#Requires -Version 5.1
function Get-SetupHardwareProfile {
 param([string]$BoardProduct,[string]$UICulture=(Get-UICulture).Name,[string]$DriverPackagePath='',
  [ValidateSet('','NUC8i7HVB','NUC8i7HNB')][string]$ConfirmedBoard='', [string]$ConfirmationComputer='')
 $detectionError='';$ambiguous=$false
 if(-not $PSBoundParameters.ContainsKey('BoardProduct')){
  try{
   $boards=@(Get-CimInstance Win32_BaseBoard -ErrorAction Stop)
   if($boards.Count -eq 1){$BoardProduct=[string]$boards[0].Product}
   elseif($boards.Count -gt 1){$BoardProduct=(@($boards|ForEach-Object {[string]$_.Product}) -join ' | ');$ambiguous=$true;$detectionError='回傳多塊主機板，無法安全選型。'}
   else{$BoardProduct='';$detectionError='未回傳主機板。'}
  }catch{$BoardProduct='';$detectionError=$_.Exception.Message}
 }
 $value=$BoardProduct.Trim()
 $detected=$value -in @('NUC8i7HVB','NUC8i7HNB')
 $unknown=(-not $value -or $value -in @('Unknown','To be filled by O.E.M.','Default string','Not specified')) -and -not $ambiguous
 $status=if($unknown){'Unknown'}elseif($ambiguous){'Ambiguous'}else{'Detected'}
 if($ConfirmedBoard){
  if(-not $ConfirmationComputer -or $ConfirmationComputer -ine $env:COMPUTERNAME){throw '手動驅動型號確認不屬於目前電腦。'}
  if(-not $unknown -and (-not $detected -or $value -ine $ConfirmedBoard)){throw '目前偵測硬體與手動確認不符，拒絕 NUC 驅動。'}
 }
 $driverBoard=if($ConfirmedBoard){$ConfirmedBoard}elseif($detected){$value}else{''}
 [pscustomobject]@{Name=$(if($driverBoard){'NUC8'}else{'Generic'});BoardProduct=$BoardProduct;DriverBoard=$driverBoard;IsNuc8=[bool]$driverBoard;IsDetectedNuc8=$detected;DetectionStatus=$status;DetectionError=$detectionError;ConfirmedBoard=$ConfirmedBoard;ConfirmationComputer=$ConfirmationComputer;UICulture=$UICulture;DriverPackagePath=$DriverPackagePath}
}
function Get-SetupModuleDecision {
 param([Parameter(Mandatory=$true)][string]$Module,[Parameter(Mandatory=$true)]$Hardware)
 $skip=($Module -in @('install_drivers.ps1','apply_amd_privacy_settings.ps1') -and -not $Hardware.IsNuc8)
 if($Module -eq 'apply_amd_privacy_settings.ps1' -and $Hardware.ConfirmedBoard -and -not $Hardware.IsDetectedNuc8){$skip=$true}
 $reason='非 NUC8i7HV/HN：略過 NUC 專屬驅動／AMD 設定'
 if($Module -eq 'install_drivers.ps1' -and $Hardware.IsNuc8 -and -not $Hardware.DriverPackagePath){$skip=$true;$reason='未選擇獨立驅動包，略過驅動安裝'}
 if($Module -eq 'desktop_icon_layout.ps1' -and $Hardware.UICulture -ne 'zh-TW'){$skip=$true;$reason='目前排列範本使用繁體中文圖示名稱，略過其他語系的座標套用'}
 [pscustomobject]@{Module=$Module;Applicable=(-not $skip);Status=$(if($skip){'Skipped'}else{'Applicable'});Reason=$(if($skip){$reason}else{'適用目前硬體設定檔'})}
}
function Test-SetupDriverPayload {
 param([Parameter(Mandatory=$true)]$Hardware,[string]$DriverPackagePath,[switch]$AllowLegacyManifest)
 if(-not $Hardware.IsNuc8){return [pscustomobject]@{Status='Skipped';Count=0;Reason='通用電腦不需要 NUC 驅動封存檔'}}
 if(-not $DriverPackagePath){return [pscustomobject]@{Status='Skipped';Count=0;Reason='未選擇獨立驅動包'}}
 $driverRoot=$DriverPackagePath
 if(-not $AllowLegacyManifest){
  $identity=Get-Content -LiteralPath (Join-Path $driverRoot 'package.json') -Raw -ErrorAction Stop|ConvertFrom-Json
  if($identity.SchemaVersion -ne 1 -or $identity.HardwareProfile -ne 'NUC8' -or $identity.Architecture -ne 'x64' -or @($identity.SupportedBoards).Count -ne 2 -or 'NUC8i7HVB' -notin $identity.SupportedBoards -or 'NUC8i7HNB' -notin $identity.SupportedBoards -or $Hardware.DriverBoard -notin $identity.SupportedBoards){throw '驅動包機型或架構識別不符合目前硬體。'}
 }
 $manifest=Get-Content -LiteralPath (Join-Path $driverRoot 'manifest.json') -Raw -ErrorAction Stop|ConvertFrom-Json
 if($manifest.Count -ne 4 -or @($manifest.File|Select-Object -Unique).Count -ne 4){throw 'NUC 驅動清單必須包含四個封存檔。'}
 foreach($entry in $manifest){
  if($entry.File -notmatch '^[^\\/:]+\.zip$' -or $entry.File -match '^\.\.' -or $entry.SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'NUC 驅動清單格式不合法。'}
  $path=Join-Path $driverRoot $entry.File
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('缺少驅動：'+$entry.File)}
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256){throw ('驅動 SHA256 不符：'+$entry.File)}
 }
 [pscustomobject]@{Status='Passed';Count=$manifest.Count;Reason='NUC 驅動雜湊通過'}
}
function New-SetupSkippedCheck {
 param([string]$Name,[string]$Reason)
 [pscustomobject]@{Name=$Name;Status='Skipped';Passed=$null;Detail=$Reason}
}
function Test-SetupChecksPassed {
 param([object[]]$Checks)
 return (@($Checks|Where-Object {$_.Status -ne 'Skipped' -and -not $_.Passed}).Count -eq 0)
}
function New-SetupDriverSelection {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$DriverPackagePath)
 $base=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PackageRoot).TrimEnd('\')+'\'
 $selected=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath).TrimEnd('\')
 $relative=''
 if([IO.Path]::GetPathRoot($base) -ieq [IO.Path]::GetPathRoot($selected)){
  $relative=[Uri]::UnescapeDataString(([Uri]$base).MakeRelativeUri([Uri]($selected+'\')).ToString()).Replace('/','\').TrimEnd('\')
  if(-not $relative){$relative='.'}
 }
 [pscustomobject]@{SchemaVersion=1;RelativePath=$relative;AbsolutePath=$selected;PackageSHA256=(Get-FileHash -LiteralPath (Join-Path $selected 'package.json') -Algorithm SHA256 -ErrorAction Stop).Hash;ManifestSHA256=(Get-FileHash -LiteralPath (Join-Path $selected 'manifest.json') -Algorithm SHA256 -ErrorAction Stop).Hash}
}
function Get-SetupSavedDriverSelection {
 param([string]$ResultPath,[string]$Computer=$env:COMPUTERNAME,[string]$UserSID,[string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))
 if(-not(Test-Path -LiteralPath $ResultPath -PathType Leaf)){return ''}
 if(-not $UserSID){$UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
 $saved=Get-Content -LiteralPath $ResultPath -Raw -ErrorAction Stop|ConvertFrom-Json
 if($saved.Computer -ne $Computer -or $saved.UserSID -ne $UserSID){return ''}
 if(-not $saved.HardwareProfile.DriverPackagePath){return ''}
 $selection=$saved.HardwareProfile.DriverSelection
 if(-not $selection){
  # Older records never guess a new disk letter. Explicit reselection upgrades the record.
  $legacy=[string]$saved.HardwareProfile.DriverPackagePath
  if(-not [IO.Path]::IsPathRooted($legacy) -or -not(Test-Path -LiteralPath $legacy -PathType Container)){throw '舊驅動選擇路徑已失效，請以 windows.cmd 重新指定獨立驅動包。'}
  return $legacy
 }
 if($selection.SchemaVersion -ne 1 -or $selection.PackageSHA256 -notmatch '^[a-fA-F0-9]{64}$' -or $selection.ManifestSHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw '驅動續跑紀錄格式不合法，請重新選擇驅動包。'}
 if($selection.RelativePath){
  if([IO.Path]::IsPathRooted($selection.RelativePath) -or $selection.RelativePath.Contains(':')){throw '驅動相對位置不可指定磁碟代號。'}
  $candidate=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $PackageRoot $selection.RelativePath))
 }else{$candidate=[string]$selection.AbsolutePath}
 if(-not [IO.Path]::IsPathRooted($candidate) -or -not(Test-Path -LiteralPath $candidate -PathType Container)){throw '找不到原選擇的獨立驅動包。請保持主包與驅動包相對位置，或以 windows.cmd 重新選擇；不會搜尋其他磁碟。'}
 foreach($item in @(@('package.json','PackageSHA256'),@('manifest.json','ManifestSHA256'))){
  if((Get-FileHash -LiteralPath (Join-Path $candidate $item[0]) -Algorithm SHA256 -ErrorAction Stop).Hash -ne $selection.($item[1])){throw '驅動包身分與原選擇不同，拒絕續跑；請重新選擇並驗證。'}
 }
 return $candidate
}
