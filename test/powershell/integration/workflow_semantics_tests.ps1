#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$runName=[regex]::Match($workflow, '(?m)^run-name:\s*(.+)$')
Assert ($runName.Success -and $runName.Groups[1].Value -match '\$\{\{') 'workflow has a dynamic top-level run name'
$name=$runName.Groups[1].Value
foreach($context in @('github.event_name','github.event.pull_request.number','github.event.pull_request.title','github.ref_name','github.sha')) {
    Assert ($name.Contains($context)) ('run name includes ' + $context)
}
Assert ($name.Contains('||')) 'run name includes fallback for missing event data'
$tool=$env:WINDOWS_SETUP_ACTIONLINT
if(-not $tool){$tool=(Get-Command actionlint.exe -CommandType Application -ErrorAction Stop).Source}
$version=@(& $tool -version)
Assert ($LASTEXITCODE -eq 0 -and $version[0] -eq '1.7.12') 'workflow semantics use the pinned real actionlint release'
$previous=$ErrorActionPreference
$temp=Join-Path $env:TEMP ('workflow_semantics_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$bad=Join-Path $temp 'bad.yml';$good=Join-Path $temp 'good.yml'
[IO.File]::WriteAllText($bad,@'
name: invalid job context
on: push
jobs:
  test:
    runs-on: windows-2022
    env:
      TOOL: ${{ runner.temp }}/tool.exe
    steps:
      - run: echo fixture
'@)
[IO.File]::WriteAllText($good,@'
name: valid step context
on: push
jobs:
  test:
    runs-on: windows-2022
    steps:
      - run: echo fixture
        env:
          TOOL: ${{ runner.temp }}/tool.exe
'@)
try{$ErrorActionPreference='Continue';$result=@(& $tool -shellcheck= -pyflakes= $bad 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
Assert ($code -ne 0 -and (($result -join "`n") -match 'context "runner" is not allowed here')) 'real semantic checker rejects valid YAML with runner context at job env'
try{$ErrorActionPreference='Continue';& $tool -shellcheck= -pyflakes= $good;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
Assert ($code -eq 0) 'same runner expression is valid within step env'

try{$ErrorActionPreference='Continue';$result=@(& $tool -shellcheck= -pyflakes= (Join-Path $root '.github/workflows/windows_tests.yml') 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
if($code -ne 0){$result|ForEach-Object {Write-Host $_}}
Assert ($code -eq 0) 'actual GitHub workflow passes context availability and expression semantics'
