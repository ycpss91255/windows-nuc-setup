#Requires -Version 5.1
$ErrorActionPreference='Stop'
$builder=Join-Path (Split-Path $PSScriptRoot -Parent) 'Core\Build-SourceRelease.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-SourceRelease-Test-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $fixture '中文 來源'
$out=Join-Path $fixture '發布 檔案'
New-Item -ItemType Directory -Path (Join-Path $repo 'Docs') -Force|Out-Null
$script:count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Invoke-FixtureGit([string[]]$Arguments){& git.exe -C $repo @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw '測試 Git 命令失敗。'}}
foreach($file in @('Init.cmd','Windows.cmd','README.md','Docs\GITHUB.md')){[IO.File]::WriteAllText((Join-Path $repo $file),'test source')}
Invoke-FixtureGit @('init','--quiet')
Invoke-FixtureGit @('config','user.name','CI Fixture')
Invoke-FixtureGit @('config','user.email','fixture@example.invalid')
Invoke-FixtureGit @('add','--all')
Invoke-FixtureGit @('commit','--quiet','-m','測試來源')
[IO.File]::WriteAllText((Join-Path $repo 'local-only.txt'),'untracked fixture')
$result=& $builder -Version 'v1.2.3' -PackageRoot $repo -OutputDirectory $out
Assert (Test-Path -LiteralPath $result.ZipPath) '來源 ZIP 已建立'
Assert ((Get-FileHash -LiteralPath $result.ZipPath).Hash.ToLowerInvariant() -eq $result.SHA256) 'ZIP SHA256 與結果一致'
Assert ([IO.File]::ReadAllText($result.ChecksumPath).StartsWith($result.SHA256+'  ')) '校驗清單含正確 SHA256'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($result.ZipPath)
try{$entries=@($zip.Entries|ForEach-Object {$_.FullName})}finally{$zip.Dispose()}
Assert ('Windows-NUC-Setup/Init.cmd' -in $entries) 'ZIP 有單一完整工具包根目錄'
Assert (-not($entries -match 'local-only|\.git/')) '不包含未追蹤檔案與 Git metadata'
Assert ($result.FileCount -eq 4) '僅打包指定提交的四個來源檔'
Assert ([IO.File]::ReadAllText($result.NotesPath).Contains('來源包')) '版本說明清楚標示來源包'
$caught=$false;try{& $builder -Version '../bad' -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'invalid')|Out-Null}catch{$caught=$true}
Assert $caught '拒絕無效版本及路徑穿越名稱'
$caught=$false;try{& $builder -Version 'v1.2.3' -PackageRoot $repo -OutputDirectory $out|Out-Null}catch{$caught=$true}
Assert $caught '拒絕覆寫既有發布檔案'
[IO.File]::WriteAllText((Join-Path $repo 'answer.xml'),'<fixture/>')
Invoke-FixtureGit @('add','answer.xml')
Invoke-FixtureGit @('commit','--quiet','-m','測試拒絕帳號暫存')
$caught=$false;try{& $builder -Version 'v1.2.4' -PackageRoot $repo -OutputDirectory (Join-Path $fixture 'blocked')|Out-Null}catch{$caught=$true}
Assert $caught '拒絕追蹤中的帳號暫存檔'
Assert (-not(Test-Path -LiteralPath (Join-Path $fixture 'blocked'))) '拒絕時不產生版本輸出'
Write-Host ('ALL PASS: '+$script:count+' source-release assertions; no tags, remote, releases or Windows settings changed.')
