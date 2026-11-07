#Requires -Version 5.1
$ErrorActionPreference='Stop'
try {
 foreach($tool in @('powershell.exe','cmd.exe','git.exe','go.exe')){Get-Command $tool -CommandType Application -ErrorAction Stop|Out-Null}
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
 . C:/workspace/script/docker/acceptance.ps1
 Initialize-ContainerGoEnvironment -SourceRoot C:/workspace -CacheRoot (Join-Path $env:TEMP ('container_go_'+[guid]::NewGuid().ToString('N')))
 $fixture=Join-Path $env:TEMP ('container_acceptance_'+[guid]::NewGuid().ToString('N'))
 $plan=Get-ContainerAcceptancePlan -ReportDirectory C:/reports -FixtureDirectory $fixture
 Write-Host 'Phase 1: actual PowerShell unit and isolated integration suites.'
 & C:/workspace/script/test/run_ci.ps1 -Layer All -ReportDirectory C:/reports
 Write-Host 'Phase 2: private, explicitly synthetic renderer fixture.'
 & C:/workspace/script/test/create_portal_fixture.ps1 -OutputDirectory $fixture
 if($plan.Mode -eq 'LocalSynthetic'){Write-Host 'Local mode: Go contract checks use synthetic evidence; actual local PowerShell metadata is preserved in reports/public. This is not published CI evidence.'}
 Write-Host ('Phase 3: Go acceptance tests / '+$plan.Mode)
 $env:WINDOWS_SETUP_ARTIFACT_DIR=$plan.ArtifactDirectory
 $env:WINDOWS_SETUP_PORTAL_FIXTURE_DIR=Join-Path $fixture 'portal'
 Invoke-ContainerGoTestPhase -Plan $plan -SourceRoot C:/workspace -ReportDirectory C:/reports
 Write-Host ('Phase 4: source and report requirements gate / '+$plan.Mode)
 Invoke-ContainerGo -Arguments @('run','./script/test/requirements_gate','--artifact-dir',$plan.ArtifactDirectory,'--source-root','C:/workspace','--expected-sha',$plan.Commit,'--expected-run-url',$plan.RunUrl)
 exit 0
} catch {
 Write-Error $_ -ErrorAction Continue
 exit 1
}
