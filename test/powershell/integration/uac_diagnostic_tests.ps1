#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$log=Join-Path ([IO.Path]::GetTempPath()) ('uac_diagnostic_'+[guid]::NewGuid().ToString('N')+'.log')
$ErrorActionPreference='Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test/powershell/unit/uac_helpers_tests.ps1') -DiagnosticProbe *> $log
$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
$text=Get-Content -LiteralPath $log -Raw -Encoding UTF8
Assert ($code -ne 0 -and $text.Contains('fixture expected message') -and $text.Contains('fixture actual message')) '負例診斷保留安全fixture的預期與實際錯誤，不以模糊FAIL掩蓋原因'