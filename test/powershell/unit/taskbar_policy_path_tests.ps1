#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('taskbar_policy_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
$layout=Join-Path $fixture 'TaskbarLayout.xml';$script:registry=@{};$script:writes=0;$script:blockPersonal=$true
function Test-Path {param($Path,$LiteralPath,$PathType) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HK*'){return $script:registry.ContainsKey($p)};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-Item {param($Path,[switch]$Force) if($Path -notlike 'HK*'){throw 'no native registry mutation'};$script:registry[$Path]=@{}}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Name -eq 'TaskbarDa' -and $script:blockPersonal){throw 'fixture protected widget key'};$script:writes++;$script:registry[$Path][$Name]=$Value}
function Get-ItemProperty {param($Path,$ErrorAction) if($script:registry.ContainsKey($Path)){[pscustomobject]$script:registry[$Path]}}
function Export-SetupTaskbarBackup {param($Path) if(-not $Path.StartsWith($fixture)){throw 'backup outside owned fixture'}}
$advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced';$script:registry[$advanced]=@{}
$canonical='HKLM:\SOFTWARE\Policies\Microsoft\Dsh';$wrong='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Dsh'
$script:policyNativeApply=@()
function Invoke-SetupTaskbarNativeAutoHide {param($ModuleRoot,[bool]$Apply) $script:policyNativeApply+=@($Apply);return [uint32]1}
$r=Invoke-SetupTaskbarSettings -OutputRoot $fixture -LayoutPath $layout
Assert ($r.Success -and $r.WidgetsPolicy -eq 0 -and $null -eq $r.TaskbarDa -and $script:registry[$canonical].AllowNewsAndInterests -eq 0 -and -not $script:registry.ContainsKey($wrong)) 'Apply從官方Dsh精確路徑讀回自己剛寫入的政策，個人鍵受保護仍可確認機器政策'
$writes=$script:writes;$r=Invoke-SetupTaskbarSettings -OutputRoot $fixture -LayoutPath $layout -VerifyOnly
Assert ($r.Status -eq 'PendingSignIn' -and $r.Configured -and $script:writes -eq $writes) 'VerifyOnly讀同官方位置，暫時layout待登入與配置錯誤分開且不重寫'
$script:registry['HKCU:\Software\Policies\Microsoft\Windows\Explorer']=@{}
$r=Invoke-SetupTaskbarSettings -OutputRoot $fixture -LayoutPath $layout -VerifyOnly
Assert ($r.Success -and $script:writes -eq $writes) '暫時layout解除後，官方政策讀回可通過且唯讀'
$script:registry.Remove($canonical);$script:registry[$wrong]=@{AllowNewsAndInterests=0}
$r=Invoke-SetupTaskbarSettings -OutputRoot $fixture -LayoutPath $layout -VerifyOnly
Assert (-not $r.Success -and -not $r.Configured) '錯誤Windows子路徑即使是0也不能假冒官方政策'
$script:registry[$canonical]=@{AllowNewsAndInterests=1}
$r=Invoke-SetupTaskbarSettings -OutputRoot $fixture -LayoutPath $layout -VerifyOnly
Assert (-not $r.Success -and $r.WidgetsPolicy -eq 1 -and $script:writes -eq $writes) '官方位置尚未拒絕小工具不可假綠且驗證不覆寫'
Assert ($script:policyNativeApply.Count -eq 5 -and $script:policyNativeApply[0] -eq $true -and @($script:policyNativeApply|Select-Object -Skip 1|Where-Object {$_}).Count -eq 0) '所有政策案例隔離原生AppBar且保留Apply與VerifyOnly模式'
