#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/paths.ps1')
$entry=Resolve-NucPath 'Apply-UACSettings.ps1'
Assert (Test-Path $entry) 'UAC獨立入口可解析'
$command=Get-Command $entry
Assert ($command.Parameters.ContainsKey('Restore') -and $command.Parameters.ContainsKey('VerifyOnly')) '獨立入口具還原與只讀驗證'
. (Join-Path $root 'modules/uac/uac_library.ps1')
function Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction) [pscustomobject]@{MachineGuid='fixture-machine'}}
$script:received=$null
function Invoke-SetupUac {param($StatePath,$ReportPath,$MachineId,$UserSid,[switch]$VerifyOnly,[switch]$Restore,$VerificationRunId) $script:received=$PSBoundParameters}
Invoke-CurrentUserUac -Restore
Assert ($script:received.Restore -and $script:received.MachineId -eq 'fixture-machine' -and $script:received.UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) '目前身分及機器動態取得並傳遞還原'
Assert ($script:received.StatePath -eq (Join-Path $env:ProgramData 'NUC8-Setup/UAC-Original.json')) '原值使用目前機器ProgramData'
Invoke-CurrentUserUac -VerifyOnly -VerificationRunId current
Assert ($script:received.VerifyOnly -and $script:received.VerificationRunId -eq 'current') '本輪驗證ID傳遞'
$tokens=$null;$errors=$null
$config=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/configure_nuc.ps1'),[ref]$tokens,[ref]$errors)
$calls=@($config.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Resolve-NucPath' -and $n.Extent.Text.Contains('apply_uac_settings.ps1')},$true))
Assert ($calls.Count -eq 1) '正式Windows流程呼叫UAC一次'
$verify=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
$fresh=@($verify.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-FreshVerification' -and $n.Extent.Text.Contains('apply_uac_settings.ps1')},$true))
Assert ($fresh.Count -eq 1) '總驗收讀取本輪UAC結果'
$dispatcher=Get-Content (Join-Path $root 'core/run_module.ps1') -Raw
Assert ($dispatcher.Contains("'Apply-UACSettings'") -and $dispatcher.Contains('if($Restore)') -and $dispatcher.Contains(' -Restore')) 'dispatcher保留還原參數跨UAC提權'
function Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction) [pscustomobject]@{MachineGuid=''}}
$failed=$false;try{Invoke-CurrentUserUac}catch{$failed=$true}
Assert $failed '缺少機器識別不繼續套用'
Write-Host 'ALL PASS: UAC routing without host writes'