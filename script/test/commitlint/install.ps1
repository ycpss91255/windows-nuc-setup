param([string]$Repository = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'main.go'
& go run $source install $Repository
exit $LASTEXITCODE
