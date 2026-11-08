#Requires -Version 5.1
param([string]$SshScriptPath,[string]$ExpectedUserSID,[string]$ResumeStatePath)
$ErrorActionPreference='Stop'
if($SshScriptPath){$SshScriptPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SshScriptPath)}
. (Join-Path $PSScriptRoot 'oobe_library.ps1')
. (Join-Path $PSScriptRoot 'provisioning_library.ps1')
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stageRoot=Join-Path $env:ProgramData 'windows_setup_init'
if(Invoke-InitProvisioningEntry -SourceRoot $sourceRoot -StageRoot $stageRoot -ResumeStatePath $ResumeStatePath -ExpectedUserSID $ExpectedUserSID){return}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$sid=$identity.User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $sid){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$imageState=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction SilentlyContinue).ImageState
$desktopOwned=$false
if($sid -ne 'S-1-5-18'){
 $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
 $explorers=@(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"|Where-Object {$_.SessionId -eq $session})
 foreach($process in $explorers){if((Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid).Sid -eq $sid){$desktopOwned=$true}}
}
$route=Get-InitRoute -Sid $sid -ImageState $imageState -IsAdministrator $admin -DesktopOwned $desktopOwned
Write-Host ('=== Init：Windows '+[Environment]::OSVersion.Version+'；階段 '+$route+' ===') -ForegroundColor Cyan
if($route -eq 'ElevationRequired'){
 Write-Host '請允許目前帳號的管理員權限；不可輸入另一個管理員帳號。'
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$sid+"'"
 if($SshScriptPath){$command+=" -SshScriptPath '"+$SshScriptPath.Replace("'","''")+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
 return
}
if($route -eq 'RejectBuiltinAdministrator'){throw '目前是一般 Administrator 桌面，不是可確認的稽核模式。請登入正式的本機管理員帳號再執行 Init。'}
if($route -eq 'RejectUnknownSetupState'){throw ('無法確認目前是稽核模式或正式使用者桌面，未變更設定。ImageState='+$imageState)}
if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw '本入口僅支援 x64 Windows，請用 64 位元 Windows PowerShell。'}
if($route -eq 'DesktopReady'){
 $user=Get-LocalUser -SID $identity.User -ErrorAction Stop
 if(-not $user.Enabled){throw '目前本機使用者未啟用。'}
 Write-Host ('目前正式帳號：'+$user.Name+'；帳號已就緒，不重設密碼。請直接執行 windows.cmd，SSH 由第 4 階段安裝。') -ForegroundColor Green
 return
}
# Audit is inferred conservatively. ImageState alone is not proof of audit mode.
if(-not $desktopOwned){throw '請在稽核模式 Administrator 桌面執行，不接受遠端或非桌面工作階段。'}
if((Read-Host '僅供已由其他管理流程進入稽核模式的維護者：確認目前確為稽核模式請輸入 AUDIT') -cne 'AUDIT'){throw '未確認稽核模式，本次未更改設定。'}
if(Get-Process sysprep -ErrorAction SilentlyContinue){throw 'Sysprep 對話框或程序仍開啟。請先按「取消」關閉，勿同時執行兩份，再重跑 init.cmd。'}
$sMode=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue).SkuPolicyRequired
if($sMode -eq 1){throw 'S mode 不支援本工具使用的首次登入清理指令，本次未建立設定。'}
$sysprep=Join-Path $env:WINDIR 'System32\Sysprep\Sysprep.exe'
if(-not(Test-Path -LiteralPath $sysprep -PathType Leaf)){throw '找不到 Sysprep，未建立設定。'}
$existingAnswer=@(Get-InitAnswerCandidates -WindowsPath $env:WINDIR|Where-Object {Test-Path -LiteralPath $_})
$answerRegistry=(Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue).UnattendFile
if($answerRegistry){$existingAnswer+=@([Environment]::ExpandEnvironmentVariables([string]$answerRegistry))}
if($existingAnswer.Count){throw ('已有 Windows answer file 或快取設定，可能來自 Windows 安裝本身；本工具保守停止，請先確認用途，勿任意刪除：'+($existingAnswer -join '；'))}
$stage=Join-Path $env:ProgramData 'NUC-Init'
Assert-InitPlainPath $stage
if(Test-Path -LiteralPath $stage){throw ('已有 Init 暫存資料，請先查看 '+$stage+'，不要重複產生帳號設定。')}
$existingNames=@((Get-LocalUser).Name)
$name=Read-Host '新的本機管理員帳號（最多 20 字；不可使用現有帳號或 Windows 保留符號）'
if(-not(Test-InitUserName -Name $name -ExistingNames $existingNames)){throw '帳號名稱無效、已存在或保留，請重新執行並使用另一個名稱。'}
$password=Read-Host '新帳號密碼' -AsSecureString
$confirm=Read-Host '再次輸入密碼' -AsSecureString
$plain=$null;$second=$null;$ptr=[IntPtr]::Zero;$ptr2=[IntPtr]::Zero
try{
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($password);$plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 $ptr2=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirm);$second=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr2)
 if(-not(Test-InitPassword $plain) -or $plain -cne $second){throw '密碼須為 1 至 127 字、不含控制字元，且兩次必須相同。本次未寫入設定。'}
 Write-Host '將在本機建立僅系統與管理員可讀的暫存 answer file。其密碼編碼可還原，不是加密；首次登入後會清理本工具檔案。密碼不寫入 USB。' -ForegroundColor Yellow
 Write-Host ('準備建立帳號 '+$name+' 並重新準備初始設定；不會自動重開。') -ForegroundColor Cyan
 New-Item -ItemType Directory -Path $stage|Out-Null
 Protect-InitFolder -Path $stage
 foreach($file in @('oobe_library.ps1','cleanup_oobe.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage $file)}
 $marker='NUC-INIT-'+[guid]::NewGuid().ToString('N')
 $cleanup='"'+(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')+'" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $stage 'cleanup_oobe.ps1')+'"'
 $xml=New-InitAnswerXml -UserName $name -Password $plain -CleanupCommand $cleanup -Marker $marker
 $utf8=New-Object Text.UTF8Encoding($false)
 [IO.File]::WriteAllText((Join-Path $stage 'state.json'),(@{Marker=$marker;UserName=$name;PreparedAt=(Get-Date).ToString('o')}|ConvertTo-Json),$utf8)
 [IO.File]::WriteAllText((Join-Path $stage 'answer.xml'),$xml,$utf8)
}catch{
 if(Test-Path -LiteralPath (Join-Path $stage 'state.json')){
  try{& (Join-Path $stage 'cleanup_oobe.ps1')}catch{Write-Warning '準備失敗且暫存檔未完全清理，請檢查受保護的 NUC-Init 資料夾。'}
 }
 throw
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 if($ptr2 -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2)}
 $plain=$null;$second=$null;$xml=$null;$password.Dispose();$confirm.Dispose()
}
Write-Host '準備下一次 OOBE；不執行 generalize，也不自動重新開機。' -ForegroundColor Cyan
try{
 $process=Start-Process -FilePath $sysprep -ArgumentList ('/oobe /quit /unattend:"'+(Join-Path $stage 'answer.xml')+'"') -Wait -PassThru -WindowStyle Hidden
 if($process.ExitCode -ne 0){throw ('Sysprep 失敗，退出碼 '+$process.ExitCode+'。請查看 Windows\System32\Sysprep\Panther 記錄，不要直接重新安裝或反覆重試。')}
}catch{
 try{& (Join-Path $stage 'cleanup_oobe.ps1')}catch{Write-Warning '失敗後的暫存檔清理未完成，請檢查受保護的 NUC-Init 資料夾。'}
 throw
}
Write-Host '帳號設定已準備完成，請現在手動重新啟動；不要再開其他應用程式。' -ForegroundColor Green
Write-Host '完成剩餘地區／隱私等初始設定，用剛才的本機帳號登入，直接執行 windows.cmd；不需再跑 Init，SSH 由 Windows 第 4 階段處理。'
Write-Host ('若初始設定失敗或取消，密碼暫存仍可能存在於 '+$stage+'；不可忽略，請先檢查 cleanup-result.json 與受保護的 answer.xml。')
