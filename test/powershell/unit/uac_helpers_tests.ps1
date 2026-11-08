#Requires -Version 5.1
param([switch]$DiagnosticProbe)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name,[string]$Expected,[int]$ExpectedWrites=0){
 if(-not $Expected){throw '每個負例都必須指定產品預期錯誤。'}
 $beforeWrites=$script:writes.Count;$statePath=$call.StatePath;$beforeState=if(Test-Path $statePath){[IO.File]::ReadAllText($statePath)}else{$null}
 $failure=$null;try{& $Action|Out-Null}catch{$failure=$_}
 Assert ($null -ne $failure -and -not ($failure.Exception -is [Management.Automation.ParameterBindingException])) ($Name+'：確實進入原函式')
 Assert ($failure.Exception.Message.Contains($Expected)) ($Name+'：符合預期錯誤；預期='+$Expected+'；實際='+$failure.Exception.Message)
 Assert ($script:writes.Count -eq $beforeWrites+$ExpectedWrites) ($Name+'：符合registry寫入次數')
 $afterState=if(Test-Path $statePath){[IO.File]::ReadAllText($statePath)}else{$null}
 Assert ($beforeState -ceq $afterState) ($Name+'：保留首份原值狀態')
}
$lib=Join-Path $root 'modules/uac/uac_library.ps1'
Assert (Test-Path $lib) 'UAC有無副作用具名函式來源'
. $lib
$script:values=@{EnableLUA=1;ConsentPromptBehaviorAdmin=5;PromptOnSecureDesktop=1;ConsentPromptBehaviorUser=3}
$script:kinds=@{EnableLUA='DWord';ConsentPromptBehaviorAdmin='DWord'};$script:writes=@();$script:drop=$false
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -like 'HKLM:*'){$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) if(-not $script:values.ContainsKey($name)){throw 'missing'};$script:kinds[$name]};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) if($Name -ne 'ConsentPromptBehaviorAdmin'){throw '禁止修改其他政策'};$script:writes+=@($Name);if(-not $script:drop){$script:values[$Name]=$Value;$script:kinds[$Name]=$PropertyType}}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($Name -ne 'ConsentPromptBehaviorAdmin'){throw '禁止移除其他政策'};$script:writes+=@($Name);$script:values.Remove($Name);$script:kinds.Remove($Name)}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('uac_test_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$call=@{StatePath=(Join-Path $dir 'original.json');ReportPath=(Join-Path $dir 'result.json');MachineId='machine-a';UserSid='test-sid';Computer='test-pc'}
if($DiagnosticProbe){Reject {throw 'fixture actual message'} '診斷probe' 'fixture expected message';throw 'probe unexpectedly passed'}
Reject {Invoke-SetupUac @call -VerifyOnly} '未設定時驗證必失敗' 'UAC政策讀回'
Assert ($script:writes.Count -eq 0 -and -not(Test-Path $call.StatePath)) '驗證不寫registry或原值快照'
Invoke-SetupUac @call|Out-Null
Assert ($script:values.ConsentPromptBehaviorAdmin -eq 0 -and $script:values.EnableLUA -eq 1 -and $script:values.PromptOnSecureDesktop -eq 1 -and $script:values.ConsentPromptBehaviorUser -eq 3) '僅管理員提示改0保留UAC及其他政策'
$before=[IO.File]::ReadAllText($call.StatePath);Invoke-SetupUac @call|Out-Null
Assert ([IO.File]::ReadAllText($call.StatePath) -ceq $before) '重跑保留第一份原值'
$n=$script:writes.Count;Invoke-SetupUac @call -VerifyOnly -VerificationRunId run1|Out-Null
$r=Get-Content $call.ReportPath -Raw|ConvertFrom-Json
Assert ($script:writes.Count -eq $n -and $r.Success -and $r.VerificationRunId -eq 'run1' -and $r.UserSID -eq 'test-sid') '只讀驗證含本輪身分'
Invoke-SetupUac @call -Restore|Out-Null
Assert ($script:values.ConsentPromptBehaviorAdmin -eq 5) '還原原始DWORD5'
$call.MachineId='machine-b';Reject {Invoke-SetupUac @call} '不同機器不可使用原快照' 'UAC原值快照';$call.MachineId='machine-a'
$script:values.EnableLUA=0;$n=$script:writes.Count;Reject {Invoke-SetupUac @call} '已停用UAC不能假稱正常' '目前EnableLUA';Assert ($script:writes.Count -eq $n) '不自行修改EnableLUA';$script:values.EnableLUA=1
$script:drop=$true;Reject {Invoke-SetupUac @call} '政策寫入被覆蓋讀回必失敗' 'UAC政策讀回' 1;$script:drop=$false
$script:kinds.ConsentPromptBehaviorAdmin='String';
Reject {Invoke-SetupUac @call -VerifyOnly} '錯誤registry型別拒絕' 'UAC政策讀回';$script:kinds.ConsentPromptBehaviorAdmin='DWord'
$call.StatePath=Join-Path $dir 'missing_original.json';$script:values.Remove('ConsentPromptBehaviorAdmin');Invoke-SetupUac @call|Out-Null;Invoke-SetupUac @call -Restore|Out-Null
Assert (-not $script:values.ContainsKey('ConsentPromptBehaviorAdmin')) '原值不存在則還原為不存在'
Reject {Invoke-SetupUac @call -VerifyOnly -Restore} '拒絕互斥模式' 'VerifyOnly與Restore'
[IO.File]::WriteAllText($call.StatePath,'{}');Reject {Invoke-SetupUac @call} '損壞快照拒絕不覆寫' 'UAC原值快照'
Assert ([IO.File]::ReadAllText($call.StatePath) -eq '{}') '損壞快照原位保存'
$call.StatePath=Join-Path $dir 'not_created.json'
Reject {Invoke-SetupUac @call -Restore} '沒有首份快照不可猜測還原值' '沒有這臺電腦'
$call.ReportPath=$call.StatePath
Reject {Invoke-SetupUac @call} '快照與報告不可共用檔案' '原值快照與結果'
$call.ReportPath=Join-Path $dir 'result.json';$script:values.ConsentPromptBehaviorAdmin='5';$script:kinds.ConsentPromptBehaviorAdmin='String'
Reject {Invoke-SetupUac @call} '首次原值型別不正確不覆寫' '原政策不是有效DWORD'
Assert (-not(Test-Path $call.StatePath)) '拒絕原值時不產生錯誤快照'
$hidden=Join-Path $dir 'hidden_parent';$hiddenInfo=[IO.Directory]::CreateDirectory($hidden);$hiddenInfo.Attributes=$hiddenInfo.Attributes -bor [IO.FileAttributes]::Hidden
$call.StatePath=Join-Path $hidden 'state.json';$call.ReportPath=Join-Path $hidden 'result.json';$script:values.ConsentPromptBehaviorAdmin=0;$script:kinds.ConsentPromptBehaviorAdmin='DWord'
$beforeWrites=$script:writes.Count
Invoke-SetupUac @call -VerifyOnly|Out-Null
Assert ($script:writes.Count -eq $beforeWrites -and -not(Test-Path $call.StatePath)) '真正Hidden祖先可讀且VerifyOnly不寫registry或原值快照'
$r=Get-Content -LiteralPath $call.ReportPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert $r.Success 'Hidden祖先不被誤判遺失而阻擋UAC驗證'
$link=Join-Path $dir 'reparse_parent';$null=New-Item -ItemType Junction -Path $link -Target $hidden
$call.StatePath=Join-Path $link 'state.json'
Reject {Invoke-SetupUac @call -VerifyOnly} 'Force讀隱藏目錄仍拒絕重新解析點' '重新解析'
Write-Host 'ALL PASS: UAC TEMP/mock only'