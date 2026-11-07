#Requires -Version 5.1
# Pure rule evaluation plus a read-only Windows network snapshot.
function Get-NetworkRulePropertyNames {
 param($Value)
 if($Value -is [Collections.IDictionary]){return @($Value.Keys)}
 return @($Value.PSObject.Properties.Name)
}

function Test-NetworkInteger {
 param($Value)
 return ($Value -is [int] -or $Value -is [long])
}

function ConvertTo-NetworkIPv4Bytes {
 param([Parameter(Mandatory=$true)][string]$Address)
 if($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$'){throw "Invalid IPv4 address: $Address"}
 $parsed=$null
 if(-not [Net.IPAddress]::TryParse($Address,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw "Invalid IPv4 address: $Address"}
 return $parsed.GetAddressBytes()
}

function ConvertTo-NetworkCidr {
 param([Parameter(Mandatory=$true)][string]$Cidr)
 if($Cidr -notmatch '^([^/]+)/([0-9]{1,2})$'){throw "Invalid IPv4 CIDR: $Cidr"}
 $address=$Matches[1];$prefix=[int]$Matches[2]
 if($prefix -gt 32){throw "Invalid IPv4 CIDR prefix: $Cidr"}
 $bytes=@(ConvertTo-NetworkIPv4Bytes -Address $address)
 return [pscustomobject]@{Bytes=$bytes;PrefixLength=$prefix}
}

function Test-NetworkIPv4Cidr {
 param([Parameter(Mandatory=$true)][string]$Address,[Parameter(Mandatory=$true)][string]$Cidr)
 $ip=@(ConvertTo-NetworkIPv4Bytes -Address $Address)
 $network=ConvertTo-NetworkCidr -Cidr $Cidr
 $remaining=$network.PrefixLength
 for($i=0;$i -lt 4;$i++){
  $bits=[Math]::Min(8,$remaining)
  if($bits -eq 0){return $true}
  $mask=[int](256-[Math]::Pow(2,8-$bits))
  if(([int]$ip[$i] -band $mask) -ne ([int]$network.Bytes[$i] -band $mask)){return $false}
  $remaining-=$bits
 }
 return $true
}

function Assert-NetworkSiteConfiguration {
 param([Parameter(Mandatory=$true)]$Configuration)
 if($Configuration -isnot [Collections.IDictionary] -and $Configuration -isnot [pscustomobject]){throw 'Network configuration must be a JSON object.'}
 $rootNames=@(Get-NetworkRulePropertyNames $Configuration)
 foreach($name in $rootNames){if($name -notin @('Version','PollSeconds','Sites','Outputs')){throw "Unknown configuration field: $name"}}
 if('Version' -notin $rootNames -or -not(Test-NetworkInteger $Configuration.Version) -or $Configuration.Version -ne 1){throw 'Network configuration Version must be integer 1.'}
 if('PollSeconds' -notin $rootNames -or -not(Test-NetworkInteger $Configuration.PollSeconds) -or $Configuration.PollSeconds -lt 5 -or $Configuration.PollSeconds -gt 300){throw 'PollSeconds must be an integer between 5 and 300.'}
 if('Sites' -notin $rootNames -or $null -eq $Configuration.Sites -or $Configuration.Sites -isnot [array]){throw 'Sites must be a JSON array (it may be empty).'}
 if('Outputs' -in $rootNames){
  if($null -eq $Configuration.Outputs -or ($Configuration.Outputs -isnot [Collections.IDictionary] -and $Configuration.Outputs -isnot [pscustomobject])){throw 'Outputs must be an object with Hosts and SSH boolean values.'}
  $outputNames=@(Get-NetworkRulePropertyNames $Configuration.Outputs)
  if($outputNames.Count -ne 2 -or 'Hosts' -notin $outputNames -or 'SSH' -notin $outputNames -or $Configuration.Outputs.Hosts -isnot [bool] -or $Configuration.Outputs.SSH -isnot [bool]){throw 'Outputs must contain exactly Hosts and SSH boolean values.'}
 }
 $seen=@{}
 foreach($site in $Configuration.Sites){
  if($null -eq $site -or ($site -isnot [Collections.IDictionary] -and $site -isnot [pscustomobject])){throw 'Each site must be a JSON object.'}
  $names=@(Get-NetworkRulePropertyNames $site)
  foreach($name in $names){if($name -notin @('Id','Enabled','Rules')){throw "Unknown site field: $name"}}
  if($site.Id -isnot [string] -or $site.Id.Length -gt 64 -or $site.Id -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or $site.Id -match '^(global|con|prn|aux|nul|com[1-9]|lpt[1-9])$'){throw 'Site Id must be 1-64 lowercase letters/digits/underscore/hyphen; global and Windows device names are reserved.'}
  if($seen.ContainsKey($site.Id)){throw ('Duplicate site Id: '+$site.Id)}
  $seen[$site.Id]=$true
  if('Enabled' -notin $names -or $site.Enabled -isnot [bool]){throw ('Enabled must be true/false for '+$site.Id)}
  if('Rules' -notin $names -or $site.Rules -isnot [array] -or $site.Rules.Count -eq 0){throw ('Rules must be a nonempty array for '+$site.Id)}
  foreach($rule in $site.Rules){
   if($null -eq $rule -or ($rule -isnot [Collections.IDictionary] -and $rule -isnot [pscustomobject])){throw ('Each rule must be an object for '+$site.Id)}
   $fields=@(Get-NetworkRulePropertyNames $rule)
   if($fields.Count -eq 0){throw ('Empty rules are not allowed for '+$site.Id)}
   foreach($field in $fields){
    if($field -notin @('SSID','NetworkProfile','IPv4Cidr','AdapterName','AdapterNameRegex','AdapterDescriptionRegex','PrefixLength')){throw "Unknown rule field: $field"}
    $value=$rule.$field
    if($field -in @('SSID','NetworkProfile','IPv4Cidr','AdapterName')){
     if($value -isnot [array] -or $value.Count -eq 0){throw "$field must be a nonempty JSON array."}
     foreach($part in $value){
      if($part -isnot [string] -or [string]::IsNullOrWhiteSpace($part)){throw "$field entries must be nonempty strings."}
      if($field -eq 'IPv4Cidr'){$null=ConvertTo-NetworkCidr -Cidr $part}
     }
    }elseif($field -eq 'PrefixLength'){
     if(-not(Test-NetworkInteger $value) -or $value -lt 0 -or $value -gt 32){throw 'PrefixLength must be an integer between 0 and 32.'}
    }else{
     if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 512){throw "$field must be a nonempty regular expression of at most 512 characters."}
     try{$null=New-Object Text.RegularExpressions.Regex($value,[Text.RegularExpressions.RegexOptions]::IgnoreCase,[TimeSpan]::FromMilliseconds(100))}catch{throw "Invalid regular expression for $field"}
    }
   }
  }
 }
}

function Test-NetworkAdapterRule {
 param([Parameter(Mandatory=$true)]$Adapter,[Parameter(Mandatory=$true)]$Rule)
 $fields=@(Get-NetworkRulePropertyNames $Rule)
 if('SSID' -in $fields){
  $ssidMatch=$false
  foreach($ssid in @($Adapter.SSIDs)){if($Rule.SSID -ccontains $ssid){$ssidMatch=$true;break}}
  if(-not $ssidMatch){return $false}
 }
 if('AdapterName' -in $fields -and $Rule.AdapterName -notcontains [string]$Adapter.Name){return $false}
 if('NetworkProfile' -in $fields){
  $profileMatch=$false
  foreach($name in @($Adapter.NetworkProfiles)){if($Rule.NetworkProfile -contains $name){$profileMatch=$true;break}}
  if(-not $profileMatch){return $false}
 }
 foreach($pair in @(@{Field='AdapterNameRegex';Value=[string]$Adapter.Name},@{Field='AdapterDescriptionRegex';Value=[string]$Adapter.Description})){
  if($pair.Field -in $fields){
   $regex=New-Object Text.RegularExpressions.Regex($Rule.($pair.Field),[Text.RegularExpressions.RegexOptions]::IgnoreCase,[TimeSpan]::FromMilliseconds(100))
   if(-not $regex.IsMatch($pair.Value)){return $false}
  }
 }
 if('IPv4Cidr' -in $fields -or 'PrefixLength' -in $fields){
  $addressMatch=$false
  foreach($address in @($Adapter.IPv4)){
   if('PrefixLength' -in $fields -and [int]$address.PrefixLength -ne $Rule.PrefixLength){continue}
   if('IPv4Cidr' -notin $fields){$addressMatch=$true;break}
   foreach($cidr in $Rule.IPv4Cidr){if(Test-NetworkIPv4Cidr -Address $address.Address -Cidr $cidr){$addressMatch=$true;break}}
   if($addressMatch){break}
  }
  if(-not $addressMatch){return $false}
 }
 return $true
}

function Get-ActiveNetworkSites {
 param([Parameter(Mandatory=$true)]$Configuration,[Parameter(Mandatory=$true)]$Snapshot)
 Assert-NetworkSiteConfiguration -Configuration $Configuration
 foreach($site in $Configuration.Sites){
  if(-not $site.Enabled){continue}
  $matched=$false
  foreach($adapter in @($Snapshot.Adapters)){
   foreach($rule in $site.Rules){if(Test-NetworkAdapterRule -Adapter $adapter -Rule $rule){$matched=$true;break}}
   if($matched){break}
  }
  if($matched){Write-Output ([string]$site.Id)}
 }
}

function Get-NetworkWlanSSIDMap {
 # netsh's GUID and SSID labels are stable in localized Windows. Each GUID starts one interface record.
 $wirelessByGuid=@{}
 try{
  $netsh=Join-Path $env:SystemRoot 'System32\netsh.exe'
  $wlan=(& $netsh wlan show interfaces 2>$null) -join "`n"
  foreach($record in [regex]::Matches($wlan,'(?ims)^\s*GUID\s*:\s*([0-9a-f-]{36})\s*\r?\n(.*?)(?=^\s*GUID\s*:|\z)')){
   $ssid=[regex]::Match($record.Groups[2].Value,'(?m)^\s*SSID\s*:\s*(.*?)\s*$')
   if($ssid.Success -and $ssid.Groups[1].Value.Length){$wirelessByGuid[$record.Groups[1].Value]=$ssid.Groups[1].Value}
  }
 }catch{Write-Verbose '目前無法取得實際的 Wi-Fi SSID。'}
 return $wirelessByGuid
}

function Get-NetworkSnapshot {
 $adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop|Where-Object Status -eq 'Up')
 $addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object {$_.AddressState -in @('Preferred','Deprecated') -and $_.IPAddress -notmatch '^(127\.|169\.254\.|0\.)'})
 $profiles=@(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
 $wirelessByGuid=Get-NetworkWlanSSIDMap
 $warnings=New-Object Collections.Generic.List[string]
 $result=@(foreach($adapter in $adapters){
  $ssids=@()
  $guid=([string]$adapter.InterfaceGuid).Trim('{}')
  $profileNames=@($profiles|Where-Object InterfaceIndex -eq $adapter.ifIndex|Select-Object -ExpandProperty Name -Unique)
  if($wirelessByGuid.ContainsKey($guid)){$ssids=@($wirelessByGuid[$guid])}
  elseif([string]$adapter.NdisPhysicalMedium -in @('9','Native802_11','WirelessLan','1') -or [string]$adapter.PhysicalMediaType -match '802\.11|Wireless'){
   $warnings.Add(('無法取得網卡「'+$adapter.Name+'」的實際 SSID。Windows 網路設定檔名稱不等於 SSID；可依需求明確設定 NetworkProfile 或 IPv4Cidr 規則。'))
  }
  [pscustomobject]@{Name=[string]$adapter.Name;Description=[string]$adapter.InterfaceDescription;IPv4=@($addresses|Where-Object InterfaceIndex -eq $adapter.ifIndex|ForEach-Object {[pscustomobject]@{Address=[string]$_.IPAddress;PrefixLength=[int]$_.PrefixLength}});SSIDs=$ssids;NetworkProfiles=$profileNames}
 })
 return [pscustomobject]@{Adapters=$result;Warnings=@($warnings.ToArray())}
}






