#Requires -Version 5.1
function Test-SetupTaskbarLayout {
 param([string]$LayoutPath)
 if(-not(Test-Path -LiteralPath $LayoutPath -PathType Leaf)){return $false}
 $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
 $reader=[Xml.XmlReader]::Create($LayoutPath,$settings)
 try{$xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)}finally{$reader.Dispose()}
 $pins=@($xml.SelectNodes('//*[local-name()="TaskbarPinList"]/*'));$collections=@($xml.SelectNodes('//*[local-name()="CustomTaskbarLayoutCollection"]'))
 return ($pins.Count -eq 1 -and $pins[0].LocalName -ceq 'DesktopApp' -and $pins[0].DesktopApplicationID -ceq 'MSEdge' -and $collections.Count -eq 1 -and $collections[0].PinListPlacement -ceq 'Replace')
}
function Invoke-SetupTaskbarSettings {
 param([Parameter(Mandatory=$true)][string]$OutputRoot,[Parameter(Mandatory=$true)][string]$LayoutPath,[switch]$VerifyOnly,[string]$ExpectedFinalizeCommand,[switch]$PendingFinalizeTask)
 if(-not $VerifyOnly){
  Export-SetupTaskbarBackup -Path (Join-Path $OutputRoot ('Taskbar-Before-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.reg'))
$search='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
if(-not(Test-Path $search)){New-Item $search -Force|Out-Null}
$searchPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
if(-not(Test-Path $searchPolicy)){New-Item $searchPolicy -Force|Out-Null}
New-ItemProperty $searchPolicy -Name SearchOnTaskbarMode -Value 0 -PropertyType DWord -Force|Out-Null
try{New-ItemProperty $advanced -Name TaskbarDa -Value 0 -PropertyType DWord -Force|Out-Null}catch{Write-Warning '個人小工具開關受保護，將以機器原則關閉小工具。'}
New-ItemProperty $advanced -Name ShowTaskViewButton -Value 0 -PropertyType DWord -Force|Out-Null
$widgets='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
if(-not(Test-Path $widgets)){New-Item $widgets -Force|Out-Null}
New-ItemProperty $widgets -Name AllowNewsAndInterests -Value 0 -PropertyType DWord -Force|Out-Null

$xml=@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="MSEdge" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
[xml]$validated=$xml
[IO.File]::WriteAllText($layoutPath,$xml,[Text.UTF8Encoding]::new($false))
$policy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if(-not(Test-Path $policy)){New-Item $policy -Force|Out-Null}
New-ItemProperty $policy -Name StartLayoutFile -Value $layoutPath -PropertyType String -Force|Out-Null
New-ItemProperty $policy -Name LockedStartLayout -Value 1 -PropertyType DWord -Force|Out-Null

 }
 $searchPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';$advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced';$widgets='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Dsh'
 $search=(Get-ItemProperty $searchPolicy -ErrorAction SilentlyContinue).SearchOnTaskbarMode
 $advancedValues=Get-ItemProperty $advanced -ErrorAction SilentlyContinue
 $widgetsValue=(Get-ItemProperty $widgets -ErrorAction SilentlyContinue).AllowNewsAndInterests
 $policy=Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -ErrorAction SilentlyContinue
 $runOnce=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue).NUC8FinalizeTaskbar
 $pending=($PendingFinalizeTask -or $null -ne $runOnce -or $null -ne $policy.StartLayoutFile -or $null -ne $policy.LockedStartLayout)
 $layoutOK=Test-SetupTaskbarLayout $LayoutPath
 $bindingOK=($null -eq $policy.StartLayoutFile -or $policy.StartLayoutFile -ceq $LayoutPath) -and ($null -eq $runOnce -or ($ExpectedFinalizeCommand -and $runOnce -ceq $ExpectedFinalizeCommand))
 $configured=($search -eq 0 -and $advancedValues.ShowTaskViewButton -eq 0 -and $widgetsValue -eq 0 -and $layoutOK)
 $applyBinding=($policy.StartLayoutFile -ceq $LayoutPath -and $policy.LockedStartLayout -eq 1)
 $success=if($VerifyOnly){$configured -and $bindingOK -and -not $pending}else{$configured -and $applyBinding}
 [pscustomobject]@{Success=[bool]$success;Status=$(if(-not $success -and -not $VerifyOnly){'Failed'}elseif(-not $VerifyOnly){'Applied'}elseif($success){'Confirmed'}elseif($configured -and $bindingOK -and $pending){'PendingSignIn'}else{'Failed'});BindingMatches=[bool]$(if($VerifyOnly){$bindingOK}else{$applyBinding});Configured=[bool]$configured;SearchPolicyMode=$search;TaskbarDa=$advancedValues.TaskbarDa;WidgetsPolicy=$widgetsValue;ShowTaskViewButton=$advancedValues.ShowTaskViewButton;TaskbarLayout=$LayoutPath;PinnedDesktopApp='MSEdge';RequiresNextSignIn=[bool]$(if($VerifyOnly){$pending}else{$true});Error=$(if(-not $success){'工作列設定尚未完成或暫時政策與本輪配置不符。'}else{''});CheckedAt=(Get-Date).ToString('o')}
}
function Invoke-SetupTaskbarFinalize {
 param([Parameter(Mandatory=$true)][string]$LayoutPath)
 Start-Sleep -Seconds 45
 $policy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
 $current=Get-ItemProperty $policy -ErrorAction SilentlyContinue
 if($current.StartLayoutFile -cne $LayoutPath){return [pscustomobject]@{Success=$false;Status='Obsolete';TemporaryLayoutPolicyRemoved=$false;Error='工作列政策已屬於其他配置，未解除。'}}
 Remove-ItemProperty $policy -Name LockedStartLayout -ErrorAction SilentlyContinue
 Remove-ItemProperty $policy -Name StartLayoutFile -ErrorAction SilentlyContinue
 $after=Get-ItemProperty $policy -ErrorAction SilentlyContinue
 if($null -ne $after.StartLayoutFile -or $null -ne $after.LockedStartLayout){return [pscustomobject]@{Success=$false;Status='Failed';TemporaryLayoutPolicyRemoved=$false;Error='工作列暫時政策讀回仍存在，未完成解除。'}}
 [pscustomobject]@{Success=$true;Status='Finalized';TemporaryLayoutPolicyRemoved=$true;FinalizedAt=(Get-Date).ToString('o')}
}
