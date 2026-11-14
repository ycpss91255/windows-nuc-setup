#Requires -Version 5.1
function Get-SetupDebloatBuild {[Environment]::OSVersion.Version.Build}
function Read-SetupDebloatRegistry {
 param([string]$Path,[string]$Name)
 try{$key=Get-Item -LiteralPath $Path -ErrorAction Stop;[pscustomobject]@{Value=$key.GetValue($Name);Kind=[string]$key.GetValueKind($Name);Error=''}}
 catch{[pscustomobject]@{Value=$null;Kind='';Error=$_.Exception.Message}}
}
function Get-SetupDebloatFeaturePlan {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[int]$Build=(Get-SetupDebloatBuild))
 $profile=Get-Content -LiteralPath (Join-Path $ModuleRoot 'debloat_profile.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $catalog=(Get-Content -LiteralPath (Join-Path $ModuleRoot 'win11debloat/Config/Features.json') -Raw -Encoding UTF8|ConvertFrom-Json).Features
 if(-not @($profile.Features).Count -or @($profile.Features|Select-Object -Unique).Count -ne @($profile.Features).Count){throw '清理功能清單為空或重複。'}
 foreach($id in $profile.Features){
  $catalogMatches=@($catalog|Where-Object FeatureId -ceq $id)
  if($catalogMatches.Count -ne 1 -or $catalogMatches[0].RegistryKey -cnotmatch '^[A-Za-z0-9_]+\.reg$'){throw '清理功能缺少唯一可驗證的登錄契約。'}
  $feature=$catalogMatches[0];$checks=@();$path=''
  foreach($line in Get-Content -LiteralPath (Join-Path $ModuleRoot ('win11debloat/Regfiles/'+$feature.RegistryKey)) -Encoding Unicode){
   $text=$line.Trim()
   if(-not $text -or $text.StartsWith(';') -or $text -ceq 'Windows Registry Editor Version 5.00'){continue}
   if($text -cmatch '^\[(HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE)\\([^\]]+)\]$'){$hive=if($matches[1] -ceq 'HKEY_CURRENT_USER'){'HKCU:'}else{'HKLM:'};$path=$hive+'\'+$matches[2];continue}
   if($path -and $text -cmatch '^"([^"\\]+)"=dword:([A-Fa-f0-9]{8})$'){$checks+=[pscustomobject]@{Path=$path;Name=$matches[1];Expected=[Convert]::ToUInt32($matches[2],16)};continue}
   throw '清理功能包含尚未支援的讀回契約，拒絕假成功。'
  }
  if(-not $checks.Count){throw '清理功能沒有登錄讀回項目。'}
  $supported=($null -eq $feature.MinVersion -or $Build -ge $feature.MinVersion) -and ($null -eq $feature.MaxVersion -or $Build -le $feature.MaxVersion)
  [pscustomobject]@{FeatureId=$id;Supported=$supported;Build=$Build;MinimumBuild=$feature.MinVersion;MaximumBuild=$feature.MaxVersion;Checks=$checks}
 }
}
function Test-SetupDebloatFeatures {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[int]$Build=(Get-SetupDebloatBuild))
 $features=@(foreach($feature in Get-SetupDebloatFeaturePlan -ModuleRoot $ModuleRoot -Build $Build){
  $checks=@()
  if($feature.Supported){foreach($policy in $feature.Checks){
   $actual=Read-SetupDebloatRegistry -Path $policy.Path -Name $policy.Name
   $numeric=$actual.Value -is [int] -or $actual.Value -is [uint32]
   $checks+=[pscustomobject]@{Path=$policy.Path;Name=$policy.Name;Expected=$policy.Expected;Actual=$actual.Value;Kind=$actual.Kind;Passed=($numeric -and $actual.Kind -ceq 'DWord' -and $actual.Value -eq $policy.Expected);ReadError=$actual.Error}
  }}
  $status=if(-not $feature.Supported){'Skipped'}elseif(@($checks|Where-Object {-not $_.Passed}).Count){'Failed'}else{'Passed'}
  [pscustomobject]@{FeatureId=$feature.FeatureId;Status=$status;Build=$feature.Build;MinimumBuild=$feature.MinimumBuild;MaximumBuild=$feature.MaximumBuild;Reason=$(if(-not $feature.Supported){'目前 Windows build 不在上游功能適用範圍，未宣稱套用。'}else{''});Checks=$checks}
 })
 [pscustomobject]@{Success=(@($features|Where-Object Status -eq Failed).Count -eq 0);Features=$features;Scope='僅核對所選功能的登錄型別及值；不代表應用程式已移除、所有資料傳輸停止或未適用功能已套用。'}
}
function Invoke-SetupDebloatNative {
 param([string[]]$Arguments)
 & powershell.exe @Arguments|Out-Host
 return $LASTEXITCODE
}
function Invoke-SetupDebloatOneDrive {param([string]$ModuleRoot) & (Join-Path $ModuleRoot 'remove_one_drive.ps1')}
function Invoke-SetupDebloat {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[switch]$VerifyOnly,[string]$VerificationRunId,[string]$ReportPath=(Join-Path $env:ProgramData 'NUC8-Setup/Debloat-Result.json'))
 $ErrorActionPreference='Stop'
 $apps=@(Get-Content -LiteralPath (Join-Path $ModuleRoot 'debloat_apps.txt')|Where-Object {$_ -and -not $_.StartsWith('#')})
 $profile=Get-Content -LiteralPath (Join-Path $ModuleRoot 'debloat_profile.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $before=@();$code=$null;$log=''
 if(-not $VerifyOnly){
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $ReportPath))
  # Validate every selected feature before any cleanup, including unsupported grammar.
  $null=@(Get-SetupDebloatFeaturePlan -ModuleRoot $ModuleRoot)
  Invoke-SetupDebloatOneDrive -ModuleRoot $ModuleRoot
  $before=@(Get-AppxPackage -AllUsers|Where-Object {@($_.PackageUserInformation|Where-Object InstallState -eq 'Installed').Count -gt 0}|Select-Object -ExpandProperty Name -Unique)
  $log=Join-Path (Split-Path -Parent $ReportPath) ('Debloat-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ModuleRoot 'win11debloat/Win11Debloat.ps1'),'-CLI','-Silent','-SkipExplorerRestart','-Language','zh-TW','-LogPath',$log,'-AppRemovalTarget','AllUsers','-RemoveApps','-Apps',($apps -join ','))
  foreach($feature in $profile.Features){$arguments+=('-'+$feature)}
  Write-Host ('正在執行 Win11Debloat，已選取 '+$apps.Count+' 個 App 項目及 '+$profile.Features.Count+' 項清理設定。') -ForegroundColor Cyan
  $code=Invoke-SetupDebloatNative -Arguments $arguments
 }
 $after=@(Get-AppxPackage -AllUsers|Where-Object {@($_.PackageUserInformation|Where-Object InstallState -eq 'Installed').Count -gt 0}|Select-Object -ExpandProperty Name -Unique)
 $remaining=@($after|Where-Object {$_ -in $apps})
 $provisioned=@(Get-AppxProvisionedPackage -Online|Where-Object DisplayName -in $apps|Select-Object -ExpandProperty DisplayName)
 $features=Test-SetupDebloatFeatures -ModuleRoot $ModuleRoot
 $success=($VerifyOnly -or ($code -is [int] -and $code -eq 0)) -and -not $remaining.Count -and -not $provisioned.Count -and $features.Success
 $result=[ordered]@{Success=[bool]$success;VerificationRunId=$VerificationRunId;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Computer=$env:COMPUTERNAME;CheckedAt=(Get-Date).ToString('o');VerifyOnly=[bool]$VerifyOnly;ProvisionedRemaining=$provisioned;BeforeAppCount=$before.Count;AfterAppCount=$after.Count;RemovedApps=@($before|Where-Object {$_ -notin $after});SelectedRemaining=$remaining;ExitCode=$code;Log=$log;FeatureChecks=$features.Features;FeatureScope=$features.Scope}
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $ReportPath))
 $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
 Write-Host ('本次實際移除：'+($result.RemovedApps -join ', '))
 Write-Host ('清單中仍存在：'+($remaining -join ', '))
 foreach($feature in $features.Features){Write-Host ('功能讀回 '+$feature.FeatureId+'：'+$feature.Status)}
 if(-not $success){throw '清理或所選功能登錄讀回未成功，請查看 Debloat-Result.json。'}
 [pscustomobject]$result
}
