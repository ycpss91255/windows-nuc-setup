#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('container_identity_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$runner=Join-Path $fixture 'runner.ps1';$log=Join-Path $fixture 'suite.log'
$prefix=@'
$ErrorActionPreference='Stop'
function global:Get-ContainerIdentityBoundary {
 [pscustomobject]@{UserSID='S-1-5-93-2-2';Computer='container-fixture';SessionId=1;CommonDataRoot=$env:TEMP;PowerShell='powershell.exe'}
}
Set-Alias -Name Get-SetupGuiIdentity -Value Get-ContainerIdentityBoundary -Scope Global
'@
$path=Join-Path $root 'test/powershell/unit/stage_runtime_gap_tests.ps1'
[IO.File]::WriteAllText($runner,($prefix+"`r`n& '"+$path.Replace("'","''")+"'`r`n"),[Text.UTF8Encoding]::new($true))
$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
Write-Host ('@@ASSERT@@'+(@{Name=('Container SID原生邊界下，正式stage隔離suite應通過；native exit '+$code);Passed=($code -eq 0)}|ConvertTo-Json -Compress))
if($code -ne 0){Write-Host ('PRIVATE_LOG '+$log);throw 'Interactive fixture must remain independent from the native container identity.'}
