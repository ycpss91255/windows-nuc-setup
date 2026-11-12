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
