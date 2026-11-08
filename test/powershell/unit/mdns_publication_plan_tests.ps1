#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/ssh/mdns_publisher_library.ps1'
if(Test-Path -LiteralPath $library){. $library}
Assert ([bool](Get-Command Get-SetupMdnsPublicationPlan -ErrorAction SilentlyContinue)) '原始RPi式.local目標需要受控publisher計畫而非只有本機解析觀測'
$rows=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.9'},[pscustomobject]@{InterfaceIndex=7;IPAddress='fe80::9%7'},[pscustomobject]@{InterfaceIndex=8;IPAddress='198.51.100.5'})
$plans=@(Get-SetupMdnsPublicationPlan -ComputerName 'FIRST-PC' -Addresses $rows)
Assert ($plans.Count -eq 2 -and $plans[0].HostName -ceq 'FIRST-PC.local' -and $plans[0].ServiceName -ceq 'FIRST-PC._ssh._tcp.local' -and $plans[0].Port -eq 22 -and $plans[0].InterfaceIndex -eq 7 -and $plans[0].IPv4 -ceq '192.0.2.9' -and $plans[0].IPv6 -ceq 'fe80::9') '每介面A/AAAA與SSH22固定schema，不借用其他介面地址'
$renamed=@(Get-SetupMdnsPublicationPlan -ComputerName 'SECOND-PC' -Addresses $rows)
Assert ($renamed[0].HostName -ceq 'SECOND-PC.local' -and $renamed[0].ServiceName -ceq 'SECOND-PC._ssh._tcp.local') '重啟後以新的系統名重新建計畫不固定主機名稱'
$default=@(Get-SetupMdnsPublicationPlan -Addresses $rows)
Assert ($default[0].HostName -ceq ([Environment]::MachineName+'.local')) '預設名稱動態取本機MachineName'
foreach($bad in @('other.local','name;command','-bad','bad name')){$failed=$false;try{Get-SetupMdnsPublicationPlan -ComputerName $bad -Addresses $rows|Out-Null}catch{$failed=$true};Assert $failed ('不接受任意名稱或命令注入 '+$bad)}
$failed=$false;try{Get-SetupMdnsPublicationPlan -ComputerName 'safe-pc' -Addresses @([pscustomobject]@{InterfaceIndex=0;IPAddress='192.0.2.9'})|Out-Null}catch{$failed=$true};Assert $failed '未知介面不得向所有介面廣播'
$none=@(Get-SetupMdnsPublicationPlan -ComputerName 'safe-pc' -Addresses @([pscustomobject]@{InterfaceIndex=7;IPAddress='127.0.0.1'},[pscustomobject]@{InterfaceIndex=7;IPAddress='0.0.0.0'},[pscustomobject]@{InterfaceIndex=7;IPAddress='224.0.0.251'}))
Assert ($none.Count -eq 0) 'loopback與未指定及multicast不是可公告主機地址'