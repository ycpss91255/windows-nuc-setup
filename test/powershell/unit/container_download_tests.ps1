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
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction,$TimeoutSec)
 $script:calls++;Assert ($Uri -ceq 'https://example.invalid/official.zip' -and $TimeoutSec -eq 120 -and $UseBasicParsing -and $ErrorAction -ceq 'Stop') '相同HTTPS來源與明確timeout保持'
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
Write-Host 'ALL PASS: bounded official downloads; TEMP and mocked HTTP only'
