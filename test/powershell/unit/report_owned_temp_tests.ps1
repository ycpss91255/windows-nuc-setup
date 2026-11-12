#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$helper=Join-Path $root 'script/report/owned_temp.ps1'
if(Test-Path -LiteralPath $helper){. $helper; $script:shared=$true}else{. (Join-Path $root 'script/report/portal.ps1');$script:shared=$false}
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
function New-TestOwner {if($script:shared){return New-ReportOwnedTemp};return [pscustomobject]@{Path=(New-PortalOwnedTemporaryDirectory);Nonce='legacy-path-only'}}
function Remove-TestOwner($Owner){if($script:shared){Remove-ReportOwnedTemp -Handle $Owner}else{Remove-PortalOwnedTemporaryDirectory $Owner.Path}}
$owner=New-TestOwner
$forged=[pscustomobject]@{Path=$owner.Path;Root=$owner.Root;Nonce=$owner.Nonce}
Refuse {Remove-TestOwner $forged} '偽造 handle 即使有相同路徑也不可清理'
Assert (Test-Path -LiteralPath $owner.Path -PathType Container) '拒絕偽造後自建目錄仍存在'
Remove-TestOwner $owner
Assert (-not (Test-Path -LiteralPath $owner.Path)) '真 handle 成功清理'
Refuse {Remove-TestOwner $owner} '已撤銷 handle 不可重用'
$owner=New-TestOwner
$nonce=$owner.Nonce;$owner.Nonce='altered'
Refuse {Remove-TestOwner $owner} '竄改 nonce 必須拒絕'
$owner.Nonce=$nonce
$base=$owner.Root;$owner.Root=[IO.Path]::GetPathRoot($base)
Refuse {Remove-TestOwner $owner} '竄改暫存根目錄必須拒絕'
$owner.Root=$base
. $helper
Assert (Test-Path -LiteralPath $owner.Path -PathType Container) '重新載入 helper 不遺失已簽發 handle'
$other=New-TestOwner
$sentinel=Join-Path $other.Path 'sentinel';[IO.File]::WriteAllText($sentinel,'keep')
$link=Join-Path $owner.Path 'junction'
New-Item -ItemType Junction -Path $link -Target $other.Path|Out-Null
Refuse {Remove-TestOwner $owner} '後代 junction 必須拒絕並保留'
Assert ((Test-Path -LiteralPath $owner.Path) -and (Test-Path -LiteralPath $sentinel)) '拒絕後本人目錄及外部 sentinel 仍存在'
[IO.Directory]::Delete($link)
Remove-TestOwner $owner
Remove-TestOwner $other
Assert (-not (Test-Path -LiteralPath $owner.Path) -and -not (Test-Path -LiteralPath $other.Path)) '移除連結後已簽發目錄可清理'
$owner=New-TestOwner
$other=New-TestOwner
$sentinel=Join-Path $other.Path 'sentinel';[IO.File]::WriteAllText($sentinel,'keep')
$held=$owner.Path+'_held'
if([IO.Path]::GetDirectoryName($held) -cne $owner.Root -or (Test-Path -LiteralPath $held)){throw 'fixture move target is not a new direct TEMP child'}
[IO.Directory]::Move($owner.Path,$held)
New-Item -ItemType Junction -Path $owner.Path -Target $other.Path|Out-Null
Refuse {Remove-TestOwner $owner} '替換 owner 本身為 junction 必須拒絕'
Assert ((Test-Path -LiteralPath $sentinel) -and (Test-Path -LiteralPath $held)) '替換連結後不得刪除目標或原始目錄'
[IO.Directory]::Delete($owner.Path)
[IO.Directory]::Move($held,$owner.Path)
Remove-TestOwner $owner
Remove-TestOwner $other
Assert (-not (Test-Path -LiteralPath $owner.Path)) '恢復原目錄後合法清理'
