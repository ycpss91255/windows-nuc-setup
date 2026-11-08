#Requires -Version 5.1
$ErrorActionPreference='Stop'
$moduleRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init'))
. (Join-Path $moduleRoot 'oobe_library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++;Write-Host ('PASS: '+$Name)}
Assert ((Get-InitRoute 'S-1-5-18' 'IMAGE_STATE_UNDEPLOYABLE' $true $false) -eq 'OobeProvisioning') 'SYSTEM routes to guarded provisioning without audit shortcut'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'IMAGE_STATE_UNDEPLOYABLE' $true $true) -eq 'RejectBuiltinAdministrator') 'unfinished image without native facts never authorizes OOBE preparation'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'unexpected' $true $true) -eq 'RejectBuiltinAdministrator') 'unknown setup state cannot prepare account'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-500' 'IMAGE_STATE_COMPLETE' $true $true) -eq 'RejectBuiltinAdministrator') 'normal built-in administrator is not audit'
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-1001' 'IMAGE_STATE_COMPLETE' $true $true) -eq 'DesktopReady') 'formal account desktop routes to Windows guidance only'
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

Write-Host ('ALL PASS: '+$script:count+' Init unit assertions; no accounts or files changed.')

$facts=@{ReadSucceeded=$true;Build=26200;ProductType=1;IsWinPE=$false;OobeApiSucceeded=$true;OobeComplete=$false;SetupInProgress=0;OobeInProgress=0;OobeProcessInSession=$false;SetupProcessInSession=$false;ProfileMatches=$true;LocalBuiltin=$true}
$builtin='S-1-5-21-1-2-3-500'
Assert ((Get-InitRoute $builtin 'IMAGE_STATE_UNDEPLOYABLE' $true $true $facts) -ceq 'PrepareOobe') 'multiple current facts authorize controlled preparation without claiming Audit mode'
foreach($entry in @(@('ReadSucceeded',$false),@('Build',22000),@('ProductType',3),@('IsWinPE',$true),@('OobeApiSucceeded',$false),@('OobeComplete',$true),@('SetupProcessInSession',$true),@('OobeProcessInSession',$true),@('ProfileMatches',$false),@('LocalBuiltin',$false))){$bad=$facts.Clone();$bad[$entry[0]]=$entry[1];Assert ((Get-InitRoute $builtin 'IMAGE_STATE_UNDEPLOYABLE' $true $true $bad) -ceq 'RejectUnknownSetupState') ('conflicting/missing native fact rejected: '+$entry[0])}
Assert ((Get-InitRoute $builtin 'IMAGE_STATE_COMPLETE' $true $true $facts) -ceq 'RejectUnknownSetupState') 'complete image versus incomplete native OOBE is contradictory'
Assert ((Get-InitRoute $builtin 'UNKNOWN' $true $true $facts) -ceq 'RejectUnknownSetupState') 'unknown ImageState cannot prepare'
Assert ((Get-InitRoute $builtin 'IMAGE_STATE_UNDEPLOYABLE' $true $false $facts) -ceq 'RejectUnknownSetupState') 'remote or unowned desktop cannot prepare'
$desktop=$facts.Clone();$desktop.LocalBuiltin=$false;$desktop.OobeComplete=$true
Assert ((Get-InitRoute 'S-1-5-21-1-2-3-1001' 'IMAGE_STATE_COMPLETE' $true $true $desktop) -ceq 'DesktopReady') 'completed formal desktop only receives windows.cmd guidance'
Assert ((Get-InitRoute $builtin 'IMAGE_STATE_UNDEPLOYABLE' $true $true $desktop) -ceq 'RejectUnknownSetupState') 'completed OOBE never returns to new-account preparation'
Assert ((Get-InitRoute $builtin 'IMAGE_STATE_UNDEPLOYABLE' $false $true $facts) -ceq 'RejectUnknownSetupState') 'builtin preparation requires an existing administrator token'
