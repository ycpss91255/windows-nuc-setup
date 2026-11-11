#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
foreach($entry in @(@{Name='NUC8-LAN-Ping-v4';Protocol='ICMPv4';Type=8;Number=1},@{Name='NUC8-LAN-Ping-v6';Protocol='ICMPv6';Type=128;Number=58})){
 $rule=Get-NetFirewallRule -Name $entry.Name -ErrorAction SilentlyContinue
 if(-not $VerifyOnly){
  if($rule){Set-NetFirewallRule -Name $entry.Name -Enabled True -Direction Inbound -Action Allow -Profile Any -Protocol $entry.Protocol -IcmpType $entry.Type -RemoteAddress LocalSubnet|Out-Null}
  else{New-NetFirewallRule -Name $entry.Name -DisplayName ('NUC LAN Ping '+$entry.Protocol) -Enabled True -Direction Inbound -Action Allow -Profile Any -Protocol $entry.Protocol -IcmpType $entry.Type -RemoteAddress LocalSubnet|Out-Null}
  $rule=Get-NetFirewallRule -Name $entry.Name
 }
 if(-not $rule){throw ('缺少區域網路 Ping 規則：'+$entry.Name)}
 $scope=@($rule|Get-NetFirewallAddressFilter|Select-Object -ExpandProperty RemoteAddress)
 $port=$rule|Get-NetFirewallPortFilter
 if($rule.Enabled -ne 'True' -or $rule.Direction -ne 'Inbound' -or $rule.Action -ne 'Allow' -or $scope.Count -ne 1 -or $scope[0] -ne 'LocalSubnet' -or [string]$port.Protocol -notin @($entry.Protocol,[string]$entry.Number) -or [string]$port.IcmpType -notmatch ('^'+$entry.Type+'(?::\*|:\d+)?$')){throw ('Ping 規則內容不符：'+$entry.Name)}
}
Write-Host 'IPv4 / IPv6 Ping 已允許同網段來源；Windows 防火牆保持啟用。' -ForegroundColor Green


try{
 . (Join-Path $PSScriptRoot 'mdns_library.ps1')
 Write-Host '正在唯讀觀測目前系統名稱的 .local 解析；這不代表另一臺已可連線。'
 $mdns=Get-SetupMdnsStatus
 Format-SetupMdnsConnectionInfo -Status $mdns | ForEach-Object {Write-Host $_}
}catch{Write-Warning ('名稱觀測無法完成：'+$_.Exception.Message+'；既有 Ping 設定與 IP 連線不受影響。')}
