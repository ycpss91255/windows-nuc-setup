#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/ssh/custom_hosts_sync/sync_custom_hosts.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
function Config { @{Version=1;PollSeconds=10;Outputs=@{Hosts=$true;SSH=$true};Sites=@(@{Id='office';Enabled=$true;Rules=@(@{IPv4Cidr=@('192.0.2.0/24')})})} }
Assert (Test-NetworkIPv4Cidr '192.0.2.1' '0.0.0.0/0') '零prefix包含所有IPv4'
Assert (Test-NetworkIPv4Cidr '192.0.2.1' '192.0.2.1/32') '完整prefix精確匹配'
Assert (-not(Test-NetworkIPv4Cidr '192.0.3.1' '192.0.2.0/24')) '不同網段不匹配'
foreach($bad in @('localhost','999.2.3.4','::1')){Reject {ConvertTo-NetworkIPv4Bytes $bad} ('無效IPv4拒絕：'+$bad)}
foreach($bad in @('192.0.2.1','192.0.2.1/33')){Reject {ConvertTo-NetworkCidr $bad} ('無效CIDR拒絕：'+$bad)}
$mutations=@(
 {param($c) $c.Other=1}, {param($c) $c.Version='1'}, {param($c) $c.PollSeconds=4},
 {param($c) $c.Sites=$null}, {param($c) $c.Outputs=$null}, {param($c) $c.Outputs.Hosts='yes'},
 {param($c) $c.Sites=@(3)}, {param($c) $c.Sites[0].Extra=1}, {param($c) $c.Sites[0].Id='CON'},
 {param($c) $c.Sites+=@($c.Sites[0])}, {param($c) $c.Sites[0].Enabled=1}, {param($c) $c.Sites[0].Rules=@()},
 {param($c) $c.Sites[0].Rules=@(4)}, {param($c) $c.Sites[0].Rules=@(@{})}, {param($c) $c.Sites[0].Rules=@(@{Bad=@('a')})},
 {param($c) $c.Sites[0].Rules=@(@{SSID='a'})}, {param($c) $c.Sites[0].Rules=@(@{SSID=@('')})},
 {param($c) $c.Sites[0].Rules=@(@{PrefixLength=33})}, {param($c) $c.Sites[0].Rules=@(@{AdapterNameRegex=''})},
 {param($c) $c.Sites[0].Rules=@(@{AdapterNameRegex='['})}
)
Reject {Assert-NetworkSiteConfiguration 'invalid'} '配置必須為物件'
$index=0;foreach($change in $mutations){$c=Config;& $change $c;Reject {Assert-NetworkSiteConfiguration $c} ('配置邊界拒絕 '+$index);$index++}
$adapter=[pscustomobject]@{Name='Ethernet';Description='Example physical';SSIDs=@('CaseSensitive');NetworkProfiles=@('Work');IPv4=@([pscustomobject]@{Address='192.0.2.5';PrefixLength=24})}
$cases=@(
 @{Rule=@{SSID=@('CaseSensitive')};Expected=$true},@{Rule=@{SSID=@('casesensitive')};Expected=$false},
 @{Rule=@{AdapterName=@('Ethernet')};Expected=$true},@{Rule=@{AdapterName=@('Other')};Expected=$false},
 @{Rule=@{NetworkProfile=@('Work')};Expected=$true},@{Rule=@{NetworkProfile=@('Other')};Expected=$false},
 @{Rule=@{AdapterNameRegex='^Eth';AdapterDescriptionRegex='physical'};Expected=$true},@{Rule=@{AdapterNameRegex='^Other'};Expected=$false},
 @{Rule=@{PrefixLength=24};Expected=$true},@{Rule=@{PrefixLength=16};Expected=$false},
 @{Rule=@{IPv4Cidr=@('198.51.100.0/24')};Expected=$false},@{Rule=@{IPv4Cidr=@('192.0.2.0/24');PrefixLength=24};Expected=$true}
)
$index=0;foreach($case in $cases){Assert ((Test-NetworkAdapterRule $adapter $case.Rule) -eq $case.Expected) ('網卡條件完整比對 '+$index);$c=Config;$c.Sites[0].Rules=@($case.Rule);Assert-NetworkSiteConfiguration $c;$index++}
$c=Config;$c.Sites[0].Enabled=$false
Assert (@(Get-ActiveNetworkSites $c @{Adapters=@($adapter)}).Count -eq 0) '停用站點不匯入'
# OS discovery is replaced at the boundary; no real network commands run.
function Get-NetAdapter {param([switch]$IncludeHidden,$ErrorAction);@([pscustomobject]@{Status='Up';Name='wifi';InterfaceDescription='fake';InterfaceGuid='{11111111-1111-1111-1111-111111111111}';ifIndex=3;NdisPhysicalMedium='9';PhysicalMediaType='Wireless'},[pscustomobject]@{Status='Up';Name='wifi2';InterfaceDescription='fake2';InterfaceGuid='22222222-2222-2222-2222-222222222222';ifIndex=4;NdisPhysicalMedium='9'})}
function Get-NetIPAddress {param($AddressFamily,$ErrorAction);@([pscustomobject]@{AddressState='Preferred';IPAddress='192.0.2.5';PrefixLength=24;InterfaceIndex=3},[pscustomobject]@{AddressState='Preferred';IPAddress='127.0.0.1';PrefixLength=8;InterfaceIndex=3})}
function Get-NetConnectionProfile {param($ErrorAction);[pscustomobject]@{InterfaceIndex=3;Name='Work'}}
function Get-NetworkWlanSSIDMap { @{'11111111-1111-1111-1111-111111111111'='test-ssid'} }
$snapshot=Get-NetworkSnapshot
Assert ($snapshot.Adapters.Count -eq 2 -and $snapshot.Adapters[0].SSIDs[0] -eq 'test-ssid') 'snapshot組合模擬SSID與網卡'
Assert ($snapshot.Adapters[0].IPv4.Count -eq 1 -and $snapshot.Warnings.Count -eq 1) 'snapshot過濾loopback且缺SSID發出警告'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('network_helpers_'+[guid]::NewGuid().ToString('N'))
$profile=Join-Path $temp 'profile';$state=Join-Path $temp 'state';$target=Join-Path $temp 'hosts'
[void][IO.Directory]::CreateDirectory((Join-Path $profile '.config/hosts/hosts.d'));[void][IO.Directory]::CreateDirectory((Join-Path $profile '.ssh/config.d'))
$utf8=[Text.UTF8Encoding]::new($false)
function WriteTemp($Path,$Text){[IO.File]::WriteAllText($Path,$Text,$utf8)}
$settings=Join-Path $profile '.config/hosts/sites.json';$c=Config
function SaveConfig {WriteTemp $settings ($c|ConvertTo-Json -Depth 8)}
SaveConfig
WriteTemp (Join-Path $profile '.ssh/config') "Include active-sites.conf`nHost custom`n  HostName example.invalid`n"
WriteTemp (Join-Path $profile '.ssh/config.d/global.conf') "Host global`n  HostName example.invalid`n"
$global=Join-Path $profile '.config/hosts/hosts.d/global.hosts';WriteTemp $global "# comment`n192.0.2.1 alpha alpha`n"
WriteTemp (Join-Path $profile '.config/hosts/hosts.d/unregistered.hosts') 'this ignored file is invalid'
WriteTemp $target '127.0.0.1 localhost'
$snapshot=[pscustomobject]@{Adapters=@($adapter);Warnings=@()}
function Get-Acl {param($LiteralPath);'fixture acl'}
function Set-Acl {param($LiteralPath,$AclObject);if(-not $LiteralPath.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Only TEMP ACL fixture permitted'}}
$result=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $state -TargetHostsPath $target -Snapshot $snapshot
Assert ($result.Success -and $result.Outputs.Hosts.Changed -and $result.Outputs.SSH.Changed) '真TEMP同步寫入兩輸出'
Assert ((Test-Path (Join-Path $state 'hosts.original.backup')) -and (Get-Content $target -Raw).Contains('alpha')) '真TEMP hosts更新前保留原始備份'
$result=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $state -TargetHostsPath $target -Snapshot $snapshot
Assert ($result.Success -and -not $result.Outputs.Hosts.Changed -and -not $result.Outputs.SSH.Changed) '重跑保持輸出不變'
Assert ($result.Outputs.Hosts.Warnings.Count -gt 0 -and $result.Outputs.SSH.Warnings.Count -gt 0) '缺少已啟用站點檔案保持警告'
WriteTemp $global "192.0.2.1 alpha`n192.0.2.2 alpha`n"
$result=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $state -TargetHostsPath $target -Snapshot $snapshot
Assert (-not $result.Success -and (Test-Path (Join-Path $state 'last-error.json'))) 'alias衝突拒絕並保存失敗狀態'
WriteTemp $global '192.0.2.3 beta'
$result=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $state -TargetHostsPath $target -Snapshot $snapshot
Assert ($result.Success -and -not(Test-Path (Join-Path $state 'last-error.json'))) '成功重試清除舊錯誤且套用新資料'
$c.Outputs.Hosts=$false;$c.Outputs.SSH=$false;SaveConfig
$before=Get-FileHash $target;$result=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $state -TargetHostsPath $target -Snapshot $snapshot
Assert ($result.Success -and -not $result.Outputs.Hosts.Enabled -and (Get-FileHash $target).Hash -eq $before.Hash) '停用輸出不改目標'
$c.Outputs.Hosts=$true;$c.Outputs.SSH=$true;SaveConfig
foreach($bad in @('only-one-token','192.0.2.1 invalid!')){WriteTemp $global $bad;Reject {Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Snapshot $snapshot} ('非法hosts拒絕：'+$bad)}
WriteTemp $global '192.0.2.1 alpha'
WriteTemp $target '# BEGIN custom-hosts'
Reject {Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Snapshot $snapshot} '不完整管理區段拒絕'
Reject {Get-CustomHostsPlan -ProfilePath $profile -Snapshot $snapshot} 'Hosts缺少目標拒絕'
WriteTemp (Join-Path $profile '.ssh/config') "Host example`nInclude active-sites.conf"
Reject {Get-CustomHostsPlan -ProfilePath $profile -Mode SSH -Snapshot $snapshot} 'SSH Include必須位於全域'
$textFile=Join-Path $temp 'encoding.txt'
foreach($encoding in @([Text.UTF8Encoding]::new($true),[Text.UnicodeEncoding]::new($false,$true),[Text.UnicodeEncoding]::new($true,$true))){[IO.File]::WriteAllText($textFile,'中文',$encoding);Assert ((Read-SyncTextDocument $textFile).Text -ceq '中文') ('保留BOM編碼 '+$encoding.WebName)}
[IO.File]::WriteAllBytes($textFile,[byte[]]@(255,254,0))
Reject {Read-SyncTextDocument $textFile} 'BOM與內容不相容拒絕'
WriteTemp $textFile 'unchanged'
Reject {Write-SyncTextFile -Path $textFile -Text 'new' -Encoding $utf8 -ExpectedHash 'wrong'} '並行修改hash拒絕'
Reject {Write-SyncTextFile -Path (Join-Path $temp 'gone') -Text 'new' -Encoding $utf8 -ExpectedHash 'expected'} '並行刪除拒絕'
