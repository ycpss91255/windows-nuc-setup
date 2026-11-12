#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/release/release.ps1')
$builder=Join-Path $root 'script/release/build_source_release.ps1'
$prepare=Join-Path $root 'script/release/prepare_release.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Windows-Release-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $fixture '中文 來源'
New-Item -ItemType Directory -Path (Join-Path $repo 'doc/changelog') -Force|Out-Null
$script:count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
function FixtureGit([string[]]$Arguments){& git.exe -C $repo @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw '測試 Git 命令失敗。'}}
function WriteFile([string]$Path,[string]$Text){[IO.File]::WriteAllText((Join-Path $repo $Path),$Text,[Text.UTF8Encoding]::new($false))}
# Invoke the copied maintenance entry in a fresh PS5.1 process without PackageRoot.
$defaultRepo=Join-Path $fixture '預設定位'
New-Item -ItemType Directory -Path (Join-Path $defaultRepo 'script/release'),(Join-Path $defaultRepo 'doc/changelog') -Force|Out-Null
Copy-Item -LiteralPath $prepare,$builder,(Join-Path $root 'script/release/release.ps1') -Destination (Join-Path $defaultRepo 'script/release')
[IO.File]::WriteAllText((Join-Path $defaultRepo 'doc/changelog/changelog.md'),"## [Unreleased]`n`n### Fixed`n`n- fixture change`n")
$priorPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $defaultRepo 'script/release/prepare_release.ps1') -Version v9.8.7-rc1 > (Join-Path $fixture 'default_prepare.log') 2>&1;$prepareExit=$LASTEXITCODE}finally{$ErrorActionPreference=$priorPreference}
Assert ($prepareExit -eq 0) 'PS5.1 新程序省略 PackageRoot 可定位腳本所屬套件'
Assert ((Get-Content (Join-Path $defaultRepo '.version') -Raw).Trim() -eq 'v9.8.7-rc1') '預設定位只更新暫存套件的版本'
foreach($file in @('init.cmd','windows.cmd','readme.md')){[IO.File]::WriteAllText((Join-Path $defaultRepo $file),'fixture')}
& git.exe -C $defaultRepo init --quiet
& git.exe -C $defaultRepo add --all
& git.exe -C $defaultRepo -c user.name='CI Fixture' -c user.email=fixture@example.invalid commit --quiet -m fixture
if($LASTEXITCODE -ne 0){throw '預設發布來源 Git 準備失敗。'}
$defaultNotes=Join-Path $fixture 'default_builder_notes'
Push-Location $fixture
try{
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $defaultRepo 'script/release/build_source_release.ps1') -Version v9.8.7-rc1 -OutputDirectory $defaultNotes > (Join-Path $fixture 'default_builder.log') 2>&1
 $builderExit=$LASTEXITCODE
}finally{$ErrorActionPreference=$priorPreference;Pop-Location}
Assert ($builderExit -eq 0) 'PS5.1 原生 File 入口省略 PackageRoot 可產生所屬 Git 套件版本說明'
$rcOriginal=Get-ReleaseNotes v9.8.7-rc1 ([IO.File]::ReadAllText((Join-Path $defaultRepo 'doc/changelog/changelog.md')))
$rcExpected='[此版本測試報表](https://ycpss91255.github.io/windows_setup/versions/v9.8.7-rc1/index.html)' + "`n`n" + $rcOriginal
Assert (([IO.File]::ReadAllText((Join-Path $defaultNotes 'release_notes.md'))) -ceq $rcExpected) 'RC 報表連結位於頂端且保留完整原始說明'
foreach($file in @('init.cmd','windows.cmd','readme.md')){WriteFile $file 'fixture'}
$log="## [Unreleased]`n`n### Changed`n`n- 通用 Windows 設定。`n"
WriteFile 'doc/changelog/changelog.md' $log
& $prepare -Version v1.2.3 -PackageRoot $repo
Assert ((Get-Content (Join-Path $repo '.version') -Raw).Trim() -eq 'v1.2.3') '準備版本同步 .version'
Assert ([IO.File]::ReadAllText((Join-Path $repo 'doc/changelog/changelog.md')).Contains('## [v1.2.3]')) 'Unreleased 提升為當版，保留新 Unreleased'
Refuse {& $prepare -Version v1.2.3 -PackageRoot $repo} '拒絕重複準備版本'
FixtureGit @('init','--quiet','-b','main');FixtureGit @('config','user.name','CI Fixture');FixtureGit @('config','user.email','fixture@example.invalid')
FixtureGit @('add','--all');FixtureGit @('commit','--quiet','-m','測試來源')
WriteFile 'local-only.txt' 'untracked'
Push-Location $fixture
try{$result=& $builder -Version v1.2.3 -PackageRoot $repo -OutputDirectory '.\notes'}finally{Pop-Location}
Assert ($result.NotesPath -eq (Join-Path $fixture 'notes\release_notes.md')) '發布輸出相對路徑依 PowerShell 位置解析'
Assert ((Get-Content $result.NotesPath -Raw -Encoding UTF8).Contains('通用 Windows 設定')) '說明來自精確版本章節'
$original=Get-ReleaseNotes v1.2.3 ([IO.File]::ReadAllText((Join-Path $repo 'doc/changelog/changelog.md')))
$expected='[此版本測試報表](https://ycpss91255.github.io/windows_setup/versions/v1.2.3/index.html)' + "`n`n" + $original
$actual=[IO.File]::ReadAllText($result.NotesPath)
Assert ($actual -ceq $expected) '正式版本必須連結自身版本報表並原樣保留說明'
Assert ($actual -cne $expected.Replace('/versions/v1.2.3/','/versions/v1.2.4/') -and $actual -cne $expected.Replace('/versions/v1.2.3/index.html','/main/index.html')) '錯版及 main 連結不能通過完整內容契約'
Assert-ReleaseReportLink -Version v1.2.3 -Notes $actual
Assert $true '正確版本入口通過發布前驗證'
Refuse {Assert-ReleaseReportLink -Version v1.2.3 -Notes $original} '缺少版本入口不得發布'
Refuse {Assert-ReleaseReportLink -Version v1.2.3 -Notes ($expected.Replace('/versions/v1.2.3/','/versions/v1.2.4/'))} '錯版入口不得發布'
Refuse {Assert-ReleaseReportLink -Version v1.2.3 -Notes ($expected.Replace('/versions/v1.2.3/index.html','/main/index.html'))} 'main 入口不得代替該版報表'
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$releaseJob=[regex]::Match($workflow,'(?ms)^  release:\s*$(.*?)(?=^  [a-z][a-z-]*:|\z)').Groups[1].Value
$builderPos=$releaseJob.IndexOf('build_source_release.ps1');$guardPos=$releaseJob.IndexOf('Assert-ReleaseReportLink');$publishPos=$releaseJob.IndexOf('publish_quality_release.ps1')
Assert ($builderPos -ge 0 -and $guardPos -gt $builderPos -and $publishPos -gt $guardPos -and $releaseJob.Contains('Assert-ReleaseReportLink -Version $env:RELEASE_TAG -Notes $notes')) 'CD 先產說明、按本次標籤核對入口後才發布'

Assert (@(Get-ChildItem (Join-Path $fixture 'notes')).Count -eq 1) '只輸出說明，不複製 GitHub 來源 ZIP'
Assert (-not $result.Prerelease) '正式版本分類正確'
Assert ((Get-ReleaseVersion 'v1.2.3-rc2').Prerelease) 'RC 分類為預覽版本'
Refuse {Get-ReleaseVersion '../invalid'} '無效版本與路徑穿越被拒絕'
Refuse {& $builder -Version v1.2.4 -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'mismatch')} '拒絕標籤與 .version 不一致'
Refuse {Get-ReleaseNotes v1.2.3 '## [v1.2.3]'} '拒絕空白版本說明'
Refuse {Get-ReleaseNotes v1.2.3 "## [v1.2.4]`n- other"} '拒絕缺少精確版本章節'
Refuse {Get-ReleaseNotes v1.2.3 "## [v1.2.3]`n- one`n## [v1.2.3]`n- two"} '拒絕重複版本章節'
$rc="## [v1.2.3]`n正式版摘要`n### Fixed`n- final fix`n## [v1.2.3-rc2]`n### Added`n- RC feature`n## [v1.2.3-rc1]`n### Fixed`n- RC fix`n"
$notes=Get-ReleaseNotes v1.2.3 $rc
Assert ($notes.Contains('RC feature') -and $notes.Contains('RC fix') -and $notes.Contains('final fix')) '正式版合併同版 RC 的分類條目'
Assert (([regex]::Matches($notes,'### Fixed')).Count -eq 1) 'RC 相同分類合併為單一標題'
Assert (-not (Get-ReleaseNotes v1.2.3-rc2 $rc).Contains('final fix')) 'RC 僅發布本身章節'
Assert-ReleaseOnMain -PackageRoot $repo -MainRef refs/heads/main
Assert $true 'main 提交可發布'
FixtureGit @('checkout','--quiet','-b','unmerged')
WriteFile 'branch.txt' 'not merged';FixtureGit @('add','branch.txt');FixtureGit @('commit','--quiet','-m','尚未合併')
Refuse {Assert-ReleaseOnMain -PackageRoot $repo -MainRef refs/heads/main} '未合併分支的標籤提交不可發布'
WriteFile 'answer.xml' '<fixture/>';FixtureGit @('add','answer.xml');FixtureGit @('commit','--quiet','-m','帳號暫存')
Refuse {& $builder -Version v1.2.3 -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'secret')} '追蹤中的帳號暫存拒絕發布'
Assert (-not(Test-Path (Join-Path $fixture 'secret'))) '拒絕發行時不產生輸出'
$introRc="## [v1.2.3]`nRelease summary`n## [v1.2.3-rc1]`n- RC leading entry`n### Added`n- feature`n"
Assert ((Get-ReleaseNotes v1.2.3 $introRc).Contains('RC leading entry')) '正式版保留 RC 分類前的條目'
Refuse {Get-ReleaseNotes v1.2.3 ($introRc+"## [v1.2.3-rc1]`n- duplicated`n")} '拒絕重複 RC 章節'
Refuse {Get-ReleaseNotes v1.2.3 ("## [v1.2.3]`n### Added`n- "+('x'*125001))} '拒絕超過 GitHub 字數上限'
$current=([IO.File]::ReadAllText((Join-Path $root '.version'))).Trim()
$currentNotes=Get-ReleaseNotes $current ([IO.File]::ReadAllText((Join-Path $root 'doc/changelog/changelog.md')))
Assert ($currentNotes.Length -gt 0) '本儲存庫 .version 對應非空版本說明'
Write-Host ('ALL PASS: '+$script:count+' release assertions; only temporary fixture repository changed.')
