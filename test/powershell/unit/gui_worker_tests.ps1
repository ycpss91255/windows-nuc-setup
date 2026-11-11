#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
. (Join-Path $root 'core/gui_stage_library.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_worker_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$run=[guid]::NewGuid().ToString('D');$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role Explorer -RunId $run
$module=Join-Path $paths.CodeRoot 'modules/explorer';[void][IO.Directory]::CreateDirectory($module);[void][IO.Directory]::CreateDirectory($paths.DataRoot)
$fixture=@'
function Invoke-SetupExplorerSettings {param($ModuleRoot,[switch]$VerifyOnly)
 $script:leafCalls++
 if($script:leafThrows){throw 'leaf fixture failure'}
 [pscustomobject]@{Success=(-not $script:leafFails);Error='leaf rejected current state';CheckedAt='fixture';ShellShowsHidden=$true}
}
'@
[IO.File]::WriteAllText((Join-Path $module 'explorer_settings_library.ps1'),$fixture)
$script:context=[pscustomobject]@{Schema=1;Role='Explorer';RunId=$run;Computer='fixture';CallerSID='S-1-5-21-1-2-3-1001';CallerSession=0;UserSID='S-1-5-21-1-2-3-1001';DesktopSession=4;VerifyOnly=$true}
$script:scope=[pscustomobject]@{CommonDataRoot=$temp;UserSID=$script:context.UserSID;SessionId=4;Computer='fixture'}
$script:leafCalls=0;$script:leafThrows=$false;$script:leafFails=$false
function Read-SetupGuiContext {param($CodeRoot,$CommonDataRoot,$Role,$RunId) if($CodeRoot -ne $paths.CodeRoot -or $CommonDataRoot -ne $temp -or $Role -cne 'Explorer' -or $RunId -cne $run){throw 'unexpected context lookup'};$script:context}
function Get-SetupGuiIdentity {$script:scope}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Test-Path -LiteralPath $Path)){throw 'fixture path invalid'}}
$call=@{CodeRoot=$paths.CodeRoot;Role='Explorer';RunId=$run}
Invoke-SetupGuiWorker @call|Out-Null
$resultPath=Join-Path $paths.DataRoot 'Explorer-Verification.json';$result=[IO.File]::ReadAllText($resultPath)|ConvertFrom-Json
Assert ($script:leafCalls -eq 1 -and $result.Success -and $result.RunId -ceq $run -and $result.SessionId -eq 4 -and $result.UserSID -ceq $script:scope.UserSID -and $result.VerifyOnly) 'fixed worker executes bound leaf and publishes scoped protected report'
$script:leafThrows=$true;Reject {Invoke-SetupGuiWorker @call} 'leaf fixture failure' 'worker preserves leaf native failure'
$result=[IO.File]::ReadAllText($resultPath)|ConvertFrom-Json
Assert (-not $result.Success -and $result.Error -eq 'leaf fixture failure' -and $result.RunId -ceq $run) 'leaf exception publishes only this run failed result'
$script:leafThrows=$false;$script:leafFails=$true;Reject {Invoke-SetupGuiWorker @call} 'leaf rejected current state' 'false leaf state cannot report successful worker';$script:leafFails=$false
$held=Open-SetupGuiExecutionLock -Paths $paths
try{$before=$script:leafCalls;Reject {Invoke-SetupGuiWorker @call} '已有執行程序' 'second worker cannot concurrently alter same GUI role';Assert ($script:leafCalls -eq $before) 'execution lock rejection occurs before any UI leaf call'}finally{$held.Dispose()}
Invoke-SetupGuiWorker @call|Out-Null;Assert (([IO.File]::ReadAllText($resultPath)|ConvertFrom-Json).Success) 'failed runs release execution lock for next invocation'
$script:scope.SessionId=0;$before=$script:leafCalls;$beforeResult=[IO.File]::ReadAllText($resultPath)
Reject {Invoke-SetupGuiWorker @call} '身分' 'worker refuses session-zero before loading UI library'
Assert ($script:leafCalls -eq $before -and [IO.File]::ReadAllText($resultPath) -ceq $beforeResult) 'wrong worker scope cannot overwrite trusted previous report'
Write-Host ('ALL PASS: '+$script:count+' worker control assertions; fixed inert leaf and TEMP only')
