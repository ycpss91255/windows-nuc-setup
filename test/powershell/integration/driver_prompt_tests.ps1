#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('windows_setup_driver_prompt_'+[guid]::NewGuid().ToString('N'))
$core=Join-Path $fixture 'windows_setup/core'
New-Item -ItemType Directory -Path $core -Force|Out-Null
Copy-Item (Join-Path $root 'core/start_windows.ps1'),(Join-Path $root 'core/hardware.ps1') -Destination $core
[IO.File]::WriteAllText((Join-Path $core 'configure_nuc.ps1'),'param($DriverPackagePath);$fixtureState.SelectedDriver=$DriverPackagePath',[Text.UTF8Encoding]::new($true))
$fixtureState=@{Board='';PromptCount=0;Answers=$null;SelectedDriver=''};$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++}
function Get-CimInstance {param($ClassName,$ErrorAction);[pscustomobject]@{Product=$fixtureState.Board}}
function Read-Host {param($Prompt);$fixtureState.PromptCount++;if(-not $fixtureState.Answers.Count){throw '不應詢問此機型的 NUC 驅動包'};$answer=$fixtureState.Answers.Dequeue();return $answer}
$fixtureState.Board='Other Board';$fixtureState.PromptCount=0;$fixtureState.Answers=New-Object 'Collections.Generic.Queue[string]'
& (Join-Path $core 'start_windows.ps1')
Assert ($fixtureState.PromptCount -eq 0 -and -not $fixtureState.SelectedDriver) '一般電腦自動使用通用設定，不詢問 NUC 包'
$fixtureState.Board='NUC8i7HVB';$fixtureState.Answers.Enqueue('')
& (Join-Path $core 'start_windows.ps1')
Assert ($fixtureState.PromptCount -eq 1 -and -not $fixtureState.SelectedDriver) '支援 NUC 可直接 Enter 略過驅動'
Write-Host ('ALL PASS: '+$count+' driver prompt assertions; no host changes.')
. (Join-Path $root 'core/hardware.ps1')
$payload=Join-Path $fixture 'windows_driver_packages/nuc8';New-Item -ItemType Directory -Path $payload -Force|Out-Null
$manifest=@(foreach($name in @('Chipset.zip','SerialIO.zip','UCM.zip','GFX-Radeon.zip')){$item=Join-Path $payload $name;[IO.File]::WriteAllText($item,'fixture');@{File=$name;SHA256=(Get-FileHash $item -Algorithm SHA256).Hash}})
$manifest|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8
$fixtureState.Board='';$fixtureState.Answers.Enqueue('1');$fixtureState.Answers.Enqueue('NUC8i7HVB');$fixtureState.Answers.Enqueue('y')
$request=Select-SetupDriverRequest -PackageRoot (Split-Path $core -Parent) -Interactive $true
Assert ($request.ConfirmedBoard -eq 'NUC8i7HVB' -and $request.DriverPackagePath -eq $payload -and $request.Hardware.BoardProduct -eq '') '未知型號明確雙重確認後可選相鄰包，保留真偵測值'
$fixtureState.Board='';$fixtureState.Answers.Enqueue('g')
$request=Select-SetupDriverRequest -PackageRoot (Split-Path $core -Parent) -Interactive $true
Assert (-not $request.ConfirmedBoard -and -not $request.DriverPackagePath) '未知型號可明確選通用且不帶入驅動'
$before=$fixtureState.PromptCount
$request=Select-SetupDriverRequest -PackageRoot (Split-Path $core -Parent) -Interactive $false
Assert ($fixtureState.PromptCount -eq $before -and -not $request.DriverPackagePath) '非互動未知電腦不等待輸入也不擅自確認'
$fixtureState.Board='NUC8i7HVB';$fixtureState.Answers.Enqueue((Join-Path $fixture 'missing'));$fixtureState.Answers.Enqueue($payload)
$request=Select-SetupDriverRequest -PackageRoot (Join-Path $fixture 'elsewhere') -Interactive $true
Assert ($request.DriverPackagePath -eq $payload) '不存在的包可重新輸入有效路徑且真驗四檔雜湊'
$fixtureState.Answers.Enqueue('')
$request=Select-SetupDriverRequest -PackageRoot (Join-Path $fixture 'elsewhere') -Interactive $true
Assert (-not $request.DriverPackagePath) '找不到包可直接略過'
$fixtureState.Board='Other Board';$before=$fixtureState.PromptCount
$request=Select-SetupDriverRequest -PackageRoot (Split-Path $core -Parent) -Interactive $true
Assert ($fixtureState.PromptCount -eq $before -and -not $request.DriverPackagePath) '已知其他機型不提供手動強制選型'
$fixtureState.Board='';$request=Select-SetupDriverRequest -PackageRoot (Split-Path $core -Parent) -Interactive $false -DriverPackagePath $payload -PathSpecified -ConfirmedBoard NUC8i7HVB -ConfirmationComputer $env:COMPUTERNAME
Assert ($request.DriverPackagePath -eq $payload) '非互動可傳明確受控確認與有效包，不需讀輸入'