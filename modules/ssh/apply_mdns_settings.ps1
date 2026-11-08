#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'mdns_publisher_library.ps1')
$result=Invoke-SetupMdnsPublisher -SourceRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -VerifyOnly:$VerifyOnly
if(-not $result.Success){throw ('mDNS原生公告尚未確認：'+$result.Status+' '+$result.Error)}
Write-Host ('mDNS持續公告已註冊：'+$result.Name+'；SSH 22；各介面IPv4/IPv6；跨機連通仍由另一臺測試。') -ForegroundColor Green
$result