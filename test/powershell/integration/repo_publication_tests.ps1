#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
$fixture=Join-Path $env:TEMP ('complete_publication_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $fixture|Out-Null
$tool=Join-Path $fixture 'repo_coverage_tool.exe'
Push-Location $root
try{& go.exe build -mod=vendor -o $tool ./script/test/repo_coverage_tool;if($LASTEXITCODE -ne 0){throw 'coverage CLI build failed'}}finally{Pop-Location}
$checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=$layer;Layer=$layer;Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='real assertion';Passed=$true})}})
$identity=@{Commit=('a'*40);RunUrl='https://github.com/example/repo/actions/runs/1';MeasuredAt='2026-11-08T00:00:00Z';SourceState='Clean'}
$public=Join-Path $fixture 'public';Write-TestReports -Checks $checks -OutputDirectory $public @identity -RefName main|Out-Null
$evidence=Join-Path $fixture 'evidence';New-Item -ItemType Directory $evidence|Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$inventory=[ordered]@{Sources=@([ordered]@{Path='core/example.ps1';Language='powershell';SHA256=('b'*64);ExpectedLines=@(1,2,3,4,5)});Excluded=$null;Blockers=$null}
[IO.File]::WriteAllText((Join-Path $evidence 'coverage_inventory.json'),($inventory|ConvertTo-Json -Depth 8),$utf8)
$xml='<coverage coverage-schema="1" coverage-metric="complete-executable-lines-v1"><packages><package><classes><class filename="core/example.ps1"><lines><line number="1" hits="1"/><line number="2" hits="1"/><line number="3" hits="1"/><line number="4" hits="1"/><line number="5" hits="0"/></lines></class></classes></package></packages></coverage>'
[IO.File]::WriteAllText((Join-Path $evidence 'coverage.xml'),$xml,$utf8)
$c=[ordered]@{SchemaVersion=1;Metric='complete-executable-lines-v1';Commit=$identity.Commit;RunUrl=$identity.RunUrl;MeasuredAt=$identity.MeasuredAt;SourceState='Clean';InventorySHA256=(Get-FileHash (Join-Path $evidence 'coverage_inventory.json')).Hash.ToLowerInvariant();NormalizedSHA256=(Get-FileHash (Join-Path $evidence 'coverage.xml')).Hash.ToLowerInvariant();Result=[ordered]@{SchemaVersion=1;Metric='complete-executable-lines-v1';Complete=$true;Covered=4;Executable=5;Percent=80.0;Missing=$null;Blockers=$null;Languages=@{powershell=@{Covered=4;Executable=5}}}}
[IO.File]::WriteAllText((Join-Path $evidence 'repo_coverage.json'),($c|ConvertTo-Json -Depth 8),$utf8)
& (Join-Path $root 'script/test/attach_repo_coverage.ps1') -PublicDirectory $public -CoverageDirectory $evidence -CoverageToolPath $tool
$report=Get-Content (Join-Path $public 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($report.Coverage -ceq 'Measured' -and $report.RepoCoverage.Result.Percent -eq 80) '真CLI重算後附加完整整體覆蓋率'
foreach($name in @('repo_coverage.json','coverage_inventory.json','coverage.xml')){Assert ((Get-FileHash (Join-Path $public $name)).Hash -eq (Get-FileHash (Join-Path $evidence $name)).Hash) ('永久證據逐位元保存：'+$name)}
$catalog=Join-Path $fixture 'catalog.json';[IO.File]::WriteAllText($catalog,'[]')
$portal=Join-Path $fixture 'portal'
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $portal -MainSnapshotPath (Join-Path $public 'summary.json') -CoverageToolPath $tool|Out-Null
$landingPage=[IO.File]::ReadAllText((Join-Path $portal 'index.html'))
Assert ($landingPage.Contains('80.0%') -and $landingPage.Contains('4/5 可執行行')) 'Pages首頁顯示整體共同計量'
foreach($name in @('repo_coverage.json','coverage_inventory.json','coverage.xml')){Assert ((Get-FileHash (Join-Path $portal ('main/'+$name))).Hash -eq (Get-FileHash (Join-Path $evidence $name)).Hash) ('Pages保留可重算證據：'+$name)}
$missing=Join-Path $fixture 'missing';Write-TestReports -Checks $checks -OutputDirectory $missing @identity -RefName main|Out-Null
Refuse {& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory (Join-Path $fixture 'missing_portal') -MainSnapshotPath (Join-Path $missing 'summary.json') -CoverageToolPath $tool} '正式Pages缺整體量測必須拒絕'
$legacyDirectory=Join-Path $fixture 'legacy_publish'
Write-TestReports -Checks $checks -OutputDirectory $legacyDirectory @identity -SchemaVersion 1 -Version v1.0.0 -RefType Release -RefName v1.0.0 -Environment Fixture|Out-Null
$global:repoPublicationRemoteCalled=$false
function gh {$global:repoPublicationRemoteCalled=$true;$global:LASTEXITCODE=1;throw 'unexpected remote operation'}
Refuse {& (Join-Path $root 'script/report/publish_quality_release.ps1') -PublicDirectory $legacyDirectory -Version v1.0.0 -Commit $identity.Commit -NotesPath (Join-Path $legacyDirectory 'summary.md') -Repository example/repo} '本輪publisher不得降級legacy契約'
Assert (-not $global:repoPublicationRemoteCalled) 'legacy只能讀歷史，發布前禁止遠端操作'
Remove-Item Function:\gh
$report.RefType='Release';$report.RefName='v1.0.0';$report.Version='v1.0.0';$report.Environment='Fixture'
. (Join-Path $root 'script/report/portal.ps1')
Write-SnapshotView $report $public
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -eq 'api' -and $words -contains '--paginate'){return}
 if($words[0] -eq 'release' -and $words[1] -eq 'create'){
  $global:repoPublicationTitle=$words[[Array]::IndexOf($words,'--title')+1]
  $global:repoPublicationDraft=$words -contains '--draft'
  $global:repoPublicationAssets=@($words|Where-Object {Test-Path -LiteralPath ([string]$_) -PathType Leaf}|Where-Object {[IO.Path]::GetExtension($_) -ne '.md' -or [IO.Path]::GetFileName($_) -eq 'summary.md'}|Select-Object -Unique|ForEach-Object {@{name=[IO.Path]::GetFileName($_);digest=('sha256:'+(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant())}})
  return
 }
 if($words[0] -eq 'release' -and $words[1] -eq 'view'){
  if($global:repoPublicationMode -eq 'bad-digest'){$global:repoPublicationAssets[0].digest='sha256:'+('0'*64)}
  return (@{isDraft=$true;assets=$global:repoPublicationAssets}|ConvertTo-Json -Depth 5)
 }
 if($words[0] -eq 'release' -and $words[1] -eq 'edit'){$global:repoPublicationPublished++;return}
 if($words[0] -eq 'api' -and $words[1] -like '*/releases/tags/*'){
  $assets=if($global:repoPublicationMode -eq 'missing-asset'){@($global:repoPublicationAssets|Select-Object -Skip 1)}else{$global:repoPublicationAssets}
  return (@{immutable=$(if($global:repoPublicationMode -eq 'string-immutable'){'true'}else{$global:repoPublicationMode -ne 'mutable'});draft=$false;tag_name='v1.0.0';assets=$assets;html_url='https://github.com/example/repo/releases/tag/v1.0.0'}|ConvertTo-Json -Depth 5)
 }
 if($words[0] -eq 'api' -and $words[1] -like '*/commits/*'){return $(if($global:repoPublicationMode -eq 'wrong-sha'){'c'*40}else{'a'*40})}
 throw ('Unexpected mock call: '+($words -join ' '))
}
foreach($mode in @('success','bad-digest','missing-asset','mutable','string-immutable','wrong-sha')){
 $global:repoPublicationMode=$mode;$global:repoPublicationPublished=0
 $accepted=$true;try{& (Join-Path $root 'script/report/publish_quality_release.ps1') -PublicDirectory $public -Version v1.0.0 -Commit $identity.Commit -NotesPath (Join-Path $public 'summary.md') -Repository example/repo -CoverageToolPath $tool|Out-Null}catch{$accepted=$false}
 Assert ($accepted -eq ($mode -eq 'success')) ('Schema2只發布真完整不可變證據：'+$mode)
 Assert ($global:repoPublicationTitle -ceq 'v1.0.0' -and $global:repoPublicationDraft) ('版本標題及草稿先行：'+$mode)
 Assert ($global:repoPublicationAssets.Count -eq 11) ('新Release精確11附件：'+$mode)
 Assert ($global:repoPublicationPublished -eq $(if($mode -eq 'bad-digest'){0}else{1})) ('草稿驗證失敗不得提前發布：'+$mode)
}
Remove-Item Function:\gh
function New-LocalEntry {
 $manifestPath=Join-Path $public 'quality-manifest.json'
 $manifest=Get-Content $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($file in $manifest.Files){$file.SHA256=(Get-FileHash (Join-Path $public $file.Name)).Hash.ToLowerInvariant()}
 [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),$utf8)
 [pscustomobject]@{Version='v1.0.0';Commit=$identity.Commit;ReleaseUrl='https://github.com/example/repo/releases/tag/v1.0.0';Immutable=$true;SnapshotPath=(Join-Path $public 'quality.json');ManifestPath=$manifestPath;SnapshotDigest=('sha256:'+(Get-FileHash (Join-Path $public 'quality.json')).Hash.ToLowerInvariant());ManifestDigest=('sha256:'+(Get-FileHash $manifestPath).Hash.ToLowerInvariant());AssetDirectory=$public;AssetDigests=@(Get-ChildItem $public -File|ForEach-Object {[pscustomobject]@{Name=$_.Name;Digest=('sha256:'+(Get-FileHash $_.FullName).Hash.ToLowerInvariant())}})}
}
$entry=New-LocalEntry
$verified=Test-PortalReleaseEvidence -Entry $entry -CoverageToolPath $tool
Assert ($verified.Snapshot.RepoCoverage.Result.Percent -eq 80) 'manifest2歷史來源同樣重算整體量測'
$xmlOriginal=[IO.File]::ReadAllText((Join-Path $public 'coverage.xml'))
[IO.File]::AppendAllText((Join-Path $public 'coverage.xml'),' ')
$forged=New-LocalEntry
Refuse {Test-PortalReleaseEvidence -Entry $forged -CoverageToolPath $tool} '即使外層digest重簽仍拒絕與coverage內層hash不同的附件'
[IO.File]::WriteAllText((Join-Path $public 'coverage.xml'),$xmlOriginal,$utf8)
$entry=New-LocalEntry
$before=(Get-FileHash (Join-Path $public 'summary.json')).Hash
[IO.File]::AppendAllText((Join-Path $evidence 'coverage.xml'),'tampered')
Refuse {& (Join-Path $root 'script/test/attach_repo_coverage.ps1') -PublicDirectory $public -CoverageDirectory $evidence -CoverageToolPath $tool} '篡改逐行證據不得附加'
Assert ((Get-FileHash (Join-Path $public 'summary.json')).Hash -eq $before) '驗證失敗不改原始報告'
