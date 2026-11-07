#Requires -Version 5.1
$ErrorActionPreference='Stop'
try {
 if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Windows PowerShell 5.1 required.'}
 $null=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 & git.exe --version
 if($LASTEXITCODE -ne 0){throw 'Git is required.'}
 & git.exe config --global --add safe.directory C:/workspace
 if($LASTEXITCODE -ne 0){throw 'Cannot configure checkout ownership exception.'}
 if(-not(Test-Path C:/workspace/.git -PathType Container)){throw 'A complete Git checkout must be mounted read-only.'}
 $env:GIT_OPTIONAL_LOCKS='0'
 $env:WINDOWS_SETUP_TEST_CONTEXT='Windows container'
 Set-Location C:/workspace
 & C:/workspace/script/test/run_ci.ps1 -Layer All -ReportDirectory C:/reports
 exit 0
} catch {
 Write-Error $_ -ErrorAction Continue
 exit 1
}
