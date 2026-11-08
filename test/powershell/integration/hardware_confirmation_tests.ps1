#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('hardware_confirm_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
$resultPath=Join-Path $fixture 'result.json'
@{Computer=$env:COMPUTERNAME;UserSID='fixture_sid';HardwareProfile=@{ConfirmedBoard='NUC8i7HVB';ConfirmationComputer=$env:COMPUTERNAME}}|ConvertTo-Json -Depth 5|Set-Content $resultPath -Encoding UTF8
$confirmation=Get-SetupSavedHardwareConfirmation -ResultPath $resultPath -UserSID fixture_sid
Assert ($confirmation.ConfirmedBoard -eq 'NUC8i7HVB') '續跑可恢復本機同帳號明確確認'
Assert ((Get-SetupSavedHardwareConfirmation -ResultPath $resultPath -UserSID different).Count -eq 0) '續跑不沿用其他帳號確認'
Assert ((Get-SetupSavedHardwareConfirmation -ResultPath $resultPath -UserSID fixture_sid -Computer different).Count -eq 0) '續跑不沿用其他電腦確認'
foreach($file in @('core/configure_nuc.ps1','core/run_module.ps1','modules/drivers/install_drivers.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
 $elevation=$ast.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Extent.Text -match 'Start-Process powershell.exe -Verb RunAs'},$true)
 $fakeEntry=Join-Path $fixture 'target.ps1'
 [IO.File]::WriteAllText($fakeEntry,'param($Module,$ExpectedUserSID,$DriverPackagePath,$ConfirmedBoard,$ConfirmationComputer);[pscustomobject]@{Board=$ConfirmedBoard;Computer=$ConfirmationComputer}',[Text.UTF8Encoding]::new($true))
 $capturedState=@{Args=''}
 function Start-Process {param($FilePath,$Verb,$ArgumentList);$capturedState.Args=$ArgumentList}
 $ConfirmedBoard='NUC8i7HVB';$ConfirmationComputer=$env:COMPUTERNAME;$DriverPackagePath='';$currentSID='fixture';$sid=$currentSID;$Module='Install-Drivers';$VerifyOnly=$false;$SyncOnly=$false;$Mode='All'
 $body=$elevation.Clauses[0].Item2.Statements|Where-Object {$_ -isnot [Management.Automation.Language.ExitStatementAst] -and $_ -isnot [Management.Automation.Language.ReturnStatementAst]}|ForEach-Object {$_.Extent.Text}
 & ([scriptblock]::Create(($body -join "`n").Replace('$PSCommandPath','$fakeEntry')))
 $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($capturedState.Args -split '-EncodedCommand ')[1]))
 $result=& ([scriptblock]::Create($decoded))
 Assert ($result.Board -eq $ConfirmedBoard -and $result.Computer -eq $ConfirmationComputer) ('真提權命令保留本機驅動確認：'+$file)
}