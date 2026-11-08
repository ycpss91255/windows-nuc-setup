#Requires -Version 5.1

param([ValidateSet('Save','Load','Verify')][string]$Mode='Load',[switch]$Worker,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId,[string]$ExpectedUserSID)
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號儲存或套用桌面排列。'}
if($Mode -ne 'Save' -and (Get-UICulture).Name -ne 'zh-TW'){Write-Host '[略過] 目前桌面排列範本僅適用繁體中文，未套用座標。';[pscustomobject]@{Status='Skipped';Module='desktop_icon_layout.ps1';Reason='目前排列範本使用繁體中文圖示名稱'};return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"' -Mode "+$Mode
 if($Worker){$command+=' -Worker'}
 if($VerificationRunId){$command+=" -VerificationRunId '"+$VerificationRunId+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'IconLayout-Worker.ps1'
 . (Join-Path $PSScriptRoot '../native/managed_source_library.ps1')
 $null=Copy-SetupManagedSource -SourceRoot $PSScriptRoot -DestinationRoot $root -FileName 'desktop_icons.cs'
 Copy-Item $PSCommandPath $workerPath -Force
 $reference=Join-Path $PSScriptRoot 'desktop_layout.json'
 if($Mode -ne 'Save' -and $reference -ne (Join-Path $root 'desktop_layout.json')){Copy-Item $reference (Join-Path $root 'desktop_layout.json') -Force}
 $resultPath=Join-Path $root 'IconLayout-Result.json'
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Desktop-IconLayout'
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker -Mode '+$Mode+$(if($VerificationRunId){' -VerificationRunId '+$VerificationRunId}else{''}))
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '未取得桌面圖示位置結果，請先登入桌面。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot 'IconLayout-Result.json')){Copy-Item $resultPath (Join-Path $PSScriptRoot 'IconLayout-Result.json') -Force}
 if($Mode -eq 'Save' -and (Join-Path $root 'desktop_layout.json') -ne $reference){Copy-Item (Join-Path $root 'desktop_layout.json') $reference -Force}
 $result|ConvertTo-Json -Depth 6|Write-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
Add-Type -Path (Join-Path $PSScriptRoot 'native/desktop_icons.cs')
 $snapshot=[NUC8Icons.Desktop]::Capture()
 $referencePath=Join-Path $PSScriptRoot 'desktop_layout.json'
 if($Mode -eq 'Save'){
  if($snapshot.Icons.Count -ne 4){throw ('目前桌面不是四個圖示，請先確認：'+$snapshot.Icons.Count)}
  $reference=[ordered]@{Width=$snapshot.Width;Height=$snapshot.Height;Icons=@($snapshot.Icons|Select-Object Name,X,Y);SavedAt=(Get-Date).ToString('o')}
  $reference|ConvertTo-Json -Depth 5|Set-Content $referencePath -Encoding UTF8
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=$true;Mode=$Mode;Reference=$reference}
 }else{
  $reference=Get-Content $referencePath -Raw|ConvertFrom-Json
  if($snapshot.Width -ne $reference.Width -or $snapshot.Height -ne $reference.Height){throw '桌面範圍與範本不同，請確認解析度、縮放及螢幕數量。'}
  $differences=@()
  foreach($expected in $reference.Icons){
   $actual=@($snapshot.Icons|Where-Object Name -eq $expected.Name)
   if($actual.Count -ne 1){$differences+=('找不到唯一圖示：'+$expected.Name);continue}
   if($Mode -eq 'Load'){[NUC8Icons.Desktop]::Position($actual[0].Index,[int]$expected.X,[int]$expected.Y)}
  }
  if($Mode -eq 'Load'){
   $key='HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
   $flags=(Get-ItemProperty $key -ErrorAction SilentlyContinue).FFlags
   if($null -ne $flags){Set-ItemProperty $key -Name FFlags -Value ($flags -band (-bnot 1))}
   Start-Sleep -Milliseconds 500
  }
  $after=[NUC8Icons.Desktop]::Capture()
  foreach($expected in $reference.Icons){$actual=@($after.Icons|Where-Object Name -eq $expected.Name);if($actual.Count -eq 1 -and ([math]::Abs($actual[0].X-$expected.X) -gt 2 -or [math]::Abs($actual[0].Y-$expected.Y) -gt 2)){$differences+=('位置不符：'+$expected.Name)}}
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=($differences.Count -eq 0);Mode=$Mode;Differences=$differences;Actual=@($after.Icons|Select-Object Name,X,Y);Error=($differences -join '；')}
 }
 $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'IconLayout-Result.json') -Encoding UTF8
 if((Join-Path $PSScriptRoot 'IconLayout-Result.json') -ne (Join-Path $root 'IconLayout-Result.json')){$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'IconLayout-Result.json') -Encoding UTF8}
 $result|ConvertTo-Json -Depth 6|Write-Host
 if(-not $result.Success){throw $result.Error}
}catch{
 @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'IconLayout-Result.json') -Encoding UTF8
 throw
}