#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'download_library.ps1')
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
# Official release metadata: https://go.dev/dl/?mode=json
$uri='https://go.dev/dl/go1.27.3.windows-amd64.zip'
$expected='f26081f438319757f8a1b46d7d0b2c5ec7583d4038e485e0aa725cfde7885fff'
$archive=Join-Path $env:TEMP 'go.zip'
Invoke-ContainerOfficialDownload -Uri $uri -OutFile $archive
try{
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'Go SHA256 mismatch.'}
# The official archive contains a top-level go directory.
$watch=[Diagnostics.Stopwatch]::StartNew();Write-Host 'Verified Go extraction started.'
try{Expand-ContainerToolArchive -LiteralPath $archive -DestinationPath C:/}
finally{Write-Host ('Verified Go extraction elapsed_ms='+$watch.ElapsedMilliseconds+'.')}
}finally{if(Test-Path -LiteralPath $archive){Remove-Item -LiteralPath $archive -Force}}
$env:GOTOOLCHAIN='local'
$version=& C:/go/bin/go.exe version
if($LASTEXITCODE -ne 0 -or $version -cne 'go version go1.27.3 windows/amd64'){throw 'Pinned Go runtime check failed.'}
