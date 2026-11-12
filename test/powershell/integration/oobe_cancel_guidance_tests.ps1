#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/provisioning_library.ps1')
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAIL: '+$Name)};[Console]::WriteLine('PASS: '+$Name)}
$stage=Join-Path $env:TEMP ('init_guidance_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $stage|Out-Null
$script:messages=@();$script:accountCalls=0;$script:phase='AwaitingConsent'
function Write-Host {param($Object,$ForegroundColor) $script:messages+=@([string]$Object)}
function Get-InitProvisioningContext { @{Sid='fixture';Build=1;ProductType=1;Is64Bit=$true;IsWinPE=$false;OobeApiSucceeded=$true;OobeComplete=$false;MachineGuid='fixture';ComputerName='fixture'} }
function Test-InitProvisioningContext {$true}
function Assert-InitProvisioningAsset { @{PackageSHA256=('d'*64)} }
function Read-InitProvisioningState { [pscustomobject]@{Phase=$script:phase;TargetUserName='existing'} }
function New-InitPublicLauncher { 'fixture_resume.cmd' }
function New-InitProvisioningAccount { $script:accountCalls++ }
function Invoke-InitProvisioningApply {param($State,$StatePath,$AssetRoot,$Confirm) $State.Phase=$script:phase }
Invoke-InitOobeFlow $root $stage
$cancel=$script:messages -join "`n"
Assert ($script:accountCalls -eq 0) '取消續跑保留既有帳號'
Assert ($cancel -match 'OOBE' -and $cancel -match 'Shift\s*\+\s*F10' -and $cancel -match 'init\.cmd' -and $cancel -notmatch '取消或中斷時的恢復入口（正常登入後直接執行 windows\.cmd）') '取消或中斷提示應指回 OOBE Init'
$script:messages=@();$script:phase='AwaitingLogon'
Invoke-InitOobeFlow $root $stage
$success=$script:messages -join "`n"
Assert ($success -match '登入' -and $success -match 'windows\.cmd') '完成套用後指引登入並執行 Windows'
$readme=Get-Content -LiteralPath (Join-Path $root 'readme.md') -Raw -Encoding UTF8
Assert ($readme -match '(?s)取消[^\r\n]*OOBE[^\r\n]*Shift\+F10[^\r\n]*init\.cmd' -and $readme -match '(?s)(完成|成功)[^\r\n]*登入[^\r\n]*windows\.cmd') 'README 區分取消續跑與完成登入'
[Console]::WriteLine('ALL PASS: safe mocked OOBE guidance')
