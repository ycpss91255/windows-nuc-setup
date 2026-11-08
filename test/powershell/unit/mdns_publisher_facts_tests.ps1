#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/ssh/mdns_publisher_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$script:g=$null;$script:l=$null;$script:kind='DWord';$script:readFailure=$false;$script:serviceMissing=$false
function Test-Path {param($LiteralPath,$ErrorAction) if($script:readFailure){throw 'fixture denied policy read'};return $true}
function Get-Item {param($LiteralPath,$ErrorAction) $value=if($LiteralPath -like '*Policies*'){$script:g}else{$script:l};$k=[pscustomobject]@{Value=$value;Kind=$script:kind};$k|Add-Member ScriptMethod GetValueNames {if($null -ne $this.Value){'EnableMDNS'}};$k|Add-Member ScriptMethod GetValue {param($name) $this.Value};$k|Add-Member ScriptMethod GetValueKind {param($name) $this.Kind};$k}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($script:serviceMissing){return $null};[pscustomobject]@{State='Running';ProcessId=42}}
function Get-NetIPInterface {param($ConnectionState,$ErrorAction) [pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4'}}
function Get-NetIPAddress {param($ErrorAction) @([pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4';IPAddress='192.0.2.9';AddressState='Preferred'},[pscustomobject]@{InterfaceIndex=8;AddressFamily='IPv4';IPAddress='192.0.2.10';AddressState='Preferred'},[pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4';IPAddress='192.0.2.11';AddressState='Tentative'})}
$f=Get-SetupMdnsPublisherFacts
Assert ($f.ComputerName -ceq [Environment]::MachineName -and $f.Addresses.Count -eq 1 -and $f.Addresses[0].IPAddress -ceq '192.0.2.9' -and $f.DnsClientRunning -and $f.SshdRunning) '真facts僅取目前機名/已連介面Preferred地址，不取斷線或Tentative'
$script:l=0;$f=Get-SetupMdnsPublisherFacts;Assert (-not $f.PolicyAllowed) '本機明確停用mDNS時保留原則拒絕公告'
$script:g=1;$f=Get-SetupMdnsPublisherFacts;Assert $f.PolicyAllowed '管理EnableMDNS1優先，未寫任何政策'
$script:g=0;$f=Get-SetupMdnsPublisherFacts;Assert (-not $f.PolicyAllowed) '管理0沿用local0，不覆蓋本機禁用'
$script:l=1;$f=Get-SetupMdnsPublisherFacts;Assert $f.PolicyAllowed '管理0沿用local1'
foreach($case in 'kind','unknown','denied','missing_service'){
 $script:g=$null;$script:l=1;$script:kind='DWord';$script:readFailure=$false;$script:serviceMissing=$false
 switch($case){kind{$script:kind='String'} unknown{$script:l=7} denied{$script:readFailure=$true} missing_service{$script:serviceMissing=$true}}
 $failed=$false;try{Get-SetupMdnsPublisherFacts|Out-Null}catch{$failed=$true};Assert $failed ('未知或讀失敗不能以預設允許公告 '+$case)
}