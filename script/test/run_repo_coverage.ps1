#Requires -Version 5.1
[CmdletBinding()]
param([string]$SourceRoot,[string]$PublicDirectory,[string]$GoCoverageDirectory,[string]$ManagedEvidencePath,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci_tasks.ps1')
function Invoke-RepoCoveragePipeline {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$PublicDirectory,[Parameter(Mandatory=$true)][string]$GoCoverageDirectory,[Parameter(Mandatory=$true)][string]$ManagedEvidencePath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
 $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/');$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
 if($output -ieq $source -or $output.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw '整體覆蓋率必須使用來源外部全新目錄。'}
 $metadata=Get-Content -LiteralPath (Join-Path $PublicDirectory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
 [void][IO.Directory]::CreateDirectory($output)
 $tool=Join-Path $output 'repo_coverage_tool.exe';$probeSource=Join-Path $output 'cmd_probe.go';$probe=Join-Path $output 'powershell.exe'
 $manifest=Join-Path $output 'powershell_manifest.json';$ps=Join-Path $output 'powershell';$cmd=Join-Path $output 'cmd.json';$coverage=Join-Path $output 'coverage'
 Copy-Item -LiteralPath (Join-Path $source 'test/fixtures/cmd_probe/main.go.txt') -Destination $probeSource
 Push-Location $source
 try{
  Invoke-CINative -File go.exe -Arguments @('build','-mod=vendor','-o',$tool,'./script/test/repo_coverage_tool')
  Invoke-CINative -File go.exe -Arguments @('build','-mod=vendor','-o',$probe,$probeSource)
  Invoke-CINative -File powershell.exe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'test/powershell/coverage/create_baseline_manifest.ps1'),'-SourceRoot',$source,'-OutputPath',$manifest)
  Invoke-CINative -File powershell.exe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'script/test/powershell_coverage.ps1'),'-ManifestPath',$manifest,'-OutputDirectory',$ps,'-ThrottleLimit','2')
  Invoke-CINative -File $tool -Arguments @('cmd-measure','--source-root',$source,'--probe-executable',$probe,'--output',$cmd)
  $identity=@('--expected-sha',[string]$metadata.Commit)
  if($metadata.RunUrl){$identity+=@('--expected-run-url',[string]$metadata.RunUrl)}
  Invoke-CINative -File $tool -Arguments (@('collect','--source-root',$source,'--output-dir',$coverage,'--go-evidence',(Join-Path $GoCoverageDirectory 'go_coverage.json'),'--go-profile',(Join-Path $GoCoverageDirectory 'go_coverage.out'),'--powershell-evidence',(Join-Path $ps 'evidence.json'),'--cmd-evidence',$cmd,'--managed-evidence',$ManagedEvidencePath)+$identity)
  Invoke-CINative -File $tool -Arguments (@('verify','--artifact-dir',$coverage,'--source-root',$source,'--require-complete','--minimum-percent','80')+$identity)
  Invoke-CINative -File powershell.exe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'script/test/attach_repo_coverage.ps1'),'-PublicDirectory',$PublicDirectory,'-CoverageDirectory',$coverage,'-CoverageToolPath',$tool,'-SourceRoot',$source)
 }finally{Pop-Location}
}
if($MyInvocation.InvocationName -ne '.') {Invoke-RepoCoveragePipeline @PSBoundParameters}
