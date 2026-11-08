#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Get-FileHash {throw 'no-package offline forbids profile hashing'}
function Get-CimInstance {throw 'no-package offline forbids native queries'}
$failure='';$result=@();try{$result=@(. (Join-Path $root 'modules/drivers/install_drivers.ps1') -PackageOnly -DriverPackagePath '')}catch{$failure=$_.Exception.Message}
Assert (-not $failure -and $result.Count -eq 1 -and $result[0].Status -eq 'Skipped') ('未選包的離線載入不讀設定檔hash或做硬體查詢：'+$failure)
Assert ([bool](Get-Command Expand-DriverArchive -ErrorAction SilentlyContinue)) '安全載入仍提供原正式封存檔helpers'
