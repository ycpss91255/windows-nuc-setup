#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1');. (Join-Path $root 'modules/drivers/driver_installation_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupDriverVerification -ErrorAction SilentlyContinue)) '整輪結束可重新唯讀核對官方目標而非只讀舊driver結果'
$fixture=Join-Path $env:TEMP ('driver_verify_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
[IO.File]::WriteAllText((Join-Path $fixture 'wifi.zip'),'inert')
$target=@{Id='wifi';InfPath='wifi.inf';Provider='Intel';DriverVersion='20.70.32.1';MinimumBuild=22000;Architecture='amd64';HardwareIds=@('PCI\VEN_8086&DEV_24FD')}
$manifest=@{SchemaVersion=2;AuditedAt=(Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json).AuditedAt;Packages=@(@{Id='wifi';PackageVersion='22.200.2';SourceUrl='https://www.intel.com/driver';File='wifi.zip';SHA256=(Get-FileHash (Join-Path $fixture 'wifi.zip')).Hash;Drivers=@($target)})}
$manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Encoding UTF8
$script:device=[pscustomobject]@{InstanceId='PCI\fixture';HardwareIds=$target.HardwareIds;DriverVersion='20.70.32.1';DriverProvider='Intel';Status='OK'};$script:reads=0
function Get-SetupDriverDeviceInventory {param($Targets) $script:reads++;$script:device}
function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{BuildNumber='26100'}}
function New-SetupDriverExtractionRoot {throw 'VerifyOnly forbids stage'}
function Expand-DriverArchive {throw 'VerifyOnly forbids extraction'}
function Invoke-SetupDriverInfInstall {throw 'VerifyOnly forbids installation'}
function Invoke-SetupDriverPnpRescan {throw 'VerifyOnly forbids native state changes'}
$run=[guid]::NewGuid().ToString()
$r=Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run
Assert ($r.Success -and $r.Targets[0].Status -eq 'Current' -and $r.VerificationRunId -ceq $run -and $r.Computer -ceq [Environment]::MachineName -and $r.UserSID -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) '真正fresh唯讀結果綁本輪同機同帳號'
Assert ($r.OfficialCheckedAt -ceq $manifest.AuditedAt -and $r.OfficialCheckedAt -match '^\d{4}-\d{2}-\d{2}$') '正式manifest的AuditedAt查核日期如實回傳，不因錯欄位成空值'
@{Success=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'Driver-Result.json') -Encoding UTF8
$script:device.DriverVersion='20.70.17.1';$r=Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run
Assert (-not $r.Success -and $r.Targets[0].Status -eq 'UpdateRequired' -and $script:reads -eq 2) 'WindowsUpdate若改回舊版不信先前Success而重新讀回'
$script:device.DriverVersion='21.0.0.1';$r=Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run
Assert ($r.Success -and $r.Targets[0].Status -eq 'NewerInstalled') '較新已裝版保留並如實列NewerInstalled'
$script:device.Status='Error';$r=Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run
Assert (-not $r.Success -and $r.Targets[0].Status -eq 'Unverified') '版本較新但裝置異常仍不通過'
$script:device.HardwareIds=@('PCI\VEN_9999&DEV_0000');$r=Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run
Assert (-not $r.Success -and $r.Targets[0].Status -eq 'Absent') '全部目標都沒讀到不得假稱官方driver已確認'
Assert (-not(Test-Path (Join-Path $fixture 'driver_logs'))) '唯讀驗證不建立安裝紀錄或payloadcache'
$manifest.SchemaVersion=1;$manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Encoding UTF8
$failed=$false;try{Invoke-SetupDriverVerification -DriverRoot $fixture -VerificationRunId $run}catch{$failed=$_.Exception.Message -match '目標'}
Assert $failed '舊包不能冒充已核官方目標版本驗證'
