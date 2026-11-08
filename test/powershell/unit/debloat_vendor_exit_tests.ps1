#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('debloat_vendor_exit_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$runner=Join-Path $fixture 'runner.ps1';$log=Join-Path $fixture 'private.log';$proof=Join-Path $fixture 'proof.json'
$code=@'
param($SourceRoot,$ProofPath)
$ErrorActionPreference='Stop'
$module=Join-Path $SourceRoot 'modules/debloat'
. (Join-Path $module 'win11debloat/Scripts/Features/Invoke-Changes.ps1')
. (Join-Path $module 'win11debloat/Scripts/CLI/Wait-ForKeyPress.ps1')
$profile=Get-Content (Join-Path $module 'debloat_profile.json') -Raw|ConvertFrom-Json
$catalog=(Get-Content (Join-Path $module 'win11debloat/Config/Features.json') -Raw|ConvertFrom-Json).Features
$script:Features=@{};foreach($feature in $catalog){$script:Features[$feature.FeatureId]=$feature}
$script:Params=@{SkipRegistryBackup=$true};foreach($id in $profile.Features){$script:Params[$id]=$true}
$script:ControlParams=@('SkipRegistryBackup');$script:UndoParams=@{};$script:CancelRequested=$false;$script:imports=0;$Silent=$true
function Import-RegistryFile {param($Message,$File) $script:imports++;return $false}
function Get-CurrentWindowsBuild {26200}
function Test-FeatureSupportedOnBuild {param($Feature,$Build) $true}
function Get-Translation {param($Key,$Field,$Section) 'fixture'}
function Stop-Transcript {}
Invoke-AllChanges
@{FeatureFailures=$script:FeatureFailures;Imports=$script:imports;Selected=$profile.Features.Count}|ConvertTo-Json|Set-Content -LiteralPath $ProofPath -Encoding UTF8
Wait-ForKeyPress
'@
[IO.File]::WriteAllText($runner,$code,[Text.UTF8Encoding]::new($true))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -SourceRoot $root -ProofPath $proof *> $log
$native=$LASTEXITCODE;$result=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
Assert ($result.FeatureFailures -eq 10 -and $result.Imports -eq 10 -and $result.Selected -eq 10) '真第三方編排透過原生匯入失敗替身累計全部十項失敗，沒有修改系統'
Assert ($native -eq 0) '真第三方 Wait-ForKeyPress 仍回0，證明外層不能只信native退出碼'
