#Requires -Version 5.1
# Read-only native observations. No registry, firewall, service or hosts changes.
function Get-SetupMdnsAddressKey {
 param([string]$Address)
 $parsed=$null
 if([Net.IPAddress]::TryParse(($Address -split '%')[0],[ref]$parsed)){return ($parsed.AddressFamily.ToString()+'|'+$parsed.ToString())}
 return ''
}
function Get-SetupMdnsStatus {
 param([string]$ComputerName=([Environment]::MachineName))
 $name=$ComputerName+'.local';$readErrors=@();$notes=@();$service=$null;$local=$null;$group=$null;$endpoints=@();$addresses=@();$queries=@()
 try{$service=Get-CimInstance Win32_Service -Filter "Name='Dnscache'" -ErrorAction Stop;if(-not $service){throw '找不到 DNS Client 服務'}}catch{$readErrors+=('Dnscache：'+$_.Exception.Message)}
 foreach($entry in @(@{Key='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient';Kind='Group'},@{Key='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Kind='Local'})){
  try{if(Test-Path -LiteralPath $entry.Key -ErrorAction Stop){$values=Get-ItemProperty -LiteralPath $entry.Key -ErrorAction Stop;$property=$values.PSObject.Properties['EnableMDNS'];if($property){if($entry.Kind -eq 'Group'){$group=$property.Value}else{$local=$property.Value}}}}catch{$readErrors+=($entry.Kind+' EnableMDNS：'+$_.Exception.Message)}
 }
 $policyMode=if($group -eq 1){'EnabledByPolicy'}else{'UseLocal'}
 $disabled=($group -ne 1 -and $null -ne $local -and $local -eq 0)
 if($group -eq 1){$notes+='管理原則要求使用 mDNS；本機值另列，未修改管理設定。'}elseif($disabled){$notes+='本機 EnableMDNS=0；原生 DNS Client mDNS 已明確停用，未覆寫。'}else{$notes+='未明確停用；缺少 EnableMDNS 值代表系統預設，並非錯誤。'}
 if($null -ne $group -and $group -notin @(0,1)){$notes+='管理原則值不是 0/1，無法解讀。'}
 if($service -and $service.State -ne 'Running'){$notes+=('DNS Client 服務狀態：'+$service.State)}
 try{$endpoints=@(Get-NetUDPEndpoint -LocalPort 5353 -ErrorAction Stop|Select-Object LocalAddress,LocalPort,OwningProcess)}catch{$readErrors+=('UDP 5353：'+$_.Exception.Message)}
 try{
  $interfaces=@(Get-NetIPInterface -ConnectionState Connected -ErrorAction Stop)
  foreach($item in @(Get-NetIPAddress -ErrorAction Stop|Where-Object AddressState -eq 'Preferred')){
   $parsed=$null;if(-not [Net.IPAddress]::TryParse([string]$item.IPAddress,[ref]$parsed) -or [Net.IPAddress]::IsLoopback($parsed) -or $parsed.Equals([Net.IPAddress]::Any) -or $parsed.Equals([Net.IPAddress]::IPv6Any) -or $parsed.IsIPv6Multicast){continue}
   $family=if($parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){'IPv4'}else{'IPv6'}
   if(-not @($interfaces|Where-Object {$_.InterfaceIndex -eq $item.InterfaceIndex -and [string]$_.AddressFamily -eq $family}).Count){continue}
   $address=[string]$item.IPAddress;$linkLocal=($parsed.IsIPv6LinkLocal -or $address -like '169.254.*')
   if($parsed.IsIPv6LinkLocal -and -not $address.Contains('%')){$address+='%'+$item.InterfaceIndex}
   $addresses+=[pscustomobject]@{IPAddress=$address;AddressFamily=$family;InterfaceIndex=$item.InterfaceIndex;InterfaceAlias=$item.InterfaceAlias;IsLinkLocal=$linkLocal;Key=(Get-SetupMdnsAddressKey $address)}
  }
  $addresses=@($addresses|Sort-Object IPAddress,InterfaceIndex -Unique)
 }catch{$readErrors+=('作用中本機 IP：'+$_.Exception.Message)}
 foreach($type in @('A','AAAA')){
  $returned=@();$errorText=''
  try{$returned=@(Resolve-DnsName -Name $name -Type $type -NoHostsFile -QuickTimeout -ErrorAction Stop|Where-Object IPAddress|ForEach-Object {[string]$_.IPAddress}|Select-Object -Unique)}catch{$errorText=$_.Exception.Message}
  $keys=@($returned|ForEach-Object {Get-SetupMdnsAddressKey $_}|Where-Object {$_})
  $matched=@($addresses|Where-Object {$_.Key -in $keys -and $_.AddressFamily -eq $(if($type -eq 'A'){'IPv4'}else{'IPv6'})})
  $queries+=[pscustomobject]@{Type=$type;Addresses=@($returned);MatchedAddresses=@($matched);Error=$errorText}
 }
 [pscustomobject]@{ComputerName=$ComputerName;Name=$name;DnsClientState=$(if($service){$service.State}else{'Unknown'});DnsClientProcessId=$(if($service){$service.ProcessId}else{$null});GroupPolicyEnableMDNS=$group;LocalEnableMDNS=$local;PolicyMode=$policyMode;NativeDisabledObserved=$disabled;Udp5353Observed=($endpoints.Count -gt 0);Endpoints=@($endpoints);ActiveAddresses=@($addresses);Queries=@($queries);LocalResolutionMatched=(@($queries|Where-Object {$_.MatchedAddresses.Count -gt 0}).Count -gt 0);RemoteVerified=$false;ReadErrors=@($readErrors);Notes=@($notes)}
}
function Format-SetupMdnsConnectionInfo {
 param([Parameter(Mandatory=$true)]$Status,[string]$UserName=$env:USERNAME)
 $userArgument="'"+$UserName.Replace("'","''")+"'";$nameArgument="'"+$Status.Name.Replace("'","''")+"'"
 '本機名稱：'+$Status.Name+'；本機系統解析吻合：'+$(if($Status.LocalResolutionMatched){'是'}else{'否'})+'；尚未由另一臺驗證。'
 'DNS Client：'+$Status.DnsClientState+'；EnableMDNS 原則：'+$(if($null -eq $Status.GroupPolicyEnableMDNS){'未設定'}else{$Status.GroupPolicyEnableMDNS})+'；本機：'+$(if($null -eq $Status.LocalEnableMDNS){'系統預設'}else{$Status.LocalEnableMDNS})+'；UDP 5353 端點：'+$(if($Status.Udp5353Observed){'已觀測'}else{'未觀測（可能按需啟用）'})
 foreach($ip in $Status.ActiveAddresses){'本機 '+$ip.AddressFamily+'：'+$ip.IPAddress+'；介面 '+$ip.InterfaceIndex+' '+$ip.InterfaceAlias}
 foreach($query in $Status.Queries){'本機 '+$query.Type+' 查詢：'+($query.Addresses -join ', ')+'；吻合本機 '+$query.MatchedAddresses.Count+' 個'+$(if($query.Error){'；錯誤：'+$query.Error}else{''})}
 '另一臺測試：ping -4 '+$nameArgument+'；ping -6 '+$nameArgument
 '名稱連線：ssh -l '+$userArgument+' '+$nameArgument
 $fallback=@($Status.ActiveAddresses|Where-Object {-not $_.IsLinkLocal}|Sort-Object AddressFamily,IPAddress|Select-Object -First 1)
 if(-not $fallback.Count){$fallback=@($Status.ActiveAddresses|Select-Object -First 1)}
 if($fallback.Count){$ip=$fallback[0];$target=$ip.IPAddress;$flag=if($ip.AddressFamily -eq 'IPv4'){'-4'}else{'-6'}
  if($ip.AddressFamily -eq 'IPv6' -and $ip.IsLinkLocal){$target=($target -split '%')[0]+'%<用戶端介面索引>'; 'IPv6 link-local 的 scope 必須使用另一臺電腦該網段的介面索引，不能直接沿用上列本機索引。'}
  'IP 備援範例：ssh '+$flag+' -l '+$userArgument+" '"+$target+"'"
 }else{'目前沒有作用中本機 IP；接上區域網路後重新查看。'}
 foreach($note in $Status.Notes){'名稱觀測說明：'+$note}
 foreach($failure in $Status.ReadErrors){'名稱觀測失敗：'+$failure}
}
