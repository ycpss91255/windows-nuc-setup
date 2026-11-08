#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/download_library.ps1')
class DownloadDiagnosticResponse : System.Net.WebResponse {
 [int]$StatusCode
 DownloadDiagnosticResponse([int]$Code){$this.StatusCode=$Code}
}
$script:messages=@()
function Write-Host {param([object[]]$Object);$text=$Object -join ' ';if($text.StartsWith('Official download')){$script:messages+=@($text)}else{Microsoft.PowerShell.Utility\Write-Host $text}}
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
function Test-ControlledFailureEvent([string]$Message,[string]$Reason,[bool]$Retry){
 $pattern='\AOfficial download failure: '+[regex]::Escape($Reason)+'; retry='+$Retry.ToString().ToLowerInvariant()+'; elapsed_ms=(0|[1-9][0-9]{0,18})\.\z'
 $match=[regex]::Match($Message,$pattern);$elapsed=0L
 return ($match.Success -and [long]::TryParse($match.Groups[1].Value,[ref]$elapsed) -and $elapsed -ge 0)
}
foreach($elapsed in @('0','1',[long]::MaxValue.ToString([Globalization.CultureInfo]::InvariantCulture))){
 Assert (Test-ControlledFailureEvent ('Official download failure: HTTP 504; retry=false; elapsed_ms='+$elapsed+'.') 'HTTP 504' $false) '完整受控診斷接受非負Int64耗時且不採用任意suffix'
}
foreach($bad in @('-1','+1','1.5','1e3','001','9223372036854775808','https://example.invalid/private','C:/Users/private')){
 Assert (-not(Test-ControlledFailureEvent ('Official download failure: HTTP 504; retry=false; elapsed_ms='+$bad+'.') 'HTTP 504' $false)) '診斷比對拒絕非法數字、溢位或私人內容'
}
foreach($bad in @('Official download failure: HTTP 504; retry=true; elapsed_ms=1.','Official download failure: HTTP 404; retry=false; elapsed_ms=1.','Official download failure: HTTP 504; retry=false; elapsed_ms=1. SECRET',"Official download failure: HTTP 504; retry=false; elapsed_ms=1.`nSECRET")){
 Assert (-not(Test-ControlledFailureEvent $bad 'HTTP 504' $false)) '診斷比對不能忽略錯誤原因、retry或尾隨內容'
}
function Start-Sleep {param($Seconds)}
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec,$ErrorAction)
 $script:calls++;[IO.File]::WriteAllText($OutFile,'fixture')
 if($script:failure -eq 'Timeout'){throw [Net.WebException]::new('SECRET-URI-PATH',$null,[Net.WebExceptionStatus]::Timeout,$null)}
 throw [Net.WebException]::new('SECRET-URI-PATH',$null,[Net.WebExceptionStatus]::ProtocolError,[DownloadDiagnosticResponse]::new($script:status))
}
$temp=Join-Path $env:TEMP ('download_diagnostics_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
foreach($case in @('504','Timeout','404')){
 $script:messages=@();$script:calls=0;$script:failure=$case;$script:status=if($case -eq '504'){504}else{404}
 $failed=$false;try{Invoke-ContainerOfficialDownload -Uri 'https://example.invalid/SECRET-URI-PATH' -OutFile (Join-Path $temp ($case+'.zip'))}catch{$failed=$true}
 $expected=if($case -eq '404'){1}else{3}
 $attempts=@($script:messages|Where-Object {$_ -like 'Official download attempt *'})
 Assert ($failed -and $script:calls -eq $expected -and $attempts.Count -eq $expected -and $attempts[0] -ceq 'Official download attempt 1/3.') ('真重試次數可觀察且沒有改上限 '+$case)
 $reason=if($case -eq 'Timeout'){'Timeout'}else{'HTTP '+$case}
 $events=@($script:messages|Where-Object {$_ -like 'Official download failure:*'})
 $controlled=$events.Count -eq $expected
 for($i=0;$i -lt $events.Count;$i++){$controlled=$controlled -and (Test-ControlledFailureEvent $events[$i] $reason ($i -lt $expected-1))}
 Assert $controlled ('每一次失敗訊息都有完整受控原因、實際retry與非負有界耗時 '+$case)
 Assert ($events.Count -eq $expected -and $events[-1] -ceq ('Official download failure: '+$reason+'; retry=false.')) ('只輸出受控原因與實際最終retry決策 '+$case)
 Assert (-not(($script:messages -join '|').Contains('SECRET')) -and -not(($script:messages -join '|').Contains($temp))) ('不輸出URI例外訊息或私人路徑 '+$case)
}
Write-Host 'ALL PASS: bounded download diagnostics; TEMP and typed HTTP doubles only'
