#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/test/test_report.ps1')
. (Join-Path $root 'script/report/portal.ps1')
function Assert([bool]$condition,[string]$message){Write-Host ('@@ASSERT@@'+(@{Name=$message;Passed=$condition}|ConvertTo-Json -Compress));if(-not $condition){throw $message}}
function Reject([scriptblock]$action,[string]$message){$caught=$false;try{& $action|Out-Null}catch{$caught=$true};Assert $caught $message}
$parent=Join-Path ([IO.Path]::GetTempPath()) ('portal_synthetic_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $parent|Out-Null
$oldLocation=Get-Location
$oldFixture=$env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR;$oldTool=$env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL;$oldRepo=$env:GH_REPO
try {
 Set-Location $root
 $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=Join-Path $parent 'fixture'
 & go.exe test -count=1 -run '^TestExportSyntheticConsumerFixture$' ./script/test/report_bundle_tool
 if($LASTEXITCODE -ne 0){throw 'synthetic report fixture generation failed'}
 $env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL=Join-Path $parent 'report_bundle_tool.exe'
 & go.exe build -o $env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL ./script/test/report_bundle_tool
 if($LASTEXITCODE -ne 0){throw 'report verifier build failed'}
 $f=Get-Content -LiteralPath (Join-Path $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR 'fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($f.kind -ceq 'Synthetic') '明確標示合成測試資料'
 $env:GH_REPO='example/windows_setup'
 $entry=[pscustomobject]@{Version=$f.version;Commit=$f.commit;Immutable=$true;Repository=$env:GH_REPO;ArchivePath=(Join-Path $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR $f.archive);ArchiveDigest=('sha256:'+$f.sha256);ArchiveSize=$f.size;SourcePath=(Join-Path $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR $f.source);SnapshotPath='';ManifestPath='';ReleaseUrl=('https://github.com/'+$env:GH_REPO+'/releases/tag/'+$f.version)}
 $evidence=Test-PortalReleaseEvidence $entry
 Assert ($evidence.Snapshot.Commit -ceq $f.commit -and $evidence.ArchiveDigest -ceq $entry.ArchiveDigest) '真驗證器接受合成 ZIP 並保留來源與外摘要'
 $wrong=$entry|Select-Object *;$wrong.ArchiveDigest='sha256:'+('0'*64)
 Reject {Test-PortalReleaseEvidence $wrong} '錯誤 ZIP 摘要拒絕'
 $wrong=$entry|Select-Object *;$wrong.ArchiveSize=1
 Reject {Test-PortalReleaseEvidence $wrong} '錯誤 ZIP 大小拒絕'
 $wrong=$entry|Select-Object *;$wrong.Repository='other/repo'
 Reject {Test-PortalReleaseEvidence $wrong} '錯誤儲存庫拒絕'
 $env:GH_REPO='other/repo'
 Reject {Test-PortalReleaseEvidence $wrong} '執行網址不屬於可信儲存庫時拒絕'
 $env:GH_REPO='example/windows_setup'
 $wrong=$entry|Select-Object *;$wrong.Immutable=$false
 Reject {Test-PortalReleaseEvidence $wrong} '可變 Release 拒絕'
 $wrong=$entry|Select-Object *;$wrong.ReleaseUrl='https://github.com/other/repo/releases/tag/v0.1.0'
 Reject {Test-PortalReleaseEvidence $wrong} '錯誤 Release 網址拒絕'
 $damaged=Join-Path $parent 'damaged.zip';$bytes=[IO.File]::ReadAllBytes($entry.ArchivePath)
 [IO.File]::WriteAllBytes($damaged,$bytes[0..($bytes.Length-21)])
 $wrong=$entry|Select-Object *;$wrong.ArchivePath=$damaged;$wrong.ArchiveSize=(Get-Item -LiteralPath $damaged).Length;$wrong.ArchiveDigest='sha256:'+(Get-FileHash -LiteralPath $damaged).Hash.ToLowerInvariant()
 Reject {Test-PortalReleaseEvidence $wrong} '外摘要重算後的損壞 ZIP 仍拒絕'
 $wrong=$entry|Select-Object *;$wrong.SnapshotPath='quality.json'
 Reject {Test-PortalReleaseEvidence $wrong} '混合 raw 與 ZIP 拒絕'
 $catalog=Join-Path $parent 'catalog.json';ConvertTo-Json -InputObject @($entry) -Depth 8|Set-Content -LiteralPath $catalog -Encoding UTF8
 & (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $catalog -OutputDirectory (Join-Path $parent 'pages')|Out-Null
 $v=Get-Content -LiteralPath (Join-Path $parent 'pages/versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($v.Status -ceq 'Verified' -and $v.Digest -ceq $evidence.SnapshotDigest -and $v.ArchiveDigest -ceq $entry.ArchiveDigest) '版本頁保留不同的原摘要與 ZIP 摘要'
 $before=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'portal_zip_*'|ForEach-Object FullName)
 function Copy-Item {throw 'synthetic copy failure'}
 try {Reject {& (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $catalog -OutputDirectory (Join-Path $parent 'failed-pages')} '頁面複製失敗應回報'}
 finally {Remove-Item Function:\Copy-Item}
 $leaked=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'portal_zip_*'|Where-Object {$before -cnotcontains $_.FullName})
 Assert ($leaked.Count -eq 0) '頁面複製失敗仍清除自建驗證目錄'
 Reject {Remove-PortalOwnedTemporaryDirectory $parent} '非本次登記的目錄不得清理'
 $safe=New-PortalOwnedTemporaryDirectory
 $target=Join-Path $parent 'link-target';New-Item -ItemType Directory $target|Out-Null
 $sentinel=Join-Path $target 'sentinel';[IO.File]::WriteAllText($sentinel,'keep')
 $junction=Join-Path $safe 'junction'
 New-Item -ItemType Junction -Path $junction -Target $target|Out-Null
 Reject {Remove-PortalOwnedTemporaryDirectory $safe} '自建目錄中有連結不得遞迴清理'
 Assert (Test-Path -LiteralPath $sentinel -PathType Leaf) '拒絕清理時連結目標仍存在'
 [IO.Directory]::Delete($junction)
 Remove-PortalOwnedTemporaryDirectory $safe
 Assert (-not (Test-Path -LiteralPath $safe)) '移除連結後僅清理登記目錄'
 # Mock only GitHub transport and fetch; the downloaded ZIP is still validated by the real binary.
 $mockAssets=@(@{name=[IO.Path]::GetFileName($entry.ArchivePath);digest=$entry.ArchiveDigest;size=$entry.ArchiveSize})
 $mockCommit=$f.commit
 function gh {
  $global:LASTEXITCODE=0
  if($args[0] -eq 'release'){$at=[array]::IndexOf($args,'--dir');Copy-Item -LiteralPath $entry.ArchivePath -Destination (Join-Path $args[$at+1] ([IO.Path]::GetFileName($entry.ArchivePath)));return}
  $request=($args|Where-Object {$_ -like 'repos/*'}|Select-Object -First 1)
  if($request -like '*/releases?*'){
   return (@{draft=$false;tag_name=$f.version;html_url=$entry.ReleaseUrl;immutable=$true;assets=$mockAssets}|ConvertTo-Json -Depth 6 -Compress)
  }
  if($request -like '*/commits/*'){return $f.commit}
 }
 function git {
  $global:LASTEXITCODE=0
  if($args -contains 'rev-parse'){return $mockCommit}
  if($args -contains 'checkout'){
   $target=$args[1]
   Copy-Item -Path (Join-Path $entry.SourcePath '*') -Destination $target -Recurse -Force
  }
 }
 $inputs=& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository $env:GH_REPO -OutputDirectory (Join-Path $parent 'inputs')
 $downloaded=Get-Content -LiteralPath $inputs.CatalogPath -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($downloadEntry in $downloaded){
  Assert ($downloadEntry.ArchiveDigest -ceq $entry.ArchiveDigest -and $downloadEntry.Commit -ceq $f.commit) '下載目錄以可信 tag 提交與外摘要建立 catalog'
  $downloadEvidence=Test-PortalReleaseEvidence $downloadEntry
  Assert ($downloadEvidence.SnapshotDigest -ceq $evidence.SnapshotDigest) '下載的封裝與精確來源通過真驗證器'
 }
 $mockAssets+=@{name='quality.json';digest=('sha256:'+('a'*64));size=10}
 $mixedInputs=& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository $env:GH_REPO -OutputDirectory (Join-Path $parent 'mixed-inputs')
 & (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $mixedInputs.CatalogPath -OutputDirectory (Join-Path $parent 'mixed-pages')|Out-Null
 $mixed=Get-Content -LiteralPath (Join-Path $parent 'mixed-pages/versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($mixed.Status -ceq 'Invalid') '下載時新舊附件混合必須 Invalid，不可回退'
 $mockAssets=@(@{name=([IO.Path]::GetFileName($entry.ArchivePath)+'.bak');digest=$entry.ArchiveDigest;size=$entry.ArchiveSize},@{name='quality.json';digest=('sha256:'+('a'*64));size=10})
 $badNameInputs=& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository $env:GH_REPO -OutputDirectory (Join-Path $parent 'bad-name-inputs')
 & (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $badNameInputs.CatalogPath -OutputDirectory (Join-Path $parent 'bad-name-pages')|Out-Null
 $badName=Get-Content -LiteralPath (Join-Path $parent 'bad-name-pages/versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($badName.Status -ceq 'Invalid') '前綴相同但名稱錯誤不得退回 raw'
 $mockAssets=@(@{name=[IO.Path]::GetFileName($entry.ArchivePath);digest=$entry.ArchiveDigest;size=$entry.ArchiveSize},@{name='summary.json';digest=('sha256:'+('a'*64));size=10})
 $summaryInputs=& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository $env:GH_REPO -OutputDirectory (Join-Path $parent 'summary-inputs')
 & (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $summaryInputs.CatalogPath -OutputDirectory (Join-Path $parent 'summary-pages')|Out-Null
 $summaryMixed=Get-Content -LiteralPath (Join-Path $parent 'summary-pages/versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($summaryMixed.Status -ceq 'Invalid') 'summary.json 與 ZIP 混合必須 Invalid'
 $mockAssets=@($mockAssets[0]);$mockCommit=('a'*40)
 Reject {& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository $env:GH_REPO -OutputDirectory (Join-Path $parent 'wrong-tag-inputs')} 'Git 物件與可信 tag 提交不同必須拒絕'
} finally {Set-Location $oldLocation;$env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=$oldFixture;$env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL=$oldTool;$env:GH_REPO=$oldRepo}
