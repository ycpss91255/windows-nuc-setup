#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
. (Join-Path $root 'core/gui_stage_library.ps1')
$manifest=@(Get-SetupGuiStageFiles -Role Explorer)
Assert ($manifest.Count -eq 4 -and @($manifest|Where-Object {$_ -match 'updates|\.cmd$'}).Count -eq 0) 'GUI Explorer stage has one exact self-contained code manifest'
Reject {Get-SetupGuiStageFiles -Role Unknown} '角色' 'unknown GUI role cannot request arbitrary executable source'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_stage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$source=Join-Path $temp 'source';$common=Join-Path $temp 'common';[void][IO.Directory]::CreateDirectory($common)
foreach($name in $manifest){$path=Join-Path $source $name;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllText($path,'inert fixture '+$name)}
$script:guardCalls=@();$script:ancestorCalls=0;$script:corruptCopy=$false
function Assert-SetupGuiAncestors {param($CommonDataRoot) if(-not $CommonDataRoot.StartsWith($temp)){throw 'fixture outside TEMP'};$script:ancestorCalls++}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'fixture outside TEMP'};[void][IO.Directory]::CreateDirectory($Path);$script:guardCalls+=@([pscustomobject]@{Path=$Path;UserSid=$UserSid;Directory=$true})}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Test-Path -LiteralPath $Path)){throw 'fixture path absent/outside TEMP'};$script:guardCalls+=@([pscustomobject]@{Path=$Path;UserSid=$UserSid;Directory=[bool]$Directory})}
function Copy-Item {param($LiteralPath,$Destination,[switch]$Force,$ErrorAction) Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters;if($script:corruptCopy){[IO.File]::AppendAllText($Destination,'corrupted')}}
$call=@{SourceRoot=$source;CommonDataRoot=$common;Role='Explorer';UserSid='S-1-5-21-1-2-3-1001';CallerSession=0;DesktopSession=3;Computer='fixture-computer';VerifyOnly=$true}
$stage=New-SetupGuiStage @call
try{
 Assert ($stage.Context.Role -ceq 'Explorer' -and $stage.Context.UserSID -ceq $call.UserSid -and $stage.Context.CallerSID -ceq $call.UserSid -and $stage.Context.CallerSession -eq 0 -and $stage.Context.DesktopSession -eq 3 -and $stage.Context.VerifyOnly -is [bool] -and $stage.Context.VerifyOnly) 'GUI context binds caller SID session desktop computer and verification mode'
 Assert ($stage.CodeRoot -ceq (Join-Path (Join-Path (Join-Path $common 'windows_setup_gui/explorer') $stage.Context.RunId) 'code') -and $stage.DataRoot -ceq (Join-Path (Split-Path $stage.CodeRoot) 'data')) 'GUI code and report roots are derived from fixed role and canonical run ID'
 Assert (@($script:guardCalls|Where-Object {$_.Path -eq $stage.DataRoot -and $_.UserSid -ceq $call.UserSid}).Count -gt 0 -and @($script:guardCalls|Where-Object {$_.Path.StartsWith($stage.CodeRoot) -and $_.UserSid}).Count -eq 0) 'only report data is user-readable; staged executable code never grants original user access'
 $context=Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $common -Role Explorer -RunId $stage.Context.RunId
 Assert ($context.Files.Count -eq 4 -and $script:ancestorCalls -ge 2) 'every source digest and ancestor is rechecked on context read'
 Reject {New-SetupGuiStage @call} '另一個程序' 'role lock prevents concurrent source replacement'
 $file=Join-Path $stage.CodeRoot $manifest[0];$original=[IO.File]::ReadAllBytes($file);[IO.File]::AppendAllText($file,'tamper')
 Reject {Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $common -Role Explorer -RunId $stage.Context.RunId} '雜湊' 'modified staged executable cannot be loaded'
 [IO.File]::WriteAllBytes($file,$original)
 $scope=[pscustomobject]@{UserSID=$call.UserSid;SessionId=3;Computer=$call.Computer}
 Assert-SetupGuiWorkerScope -Context $context -Scope $scope
 Assert $true 'worker accepts only the bound active desktop scope'
 foreach($field in @('UserSID','SessionId','Computer')){$wrong=[pscustomobject]@{UserSID=$call.UserSid;SessionId=3;Computer=$call.Computer};if($field -eq 'SessionId'){$wrong.SessionId=0}else{$wrong.$field='wrong'};Reject {Assert-SetupGuiWorkerScope -Context $context -Scope $wrong} '身分' ('worker rejects wrong '+$field)}
 $originalContext=[IO.File]::ReadAllText((Join-Path $stage.CodeRoot 'context.json'));$invalid=$originalContext|ConvertFrom-Json;$invalid.Files+=@($invalid.Files[0]);[IO.File]::WriteAllText((Join-Path $stage.CodeRoot 'context.json'),($invalid|ConvertTo-Json -Depth 6))
 Reject {Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $common -Role Explorer -RunId $stage.Context.RunId} '清單' 'duplicate source entry cannot satisfy fixed manifest'
 [IO.File]::WriteAllText((Join-Path $stage.CodeRoot 'context.json'),$originalContext)
 Write-SetupGuiResult -DataRoot $stage.DataRoot -Context $context -Result @{Success=$true;Error=$null;ShellShowsHidden=$true}
 $result=Read-SetupGuiResult -Stage $stage
 Assert ($result.Success -and $result.RunId -ceq $context.RunId -and $result.UserSID -ceq $call.UserSid -and $result.SessionId -eq 3 -and $result.VerifyOnly) 'result is read only from protected current-run data and carries exact scope'
 $resultPath=Join-Path $stage.DataRoot 'Explorer-Verification.json';$result.RunId=[guid]::NewGuid().ToString();[IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json))
 Reject {Read-SetupGuiResult -Stage $stage} '身分' 'stale result from another run cannot pass'
}finally{$stage.Lock.Dispose()}
$call.DesktopSession=0;Reject {New-SetupGuiStage @call} '桌面' 'session zero cannot be selected as desktop';$call.DesktopSession=3
$call.CallerSession=4;Reject {New-SetupGuiStage @call} '桌面' 'unrelated interactive caller session cannot target another desktop';$call.CallerSession=0
$script:corruptCopy=$true;Reject {New-SetupGuiStage @call} '雜湊' 'copy corruption aborts protected stage before task launch';$script:corruptCopy=$false
$again=New-SetupGuiStage @call;$again.Lock.Dispose();Assert ($again.Context.RunId -cne $stage.Context.RunId) 'a failed stage releases lock and a new invocation receives a fresh run ID'
Write-Host ('ALL PASS: '+$script:count+' GUI stage control assertions; TEMP file IO with explicit ACL boundaries mocked')