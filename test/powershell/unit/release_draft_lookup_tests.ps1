#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/release/driver_release_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
Assert ([bool](Get-Command Get-ReleaseDraftByTag -ErrorAction SilentlyContinue)) '草稿由完整分頁選取唯一 ID，而不是已發布專用 tag 端點'
$global:draftLookupMode='success';$global:draftLookupLists=0;$global:draftLookupReads=0
$global:draftLookupBody="繁體中文版本說明`r`n包含 `"引號`" 與換行"
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -ne 'api'){throw 'Read-only draft lookup must not mutate releases.'}
 if($words -contains '--paginate'){
  $global:draftLookupLists++
  if($global:draftLookupMode -eq 'list-fail'){$global:LASTEXITCODE=1;return}
  Assert (($words -join ' ') -match '@json') '分頁每列保留 JSON 型別而不只擷取 tag 字串'
  if($global:draftLookupMode -eq 'malformed-list'){return '{'}
  if($global:draftLookupMode -eq 'array-row'){return '[]'}
  for($i=1;$i -le 105;$i++){@{id=(1000+$i);tag_name=('other-'+$i);draft=$false;immutable=$true}|ConvertTo-Json -Compress}
  $row=@{id=42;tag_name='v1.2.3';draft=$true;immutable=$false}
  switch($global:draftLookupMode){missing{return}case-tag{$row.tag_name='V1.2.3'}string-id{$row.id='42'}bool-id{$row.id=$true}float-id{$row.id=42.5}zero-id{$row.id=0}published{$row.draft=$false}immutable{$row.immutable=$true}string-draft{$row.draft='true'}null-immutable{$row.immutable=$null}}
  $row|ConvertTo-Json -Compress
  if($global:draftLookupMode -eq 'duplicate'){$row.id=43;$row|ConvertTo-Json -Compress}
  return
 }
 if($words[1] -eq 'repos/example/repo/releases/42'){
  $global:draftLookupReads++
  if($global:draftLookupMode -eq 'id-fail'){$global:LASTEXITCODE=1;return}
  if($global:draftLookupMode -eq 'invalid-base64'){return '?'}
  $draft=@{id=42;tag_name='v1.2.3';draft=$true;immutable=$false;body=$global:draftLookupBody}
  switch($global:draftLookupMode){changed-id{$draft.id=43}changed-tag{$draft.tag_name='v1.2.4'}changed-state{$draft.draft=$false}changed-immutable{$draft.immutable=$true}string-read-id{$draft.id='42'}}
  $json=$draft|ConvertTo-Json -Compress
  if($global:draftLookupMode -eq 'array-id'){$json='['+$json+']'}
  if($global:draftLookupMode -eq 'invalid-utf8'){return [Convert]::ToBase64String([byte[]]@(255,254,255))}
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
  if($global:draftLookupMode -eq 'multiple-base64'){return $encoded,$encoded}
  return $encoded
 }
 throw ('Published-only tag endpoint must never read a draft: '+$words[1])
}
$draft=Get-ReleaseDraftByTag -Repository example/repo -Version v1.2.3
Assert ($draft.id -eq 42 -and $draft.body -ceq $global:draftLookupBody) '第二頁草稿用 ID 讀回，中文 CRLF 引號精確還原'
$lists=$global:draftLookupLists
$draft=Get-ReleaseDraftByTag -Repository example/repo -Version v1.2.3 -ExpectedId 42
Assert ($draft.id -eq 42 -and $global:draftLookupLists -eq $lists) '後續只讀固定 ID，不重新掃描或改選草稿'
foreach($mode in @('missing','case-tag','duplicate','list-fail','malformed-list','array-row','string-id','bool-id','float-id','zero-id','published','immutable','string-draft','null-immutable','id-fail','invalid-base64','invalid-utf8','multiple-base64','array-id','changed-id','changed-tag','changed-state','changed-immutable','string-read-id')){
 $global:draftLookupMode=$mode
 Reject {Get-ReleaseDraftByTag -Repository example/repo -Version v1.2.3} ('拒絕草稿查詢異常：'+$mode)
}
$global:draftLookupMode='success'
foreach($idValue in @($null,$true,42.5,'42',0,-1)){
 $lists=$global:draftLookupLists;$reads=$global:draftLookupReads
 Reject {Get-ReleaseDraftByTag -Repository example/repo -Version v1.2.3 -ExpectedId $idValue} '明確非法 ExpectedId 不得回退為重新發現'
 Assert ($global:draftLookupLists -eq $lists -and $global:draftLookupReads -eq $reads) '非法 ID 在任何遠端查詢前拒絕'
}
$global:draftLookupMode='id-fail';$lists=$global:draftLookupLists
Reject {Get-ReleaseDraftByTag -Repository example/repo -Version v1.2.3 -ExpectedId 42} '固定 ID 讀回失敗不重選草稿'
Assert ($global:draftLookupLists -eq $lists) '固定 ID 失敗沒有 fallback list'
Remove-Item Function:\gh
