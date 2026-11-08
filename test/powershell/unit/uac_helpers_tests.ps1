#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{Assert (-not ($_.Exception -is [Management.Automation.ParameterBindingException])) ($Name+'：必須進入真函式而非參數繫結失敗');$caught=$true};Assert $caught $Name}
$lib=Join-Path $root 'modules/uac/uac_library.ps1'
Assert (Test-Path $lib) 'UAC有無副作用具名函式來源'
. $lib
$script:values=@{EnableLUA=1;ConsentPromptBehaviorAdmin=5;PromptOnSecureDesktop=1;ConsentPromptBehaviorUser=3}
$script:kinds=@{EnableLUA='DWord';ConsentPromptBehaviorAdmin='DWord'};$script:writes=@();$script:drop=$false
function Get-Item {param($LiteralPath,$ErrorAction) if($LiteralPath -like 'HKLM:*'){$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) if(-not $script:values.ContainsKey($name)){throw 'missing'};$script:kinds[$name]};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) if($Name -ne 'ConsentPromptBehaviorAdmin'){throw '禁止修改其他政策'};$script:writes+=@($Name);if(-not $script:drop){$script:values[$Name]=$Value;$script:kinds[$Name]=$PropertyType}}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($Name -ne 'ConsentPromptBehaviorAdmin'){throw '禁止移除其他政策'};$script:writes+=@($Name);$script:values.Remove($Name);$script:kinds.Remove($Name)}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('uac_test_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$args=@{StatePath=(Join-Path $dir 'original.json');ReportPath=(Join-Path $dir 'result.json');MachineId='machine-a';UserSid='test-sid';Computer='test-pc'}
Reject {Invoke-SetupUac @args -VerifyOnly} '未設定時驗證必失敗'
Assert ($script:writes.Count -eq 0 -and -not(Test-Path $args.StatePath)) '驗證不寫registry或原值快照'
Invoke-SetupUac @args|Out-Null
Assert ($script:values.ConsentPromptBehaviorAdmin -eq 0 -and $script:values.EnableLUA -eq 1 -and $script:values.PromptOnSecureDesktop -eq 1 -and $script:values.ConsentPromptBehaviorUser -eq 3) '僅管理員提示改0保留UAC及其他政策'
$before=[IO.File]::ReadAllText($args.StatePath);Invoke-SetupUac @args|Out-Null
Assert ([IO.File]::ReadAllText($args.StatePath) -ceq $before) '重跑保留第一份原值'
$n=$script:writes.Count;Invoke-SetupUac @args -VerifyOnly -VerificationRunId run1|Out-Null
$r=Get-Content $args.ReportPath -Raw|ConvertFrom-Json
Assert ($script:writes.Count -eq $n -and $r.Success -and $r.VerificationRunId -eq 'run1' -and $r.UserSID -eq 'test-sid') '只讀驗證含本輪身分'
Invoke-SetupUac @args -Restore|Out-Null
Assert ($script:values.ConsentPromptBehaviorAdmin -eq 5) '還原原始DWORD5'
$args.MachineId='machine-b';Reject {Invoke-SetupUac @args} '不同機器不可使用原快照';$args.MachineId='machine-a'
$script:values.EnableLUA=0;$n=$script:writes.Count;Reject {Invoke-SetupUac @args} '已停用UAC不能假稱正常';Assert ($script:writes.Count -eq $n) '不自行修改EnableLUA';$script:values.EnableLUA=1
$script:drop=$true;Reject {Invoke-SetupUac @args} '政策寫入被覆蓋讀回必失敗';$script:drop=$false
$script:kinds.ConsentPromptBehaviorAdmin='String';Reject {Invoke-SetupUac @args -VerifyOnly} '錯誤registry型別拒絕';$script:kinds.ConsentPromptBehaviorAdmin='DWord'
$args.StatePath=Join-Path $dir 'missing_original.json';$script:values.Remove('ConsentPromptBehaviorAdmin');Invoke-SetupUac @args|Out-Null;Invoke-SetupUac @args -Restore|Out-Null
Assert (-not $script:values.ContainsKey('ConsentPromptBehaviorAdmin')) '原值不存在則還原為不存在'
Reject {Invoke-SetupUac @args -VerifyOnly -Restore} '拒絕互斥模式'
[IO.File]::WriteAllText($args.StatePath,'{}');Reject {Invoke-SetupUac @args} '損壞快照拒絕不覆寫'
Assert ([IO.File]::ReadAllText($args.StatePath) -eq '{}') '損壞快照原位保存'
$args.StatePath=Join-Path $dir 'not_created.json'
Reject {Invoke-SetupUac @args -Restore} '沒有首份快照不可猜測還原值'
$args.ReportPath=$args.StatePath
Reject {Invoke-SetupUac @args} '快照與報告不可共用檔案'
$args.ReportPath=Join-Path $dir 'result.json';$script:values.ConsentPromptBehaviorAdmin='5';$script:kinds.ConsentPromptBehaviorAdmin='String'
Reject {Invoke-SetupUac @args} '首次原值型別不正確不覆寫'
Assert (-not(Test-Path $args.StatePath)) '拒絕原值時不產生錯誤快照'
Write-Host 'ALL PASS: UAC TEMP/mock only'