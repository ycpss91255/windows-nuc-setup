#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$path=Join-Path $root 'modules/ssh/connection_info_library.ps1'
Assert (Test-Path $path) 'SSH領域提供獨立連線資訊函式'
. $path
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) @([pscustomobject]@{IPAddress='192.0.2.42';AddressState='Preferred'},[pscustomobject]@{IPAddress='192.0.2.42';AddressState='Preferred'},[pscustomobject]@{IPAddress='127.0.0.2';AddressState='Preferred'},[pscustomobject]@{IPAddress='169.254.1.1';AddressState='Preferred'},[pscustomobject]@{IPAddress='198.51.100.1';AddressState='Tentative'})}
$text=@(Get-SetupSshConnectionInfo -UserName 'fixture_user' -ComputerName 'fixture_pc')
Assert ($text[0] -eq '電腦名稱：fixture_pc') '顯示動態電腦名'
Assert ($text[1].Contains('fixture_user') -and $text[1].Contains('不顯示密碼')) '顯示帳號及既有密碼說明不輸出密碼'
Assert (@($text|Where-Object {$_ -like 'IPv4*'}).Count -eq 1 -and ($text -join '').Contains('ssh "fixture_user@192.0.2.42"')) '只輸出唯一可用IPv4及完整連線命令'
Assert (($text -join '') -notmatch '127\.0|169\.254|198\.51') '排除loopback/linklocal/tentative'
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) @()}
Assert ((@(Get-SetupSshConnectionInfo) -join '').Contains('沒有可用 IPv4')) '未連線仍明確提示'
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) throw 'fixture failure'}
Assert ((@(Get-SetupSshConnectionInfo) -join '').Contains('無法讀取 IPv4')) '讀取失敗有中文說明'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/ssh/apply_ssh_settings.ps1'),[ref]$tokens,[ref]$errors)
$calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-SetupSshConnectionInfo'},$true))
Assert ($calls.Count -eq 1) 'Windows第4階段與獨立SSH入口完成後顯示資訊'
Write-Host 'ALL PASS: SSH connection info source tests; no host changes'
