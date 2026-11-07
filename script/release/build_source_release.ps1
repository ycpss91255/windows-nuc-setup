#Requires -Version 5.1
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Version,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [string]$PackageRoot=([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))),
 [ValidatePattern('^(HEAD|[a-fA-F0-9]{40})$')][string]$Revision='HEAD'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'release.ps1')
$null=Get-ReleaseVersion $Version
$PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path
$commit=(& git -C $PackageRoot rev-parse --verify ($Revision+'^{commit}'))
if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-fA-F0-9]{40}$'){throw '無法確認來源提交。'}
$files=@(& git -C $PackageRoot -c core.quotepath=false ls-tree -r --name-only $commit)
if($LASTEXITCODE -ne 0 -or -not $files.Count){throw '無法讀取提交中的來源檔案。'}
foreach($path in $files){
 $normalized=$path.Replace('\','/')
 if($normalized -match '(^|/)(Reports|TestResults|\.ssh|NUC-Init|Private|LocalConfig)(/|$)' -or
    $normalized -match '(?i)\.(exe|dll|zip|7z|rar|msi|msix|cab|iso|pfx|pem|key)$' -or
    $normalized -match '(?i)(^|/)(answer\.xml|unattend\.xml|autounattend\.xml|runtime\.json|owner\.json|state\.json|cleanup-result\.json|known_hosts.*|id_rsa.*|id_ed25519.*)$' -or
    $normalized -match '(?i)(^|/)[^/]*-(Result|Verification|Progress)\.json$'){
  throw ('拒絕將執行資料、秘密或安裝二進位放入來源版本包：'+$path)
 }
}
foreach($required in @('init.cmd','windows.cmd','readme.md')){
 if($required -notin $files){throw ('來源提交缺少必要檔案：'+$required)}
}
$declared=(& git -C $PackageRoot show ($commit+':.version'))
if($LASTEXITCODE -ne 0 -or ($declared -join "`n").Trim() -cne $Version){throw '.version 與標籤不一致。'}
$changelog=(& git -C $PackageRoot show ($commit+':doc/changelog/changelog.md'))
if($LASTEXITCODE -ne 0){throw '來源提交缺少變更紀錄。'}
$body=Get-ReleaseNotes $Version ($changelog -join "`n")
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$notes=Join-Path $output 'release_notes.md'
if(Test-Path -LiteralPath $notes){throw '版本說明檔已存在，未覆寫。'}
if(-not(Test-Path -LiteralPath $output)){New-Item -ItemType Directory -Path $output|Out-Null}
[IO.File]::WriteAllText($notes,$body,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Version=$Version;Commit=$commit;FileCount=$files.Count;NotesPath=$notes;Prerelease=(Get-ReleaseVersion $Version).Prerelease}