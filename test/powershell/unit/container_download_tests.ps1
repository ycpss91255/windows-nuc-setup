#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$library=Join-Path $root 'script/docker/download_library.ps1';if(Test-Path $library){. $library}
Assert ([bool](Get-Command Invoke-ContainerOfficialDownload -ErrorAction SilentlyContinue)) '官方下載需要固定上限重試，不因504立即丟失整次Docker測試'
class DownloadFixtureResponse : System.Net.WebResponse {
 [int]$StatusCode
 DownloadFixtureResponse([int]$Code){$this.StatusCode=$Code}
}
$temp=Join-Path $env:TEMP ('download_fixture_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:expectedUri='https://example.invalid/official.zip'
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction,$TimeoutSec)
 $script:calls++;Assert ($Uri -ceq $script:expectedUri -and $TimeoutSec -eq 120 -and $UseBasicParsing -and $ErrorAction -ceq 'Stop') '相同HTTPS來源與明確timeout保持'
 [IO.File]::WriteAllText($OutFile,'partial-or-complete')
 $code=$script:codes[[Math]::Min($script:calls-1,$script:codes.Count-1)]
 if($code -eq -1){throw [Net.WebException]::new('fixture timeout',$null,[Net.WebExceptionStatus]::Timeout,$null)}
 if($code -gt 0){throw [Net.WebException]::new('fixture HTTP',$null,[Net.WebExceptionStatus]::ProtocolError,[DownloadFixtureResponse]::new($code))}
 if($code -eq -2){throw 'non-network fixture failure'}
}
function Start-Sleep {param($Seconds);$script:sleeps+=@($Seconds);Assert (@(Get-ChildItem $temp -Filter '*.partial' -File).Count -eq 0) 'backoff之前已清理本次半檔'}
foreach($case in @('transient','persistent','404','timeout','non-network','429')){
 $script:calls=0;$script:sleeps=@();$script:codes=switch($case){transient{@(504,0)}persistent{@(504)}'404'{@(404)}timeout{@(-1,0)}'non-network'{@(-2)}'429'{@(429,0)}}
 $out=Join-Path $temp ($case+'.zip');$accepted=$true
 try{Invoke-ContainerOfficialDownload -Uri 'https://example.invalid/official.zip' -OutFile $out}catch{$accepted=$false}
 $success=$case -in @('transient','timeout','429');$expected=if($case -eq 'persistent'){3}elseif($success){2}else{1}
 Assert ($accepted -eq $success -and $script:calls -eq $expected) ('僅timeout或暫時HTTP重試且最多三次 '+$case)
 Assert ((Test-Path $out) -eq $success -and @(Get-ChildItem $temp -Filter '*.partial' -File).Count -eq 0) ('失敗不接受半檔cache '+$case)
 if($case -eq 'persistent'){Assert (($script:sleeps -join ',') -ceq '1,2') '連續504的backoff有界'}
}
$existing=Join-Path $temp 'existing.zip';[IO.File]::WriteAllText($existing,'original');$script:calls=0;$rejected=$false
try{Invoke-ContainerOfficialDownload -Uri 'https://example.invalid/official.zip' -OutFile $existing}catch{$rejected=$true}
Assert ($rejected -and $script:calls -eq 0 -and [IO.File]::ReadAllText($existing) -ceq 'original') '不把既有或未知cache當成成功也不覆寫'
. (Join-Path $root 'script/docker/install_managed_tools.ps1')
$fixtureContent=Join-Path $temp 'expected.bin';[IO.File]::WriteAllText($fixtureContent,'partial-or-complete')
$artifact=[pscustomobject]@{Name='fixture.zip';Uri='https://example.invalid/official.zip';Algorithm='SHA256';Hash=(Get-FileHash $fixtureContent).Hash;Kind='File';HashFormat='Hex'}
$script:calls=0;$script:sleeps=@();$script:codes=@(504,0);$target=Join-Path $temp 'target.bin';$stage=Join-Path $temp 'stage';$accepted=$true
try{Install-ContainerToolArtifact -Artifact $artifact -Destination $target -ArchiveDirectory $stage}catch{$accepted=$false}
Assert ($accepted -and $script:calls -eq 2 -and (Get-FileHash $target).Hash -ceq $artifact.Hash) '正式managed安裝器使用同URL重試並保留真hash驗證'
$artifact.Name='bad.zip';$artifact.Hash='0'*64;$script:calls=0;$script:codes=@(0);$accepted=$true
try{Install-ContainerToolArtifact -Artifact $artifact -Destination (Join-Path $temp 'bad.bin') -ArchiveDirectory $stage}catch{$accepted=$false}
Assert (-not $accepted -and $script:calls -eq 1 -and -not(Test-Path (Join-Path $stage 'bad.zip')) -and -not(Test-Path (Join-Path $temp 'bad.bin'))) '雜湊失敗不重試、不安裝且不保留未信任cache'
function Expand-Archive {param($LiteralPath,$DestinationPath);$script:expansions++;throw 'untrusted data must not be extracted'}
$oldTemp=$env:TEMP
try{
 $env:TEMP=Join-Path $temp 'installer_temp';[void][IO.Directory]::CreateDirectory($env:TEMP)
 foreach($installer in @('install_min_git.ps1','install_go.ps1')){
  $script:calls=0;$script:codes=@(0);$script:expansions=0
  $script:expectedUri=if($installer -eq 'install_go.ps1'){'https://go.dev/dl/go1.27.3.windows-amd64.zip'}else{'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/MinGit-2.56.0.4-64-bit.zip'}
  $message='';try{. (Join-Path $root ('script/docker/'+$installer))}catch{$message=$_.Exception.Message}
  Assert ($message -like '*SHA256 mismatch*' -and $script:calls -eq 1 -and $script:expansions -eq 0 -and @(Get-ChildItem $env:TEMP -File).Count -eq 0) ('正式入口錯hash不解壓或保留cache '+$installer)
 }
}finally{$env:TEMP=$oldTemp}
Write-Host 'ALL PASS: bounded official downloads; TEMP and mocked HTTP only'
