#Requires -Version 5.1
function Get-InitRoute {
 param([string]$Sid,[string]$ImageState,[bool]$IsAdministrator,[bool]$DesktopOwned)
 if($Sid -eq 'S-1-5-18'){return 'GuideAudit'}
 if(-not $IsAdministrator){return 'ElevationRequired'}
 if($Sid -match '-500$'){
  if($ImageState -in @('IMAGE_STATE_UNDEPLOYABLE','IMAGE_STATE_GENERALIZE_RESEAL_TO_AUDIT','IMAGE_STATE_SPECIALIZE_RESEAL_TO_AUDIT')){return 'ConfirmAudit'}
  return 'RejectBuiltinAdministrator'
 }
 if($ImageState -eq 'IMAGE_STATE_COMPLETE' -and $DesktopOwned){return 'DesktopSSH'}
 return 'RejectUnknownSetupState'
}
function Test-InitUserName {
 param([string]$Name,[string[]]$ExistingNames)
 if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 20 -or $Name -match '["/\\\[\]:;|=,+*?<>@\x00-\x1f]' -or $Name -match '^[. ]+$' -or $Name -ne $Name.Trim() -or $Name.EndsWith('.')){return $false}
 if($Name -in @('Administrator','Guest','DefaultAccount','defaultuser0','WDAGUtilityAccount','SYSTEM','Public') -or $Name -in $ExistingNames){return $false}
 return $true
}
function Test-InitPassword {
 param([string]$Password)
 return (-not [string]::IsNullOrEmpty($Password) -and $Password.Length -le 127 -and $Password -notmatch '[\x00-\x1f]')
}
function New-InitAnswerXml {
 param([string]$UserName,[string]$Password,[string]$CleanupCommand,[string]$Marker)
 if($Marker -notmatch '^NUC-INIT-[a-f0-9]{32}$'){throw 'Invalid ownership marker.'}
 $ns='urn:schemas-microsoft-com:unattend';$wcm='http://schemas.microsoft.com/WMIConfig/2002/State'
 $doc=New-Object Xml.XmlDocument
 [void]$doc.AppendChild($doc.CreateXmlDeclaration('1.0','utf-8',$null))
 [void]$doc.AppendChild($doc.CreateComment($Marker))
 $root=$doc.CreateElement('unattend',$ns);[void]$doc.AppendChild($root)
 function Element($Parent,[string]$Name,[string]$Text){$e=$doc.CreateElement($Name,$ns);if($PSBoundParameters.ContainsKey('Text')){$e.InnerText=$Text};[void]$Parent.AppendChild($e);return $e}
 $settings=Element $root 'settings';$settings.SetAttribute('pass','oobeSystem')
 $component=Element $settings 'component'
 foreach($pair in @(@('name','Microsoft-Windows-Shell-Setup'),@('processorArchitecture','amd64'),@('publicKeyToken','31bf3856ad364e35'),@('language','neutral'),@('versionScope','nonSxS'))){$component.SetAttribute($pair[0],$pair[1])}
 $oobe=Element $component 'OOBE'
 [void](Element $oobe 'HideOnlineAccountScreens' 'true')
 [void](Element $oobe 'HideWirelessSetupInOOBE' 'true')
 $accounts=Element $component 'UserAccounts';$locals=Element $accounts 'LocalAccounts';$account=Element $locals 'LocalAccount'
 [void]$account.SetAttribute('action',$wcm,'add')
 [void](Element $account 'Name' $UserName)
 [void](Element $account 'Group' 'Administrators')
 $passwordNode=Element $account 'Password'
 # Unattend encoding obscures the value; it is NOT encryption.
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Password+'Password'))
 [void](Element $passwordNode 'Value' $encoded);[void](Element $passwordNode 'PlainText' 'false')
 $first=Element $component 'FirstLogonCommands';$command=Element $first 'SynchronousCommand'
 [void]$command.SetAttribute('action',$wcm,'add')
 [void](Element $command 'Order' '1');[void](Element $command 'Description' 'Remove NUC Init temporary answer file')
 [void](Element $command 'CommandLine' $CleanupCommand)
 return $doc.OuterXml
}
function Get-InitAnswerCandidates {
 param([string]$WindowsPath)
 return @((Join-Path $WindowsPath 'Panther\unattend.xml'),(Join-Path $WindowsPath 'Panther\autounattend.xml'),(Join-Path $WindowsPath 'Panther\Unattend\unattend.xml'),(Join-Path $WindowsPath 'Panther\Unattend\autounattend.xml'),(Join-Path $WindowsPath 'System32\Sysprep\unattend.xml'))
}
function Assert-InitPlainPath {
 param([string]$Path)
 $current=[IO.Path]::GetFullPath($Path)
 while($current){
  if(Test-Path -LiteralPath $current){$item=Get-Item -LiteralPath $current -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('不接受重新解析點路徑：'+$current)}}
  $parent=Split-Path $current -Parent;if($parent -eq $current){break};$current=$parent
 }
}
function Protect-InitFolder {
 param([string]$Path)
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $admin=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
 $system=New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
 $acl.SetOwner($admin)
 foreach($sid in @($admin,$system)){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 Set-Acl -LiteralPath $Path -AclObject $acl
}
