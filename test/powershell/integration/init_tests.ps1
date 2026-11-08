#Requires -Version 5.1
$ErrorActionPreference='Stop'
$moduleRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init'))
. (Join-Path $moduleRoot 'oobe_library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++;Write-Host ('PASS: '+$Name)}
$marker='NUC-INIT-'+[guid]::NewGuid().ToString('N')
$password='a&<>"中文'
$xmlText=New-InitAnswerXml -UserName 'my&user' -Password $password -CleanupCommand 'powershell.exe -File "C:\測試 資料夾\Cleanup.ps1"' -Marker $marker
[xml]$xml=$xmlText
$n=New-Object Xml.XmlNamespaceManager($xml.NameTable);$n.AddNamespace('u','urn:schemas-microsoft-com:unattend')
$value=$xml.SelectSingleNode('//u:LocalAccount/u:Password/u:Value',$n).InnerText
$main=[IO.File]::ReadAllText((Join-Path $moduleRoot 'initialize_nuc.ps1'))
Assert ($main.Contains('/oobe /quit /unattend:') -and $main -notmatch '(?im)^\s*(Restart-Computer|shutdown)\b' -and $main -notmatch "ArgumentList.*(/reboot|/generalize)") 'sysprep preparation does not request restart or generalize'
Assert ($main.IndexOf("Invoke-InitProvisioningEntry") -lt $main.IndexOf("`$password=Read-Host")) 'guarded provisioning entry runs before legacy audit password collection'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-Init-Test-'+[guid]::NewGuid().ToString('N'))
$fakeWindows=Join-Path $fixture 'Windows';$stage=Join-Path $fixture 'Stage'
New-Item -ItemType Directory -Path $stage -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $moduleRoot 'oobe_library.ps1') -Destination $stage
$cleanup=[IO.File]::ReadAllText((Join-Path $moduleRoot 'cleanup_oobe.ps1')) -replace '(?im)^#Requires -RunAsAdministrator\s*',''
[IO.File]::WriteAllText((Join-Path $stage 'cleanup_oobe.ps1'),$cleanup,(New-Object Text.UTF8Encoding($true)))
[IO.File]::WriteAllText((Join-Path $stage 'state.json'),(@{Marker=$marker;UserName='fixture'}|ConvertTo-Json))
[IO.File]::WriteAllText((Join-Path $stage 'answer.xml'),$xmlText)
$owned=Join-Path $fakeWindows 'Panther\unattend.xml';$oem=Join-Path $fakeWindows 'Panther\Unattend\unattend.xml'
New-Item -ItemType Directory -Path (Split-Path $owned -Parent),(Split-Path $oem -Parent) -Force|Out-Null
[IO.File]::WriteAllText($owned,$xmlText);[IO.File]::WriteAllText($oem,'<unattend><!--OEM answer--></unattend>')
& (Join-Path $stage 'cleanup_oobe.ps1') -WindowsPath $fakeWindows
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
