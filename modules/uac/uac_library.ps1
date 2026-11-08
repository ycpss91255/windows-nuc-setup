#Requires -Version 5.1
# https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/settings-and-configuration/
function Assert-UacPlainPath {
 param([string]$Path)
 $full=[IO.Path]::GetFullPath($Path);$cursor=$full
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'UAC紀錄路徑不可使用重新解析點。'}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
 return $full
}
function Read-SetupUacValue {
 param([string]$Name)
 $key=Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
 $exists=$Name -in @($key.GetValueNames())
 $kind='';$value=$null
 if($exists){$kind=[string]$key.GetValueKind($Name);$value=$key.GetValue($Name)}
 [pscustomobject]@{Exists=$exists;Kind=$kind;Value=$value}
}
function Invoke-SetupUac {
 param([Parameter(Mandatory=$true)][string]$StatePath,[Parameter(Mandatory=$true)][string]$ReportPath,
 [Parameter(Mandatory=$true)][string]$MachineId,[Parameter(Mandatory=$true)][string]$UserSid,
 [string]$Computer=$env:COMPUTERNAME,[string]$VerificationRunId,[switch]$VerifyOnly,[switch]$Restore)
 $ErrorActionPreference='Stop'
 if($VerifyOnly -and $Restore){throw 'VerifyOnly與Restore不可同時使用。'}
 $StatePath=Assert-UacPlainPath $StatePath;$ReportPath=Assert-UacPlainPath $ReportPath
 if($StatePath -eq $ReportPath){throw '原值快照與結果路徑不可相同。'}
 $success=$false;$errorText='';$mode=if($Restore){'Restore'}elseif($VerifyOnly){'VerifyOnly'}else{'Apply'}
 try{
  $lua=Read-SetupUacValue EnableLUA
  if(-not $lua.Exists -or $lua.Kind -ne 'DWord' -or $lua.Value -ne 1){throw '目前EnableLUA不是DWORD 1；請先人工確認既有UAC設定，本模組不會修改它。'}
  $original=$null
  if(-not $VerifyOnly){
   if(Test-Path -LiteralPath $StatePath){
    $original=Get-Content -LiteralPath $StatePath -Raw|ConvertFrom-Json
    if($original.Schema -ne 1 -or $original.MachineId -cne $MachineId -or $original.Exists -isnot [bool] -or ($original.Exists -and ($original.Kind -ne 'DWord' -or $original.Value -isnot [int] -or $original.Value -lt 0 -or $original.Value -gt 5))){throw 'UAC原值快照損壞、型別不符或來自其他電腦。'}
   }elseif($Restore){throw '沒有這臺電腦的UAC原值快照，無法還原。'}
   else{
    $current=Read-SetupUacValue ConsentPromptBehaviorAdmin
    if($current.Exists -and ($current.Kind -ne 'DWord' -or $current.Value -lt 0 -or $current.Value -gt 5)){throw '原政策不是有效DWORD值，拒絕覆寫。'}
    $original=[ordered]@{Schema=1;MachineId=$MachineId;Exists=[bool]$current.Exists;Kind=$current.Kind;Value=$current.Value}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($StatePath))
    # CreateNew is atomic and never replaces the first snapshot, including concurrent invocations.
    $bytes=[Text.Encoding]::UTF8.GetBytes(($original|ConvertTo-Json));$stream=[IO.File]::Open($StatePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
   }
  }
  $path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
  if(-not $VerifyOnly){
   if($Restore -and -not $original.Exists){if((Read-SetupUacValue ConsentPromptBehaviorAdmin).Exists){Remove-ItemProperty -LiteralPath $path -Name ConsentPromptBehaviorAdmin -ErrorAction Stop}}
   else{$value=if($Restore){[int]$original.Value}else{0};New-ItemProperty -LiteralPath $path -Name ConsentPromptBehaviorAdmin -Value $value -PropertyType DWord -Force -ErrorAction Stop|Out-Null}
  }
  $actual=Read-SetupUacValue ConsentPromptBehaviorAdmin
  if($Restore -and -not $original.Exists){$success=-not $actual.Exists}
  else{$expected=if($Restore){[int]$original.Value}else{0};$success=$actual.Exists -and $actual.Kind -eq 'DWord' -and $actual.Value -eq $expected}
  if(-not $success){throw 'UAC政策讀回不符合要求，可能被組織政策覆寫。'}
 }catch{$success=$false;$errorText=$_.Exception.Message}
 $result=[ordered]@{Success=$success;Mode=$mode;UserSID=$UserSid;Computer=$Computer;VerificationRunId=$VerificationRunId;CheckedAt=(Get-Date).ToString('o');Error=$errorText;Scope='此電腦所有管理員的提權提示；保留UAC與標準使用者政策。'}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ReportPath));[IO.File]::WriteAllText($ReportPath,($result|ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
 if(-not $success){throw $errorText}
 [pscustomobject]$result
}
function Invoke-CurrentUserUac {
 param([switch]$VerifyOnly,[switch]$Restore,[string]$VerificationRunId)
 $machine=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
 if([string]::IsNullOrWhiteSpace($machine)){throw '無法取得此電腦的MachineGuid。'}
 $root=Join-Path $env:ProgramData 'NUC8-Setup'
 Invoke-SetupUac -StatePath (Join-Path $root 'UAC-Original.json') -ReportPath (Join-Path $root 'UAC-Result.json') -MachineId $machine -UserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -VerifyOnly:$VerifyOnly -Restore:$Restore -VerificationRunId $VerificationRunId
}