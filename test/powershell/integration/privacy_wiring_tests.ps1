#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/paths.ps1')
$entry=Resolve-NucPath 'Apply-PrivacySettings.ps1'
Assert (Test-Path -LiteralPath $entry) '獨立隱私入口可由既有dispatcher解析'
$command=Get-Command $entry
Assert ($command.Parameters.ContainsKey('VerifyOnly')) '隱私入口公開VerifyOnly'
$tokens=$null;$errors=$null
$dispatcher=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/run_module.ps1'),[ref]$tokens,[ref]$errors)
$allowed=$dispatcher.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$allowed'},$true)
$values=@($allowed.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object Value)
Assert ('Apply-PrivacySettings' -in $values) '通用dispatcher白名單包含隱私模組並沿用SID/UAC防護'
$debloat=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/debloat/apply_debloat.ps1'),[ref]$tokens,[ref]$errors)
$calls=@($debloat.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-CurrentUserPrivacy'},$true))
Assert ($calls.Count -eq 1) '既有Debloat階段呼叫同一隱私功能一次'
. (Join-Path $root 'modules/privacy/privacy_library.ps1')
$script:received=$null
function Get-ItemProperty {param($LiteralPath,$ErrorAction) [pscustomobject]@{EditionID='ProfessionalWorkstation'}}
function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{ProductType=1}}
function Invoke-SetupPrivacy {param($EditionId,$ProductType,$ReportPath,$UserSid,$Computer,$VerificationRunId,[switch]$VerifyOnly) $script:received=@{Edition=$EditionId;ProductType=$ProductType;Report=$ReportPath;SID=$UserSid;Verify=[bool]$VerifyOnly;Run=$VerificationRunId}}
$out=Join-Path ([IO.Path]::GetTempPath()) ('privacy_route_'+[guid]::NewGuid().ToString('N')+'.json')
Invoke-CurrentUserPrivacy -ReportPath $out -VerifyOnly -VerificationRunId fixture
Assert ($script:received.Edition -eq 'ProfessionalWorkstation' -and $script:received.ProductType -eq 1) '目前系統版本由只讀邊界動態取得'
Assert ($script:received.SID -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) '使用當前帳號SID'
Assert ($script:received.Report -eq $out -and $script:received.Verify -and $script:received.Run -eq 'fixture') 'VerifyOnly及結果位置正確傳遞'
Write-Host 'ALL PASS: privacy routing tests; no host changes'
