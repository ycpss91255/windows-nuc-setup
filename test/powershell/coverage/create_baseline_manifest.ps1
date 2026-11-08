#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $SourceRoot).Path
if(Test-Path -LiteralPath $OutputPath){throw '基線清單輸出已存在。'}
# Reviewed standalone suites only. Never include the collector's recursive PoC.
$unit=@('hardware_confirmation','hardware','init','input_method','report')
$integration=@('architecture','container_tools','desktop_safety','driver_prompt','go_coverage','hardware_confirmation','hardware','hosts_sync','init','layout','module_identity','naming','portal','runtime_failures','source_release','ssh_client','ssh_firewall','usb_portability')
$tests=@($unit|ForEach-Object {'test/powershell/unit/'+$_+'_tests.ps1'})+@($integration|ForEach-Object {'test/powershell/integration/'+$_+'_tests.ps1'})
foreach($test in $tests){if(-not(Test-Path -LiteralPath (Join-Path $source $test) -PathType Leaf)){throw ('安全測試遺失：'+$test)}}
$tracked=@(& git -C $source ls-files '*.ps1')
if($LASTEXITCODE -ne 0){throw '無法取得版本控制來源清單。'}
$sources=@($tracked|Where-Object {$_ -match '^(core|modules|script)/' -and $_ -notmatch '^modules/debloat/win11debloat/'}|Sort-Object)
if(-not $sources.Count){throw '正式 PowerShell 來源清單為空。'}
$manifest=[ordered]@{SourceRoot=$source;Sources=$sources;Tests=$tests;Wrapper='test/powershell/coverage/safe_suite.ps1'}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Host ('已準備 '+$sources.Count+' 個正式來源與 '+$tests.Count+' 個獨立安全 suite。')
