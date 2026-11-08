#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('nested_diagnostic_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
$failed=Join-Path $fixture 'controlled_tests.ps1';$runner=Join-Path $fixture 'runner.ps1';$log=Join-Path $fixture 'parent.private.log'
[IO.File]::WriteAllText($failed,@'
Write-Host ('@@ASSERT@@'+(@{Name='PRIVATE_DO_NOT_PUBLISH C:\Users\private-account\password-token';Passed=$false}|ConvertTo-Json -Compress))
throw 'PRIVATE_DO_NOT_PUBLISH C:\Users\private-account\password-token'
'@,[Text.UTF8Encoding]::new($true))
$text=@'
$ErrorActionPreference='Stop'
$native=(Get-Command powershell.exe -CommandType Application).Source
function powershell.exe {
 param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
 $argsList=@($Arguments)
 $suiteIndex=[array]::IndexOf($argsList,'-SuitePath')
 if($suiteIndex -ge 0){$argsList[$suiteIndex+1]='__FAILED__'}else{$argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File','__FAILED__')}
 & $native @argsList
 $global:LASTEXITCODE=$LASTEXITCODE
}
& '__ORIGINAL__'
'@
$text=$text.Replace('__FAILED__',$failed.Replace("'","''")).Replace('__ORIGINAL__',(Join-Path $root 'test/powershell/integration/short_temp_fixture_tests.ps1').Replace("'","''"))
[IO.File]::WriteAllText($runner,$text,[Text.UTF8Encoding]::new($true))
$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
$output=[IO.File]::ReadAllText($log)
$passed=($code -eq 1 -and $output.Contains('child-case=1') -and -not $output.Contains('PRIVATE_DO_NOT_PUBLISH'))
Write-Host ('@@ASSERT@@'+(@{Name='真正nested child失敗保留退出1並公開固定失敗序號，私有訊息不外洩';Passed=$passed}|ConvertTo-Json -Compress))
if(-not $passed){throw 'Nested child failure needs safe diagnostics without publishing its private log.'}
