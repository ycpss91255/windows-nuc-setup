#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$library=Join-Path $root 'modules/privacy/privacy_library.ps1'
Assert (Test-Path $library) '隱私政策有可安全載入的具名來源'
. $library
foreach($edition in @('Professional','ProfessionalN','ProfessionalWorkstation','ProfessionalWorkstationN')){
 $plan=Get-SetupPrivacyPlan -EditionId $edition
 Assert ($plan.Supported -and $plan.DiagnosticLevel -eq 1) ('專業版最低仍為必要診斷 '+$edition)
}
foreach($edition in @('Enterprise','EnterpriseS','Education','EducationN','IoTEnterprise')){Assert ((Get-SetupPrivacyPlan -EditionId $edition).DiagnosticLevel -eq 0) ('支援版本可停Windows診斷 '+$edition)}
Assert ((Get-SetupPrivacyPlan -EditionId 'ServerDatacenter' -ProductType 3).DiagnosticLevel -eq 0) 'Server正確使用支援最低值'
foreach($edition in @('Core','CoreSingleLanguage','Unknown','')){Assert (-not(Get-SetupPrivacyPlan -EditionId $edition).Supported) ('未支援版本不可假PASS '+$edition)}
$plan=Get-SetupPrivacyPlan -EditionId Professional
Assert ($plan.Policies.Count -eq 9) '精確限定九項政策值'
$tailored=@($plan.Policies|Where-Object Name -eq 'DisableTailoredExperiencesWithDiagnosticData')[0]
Assert ($tailored.Path -like 'HKCU:*' -and $tailored.Value -eq 1) '個人化政策使用目前使用者及正確反向值'
Assert (@($plan.Policies|Where-Object {$_.Path -match 'Defender|Firewall|WindowsUpdate|CapabilityAccessManager'}).Count -eq 0) '政策不更動安全服務或一般app權限'
$script:registry=@{};$script:writes=0;$script:wrongType=$false;$script:dropWrites=$false
function Test-Path {param($LiteralPath,$Path) if($LiteralPath -like 'HK*:*' -or $Path -like 'HK*:*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) $script:writes++;if(-not $script:dropWrites){$script:registry[$LiteralPath+'|'+$Name]=[pscustomobject]@{Value=$Value;Kind='DWord'}}}
function Get-Item {param($LiteralPath,$ErrorAction) $obj=[pscustomobject]@{FixturePath=$LiteralPath};$obj|Add-Member ScriptMethod GetValue {param($Name) $key=$this.FixturePath+'|'+$Name;if(-not $script:registry.ContainsKey($key)){return $null};$script:registry[$key].Value};$obj|Add-Member ScriptMethod GetValueKind {param($Name) if($script:wrongType){return 'String'};$key=$this.FixturePath+'|'+$Name;if(-not $script:registry.ContainsKey($key)){throw 'missing'};$script:registry[$key].Kind};return $obj}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('privacy_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$call=@{EditionId='ProfessionalWorkstation';ReportPath=(Join-Path $fixture 'result.json');UserSid='fixture-sid';Computer='fixture-computer'}
Reject {Invoke-SetupPrivacy @call -VerifyOnly} '未設定的VerifyOnly失敗'
Assert ($script:writes -eq 0) 'VerifyOnly不寫registry'
Invoke-SetupPrivacy @call|Out-Null
Assert ($script:writes -eq 9 -and $script:registry.Count -eq 9) '只寫九個核准政策'
$result=Get-Content $call.ReportPath -Raw|ConvertFrom-Json
Assert ($result.Success -and $result.DiagnosticLevel -eq 1 -and $result.Checks.Count -eq 9) '讀回全項後記錄成功及必要診斷限制'
Assert ($result.UserSID -eq 'fixture-sid' -and $result.Computer -eq 'fixture-computer') '紀錄動態執行身分'
$before=$script:writes;Invoke-SetupPrivacy @call -VerifyOnly|Out-Null;Assert ($script:writes -eq $before) '已設定VerifyOnly依然不寫registry'
$script:wrongType=$true;Reject {Invoke-SetupPrivacy @call -VerifyOnly} '相同數值但registry型別錯誤必須拒絕';$script:wrongType=$false
$key='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry';$script:registry[$key].Value=3
Reject {Invoke-SetupPrivacy @call -VerifyOnly} '診斷級別錯誤必須拒絕'
$script:dropWrites=$true;Reject {Invoke-SetupPrivacy @call} '寫入未生效不得宣稱成功';$script:dropWrites=$false
$before=$script:writes;Reject {Invoke-SetupPrivacy -EditionId Core -ReportPath $call.ReportPath -UserSid x -Computer y} 'Home明確Unsupported'
$result=Get-Content $call.ReportPath -Raw|ConvertFrom-Json
Assert (-not $result.Success -and $result.Status -eq 'Unsupported' -and $script:writes -eq $before) 'Unsupported報告不假通過且無寫入'
Write-Host 'ALL PASS: privacy named-source tests; registry is in-memory only'
