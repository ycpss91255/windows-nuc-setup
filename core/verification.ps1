#Requires -Version 5.1
function Invoke-FreshVerification {
 param([Parameter(Mandatory=$true)][string]$ScriptPath,[Parameter(Mandatory=$true)][string]$ReportPath,[hashtable]$Arguments=@{})
 $runId=[guid]::NewGuid().ToString()
 $callArguments=@{};foreach($key in $Arguments.Keys){$callArguments[$key]=$Arguments[$key]}
 $callArguments.VerificationRunId=$runId
 & $ScriptPath @callArguments | Out-Null
 if(-not(Test-Path -LiteralPath $ReportPath -PathType Leaf)){throw '本輪驗證未產生結果。'}
 $result=Get-Content -LiteralPath $ReportPath -Raw|ConvertFrom-Json
 if($result.VerificationRunId -cne $runId){throw '驗證結果不是本輪產生；拒絕使用舊結果。'}
 if($result.Computer -cne $env:COMPUTERNAME -or $result.UserSID -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw '驗證結果的電腦或使用者不符。'}
 return $result
}
function Test-WindowsUpdateResult {
 param($Result)
 if($null -eq $Result -or $null -eq $Result.PSObject.Properties['Selected'] -or $null -eq $Result.PSObject.Properties['Updates']){return $false}
 if($Result.Selected -isnot [int] -and $Result.Selected -isnot [long]){return $false}
 if($Result.Selected -lt 0 -or $null -eq $Result.Updates){return $false}
 $updates=@($Result.Updates)
 return ($updates.Count -eq $Result.Selected -and @($updates|Where-Object {$null -eq $_ -or $_.ResultCode -ne 2}).Count -eq 0)
}