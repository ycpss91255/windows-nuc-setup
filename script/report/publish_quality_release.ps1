#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$PublicDirectory,[Parameter(Mandatory=$true)][string]$Version,[Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$NotesPath,[Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[switch]$Prerelease)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../test/test_report.ps1')
$snapshot=Get-Content (Join-Path $PublicDirectory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-TestReportSnapshot -Report $snapshot -Release
if($snapshot.Commit -cne $Commit -or $snapshot.Version -cne $Version -or $snapshot.RefName -cne $Version){throw '發布版本與測試來源不一致。'}
$files=@('index.html','summary.json','summary.md','junit.xml','unit.svg','integration.svg','system.svg','coverage.svg')
$hashes=@(foreach($name in $files){[ordered]@{Name=$name;SHA256=(Get-FileHash -LiteralPath (Join-Path $PublicDirectory $name)).Hash.ToLowerInvariant()}})
$quality=Join-Path $PublicDirectory 'quality.json';Copy-Item -LiteralPath (Join-Path $PublicDirectory 'summary.json') -Destination $quality
$manifest=[ordered]@{SchemaVersion=1;Version=$Version;Commit=$Commit;MeasuredAt=$snapshot.MeasuredAt;RunUrl=$snapshot.RunUrl;SnapshotSHA256=(Get-FileHash $quality).Hash.ToLowerInvariant();Files=$hashes}
$manifestPath=Join-Path $PublicDirectory 'quality-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$existing=& gh api --paginate ('repos/'+$Repository+'/releases?per_page=100') --jq '.[].tag_name'
if($LASTEXITCODE -ne 0){throw '無法確認既有版本。'}
if($existing -ccontains $Version){throw '版本已存在；不覆寫或重用草稿。'}
$ghArguments=@('release','create',$Version,'--repo',$Repository,'--verify-tag','--draft','--title',('Windows 設定工具 '+$Version),'--notes-file',$NotesPath)
if($Prerelease){$ghArguments+=@('--prerelease','--latest=false')}
$attachments=@($quality,$manifestPath)+@($files|Where-Object {$_ -ne 'summary.json'}|ForEach-Object {Join-Path $PublicDirectory $_})
$ghArguments+=$attachments
& gh @ghArguments
if($LASTEXITCODE -ne 0){throw '草稿或附件建立失敗，未發布。'}
$draft=(& gh release view $Version --repo $Repository --json assets,isDraft)|ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or -not $draft.isDraft -or $draft.assets.Count -ne $attachments.Count){throw '草稿附件數量不符，未發布。'}
foreach($file in $attachments){$asset=@($draft.assets|Where-Object name -ceq ([IO.Path]::GetFileName($file)));if($asset.Count -ne 1 -or $asset[0].digest -cne ('sha256:'+(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant())){throw '草稿附件 digest 不符，未發布。'}}
# Publishing last locks the completed attachment set when immutability is enabled.
& gh release edit $Version --repo $Repository --draft=false
if($LASTEXITCODE -ne 0){throw '草稿發布失敗；保留草稿供查核，不自動覆寫。'}
$published=(& gh api ('repos/'+$Repository+'/releases/tags/'+$Version))|ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or $published.immutable -isnot [bool] -or $published.immutable -cne $true -or $published.draft -isnot [bool] -or $published.draft -cne $false -or $published.tag_name -cne $Version){throw '已發布版本未鎖定或版本／草稿狀態不符，不能宣稱永久證據鎖定。'}
$tagCommit=& gh api ('repos/'+$Repository+'/commits/'+$Version) --jq '.sha'
if($LASTEXITCODE -ne 0 -or $tagCommit -cne $Commit){throw '發布後標籤來源 SHA 不符。'}
if($published.assets.Count -ne $attachments.Count){throw '發布後附件數量不符。'}
foreach($file in $attachments){$asset=@($published.assets|Where-Object name -ceq ([IO.Path]::GetFileName($file)));if($asset.Count -ne 1 -or $asset[0].digest -cne ('sha256:'+(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant())){throw '發布後品質附件 digest 不符。'}}
Write-Host ('已發布並鎖定品質證據：'+$published.html_url)
