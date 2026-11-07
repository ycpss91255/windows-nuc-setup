#Requires -Version 5.1
$ErrorActionPreference='Stop'
$moduleRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $moduleRoot 'OOBE-Library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++;Write-Host ('PASS: '+$Name)}
Assert ((Get-InitRoute 'S-1-5-18' 'IMAGE_STATE_UNDEPLOYABLE' $true $false) -eq 'GuideAudit') 'SYSTEM always guides to audit, never prepares account'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'IMAGE_STATE_UNDEPLOYABLE' $true $true) -eq 'ConfirmAudit') 'known unfinished built-in administrator requires audit confirmation'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'unexpected' $true $true) -eq 'RejectBuiltinAdministrator') 'unknown setup state cannot prepare account'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'IMAGE_STATE_COMPLETE' $true $true) -eq 'RejectBuiltinAdministrator') 'normal built-in administrator is not audit'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-1001' 'IMAGE_STATE_COMPLETE' $true $true) -eq 'DesktopSSH') 'formal account desktop routes only to SSH'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-1001' 'IMAGE_STATE_COMPLETE' $true $false) -eq 'RejectUnknownSetupState') 'non-desktop account rejected'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-1001' 'IMAGE_STATE_COMPLETE' $false $true) -eq 'ElevationRequired') 'desktop user elevation required'
Assert (Test-InitUserName 'cyc-user' @('other')) 'valid local user accepted'
Assert (-not(Test-InitUserName 'existing' @('Existing'))) 'existing user rejected case-insensitively'
Assert (-not(Test-InitUserName 'defaultuser0' @())) 'reserved user rejected'
Assert (-not(Test-InitUserName 'bad/name' @())) 'invalid local name rejected'
Assert (-not(Test-InitUserName ('a'*21) @())) 'long local name rejected'
Assert (-not(Test-InitPassword '')) 'empty password rejected'
Assert (-not(Test-InitPassword ('a'*128))) 'password over Windows length rejected'
Assert (-not(Test-InitPassword ("a"+[char]0+"b"))) 'NUL password rejected'
$marker='NUC-INIT-'+[guid]::NewGuid().ToString('N')
$password='a&<>"中文'
$xmlText=New-InitAnswerXml -UserName 'my&user' -Password $password -CleanupCommand 'powershell.exe -File "C:\測試 資料夾\Cleanup.ps1"' -Marker $marker
[xml]$xml=$xmlText
$n=New-Object Xml.XmlNamespaceManager($xml.NameTable);$n.AddNamespace('u','urn:schemas-microsoft-com:unattend')
$value=$xml.SelectSingleNode('//u:LocalAccount/u:Password/u:Value',$n).InnerText
Assert ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($value)) -ceq ($password+'Password')) 'XML password encoding preserves special characters and Chinese'
Assert (-not $xmlText.Contains($password)) 'answer XML does not contain literal password (encoding is reversible)'
Assert ($xml.SelectSingleNode('//u:LocalAccount/u:Name',$n).InnerText -eq 'my&user') 'XML escapes username without injection'
Assert ($xml.SelectSingleNode('//u:LocalAccount/u:Group',$n).InnerText -eq 'Administrators') 'local account administrator group specified'
Assert ($xml.SelectNodes('//u:AutoLogon|//u:SkipMachineOOBE|//u:SkipUserOOBE',$n).Count -eq 0) 'does not fake OOBE completion or configure autologon'
Assert ($xml.SelectSingleNode('//u:HideOnlineAccountScreens',$n).InnerText -eq 'true' -and $xml.SelectSingleNode('//u:HideWirelessSetupInOOBE',$n).InnerText -eq 'true') 'offline local account OOBE settings present'
Assert ($xml.SelectSingleNode('//u:settings',$n).GetAttribute('pass') -eq 'oobeSystem') 'answer uses oobeSystem pass'
$main=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Initialize-NUC.ps1'))
Assert ($main.Contains('/oobe /quit /unattend:') -and $main -notmatch '(?im)^\s*(Restart-Computer|shutdown)\b' -and $main -notmatch "ArgumentList.*(/reboot|/generalize)") 'sysprep preparation does not request restart or generalize'
Assert ($main.IndexOf("if(`$route -eq 'GuideAudit')") -lt $main.IndexOf("`$password=Read-Host")) 'SYSTEM returns before password collection'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-Init-Test-'+[guid]::NewGuid().ToString('N'))
$fakeWindows=Join-Path $fixture 'Windows';$stage=Join-Path $fixture 'Stage'
New-Item -ItemType Directory -Path $stage -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $moduleRoot 'OOBE-Library.ps1') -Destination $stage
$cleanup=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Cleanup-OOBE.ps1')) -replace '(?im)^#Requires -RunAsAdministrator\s*',''
[IO.File]::WriteAllText((Join-Path $stage 'Cleanup-OOBE.ps1'),$cleanup,(New-Object Text.UTF8Encoding($true)))
[IO.File]::WriteAllText((Join-Path $stage 'state.json'),(@{Marker=$marker;UserName='fixture'}|ConvertTo-Json))
[IO.File]::WriteAllText((Join-Path $stage 'answer.xml'),$xmlText)
$owned=Join-Path $fakeWindows 'Panther\unattend.xml';$oem=Join-Path $fakeWindows 'Panther\Unattend\unattend.xml'
New-Item -ItemType Directory -Path (Split-Path $owned -Parent),(Split-Path $oem -Parent) -Force|Out-Null
[IO.File]::WriteAllText($owned,$xmlText);[IO.File]::WriteAllText($oem,'<unattend><!--OEM answer--></unattend>')
& (Join-Path $stage 'Cleanup-OOBE.ps1') -WindowsPath $fakeWindows
Assert (-not(Test-Path (Join-Path $stage 'answer.xml')) -and -not(Test-Path $owned)) 'cleanup removes only owned source and owned cache'
Assert ([IO.File]::ReadAllText($oem) -eq '<unattend><!--OEM answer--></unattend>') 'cleanup preserves OEM answer'
$report=[IO.File]::ReadAllText((Join-Path $stage 'cleanup-result.json'))|ConvertFrom-Json
Assert ($report.Success -and @($report.Removed).Count -eq 2) 'cleanup produces accurate non-secret result'
Assert (-not([IO.File]::ReadAllText((Join-Path $stage 'cleanup-result.json'))).Contains($value)) 'cleanup report contains no encoded password'
$target=Join-Path $fixture 'JunctionTarget';$link=Join-Path $fixture 'JunctionLink'
New-Item -ItemType Directory -Path $target|Out-Null
New-Item -ItemType Junction -Path $link -Target $target|Out-Null
$rejected=$false;try{Assert-InitPlainPath (Join-Path $link 'answer.xml')}catch{$rejected=$true}
Assert $rejected 'cleanup path helper rejects junction ancestors'
Write-Host ('ALL PASS: '+$script:count+' isolated assertions; no real accounts, setup state, SSH or reboot changed. Fixture: '+$fixture)
