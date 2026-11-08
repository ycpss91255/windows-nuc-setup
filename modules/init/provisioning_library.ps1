#Requires -Version 5.1
# Definitions only: loading this file never creates accounts or applies a package.
function Test-InitProvisioningContext {
 param([string]$Sid,[int]$Build,[int]$ProductType,[bool]$Is64Bit,[bool]$IsWinPE,[int]$OobeInProgress,[int]$SetupInProgress,[bool]$OobeProcessInSession)
 return ($Sid -eq 'S-1-5-18' -and $Build -ge 22621 -and $ProductType -eq 1 -and $Is64Bit -and -not $IsWinPE -and $OobeInProgress -eq 1 -and $SetupInProgress -eq 1 -and $OobeProcessInSession)
}
function New-InitProvisioningState {
 param([string]$MachineGuid,[string]$ComputerName,[string]$SourceRoot,[string]$PackageHash)
 return [pscustomobject][ordered]@{SchemaVersion=1;MachineGuid=$MachineGuid;ComputerName=$ComputerName;SourceRoot=$SourceRoot;PackageHash=$PackageHash;PackageId='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageVersion='1.0';TargetUserName='';TargetSid='';Phase='Prepared';LastErrorCode='';UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
}
function Assert-InitProvisioningState {
 param($State,[string]$MachineGuid,[string]$PackageHash)
 $fields=@('SchemaVersion','MachineGuid','ComputerName','SourceRoot','PackageHash','PackageId','PackageVersion','TargetUserName','TargetSid','Phase','LastErrorCode','UpdatedUtc')
 if($null -eq $State -or @($State.PSObject.Properties.Name).Count -ne $fields.Count -or @($State.PSObject.Properties.Name|Where-Object {$_ -notin $fields}).Count){throw 'Init 狀態欄位不符，拒絕讀取未知或機密欄位。'}
 if($State.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($MachineGuid) -or $State.MachineGuid -cne $MachineGuid -or $PackageHash -notmatch '^[a-fA-F0-9]{64}$' -or $State.PackageHash -ine $PackageHash){throw 'Init 狀態不屬於此機器或設定包。'}
 if($State.PackageId -ne '1c2605ea-96ae-42fc-8f11-45fc0cb9d133' -or $State.PackageVersion -ne '1.0' -or $State.Phase -notin @('Prepared','AccountReady','AwaitingConsent','ApplyPending','AwaitingLogon','SshPending','Complete')){throw 'Init 狀態版本或階段無效。'}
 if($State.Phase -ne 'Prepared' -and ($State.TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or [string]::IsNullOrWhiteSpace($State.TargetUserName))){throw 'Init 狀態缺少已確認的正式帳號 SID。'}
}
