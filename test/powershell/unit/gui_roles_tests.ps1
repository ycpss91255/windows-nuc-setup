#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_roles_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
foreach($role in @('Display','Theme')){
 $files=@(Get-SetupGuiStageFiles $role)
 $lower=$role.ToLowerInvariant()
 Assert ($files.Count -eq 4 -and $files[0] -ceq 'core/gui_stage_library.ps1' -and $files[1] -ceq 'core/gui_worker.ps1' -and $files[2] -ceq ('modules/'+$lower+'/'+$lower+'_settings_library.ps1') -and $files[3] -ceq ('modules/'+$lower+'/native/'+$lower+'.cs')) ('approved '+$role+' stage contains only its fixed self-contained leaf and native source')
 foreach($file in $files){Assert (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf) ('approved role source exists: '+$file)}
 $context=[pscustomobject]@{Role=$role;VerifyOnly=$true}
 Assert ((Get-SetupGuiResultName $context) -ceq ($role+'-Verification.json')) 'role verification result has its fixed distinct name'
 $context.VerifyOnly=$false
 Assert ((Get-SetupGuiResultName $context) -ceq ($role+'-Result.json')) 'role application result has its fixed distinct name'
}
$bad='';try{Get-SetupGuiStageFiles 'Unapproved'|Out-Null}catch{$bad=$_.Exception.Message}
Assert ($bad.Contains('尚未核准')) 'adding approved leaves does not permit arbitrary role script execution'
$script:scope=[pscustomobject]@{CommonDataRoot=$temp;UserSID='S-1-5-21-1-2-3-1001';SessionId=4;Computer='fixture'}
function Get-SetupGuiIdentity {$script:scope}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Test-Path -LiteralPath $Path)){throw 'outside fixture protected paths'}}
function Read-SetupGuiContext {param($CodeRoot,$CommonDataRoot,$Role,$RunId) if($CodeRoot -ne $script:paths.CodeRoot -or $CommonDataRoot -ne $temp -or $Role -cne $script:context.Role -or $RunId -cne $script:context.RunId){throw 'wrong scoped role lookup'};$script:context}
foreach($role in @('Display','Theme')){
 $run=[guid]::NewGuid().ToString('D');$script:paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role $role -RunId $run
 $lower=$role.ToLowerInvariant();$module=Join-Path $script:paths.CodeRoot ('modules/'+$lower);[void][IO.Directory]::CreateDirectory($module);[void][IO.Directory]::CreateDirectory($script:paths.DataRoot)
 $leaf='function Invoke-Setup'+$role+'Settings {param($ModuleRoot,[switch]$VerifyOnly); if($ModuleRoot -notlike ''*modules\'+$lower+'''){throw ''wrong role directory''}; [pscustomobject]@{Success=$true;CheckedRole='''+$role+''';ReadOnly=[bool]$VerifyOnly}}'
 [IO.File]::WriteAllText((Join-Path $module ($lower+'_settings_library.ps1')),$leaf,[Text.UTF8Encoding]::new($true))
 $script:context=[pscustomobject]@{Schema=1;Role=$role;RunId=$run;Computer='fixture';CallerSID=$script:scope.UserSID;CallerSession=0;UserSID=$script:scope.UserSID;DesktopSession=4;VerifyOnly=$true}
 $result=Invoke-SetupGuiWorker -CodeRoot $script:paths.CodeRoot -Role $role -RunId $run
 $published=Get-Content -LiteralPath (Join-Path $script:paths.DataRoot ($role+'-Verification.json')) -Raw|ConvertFrom-Json
 Assert ($result.CheckedRole -ceq $role -and $result.ReadOnly -and $published.Success -and $published.Role -ceq $role -and $published.RunId -ceq $run) ('fixed worker dispatches '+$role+' only after bound context validation and publishes protected scoped result')
}
