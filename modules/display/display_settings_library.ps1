#Requires -Version 5.1
# Definitions only; native calls and current-user preferences run only in the named leaf.
function Invoke-SetupDisplaySettings {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 if(-not ('NUC8Display.Display' -as [type])){Add-Type -Path (Join-Path $ModuleRoot 'native/display.cs')}
 $desktop='HKCU:\Control Panel\Desktop'
 if($VerifyOnly){
  $actual=[NUC8Display.Display]::Read()
  $custom=(Get-ItemProperty $desktop -ErrorAction SilentlyContinue).Win8DpiScaling -eq 1
  $result=[ordered]@{Success=($actual[0] -eq 1920 -and $actual[1] -eq 1080 -and $actual[2] -eq 96 -and -not $custom);Width=$actual[0];Height=$actual[1];CurrentMonitorDPI=$actual[2];CurrentScalePercent=[math]::Round($actual[2]*100/96);CustomScalingEnabled=$custom;VerifiedAt=(Get-Date).ToString('o');Error='解析度或實際 DPI 尚未符合 1920×1080 / 100%，可能需要重新登入。'}
  if($result.Success){$result.Error=$null}
  return [pscustomobject]$result
 }
 $values=[NUC8Display.Display]::Apply()
 # Retain standard per-monitor scaling rather than global custom LogPixels scaling.
 New-ItemProperty $desktop -Name Win8DpiScaling -Value 0 -PropertyType DWord -Force|Out-Null
 Remove-ItemProperty $desktop -Name LogPixels -ErrorAction SilentlyContinue
 $nativeScales=@([NUC8Display.Display]::NativeScales($true))
 if(@($nativeScales|Where-Object {$_ -ne 100}).Count){throw '標準縮放尚未成功設定為 100%。'}
 return [pscustomobject][ordered]@{Success=$true;PreviousWidth=$values[0];PreviousHeight=$values[1];Width=$values[2];Height=$values[3];DisplayChangeResult=$values[4];LegacySystemDPI=$values[5];RequestedScalePercent=100;NativeScalePercent=$nativeScales;CustomScalingEnabled=$false;LegacyAppsMayRequireNextSignIn=$true;AppliedAt=(Get-Date).ToString('o')}
}
