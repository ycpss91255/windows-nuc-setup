#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
. (Join-Path $root 'core/paths.ps1')
$entry=Resolve-NucPath 'Apply-MdnsSettings.ps1'
Assert ($entry -eq (Join-Path $root 'modules/ssh/apply_mdns_settings.ps1') -and (Get-Command $entry).Parameters.ContainsKey('VerifyOnly')) 'standalone dispatcher resolves original native publisher VerifyOnly entry'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/run_module.ps1'),[ref]$tokens,[ref]$errors)
$allowed=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$allowed'},$true)
$values=@($allowed.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object Value)
Assert ('Apply-MdnsSettings' -in $values) 'standalone native publisher uses existing SID and UAC guarded dispatcher'
$ssh=[IO.File]::ReadAllText((Join-Path $root 'modules/ssh/apply_ssh_settings.ps1'))
$lan=$ssh.IndexOf("& (Join-Path `$PSScriptRoot 'apply_lan_ping_settings.ps1')");$publisher=$ssh.IndexOf("& (Join-Path `$PSScriptRoot 'apply_mdns_settings.ps1')");$service=$ssh.IndexOf("if((Get-Service sshd).Status -ne 'Running')")
Assert ($service -ge 0 -and $lan -gt $service -and $publisher -gt $lan -and $publisher -lt $ssh.IndexOf('Get-SetupSshConnectionInfo')) 'stage4 starts publisher after SSH running and LAN Ping, before connection instructions'
$config=[IO.File]::ReadAllText((Join-Path $root 'core/configuration_library.ps1'))
Assert (([regex]::Matches($config,"File='([^']+\.ps1)'" )).Count -eq 18) 'publisher belongs to existing SSH stage, without adding a twentieth stage'
$fixture=[IO.Path]::GetFullPath((Join-Path $env:TEMP ('mdns_wiring_'+[guid]::NewGuid().ToString('N'))));[void][IO.Directory]::CreateDirectory($fixture)
foreach($dir in @('core','modules','drivers')){foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root $dir) -File -Recurse|Where-Object {$_.Extension -notin @('.exe','.zip','.log')})){$relative=$file.FullName.Substring($root.Length).TrimStart('\');$target=Join-Path $fixture $relative;[void][IO.Directory]::CreateDirectory((Split-Path $target -Parent));[IO.File]::Copy($file.FullName,$target)}}
foreach($file in @('init.cmd','windows.cmd','readme.md')){[IO.File]::Copy((Join-Path $root $file),(Join-Path $fixture $file))}
[IO.File]::WriteAllText((Join-Path $fixture 'modules/accounts/Autologon64.exe'),'existence fixture; never executed')
& (Join-Path $fixture 'core/test_setup_prerequisites.ps1') -PackageOnly -HardwareProfile Generic
foreach($relative in @('modules/ssh/apply_mdns_settings.ps1','modules/ssh/apply_mdns_settings.cmd','modules/ssh/mdns_publisher_library.ps1','modules/ssh/mdns_worker.ps1','modules/ssh/native/mdns_publisher.cs')){
 $path=Join-Path $fixture $relative;$held=$path+'.held';if(-not [IO.Path]::GetFullPath($path).StartsWith($fixture+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside owned fixture'}
 [IO.File]::Move($path,$held);$errorText=''
 try{& (Join-Path $fixture 'core/test_setup_prerequisites.ps1') -PackageOnly -HardwareProfile Generic}catch{$errorText=$_.Exception.Message}finally{[IO.File]::Move($held,$path)}
 Assert ($errorText.Contains([IO.Path]::GetFileName($relative))) ('USB PackageOnly rejects missing true publisher dependency: '+$relative)
}