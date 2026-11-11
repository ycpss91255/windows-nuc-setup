#Requires -Version 5.1
# Microsoft policy mappings and edition limits: see readme.md Windows privacy section.
function Get-SetupPrivacyPlan {
 param([AllowEmptyString()][string]$EditionId,[ValidateSet(1,2,3)][int]$ProductType=1)
 $required=@('Professional','ProfessionalN','ProfessionalWorkstation','ProfessionalWorkstationN','ProfessionalEducation','ProfessionalEducationN')
 $off=@('Enterprise','EnterpriseN','EnterpriseS','EnterpriseSN','EnterpriseG','EnterpriseGN','Education','EducationN','IoTEnterprise','IoTEnterpriseS')
 $supported=$ProductType -in @(2,3) -or $EditionId -in $required -or $EditionId -in $off
 if(-not $supported){return [pscustomobject]@{Supported=$false;EditionId=$EditionId;DiagnosticLevel=$null;Policies=@()}}
 $level=if($ProductType -in @(2,3) -or $EditionId -in $off){0}else{1}
 $machine='HKLM:\SOFTWARE\Policies\Microsoft'
 $policies=@(
  @{Path=$machine+'\Windows\DataCollection';Name='AllowTelemetry';Value=$level;Description='Windows診斷資料最低支援級別'},
  @{Path=$machine+'\Windows\DataCollection';Name='DoNotShowFeedbackNotifications';Value=1;Description='不顯示回饋邀請'},
  @{Path=$machine+'\Windows\AdvertisingInfo';Name='DisabledByGroupPolicy';Value=1;Description='停用廣告識別碼'},
  @{Path='HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';Name='DisableTailoredExperiencesWithDiagnosticData';Value=1;Description='不以診斷資料個人化推薦'},
  @{Path=$machine+'\Windows\System';Name='EnableActivityFeed';Value=0;Description='停用活動摘要'},
  @{Path=$machine+'\Windows\System';Name='PublishUserActivities';Value=0;Description='不發布使用者活動'},
  @{Path=$machine+'\Windows\System';Name='UploadUserActivities';Value=0;Description='不上傳使用者活動'},
  @{Path=$machine+'\InputPersonalization';Name='AllowInputPersonalization';Value=0;Description='停用線上語音辨識，包含雲端聽寫'},
  @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput';Name='AllowLinguisticDataCollection';Value=0;Description='不分享手寫與輸入改善資料'}
 )
 [pscustomobject]@{Supported=$true;EditionId=$EditionId;DiagnosticLevel=$level;Policies=$policies}
}
function Read-SetupPrivacyValue {
 param([string]$Path,[string]$Name)
 try{
  $key=Get-Item -LiteralPath $Path -ErrorAction Stop
  $value=$key.GetValue($Name)
  $kind=[string]$key.GetValueKind($Name)
  [pscustomobject]@{Value=$value;Kind=$kind;Error=''}
 }catch{[pscustomobject]@{Value=$null;Kind='';Error=$_.Exception.Message}}
}
function Invoke-SetupPrivacy {
 param([AllowEmptyString()][string]$EditionId,[ValidateSet(1,2,3)][int]$ProductType=1,
  [Parameter(Mandatory=$true)][string]$ReportPath,[Parameter(Mandatory=$true)][string]$UserSid,
  [string]$Computer=$env:COMPUTERNAME,[string]$VerificationRunId,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 $plan=Get-SetupPrivacyPlan -EditionId $EditionId -ProductType $ProductType
 $checks=@();$writeErrors=@()
 if($plan.Supported){
  foreach($policy in $plan.Policies){
   if(-not $VerifyOnly){
    try{
     if(-not(Test-Path -LiteralPath $policy.Path)){New-Item -Path $policy.Path -Force -ErrorAction Stop|Out-Null}
     New-ItemProperty -LiteralPath $policy.Path -Name $policy.Name -Value $policy.Value -PropertyType DWord -Force -ErrorAction Stop|Out-Null
    }catch{$writeErrors+=$policy.Name+': '+$_.Exception.Message}
   }
   $actual=Read-SetupPrivacyValue -Path $policy.Path -Name $policy.Name
   $numeric=$actual.Value -is [int] -or $actual.Value -is [uint32]
   $checks+=[pscustomobject]@{Name=$policy.Name;Description=$policy.Description;Path=$policy.Path;Expected=$policy.Value;Actual=$actual.Value;Kind=$actual.Kind;Passed=($numeric -and $actual.Kind -eq 'DWord' -and $actual.Value -eq $policy.Value);ReadError=$actual.Error}
  }
 }
 $success=$plan.Supported -and $writeErrors.Count -eq 0 -and @($checks|Where-Object {-not $_.Passed}).Count -eq 0
 $status=if(-not $plan.Supported){'Unsupported'}elseif($success){'Passed'}else{'Failed'}
 $result=[ordered]@{Success=$success;Status=$status;EditionId=$EditionId;ProductType=$ProductType;DiagnosticLevel=$plan.DiagnosticLevel;UserSID=$UserSid;Computer=$Computer;VerificationRunId=$VerificationRunId;VerifyOnly=[bool]$VerifyOnly;CheckedAt=(Get-Date).ToString('o');Checks=$checks;WriteErrors=$writeErrors;Scope='Windows政策讀回；不代表網路流量為零，也不涵蓋其他應用程式。'}
 $destination=[IO.Path]::GetFullPath($ReportPath)
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
 [IO.File]::WriteAllText($destination,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($true))
 if(-not $plan.Supported){throw ('不支援此Windows版本的政策驗證：'+$EditionId+'；未套用隱私設定。')}
 if(-not $success){throw ('隱私政策寫入或讀回失敗，請查看 '+$destination)}
 Write-Host ('隱私政策讀回完成；Windows診斷級別：'+$plan.DiagnosticLevel+'。必要服務及其他應用程式仍可能傳送資料。') -ForegroundColor Green
 return [pscustomobject]$result
}

function Invoke-CurrentUserPrivacy {
 param([string]$ReportPath=(Join-Path $env:ProgramData 'NUC8-Setup/Privacy-Result.json'),[string]$VerificationRunId,[switch]$VerifyOnly)
 $edition=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).EditionID
 $productType=(Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType
 Invoke-SetupPrivacy -EditionId $edition -ProductType $productType -ReportPath $ReportPath -UserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -Computer $env:COMPUTERNAME -VerificationRunId $VerificationRunId -VerifyOnly:$VerifyOnly
}
