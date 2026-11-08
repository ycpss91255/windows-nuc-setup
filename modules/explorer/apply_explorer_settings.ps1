#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$resultFileName=if($VerifyOnly){'Explorer-Verification.json'}else{'Explorer-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Explorer-Worker.ps1'
 . (Join-Path $PSScriptRoot '../native/managed_source_library.ps1')
 $null=Copy-SetupManagedSource -SourceRoot $PSScriptRoot -DestinationRoot $root -FileName 'explorer.cs'
 Copy-Item $PSCommandPath $workerPath -Force
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Apply-Explorer'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $workerArgs
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '未取得桌面隱藏檔案設定結果，請先登入桌面。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot $resultFileName)){Copy-Item $resultPath (Join-Path $PSScriptRoot $resultFileName) -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
 $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
 if(-not $VerifyOnly){
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  Set-ItemProperty $key -Name Hidden -Value 1|Out-Null
  Set-ItemProperty $key -Name ShowSuperHidden -Value 0|Out-Null
  Set-ItemProperty $key -Name HideFileExt -Value 0|Out-Null
  if(-not ('NucExplorerRefresh' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class NucExplorerRefresh{[DllImport("shell32.dll")]public static extern void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b);}'}
  [NucExplorerRefresh]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
 }
 if(-not ('NucExplorerLiveV2' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'native/explorer.cs')}
 $shellOptions=[NucExplorerLiveV2]::Options((-not $VerifyOnly))
 $shellHidden=($shellOptions -band 1) -ne 0
 $shellExtensions=($shellOptions -band 2) -ne 0
 if(-not $VerifyOnly){
  $shell=New-Object -ComObject Shell.Application
  foreach($window in @($shell.Windows())){try{if($window.FullName -match 'explorer.exe$'){$window.Refresh()}}catch{Write-Warning '有一個檔案總管視窗無法立即重新整理。'}}
 }
 $actual=Get-ItemProperty $key
 $result=[ordered]@{Success=($actual.Hidden -eq 1 -and $actual.ShowSuperHidden -eq 0 -and $actual.HideFileExt -eq 0 -and $shellHidden -and $shellExtensions);ShellShowsHidden=$shellHidden;ShellShowsExtensions=$shellExtensions;ShowFileExtensions=($actual.HideFileExt -eq 0);ShowHiddenFiles=($actual.Hidden -eq 1);HideProtectedSystemFiles=($actual.ShowSuperHidden -eq 0);CheckedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if(-not $result.Success){throw '隱藏檔案或副檔名顯示設定驗證失敗。'}
 Write-Host '已顯示一般隱藏檔案與副檔名；受保護的系統檔案仍隱藏。' -ForegroundColor Green
}catch{ @{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8;throw }



