#Requires -Version 5.1
param([switch]$AfterRestart,[switch]$VerifyOnly,[string]$DriverPackagePath)
$ErrorActionPreference='Stop'
if($AfterRestart -and $VerifyOnly){throw 'AfterRestart 與 VerifyOnly 不可同時指定。'}
$entry=if($AfterRestart){'verify_after_restart.ps1'}elseif($VerifyOnly){'verify_only.ps1'}else{'configure_nuc.ps1'}
if($AfterRestart -or $VerifyOnly){
 if($DriverPackagePath){throw '重開後／只驗證使用同機紀錄的驅動選擇；如要重新選擇請執行一般 Windows 入口。'}
 & (Join-Path $PSScriptRoot $entry)
}else{
 if(-not $PSBoundParameters.ContainsKey('DriverPackagePath')){
  $DriverPackagePath=Read-Host '獨立 NUC 驅動包目錄（直接 Enter 預設略過，不安裝驅動）'
 }
 if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath.Trim('"'))}
 & (Join-Path $PSScriptRoot $entry) -DriverPackagePath $DriverPackagePath
}
