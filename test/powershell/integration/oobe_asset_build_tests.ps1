#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$builder=Join-Path $root 'script\package\build_oobe_asset.ps1'
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert (Test-Path -LiteralPath $builder) 'maintainer build script can be reviewed without executing compiler'
. $builder
$temp=Join-Path ([IO.Path]::GetTempPath()) ('oobe_builder_test_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$compiler=Join-Path $temp 'ICD.exe';[IO.File]::WriteAllText($compiler,'mock only')
[IO.File]::WriteAllText((Join-Path $temp 'Microsoft-Desktop-Provisioning.dat'),'mock store')
$script:valid=$false;$script:started=0;$script:badExit=$false
function Get-InitBuildCompilerIdentity {param($Path) [pscustomobject]@{Status='Valid';Subject='CN=Microsoft Windows, O=Microsoft Corporation, C=US';SHA256=$(if($script:valid){'E89F844A375BBEF9D5D98AE3920C68CFB75973FCA0CAC1202354A8AEA36842F0'}else{'0'*64});Version='10.0.26100.9457'}}
function Start-Process {param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$Wait,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
 $script:started++;Assert ($WindowStyle -eq 'Hidden' -and $Wait -and $PassThru) 'compiler invocation is hidden and awaited'
 Assert ($ArgumentList -match '/Build-ProvisioningPackage' -and $ArgumentList -notmatch 'Install|Apply') 'compiler invoked only to build package'
 [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'hide_oobe.ppkg'),'synthetic test output, not a provisioning package')
 return [pscustomobject]@{ExitCode=$(if($script:badExit){1}else{0})}
}
function Get-ProvisioningPackage {param($PackagePath,$LogsDirectoryPath,$ErrorAction) [pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';Version='1.0';Rank=0;OwnerType=5000}}
$out=Join-Path $temp 'output'
$failed=$false;try{Invoke-BuildOobeAsset -CompilerPath $compiler -OutputDirectory $out}catch{$failed=$true}
Assert ($failed -and $script:started -eq 0 -and -not(Test-Path $out)) 'untrusted compiler rejected before writing output'
$script:valid=$true
$result=Invoke-BuildOobeAsset -CompilerPath $compiler -OutputDirectory $out
Assert ($script:started -eq 1 -and $result.PackageName -eq 'windows_setup_hide_oobe') 'mock build produces verifiable provenance without running an executable'
Assert (@(Get-ChildItem $out -File).Count -eq 3) 'output contains own XML synthetic package and provenance only'
$failed=$false;try{Invoke-BuildOobeAsset $compiler $out}catch{$failed=$true}
Assert ($failed -and $script:started -eq 1) 'existing output is never overwritten'
$script:badExit=$true
$badOut=Join-Path $temp 'failed_output'
$failed=$false;try{Invoke-BuildOobeAsset $compiler $badOut}catch{$failed=$true}
Assert ($failed -and -not(Test-Path (Join-Path $badOut 'provenance.json'))) 'compiler failure cannot produce success provenance'
Write-Host ('ALL PASS: '+$script:count+' build orchestration assertions; all processes mocked, no real package generated')
