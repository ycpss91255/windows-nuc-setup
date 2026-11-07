#Requires -Version 5.1
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $package 'modules\ssh\custom_hosts_sync\sync-custom-hosts.ps1')
$count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$root=Join-Path ([IO.Path]::GetTempPath()) ('NUC-Hosts-Test-'+[guid]::NewGuid().ToString('N'))
$profile=Join-Path $root 'profile'
$hostsSource=Join-Path $profile '.config\hosts\hosts.d'
$sshSource=Join-Path $profile '.ssh\config.d'
New-Item -ItemType Directory -Path $hostsSource,$sshSource -Force|Out-Null
$encoding=New-Object Text.UTF8Encoding($false)
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,$encoding)}
$settings=Join-Path $profile '.config\hosts\sites.json'
Copy-Item (Join-Path $package 'modules\ssh\custom_hosts_sync\sites.json') $settings
$config=[IO.File]::ReadAllText($settings)|ConvertFrom-Json
Assert (@($config.Sites).Count -eq 0) 'public defaults contain no personal network rules'
Assert-NetworkSiteConfiguration $config
$snapshot=[pscustomobject]@{Adapters=@();Warnings=@()}
Write-Fixture (Join-Path $hostsSource 'global.hosts') "192.0.2.1 global-server`r`n"
Write-Fixture (Join-Path $sshSource 'global.conf') "Host example`r`n    HostName 192.0.2.1`r`n"
Write-Fixture (Join-Path $profile '.ssh\config') "Include active-sites.conf`r`n"
$target=Join-Path $root 'hosts'
Write-Fixture $target "127.0.0.1 localhost`r`n"
$plan=Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Mode Hosts -Snapshot $snapshot
Assert ($plan.Text -match 'global-server' -and $plan.Text.StartsWith('127.0.0.1 localhost')) 'global hosts retained without active sites and existing hosts preserved'
$ssh=Get-CustomHostsPlan -ProfilePath $profile -Mode SSH -Snapshot $snapshot
Assert ($ssh.Text -match 'config.d/global.conf') 'global SSH retained without active sites'
$config.Sites=@([pscustomobject]@{Id='site-a';Enabled=$true;Rules=@([pscustomobject]@{IPv4Cidr=@('192.0.2.0/24')})})
Write-Fixture $settings ($config|ConvertTo-Json -Depth 8)
Write-Fixture (Join-Path $hostsSource 'site-a.hosts') "192.0.2.2 site-server`r`n192.0.2.3 ip.global.example`r`n"
Write-Fixture (Join-Path $sshSource 'site-a.conf') "Host site-server`r`n    HostName 192.0.2.2`r`n"
$inactive=Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Mode Hosts -Snapshot $snapshot
Assert ($inactive.Text -notmatch 'site-server' -and $inactive.Text -match 'ip.global.example') 'inactive site excluded while generic global alias remains'
$snapshot.Adapters=@([pscustomobject]@{Name='Example';Description='Example adapter';SSIDs=@();NetworkProfiles=@();IPv4=@([pscustomobject]@{Address='192.0.2.10';PrefixLength=24})})
$active=Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Mode Hosts -Snapshot $snapshot
Assert ($active.Text -match 'site-server') 'matching documentation network activates generic site'
$activeSsh=Get-CustomHostsPlan -ProfilePath $profile -Mode SSH -Snapshot $snapshot
Assert ($activeSsh.Text -match 'config.d/site-a.conf') 'matching generic site activates SSH include'
# Only fixtures are changed; neither branch reads the other output data.
Move-Item -LiteralPath (Join-Path $profile '.ssh') -Destination (Join-Path $profile 'ssh-not-used')
$null=Get-CustomHostsPlan -ProfilePath $profile -TargetHostsPath $target -Mode Hosts -Snapshot $snapshot
Assert $true 'Hosts-only does not require SSH configuration'
Move-Item -LiteralPath (Join-Path $profile 'ssh-not-used') -Destination (Join-Path $profile '.ssh')
Move-Item -LiteralPath $hostsSource -Destination (Join-Path $profile '.config\hosts\hosts-not-used')
$null=Get-CustomHostsPlan -ProfilePath $profile -Mode SSH -Snapshot $snapshot
Assert $true 'SSH-only does not require hosts sources or system hosts'
Assert ([IO.File]::ReadAllText($target) -eq "127.0.0.1 localhost`r`n") 'plan tests never write target hosts'
Write-Host ('ALL PASS: '+$count+' generic hosts/SSH assertions; only temporary fixture data used.')
