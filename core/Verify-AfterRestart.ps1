#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath
$skippedModules=@(@('Install-Drivers.ps1','Apply-AMDPrivacySettings.ps1','Desktop-IconLayout.ps1')|ForEach-Object {Get-SetupModuleDecision -Module $_ -Hardware $hardware}|Where-Object {-not $_.Applicable})
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "'+$PSCommandPath+'"');exit
}
& (Resolve-NucPath 'Test-SetupPrerequisites.ps1') -DriverPackagePath $DriverPackagePath
$errors=@();$remaining=@()
$resultPath=Resolve-NucPath 'Setup-Result.json'
if(Test-Path $resultPath){
 $previous=Get-Content $resultPath -Raw|ConvertFrom-Json
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($previous.Computer -eq $env:COMPUTERNAME -and $previous.UserSID -eq $sid){
  $config=[IO.File]::ReadAllText((Resolve-NucPath 'Configure-NUC.ps1'))
  $allowed=@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
  foreach($file in @($previous.FailedModules|Where-Object {$_ -and $_ -ne 'Install-WindowsUpdates.ps1'})){
   if($file -notin $allowed){throw ('未知的失敗模組：'+$file)}
   $decision=Get-SetupModuleDecision -Module $file -Hardware $hardware
   if(-not $decision.Applicable){Write-Host ('[略過] '+$decision.Reason);continue}
   Write-Host ('重試未完成模組：'+$file) -ForegroundColor Cyan
   try{ if($file -eq 'Install-Drivers.ps1'){& (Resolve-NucPath $file) -DriverPackagePath $DriverPackagePath}else{& (Resolve-NucPath $file)} }catch{$errors+=($file+'：'+$_.Exception.Message);$remaining+=$file;Write-Warning $errors[-1]}
  }
 }
}
Write-Host '重新掃描更新；完成後再次清理預載程式並驗證。' -ForegroundColor Cyan
foreach($file in @('Install-WindowsUpdates.ps1','Apply-Debloat.ps1','Apply-CopilotSettings.ps1','Remove-SetupResidue.ps1')){
 try{ if($file -eq 'Install-Drivers.ps1'){& (Resolve-NucPath $file) -DriverPackagePath $DriverPackagePath}else{& (Resolve-NucPath $file)} }catch{$errors+=($file+'：'+$_.Exception.Message);$remaining+=$file;Write-Warning $errors[-1]}
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
$layoutDecision=Get-SetupModuleDecision -Module 'Desktop-IconLayout.ps1' -Hardware $hardware
if($layoutDecision.Applicable){try{ & (Resolve-NucPath 'Desktop-IconLayout.ps1') -Mode Load }catch{$errors+=$_.Exception.Message}}else{Write-Host ('[略過] '+$layoutDecision.Reason)}
& (Resolve-NucPath 'Verify-Only.ps1')
$verification=Get-Content (Resolve-NucPath 'Verification-Result.json') -Raw|ConvertFrom-Json
@{Computer=$env:COMPUTERNAME;CheckedAt=(Get-Date).ToString('o');Success=($verification.Passed -and $errors.Count -eq 0);Errors=$errors;SkippedChecks=@($verification.Checks|Where-Object Status -eq Skipped);HardwareProfile=$hardware;FailedChecks=@($verification.Checks|Where-Object {$_.Status -ne 'Skipped' -and -not $_.Passed})}|ConvertTo-Json -Depth 6|Set-Content (Resolve-NucPath 'Acceptance-Result.json') -Encoding UTF8
if($errors.Count -or -not $verification.Passed){throw '驗收尚未全部通過。請查看 Acceptance-Result.json；若要求重新開機，手動重開後再執行此入口。'}
Write-Host '設定及清理驗收通過。請目視確認自動登入、工作列僅釘選 Edge ；NUC 適用時再確認無 AMD 位置提示。' -ForegroundColor Green


