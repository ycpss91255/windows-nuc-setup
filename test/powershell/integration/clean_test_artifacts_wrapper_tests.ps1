#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$wrapper = Join-Path $repo 'script/test/clean_test_artifacts.ps1'
if (-not [IO.File]::Exists($wrapper)) { throw 'SPEC MISSING: PowerShell cleanup entry point' }
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temp ('windows_setup_wrapper_test_' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$root = Join-Path $fixture 'owned root'
$ps = (Get-Process -Id $PID).Path
function Invoke-Wrapper([string[]]$Arguments, [int]$Expected) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $wrapper @Arguments 2>&1); $actual = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if (($Expected -eq 0 -and $actual -ne 0) -or ($Expected -ne 0 -and $actual -eq 0)) { throw "Unexpected exit code: $actual; $($output -join ' ')" }
    return ($output -join "`n")
}
Push-Location $fixture
try {
    [void](Invoke-Wrapper @('init', $root) 0)
    [void](Invoke-Wrapper @('create', $root, 'item') 0)
    $payload = Join-Path $root 'item/payload'
    [IO.File]::WriteAllText($payload, 'owned fixture')
    [void](Invoke-Wrapper @('finish', $root, 'item', '2000-01-01T00:00:00Z') 0)
    $preview = Invoke-Wrapper @('clean', $root, 'item') 0
    if ($preview -notmatch ([string][char]0x5019 + [char]0x9078) -or -not [IO.File]::Exists($payload)) { throw 'Preview must identify candidate and retain file' }
    [void](Invoke-Wrapper @('clean', $root, 'item', '--invalid') 1)
    if (-not [IO.File]::Exists($payload)) { throw 'Invalid option deleted data' }
    [void](Invoke-Wrapper @('clean', $root, 'item', '--delete') 0)
    if ([IO.Directory]::Exists((Join-Path $root 'item'))) { throw 'Explicit deletion left item' }
    Write-Output 'PASS: PS5 wrapper, preview, options and owned data'
} finally { Pop-Location }
