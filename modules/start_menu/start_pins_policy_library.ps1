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
 try{Export-StartLayout -Path $ExportPath -ErrorAction Stop}catch{
  $native=$_.Exception
  while($native.InnerException -and $native.HResult -ne -2147023728){$native=$native.InnerException}
  if($native.HResult -ne -2147023728 -or -not $PolicyState.PolicyInstalled){throw}
  $session=(Get-Process -Id $PID -ErrorAction Stop).SessionId
  $hosts=@(Get-Process -ErrorAction Stop|Where-Object {$_.ProcessName -eq 'StartMenuExperienceHost' -and $_.SessionId -eq $session})
  if($hosts.Count -gt 0){throw}
  # ERROR_NOT_FOUND is not proof of an empty layout; retain a pending observation.
  return [ordered]@{Success=$false;Status='PendingSignIn';PinCount=$null;ExportPath=$null;ExportStatus='Unavailable';NativeHResult='0x80070490';Reason='開始選單原生匯出尚不可用，且目前工作階段未啟動 Start Host；登入後請再驗證。';CheckedAt=(Get-Date).ToString('o')}
 }
 $actual=[IO.File]::ReadAllText($ExportPath)|ConvertFrom-Json -ErrorAction Stop
 if(-not $actual -or 'pinnedList' -notin @($actual.PSObject.Properties.Name) -or $null -eq $actual.pinnedList -or $actual.pinnedList -isnot [Array]){throw '開始選單原生匯出缺少有效 pinnedList，不能視為空白。'}
 $count=@($actual.pinnedList).Count
 $status=if($PolicyState.Status -eq 'LegacyPendingApply'){'LegacyPendingApply'}elseif($count -eq 0){'Confirmed'}else{'PendingSignIn'}
 return [ordered]@{Success=($status -eq 'Confirmed');Status=$status;PinCount=$count;ExportPath=$ExportPath;CheckedAt=(Get-Date).ToString('o')}
}
function Invoke-StartPinsConfiguration {
 param([string]$AssetRoot,[string]$OutputRoot,[string]$AdmxPath=(Join-Path $env:WINDIR 'PolicyDefinitions/StartMenu.admx'),[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive)
 $version=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
 $admx=if(Test-Path -LiteralPath $AdmxPath -PathType Leaf){[IO.File]::ReadAllText($AdmxPath)}else{''}
 $route=Get-StartPinsRoute ([int]$version.CurrentBuildNumber) ([int]$version.UBR) $admx
 if($route -eq 'Gpo'){
  if(-not $VerifyOnly){
   $layout=Join-Path $OutputRoot 'EmptyStartLayout.json'
   Set-Content -LiteralPath $layout -Value '{"pinnedList":[],"applyOnce":true}' -Encoding UTF8 -ErrorAction Stop
   $key='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
   New-Item -Path $key -Force|Out-Null
   New-ItemProperty -Path $key -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force|Out-Null
   New-ItemProperty -Path $key -Name ConfigureStartPinsJSON -PropertyType String -Value $layout -Force|Out-Null
  }
  $policy=[pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true}
 }else{
  $policy=Invoke-StartPinsLegacyPolicy -AssetRoot $AssetRoot -ApplyPolicy:($ApplyPolicy -and -not $VerifyOnly) -NonInteractive:$NonInteractive -Confirm {
   Write-Host '舊版 Windows 的開始選單政策套用於整臺電腦，每次登入會重新清空釘選。Windows 可能要求重新登入或重新啟動。' -ForegroundColor Yellow
   Read-Host '請確認其他設定與更新都已完成；現在套用請輸入 YES，其餘輸入保留待處理'
  }
 }
 $result=Get-StartPinsExportState -ExportPath (Join-Path $OutputRoot ('StartMenu-Actual-'+[guid]::NewGuid().ToString('N')+'.json')) -PolicyState $policy
 $result.PolicyRoute=$route
 return $result
}

function Complete-StartPinsPending {
 param($Result,[string[]]$StageErrors=@(),[int]$ProblemCount=0,[switch]$NonInteractive,[scriptblock]$Apply)
 if($null -eq $Result -or $Result.Status -ne 'LegacyPendingApply' -or $StageErrors.Count -gt 0 -or $ProblemCount -gt 0 -or $NonInteractive){return $Result}
 if($null -eq $Apply){throw '開始選單後置套用入口缺失。'}
 return (& $Apply -ApplyPolicy)
}
