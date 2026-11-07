#Requires -Version 5.1
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
# Official release manifest: https://www.python.org/ftp/python/3.13.17/windows-3.13.17.json
$uri='https://www.python.org/ftp/python/3.13.17/python-3.13.17-amd64.zip'
$expected='b26ca4b4ee51e157836049934d2b8eabd55939be296f3130254251b6df96ec2f'
$archive=Join-Path $env:TEMP 'python.zip'
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $archive
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'Python SHA256 mismatch.'}
Expand-Archive -LiteralPath $archive -DestinationPath C:/python
Remove-Item -LiteralPath $archive
& C:/python/python.exe -X utf8 -B -c 'import sys, unittest, xml.etree.ElementTree; assert sys.version_info[:3] == (3, 13, 17)'
if($LASTEXITCODE -ne 0){throw 'Pinned Python runtime check failed.'}
