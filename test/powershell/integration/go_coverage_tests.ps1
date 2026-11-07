#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
$fixture=Join-Path $env:TEMP ('go_coverage_render_'+[guid]::NewGuid().ToString('N'))
$checks=@([pscustomobject]@{Name='fixture_unit';Layer='Unit';Executed=$true;Passed=$true;Status='Passed';ExitCode=0;Assertions=@([pscustomobject]@{Name='unit';Passed=$true})},[pscustomobject]@{Name='fixture_integration';Layer='Integration';Executed=$true;Passed=$true;Status='Passed';ExitCode=0;Assertions=@([pscustomobject]@{Name='integration';Passed=$true})})
$arguments=@{Checks=$checks;OutputDirectory=(Join-Path $fixture 'legacy');Commit=('a'*40);RunUrl='https://github.com/example/repo/actions/runs/123';SourceState='Clean';Version='v1.0.0';Environment='Windows fixture';RefType='Branch';RefName='main';MeasuredAt='2026-11-08T00:00:00Z'}
$legacy=Write-TestReports @arguments
Assert ($legacy.Coverage -eq 'NotMeasured' -and -not $legacy.PSObject.Properties['GoCoverage']) 'historical reports keep unmeasured PowerShell coverage without invented Go evidence'
$coverage=[pscustomobject]@{SchemaVersion=1;Scope='all-owned-go-including-cli';Metric='statements';CoveredStatements=8;TotalStatements=10;Percent=80.0;Threshold=80;Commit=('a'*40);RunUrl=$arguments.RunUrl;MeasuredAt='2026-11-08T00:00:01Z';SourceState='Clean';GoVersion='go1.27.3';Environment='windows/amd64';ProfileSHA256=('b'*64);Packages=@('windows_setup/script/test/acceptance','windows_setup/script/test/requirements_gate','windows_setup/script/test/verify_deployment')}
$arguments.OutputDirectory=Join-Path $fixture 'measured'
$measured=Write-TestReports @arguments -GoCoverage $coverage
$html=[IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'index.html'))
Assert ($measured.Coverage -eq 'NotMeasured' -and $measured.GoCoverage.CoveredStatements -eq 8 -and $html.Contains('Go 程式敘述覆蓋率') -and $html.Contains('80.0%')) 'actual renderer displays measured Go percentage separately from unmeasured PowerShell'
$badge=[IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'go_coverage.svg'))
Assert ($badge.Contains('go coverage branch: 80.0%') -and $badge.Contains('#4c1')) 'Go badge identifies scope and actual passing percentage'
Assert (([IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'coverage.svg'))).Contains('not measured')) 'existing coverage badge never changes into an overall Go percentage'
Assert ((Get-Content (Join-Path $arguments.OutputDirectory 'go_coverage.json') -Raw|ConvertFrom-Json).Commit -eq $arguments.Commit) 'Go sidecar retains measured source identity'
$coverage.Commit='c'*40
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'coverage from a different commit is rejected'
$coverage.Commit=$arguments.Commit;$coverage.Percent=81
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'display percentage must agree with raw statement counts'
$coverage.Percent=80;$coverage.TotalStatements=0
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'zero denominator cannot claim measured coverage'
$coverage.TotalStatements=10;$coverage.Percent=70;$coverage.CoveredStatements=7
$arguments.OutputDirectory=Join-Path $fixture 'below_threshold'
$null=Write-TestReports @arguments -GoCoverage $coverage
Assert (([IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'go_coverage.svg'))).Contains('#e05d44')) 'below-threshold measured result stays visible as failed coverage'
