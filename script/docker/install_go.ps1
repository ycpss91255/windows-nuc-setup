#Requires -Version 5.1
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
# Official release metadata: https://go.dev/dl/?mode=json
$uri='https://go.dev/dl/go1.27.3.windows-amd64.zip'
$expected='f26081f438319757f8a1b46d7d0b2c5ec7583d4038e485e0aa725cfde7885fff'
$archive=Join-Path $env:TEMP 'go.zip'
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $archive
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'Go SHA256 mismatch.'}
# The official archive contains a top-level go directory.
Expand-Archive -LiteralPath $archive -DestinationPath C:/
Remove-Item -LiteralPath $archive
$env:GOTOOLCHAIN='local'
$version=& C:/go/bin/go.exe version
if($LASTEXITCODE -ne 0 -or $version -cne 'go version go1.27.3 windows/amd64'){throw 'Pinned Go runtime check failed.'}
