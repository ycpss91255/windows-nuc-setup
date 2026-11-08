#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Passed,[string]$Name){Microsoft.PowerShell.Utility\Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_payload_progress_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
$entries=@(foreach($i in 1..4){$file="driver_$i.zip";$path=Join-Path $fixture $file;[IO.File]::WriteAllText($path,"inert fixture $i");@{File=$file;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}})
$entries|ConvertTo-Json|Set-Content (Join-Path $fixture 'manifest.json') -Encoding UTF8
$hardware=[pscustomobject]@{IsNuc8=$true;DriverProfileId=''}
$script:events=[Collections.Generic.List[string]]::new();$script:hashes=0;$script:throwNative=$false
function Write-Host {param($Object,$ForegroundColor) $script:events.Add([string]$Object)}
function Get-FileHash {
 param($LiteralPath,$Algorithm,$ErrorAction)
 $script:hashes++
 Assert ($script:events.Count -eq (2*$script:hashes-1) -and $script:events[-1].Contains([IO.Path]::GetFileName($LiteralPath)) -and $script:events[-1].Contains(($script:hashes.ToString()+'/4'))) '原生hash尚未開始前，使用者已看見目前檔案及步序'
 if($script:throwNative){throw [IO.IOException]::new('controlled native read failure')}
 Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm -ErrorAction Stop
}
$result=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $fixture -AllowLegacyManifest
Assert ($result.Status -ceq 'Passed' -and $result.Count -eq 4 -and $script:events.Count -eq 8 -and $script:events[-1].Contains('4/4')) '每個真SHA256成功後才顯示完成，完整四包才Passed'
$entries[1].SHA256='0'*64;$entries|ConvertTo-Json|Set-Content (Join-Path $fixture 'manifest.json') -Encoding UTF8
$script:events.Clear();$script:hashes=0;$failure=$null
try{Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $fixture -AllowLegacyManifest|Out-Null}catch{$failure=$_}
Assert ($failure -and $failure.Exception.Message.Contains('driver_2.zip') -and $script:hashes -eq 2 -and $script:events.Count -eq 3) '第二包hash錯誤指出檔名並停止，沒有假完成或繼續下一包'
$script:events.Clear();$script:hashes=0;$script:throwNative=$true;$failure=$null
try{Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $fixture -AllowLegacyManifest|Out-Null}catch{$failure=$_}
Assert ($failure -and $failure.Exception.Message.Contains('driver_1.zip') -and $failure.Exception.Message.Contains('controlled native read failure') -and $script:events.Count -eq 1) '原生讀檔失敗保留根因與檔名，不能顯示已完成'
