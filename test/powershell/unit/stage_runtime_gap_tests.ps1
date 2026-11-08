#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/gui_stage_library.ps1')
. (Join-Path $root 'modules/updates/update_stage_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$f=$null;try{& $Action|Out-Null}catch{$f=$_};Assert ($f -and $f.Exception -isnot [Management.Automation.ParameterBindingException] -and $f.Exception.Message.Contains($Expected)) ($Name+'; actual='+$f.Exception.Message)}
function Clone($v){$v|ConvertTo-Json -Depth 12|ConvertFrom-Json}
$fixture=Join-Path $env:TEMP ('stage_gaps_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$nativeScope=Get-SetupGuiIdentity
Assert ([bool]$nativeScope.UserSID -and [bool]$nativeScope.Computer) '原生身分僅唯讀觀測，不作為互動案例的帳號假設'
$script:controlledGuiScope=[pscustomobject]@{UserSID='S-1-5-21-1-2-3-1001';Computer='stage-fixture';SessionId=1;CommonDataRoot=$fixture;PowerShell='powershell.exe'}
function Get-StageFixtureIdentity {$script:controlledGuiScope}
Set-Alias -Name Get-SetupGuiIdentity -Value Get-StageFixtureIdentity -Scope Script
$scope=Get-SetupGuiIdentity;$user=$scope.UserSID;$session=$scope.SessionId;$script:aclOverride=@{};$script:copyCorrupt=$false;$script:referenceRace=$false
function NewFileAcl([string]$UserSid){$a=[Security.AccessControl.FileSecurity]::new();$a.SetAccessRuleProtection($true,$false);$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));foreach($id in @('S-1-5-18','S-1-5-32-544')){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','Allow'))};if($UserSid){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($UserSid),'ReadAndExecute','Allow'))};return $a}
function Get-Acl {param($LiteralPath,$ErrorAction) if($script:aclOverride.ContainsKey($LiteralPath)){return $script:aclOverride[$LiteralPath]};$data=if($LiteralPath -match '[\\/]data([\\/]|$)'){$user}else{''};if((Get-Item -LiteralPath $LiteralPath -Force).PSIsContainer){return (New-SetupGuiDirectorySecurity -UserSid $data)}else{return (NewFileAcl $data)}}
function Copy-Item {param($LiteralPath,$Destination,$ErrorAction,[switch]$Force) Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction Stop;if($script:copyCorrupt -and ([IO.Path]::GetFullPath($Destination)).StartsWith($fixture)){[IO.File]::AppendAllText($Destination,'tampered')}}
function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding,$ErrorAction) $result=Microsoft.PowerShell.Management\Get-Content @PSBoundParameters;if($script:referenceRace -and $LiteralPath -like '*desktop_layout.json'){$script:referenceRace=$false;[IO.File]::AppendAllText($LiteralPath,' ')};return $result}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) [pscustomobject]@{SessionId=$session;Name='explorer.exe'}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{ReturnValue=0;Sid=$user}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) [pscustomobject]@{State='Ready'}}
function Register-ScheduledTask {throw 'fixture forbids real task registration'}
Assert-SetupGuiAncestors $fixture;Assert-SetupUpdateAncestors $fixture;Assert $true '原始兩個ancestor迴圈逐層驗證，native GetAcl僅回安全descriptor'
$file=Join-Path $fixture 'plain.txt';[IO.File]::WriteAllText($file,'keep')
Reject {Assert-SetupGuiAncestors $file} '不是目錄' 'GUI ancestor不接受檔案'
Reject {Assert-SetupUpdateAncestors $file} '不是目錄' '更新ancestor不接受檔案'
Reject {Assert-SetupGuiProtectedPath $file -Directory} '類型不符' 'GUI類型驗證不把檔案當資料夾'
Reject {Assert-SetupUpdateProtectedPath $file -Directory} '類型不符' '更新類型驗證不把檔案當資料夾'
Reject {Assert-SetupUpdatePlainPath '\\host\share\worker'} '本機絕對' '更新來源不接受網路路徑'
foreach($kind in @('owner','deny','reader','inherit')){
 $a=New-SetupGuiDirectorySecurity -UserSid $user
 switch($kind){owner{$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-18'))} deny{$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'),'Read','Deny'))} reader{$a.RemoveAccessRuleAll([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($user),'ReadAndExecute','Allow'))} inherit{$a=[Security.AccessControl.DirectorySecurity]::new();$a.SetAccessRuleProtection($true,$false);$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));foreach($id in @('S-1-5-18','S-1-5-32-544')){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','Allow'))};$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($user),'ReadAndExecute','Allow'))}}
 Reject {Assert-SetupGuiAcl -Acl $a -Directory -UserSid $user} $(switch($kind){owner{'擁有者必須'} deny{'非預期'} reader{'讀取權限'} inherit{'繼承保護'}}) ('GUI data拒絕不完整原生ACL '+$kind)
}
foreach($kind in @('inherited','missing','inherit')){$a=New-SetupUpdateDirectorySecurity;switch($kind){inherited{$a.SetAccessRuleProtection($false,$true)} missing{$a.RemoveAccessRuleAll([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-18'),'FullControl','Allow'))} inherit{$a=[Security.AccessControl.DirectorySecurity]::new();$a.SetAccessRuleProtection($true,$false);$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));foreach($id in @('S-1-5-18','S-1-5-32-544')){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','Allow'))}}};Reject {Assert-SetupUpdateAcl $a -Directory} $(switch($kind){inherited{'繼承'} missing{'完整權限'} inherit{'繼承保護'}}) ('更新ACL拒絕 '+$kind)}
Reject {Assert-SetupGuiCaller -UserSid 'invalid' -CallerSession 1 -DesktopSession 1 -Computer fixture} '身分格式' 'GUI拒絕未知呼叫SID'
Reject {Assert-SetupGuiCaller -UserSid $user -CallerSession 1 -DesktopSession 1 -Computer ''} '身分格式' 'GUI拒絕空機器名稱'
function GuiCase([string]$Role,[switch]$VerifyOnly,[string]$IconMode='Load'){
 $base=Join-Path $fixture ([guid]::NewGuid().ToString('N'));$source=Join-Path $base 'source';$common=Join-Path $base 'common';$run=[guid]::NewGuid().ToString('D');$paths=Get-SetupGuiRunPaths $common $Role $run
 foreach($p in @($common,(Split-Path $paths.RoleRoot -Parent),$paths.RoleRoot,$paths.RunRoot,$paths.CodeRoot,$paths.DataRoot)){[void][IO.Directory]::CreateDirectory($p)}
 foreach($name in @(Get-SetupGuiStageFiles $Role)){$to=Join-Path $source $name;[void][IO.Directory]::CreateDirectory((Split-Path $to -Parent));Microsoft.PowerShell.Management\Copy-Item -LiteralPath (Join-Path $root $name) -Destination $to;[void][IO.Directory]::CreateDirectory((Split-Path (Join-Path $paths.CodeRoot $name) -Parent))}
 if($Role -eq 'Icons'){$to=Join-Path $source 'modules/desktop/desktop_layout.json';Microsoft.PowerShell.Management\Copy-Item -LiteralPath (Join-Path $root 'modules/desktop/desktop_layout.json') -Destination $to}
 return @{SourceRoot=$source;CommonDataRoot=$common;Role=$Role;UserSid=$user;CallerSession=0;DesktopSession=$session;Computer=$scope.Computer;RunId=$run;VerifyOnly=[bool]$VerifyOnly;IconMode=$IconMode}
}
$call=GuiCase Explorer;Remove-Item -LiteralPath (Join-Path $call.SourceRoot 'core/gui_worker.ps1');Reject {New-SetupGuiStage @call} '來源缺少檔案' '缺少實際來源不建立可執行stage'
$call=GuiCase Explorer;$paths=Get-SetupGuiRunPaths $call.CommonDataRoot $call.Role $call.RunId;$target=Join-Path $paths.CodeRoot 'core/gui_stage_library.ps1';[IO.File]::WriteAllText($target,'existing');Reject {New-SetupGuiStage @call} '非預期檔案' '原有worker code不覆寫';Assert ([IO.File]::ReadAllText($target) -ceq 'existing') '拒絕後原資料不變'
$call=GuiCase TaskbarFinalize -VerifyOnly;Reject {New-SetupGuiStage @call} '不能使用驗收模式' '收尾工作不可偽裝VerifyOnly'
$call=GuiCase Icons -IconMode Verify;Reject {New-SetupGuiStage @call} '必須使用唯讀' '圖示Verify必須對應唯讀旗標'
$call=GuiCase Icons;$script:referenceRace=$true;Reject {New-SetupGuiStage @call} '讀取期間改變' '實際範本讀取後改動必須拒絕'
$call=GuiCase TaskbarFinalize;$stage=New-SetupGuiStage @call
try{
 $contextPath=Join-Path $stage.CodeRoot 'context.json';$original=[IO.File]::ReadAllText($contextPath);$bad=Clone $stage.Context;$bad.ApplyRunID=[guid]::NewGuid().ToString('D');$bad|ConvertTo-Json -Depth 10|Set-Content $contextPath -Encoding UTF8;Reject {Read-SetupGuiContext $stage.CodeRoot $stage.CommonDataRoot TaskbarFinalize $stage.Context.RunId} '收尾本輪身分' '收尾context不沿用另一輪ID'
 [IO.File]::WriteAllText($contextPath,$original);$bad=Clone $stage.Context;$bad.Files[0].SHA256='not-a-hash';$bad|ConvertTo-Json -Depth 10|Set-Content $contextPath -Encoding UTF8;Reject {Read-SetupGuiContext $stage.CodeRoot $stage.CommonDataRoot TaskbarFinalize $stage.Context.RunId} '雜湊格式' 'context拒絕非SHA檔案紀錄';[IO.File]::WriteAllText($contextPath,$original)
 Reject {Write-SetupGuiResult -DataRoot $stage.DataRoot -Context $stage.Context -Result @{Success=$true} -ExecutionSessionId 0} '互動桌面' '收尾結果必須明列本次桌面'
 Reject {Write-SetupGuiResult -DataRoot $stage.DataRoot -Context $stage.Context -Result @{Role='Other'} -ExecutionSessionId $session} '不可覆寫' '葉節點不得覆寫結果身分欄'
 Write-SetupGuiResult -DataRoot $stage.DataRoot -Context $stage.Context -Result @{Success=$true;Status='Finalized';TemporaryLayoutPolicyRemoved=$true} -ExecutionSessionId $session
 $bad=Clone $stage.Context;$bad.Computer='OTHER';$bad|ConvertTo-Json -Depth 10|Set-Content $contextPath -Encoding UTF8;Reject {Read-SetupGuiResult $stage} '執行期間改變' '本輪context競態變更不可讀回';[IO.File]::WriteAllText($contextPath,$original)
 $wrong=[pscustomobject]@{CodeRoot=$stage.CodeRoot;CommonDataRoot=$stage.CommonDataRoot;DataRoot=$fixture;Context=$stage.Context};Reject {Read-SetupGuiResult $wrong} '固定data' '結果不能從其他資料夾讀取'
 $resultPath=Join-Path $stage.DataRoot 'TaskbarFinalize-Result.json';$saved=Get-Content $resultPath -Raw|ConvertFrom-Json;$saved.OriginalDesktopSession=$session+1;$saved|ConvertTo-Json|Set-Content $resultPath -Encoding UTF8;Reject {Read-SetupGuiResult $stage} '原帳號或原電腦' '收尾結果原桌面不符即拒絕'
 Reject {Invoke-SetupGuiScheduledWorker -Stage $stage -Scope $scope} '已存在' '已有同名排程不接管也不註冊'
}finally{$stage.Lock.Dispose()}
Reject {Assert-SetupGuiTaskbarResult ([pscustomobject]@{Success=$true;Status='Finalized'}) -Finalize} '未明確確認' '收尾必須回報暫時政策已移除'
foreach($field in @('RequiresNextSignIn','Configured','BindingMatches')){$r=[pscustomobject]@{Success=$false;Status='PendingSignIn';RequiresNextSignIn=$true;Configured=$true;BindingMatches=$true};$r.$field=$false;Reject {Assert-SetupGuiTaskbarResult $r -VerifyOnly} '待登入狀態不完整' ('PendingSignIn完整性 '+$field)}
Assert (-not(Test-SetupGuiPendingResult -Role Start -Result ([pscustomobject]@{Success='not-bool'}))) '非布林成功值不能當pending略過'
Reject {Invoke-SetupGuiRole -PackageRoot $fixture -Role TaskbarFinalize} '固定工作' '公用GUI路由不能直接啟動收尾'
Reject {Invoke-SetupGuiRole -PackageRoot $fixture -Role Explorer -VerificationRunId bad} 'ID格式' '非法fresh ID在stage建立前拒絕'
$roots=@(Get-SetupDesktopRoots);Assert ($roots.Count -ge 1) '只讀實際桌面路徑，不改動桌面'
Reject {Export-SetupTaskbarBackup -Path (Join-Path $fixture 'missing-parent/settings.reg')} '匯出失敗' '真reg export寫入不存在TEMP目錄失敗不當成功'
# Update stage: pre-existing TEMP directories avoid any privileged ACL creation.
$updateSource=Join-Path $fixture 'update_source';$common=Join-Path $fixture 'update_common';$updateRoot=Join-Path $common 'windows_setup_update';[void][IO.Directory]::CreateDirectory($updateRoot);[void][IO.Directory]::CreateDirectory((Join-Path $updateRoot 'native'))
foreach($entry in Get-SetupUpdateStageFiles){$to=Join-Path $updateSource $entry.Source;[void][IO.Directory]::CreateDirectory((Split-Path $to -Parent));[IO.File]::WriteAllText($to,'inert '+$entry.Source)}
$updateCall=@{SourceRoot=$updateSource;CommonDataRoot=$common;UserSid=$user;Computer=$scope.Computer}
$removed=Join-Path $updateSource 'update_entry_library.ps1';Remove-Item -LiteralPath $removed;Reject {New-SetupUpdateStage @updateCall} '來源缺少檔案' '更新缺少依賴即拒絕';[IO.File]::WriteAllText($removed,'inert update_entry_library.ps1')
$script:copyCorrupt=$true;Reject {New-SetupUpdateStage @updateCall} '複製前後雜湊' 'TEMP原生copy損壞必須拒絕並釋放lease';$script:copyCorrupt=$false
$update=New-SetupUpdateStage @updateCall
try{$contextPath=Join-Path $update.Path 'context.json';$saved=[IO.File]::ReadAllText($contextPath)
 foreach($field in @('Schema','RunId','UserSID','Computer','Files')){$bad=Clone $update.Context;switch($field){Schema{$bad.Schema=99} RunId{$bad.RunId='bad'} UserSID{$bad.UserSID='bad'} Computer{$bad.Computer=''} Files{$bad.Files=@()}};$bad|ConvertTo-Json -Depth 8|Set-Content $contextPath -Encoding UTF8;Reject {Read-SetupUpdateContext -StageRoot $update.Path} 'context格式' ('更新context拒絕 '+$field)}
 $bad=Clone $update.Context;$bad.Files[0].SHA256='bad';$bad|ConvertTo-Json -Depth 8|Set-Content $contextPath -Encoding UTF8;Reject {Read-SetupUpdateContext -StageRoot $update.Path} '雜湊格式' '更新context hash必須小寫SHA256';[IO.File]::WriteAllText($contextPath,$saved)
 $result=Join-Path $update.Path 'WindowsUpdate-Result.json';@{RunId=$update.Context.RunId;UserSID=$user;Computer=$scope.Computer;Selected=1;SearchResultCode=2;DownloadResultCode=3;ResultCode=2;Updates=@()}|ConvertTo-Json|Set-Content $result -Encoding UTF8;Reject {Read-SetupUpdateResult -CommonDataRoot $common -UserSid $user -Computer $scope.Computer} '下載未完整成功' '安裝成功不能掩蓋下載失敗'
}finally{$update.Lock.Dispose()}
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'no_context'))
Reject {Read-SetupUpdateResult -CommonDataRoot (Join-Path $fixture 'no_context') -UserSid $user -Computer $scope.Computer} '尚未找到' '沒有context不採信舊成功紀錄'
