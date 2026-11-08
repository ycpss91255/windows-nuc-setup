#Requires -Version 5.1
param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$MainRunId)
$ErrorActionPreference='Stop'
$out=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $out){throw '證據下載目錄必須不存在。'}
New-Item -ItemType Directory $out|Out-Null
$lines=& gh api --paginate ('repos/'+$Repository+'/releases?per_page=100') --jq '.[] | @json'
if($LASTEXITCODE -ne 0){throw '無法列出 Release。'}
$rows=New-Object Collections.Generic.List[object]
foreach($line in $lines){
 $release=$line|ConvertFrom-Json
 if($release.draft -or $release.tag_name -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'){continue}
 $sha=& gh api ('repos/'+$Repository+'/commits/'+$release.tag_name) --jq '.sha'
 if($LASTEXITCODE -ne 0){throw '無法核對 Release tag SHA。'}
 $snapshot=@($release.assets|Where-Object name -ceq 'quality.json');$manifest=@($release.assets|Where-Object name -ceq 'quality-manifest.json')
 $row=[ordered]@{Version=$release.tag_name;Commit=$sha;ReleaseUrl=$release.html_url;Immutable=($release.immutable -is [bool] -and $release.immutable -ceq $true);SnapshotPath='';ManifestPath='';SnapshotDigest='';ManifestDigest='';AssetDirectory='';AssetDigests=@()}
 if($snapshot.Count -eq 1 -and $manifest.Count -eq 1){
  $dir=Join-Path $out $release.tag_name;New-Item -ItemType Directory $dir|Out-Null
  $download=@('release','download',$release.tag_name,'--repo',$Repository,'--dir',$dir)
  foreach($name in @('quality.json','quality-manifest.json','index.html','summary.md','junit.xml','unit.svg','integration.svg','system.svg','coverage.svg','repo_coverage.json','coverage_inventory.json','coverage.xml')){if($release.assets.name -ccontains $name){$download+=@('--pattern',$name)}}
  & gh @download
  if($LASTEXITCODE -ne 0){throw 'Release 品質證據下載失敗。'}
  $row.SnapshotPath=Join-Path $dir 'quality.json';$row.ManifestPath=Join-Path $dir 'quality-manifest.json';$row.SnapshotDigest=$snapshot[0].digest;$row.ManifestDigest=$manifest[0].digest
  $row.AssetDirectory=$dir;$row.AssetDigests=@($release.assets|ForEach-Object {[pscustomobject]@{Name=$_.name;Digest=$_.digest}})
 }
 $rows.Add([pscustomobject]$row)
}
[IO.File]::WriteAllText((Join-Path $out 'catalog.json'),(ConvertTo-Json -InputObject @($rows.ToArray()) -Depth 8),[Text.UTF8Encoding]::new($false))
# Never relabel a tag run as main: resolve a completed run for the current main SHA.
$mainSha=& gh api ('repos/'+$Repository+'/commits/main') --jq '.sha'
if($LASTEXITCODE -ne 0){throw '無法確認 main SHA。'}
if(-not $MainRunId){
 $runLines=& gh api ('repos/'+$Repository+'/actions/workflows/windows_tests.yml/runs?branch=main&event=push&status=completed&per_page=100') --jq '.workflow_runs[] | @json'
 if($LASTEXITCODE -ne 0){throw '無法尋找 main 品質證據。'}
 $run=@($runLines|ForEach-Object {$_|ConvertFrom-Json}|Where-Object head_sha -ceq $mainSha|Select-Object -First 1)
 if($run.Count){$MainRunId=[string]$run[0].id}
}
if($MainRunId){
 if($MainRunId -notmatch '^[0-9]+$'){throw 'Run ID 不合法。'}
 $run=(& gh api ('repos/'+$Repository+'/actions/runs/'+$MainRunId))|ConvertFrom-Json
 if($LASTEXITCODE -ne 0 -or $run.head_sha -cne $mainSha -or $run.head_branch -cne 'main' -or $run.event -cne 'push'){throw 'main run 來源不符。'}
 $artifacts=(& gh api ('repos/'+$Repository+'/actions/runs/'+$MainRunId+'/artifacts'))|ConvertFrom-Json
 $artifact=@($artifacts.artifacts|Where-Object {$_.name -eq ('windows-test-reports-'+$MainRunId+'-'+$run.run_attempt) -and -not $_.expired})
 if($artifact.Count -eq 1){
  $mainDir=Join-Path $out 'main';New-Item -ItemType Directory $mainDir|Out-Null
  & gh run download $MainRunId --repo $Repository --name $artifact[0].name --dir $mainDir
  if($LASTEXITCODE -ne 0){throw 'main 品質快照下載失敗。'}
  $snapshot=Get-Content (Join-Path $mainDir 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($snapshot.Commit -cne $mainSha){throw 'main 快照提交不符。'}
 }
}
[pscustomobject]@{CatalogPath=(Join-Path $out 'catalog.json');MainSnapshotPath=(Join-Path $out 'main/summary.json')}
