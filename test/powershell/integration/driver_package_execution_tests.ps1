#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupOfficialDriverPackage -ErrorAction SilentlyContinue)) '版本2套件使用全檔hash與安全freshstage'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_package_exec_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$archive=Join-Path $fixture 'fixture.zip';[IO.File]::WriteAllText($archive,'fixture')
$stage=Join-Path $fixture 'stage';[void][IO.Directory]::CreateDirectory($stage);[IO.File]::WriteAllText((Join-Path $stage 'driver.sys'),'payload')
$entry=[pscustomobject]@{Id='fixture';File='fixture.zip';SHA256=(Get-FileHash $archive).Hash;Files=@([pscustomobject]@{Path='driver.sys';SHA256=(Get-FileHash (Join-Path $stage 'driver.sys')).Hash});Drivers=@([pscustomobject]@{InfPath='driver.inf'})}
$script:installed=0;$script:expanded=0;$script:secure=0
function New-SetupDriverExtractionRoot {$script:secure++;return $stage}
function Expand-DriverArchive {param($Archive,$Destination) $script:expanded++}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Get-SetupDriverDeviceInventory {throw 'fixture forbids native inventory outside the mocked target boundary'}
function Invoke-SetupDriverTarget {$script:installed++;[pscustomobject]@{Results=@([pscustomobject]@{Status='Updated'});RebootRequired=$false;Failures=@()}}
$r=Invoke-SetupOfficialDriverPackage -Entry $entry -Archive $archive -Build 22621 -LogPath 'fixture'
Assert ($r.Results[0].Status -eq 'Updated' -and $script:installed -eq 1 -and $script:secure -eq 1 -and $script:expanded -eq 1) '真套件編排先freshstage再展開核實payload後目標安裝'
$script:installed=0;[IO.File]::AppendAllText((Join-Path $stage 'driver.sys'),'tampered');$failed=$false;try{Invoke-SetupOfficialDriverPackage -Entry $entry -Archive $archive -Build 22621 -LogPath 'fixture'}catch{$failed=$true};Assert ($failed -and $script:installed -eq 0) 'INF之外SYS竄改必須零安裝'
[IO.File]::WriteAllText((Join-Path $stage 'driver.sys'),'payload');[IO.File]::WriteAllText((Join-Path $stage 'extra.dll'),'unexpected');$failed=$false;try{Invoke-SetupOfficialDriverPackage -Entry $entry -Archive $archive -Build 22621 -LogPath 'fixture'}catch{$failed=$true};Assert ($failed -and $script:installed -eq 0) '額外非清單檔案拒絕'
$script:secure=0;[IO.File]::AppendAllText($archive,'changed');$failed=$false;try{Invoke-SetupOfficialDriverPackage -Entry $entry -Archive $archive -Build 22621 -LogPath 'fixture'}catch{$failed=$true};Assert ($failed -and $script:secure -eq 0 -and $script:installed -eq 0) 'archiveSHA失敗在stage前阻擋'
