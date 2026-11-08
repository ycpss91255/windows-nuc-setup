#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/ssh/mdns_publisher_library.ps1';if(Test-Path -LiteralPath $library){. $library}
Assert ([bool](Get-Command Invoke-SetupMdnsPublisherCycle -ErrorAction SilentlyContinue)) '原生公告必須有保活與地址機名更新的真worker控制器'
$script:begins=0;$script:closes=0;$script:failNative=$false;$script:lastStatus=$null
function New-SetupMdnsNativeRegistration {param($CodeRoot,$Row) $script:begins++;if($script:failNative){throw 'fixture native timeout'};$lease=[pscustomobject]@{Registered=$true};$lease|Add-Member ScriptMethod Dispose {$script:closes++;$this.Registered=$false};$lease}
function Write-SetupMdnsPublisherState {param($Path,$Context,$Facts,$State) $script:lastStatus=[pscustomobject]@{Status=$State.Status;Registered=$State.Ready;Name=$Facts.ComputerName;Count=$State.Leases.Count;Error=$State.Error}}
$facts=[pscustomobject]@{ComputerName='FIRST-PC';Addresses=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.9'});PolicyAllowed=$true;DnsClientRunning=$true;SshdRunning=$true;DnsClientProcessId=42}
$context=[pscustomobject]@{RunId=[guid]::NewGuid().ToString('D')}
$state=[pscustomobject]@{Leases=@();Fingerprint='';Plans=@();Ready=$false;Status='Starting';Error=''}
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert ($script:begins -eq 1 -and $state.Ready -and $script:lastStatus.Registered) '真worker保留native lease不在註冊後立即Dispose或退出'
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert ($script:begins -eq 1 -and $script:closes -eq 0) '持續心跳不重覆註冊且原生程序生命週期仍保活'
$facts.ComputerName='SECOND-PC';$facts.Addresses[0].IPAddress='192.0.2.10'
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert ($script:begins -eq 2 -and $script:closes -eq 1 -and $state.Plans[0].HostName -ceq 'SECOND-PC.local') '名稱或地址改變時先解除舊公告再註冊新計畫'
$facts.DnsClientProcessId=43
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert ($script:begins -eq 3 -and $script:closes -eq 2) 'DNSClient程序改變不能沿用舊的註冊成功快照'
$facts.PolicyAllowed=$false
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert (-not $state.Ready -and $script:closes -eq 3 -and $state.Status -eq 'SuppressedByPolicy') '管理或本機明確禁用時撤銷公告但不改GPO'
$facts.PolicyAllowed=$true;$facts.Addresses=@()
Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null
Assert (-not $state.Ready -and $state.Status -eq 'WaitingForNetwork') '離線時保活等待網路，不以localresolve冒稱公告成功'
$facts.Addresses=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.10'});$script:failNative=$true;$failed=$false
try{Invoke-SetupMdnsPublisherCycle -State $state -Context $context -Facts $facts -CodeRoot $root -StatusPath 'fixture'|Out-Null}catch{$failed=$true}
Assert ($failed -and -not $state.Ready -and $script:lastStatus.Status -eq 'Failed' -and $script:lastStatus.Error.Contains('timeout')) '原生錯誤或逾時明確失敗，不依本機解析假通過'