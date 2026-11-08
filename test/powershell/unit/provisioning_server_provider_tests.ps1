#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('server_provider_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$outcomes=@()
foreach($suite in @('provisioning_runtime_gap_tests.ps1','provisioning_context_gap_tests.ps1')){
 $path=Join-Path $root ('test/powershell/unit/'+$suite);$runner=Join-Path $fixture ($suite+'.runner.ps1');$log=Join-Path $fixture ($suite+'.log');$marker=Join-Path $fixture ($suite+'.native_called')
 $prefix=@'
$ErrorActionPreference='Stop'
function global:Get-ProvisioningPackage {
 [IO.File]::WriteAllText('__MARKER__','native client provider called')
 throw [Management.Automation.CommandNotFoundException]::new('Get-ProvisioningPackage is unavailable in the Server fixture.')
}
'@
 $text=$prefix.Replace('__MARKER__',$marker.Replace("'","''"))+"`r`n& '"+$path.Replace("'","''")+"'`r`n"
 [IO.File]::WriteAllText($runner,$text,[Text.UTF8Encoding]::new($true))
 $oldPreference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> $log;$childCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 $outcomes+=[pscustomobject]@{Suite=$suite;ExitCode=$childCode;NativeReached=(Test-Path -LiteralPath $marker);Log=$log}
}
foreach($outcome in $outcomes){
 $passed=($outcome.ExitCode -eq 0 -and -not $outcome.NativeReached)
 Write-Host ('@@ASSERT@@'+(@{Name=('Server無Client provider仍可隔離執行正式suite '+$outcome.Suite+'；native exit '+$outcome.ExitCode);Passed=$passed}|ConvertTo-Json -Compress))
 if(-not $passed){Write-Host ('PRIVATE_LOG '+$outcome.Log)}
}
if(@($outcomes|Where-Object {$_.ExitCode -ne 0 -or $_.NativeReached}).Count){throw 'Server isolation suites must not delegate to the native client provider.'}
