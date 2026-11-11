#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
. (Join-Path $root 'modules/start_menu/start_menu_settings_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('policy_owners_'+[guid]::NewGuid().ToString('N'))
foreach($name in @('taskbar','start','PolicyDefinitions')){[void][IO.Directory]::CreateDirectory((Join-Path $temp $name))}
$admx=Join-Path $temp 'PolicyDefinitions/StartMenu.admx'
[IO.File]::WriteAllText($admx,'<policyDefinitions><policies><policy name="ConfigureStartPins" key="Software\Policies\Microsoft\Windows\Explorer" valueName="ConfigureStartPins"><elements><text valueName="ConfigureStartPinsJSON"/></elements></policy></policies></policyDefinitions>')
$shared='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
$script:values=@{};$script:kinds=@{};$script:creates=0;$script:writes=0;$script:destructive=0;$script:race=$false;$script:exports=0;$script:nativeStubCalls=0
$script:values[$shared]=@{UnrelatedPolicy=42;ForeignOwner='keep this value'};$script:kinds[$shared]=@{UnrelatedPolicy='DWord';ForeignOwner='String'}
$script:values[$advanced]=@{};$script:kinds[$advanced]=@{}
# Model the actual Registry provider: Force on an existing key clears all values.
function Test-Path {param($Path,$LiteralPath,$PathType,$ErrorAction) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HK*'){if($p -eq $shared -and $script:race){$script:race=$false;return $false};return $script:values.ContainsKey($p)};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-Item {param($Path,[switch]$Force,$ErrorAction) if($Path -notlike 'HK*'){throw 'No real key or directory creation allowed'};if($script:values.ContainsKey($Path)){if(-not $Force){throw 'fixture existing key creation rejected'};$script:destructive++};$script:creates++;$script:values[$Path]=@{};$script:kinds[$Path]=@{}}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) if(-not $script:values.ContainsKey($Path) -or $PropertyType -notin @('DWord','String')){throw 'unexpected typed registry write'};$script:values[$Path][$Name]=$Value;$script:kinds[$Path][$Name]=$PropertyType;$script:writes++}
function Get-ItemProperty {param($Path,$LiteralPath,$ErrorAction) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -eq 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'){return [pscustomobject]@{CurrentBuildNumber=26200;UBR=1}};if($script:values.ContainsKey($p)){return [pscustomobject]$script:values[$p]};return [pscustomobject]@{}}
function Remove-ItemProperty {param($Path,$Name,$ErrorAction) if($Path -cne $shared -or $Name -notin @('StartLayoutFile','LockedStartLayout')){throw 'owner attempted unrelated cleanup'};$script:values[$Path].Remove($Name);$script:kinds[$Path].Remove($Name);$script:writes++}
function Set-Content {param($LiteralPath,$Value,$Encoding,$ErrorAction) if(-not $LiteralPath.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside TEMP content write'};Microsoft.PowerShell.Management\Set-Content @PSBoundParameters}
function Export-StartLayout {param($Path,$ErrorAction) if(-not $Path.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside TEMP export'};$script:exports++;[IO.File]::WriteAllText($Path,'{"pinnedList":[]}')}
function Invoke-SetupTaskbarNativeAutoHide {param($ModuleRoot,[bool]$Apply) $script:nativeStubCalls++;return [uint32]1}
function Export-SetupTaskbarBackup {param($Path) if(-not $Path.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside TEMP backup'}}
function Add-Type {throw 'Native AppBar compilation must stay isolated'}
function Start-Sleep {param($Seconds) if($Seconds -ne 45){throw 'unexpected delay'}}
$oldWindows=$env:WINDIR
try{
 $env:WINDIR=$temp
 $layout=Join-Path $temp 'taskbar/TaskbarLayout.xml';$output=Join-Path $temp 'start'
 $taskbar=Invoke-SetupTaskbarSettings -OutputRoot (Join-Path $temp 'taskbar') -LayoutPath $layout
 Assert ($taskbar.Success -and $script:values[$shared].StartLayoutFile -ceq $layout -and $script:values[$shared].LockedStartLayout -eq 1) '真stage10工作列先成功寫入其owner的暫時政策'
 $start=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $output
 Assert ($start.Success -and $script:values[$shared].StartLayoutFile -ceq $layout -and $script:values[$shared].LockedStartLayout -eq 1 -and $script:values[$shared].UnrelatedPolicy -eq 42 -and $script:values[$shared].ForeignOwner -ceq 'keep this value' -and $script:values[$shared].HideRecommendedSection -eq 1) '真stage11預設GPO保留工作列與其他owner及剛寫的推薦政策'
 Assert ($script:kinds[$shared].UnrelatedPolicy -ceq 'DWord' -and $script:kinds[$shared].ForeignOwner -ceq 'String' -and $script:kinds[$shared].ConfigureStartPins -ceq 'DWord' -and $script:kinds[$shared].ConfigureStartPinsJSON -ceq 'String') '保留既有值型別且只寫正確Start政策型別'
 $before=$script:writes
 $readonly=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $output -VerifyOnly
 Assert ($readonly.Success -and $script:writes -eq $before) 'Start唯讀驗證不改任何owner政策'
 $script:lateCalls=0
 $pending=[pscustomobject]@{Status='LegacyPendingApply';Success=$false}
 $late=Complete-StartPinsPending -Result $pending -Apply {param([switch]$ApplyPolicy) $script:lateCalls++;Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $output -ApplyPolicy:$ApplyPolicy}
 Assert ($late.Success -and $script:lateCalls -eq 1 -and $script:values[$shared].StartLayoutFile -ceq $layout -and $script:values[$shared].LockedStartLayout -eq 1 -and $script:values[$shared].HideRecommendedSection -eq 1 -and $script:values[$shared].UnrelatedPolicy -eq 42) '真CompletePending後置重入GPO也保留所有stage owner值'
 $again=Complete-StartPinsPending -Result $late -Apply {throw 'confirmed result must not reapply'}
 Assert ($again.Success -and $script:lateCalls -eq 1) '已確認的完成結果不再次套用'
 $startJson=$script:values[$shared].ConfigureStartPinsJSON
 $final=Invoke-SetupTaskbarFinalize -LayoutPath $layout
 Assert ($final.Success -and -not $script:values[$shared].ContainsKey('StartLayoutFile') -and -not $script:values[$shared].ContainsKey('LockedStartLayout') -and $script:values[$shared].ConfigureStartPins -eq 1 -and $script:values[$shared].ConfigureStartPinsJSON -ceq $startJson -and $script:values[$shared].HideRecommendedSection -eq 1 -and $script:values[$shared].UnrelatedPolicy -eq 42) '真Taskbar owner收尾僅移除自己的兩值不刪Start及其他owner'
 $taskbarCheck=Invoke-SetupTaskbarSettings -OutputRoot (Join-Path $temp 'taskbar') -LayoutPath $layout -VerifyOnly
 Assert $taskbarCheck.Success '收尾後工作列唯讀驗收仍成功且沒有被Start破壞'
 $start=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $output
 Assert ($start.Success -and -not $script:values[$shared].ContainsKey('StartLayoutFile') -and $script:values[$shared].UnrelatedPolicy -eq 42) 'Start重跑不復活已清除的Taskbar暫時值且不刪外部值'
 $script:values.Remove($shared);$script:kinds.Remove($shared);$before=$script:creates
 $created=Invoke-StartPinsConfiguration -AssetRoot (Join-Path $root 'modules/start_menu/assets') -OutputRoot $output -AdmxPath $admx
 Assert ($created.Success -and $script:creates -eq $before+1 -and $script:values[$shared].ConfigureStartPins -eq 1) '缺少共享key時真GPO仍建立一次並完成'
 $script:values[$shared].ForeignOwner='race owner';$before=$script:values[$shared]|ConvertTo-Json -Compress;$script:race=$true;$failed=$false
 try{Invoke-StartPinsConfiguration -AssetRoot (Join-Path $root 'modules/start_menu/assets') -OutputRoot $output -AdmxPath $admx|Out-Null}catch{$failed=$true}
 Assert ($failed -and ($script:values[$shared]|ConvertTo-Json -Compress) -ceq $before) 'key建立競態明確失敗且不Force清空另一owner值'
 Assert ($script:destructive -eq 0 -and $script:nativeStubCalls -eq 2) '完整生命周期未清空任何既存key且所有AppBar呼叫皆經隔離邊界'
}finally{$env:WINDIR=$oldWindows}