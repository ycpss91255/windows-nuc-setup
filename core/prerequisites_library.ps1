#Requires -Version 5.1
# Shared complete guard; the CLI supplies only the real native SID.
function Assert-SetupWindowsPrerequisites {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][ValidateNotNull()][Security.Principal.SecurityIdentifier]$UserSid,[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceRoot)
 if(-not [Environment]::Is64BitProcess){throw '請用 64 位元 Windows PowerShell 執行。'}
 $os=Get-CimInstance Win32_OperatingSystem
 if([int]$os.BuildNumber -lt 22621){throw '需要 Windows 11 22H2 或更新版本。'}
 $edition=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
 if($edition -notmatch 'Professional|Enterprise|Education'){throw ('此套偏好原則需要 Windows 專業版或企業/教育版，目前：'+$edition)}

 if($UserSid.Value -eq 'S-1-5-18' -or $UserSid.Value -match '-500$'){throw 'Windows 流程不可在 SYSTEM 或稽核用內建 Administrator 執行；請先用 Init 建立正式帳號並登入。'}
 $imageState=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Stop).ImageState
 if($imageState -ne 'IMAGE_STATE_COMPLETE'){throw 'Windows 初始設定尚未完成；請完成 Init／OOBE 並登入正式帳號後再執行 Windows。'}
 $local=Get-LocalUser -SID $UserSid -ErrorAction Stop
 if($null -eq $local -or $local.SID.Value -cne $UserSid.Value -or -not $local.Enabled){throw '目前本機帳號不存在、不符或未啟用。'}
 $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
 $explorers=@(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"|Where-Object {$session -eq 0 -or $_.SessionId -eq $session})
 $owners=@($explorers|ForEach-Object {$owner=Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop;if(($owner.ReturnValue -is [uint32] -or $owner.ReturnValue -is [int]) -and $owner.ReturnValue -eq 0){$owner.Sid}})
 if($UserSid.Value -notin $owners){throw '請以目前登入桌面的本機管理員帳號執行，不可用另一個管理員帳號提權。'}
 foreach($cmd in @('wt.exe','winget.exe')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw ('缺少 '+$cmd+'；請先安裝 Windows Terminal / App Installer。')}}
 . (Join-Path $SourceRoot 'modules/desktop/desktop_safety.ps1')
 Assert-DesktopSourceLocation -SourceRoot $SourceRoot -DesktopRoots @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))
}
