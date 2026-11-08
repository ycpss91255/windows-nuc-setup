#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'core/paths.ps1')
$fixture=Join-Path $env:TEMP ('windows_setup_names_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'core'),(Join-Path $fixture 'modules/debloat'),(Join-Path $fixture 'reports')|Out-Null
$script:NucPackageRoot=$fixture
[IO.File]::WriteAllText((Join-Path $fixture 'core/configuration_library.ps1'),"File='apply_debloat.ps1'")
$marker=Join-Path $fixture 'invoked.txt'
[IO.File]::WriteAllText((Join-Path $fixture 'modules/debloat/apply_debloat.ps1'),"[IO.File]::WriteAllText('$marker','called')")
Assert ((Resolve-NucPath 'Apply-Debloat.ps1') -eq (Join-Path $fixture 'modules/debloat/apply_debloat.ps1')) 'legacy source alias resolves to new physical filename'
Assert ((Resolve-NucModuleName 'Apply-Debloat.ps1') -ceq 'apply_debloat.ps1') 'legacy failed module id normalizes before allowlist'
Assert ((Resolve-NucPath 'Setup-Result.json') -eq (Join-Path $fixture 'reports/Setup-Result.json')) 'existing per-machine result filename remains compatible'
# Execute the actual restart retry block with a legacy failure record and harmless module.
$source=[IO.File]::ReadAllText((Join-Path $root 'core/verify_after_restart.ps1'))
$start=$source.IndexOf("`$resultPath=Resolve-NucPath")
$end=$source.IndexOf("Write-Host '重新掃描更新",$start)
$retry=[scriptblock]::Create($source.Substring($start,$end-$start))
function Get-SetupModuleDecision {param($Module,$Hardware);[pscustomobject]@{Applicable=$true;Reason='fixture'}}
$hardware=@{};$DriverPackagePath='';$errors=@();$remaining=@()
$record=[pscustomobject]@{Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;FailedModules=@('Apply-Debloat.ps1')}
$record|ConvertTo-Json|Set-Content (Join-Path $fixture 'reports/Setup-Result.json') -Encoding UTF8
. $retry
Assert ((Test-Path $marker) -and -not $errors.Count) 'actual continuation retries legacy module id using renamed script'
[IO.File]::WriteAllText($marker,'unchanged')
$record.UserSID='different-owner';$record|ConvertTo-Json|Set-Content (Join-Path $fixture 'reports/Setup-Result.json') -Encoding UTF8
. $retry
Assert ([IO.File]::ReadAllText($marker) -eq 'unchanged') 'legacy alias does not bypass owner SID check'
$record.UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$record.FailedModules=@('unregistered.ps1');$record|ConvertTo-Json|Set-Content (Join-Path $fixture 'reports/Setup-Result.json') -Encoding UTF8
$rejected=$false;try{. $retry}catch{$rejected=$true}
Assert $rejected 'unknown legacy module remains rejected'
