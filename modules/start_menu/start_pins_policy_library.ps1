#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'start_pins_asset_library.ps1')
function Get-StartPinsRoute {
 param([int]$Build,[int]$Revision,[string]$AdmxText)
 if($Build -lt 26100 -or ($Build -eq 26100 -and $Revision -lt 4770) -or [string]::IsNullOrWhiteSpace($AdmxText)){return 'LegacyPackage'}
 $xml=ConvertTo-StartPinsXml $AdmxText
 $policy=@($xml.SelectNodes('//*[local-name()="policy" and @name="ConfigureStartPins" and @key="Software\Policies\Microsoft\Windows\Explorer" and @valueName="ConfigureStartPins"]'))
 if($policy.Count -eq 1 -and $policy[0].SelectSingleNode('.//*[local-name()="text" and @valueName="ConfigureStartPinsJSON"]')){return 'Gpo'}
 return 'LegacyPackage'
}
function Invoke-StartPinsLegacyPolicy {
 param([string]$AssetRoot,[switch]$ApplyPolicy,[switch]$NonInteractive,[scriptblock]$Confirm)
 $manifest=Assert-StartPinsAsset $AssetRoot
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.PackageID -eq $manifest.PackageId -and $_.IsInstalled})
 if($installed.Count -gt 1 -or ($installed.Count -eq 1 -and ($installed[0].PackageName -cne $manifest.PackageName -or $installed[0].Version -ne $manifest.PackageVersion))){throw '既有 Start 政策包身分不符，未重新套用。'}
 if($installed.Count -eq 1){return [pscustomobject]@{Success=$false;Status='PendingSignIn';PolicyInstalled=$true}}
 if(-not $ApplyPolicy -or $NonInteractive -or $null -eq $Confirm){return [pscustomobject]@{Success=$false;Status='LegacyPendingApply';PolicyInstalled=$false}}
 if((& $Confirm) -cne 'YES'){return [pscustomobject]@{Success=$false;Status='LegacyPendingApply';PolicyInstalled=$false}}
 Install-ProvisioningPackage -PackagePath (Join-Path $AssetRoot 'empty_start.ppkg') -QuietInstall -ErrorAction Stop|Out-Null
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.PackageID -eq $manifest.PackageId -and $_.IsInstalled -and $_.PackageName -ceq $manifest.PackageName -and $_.Version -eq $manifest.PackageVersion})
 if($installed.Count -ne 1){throw 'Start 政策套用後原生讀回不符，不能視為完成。'}
 return [pscustomobject]@{Success=$false;Status='PendingSignIn';PolicyInstalled=$true}
}
function Get-StartPinsExportState {
 param([string]$ExportPath,$PolicyState)
 Export-StartLayout -Path $ExportPath -ErrorAction Stop
 $actual=[IO.File]::ReadAllText($ExportPath)|ConvertFrom-Json -ErrorAction Stop
 if(-not $actual -or 'pinnedList' -notin @($actual.PSObject.Properties.Name) -or $null -eq $actual.pinnedList -or $actual.pinnedList -isnot [Array]){throw '開始選單原生匯出缺少有效 pinnedList，不能視為空白。'}
 $count=@($actual.pinnedList).Count
 $status=if($PolicyState.Status -eq 'LegacyPendingApply'){'LegacyPendingApply'}elseif($count -eq 0){'Confirmed'}else{'PendingSignIn'}
 return [ordered]@{Success=($status -eq 'Confirmed');Status=$status;PinCount=$count;ExportPath=$ExportPath;CheckedAt=(Get-Date).ToString('o')}
}
