#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_acl_capability_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$runner=Join-Path $temp 'runner.ps1'
@'
param([string]$Suite,[string]$Context)
$ErrorActionPreference='Stop'
$env:GITHUB_ACTIONS='true'
$env:WINDOWS_SETUP_TEST_CONTEXT=$Context
& $Suite
'@|Set-Content -LiteralPath $runner -Encoding UTF8
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
foreach($context in @('Windows host','Windows container')){
 $log=Join-Path $temp ($context.Replace(' ','_')+'.log')
 $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner (Join-Path $root 'test/powershell/unit/gui_stage_acl_tests.ps1') $context *> $log
 $code=$LASTEXITCODE;$ErrorActionPreference=$old
 $text=Get-Content -LiteralPath $log -Raw
 if($context -eq 'Windows host' -and -not $admin){
  Assert ($code -ne 0 -and $text.Contains('CI_GUI_NATIVE_ADMIN_REQUIRED') -and -not $text.Contains('NATIVE_ADMIN_CREATE_NOT_RUN')) 'GitHub host cannot turn a missing native admin ACL proof into a passed suite'
 }elseif($admin){
  Assert ($code -eq 0 -and $text.Contains('elevated Windows creates code/data with native descriptor and validates actual ACL') -and -not $text.Contains('NATIVE_ADMIN_CREATE_NOT_RUN')) ('elevated '+$context+' executes and reports real TEMP native ACL creation')
 }else{
  Assert ($code -eq 0 -and $text.Contains('NATIVE_ADMIN_CREATE_NOT_RUN')) 'standard-token container keeps an honest explicit native ACL limitation'
 }
}
