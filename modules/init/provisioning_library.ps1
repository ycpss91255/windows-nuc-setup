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
 if($State.PackageId -ne '1c2605ea-96ae-42fc-8f11-45fc0cb9d133' -or $State.PackageVersion -ne '1.0' -or $State.Phase -notin @('Prepared','AccountCreated','AccountReady','AwaitingConsent','ApplyPending','AwaitingLogon','SshPending','Complete')){throw 'Init 狀態版本或階段無效。'}
 if($State.Phase -ne 'Prepared' -and ($State.TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or [string]::IsNullOrWhiteSpace($State.TargetUserName))){throw 'Init 狀態缺少已確認的正式帳號 SID。'}
}
function New-InitProvisioningAccount {
 param($State,[string]$UserName,[Security.SecureString]$Password,[string]$StatePath)
 if($State.Phase -notin @('Prepared','AccountCreated','AccountReady')){throw '目前階段不可建立或恢復帳號。'}
 if($State.TargetSid){
  $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
  if(-not $user -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or $UserName -cne $State.TargetUserName -or -not $user.Enabled){throw '已建立帳號的 SID、名稱或啟用狀態改變，停止恢復。'}
 }else{
  if($State.Phase -ne 'Prepared' -or [string]::IsNullOrWhiteSpace($UserName) -or $null -eq $Password -or $Password.Length -eq 0){throw '缺少有效的新帳號與安全密碼。'}
  if(Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue){throw '此帳號已存在；不重設密碼、不變更群組。'}
  $State.TargetUserName=$UserName
  Save-InitProvisioningState -State $State -StatePath $StatePath
  $user=New-LocalUser -Name $UserName -Password $Password -ErrorAction Stop
  if(-not $user -or $user.SID.Value -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw '無法取得新帳號 SID；保留帳號，停止而不盲目重建。'}
  $State.TargetSid=$user.SID.Value;$State.Phase='AccountCreated'
  Save-InitProvisioningState -State $State -StatePath $StatePath
 }
 $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
 if(-not $user -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or -not $user.Enabled){throw '新帳號讀回驗證失敗，保留帳號並停止。'}
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $State.TargetSid -ErrorAction Stop}
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){throw '管理員群組 SID 讀回驗證失敗。'}
 $State.Phase='AccountReady';$State.LastErrorCode=''
 Save-InitProvisioningState -State $State -StatePath $StatePath
}
function Assert-InitProtectedDirectory {
 param([string]$Path)
 Assert-InitPlainPath -Path $Path
 $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
 if(-not $acl.AreAccessRulesProtected){throw 'Init 暫存目錄未停用繼承，拒絕寫入。'}
 $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 暫存目錄擁有者不是 SYSTEM 或管理員群組。'}
 $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 foreach($rule in $rules){if($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 暫存目錄存在非預期 ACL。'}}
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  if(-not @($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and $_.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl -and $_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -and $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None}).Count){throw 'Init 暫存目錄缺少可繼承的完整保護規則。'}
 }
}
function Save-InitProvisioningState {
 param($State,[string]$StatePath)
 Assert-InitProvisioningState -State $State -MachineGuid $State.MachineGuid -PackageHash $State.PackageHash
 Assert-InitPlainPath -Path $StatePath
 Assert-InitProtectedDirectory -Path (Split-Path $StatePath -Parent)
 $State.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
 $temporary=$StatePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $backup=$temporary+'.previous'
 try{
  [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 3),(New-Object Text.UTF8Encoding($false)))
  if(Test-Path -LiteralPath $StatePath){[IO.File]::Replace($temporary,$StatePath,$backup)}else{[IO.File]::Move($temporary,$StatePath)}
 }finally{foreach($path in @($temporary,$backup)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
}
