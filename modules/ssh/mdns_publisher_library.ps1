#Requires -Version 5.1
# Definitions only. Native registration runs exclusively in the protected startup worker.
. (Join-Path $PSScriptRoot '../updates/update_stage_library.ps1')
function Get-SetupMdnsPublicationPlan {
 param([string]$ComputerName=([Environment]::MachineName),[object[]]$Addresses=@())
 if($ComputerName -notmatch '^[\p{L}\p{Nd}_][\p{L}\p{Nd}_-]*$' -or [Text.Encoding]::UTF8.GetByteCount($ComputerName) -gt 63){throw '系統名稱不是有效的單一mDNS標籤。'}
 $groups=@{}
 foreach($row in $Addresses){
  $index=[uint32]0;if(-not [uint32]::TryParse([string]$row.InterfaceIndex,[ref]$index) -or $index -eq 0){throw '公告介面索引未知，不能改向所有介面。'}
  $ip=$null;if(-not [Net.IPAddress]::TryParse([string]$row.IPAddress,[ref]$ip)){throw '作用中IP無法解析。'}
  $six=$ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
  if([Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any) -or $ip.IsIPv6Multicast -or (-not $six -and $ip.GetAddressBytes()[0] -ge 224)){continue}
  if($six -and $ip.ScopeId -ne 0 -and $ip.ScopeId -ne $index){throw 'IPv6 scope不屬於公告介面。'}
  if(-not $groups.ContainsKey($index)){$groups[$index]=@{IPv4=@();IPv6=@()}}
  $family=if($six){'IPv6'}else{'IPv4'};$canonical=(New-Object Net.IPAddress(,$ip.GetAddressBytes())).ToString()
  $groups[$index][$family]+=[pscustomobject]@{Address=$canonical;LinkLocal=($ip.IsIPv6LinkLocal -or $canonical -like '169.254.*')}
 }
 foreach($index in @($groups.Keys|Sort-Object)){
  $four=@($groups[$index].IPv4|Sort-Object LinkLocal,Address|Select-Object -First 1);$six=@($groups[$index].IPv6|Sort-Object LinkLocal,Address|Select-Object -First 1)
  [pscustomobject][ordered]@{HostName=($ComputerName+'.local');ServiceName=($ComputerName+'._ssh._tcp.local');InterfaceIndex=[uint32]$index;IPv4=$(if($four.Count){$four[0].Address}else{$null});IPv6=$(if($six.Count){$six[0].Address}else{$null});Port=22}
 }
}
function Get-SetupMdnsFingerprint {
 param([object[]]$Plans,[int]$DnsClientProcessId)
 $text=[ordered]@{DnsClientProcessId=$DnsClientProcessId;Plans=@($Plans)}|ConvertTo-Json -Depth 6 -Compress
 $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-SetupMdnsPublisherFacts {
 $allowed=$true;$group=$null;$local=$null
 foreach($row in @(@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient';Group=$true},@{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Group=$false})){
  if(Test-Path -LiteralPath $row.Path -ErrorAction Stop){$key=Get-Item -LiteralPath $row.Path -ErrorAction Stop;if('EnableMDNS' -in $key.GetValueNames()){$value=$key.GetValue('EnableMDNS');if($key.GetValueKind('EnableMDNS') -ne 'DWord' -or $value -notin @(0,1)){throw 'EnableMDNS原則型別或值未知，未覆寫。'};if($row.Group){$group=$value}else{$local=$value}}}
 }
 if($group -ne 1 -and $null -ne $local -and $local -eq 0){$allowed=$false}
 $dns=Get-CimInstance Win32_Service -Filter "Name='Dnscache'" -ErrorAction Stop;$ssh=Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction Stop
 if(-not $dns -or -not $ssh){throw '無法讀取DNS Client或SSH服務。'}
 $interfaces=@(Get-NetIPInterface -ConnectionState Connected -ErrorAction Stop);$addresses=@()
 foreach($ip in @(Get-NetIPAddress -ErrorAction Stop|Where-Object AddressState -eq 'Preferred')){
  if(@($interfaces|Where-Object {$_.InterfaceIndex -eq $ip.InterfaceIndex -and [string]$_.AddressFamily -eq [string]$ip.AddressFamily}).Count){$addresses+=[pscustomobject]@{InterfaceIndex=$ip.InterfaceIndex;IPAddress=[string]$ip.IPAddress}}
 }
 [pscustomobject]@{ComputerName=[Environment]::MachineName;Addresses=$addresses;PolicyAllowed=$allowed;DnsClientRunning=($dns.State -eq 'Running');SshdRunning=($ssh.State -eq 'Running');DnsClientProcessId=[int]$dns.ProcessId}
}
function New-SetupMdnsNativeRegistration {
 param([string]$CodeRoot,$Row)
 if(-not ('WindowsSetup.MdnsPublisher' -as [type])){Add-Type -Path (Join-Path $CodeRoot 'modules/ssh/native/mdns_publisher.cs') -ErrorAction Stop}
 $ad=New-Object WindowsSetup.MdnsPublisher+Advertisement
 foreach($name in @('HostName','ServiceName','InterfaceIndex','IPv4','IPv6','Port')){$ad.$name=$Row.$name}
 return [WindowsSetup.MdnsPublisher]::Begin($ad,$null,15000)
}
function Close-SetupMdnsRegistrations {
 param($State)
 $errors=@();foreach($lease in $State.Leases){try{$lease.Dispose()}catch{$errors+=$_.Exception.Message}}
 if($errors.Count){throw ('原生mDNS撤銷未完成：'+($errors -join '; '))}
 $State.Leases=@();$State.Fingerprint='';$State.Ready=$false
}
function Invoke-SetupMdnsPublisherCycle {
 param($State,$Context,$Facts,[string]$CodeRoot,[string]$StatusPath)
 $ErrorActionPreference='Stop'
 try{
  $plans=@(Get-SetupMdnsPublicationPlan -ComputerName $Facts.ComputerName -Addresses $Facts.Addresses)
  $State.Plans=$plans;$State.Error=''
  $waiting=if(-not $Facts.PolicyAllowed){'SuppressedByPolicy'}elseif(-not $Facts.DnsClientRunning -or -not $Facts.SshdRunning){'WaitingForServices'}elseif(-not $plans.Count){'WaitingForNetwork'}else{''}
  if($waiting){Close-SetupMdnsRegistrations $State;$State.Status=$waiting;Write-SetupMdnsPublisherState -Path $StatusPath -Context $Context -Facts $Facts -State $State;return}
  $fingerprint=Get-SetupMdnsFingerprint -Plans $plans -DnsClientProcessId $Facts.DnsClientProcessId
  if($State.Fingerprint -cne $fingerprint -or -not $State.Ready -or @($State.Leases|Where-Object {-not $_.Registered}).Count){
   Close-SetupMdnsRegistrations $State;$State.Status='Registering';Write-SetupMdnsPublisherState -Path $StatusPath -Context $Context -Facts $Facts -State $State
   foreach($row in $plans){$lease=New-SetupMdnsNativeRegistration -CodeRoot $CodeRoot -Row $row;$State.Leases+=@($lease);if($lease.Registered -isnot [bool] -or -not $lease.Registered){throw '原生mDNS未確認註冊。'}}
   $State.Fingerprint=$fingerprint;$State.Ready=$true
  }
  $State.Status='Registered';Write-SetupMdnsPublisherState -Path $StatusPath -Context $Context -Facts $Facts -State $State
 }catch{
  $State.Ready=$false;$State.Status='Failed';$State.Error=$_.Exception.Message
  try{Close-SetupMdnsRegistrations $State}catch{$State.Error+='; '+$_.Exception.Message}
  Write-SetupMdnsPublisherState -Path $StatusPath -Context $Context -Facts $Facts -State $State
  throw
 }
}function Get-SetupMdnsSourceNames {return @('modules/ssh/mdns_publisher_library.ps1','modules/ssh/mdns_worker.ps1','modules/ssh/native/mdns_publisher.cs','modules/updates/update_stage_library.ps1')}
function Get-SetupMdnsMachineGuid {
 $value=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction Stop).MachineGuid
 $guid=[guid]::Empty;if(-not [guid]::TryParse($value,[ref]$guid)){throw '無法確認本機MachineGuid。'};return $guid.ToString('D')
}
function Get-SetupMdnsPaths {
 param([string]$RunId)
 if($RunId){$guid=[guid]::Empty;if(-not [guid]::TryParseExact($RunId,'D',[ref]$guid) -or $RunId -cne $guid.ToString('D')){throw 'mDNS RunId不是標準GUID。'}}
 $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData);$root=Join-Path $common 'windows_setup_mdns';$runs=Join-Path $root 'runs';$run=if($RunId){Join-Path $runs $RunId}else{$null}
 [pscustomobject]@{Common=$common;Root=$root;Runs=$runs;Current=(Join-Path $root 'current.json');RunRoot=$run;CodeRoot=$(if($run){Join-Path $run 'code'}else{$null});Context=$(if($run){Join-Path $run 'context.json'}else{$null});Status=$(if($run){Join-Path $run 'status.json'}else{$null});TaskName='WindowsSetup-mDNS-Publisher';PowerShell=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe');System=([Environment]::GetFolderPath([Environment+SpecialFolder]::System))}
}
function Assert-SetupMdnsFields {
 param($Value,[string[]]$Fields)
 if($null -eq $Value -or @($Value.PSObject.Properties.Name|Where-Object {$_ -cnotin $Fields}).Count -or @($Fields|Where-Object {$_ -cnotin $Value.PSObject.Properties.Name}).Count){throw 'mDNS固定資料schema不符。'}
}
function Get-SetupMdnsSourceFingerprint {
 param([object[]]$Files)
 $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($Files|ConvertTo-Json -Depth 4 -Compress))))).Replace('-','')}finally{$sha.Dispose()}
}
function Write-SetupMdnsAtomicJson {
 param([string]$Path,$Value)
 $parent=Split-Path $Path -Parent;Assert-SetupUpdateProtectedPath -Path $parent -Directory
 if(Test-Path -LiteralPath $Path){Assert-SetupUpdateProtectedPath -Path $Path}
 $temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
 [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($true));Assert-SetupUpdateProtectedPath -Path $temporary
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
 Assert-SetupUpdateProtectedPath -Path $Path
}
function New-SetupMdnsStage {
 param([Parameter(Mandatory=$true)][string]$SourceRoot)
 $runId=[guid]::NewGuid().ToString('D');$paths=Get-SetupMdnsPaths $runId
 Assert-SetupUpdateAncestors $paths.Common
 foreach($dir in @($paths.Root,$paths.Runs,$paths.RunRoot,$paths.CodeRoot)){New-SetupUpdateProtectedDirectory $dir}
 $files=@()
 foreach($name in Get-SetupMdnsSourceNames){
  $source=Join-Path $SourceRoot $name;$target=Join-Path $paths.CodeRoot $name;Assert-SetupUpdatePlainPath $source
  $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash
  $parent=$paths.CodeRoot;foreach($part in (($name -split '/')|Select-Object -SkipLast 1)){$parent=Join-Path $parent $part;New-SetupUpdateProtectedDirectory $parent}
  Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop;Assert-SetupUpdateProtectedPath $target
  if((Get-FileHash -LiteralPath $target).Hash -cne $hash -or (Get-FileHash -LiteralPath $source).Hash -cne $hash){throw 'mDNS程式複製前後雜湊不符。'}
  $files+=[pscustomobject][ordered]@{Name=$name;SHA256=$hash}
 }
 $context=[pscustomobject][ordered]@{Schema=1;RunId=$runId;MachineGuid=(Get-SetupMdnsMachineGuid);Files=$files;SourceFingerprint=(Get-SetupMdnsSourceFingerprint $files)}
 Write-SetupMdnsAtomicJson -Path $paths.Context -Value $context
 $null=Read-SetupMdnsContext $runId
 return [pscustomobject]@{Paths=$paths;Context=$context}
}
function Read-SetupMdnsContext {
 param([string]$RunId)
 $paths=Get-SetupMdnsPaths $RunId;Assert-SetupUpdateAncestors $paths.Common
 foreach($dir in @($paths.Root,$paths.Runs,$paths.RunRoot,$paths.CodeRoot)){Assert-SetupUpdateProtectedPath -Path $dir -Directory}
 Assert-SetupUpdateProtectedPath $paths.Context
 $ctx=Get-Content -LiteralPath $paths.Context -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-SetupMdnsFields $ctx @('Schema','RunId','MachineGuid','Files','SourceFingerprint')
 if($ctx.Schema -ne 1 -or $ctx.RunId -cne $RunId -or $ctx.MachineGuid -cne (Get-SetupMdnsMachineGuid)){throw 'mDNS context不是本機固定run。'}
 $names=@(Get-SetupMdnsSourceNames)
 if(@($ctx.Files).Count -ne $names.Count -or (@($ctx.Files.Name) -join '|') -cne ($names -join '|')){throw 'mDNS可執行來源清單不符。'}
 foreach($file in $ctx.Files){Assert-SetupMdnsFields $file @('Name','SHA256');if($file.SHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'mDNS來源hash不合法。'};$path=Join-Path $paths.CodeRoot $file.Name;Assert-SetupUpdateProtectedPath $path;if((Get-FileHash -LiteralPath $path).Hash -cne $file.SHA256){throw 'mDNS staged來源被修改。'}}
 if($ctx.SourceFingerprint -cne (Get-SetupMdnsSourceFingerprint $ctx.Files)){throw 'mDNS context來源指紋不符。'}
 return $ctx
}
function Read-SetupMdnsCurrent {
 $paths=Get-SetupMdnsPaths;Assert-SetupUpdateAncestors $paths.Common;Assert-SetupUpdateProtectedPath -Path $paths.Root -Directory;Assert-SetupUpdateProtectedPath $paths.Current
 $pointer=Get-Content -LiteralPath $paths.Current -Raw -Encoding UTF8|ConvertFrom-Json;Assert-SetupMdnsFields $pointer @('Schema','RunId','MachineGuid')
 if($pointer.Schema -ne 1 -or $pointer.MachineGuid -cne (Get-SetupMdnsMachineGuid)){throw 'mDNS current指標不屬本機。'}
 return Read-SetupMdnsContext $pointer.RunId
}
function Get-SetupMdnsTaskArguments {
 param([string]$RunId)
 $paths=Get-SetupMdnsPaths $RunId
 return ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $paths.CodeRoot 'modules/ssh/mdns_worker.ps1')+'" -RunId '+$RunId)
}
function Assert-SetupMdnsTask {
 param($Task,$Context)
 $paths=Get-SetupMdnsPaths $Context.RunId
 if(@($Task).Count -ne 1 -or $Task.TaskName -cne $paths.TaskName -or $Task.TaskPath -cne '\' -or $Task.Description -cne 'windows_setup native mDNS publisher v1' -or @($Task.Actions).Count -ne 1 -or -not [string]::Equals([string]$Task.Actions[0].Execute,$paths.PowerShell,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$Task.Actions[0].WorkingDirectory,$paths.System,[StringComparison]::OrdinalIgnoreCase) -or $Task.Actions[0].Arguments -cne (Get-SetupMdnsTaskArguments $Context.RunId) -or [string]$Task.Principal.LogonType -cne 'ServiceAccount' -or [string]$Task.Principal.RunLevel -cne 'Highest' -or @($Task.Triggers).Count -ne 1 -or $Task.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or [string]$Task.Settings.ExecutionTimeLimit -cne 'PT0S' -or [string]$Task.Settings.MultipleInstances -cne 'IgnoreNew'){throw 'mDNS startup工作不是受控SYSTEM固定action與無時限啟動程序。'}
 $identity=[string]$Task.Principal.UserId
 $sid=if($identity -match '^S-1-'){$identity}else{(New-Object Security.Principal.NTAccount($identity)).Translate([Security.Principal.SecurityIdentifier]).Value}
 if($sid -cne 'S-1-5-18'){throw 'mDNS startup principal不是SYSTEM。'}
}
function Get-SetupMdnsOwnedTaskContext {
 param($Task)
 if(@($Task).Count -ne 1 -or @($Task.Actions).Count -ne 1 -or $Task.Actions[0].Arguments -cnotmatch ' -RunId ([a-f0-9-]{36})$'){throw '既有同名工作不是可確認的mDNS owner，未接管。'}
 $ctx=Read-SetupMdnsContext $Matches[1];Assert-SetupMdnsTask -Task $Task -Context $ctx;return $ctx
}
function Write-SetupMdnsPublisherState {
 param([string]$Path,$Context,$Facts,$State)
 $value=[ordered]@{Schema=1;RunId=$Context.RunId;MachineGuid=$Context.MachineGuid;SourceFingerprint=$Context.SourceFingerprint;ComputerName=$Facts.ComputerName;ProcessId=$PID;DnsClientProcessId=$Facts.DnsClientProcessId;PlanFingerprint=$State.Fingerprint;Plans=@($State.Plans);Status=$State.Status;Registered=[bool]$State.Ready;LeaseCount=@($State.Leases).Count;Error=$State.Error;CheckedAt=[datetime]::UtcNow.ToString('o');RemoteVerified=$false}
 Write-SetupMdnsAtomicJson -Path $Path -Value $value
}
function Invoke-SetupMdnsPublisherWorker {
 param([string]$RunId,[string]$CodeRoot)
 $paths=Get-SetupMdnsPaths $RunId;$ctx=Read-SetupMdnsContext $RunId
 if([IO.Path]::GetFullPath($CodeRoot) -cne $paths.CodeRoot -or (Read-SetupMdnsCurrent).RunId -cne $RunId){throw 'mDNS worker不是目前受保護snapshot。'}
 $state=[pscustomobject]@{Leases=@();Fingerprint='';Plans=@();Ready=$false;Status='Starting';Error=''};$facts=[pscustomobject]@{ComputerName=[Environment]::MachineName;DnsClientProcessId=0}
 try{
  while($true){
   if((Read-SetupMdnsCurrent).RunId -cne $RunId){break}
   $facts=Get-SetupMdnsPublisherFacts
   Invoke-SetupMdnsPublisherCycle -State $state -Context $ctx -Facts $facts -CodeRoot $CodeRoot -StatusPath $paths.Status
   Start-Sleep -Seconds 5
  }
 }catch{$state.Ready=$false;$state.Status='Failed';$state.Error=$_.Exception.Message;Write-SetupMdnsPublisherState -Path $paths.Status -Context $ctx -Facts $facts -State $state;throw}
 finally{Close-SetupMdnsRegistrations $state}
}
function Get-SetupMdnsPublisherStatus {
 param([Parameter(Mandatory=$true)][string]$SourceRoot)
 $ctx=Read-SetupMdnsCurrent;$paths=Get-SetupMdnsPaths $ctx.RunId
 $task=@(Get-ScheduledTask -TaskName $paths.TaskName -TaskPath '\' -ErrorAction Stop);Assert-SetupMdnsTask -Task $task -Context $ctx
 foreach($file in $ctx.Files){$path=Join-Path $SourceRoot $file.Name;Assert-SetupUpdatePlainPath $path;if((Get-FileHash -LiteralPath $path -ErrorAction Stop).Hash -cne $file.SHA256){throw '已安裝mDNS snapshot不是目前工具包來源，請重新套用。'}}
 Assert-SetupUpdateProtectedPath $paths.Status;$status=Get-Content -LiteralPath $paths.Status -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-SetupMdnsFields $status @('Schema','RunId','MachineGuid','SourceFingerprint','ComputerName','ProcessId','DnsClientProcessId','PlanFingerprint','Plans','Status','Registered','LeaseCount','Error','CheckedAt','RemoteVerified')
 if($status.Schema -ne 1 -or $status.RunId -cne $ctx.RunId -or $status.MachineGuid -cne $ctx.MachineGuid -or $status.SourceFingerprint -cne $ctx.SourceFingerprint -or $status.Registered -isnot [bool] -or $status.RemoteVerified -isnot [bool] -or $status.RemoteVerified){throw 'mDNS heartbeat不是本機本snapshot的固定schema。'}
 $facts=Get-SetupMdnsPublisherFacts;$plans=@(Get-SetupMdnsPublicationPlan -ComputerName $facts.ComputerName -Addresses $facts.Addresses);$fingerprint=Get-SetupMdnsFingerprint -Plans $plans -DnsClientProcessId $facts.DnsClientProcessId
 foreach($row in @($status.Plans)){Assert-SetupMdnsFields $row @('HostName','ServiceName','InterfaceIndex','IPv4','IPv6','Port')}
 if(@($status.Plans).Count -ne $plans.Count -or (Get-SetupMdnsFingerprint -Plans @($status.Plans) -DnsClientProcessId $status.DnsClientProcessId) -cne $fingerprint){throw 'mDNS heartbeat公告計畫不是目前固定SSH22地址與名稱。'}
 $checked=[datetime]::MinValue;if(-not [datetime]::TryParseExact([string]$status.CheckedAt,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$checked)){throw 'mDNS heartbeat時間無法解析。'}
 $age=([datetime]::UtcNow-$checked.ToUniversalTime()).TotalSeconds
 $pidValue=[int]0;if(-not [int]::TryParse([string]$status.ProcessId,[ref]$pidValue) -or $pidValue -le 0){throw 'mDNS heartbeat程序ID不合法。'}
 $process=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$pidValue) -ErrorAction Stop);$processOK=$false
 if($process.Count -eq 1){$owner=Invoke-CimMethod -InputObject $process[0] -MethodName GetOwnerSid -ErrorAction Stop;$processOK=(($owner.ReturnValue -is [uint32] -or $owner.ReturnValue -is [int]) -and $owner.ReturnValue -eq 0 -and $owner.Sid -ceq 'S-1-5-18' -and $process[0].SessionId -eq 0 -and [string]::Equals([string]$process[0].ExecutablePath,$paths.PowerShell,[StringComparison]::OrdinalIgnoreCase) -and [string]$process[0].CommandLine -like ('*'+(Join-Path $paths.CodeRoot 'modules/ssh/mdns_worker.ps1')+'* -RunId '+$ctx.RunId) -and ([datetime]$process[0].CreationDate).ToUniversalTime() -le $checked.ToUniversalTime())}
 $ready=($task[0].State -eq 'Running' -and $processOK -and $age -ge 0 -and $age -le 30 -and $status.Status -ceq 'Registered' -and $status.Registered -and $plans.Count -gt 0 -and $status.LeaseCount -eq $plans.Count -and $status.PlanFingerprint -ceq $fingerprint -and $status.ComputerName -ceq $facts.ComputerName -and $status.DnsClientProcessId -eq $facts.DnsClientProcessId -and $facts.PolicyAllowed -and $facts.DnsClientRunning -and $facts.SshdRunning)
 [pscustomobject]@{Success=[bool]$ready;Status=$status.Status;Name=($facts.ComputerName+'.local');RunId=$ctx.RunId;Plans=$plans;Error=$status.Error;RemoteVerified=$false;Detail='受保護SYSTEM程序與新鮮native註冊心跳核對；不是另一臺已連通的證明。'}
}
function Invoke-SetupMdnsPublisher {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 if($VerifyOnly){return Get-SetupMdnsPublisherStatus -SourceRoot $SourceRoot}
 $paths=Get-SetupMdnsPaths;$task=@(Get-ScheduledTask -TaskName $paths.TaskName -TaskPath '\' -ErrorAction SilentlyContinue)
 if($task.Count){
  $old=Get-SetupMdnsOwnedTaskContext $task
  try{$existing=Get-SetupMdnsPublisherStatus -SourceRoot $SourceRoot;if($existing.Success){return $existing}}catch{}
  Stop-ScheduledTask -TaskName $paths.TaskName -TaskPath '\' -ErrorAction Stop
  for($i=0;$i -lt 20 -and (Get-ScheduledTask -TaskName $paths.TaskName -TaskPath '\' -ErrorAction Stop).State -eq 'Running';$i++){Start-Sleep -Milliseconds 500}
  $stopped=Get-ScheduledTask -TaskName $paths.TaskName -TaskPath '\' -ErrorAction Stop;Assert-SetupMdnsTask -Task $stopped -Context $old;if($stopped.State -eq 'Running'){throw '既有mDNS程序未停止，未覆寫startup工作。'}
 }
 $stage=New-SetupMdnsStage -SourceRoot $SourceRoot;$new=$stage.Paths
 $arguments=Get-SetupMdnsTaskArguments $stage.Context.RunId
 $action=New-ScheduledTaskAction -Execute $new.PowerShell -Argument $arguments -WorkingDirectory $new.System
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1)) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $new.TaskName -TaskPath '\' -Description 'windows_setup native mDNS publisher v1' -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force:($task.Count -eq 1) -ErrorAction Stop|Out-Null
 Assert-SetupMdnsTask -Task @(Get-ScheduledTask -TaskName $new.TaskName -TaskPath '\' -ErrorAction Stop) -Context $stage.Context
 Write-SetupMdnsAtomicJson -Path $new.Current -Value ([ordered]@{Schema=1;RunId=$stage.Context.RunId;MachineGuid=$stage.Context.MachineGuid})
 Start-ScheduledTask -TaskName $new.TaskName -TaskPath '\' -ErrorAction Stop
 $last=$null
 for($i=0;$i -lt 120;$i++){
  try{$last=Get-SetupMdnsPublisherStatus -SourceRoot $SourceRoot;if($last.Success){return $last};if($last.Status -in @('Failed','SuppressedByPolicy')){throw ('mDNS公告未完成：'+$last.Status+' '+$last.Error)}}catch{if($last -and $last.Status -in @('Failed','SuppressedByPolicy')){throw}}
  Start-Sleep -Seconds 1
 }
 throw '等待受控mDNS原生註冊逾時，不能以本機解析結果取代公告。'
}