#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$caught=$null;try{& $Action|Out-Null}catch{$caught=$_};Assert ($caught -and $caught.Exception -isnot [Management.Automation.ParameterBindingException] -and $caught.Exception.Message.Contains($Expected)) $Name}
function Clone($Value){$Value|ConvertTo-Json -Depth 25|ConvertFrom-Json}
$fixture=Join-Path $env:TEMP ('hardware_gaps_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
Assert ((Test-SetupAdministrator) -is [bool]) '實際權杖唯讀查詢回傳布林，不提權'
Assert ((Test-SetupInteractiveHost) -is [bool]) '實際主控台唯讀查詢不啟動互動程序'
Assert ($null -eq (Get-SetupDriverProfile -ProfilesRoot (Join-Path $fixture 'missing'))) '不存在的registry不猜測其他機型'
$registry=Join-Path $fixture 'registry';$profileDir=Join-Path $registry 'safe_board';[void][IO.Directory]::CreateDirectory($profileDir)
foreach($board in @(' spaced ','bad\board',"bad`nboard")){
 @{SchemaVersion=1;ProfileId='safe_board';PackageDirectory='safe_board';Architecture='x64';SupportedBoards=@($board)}|ConvertTo-Json|Set-Content (Join-Path $profileDir 'profile.json') -Encoding UTF8
 Reject {Get-SetupDriverProfile -ProfilesRoot $registry -BoardProduct anything} '板號無效' ('拒絕非可攜板號 '+$board.Replace("`n",'newline'))
}
$official=Get-Content (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$base=@{SchemaVersion=2;Packages=@(($official.Packages|Where-Object Id -eq radeon_vega_m))}|ConvertTo-Json -Depth 25|ConvertFrom-Json
foreach($bad in @('BAD ID','')){$m=Clone $base;$m.Packages[0].Id=$bad;Reject {Get-SetupDriverManifestEntries $m} '識別或版本' '拒絕套件識別格式不符'}
$m=Clone $base;$m.Packages[0].PackageVersion='latest';Reject {Get-SetupDriverManifestEntries $m} '識別或版本' '版號不能寫latest'
$m=Clone $base;$m.Packages[0].Drivers[0].HardwareIds=@();Reject {Get-SetupDriverManifestEntries $m} '明確硬體' '沒有明確硬體ID不能安裝'
$m=Clone $base;$m.Packages[0].Extensions=@($m.Packages[0].Extensions[0],$m.Packages[0].Extensions[0]);Reject {Get-SetupDriverManifestEntries $m} 'Extension 識別重複' '延伸組件不得重複'
foreach($field in @('DriverVersion','Provider','Architecture','MinimumBuild','HardwareIds')){$m=Clone $base;switch($field){DriverVersion{$m.Packages[0].Extensions[0].DriverVersion='bad'} Provider{$m.Packages[0].Extensions[0].Provider=''} Architecture{$m.Packages[0].Extensions[0].Architecture='x86'} MinimumBuild{$m.Packages[0].Extensions[0].MinimumBuild=1} HardwareIds{$m.Packages[0].Extensions[0].HardwareIds=@()}};Reject {Get-SetupDriverManifestEntries $m} 'Extension 裝置規格' ('延伸規格拒絕 '+$field)}
$m=Clone $base;$m.Packages[0].Extensions[0].HardwareIds=@('SWC\NOT_A_PHYSICAL_EXTENSION');Reject {Get-SetupDriverManifestEntries $m} 'Extension 硬體' '延伸關聯必須實體硬體ID'
$m=Clone $base;$m.SchemaVersion=99;Reject {Get-SetupDriverManifestEntries $m} '不支援' '未知schema不可退回舊格式'
Reject {Get-SetupDriverManifestEntries @(@{File='a.zip';SHA256=('a'*64)})} '四個' '舊包不完整時不可當四包成功'
$m=Clone $base;$m.Packages[0].File='../outside.zip';Reject {Get-SetupDriverManifestEntries $m} '清單格式' '封存檔不能跳出資料夾'
$payload=Join-Path $fixture 'windows_driver_packages/nuc8';[void][IO.Directory]::CreateDirectory($payload)
$entries=@(foreach($name in @('Chipset.zip','SerialIO.zip','UCM.zip','GFX-Radeon.zip')){[IO.File]::WriteAllText((Join-Path $payload $name),'inert fixture');@{File=$name;SHA256=(Get-FileHash (Join-Path $payload $name)).Hash}})
$entries|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
$identity=@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')};$identity|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8
$h=Get-SetupHardwareProfile -BoardProduct NUC8i7HVB -DriverPackagePath $payload
$identity.Architecture='arm64';$identity|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8;Reject {Test-SetupDriverPayload $h $payload} '機型或架構' '舊包不同架構不得跨平台'
$identity.Architecture='x64';$identity|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8
Remove-Item -LiteralPath (Join-Path $payload 'UCM.zip');Reject {Test-SetupDriverPayload $h $payload} '缺少驅動' '實際缺少封存檔保留錯誤';[IO.File]::WriteAllText((Join-Path $payload 'UCM.zip'),'inert fixture')
$same=New-SetupDriverSelection -PackageRoot $payload -DriverPackagePath $payload;Assert ($same.RelativePath -eq '.') '同目錄可攜續跑位置記為點'
$result=Join-Path $fixture 'result.json';Assert (-not(Get-SetupSavedDriverSelection -ResultPath $result)) '無紀錄不沿用其他來源'
Assert ((Get-SetupSavedHardwareConfirmation -ResultPath $result).Count -eq 0) '無紀錄不創造手動機型確認'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$record=@{Computer=$env:COMPUTERNAME;UserSID=$sid;HardwareProfile=@{DriverPackagePath='';ConfirmedBoard='NUC8i7HVB';ConfirmationComputer='different-machine'}};$record|ConvertTo-Json -Depth 8|Set-Content $result -Encoding UTF8
Assert (-not(Get-SetupSavedDriverSelection -ResultPath $result)) '明確未選包維持略過'
Reject {Get-SetupSavedHardwareConfirmation -ResultPath $result} '不屬於目前電腦' '不沿用另一電腦的手動確認'
$record.HardwareProfile.DriverPackagePath=$payload;$record.HardwareProfile.DriverSelection=$same
foreach($property in @('SchemaVersion','PackageSHA256','ManifestSHA256')){$bad=Clone $record;$bad.HardwareProfile.DriverSelection.$property='invalid';$bad|ConvertTo-Json -Depth 8|Set-Content $result -Encoding UTF8;Reject {Get-SetupSavedDriverSelection -ResultPath $result} '紀錄格式' ('續跑身分拒絕 '+$property)}
$bad=Clone $record;$bad.HardwareProfile.DriverSelection.RelativePath='';$bad.HardwareProfile.DriverSelection.AbsolutePath='not-rooted';$bad|ConvertTo-Json -Depth 8|Set-Content $result -Encoding UTF8;Reject {Get-SetupSavedDriverSelection -ResultPath $result} '找不到原選擇' '不存在/非絕對位置不亂搜尋其他磁碟'
# Native UI/CIM boundaries only; every decision below is the real shared source.
$script:board='';function Get-CimInstance {param($ClassName,$ErrorAction) if($script:board){[pscustomobject]@{Product=$script:board}}}
$script:answers=[Collections.Generic.Queue[string]]::new();function Read-Host {param($Prompt) if(-not $script:answers.Count){throw 'unexpected interactive prompt'};$script:answers.Dequeue()}
$tool=Join-Path $fixture 'tool';[void][IO.Directory]::CreateDirectory($tool)
foreach($answer in @('r','g')){$script:answers.Enqueue($answer)};$request=Select-SetupDriverRequest -PackageRoot $tool -Interactive $true
Assert (-not $request.DriverPackagePath -and $request.Hardware.DetectionError) '查無主機板可重試後選通用，仍保留偵測錯誤'
foreach($answer in @('1','not-confirmed','2','NUC8i7HNB','y')){$script:answers.Enqueue($answer)};$request=Select-SetupDriverRequest -PackageRoot $tool -Interactive $true
Assert ($request.ConfirmedBoard -eq 'NUC8i7HNB' -and $request.DriverPackagePath -eq $payload) '錯誤確認不放行，明確第二板號確認後才選合法包'
$script:board='NUC8i7HVB';foreach($answer in @('p',(Join-Path $fixture 'missing'),$payload)){$script:answers.Enqueue($answer)};$request=Select-SetupDriverRequest -PackageRoot $tool -Interactive $true
Assert ($request.DriverPackagePath -eq $payload -and $script:answers.Count -eq 0) '自訂位置錯誤可重新輸入且不固定磁碟'
Reject {Select-SetupDriverRequest -PackageRoot $tool -DriverPackagePath (Join-Path $fixture 'missing') -PathSpecified -Interactive $false} 'package.json' '非互動錯包保留真失敗而不詢問或偷偷略過'
