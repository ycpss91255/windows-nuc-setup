#Requires -Version 5.1
function Get-ContainerContext {
 param([string]$Root,[string]$ReportDirectory,[ValidateSet('process','hyperv')][string]$Isolation='process')
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 if(-not(Test-Path -LiteralPath (Join-Path $rootPath '.git') -PathType Container)){throw 'Use a complete Git checkout; linked worktrees and source ZIPs are not supported by this container entry.'}
 if(-not $ReportDirectory){$ReportDirectory=Join-Path ([IO.Path]::GetTempPath()) ('windows_container_'+[guid]::NewGuid().ToString('N'))}
 $reportPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory).TrimEnd('\','/')
 if($reportPath -ieq $rootPath -or $reportPath.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase) -or $rootPath.StartsWith($reportPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Container reports must be outside, and must not contain, the checkout.'}
 $inputs=@('dockerfile/windows_tests.dockerfile','script/docker/download_library.ps1','script/docker/install_min_git.ps1','script/docker/install_go.ps1','script/docker/install_managed_tools.ps1','script/docker/container_test.ps1','script/test/ci_tasks.ps1','.dockerignore','compose.yaml')
 $fingerprint=(@($inputs|ForEach-Object {$_+':'+(Get-FileHash -LiteralPath (Join-Path $rootPath $_) -Algorithm SHA256).Hash}) -join "`n")
 $sha=[Security.Cryptography.SHA256]::Create()
 try{
  $imageHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint)))).Replace('-','').ToLowerInvariant()
  $rootHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rootPath.ToLowerInvariant())))).Replace('-','').ToLowerInvariant()
  $scope=$rootHash.Substring(0,12)
 }finally{$sha.Dispose()}
 [pscustomobject]@{Root=$rootPath;Reports=$reportPath;Isolation=$Isolation;Image=('windows_setup_tests:'+ $imageHash);Project=('windows_setup_'+$scope);InputsSHA256=$imageHash;RootSHA256=$rootHash}
}
function Get-ContainerSourceCommit {
 param([Parameter(Mandatory=$true)][string]$Root)
 $head=& git.exe -C $Root rev-parse HEAD
 if($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[a-f0-9]{40}$'){throw 'Container source commit cannot be verified.'}
 return [string]$head
}
function Get-ContainerBuiltImageId {
 param([Parameter(Mandatory=$true)]$Context)
 $image=((Invoke-ContainerDocker -Arguments @('image','inspect',$Context.Image,'--format','{{json .}}')) -join "`n")|ConvertFrom-Json
 if($image.Id -isnot [string] -or $image.Id -cnotmatch '^sha256:[a-f0-9]{64}$' -or @($image.RepoTags) -cnotcontains $Context.Image){throw 'Exact content-addressed container image is missing or invalid.'}
 return $image.Id
}
function Get-ContainerReceiptPath {
 param($Context,[string]$Path)
 if([string]::IsNullOrWhiteSpace($Path)){throw 'A successful build receipt is required.'}
 $full=[IO.Path]::GetFullPath($Path)
 if($full -ieq $Context.Root -or $full.StartsWith($Context.Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Build receipt must stay outside the read-only source checkout.'}
 return $full
}
function Save-ContainerBuildReceipt {
 param([Parameter(Mandatory=$true)]$Context,[Parameter(Mandatory=$true)][string]$Path)
 $full=Get-ContainerReceiptPath -Context $Context -Path $Path
 $receipt=[ordered]@{SchemaVersion=1;SourceCommit=(Get-ContainerSourceCommit -Root $Context.Root);InputsSHA256=$Context.InputsSHA256;RootSHA256=$Context.RootSHA256;Image=$Context.Image;ImageId=(Get-ContainerBuiltImageId -Context $Context);Isolation=$Context.Isolation}
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Compress))
 $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
}
function Assert-ContainerBuildReceipt {
 param([Parameter(Mandatory=$true)]$Context,[Parameter(Mandatory=$true)][string]$Path)
 $full=Get-ContainerReceiptPath -Context $Context -Path $Path
 $receipt=[IO.File]::ReadAllText($full)|ConvertFrom-Json
 $keys=@('SchemaVersion','SourceCommit','InputsSHA256','RootSHA256','Image','ImageId','Isolation')
 if(@($receipt.PSObject.Properties).Count -ne $keys.Count -or @($keys|Where-Object {$receipt.PSObject.Properties.Name -cnotcontains $_}).Count -or ($receipt.SchemaVersion -isnot [int] -and $receipt.SchemaVersion -isnot [long]) -or $receipt.SchemaVersion -ne 1){throw 'Container build receipt schema is invalid.'}
 if($receipt.SourceCommit -cne (Get-ContainerSourceCommit -Root $Context.Root) -or $receipt.InputsSHA256 -cne $Context.InputsSHA256 -or $receipt.RootSHA256 -cne $Context.RootSHA256 -or $receipt.Image -cne $Context.Image -or $receipt.Isolation -cne $Context.Isolation -or $receipt.ImageId -cne (Get-ContainerBuiltImageId -Context $Context)){throw 'Container build receipt does not match current source, tool inputs, isolation and exact image.'}
 return $receipt.ImageId
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
