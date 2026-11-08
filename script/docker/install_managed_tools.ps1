#Requires -Version 5.1
$ErrorActionPreference='Stop'
function Get-ContainerManagedToolArtifacts {
 # Microsoft release metadata: PowerShell/PowerShell v7.6.9, dotnet release-metadata/10.0/releases.json.
 @(
  [pscustomobject]@{Name='PowerShell-7.6.9-win-x64.zip';Version='7.6.9';Uri='https://github.com/PowerShell/PowerShell/releases/download/v7.6.9/PowerShell-7.6.9-win-x64.zip';Algorithm='SHA256';Hash='ce7484804c0f0ad4dda10c958e71acdaf7eebfb22505c1b480f89e0e9f1da94d';Kind='Zip';Destination='C:/pwsh'},
  [pscustomobject]@{Name='dotnet-sdk-10.0.300-win-x64.zip';Version='10.0.300';Uri='https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.300/dotnet-sdk-10.0.300-win-x64.zip';Algorithm='SHA512';Hash='32446eddffc5a485f58f9d79cdab3a1a9adab4adc2ef0e4c787cfbb2465020d50beaadc54d40f0850e2e0089edd09864d12d6c19c526319819d57a4c00d38518';Kind='Zip';Destination='C:/dotnet'},
  [pscustomobject]@{Name='dotnet-coverage.17.14.1.nupkg';Version='17.14.1';Uri='https://api.nuget.org/v3-flatcontainer/dotnet-coverage/17.14.1/dotnet-coverage.17.14.1.nupkg';Algorithm='SHA512';Hash='860cda1be73b2ed2aea7a1d98b1bd7b67de5e0f6bc54adb76ccf6f2c7bde0f722ad979732eeeefa8c670b558d076ca1ff37c31e4ecd8d2da43877f9845d3958c';Kind='File';Destination='C:/tools/cache/dotnet-coverage.17.14.1.nupkg'}
 )
}
function Install-ContainerToolArtifact {
 param([Parameter(Mandatory=$true)]$Artifact,[Parameter(Mandatory=$true)][string]$Destination,[Parameter(Mandatory=$true)][string]$ArchiveDirectory)
 [void][IO.Directory]::CreateDirectory($ArchiveDirectory)
 $archive=Join-Path $ArchiveDirectory $Artifact.Name
 Invoke-WebRequest -UseBasicParsing -Uri $Artifact.Uri -OutFile $archive -ErrorAction Stop
 if((Get-FileHash -LiteralPath $archive -Algorithm $Artifact.Algorithm).Hash -ine $Artifact.Hash){throw ('Container tool digest mismatch: '+$Artifact.Name)}
 if($Artifact.Kind -eq 'Zip'){Expand-Archive -LiteralPath $archive -DestinationPath $Destination}
 elseif($Artifact.Kind -eq 'File'){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination));Copy-Item -LiteralPath $archive -Destination $Destination}
 else{throw ('Unsupported container artifact kind: '+$Artifact.Kind)}
 Remove-Item -LiteralPath $archive
}
if($MyInvocation.InvocationName -ne '.'){
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $archives=Join-Path $env:TEMP ('container_managed_'+[guid]::NewGuid().ToString('N'))
 foreach($artifact in @(Get-ContainerManagedToolArtifacts)){Install-ContainerToolArtifact -Artifact $artifact -Destination $artifact.Destination -ArchiveDirectory $archives}
}