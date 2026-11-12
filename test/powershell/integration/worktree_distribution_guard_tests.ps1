#Requires -Version 5.1
param([switch]$LayoutOnly)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('worktree_source_guard_'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $fixture 'repo';[IO.Directory]::CreateDirectory((Join-Path $repo 'doc/changelog'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $repo 'core/worktree'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $repo 'worktree_extra'))|Out-Null
function WriteFixture([string]$Name,[string]$Text){$path=Join-Path $repo $Name;[IO.Directory]::CreateDirectory((Split-Path $path -Parent))|Out-Null;[IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))}
function GitFixture([string[]]$Arguments){& git.exe -C $repo @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw 'Git fixture 失敗'}}
function Assert([bool]$Pass,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Pass}|ConvertTo-Json -Compress));if(-not $Pass){throw ('FAIL: '+$Message)}}
foreach($name in @('init.cmd','windows.cmd','readme.md')){WriteFixture $name 'fixture'}
WriteFixture '.version' 'v1.2.3';WriteFixture 'doc/changelog/changelog.md' "## [v1.2.3]`n- fixture`n";WriteFixture 'worktree_extra/owned.ps1' 'Write-Output 1';WriteFixture 'core/worktree/owned.ps1' 'Write-Output 1'
foreach($name in @('paths.ps1','paths.json','hardware.ps1')){Copy-Item -LiteralPath (Join-Path $root ('core/'+$name)) -Destination (Join-Path $repo ('core/'+$name))}
GitFixture @('init','-q');GitFixture @('config','user.name','CI Fixture');GitFixture @('config','user.email','fixture@example.invalid');GitFixture @('add','-A');GitFixture @('commit','-qm','fixture')
$builder=Join-Path $root 'script/release/build_source_release.ps1';$layout=Join-Path $root 'test/powershell/integration/layout_tests.ps1'
& $builder -Version v1.2.3 -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'allowed')|Out-Null
Assert (Test-Path -LiteralPath (Join-Path $fixture 'allowed/release_notes.md')) '近名及巢狀工作樹來源可發布'
WriteFixture 'worktree/owned.ps1' 'Write-Output 1';GitFixture @('add','-f','worktree/owned.ps1');GitFixture @('commit','-qm','tracked development folder')
$archive=Join-Path $fixture 'tracked.zip';GitFixture @('archive','--format=zip',('--output='+$archive),'HEAD');Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($archive);try{$contains=@($zip.Entries|Where-Object FullName -ceq 'worktree/owned.ps1').Count -eq 1}finally{$zip.Dispose()}
Assert $contains '強制追蹤的根工作樹會進入 Git 來源 ZIP'
$caught=$false;try{& $builder -Version v1.2.3 -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'refused')|Out-Null}catch{$caught=$true}
if(-not $LayoutOnly){Assert ($caught -and -not(Test-Path -LiteralPath (Join-Path $fixture 'refused'))) '已追蹤根工作樹不得發布'}
$sourceArchive=Join-Path $fixture 'complete-source.zip';& git.exe -C $root archive --format=zip ('--output='+$sourceArchive) HEAD;if($LASTEXITCODE -ne 0){throw '無法建立完整來源 fixture'}
$layoutRepo=Join-Path $fixture 'complete-source';Expand-Archive -LiteralPath $sourceArchive -DestinationPath $layoutRepo
[IO.Directory]::CreateDirectory((Join-Path $layoutRepo 'worktree'))|Out-Null;[IO.File]::WriteAllText((Join-Path $layoutRepo 'worktree/owned.ps1'),'Write-Output 1')
$zipLog=Join-Path $fixture 'layout_zip.log';$oldPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $layout -PackageRoot $layoutRepo -SourceOnly *> $zipLog;$zipExit=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
$zipRows=@(Get-Content -LiteralPath $zipLog|Where-Object {$_.StartsWith('@@ASSERT@@')}|ForEach-Object {$_.Substring(10)|ConvertFrom-Json})
Assert ($zipExit -ne 0 -and @($zipRows|Where-Object {$_.Name -ceq 'tracked root worktree is excluded from source distribution' -and -not $_.Passed}).Count -eq 1) '無 Git 來源版面也拒絕根工作樹'
& git.exe -C $layoutRepo init -q;& git.exe -C $layoutRepo config user.name 'CI Fixture';& git.exe -C $layoutRepo config user.email 'fixture@example.invalid';& git.exe -C $layoutRepo add -A;& git.exe -C $layoutRepo add -f worktree/owned.ps1;& git.exe -C $layoutRepo commit -qm fixture;if($LASTEXITCODE -ne 0){throw '無法準備完整來源 fixture'}
$log=Join-Path $fixture 'layout.log';$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $layout -PackageRoot $layoutRepo -SourceOnly *> $log;$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
$rows=@(Get-Content -LiteralPath $log|Where-Object {$_.StartsWith('@@ASSERT@@')}|ForEach-Object {$_.Substring(10)|ConvertFrom-Json})
Assert ($exit -ne 0 -and @($rows|Where-Object {$_.Name -ceq 'tracked root worktree is excluded from source distribution' -and -not $_.Passed}).Count -eq 1) 'CI 版面檢查拒絕已追蹤根工作樹'
$global:LASTEXITCODE=0