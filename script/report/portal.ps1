#Requires -Version 5.1
function Get-TestReportArtifactNames {
 param([ValidateSet(1,2)][int]$SchemaVersion)
 $files=@('index.html','summary.json','summary.md','junit.xml','unit.svg','integration.svg','coverage.svg')
 if($SchemaVersion -eq 1){return @($files+'system.svg')}
 return @($files+@('repo_coverage.json','coverage_inventory.json','coverage.xml'))
}
function Get-TestIdentityMap {
 param($Snapshot)
 $map=@{}
 foreach($suite in @($Snapshot.Checks)){
  $suiteId=$suite.Layer+' / '+$suite.Name+' / [suite execution]'
  if($map.ContainsKey($suiteId)){throw ('重複測試識別：'+$suiteId)}
  $map[$suiteId]=if(-not $suite.Executed){'NotRun'}elseif($suite.Passed){'Passed'}else{'Failed'}
  $items=@($suite.Assertions)
  if(-not $items.Count){$items=@([pscustomobject]@{Name='[suite]';Passed=$suite.Passed})}
  foreach($item in $items){
   $id=$suite.Layer+' / '+$suite.Name+' / '+$item.Name
   if($map.ContainsKey($id)){throw ('重複測試識別：'+$id)}
   $status=if(-not $suite.Executed){'NotRun'}elseif(-not $suite.Passed -and $item.Name -eq '[suite]'){'Failed'}elseif($item.Passed){'Passed'}else{'Failed'}
   $map[$id]=$status
  }
 }
 return $map
}
function Compare-TestSnapshots {
 param($Baseline,$Candidate)
 if($null -eq $Baseline -or $null -eq $Candidate){return [pscustomobject]@{Status='Unknown';Reason='至少一個版本沒有可驗證的品質快照。';CoverageDelta='Unknown / NotMeasured';Added=@();Removed=@();NewFailures=@();Fixed=@();NotRun=@()}}
 if($Baseline.SchemaVersion -ne $Candidate.SchemaVersion -or $Baseline.RequestedLayer -cne 'All' -or $Candidate.RequestedLayer -cne 'All' -or $Baseline.Environment -cne $Candidate.Environment -or -not $Baseline.Environment -or $Baseline.Environment -eq 'Unknown'){
  return [pscustomobject]@{Status='Unknown';Reason='測試範圍、schema 或量測環境不相容，不能推論測試差異。';CoverageDelta='Unknown / NotMeasured';Added=@();Removed=@();NewFailures=@();Fixed=@();NotRun=@()}
 }
 try{$a=Get-TestIdentityMap $Baseline;$b=Get-TestIdentityMap $Candidate}catch{
  if(-not $_.Exception.Message.StartsWith('重複測試識別：')){throw}
  return [pscustomobject]@{Status='Unknown';Reason=($_.Exception.Message+'；無法唯一對應測試，不能推論版本差異。');CoverageDelta='Unknown / NotMeasured';Added=@();Removed=@();NewFailures=@();Fixed=@();NotRun=@()}
 }
 [pscustomobject]@{Status='Compared';BaselineVersion=$Baseline.Version;CandidateVersion=$Candidate.Version;BaselineCommit=$Baseline.Commit;CandidateCommit=$Candidate.Commit;BaselineMeasuredAt=$Baseline.MeasuredAt;CandidateMeasuredAt=$Candidate.MeasuredAt;CoverageDelta='Unknown / NotMeasured';Added=@($b.Keys|Where-Object {-not $a.ContainsKey($_)}|Sort-Object);Removed=@($a.Keys|Where-Object {-not $b.ContainsKey($_)}|Sort-Object);NewFailures=@($b.Keys|Where-Object {$b[$_] -eq 'Failed' -and (-not $a.ContainsKey($_) -or $a[$_] -ne 'Failed')}|Sort-Object);Fixed=@($b.Keys|Where-Object {$b[$_] -eq 'Passed' -and $a.ContainsKey($_) -and $a[$_] -eq 'Failed'}|Sort-Object);NotRun=@($b.Keys|Where-Object {$b[$_] -eq 'NotRun'}|Sort-Object)}
}
function Write-SnapshotView {
 param($Snapshot,[string]$OutputDirectory)
 Write-TestReports -SchemaVersion $Snapshot.SchemaVersion -Checks @($Snapshot.Checks) -OutputDirectory $OutputDirectory -Layer $Snapshot.RequestedLayer -Commit $Snapshot.Commit -RunUrl $Snapshot.RunUrl -SourceState $Snapshot.SourceState -Version $Snapshot.Version -Environment $Snapshot.Environment -RefType $Snapshot.RefType -RefName $Snapshot.RefName -MeasuredAt $Snapshot.MeasuredAt -Changes $Snapshot.Changes -RepoCoverage $(if($Snapshot.PSObject.Properties['RepoCoverage']){$Snapshot.RepoCoverage}else{$null}) -GoCoverage $(if($Snapshot.PSObject.Properties['GoCoverage']){$Snapshot.GoCoverage}else{$null})|Out-Null
}
function Test-PortalReleaseEvidence {
 param($Entry)
 if($Entry.Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'){throw '版本名稱不合法。'}
 if($Entry.Immutable -isnot [bool] -or $Entry.Immutable -cne $true){throw 'Release 未鎖定，不能作為不可變版本證據。'}
 if($Entry.Commit -notmatch '^[a-fA-F0-9]{40}$'){throw '缺少標籤來源提交。'}
 foreach($key in @('SnapshotPath','ManifestPath')){if(-not(Test-Path -LiteralPath $Entry.$key -PathType Leaf)){throw '缺少品質證據附件。'}}
 $actual=(Get-FileHash -LiteralPath $Entry.SnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if($Entry.SnapshotDigest -cne ('sha256:'+$actual)){throw 'GitHub 品質附件 digest 不符。'}
 $manifestActual=(Get-FileHash -LiteralPath $Entry.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if($Entry.ManifestDigest -cne ('sha256:'+$manifestActual)){throw 'GitHub manifest digest 不符。'}
 $snapshot=Get-Content -LiteralPath $Entry.SnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
 $manifest=Get-Content -LiteralPath $Entry.ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.SchemaVersion -notin @(1,2) -or $manifest.SchemaVersion -ne $snapshot.SchemaVersion){throw '品質 manifest 與報告 schema 不相符。'}
 Assert-TestReportSnapshot -Report $snapshot -Release
 if($snapshot.Version -cne $Entry.Version -or $snapshot.Commit -cne $Entry.Commit -or $manifest.Version -cne $Entry.Version -or $manifest.Commit -cne $Entry.Commit -or $manifest.SnapshotSHA256 -cne $actual){throw '版本、來源提交或品質 digest 不一致。'}
 $required=@(Get-TestReportArtifactNames $snapshot.SchemaVersion)
 if(@($manifest.Files).Count -ne $required.Count){throw '品質 manifest 不完整。'}
 foreach($name in $required){
  $items=@($manifest.Files|Where-Object {$_.Name -ceq $name});if($items.Count -ne 1 -or $items[0].SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw '品質 manifest 缺少或重複必要檔案。'}
  $local=if($name -eq 'summary.json'){$Entry.SnapshotPath}else{Join-Path $Entry.AssetDirectory $name}
  if(-not(Test-Path -LiteralPath $local -PathType Leaf)){throw '缺少不可變品質附件。'}
  $hash=(Get-FileHash -LiteralPath $local).Hash.ToLowerInvariant()
  $assetName=if($name -eq 'summary.json'){'quality.json'}else{$name}
  $metadata=@($Entry.AssetDigests|Where-Object Name -ceq $assetName)
  if($metadata.Count -ne 1 -or $metadata[0].Digest -cne ('sha256:'+$hash) -or $items[0].SHA256 -cne $hash){throw '不可變品質附件與 GitHub／manifest digest 不符。'}
  if($name -match '\.(html|svg)$'){
   $content=[IO.File]::ReadAllText($local)
   if($content -match '(?is)<script\b|\bon[a-z]+\s*=|javascript\s*:|<iframe\b|<object\b|<embed\b'){throw '版本附件含可執行內容，拒絕發布。'}
  }
 }
 [pscustomobject]@{Snapshot=$snapshot;Manifest=$manifest}
}
