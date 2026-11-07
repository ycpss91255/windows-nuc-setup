#Requires -Version 5.1
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$uri='https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/MinGit-2.56.0.4-64-bit.zip'
$expected='e3bf78351fe777fba47ddee5950082f8a98bb0f02604fdc7ba3ee2cb68ffa877'
$archive=Join-Path $env:TEMP 'min_git.zip'
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $archive
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'MinGit SHA256 mismatch.'}
Expand-Archive -LiteralPath $archive -DestinationPath C:/git
Remove-Item -LiteralPath $archive
