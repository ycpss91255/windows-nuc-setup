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
$coverage=[pscustomobject]@{SchemaVersion=1;Scope='all-owned-go-including-cli';Metric='statements';Covered=8;TotalStatements=10;Percent=80.0;Threshold=80;Commit=('a'*40);RunUrl=$arguments.RunUrl;MeasuredAt='2026-11-08T00:00:01Z';SourceState='Clean';GoVersion='go1.27.3';Environment='windows/amd64';ProfileSHA256=('b'*64);Packages=@('windows_setup/script/test/acceptance','windows_setup/script/test/requirements_gate','windows_setup/script/test/verify_deployment')}
$arguments.OutputDirectory=Join-Path $fixture 'measured'
$measured=Write-TestReports @arguments -GoCoverage $coverage
$html=[IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'index.html'))
Assert ($measured.Coverage -eq 'NotMeasured' -and $measured.GoCoverage.Covered -eq 8 -and $html.Contains('Go 程式敘述覆蓋率') -and $html.Contains('80.0%')) 'actual renderer displays measured Go percentage separately from unmeasured PowerShell'
Assert ($html.IndexOf('<h2>Go 程式敘述覆蓋率</h2>') -lt $html.IndexOf('<h2>各項檢查結果</h2>') -and $html.IndexOf('href="go_coverage.out"') -lt $html.IndexOf('<h2>各項檢查結果</h2>')) 'visible Go percentage and evidence downloads precede the long individual-check section'
$markdown=[IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'summary.md'))
Assert ($markdown.Contains('Go 程式敘述覆蓋率：80.0%；範圍為全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式。') -and $markdown.Contains('Go statements: 8/10；門檻 80%')) 'Markdown keeps actual Go percentage scope and raw counts on complete lines'
$badge=[IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'go_coverage.svg'))
Assert ($badge.Contains('go coverage branch: 80.0%') -and $badge.Contains('#97ca00')) 'Go badge identifies scope and actual passing percentage with base 80 percent colour'
[xml]$goSvg=$badge
Assert ($goSvg.SelectSingleNode('//*[local-name()="text"]').InnerText -eq 'go coverage' -and $goSvg.svg.'aria-label'.Contains('branch')) 'Go badge uses short visible label and retains branch scope accessibly'
[xml]$psSvg=Get-Content (Join-Path $arguments.OutputDirectory 'coverage.svg') -Raw
Assert ($psSvg.SelectSingleNode('//*[local-name()="text"]').InnerText -eq 'ps coverage' -and $psSvg.svg.'aria-label'.Contains('branch')) 'PowerShell badge visibly identifies its unmeasured language without duplicate branch text'
Assert ($goSvg.svg.defs.clipPath.rect.rx -eq '3' -and $goSvg.svg.defs.linearGradient.id -eq 's' -and $goSvg.svg.g[0].'clip-path' -eq 'url(#r)' -and @($goSvg.svg.g[1].text).Count -eq 4) 'Go coverage uses flat rounded clip gradient and shadow text'
Assert ($psSvg.svg.defs.clipPath.rect.rx -eq '3' -and @($psSvg.svg.g[1].text).Count -eq 4) 'PowerShell coverage uses the same portable flat SVG template'
foreach($case in @(@(79.9,'#a4a61d'),@(80,'#97ca00'),@(89.9,'#97ca00'),@(90,'#4c1'))){Assert ((Get-GoCoverageColor ([double]$case[0])) -eq $case[1]) ('base palette boundary '+$case[0])}
Assert (([IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'coverage.svg'))).Contains('not measured')) 'existing coverage badge never changes into an overall Go percentage'
Assert ((Get-Content (Join-Path $arguments.OutputDirectory 'go_coverage.json') -Raw|ConvertFrom-Json).Commit -eq $arguments.Commit) 'Go sidecar retains measured source identity'
$coverage.Commit='c'*40
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'coverage from a different commit is rejected'
$coverage.Commit=$arguments.Commit;$coverage.Percent=81
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'display percentage must agree with raw statement counts'
$coverage.Percent=80;$coverage.TotalStatements=0
Refuse {Write-TestReports @arguments -GoCoverage $coverage} 'zero denominator cannot claim measured coverage'
$coverage.TotalStatements=10;$coverage.Percent=70;$coverage.Covered=7
$arguments.OutputDirectory=Join-Path $fixture 'below_threshold'
$null=Write-TestReports @arguments -GoCoverage $coverage
Assert (([IO.File]::ReadAllText((Join-Path $arguments.OutputDirectory 'go_coverage.svg'))).Contains('#a4a61d')) 'below-threshold measured result retains base 70 percent colour'

# Attach real file bytes and preserve them through the actual main portal renderer.
$producer=Join-Path $fixture 'producer';New-Item -ItemType Directory $producer|Out-Null
$profile=Join-Path $producer 'go_coverage.out'
[IO.File]::WriteAllText($profile,"mode: atomic`nwindows_setup/script/test/acceptance/report.go:1.1,1.2 8 1`nwindows_setup/script/test/acceptance/report.go:2.1,2.2 2 0`n",[Text.UTF8Encoding]::new($false))
$coverage.Covered=8;$coverage.Percent=80;$coverage.ProfileSHA256=(Get-FileHash $profile -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $producer 'go_coverage.json'),($coverage|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$arguments.OutputDirectory=Join-Path $fixture 'attach';$null=Write-TestReports @arguments
$attach=Join-Path $root 'script/test/attach_go_coverage.ps1'
& $attach -PublicDirectory $arguments.OutputDirectory -CoverageDirectory $producer
$joined=Get-Content (Join-Path $arguments.OutputDirectory 'summary.json') -Raw|ConvertFrom-Json
Assert ($joined.GoCoverage.ProfileSHA256 -eq $coverage.ProfileSHA256 -and $joined.MeasuredAt -eq $arguments.MeasuredAt) 'attachment binds actual profile without changing original PowerShell measurement time'
Assert ((Get-FileHash (Join-Path $arguments.OutputDirectory 'go_coverage.out')).Hash -eq (Get-FileHash $profile).Hash) 'published profile bytes match measured source file'
$catalog=Join-Path $fixture 'catalog.json';[IO.File]::WriteAllText($catalog,'[]')
$portal=Join-Path $fixture 'portal'
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $portal -MainSnapshotPath (Join-Path $arguments.OutputDirectory 'summary.json') -RequireGoCoverage|Out-Null
Assert ((Get-FileHash (Join-Path $portal 'main/go_coverage.out')).Hash -eq (Get-FileHash $profile).Hash -and (Test-Path (Join-Path $portal 'main/go_coverage.svg'))) 'main portal preserves dedicated Go coverage artifacts'
$portalHome=[IO.File]::ReadAllText((Join-Path $portal 'index.html'))
Assert ($portalHome.Contains('Go 程式敘述覆蓋率：80.0%') -and $portalHome.Contains('8/10 statements') -and $portalHome.Contains('PowerShell 覆蓋率尚未量測') -and -not $portalHome.Contains('程式碼覆蓋率也尚未量測')) 'actual portal homepage presents measured Go separately from unmeasured PowerShell'
$legacyPortal=Join-Path $fixture 'legacy_portal'
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $legacyPortal -MainSnapshotPath (Join-Path $fixture 'legacy/summary.json')|Out-Null
$legacyHome=[IO.File]::ReadAllText((Join-Path $legacyPortal 'index.html'))
Assert ($legacyHome.Contains('程式碼覆蓋率尚未量測') -and -not $legacyHome.Contains('Go 程式敘述覆蓋率：')) 'legacy portal without measured Go never invents a percentage'
Refuse {& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory (Join-Path $fixture 'missing') -MainSnapshotPath (Join-Path $fixture 'legacy/summary.json') -RequireGoCoverage} 'current main publication cannot silently omit measured Go coverage'
$before=(Get-FileHash (Join-Path $arguments.OutputDirectory 'summary.json')).Hash
[IO.File]::AppendAllText($profile,'tampered')
Refuse {& $attach -PublicDirectory $arguments.OutputDirectory -CoverageDirectory $producer} 'tampered raw profile cannot be attached'
Assert ((Get-FileHash (Join-Path $arguments.OutputDirectory 'summary.json')).Hash -eq $before) 'failed attachment leaves original report untouched'
# Exercise orchestration with a process substitute, including native failures.
$global:coverageCalls=New-Object Collections.Generic.List[object]
function global:go.exe {
 $global:coverageCalls.Add(@($args))
 $global:LASTEXITCODE=0
 if($args[0] -eq 'test'){$global:LASTEXITCODE=19}
}
$measure=Join-Path $root 'script/test/measure_go_coverage.ps1'
$failed=$false
try{& $measure -SourceRoot $root -ReportDirectory $arguments.OutputDirectory -OutputDirectory (Join-Path $fixture 'measured_process')}catch{$failed=$_.Exception.Message -match '19'}
Assert ($failed -and $global:coverageCalls.Count -eq 1) 'measurement stops on actual native test failure before producer or attachment'
Assert ($global:coverageCalls[0] -contains '-coverpkg=./script/test/...' -and $global:coverageCalls[0] -contains './...') 'measurement instruments every production Go package while executing all tests'
Remove-Item Function:/go.exe