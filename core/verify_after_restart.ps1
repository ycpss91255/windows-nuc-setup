#Requires -Version 5.1
param([string]$ExpectedUserSID)
$ErrorActionPreference='Stop'
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
. (Join-Path $PSScriptRoot 'paths.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$confirmation=Get-SetupSavedHardwareConfirmation -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath @confirmation
$skippedModules=@(@('install_drivers.ps1','apply_amd_privacy_settings.ps1','desktop_icon_layout.ps1')|ForEach-Object {Get-SetupModuleDecision -Module $_ -Hardware $hardware}|Where-Object {-not $_.Applicable})
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"'"
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
& (Resolve-NucPath 'test_setup_prerequisites.ps1') -DriverPackagePath $DriverPackagePath @confirmation
if($hardware.IsNuc8 -and $DriverPackagePath){$hardware|Add-Member -NotePropertyName DriverSelection -NotePropertyValue (New-SetupDriverSelection -PackageRoot $script:NucPackageRoot -DriverPackagePath $DriverPackagePath) -Force}
$errors=@();$remaining=@()
$resultPath=Resolve-NucPath 'Setup-Result.json'
if(Test-Path $resultPath){
 $previous=Get-Content $resultPath -Raw|ConvertFrom-Json
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($previous.Computer -eq $env:COMPUTERNAME -and $previous.UserSID -eq $sid){
  $config=[IO.File]::ReadAllText((Resolve-NucPath 'configure_nuc.ps1'))
  $allowed=@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
  foreach($file in @($previous.FailedModules|ForEach-Object {Resolve-NucModuleName $_}|Where-Object {$_ -and $_ -ne 'install_windows_updates.ps1'})){
   if($file -notin $allowed){throw ('未知的失敗模組：'+$file)}
   $decision=Get-SetupModuleDecision -Module $file -Hardware $hardware
   if(-not $decision.Applicable){Write-Host ('[略過] '+$decision.Reason);continue}
   Write-Host ('重試未完成模組：'+$file) -ForegroundColor Cyan
   try{ if($file -eq 'install_drivers.ps1'){& (Resolve-NucPath $file) -DriverPackagePath $DriverPackagePath @confirmation}else{& (Resolve-NucPath $file)} }catch{$errors+=($file+'：'+$_.Exception.Message);$remaining+=$file;Write-Warning $errors[-1]}
  }
 }
}
Write-Host '重新掃描更新；完成後再次清理預載程式並驗證。' -ForegroundColor Cyan
foreach($file in @('install_windows_updates.ps1','apply_debloat.ps1','apply_copilot_settings.ps1','remove_setup_residue.ps1')){
 try{ if($file -eq 'install_drivers.ps1'){& (Resolve-NucPath $file) -DriverPackagePath $DriverPackagePath @confirmation}else{& (Resolve-NucPath $file)} }catch{$errors+=($file+'：'+$_.Exception.Message);$remaining+=$file;Write-Warning $errors[-1]}
}
if($previous -and $previous.Computer -eq $env:COMPUTERNAME -and $previous.UserSID -eq $sid){
 $previous|Add-Member -NotePropertyName HardwareProfile -NotePropertyValue $hardware -Force
 $previous|Add-Member -NotePropertyName SkippedModules -NotePropertyValue @($skippedModules) -Force
 $previous.FailedModules=@($remaining|Select-Object -Unique);$previous.StageErrors=$errors
 $previous|ConvertTo-Json -Depth 6|Set-Content $resultPath -Encoding UTF8
}
# The temporary taskbar layout is removed by a 45-second logon worker.
for($i=0;$i -lt 12;$i++){
 $policy=Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -ErrorAction SilentlyContinue
 if(-not $policy.StartLayoutFile){break}
 Write-Host '等待登入後的工作列配置收尾…';Start-Sleep -Seconds 5
}
$layoutDecision=Get-SetupModuleDecision -Module 'desktop_icon_layout.ps1' -Hardware $hardware
if($layoutDecision.Applicable){try{ & (Resolve-NucPath 'desktop_icon_layout.ps1') -Mode Load }catch{$errors+=$_.Exception.Message}}else{Write-Host ('[略過] '+$layoutDecision.Reason)}
$verificationRunId=[guid]::NewGuid().ToString()
$verification=$null
try{ & (Resolve-NucPath 'verify_only.ps1') -VerificationRunId $verificationRunId }catch{$errors+=('本輪驗證：'+$_.Exception.Message)}
try{
 $candidate=Get-Content (Resolve-NucPath 'Verification-Result.json') -Raw|ConvertFrom-Json
 if($candidate.VerificationRunId -cne $verificationRunId -or $candidate.Computer -cne $env:COMPUTERNAME -or $candidate.UserSID -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw '驗證結果不是本輪、同機、同帳號的結果。'}
 $verification=$candidate
}catch{$errors+=('驗證結果：'+$_.Exception.Message)}
if($null -eq $verification){$verification=[pscustomobject]@{Passed=$false;Checks=@()}}
@{Computer=$env:COMPUTERNAME;CheckedAt=(Get-Date).ToString('o');Success=($verification.Passed -and $errors.Count -eq 0);Errors=$errors;SkippedChecks=@($verification.Checks|Where-Object Status -eq Skipped);HardwareProfile=$hardware;FailedChecks=@($verification.Checks|Where-Object {$_.Status -ne 'Skipped' -and -not $_.Passed})}|ConvertTo-Json -Depth 6|Set-Content (Resolve-NucPath 'Acceptance-Result.json') -Encoding UTF8
if($errors.Count -or -not $verification.Passed){throw '驗收尚未全部通過。請查看 Acceptance-Result.json；若要求重新開機，手動重開後再執行此入口。'}
Write-Host '設定及清理驗收通過。請目視確認自動登入、工作列僅釘選 Edge ；NUC 適用時再確認無 AMD 位置提示。' -ForegroundColor Green


