#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$installer=Join-Path $root 'script/docker/install_managed_tools.ps1'
Assert (Test-Path -LiteralPath $installer -PathType Leaf) 'offline Windows container must prepare managed compiler and pwsh at build time'
. $installer
$pins=@(Get-ContainerManagedToolArtifacts)
Assert ($pins.Count -eq 3) 'toolchain includes portable PowerShell SDK and offline native coverage package'
Assert ($pins[0].Version -eq '7.6.9' -and $pins[0].Hash -eq 'ce7484804c0f0ad4dda10c958e71acdaf7eebfb22505c1b480f89e0e9f1da94d') 'PowerShell archive is pinned to official release digest'
Assert ($pins[1].Version -eq '10.0.300' -and $pins[1].Algorithm -eq 'SHA512' -and $pins[1].Hash -eq '32446eddffc5a485f58f9d79cdab3a1a9adab4adc2ef0e4c787cfbb2465020d50beaadc54d40f0850e2e0089edd09864d12d6c19c526319819d57a4c00d38518') 'SDK archive matches official release metadata'
Assert ($pins[2].Version -eq '17.14.1' -and $pins[2].Algorithm -eq 'SHA512' -and $pins[2].Kind -eq 'File') 'native collector package is preloaded rather than fetched inside offline tests'
$temp=Join-Path $env:TEMP ('container_tools_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$payload=Join-Path $temp 'fixture.zip';[IO.File]::WriteAllText($payload,'safe fake download')
$pin=[pscustomobject]@{Name='fixture.zip';Uri='https://example.invalid/fixture.zip';Algorithm='SHA256';Hash=(Get-FileHash $payload).Hash;Kind='Zip'}
function Invoke-WebRequest {param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction) Copy-Item -LiteralPath $payload -Destination $OutFile}
$script:expanded=0
function Expand-ContainerToolArchive {param($LiteralPath,$DestinationPath) $script:expanded++;[void][IO.Directory]::CreateDirectory($DestinationPath);[IO.File]::WriteAllText((Join-Path $DestinationPath 'ready.txt'),'expanded')}
$destination=Join-Path $temp 'tool';$archives=Join-Path $temp 'downloads'
Install-ContainerToolArtifact -Artifact $pin -Destination $destination -ArchiveDirectory $archives
Assert ($script:expanded -eq 1 -and (Test-Path (Join-Path $destination 'ready.txt'))) 'verified archive reaches extraction only after a matching real digest'
$pin.Hash='0'*64;$failed=$false
try{Install-ContainerToolArtifact -Artifact $pin -Destination (Join-Path $temp 'bad') -ArchiveDirectory $archives}catch{$failed=$_.Exception.Message -match 'digest'}
Assert ($failed -and $script:expanded -eq 1 -and -not(Test-Path (Join-Path $temp 'bad'))) 'corrupt download fails before extraction and cannot create tool destination'
$pin.Hash=(Get-FileHash $payload).Hash;$pin.Kind='File';$target=Join-Path $temp 'cache/native.nupkg'
Install-ContainerToolArtifact -Artifact $pin -Destination $target -ArchiveDirectory $archives
Assert ((Get-FileHash $target).Hash -eq $pin.Hash -and $script:expanded -eq 1) 'offline package bytes are preserved without archive mutation'
Remove-Item Function:/Invoke-WebRequest,Function:/Expand-ContainerToolArchive
. (Join-Path $root 'script/test/ci_tasks.ps1')
$script:lookups=@();$script:invocations=@()
function Get-Command {param($Name,$CommandType,$ErrorAction) $script:lookups+=@($Name);[pscustomobject]@{Name=$Name}}
function Invoke-CINative {param($File,$Arguments) $script:invocations+=@(($File+'|'+($Arguments -join '|')));if($File -eq 'pwsh.exe'){'7.6.9'}elseif($File -eq 'dotnet.exe'){'10.0.300'}}
Assert-CIRequiredTools -Managed
Assert (($script:lookups -contains 'pwsh.exe') -and ($script:lookups -contains 'dotnet.exe') -and ($script:invocations -contains 'dotnet.exe|--version')) 'managed prerequisites are checked before isolated container suites'
function Invoke-CINative {param($File,$Arguments) if($File -eq 'pwsh.exe'){'7.3.0'}elseif($File -eq 'dotnet.exe'){'10.0.300'}}
$failed=$false;try{Assert-CIRequiredTools -Managed}catch{$failed=$true}
Assert $failed 'wrong PowerShell runtime cannot silently produce metadata evidence'
function Invoke-CINative {param($File,$Arguments) if($File -eq 'pwsh.exe'){'7.6.9'}elseif($File -eq 'dotnet.exe'){'9.0.100'}}
$failed=$false;try{Assert-CIRequiredTools -Managed}catch{$failed=$true}
Assert $failed 'wrong managed SDK cannot silently substitute compiler'
Remove-Item Function:/Get-Command,Function:/Invoke-CINative
$docker=[IO.File]::ReadAllText((Join-Path $root 'dockerfile/windows_tests.dockerfile'))
$ignore=[IO.File]::ReadAllText((Join-Path $root '.dockerignore'))
$runner=[IO.File]::ReadAllText((Join-Path $root 'script/docker/container_test.ps1'))
Assert ($docker.Contains('COPY script/docker/install_managed_tools.ps1 C:/tools/install_managed_tools.ps1') -and $docker.Contains('RUN C:/tools/install_managed_tools.ps1') -and $ignore.Contains('!script/docker/install_managed_tools.ps1')) 'Docker build must actually receive and execute the pinned installer'
Assert ($docker.Contains('C:\pwsh;C:\dotnet;') -and $docker.Contains('WINDOWS_SETUP_MANAGED_PACKAGE_PATH="C:/tools/cache/dotnet-coverage.17.14.1.nupkg"')) 'offline runtime resolves portable tools and verified local native package'
Assert ($docker.Contains('Assert-CIRequiredTools -Managed') -and $runner.Contains('Assert-CIRequiredTools -Managed')) 'image build and test startup both reject missing managed prerequisites'
