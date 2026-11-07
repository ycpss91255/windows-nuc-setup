#Requires -Version 5.1
# Library only. Importing this file does not modify the system.
. (Join-Path $PSScriptRoot 'network-sites.ps1')

function Assert-SyncPlainPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 $current=[IO.Path]::GetFullPath($Path)
 while($current){
  if(Test-Path -LiteralPath $current){
   if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "拒絕存取重新解析點：$current"}
  }
  $parent=[IO.Path]::GetDirectoryName($current.TrimEnd('\'))
  if($parent -eq $current){break};$current=$parent
 }
}

function Get-SyncTextHash {
 param([AllowEmptyString()][string]$Text)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','')}finally{$sha.Dispose()}
}

function Get-CustomHostsSourceDigest {
 param([Parameter(Mandatory=$true)][string]$ProfilePath,[ValidateSet('All','Hosts','SSH')][string]$Mode='All')
 $paths=@((Join-Path $ProfilePath '.config\hosts\sites.json'))
 if($Mode -in @('All','SSH')){$paths+=Join-Path $ProfilePath '.ssh\config'}
 foreach($spec in @(@{Path='.config\hosts\hosts.d';Filter='*.hosts'},@{Path='.ssh\config.d';Filter='*.conf'})){
  if($Mode -eq 'Hosts' -and $spec.Filter -eq '*.conf'){continue}
  if($Mode -eq 'SSH' -and $spec.Filter -eq '*.hosts'){continue}
  $directory=Join-Path $ProfilePath $spec.Path;Assert-SyncPlainPath $directory
  if(Test-Path -LiteralPath $directory){$paths+=@(Get-ChildItem -LiteralPath $directory -File -Filter $spec.Filter|Sort-Object Name|Select-Object -ExpandProperty FullName)}
 }
 $parts=foreach($path in ($paths|Sort-Object -Unique)){
  Assert-SyncPlainPath $path
  if(Test-Path -LiteralPath $path -PathType Leaf){$path+'='+[IO.File]::ReadAllText($path)}else{$path+'=<missing>'}
 }
 Get-SyncTextHash ($parts -join "`n")
}

function Read-SyncTextDocument {
 param([string]$Path)
 Assert-SyncPlainPath $Path
 $bytes=[IO.File]::ReadAllBytes($Path)
 $encoding=New-Object Text.UTF8Encoding($false,$true);$offset=0
 if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){$encoding=New-Object Text.UTF8Encoding($true,$true);$offset=3}
 elseif($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254){$encoding=New-Object Text.UnicodeEncoding($false,$true,$true);$offset=2}
 elseif($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255){$encoding=New-Object Text.UnicodeEncoding($true,$true,$true);$offset=2}
 try{$text=$encoding.GetString($bytes,$offset,$bytes.Length-$offset)}catch{
  if($offset -gt 0){throw 'hosts 檔案的 BOM 編碼內容不合法，拒絕改寫。'}
  # PowerShell 7's Encoding.Default is UTF-8, not the Windows ANSI code page.
  if(-not ('CustomHostsNativeEncoding' -as [type])){Add-Type 'using System.Runtime.InteropServices;public static class CustomHostsNativeEncoding{[DllImport("kernel32.dll")]public static extern uint GetACP();}'}
  $encoding=[Text.Encoding]::GetEncoding([int][CustomHostsNativeEncoding]::GetACP(),(New-Object Text.EncoderExceptionFallback),(New-Object Text.DecoderExceptionFallback));$offset=0;$text=$encoding.GetString($bytes)
 }
 [pscustomobject]@{Text=$text;Encoding=$encoding;ByteHash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}

function Write-SyncTextFile {
 param([string]$Path,[AllowEmptyString()][string]$Text,[Text.Encoding]$Encoding,[AllowNull()][string]$ExpectedHash)
 Assert-SyncPlainPath $Path
 $exists=Test-Path -LiteralPath $Path -PathType Leaf
 if($exists){
  if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash){throw "檔案在同步期間被其他程式修改，下一輪重試：$Path"}
  if((Read-SyncTextDocument $Path).Text -ceq $Text){return $false}
 }elseif($ExpectedHash){throw "檔案在同步期間被刪除：$Path"}
 $temp=Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.custom-hosts-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  [IO.File]::WriteAllText($temp,$Text,$Encoding)
  if($exists){
   Set-Acl -LiteralPath $temp -AclObject (Get-Acl -LiteralPath $Path)
   Assert-SyncPlainPath $Path
   if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash){throw "檔案在同步期間被其他程式修改：$Path"}
   [IO.File]::Replace($temp,$Path,($temp+'.previous'))
  }else{[IO.File]::Move($temp,$Path)}
  return $true
 }finally{foreach($cleanup in @($temp,($temp+'.previous'))){if(Test-Path -LiteralPath $cleanup){Remove-Item -LiteralPath $cleanup -Force}}}
}


function Get-CustomHostsPlan {
 param([Parameter(Mandatory=$true)][string]$ProfilePath,[string]$TargetHostsPath,[ValidateSet('Hosts','SSH')][string]$Mode='Hosts',[object]$Snapshot)
 $configPath=Join-Path $ProfilePath '.config\hosts\sites.json'
 Assert-SyncPlainPath $configPath
 $sourceDigest=Get-CustomHostsSourceDigest -ProfilePath $ProfilePath -Mode $Mode
 $configuration=[IO.File]::ReadAllText($configPath)|ConvertFrom-Json
 if(-not $PSBoundParameters.ContainsKey('Snapshot')){$Snapshot=Get-NetworkSnapshot}
 $active=@(Get-ActiveNetworkSites -Configuration $configuration -Snapshot $Snapshot|Sort-Object -Unique)
 $known=@('global')+@($configuration.Sites|ForEach-Object {$_.Id})
 $enabled=@('global')+$active
 $warnings=@($Snapshot.Warnings|Where-Object {$_})
 if($Mode -eq 'SSH'){
  $sshRoot=Join-Path $ProfilePath '.ssh\config.d'
  $includes=New-Object Collections.Generic.List[string]
  foreach($site in $enabled){
   $path=Join-Path $sshRoot ($site+'.conf');Assert-SyncPlainPath $path
   if(Test-Path -LiteralPath $path -PathType Leaf){$includes.Add('Include "config.d/'+$site+'.conf"')}
   elseif($site -ne 'global'){$warnings+=('SSH 站點來源尚未建立：'+$site+'.conf')}
  }
  $text=(@('# Generated by CustomHostsSync. Edit config.d sources, not this file.')+@($includes.ToArray())) -join "`r`n"
  $text+="`r`n"
  $main=Join-Path $ProfilePath '.ssh\config';Assert-SyncPlainPath $main
  $mainText=[IO.File]::ReadAllText($main)
  $mainInclude=[regex]::Match($mainText,'(?im)^\s*Include\s+"?active-sites\.conf"?\s*(?:#.*)?$')
  $mainScope=[regex]::Match($mainText,'(?im)^\s*(?:Host|Match)\s+')
  if(-not $mainInclude.Success -or ($mainScope.Success -and $mainInclude.Index -gt $mainScope.Index)){throw '.ssh/config 必須在全域區段 Include active-sites.conf，且放在 Host/Match 之前。'}
  if($mainText -match '(?im)^\s*(?:Host|Match)\s+' -or $mainText -match '(?im)^\s*Include\s+(?!"?active-sites\.conf"?\s*(?:#.*)?$)'){$warnings+='既有 SSH config 另有 Host/Match/Include；這些設定不受站點匯入限制。'}
  $output=Join-Path $ProfilePath '.ssh\active-sites.conf';Assert-SyncPlainPath $output
  $document=if(Test-Path -LiteralPath $output){Read-SyncTextDocument $output}else{$null}
  $entries=$includes.Count;$sourceCount=@(Get-ChildItem -LiteralPath $sshRoot -Filter '*.conf' -File -ErrorAction SilentlyContinue).Count
  $encoding=New-Object Text.UTF8Encoding($false)
 }else{
  if([string]::IsNullOrWhiteSpace($TargetHostsPath)){throw 'Hosts 輸出未指定目標檔案。'}
  $hostRoot=Join-Path $ProfilePath '.config\hosts\hosts.d'
  $lines=New-Object Collections.Generic.List[string]
  $mapping=@{};$sourceCount=0
  foreach($file in @(Get-ChildItem -LiteralPath $hostRoot -Filter '*.hosts' -File -ErrorAction SilentlyContinue|Sort-Object Name)){
   Assert-SyncPlainPath $file.FullName
   $site=$file.BaseName
   if($site -notin $known){continue}
   $lineNumber=0
   foreach($raw in [IO.File]::ReadAllLines($file.FullName)){
    $lineNumber++;$line=($raw -split '#',2)[0].Trim()
    if(-not $line){continue};$sourceCount++
    $parts=@($line -split '\s+');$ip=$null
    if($parts.Count -lt 2 -or $parts[0] -notmatch '[\.:]' -or -not [Net.IPAddress]::TryParse($parts[0],[ref]$ip)){throw "不合法的 hosts 資料：$($file.Name):$lineNumber"}
    $selected=New-Object Collections.Generic.List[string]
    foreach($alias in $parts[1..($parts.Count-1)]){
     if($alias.Length -gt 253 -or $alias -notmatch '^[A-Za-z0-9_](?:[A-Za-z0-9_.-]*[A-Za-z0-9_])?$'){throw "不合法的主機別名：$($file.Name):$lineNumber"}
     $include=($site -in $enabled -or $alias -like 'ip.global.*')
     if(-not $include){continue}
     $key=$alias.ToLowerInvariant()+'|'+$ip.AddressFamily
     if($mapping.ContainsKey($key) -and $mapping[$key] -ne $ip.ToString()){throw "啟用站點的主機別名 IP 衝突：$alias"}
     if(-not $mapping.ContainsKey($key)){$mapping[$key]=$ip.ToString();$selected.Add($alias)}
    }
    if($selected.Count){$lines.Add($ip.ToString()+"`t"+($selected -join ' '))}
   }
  }
  foreach($site in $active){if(-not(Test-Path -LiteralPath (Join-Path $hostRoot ($site+'.hosts')))){$warnings+=('Hosts 站點來源尚未建立：'+$site+'.hosts')}}
  $document=Read-SyncTextDocument $TargetHostsPath
  $newline=if($document.Text.Contains("`r`n")){"`r`n"}else{"`n"}
  $starts=[regex]::Matches($document.Text,'(?m)^# BEGIN custom-hosts\r?$')
  $ends=[regex]::Matches($document.Text,'(?m)^# END custom-hosts\r?$')
  if($starts.Count -ne $ends.Count -or $starts.Count -gt 1 -or ($starts.Count -eq 1 -and $starts[0].Index -gt $ends[0].Index)){throw 'Windows hosts 的 custom-hosts 管理標記不完整或重複，已停止修改。'}
  $block=(@('# BEGIN custom-hosts','# Managed by CustomHostsSync. Edit user source files instead.')+@($lines.ToArray())+@('# END custom-hosts')) -join $newline
  if($starts.Count){
   $first=$starts[0].Index;$last=$ends[0].Index+$ends[0].Length
   $tail=$document.Text.Substring($last)
   if($ends[0].Value.EndsWith("`r") -and $tail.StartsWith("`n")){$tail="`r"+$tail}
   $text=$document.Text.Substring(0,$first)+$block+$tail
  }else{
   $separator=if($document.Text.Length -eq 0 -or $document.Text.EndsWith("`n")){''}else{$newline}
   $text=$document.Text+$separator+$block+$newline
  }
  $output=$TargetHostsPath;$encoding=$document.Encoding;$entries=$lines.Count
 }
 if((Get-CustomHostsSourceDigest -ProfilePath $ProfilePath -Mode $Mode) -ne $sourceDigest){throw '來源在讀取期間變更，下一輪重新讀取。'}
 [pscustomobject]@{Configuration=$configuration;ActiveSites=$active;SourceDigest=$sourceDigest;OutputPath=$output;Text=$text;Document=$document;Encoding=$encoding;Entries=$entries;SourceEntryCount=$sourceCount;Warnings=$warnings}
}

function Invoke-CustomHostsSync {
 param([Parameter(Mandatory=$true)][string]$ProfilePath,[Parameter(Mandatory=$true)][string]$StatePath,[string]$TargetHostsPath,[ValidateSet('All','Hosts','SSH')][string]$Mode='All',[object]$Snapshot)
 Assert-SyncPlainPath $StatePath
 if(-not(Test-Path -LiteralPath $StatePath)){New-Item -ItemType Directory -Path $StatePath|Out-Null}
 $configPath=Join-Path $ProfilePath '.config\hosts\sites.json';Assert-SyncPlainPath $configPath
 $configuration=[IO.File]::ReadAllText($configPath)|ConvertFrom-Json
 Assert-NetworkSiteConfiguration $configuration
 if(-not $PSBoundParameters.ContainsKey('Snapshot')){$Snapshot=Get-NetworkSnapshot}
 $active=@(Get-ActiveNetworkSites -Configuration $configuration -Snapshot $Snapshot|Sort-Object -Unique)
 $outputs=[ordered]@{}
 $statusPath=Join-Path $StatePath 'status.json'
 if(Test-Path $statusPath){try{$previous=[IO.File]::ReadAllText($statusPath)|ConvertFrom-Json;foreach($name in @('Hosts','SSH')){if($previous.Outputs.$name){$outputs[$name]=$previous.Outputs.$name}}}catch{}}
 $selected=if($Mode -eq 'All'){@('Hosts','SSH')}else{@($Mode)}
 foreach($name in $selected){
  $enabled=if($configuration.Outputs){[bool]$configuration.Outputs.$name}else{$true}
  if(-not $enabled){$outputs[$name]=[pscustomobject]@{Enabled=$false;Success=$true;CheckedAt=(Get-Date).ToString('o');Changed=$false;Warnings=@('此輸出已停用，原有輸出檔保持不變。')};continue}
  try{
   $plan=Get-CustomHostsPlan -ProfilePath $ProfilePath -TargetHostsPath $TargetHostsPath -Mode $name -Snapshot $Snapshot
   if($name -eq 'Hosts' -and $plan.Document.Text -cne $plan.Text){
    $original=Join-Path $StatePath 'hosts.original.backup'
    if(-not(Test-Path -LiteralPath $original)){Copy-Item -LiteralPath $TargetHostsPath -Destination $original}
    Copy-Item -LiteralPath $TargetHostsPath -Destination (Join-Path $StatePath 'hosts.previous.backup') -Force
   }
   $changed=Write-SyncTextFile -Path $plan.OutputPath -Text $plan.Text -Encoding $plan.Encoding -ExpectedHash $(if($plan.Document){$plan.Document.ByteHash}else{$null})
   $outputs[$name]=[pscustomobject]@{Enabled=$true;Success=$true;CheckedAt=(Get-Date).ToString('o');SourceDigest=$plan.SourceDigest;OutputHash=(Get-FileHash -LiteralPath $plan.OutputPath).Hash;Entries=$plan.Entries;SourceEntryCount=$plan.SourceEntryCount;Changed=[bool]$changed;Warnings=@($plan.Warnings)}
  }catch{
   $outputs[$name]=[pscustomobject]@{Enabled=$true;Success=$false;CheckedAt=(Get-Date).ToString('o');Error=$_.Exception.Message;Changed=$false;Warnings=@()}
  }
 }
 $failures=@($selected|Where-Object {-not $outputs[$_].Success})
 $status=[ordered]@{Success=($failures.Count -eq 0);Mode=$Mode;CheckedAt=(Get-Date).ToString('o');ProfilePath=$ProfilePath;ActiveSites=$active;Outputs=$outputs;PollSeconds=$configuration.PollSeconds;Warnings=@($Snapshot.Warnings|Where-Object {$_})}
 [IO.File]::WriteAllText($statusPath,($status|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
 $errorPath=Join-Path $StatePath 'last-error.json'
 if($failures.Count){
  [IO.File]::WriteAllText($errorPath,(@{FailedAt=$status.CheckedAt;FailedOutputs=$failures;Errors=@($failures|ForEach-Object {$outputs[$_].Error})}|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
 }elseif($Mode -eq 'All' -and (Test-Path -LiteralPath $errorPath)){Remove-Item -LiteralPath $errorPath -Force}
 [pscustomobject]$status
}






