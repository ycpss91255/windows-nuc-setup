#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'));$module=Join-Path $root 'modules/debloat'
. (Join-Path $module 'debloat_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException]) $Name}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('debloat_readback_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$plan=@(Get-SetupDebloatFeaturePlan -ModuleRoot $module -Build 26200)
Assert ($plan.Count -eq 10 -and @($plan.Checks).Count -eq 57) '所選十項原始REG完整57個DWORD契約均納入，沒有少量抽查代替'
$recall=$plan|Where-Object FeatureId -eq DisableRecall
Assert ($recall.Checks.Count -eq 4 -and @($recall.Checks|Where-Object {$_.Name -eq 'AllowRecallEnablement' -and $_.Expected -eq 0 -and $_.Path -like 'HKLM:*'}).Count -eq 1) 'Recall保留HKCU與HKLM四項原始契約及AllowRecallEnablement=0'
$low=@(Get-SetupDebloatFeaturePlan -ModuleRoot $module -Build 20348)
Assert (@($low|Where-Object Supported).Count -eq 4) 'Server較舊build只核適用四項，六項不冒充已套用'
$native=Invoke-SetupDebloatNative -Arguments @('-NoProfile','-Command',"Write-Output 'safe native fixture';exit 0")
Assert ($native -is [int] -and $native -eq 0) '原生bridge顯示子程序輸出但只回傳單一整數退出碼'
$script:registry=@{};foreach($p in $plan.Checks){$script:registry[$p.Path+'|'+$p.Name]=[int]$p.Expected}
$script:registryMode='good';$script:reads=0
function Get-Item {
 param($LiteralPath,$ErrorAction)
 if($LiteralPath -notmatch '^HK(CU|LM):'){throw 'fixture only allows registry reads'}
 if($script:registryMode -eq 'denied'){throw [UnauthorizedAccessException]::new('fixture denied')}
 $key=[pscustomobject]@{FixturePath=$LiteralPath}
 $key|Add-Member ScriptMethod GetValue {param($Name) $script:reads++;if($script:registryMode -eq 'missing'){return $null};if($script:registryMode -eq 'string'){return '0'};if($script:registryMode -eq 'wrong'){return 99};return $script:registry[$this.FixturePath+'|'+$Name]}
 $key|Add-Member ScriptMethod GetValueKind {param($Name) if($script:registryMode -eq 'kind'){return 'String'};return 'DWord'}
 return $key
}
$ok=Test-SetupDebloatFeatures -ModuleRoot $module -Build 26200
Assert ($ok.Success -and @($ok.Features|Where-Object Status -eq Passed).Count -eq 10 -and $script:reads -eq 57) '真正式reader完整讀回57值且十項Passed'
foreach($mode in @('missing','wrong','kind','string','denied')){
 $script:registryMode=$mode;$r=Test-SetupDebloatFeatures -ModuleRoot $module -Build 26200
 Assert (-not $r.Success -and @($r.Features|Where-Object Status -eq Failed).Count -eq 10) ('缺值錯值錯型別拒絕功能假成功 '+$mode)
}
$script:registryMode='good';$script:reads=0;$r=Test-SetupDebloatFeatures -ModuleRoot $module -Build 20348
Assert ($r.Success -and @($r.Features|Where-Object Status -eq Skipped).Count -eq 6 -and $script:reads -eq 36) '不適用build保留六項Skipped原因且不讀其registry'
function Get-SetupDebloatBuild {26200}
$script:nativeCalls=0;$script:oneDriveCalls=0;$script:appReads=0;$script:appMode='none';$script:nativeCode=0
function Invoke-SetupDebloatNative {param($Arguments) $script:nativeCalls++;Assert ('-DisableRecall' -in $Arguments -and '-DisableBing' -in $Arguments -and '-SkipExplorerRestart' -in $Arguments) '真正編排仍轉送原始feature與不重啟Explorer參數';return $script:nativeCode}
function Invoke-SetupDebloatOneDrive {param($ModuleRoot) $script:oneDriveCalls++}
function Get-AppxPackage {param([switch]$AllUsers) $script:appReads++;if($script:appMode -eq 'installed'){[pscustomobject]@{Name='Microsoft.BingSearch';PackageUserInformation=@([pscustomobject]@{InstallState='Installed'})}}}
function Get-AppxProvisionedPackage {param([switch]$Online) if($script:appMode -eq 'provisioned'){[pscustomobject]@{DisplayName='Microsoft.BingSearch'}}}
$report=Join-Path $fixture 'reports/result.json'
$r=Invoke-SetupDebloat -ModuleRoot $module -VerifyOnly -VerificationRunId fixture-run -ReportPath $report
Assert ($r.Success -and $r.VerifyOnly -and $r.VerificationRunId -eq 'fixture-run' -and $script:nativeCalls -eq 0 -and $script:oneDriveCalls -eq 0) 'VerifyOnly不呼叫native或OneDrive，結果綁本輪動態SID與帳號'
Assert ($r.UserSID -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $r.Computer -ceq $env:COMPUTERNAME -and $r.FeatureChecks.Count -eq 10) '讀回結果含動態身分及十個功能，沒有固定user'
$r=Invoke-SetupDebloat -ModuleRoot $module -ReportPath $report
Assert ($r.Success -and $script:nativeCalls -eq 1 -and $script:oneDriveCalls -eq 1) '套用仍走原生debloat與OneDrive一次，且必須完成讀回'
foreach($case in @('feature','exit','installed','provisioned')){
 $script:registryMode=if($case -eq 'feature'){'wrong'}else{'good'};$script:nativeCode=if($case -eq 'exit'){7}else{0};$script:appMode=$case
 Reject {Invoke-SetupDebloat -ModuleRoot $module -ReportPath $report} ('native退出零仍拒絕實際未完成 '+$case)
 $saved=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
 Assert (-not $saved.Success -and $saved.FeatureChecks.Count -eq 10) ('失敗JSON仍保留實際功能讀回 '+$case)
}
$data=Join-Path $fixture 'contract';[void][IO.Directory]::CreateDirectory((Join-Path $data 'win11debloat/Config'));[void][IO.Directory]::CreateDirectory((Join-Path $data 'win11debloat/Regfiles'))
$profilePath=Join-Path $data 'debloat_profile.json';$catalogPath=Join-Path $data 'win11debloat/Config/Features.json';$reg=Join-Path $data 'win11debloat/Regfiles/test.reg'
foreach($case in @('empty','duplicate','unknown','duplicate_catalog','unsafe','unknown_reg','no_values','maximum')){
 $ids=if($case -eq 'empty'){@()}elseif($case -eq 'duplicate'){@('Test','Test')}else{@('Test')}
 @{Features=@($ids)}|ConvertTo-Json|Set-Content -LiteralPath $profilePath -Encoding UTF8
 $f=@{FeatureId=$(if($case -eq 'unknown'){'Other'}else{'Test'});RegistryKey=$(if($case -eq 'unsafe'){'../test.reg'}else{'test.reg'});MinVersion=1;MaxVersion=200}
 @{Features=@($f)+@($(if($case -eq 'duplicate_catalog'){$f}))|Where-Object {$_}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $catalogPath -Encoding UTF8
 $line=if($case -eq 'unknown_reg'){'"Value"="string"'}elseif($case -eq 'no_values'){'; no values'}else{'"Value"=dword:00000000'}
 [IO.File]::WriteAllText($reg,('Windows Registry Editor Version 5.00'+"`r`n[HKEY_CURRENT_USER\Software\Fixture]`r`n"+$line),[Text.Encoding]::Unicode)
 if($case -eq 'maximum'){$p=@(Get-SetupDebloatFeaturePlan -ModuleRoot $data -Build 201);Assert (-not $p[0].Supported) '上游MaxBuild同樣遵守不冒充套用'}
 else{Reject {Get-SetupDebloatFeaturePlan -ModuleRoot $data -Build 100} ('未知或損壞契約必須明確拒絕 '+$case)}
}
