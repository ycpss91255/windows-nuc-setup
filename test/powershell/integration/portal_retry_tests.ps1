#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$parent = Join-Path ([IO.Path]::GetTempPath()) ('portal_retry_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $parent | Out-Null
$script:downloadCalls = 0
function global:gh {
 $global:LASTEXITCODE = 0
 $argsText = $args -join ' '
 if ($argsText -like '*releases?per_page=100*') { return }
 if ($argsText -like 'api repos/example/repo/commits/main*') { return 'abc' }
 if ($argsText -like 'api repos/example/repo/actions/runs/123/artifacts*') { return '{"artifacts":[{"name":"windows-test-reports-123-1","expired":false}]}' }
 if ($argsText -like 'api repos/example/repo/actions/runs/123*') { return '{"id":123,"run_attempt":1,"head_sha":"abc","head_branch":"main","event":"push"}' }
 if ($argsText -like 'run download*') {
  $script:downloadCalls++
  if ($script:downloadCalls -eq 1) { $global:LASTEXITCODE = 1; [Console]::Error.WriteLine('HTTP 503'); return }
  $index = [Array]::IndexOf($args, '--dir')
  [IO.File]::WriteAllText((Join-Path $args[$index + 1] 'summary.json'), '{"Commit":"abc"}')
  return
 }
 throw "Unexpected gh command: $argsText"
}
try {
 try { & (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository 'example/repo' -OutputDirectory (Join-Path $parent 'out') -MainRunId 123 | Out-Null }
 catch { throw "Transient artifact download was not retried: $_" }
 if ($script:downloadCalls -ne 2) { throw "Expected two download calls, got $script:downloadCalls" }
} finally {
 Remove-Item function:global:gh -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $parent -Recurse -Force
}
