#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Get-SetupDriverPnpTool -ErrorAction SilentlyContinue)) '原生驅動工具由OS真系統目錄解析'
$expected=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'pnputil.exe'
$saved=$env:SystemRoot
try{
 $env:SystemRoot='X:\untrusted_caller'
 Assert ((Get-SetupDriverPnpTool) -ceq $expected) 'caller改寫SystemRoot不改原生工具位置'
}finally{$env:SystemRoot=$saved}
$fixture=Join-Path $env:TEMP ('driver_native_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
function Get-SetupDriverPnpTool {return 'Invoke-InertPnP'}
function Invoke-InertPnP {param([Parameter(ValueFromRemainingArguments=$true)][object[]]$NativeArgs) $script:arguments=$NativeArgs;$global:LASTEXITCODE=3010;return 'inert native driver output'}
$result=Invoke-SetupDriverInfInstall -InfPath 'C:\fixture space\driver.inf' -LogPath (Join-Path $fixture 'native.log')
Assert ($result.ExitCode -eq 3010 -and ($script:arguments -join '|') -ceq '/add-driver|C:\fixture space\driver.inf|/install') '真正adapter保持原生參數與重開機退出碼，不自動重開'
Assert ((Get-Content -LiteralPath (Join-Path $fixture 'native.log') -Raw).Contains('inert native driver output')) '原生輸出保留紀錄'
