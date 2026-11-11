#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/ssh/mdns_library.ps1'
Assert (Test-Path -LiteralPath $library) '原生.local提供可獨立唯讀查驗的正式函式'
. $library
function New-NetFirewallRule {throw 'readonly forbids firewall writes'}
function Set-NetFirewallRule {throw 'readonly forbids firewall writes'}
function New-ItemProperty {throw 'readonly forbids registry writes'}
function Set-ItemProperty {throw 'readonly forbids registry writes'}
function Restart-Service {throw 'readonly forbids service changes'}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($global:MdnsFixture.Mode -eq 'service_error'){throw 'fixture service denied'};[pscustomobject]@{State=$(if($global:MdnsFixture.Mode -eq 'service_stopped'){'Stopped'}else{'Running'});ProcessId=42}}
function Test-Path {param($LiteralPath,$ErrorAction) return ($global:MdnsFixture.Mode -in @('local_disabled','policy_enabled','policy_zero','policy_error'))}
function Get-ItemProperty {param($LiteralPath,$ErrorAction) if($global:MdnsFixture.Mode -eq 'policy_error'){throw 'fixture registry denied'};if($LiteralPath -like '*SOFTWARE\Policies*'){if($global:MdnsFixture.Mode -eq 'policy_enabled'){[pscustomobject]@{EnableMDNS=1}}elseif($global:MdnsFixture.Mode -eq 'policy_zero'){[pscustomobject]@{EnableMDNS=0}}else{[pscustomobject]@{}}}else{if($global:MdnsFixture.Mode -in @('local_disabled','policy_enabled')){[pscustomobject]@{EnableMDNS=0}}else{[pscustomobject]@{}}}}
function Get-NetUDPEndpoint {param($LocalPort,$ErrorAction) if($LocalPort -ne 5353){throw 'wrong endpoint protocol'};if($global:MdnsFixture.Mode -eq 'endpoint_error'){throw 'fixture endpoint denied'};if($global:MdnsFixture.Mode -ne 'ipv6_only'){[pscustomobject]@{LocalAddress='::';LocalPort=5353;OwningProcess=42}}}
function Get-NetIPInterface {param($ConnectionState,$ErrorAction) @([pscustomobject]@{InterfaceIndex=12;AddressFamily='IPv4';ConnectionState='Connected'},[pscustomobject]@{InterfaceIndex=12;AddressFamily='IPv6';ConnectionState='Connected'},[pscustomobject]@{InterfaceIndex=13;AddressFamily='IPv4';ConnectionState='Connected'})}
function Get-NetIPAddress {param($ErrorAction) if($global:MdnsFixture.Mode -eq 'ip_error'){throw 'fixture IP denied'};if($global:MdnsFixture.Mode -ne 'ipv6_only'){@([pscustomobject]@{IPAddress='192.0.2.9';InterfaceIndex=12;AddressState='Preferred';InterfaceAlias='fixture LAN'},[pscustomobject]@{IPAddress='198.51.100.2';InterfaceIndex=13;AddressState='Preferred';InterfaceAlias='fixture second'},[pscustomobject]@{IPAddress='203.0.113.9';InterfaceIndex=99;AddressState='Preferred'},[pscustomobject]@{IPAddress='192.0.2.10';InterfaceIndex=12;AddressState='Tentative'})};[pscustomobject]@{IPAddress='fe80::1%12';InterfaceIndex=12;AddressState='Preferred';InterfaceAlias='fixture LAN'}}
function Resolve-DnsName {param($Name,$Type,[switch]$NoHostsFile,[switch]$QuickTimeout,[switch]$DnsOnly,$ErrorAction) $global:MdnsFixture.Queries.Add(@{Name=$Name;Type=$Type;NoHostsFile=[bool]$NoHostsFile;DnsOnly=[bool]$DnsOnly});if($global:MdnsFixture.Mode -eq 'nxdomain' -or ($global:MdnsFixture.Mode -eq 'ipv6_only' -and $Type -eq 'A')){throw 'fixture NXDOMAIN'};if($Type -eq 'A'){@([pscustomobject]@{IPAddress='192.0.2.9'},[pscustomobject]@{IPAddress='203.0.113.55'})}else{[pscustomobject]@{IPAddress='fe80::1'}}}
try{
 foreach($mode in @('normal','ipv6_only','nxdomain','local_disabled','policy_enabled','policy_zero','service_stopped','service_error','policy_error','endpoint_error','ip_error')){
  $global:MdnsFixture=@{Mode=$mode;Queries=[Collections.Generic.List[object]]::new()}
  $s=Get-SetupMdnsStatus -ComputerName 'OTHER-PC'
  Assert ($s.Name -ceq 'OTHER-PC.local' -and -not $s.RemoteVerified -and $global:MdnsFixture.Queries.Count -eq 2 -and @($global:MdnsFixture.Queries|Where-Object {-not $_.NoHostsFile -or $_.DnsOnly -or $_.Name -cne 'OTHER-PC.local'}).Count -eq 0) ('動態名稱用原生A與AAAA，排hosts但不禁multicast且不冒稱遠端 '+$mode)
  if($mode -eq 'normal'){Assert ($s.ActiveAddresses.Count -eq 3 -and $s.LocalResolutionMatched -and $s.Queries[0].MatchedAddresses.Count -eq 1 -and $s.ActiveAddresses.IPAddress -notcontains '203.0.113.9') '多介面只取作用中Preferred IP，解析須與本機交集';$text=@(Format-SetupMdnsConnectionInfo -Status $s -UserName "user's name");Assert (($text -join '').Contains("'user''s name'") -and ($text -join '').Contains('fe80::1%12') -and ($text -join '').Contains('192.0.2.9')) '帳號安全引用、IPv4備援及完整IPv6 scope可見'}
  if($mode -eq 'ipv6_only'){Assert ($s.LocalResolutionMatched -and -not $s.Udp5353Observed -and $s.ActiveAddresses.Count -eq 1 -and $s.ActiveAddresses[0].IPAddress -ceq 'fe80::1%12') 'IPv6-only與on-demand無5353不誤報失敗';$text=@(Format-SetupMdnsConnectionInfo -Status $s -UserName 'other_user');Assert (($text -join '').Contains('用戶端介面索引') -and ($text -join '').Contains('ssh -6')) 'linklocal備援不把伺服器scope冒充用戶端scope'}
  if($mode -eq 'nxdomain'){Assert (-not $s.LocalResolutionMatched -and @($s.Queries|Where-Object Error).Count -eq 2) 'NXDOMAIN實際錯誤保留且不假通過'}
  if($mode -eq 'policy_zero'){Assert ($s.PolicyMode -eq 'UseLocal' -and -not $s.NativeDisabledObserved) '官方ADMX的GPO零值為使用本機設定，不等於停用'}
  if($mode -eq 'local_disabled'){Assert ($s.NativeDisabledObserved -and $s.Notes.Count -gt 0) '本機明確停用可見原因但不覆寫'}
  if($mode -eq 'policy_enabled'){Assert ($s.PolicyMode -eq 'EnabledByPolicy' -and $s.GroupPolicyEnableMDNS -eq 1 -and $s.LocalEnableMDNS -eq 0) '原則與本機值分開回報不亂猜'}
  if($mode -eq 'policy_error'){Assert ($s.PolicyMode -eq 'Unknown' -and -not $s.GroupPolicyReadSucceeded -and -not $s.LocalPolicyReadSucceeded) '讀取失敗不能冒稱系統預設或UseLocal'}
  if($mode -like '*_error'){Assert ($s.ReadErrors.Count -gt 0) ('原生讀取失敗有具體原因 '+$mode)}
 }
 $s=Get-SetupMdnsStatus;Assert ($s.Name -ceq ([Environment]::MachineName+'.local')) '預設名稱直接來自目前系統MachineName'
}finally{Remove-Variable MdnsFixture -Scope Global -ErrorAction SilentlyContinue}
