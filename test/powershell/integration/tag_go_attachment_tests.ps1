#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('tag_go_staging_'+[guid]::NewGuid().ToString('N'))
$attach=Join-Path $root 'script/test/attach_go_coverage.ps1'
function New-Case([string]$Name,[string]$RefType='Release',[int]$SchemaVersion=2){
 $directory=Join-Path $fixture $Name;$public=Join-Path $directory 'NUC-CI-Results/public';$producer=Join-Path $directory 'go-coverage'
 [void][IO.Directory]::CreateDirectory($producer)
 $checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=('synthetic_'+$layer);Layer=$layer;Executed=$true;Passed=$true;Status='Passed';ExitCode=0;Assertions=@([pscustomobject]@{Name='explicit synthetic staging fixture';Passed=$true})}})
 $refName=if($RefType -eq 'Release'){'v1.2.3'}else{'main'}
 $null=Write-TestReports -Checks $checks -OutputDirectory $public -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/123' -SourceState Clean -Version v1.2.3 -Environment 'Synthetic staging fixture' -RefType $RefType -RefName $refName -MeasuredAt '2026-11-09T00:00:00Z' -SchemaVersion $SchemaVersion
 $profile=Join-Path $producer 'go_coverage.out'
 [IO.File]::WriteAllText($profile,"mode: atomic`nwindows_setup/script/test/acceptance/report.go:1.1,1.2 8 1`nwindows_setup/script/test/acceptance/report.go:2.1,2.2 2 0`n",[Text.UTF8Encoding]::new($false))
 $coverage=[ordered]@{SchemaVersion=1;Scope='all-owned-go-including-cli';Metric='statements';Covered=8;TotalStatements=10;Percent=80.0;Threshold=80;Commit=('a'*40);RunUrl='https://github.com/example/repo/actions/runs/123';MeasuredAt='2026-11-09T00:00:01Z';SourceState='Clean';GoVersion='go1.27.3';Environment='windows/amd64';ProfileSHA256=(Get-FileHash -LiteralPath $profile).Hash.ToLowerInvariant();Packages=@('windows_setup/script/test/acceptance')}
 [IO.File]::WriteAllText((Join-Path $producer 'go_coverage.json'),($coverage|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 return [pscustomobject]@{Directory=$directory;Public=$public;Producer=$producer;Summary=(Join-Path $public 'summary.json')}
}
function Run-Attach($Case,[switch]$PreparingRelease){
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$attach,'-PublicDirectory',$Case.Public,'-CoverageDirectory',$Case.Producer)
 if($PreparingRelease){$arguments+=@('-PreparingRelease')}
 $prior=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& powershell.exe @arguments *> (Join-Path $Case.Directory 'attach.private.log');return $LASTEXITCODE}finally{$ErrorActionPreference=$prior}
}
function Reject-Unchanged($Case,[string]$Name){
 $before=(Get-FileHash -LiteralPath $Case.Summary).Hash
 Assert ((Run-Attach $Case -PreparingRelease) -ne 0) $Name
 Assert ((Get-FileHash -LiteralPath $Case.Summary).Hash -ceq $before -and -not(Test-Path -LiteralPath (Join-Path $Case.Public 'go_coverage.out'))) ($Name+' leaves the original staging report untouched')
}
$tag=New-Case 'tag'
Assert ((Run-Attach $tag) -ne 0) 'Release reports still require explicit unpublished-staging intent'
Assert ((Run-Attach $tag -PreparingRelease) -eq 0) 'native Tag staging attaches measured Go metadata and raw bytes before publication'
$joined=Get-Content -LiteralPath $tag.Summary -Raw|ConvertFrom-Json
Assert ($joined.RefType -ceq 'Release' -and $joined.RefName -ceq 'v1.2.3' -and $joined.GoCoverage.Covered -eq 8 -and $joined.Coverage -ceq 'NotMeasured') 'Tag attachment preserves identity and does not invent whole-repo coverage'
Assert ((Get-FileHash -LiteralPath (Join-Path $tag.Public 'go_coverage.out')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $tag.Producer 'go_coverage.out')).Hash) 'Tag staging contains the exact measured profile bytes'
$before=(Get-FileHash -LiteralPath $tag.Summary).Hash
Assert ((Run-Attach $tag -PreparingRelease) -ne 0 -and (Get-FileHash -LiteralPath $tag.Summary).Hash -ceq $before) 'already-attached Release evidence cannot be rewritten'
$legacy=New-Case 'legacy' 'Release' 1;Reject-Unchanged $legacy 'historical schema1 Release cannot gain fabricated modern evidence'
foreach($mutation in @('commit','run','profile','missing_profile','below_threshold','dirty')){
 $case=New-Case $mutation;$path=Join-Path $case.Producer 'go_coverage.json';$c=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 switch($mutation){
  commit{$c.Commit='b'*40}
  run{$c.RunUrl='https://github.com/example/repo/actions/runs/124'}
  profile{[IO.File]::AppendAllText((Join-Path $case.Producer 'go_coverage.out'),'tampered')}
  missing_profile{Remove-Item -LiteralPath (Join-Path $case.Producer 'go_coverage.out')}
  below_threshold{$c.Covered=7;$c.Percent=70;[IO.File]::WriteAllText((Join-Path $case.Producer 'go_coverage.out'),"mode: atomic`nwindows_setup/script/test/acceptance/report.go:1.1,1.2 7 1`nwindows_setup/script/test/acceptance/report.go:2.1,2.2 3 0`n");$c.ProfileSHA256=(Get-FileHash -LiteralPath (Join-Path $case.Producer 'go_coverage.out')).Hash.ToLowerInvariant()}
  dirty{$report=Get-Content -LiteralPath $case.Summary -Raw|ConvertFrom-Json;$report.SourceState='Dirty';[IO.File]::WriteAllText($case.Summary,($report|ConvertTo-Json -Depth 20))}
 }
 [IO.File]::WriteAllText($path,($c|ConvertTo-Json -Depth 8));Reject-Unchanged $case ('invalid Tag evidence is rejected: '+$mutation)
}
# Execute the actual producer step for both events, using only synthetic local reports.
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$step=[regex]::Match($workflow,'(?ms)^      - name: 附加分項 Go 證據\r?\n(?<body>.*?)(?=^      - name:|\z)').Groups['body'].Value
Assert ($step -and $step -notmatch '(?m)^        if:') 'both branch and Tag events execute the Go producer step'
$run=[regex]::Match($step,'(?ms)^        run: \|\r?\n(?<run>.*)').Groups['run'].Value -replace '(?m)^          ',''
$oldTemp=$env:RUNNER_TEMP;$oldType=$env:GITHUB_REF_TYPE
Push-Location $root
try{
 foreach($event in @('branch','tag')){
  $kind=if($event -eq 'tag'){'Release'}else{'Branch'};$case=New-Case ('workflow_'+$event) $kind
  $env:RUNNER_TEMP=$case.Directory;$env:GITHUB_REF_TYPE=$event
  & ([scriptblock]::Create($run))
  $report=Get-Content -LiteralPath $case.Summary -Raw|ConvertFrom-Json
  Assert ($report.GoCoverage.Covered -eq 8 -and (Test-Path -LiteralPath (Join-Path $case.Public 'go_coverage.out'))) ('actual workflow run step attaches metadata and profile for '+$event)
 }
}finally{$env:RUNNER_TEMP=$oldTemp;$env:GITHUB_REF_TYPE=$oldType;Pop-Location}
$global:LASTEXITCODE=0
