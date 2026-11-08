#Requires -Version 5.1
$ErrorActionPreference='Stop'
$init=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init'))
. (Join-Path $init 'oobe_library.ps1')
. (Join-Path $init 'provisioning_library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Save-InitProvisioningState -ErrorAction SilentlyContinue)) 'state persistence validates protected directory before writing'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_state_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$path=Join-Path $temp 'state.json'
$script:allow=$false
function Assert-InitProtectedDirectory {param($Path) if(-not $script:allow){throw 'synthetic ACL rejection'}}
$state=New-InitProvisioningState 'fixture' 'TEST' 'Q:\source' ('b'*64)
$rejected=$false;try{Save-InitProvisioningState $state $path}catch{$rejected=$true}
Assert ($rejected -and -not(Test-Path -LiteralPath $path)) 'unsafe ACL prevents any state write'
$script:allow=$true
Save-InitProvisioningState $state $path
$saved=[IO.File]::ReadAllText($path)|ConvertFrom-Json
Assert ($saved.MachineGuid -eq 'fixture' -and $saved.Phase -eq 'Prepared') 'protected state serialized without credentials'
$original=[IO.File]::ReadAllText($path)
$state|Add-Member NoteProperty Password 'never-write-this'
$rejected=$false;try{Save-InitProvisioningState $state $path}catch{$rejected=$true}
Assert ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'invalid state preserves prior file exactly'
$state.PSObject.Properties.Remove('Password');$state.LastErrorCode='synthetic'
Save-InitProvisioningState $state $path
Assert (([IO.File]::ReadAllText($path)|ConvertFrom-Json).LastErrorCode -eq 'synthetic') 'atomic replacement retains latest non-secret status'
Assert (@(Get-ChildItem -LiteralPath $temp -File).Count -eq 1) 'successful persistence leaves no temporary state copies'
Write-Host ('ALL PASS: '+$script:count+' TEMP state assertions; ACL mocked, no host ACL changes')
