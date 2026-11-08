#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'core/audit_library.ps1'
Assert (Test-Path -LiteralPath $library) 'Audit盤點必須可由正式具名來源指定TEMP輸出'
. $library
$fixture=Join-Path $env:TEMP ('audit_runtime_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$script:failure=$false
function Get-SetupHardwareProfile {[pscustomobject]@{Name='Generic'}}
function Get-CimInstance {param($ClassName,$Filter);switch($ClassName){Win32_Service{[pscustomobject]@{State='Running';StartMode='Auto'}} default{[pscustomobject]@{Name='fixture';Caption='fixture';BuildNumber='22631'}}}}
function Get-NetFirewallRule {[pscustomobject]@{Enabled=$true;Direction='Inbound';Action='Allow';Profile='Private'}}
function Get-NetFirewallAddressFilter {param([Parameter(ValueFromPipeline=$true)]$InputObject);process{[pscustomobject]@{RemoteAddress='LocalSubnet'}}}
function Get-NetFirewallProfile {[pscustomobject]@{Name='Private';Enabled=$true}}
function Get-NetIPAddress {[pscustomobject]@{InterfaceAlias='fixture';IPAddress='192.0.2.1';PrefixLength=24;PrefixOrigin='Dhcp'}}
function Get-NetIPInterface {[pscustomobject]@{InterfaceAlias='fixture';Dhcp='Enabled';ConnectionState='Connected'}}
function Get-ItemProperty {[pscustomobject]@{AutoAdminLogon='1';DefaultUserName='fixture'}}
function Get-LocalUser {param($SID);if($SID -ne 'fixture_sid'){throw 'wrong SID'};[pscustomobject]@{Name='fixture';Enabled=$true}}
function Get-PnpDevice {@([pscustomobject]@{Status='OK'},[pscustomobject]@{Status='Error';Class='USB';FriendlyName='fixture';InstanceId='fixture'})}
function Get-PhysicalDisk {[pscustomobject]@{FriendlyName='fixture';HealthStatus='Healthy';Size=1024}}
function Get-Volume {[pscustomobject]@{Size=1024;SizeRemaining=512;HealthStatus='Healthy'}}
function Get-BitLockerVolume {if($script:failure){throw 'fixture bitlocker failure'};[pscustomobject]@{EncryptionPercentage=0}}
function Get-Tpm {if($script:failure){throw 'fixture tpm failure'};[pscustomobject]@{TpmReady=$true}}
function Confirm-SecureBootUEFI {if($script:failure){throw 'fixture secureboot failure'};return $true}
function Test-Path {param($Path,$LiteralPath);if(($Path -like 'HKLM:*') -or ($LiteralPath -like 'HKLM:*')){return $false};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function Get-ScheduledTask {[pscustomobject]@{State='Ready'}}
function Read-SetupUpdateResult {param($CommonDataRoot,$LegacyRoot,$UserSid,$Computer);if($script:failure){throw 'fixture update identity error'};if($UserSid -ne 'fixture_sid'){throw 'wrong update SID'};[pscustomobject]@{RunId='fixture_run'}}
function Set-Service {throw 'audit attempted mutation'}
function Set-NetFirewallRule {throw 'audit attempted mutation'}
function Set-ItemProperty {throw 'audit attempted mutation'}
foreach($mode in @($false,$true)){
 $script:failure=$mode;$reportPath=Join-Path $fixture ('audit_'+$mode+'.json')
 $r=Invoke-SetupAudit -ReportPath $reportPath -UserSID fixture_sid -CommonDataRoot $fixture
 Assert (Test-Path -LiteralPath $reportPath) '唯讀盤點只把報告寫入明確TEMP路徑'
 $saved=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($saved.ProblemDevices.Count -eq 1 -and $saved.User.Name -eq 'fixture' -and -not $saved.RebootRequired) '實際枚舉結果與使用者SID保留'
 if($mode){Assert ($saved.UpdateResultError -eq 'fixture update identity error' -and $saved.TPM -eq 'fixture tpm failure') '可選API與受保護更新盤點錯誤如實保存'}else{Assert ($saved.UpdateResult.RunId -eq 'fixture_run' -and $saved.SecureBoot) '正常更新身分與安全狀態讀回'}
}
Write-Host 'ALL PASS: named audit source, TEMP only, Windows changes trapped.'