#Requires -Version 5.1
param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[switch]$EnableImmutable,[switch]$EnablePages)
$ErrorActionPreference='Stop'
# Administrative setup only; regular tag jobs use GITHUB_TOKEN and verify the published release.
if($EnableImmutable){& gh api -X PUT ('repos/'+$Repository+'/immutable-releases');if($LASTEXITCODE -ne 0){throw '啟用 immutable releases 失敗。'}}
if($EnablePages){& gh api -X POST ('repos/'+$Repository+'/pages') -f build_type=workflow;if($LASTEXITCODE -ne 0){throw '建立 Pages 失敗；已有站台請先查核既有設定。'}}
$policy=(& gh api ('repos/'+$Repository+'/immutable-releases'))|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw '需要管理員讀取權限確認 immutable releases；一般 GITHUB_TOKEN 不具此權限。'}
$pages=(& gh api ('repos/'+$Repository+'/pages'))|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw '無法讀取 Pages 設定。'}
[pscustomobject]@{Repository=$Repository;ImmutableEnabled=$policy.enabled;PagesBuildType=$pages.build_type;PagesUrl=$pages.html_url;CheckedAt=[DateTime]::UtcNow.ToString('o')}
