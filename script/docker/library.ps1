#Requires -Version 5.1
function Get-ContainerContext {
 param([string]$Root,[string]$ReportDirectory,[ValidateSet('process','hyperv')][string]$Isolation='process')
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 if(-not(Test-Path -LiteralPath (Join-Path $rootPath '.git') -PathType Container)){throw 'Use a complete Git checkout; linked worktrees and source ZIPs are not supported by this container entry.'}
 if(-not $ReportDirectory){$ReportDirectory=Join-Path ([IO.Path]::GetTempPath()) ('windows_container_'+[guid]::NewGuid().ToString('N'))}
 $reportPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory).TrimEnd('\','/')
 if($reportPath -ieq $rootPath -or $reportPath.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase) -or $rootPath.StartsWith($reportPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Container reports must be outside, and must not contain, the checkout.'}
 $inputs=@('dockerfile/windows_tests.dockerfile','script/docker/install_min_git.ps1','script/docker/install_go.ps1','script/docker/container_test.ps1','.dockerignore','compose.yaml')
 $fingerprint=(@($inputs|ForEach-Object {$_+':'+(Get-FileHash -LiteralPath (Join-Path $rootPath $_) -Algorithm SHA256).Hash}) -join "`n")
 $sha=[Security.Cryptography.SHA256]::Create()
 try{
  $imageHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint)))).Replace('-','').ToLowerInvariant()
  $scope=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rootPath.ToLowerInvariant())))).Replace('-','').ToLowerInvariant().Substring(0,12)
 }finally{$sha.Dispose()}
 [pscustomobject]@{Root=$rootPath;Reports=$reportPath;Isolation=$Isolation;Image=('windows_setup_tests:'+ $imageHash);Project=('windows_setup_'+$scope)}
}
function Invoke-ContainerDocker {
 param([string[]]$Arguments)
 $preference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue'; & docker.exe @Arguments; $dockerExit=$LASTEXITCODE}finally{$ErrorActionPreference=$preference}
 if($dockerExit -ne 0){$failure=[Exception]::new(('Docker failed with exit code '+$dockerExit));$failure.Data['ExitCode']=$dockerExit;throw $failure}
}

function Assert-ContainerCompose {
 param($Configuration,[string]$Isolation,[string]$Image)
 $service=$Configuration.services.tools
 if(-not $service -or $service.isolation -cne $Isolation -or $service.build.isolation -cne $Isolation){throw 'Compose must apply the selected isolation to both build and run.'}
 if($service.image -cne $Image){throw 'Compose image does not match the content-addressed toolchain.'}
}