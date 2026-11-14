#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$parent=Join-Path ([IO.Path]::GetTempPath()) ('portal_retry_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $parent|Out-Null
$oldTool=$env:WINDOWS_SETUP_ARTIFACT_DOWNLOAD_TOOL
$env:WINDOWS_SETUP_ARTIFACT_DOWNLOAD_TOOL='Invoke-ArtifactFixture'
$global:portalRetryDownloadCalls=0
function global:gh {
 $global:LASTEXITCODE=0
 $vector=$args -join ' '
 if($vector -like '*releases?per_page=100*'){return}
 if($vector -like 'api repos/example/repo/commits/main*'){return 'abc'}
 if($vector -like 'api --paginate repos/example/repo/actions/runs/123/artifacts*'){
  $row='{"id":456,"name":"windows-test-reports-123-1","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expired":false}'
  if($global:portalRetryDuplicate){return @($row,$row)}
  return $row
 }
 if($vector -like 'api repos/example/repo/actions/runs/123*'){return '{"id":123,"run_attempt":1,"head_sha":"abc","head_branch":"main","event":"push"}'}
 throw "Unexpected gh command: $vector"
}
function global:Invoke-ArtifactFixture {
 $global:portalRetryDownloadCalls++
 $expected=@('--repo','example/repo','--run','123','--attempt','1','--id','456','--digest',('sha256:'+('a'*64)),'--dest',(Join-Path $parent 'out/main'))
 if(($args -join '|') -cne ($expected -join '|')){throw 'Artifact identity was not passed intact'}
 New-Item -ItemType Directory -Path $args[-1]|Out-Null
 [IO.File]::WriteAllText((Join-Path $args[-1] 'summary.json'),'{"Commit":"abc"}')
 $global:LASTEXITCODE=0
}
try {
 & (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository 'example/repo' -OutputDirectory (Join-Path $parent 'out') -MainRunId 123|Out-Null
 if($global:portalRetryDownloadCalls -ne 1){throw 'Expected one identity-bound helper invocation'}
 $global:portalRetryDuplicate=$true
 $rejected=$false
 try {& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository 'example/repo' -OutputDirectory (Join-Path $parent 'duplicate') -MainRunId 123|Out-Null} catch {$rejected=$true}
 if(-not $rejected -or $global:portalRetryDownloadCalls -ne 1){throw 'Duplicate artifacts must fail before download'}
} finally {
 $env:WINDOWS_SETUP_ARTIFACT_DOWNLOAD_TOOL=$oldTool
 Remove-Variable portalRetryDuplicate,portalRetryDownloadCalls -Scope Global -ErrorAction SilentlyContinue
 Remove-Item function:global:gh,function:global:Invoke-ArtifactFixture -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $parent -Recurse -Force
}
