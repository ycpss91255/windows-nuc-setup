#Requires -Version 5.1
function Get-SetupHardwareProfile {
 param([string]$BoardProduct,[string]$UICulture=(Get-UICulture).Name,[string]$DriverPackagePath='')
 if(-not $PSBoundParameters.ContainsKey('BoardProduct')){$BoardProduct=[string](Get-CimInstance Win32_BaseBoard -ErrorAction Stop).Product}
 $matched=$BoardProduct.Trim() -in @('NUC8i7HVB','NUC8i7HNB')
 [pscustomobject]@{Name=$(if($matched){'NUC8'}else{'Generic'});BoardProduct=$BoardProduct;IsNuc8=$matched;UICulture=$UICulture;DriverPackagePath=$DriverPackagePath}
}
function Get-SetupModuleDecision {
 param([Parameter(Mandatory=$true)][string]$Module,[Parameter(Mandatory=$true)]$Hardware)
 $skip=($Module -in @('Install-Drivers.ps1','Apply-AMDPrivacySettings.ps1') -and -not $Hardware.IsNuc8)
 $reason='非 NUC8i7HV/HN：略過 NUC 專屬驅動／AMD 設定'
 if($Module -eq 'Install-Drivers.ps1' -and $Hardware.IsNuc8 -and -not $Hardware.DriverPackagePath){$skip=$true;$reason='未選擇獨立驅動包，略過驅動安裝'}
 if($Module -eq 'Desktop-IconLayout.ps1' -and $Hardware.UICulture -ne 'zh-TW'){$skip=$true;$reason='目前排列範本使用繁體中文圖示名稱，略過其他語系的座標套用'}
 [pscustomobject]@{Module=$Module;Applicable=(-not $skip);Status=$(if($skip){'Skipped'}else{'Applicable'});Reason=$(if($skip){$reason}else{'適用目前硬體設定檔'})}
}
function Test-SetupDriverPayload {
 param([Parameter(Mandatory=$true)]$Hardware,[string]$DriverPackagePath,[switch]$AllowLegacyManifest)
 if(-not $Hardware.IsNuc8){return [pscustomobject]@{Status='Skipped';Count=0;Reason='通用電腦不需要 NUC 驅動封存檔'}}
 if(-not $DriverPackagePath){return [pscustomobject]@{Status='Skipped';Count=0;Reason='未選擇獨立驅動包'}}
 $driverRoot=$DriverPackagePath
 if(-not $AllowLegacyManifest){
  $identity=Get-Content -LiteralPath (Join-Path $driverRoot 'package.json') -Raw -ErrorAction Stop|ConvertFrom-Json
  if($identity.SchemaVersion -ne 1 -or $identity.HardwareProfile -ne 'NUC8' -or $identity.Architecture -ne 'x64' -or @($identity.SupportedBoards).Count -ne 2 -or 'NUC8i7HVB' -notin $identity.SupportedBoards -or 'NUC8i7HNB' -notin $identity.SupportedBoards -or $Hardware.BoardProduct.Trim() -notin $identity.SupportedBoards){throw '驅動包機型或架構識別不符合目前硬體。'}
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
function Get-SetupSavedDriverSelection {
 param([string]$ResultPath,[string]$Computer=$env:COMPUTERNAME,[string]$UserSID)
 if(-not(Test-Path -LiteralPath $ResultPath -PathType Leaf)){return ''}
 if(-not $UserSID){$UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
 $saved=Get-Content -LiteralPath $ResultPath -Raw -ErrorAction Stop|ConvertFrom-Json
 if($saved.Computer -eq $Computer -and $saved.UserSID -eq $UserSID -and $saved.HardwareProfile.DriverPackagePath){return [string]$saved.HardwareProfile.DriverPackagePath}
 return ''
}