#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path $env:TEMP ('entry_boundary_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$encoding=New-Object Text.UTF8Encoding($true)
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
try {
 foreach($name in @('configure_nuc.ps1','verify_after_restart.ps1','verify_only.ps1')){
  Copy-Item -LiteralPath (Join-Path $root ('core/'+$name)) -Destination $temp
 }
 [IO.File]::WriteAllText((Join-Path $temp 'entry_os_boundary.ps1'),"function Get-SetupEntryIdentity { return 'fixture-sid' }`nfunction Test-SetupEntryAdministrator { throw 'unexpected admin check' }`nfunction Start-SetupEntryElevated { throw 'unexpected launch' }",$encoding)
 [IO.File]::WriteAllText((Join-Path $temp 'paths.ps1'),"throw 'fixture paths reached'",$encoding)
 foreach($name in @('configure_nuc.ps1','verify_after_restart.ps1','verify_only.ps1')){
  $ErrorActionPreference='Continue'
  $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $temp $name) -ExpectedUserSID fixture-sid 2>&1 | Out-String
  $ErrorActionPreference='Stop'
  Assert ($LASTEXITCODE -ne 0 -and $output.Contains('fixture paths reached')) ($name+' 使用可隔離身分邊界並在受控路徑停止')
 }
} finally {if($temp.StartsWith(([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}}
