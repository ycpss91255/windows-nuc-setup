#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$library=Join-Path $root 'modules/drivers/driver_plan_library.ps1'
if(Test-Path $library){. $library}
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Get-SetupDriverTargetPlan -ErrorAction SilentlyContinue)) '具名驅動計畫函式可安全載入而不安裝'
$t=[pscustomobject]@{InfPath='net.inf';HardwareIds=@('USB\VID_8087&PID_0A2B');Provider='Intel Corporation';ProviderAliases=@('Intel');DriverVersion='22.200.0.2';MinimumBuild=22000;Architecture='amd64'}
$d=[pscustomobject]@{InstanceId='USB\fixture';HardwareIds=@('USB\VID_8087&PID_0A2B');DriverProvider='Intel Corporation';DriverVersion='21.90.0.4';Status='OK'}
function Plan {param($Devices=@($d),$Build=22621) @(Get-SetupDriverTargetPlan -Target $t -Devices $Devices -Build $Build -Architecture amd64)}
Assert ((Plan)[0].Status -eq 'UpdateRequired') '精確USB硬體ID且同供應商舊版需要更新'
$d.HardwareIds=@('USB\VID_8087&PID_0A2B0');Assert ((Plan)[0].Status -eq 'Absent') '不得substring匹配不同PID'
$d.HardwareIds=@('USB\VID_8087&PID_0A2B');$d.DriverVersion='23.0.0.1';Assert ((Plan)[0].Status -eq 'NewerInstalled') '已裝更新版本不降版'
$d.DriverVersion='22.200.0.2';Assert ((Plan)[0].Status -eq 'Current') '相同供應商版本列目前已達目標'
$d.DriverProvider='Unknown Vendor';Assert ((Plan)[0].Status -eq 'Unverified') '不同未知供應商不可直接比較版本或覆寫'
$d.DriverProvider='Microsoft';Assert ((Plan)[0].Status -eq 'UpdateRequired') '已匹配原廠目標可替代Windows通用驅動'
Assert ((Plan -Build 19045)[0].Status -eq 'NotApplicable') '最低OS版本不符不安裝'
Assert ((Plan -Devices @())[0].Status -eq 'Absent') '未枚舉裝置不強裝'
$d.DriverProvider='Intel';$d.DriverVersion='invalid';Assert ((Plan)[0].Status -eq 'Unverified') '讀不到可信版本不盲裝'
$d.DriverVersion='21.90.0.4';$p=(Plan)[0]
$r=Get-SetupDriverReadback -Plan $p -Devices @($d)
Assert ($r.Status -eq 'Unverified') 'PnP成功退出但版本未改不得報Updated'
$d.DriverVersion='22.200.0.2';$r=Get-SetupDriverReadback -Plan $p -Devices @($d)
Assert ($r.Status -eq 'Updated') '讀回同裝置目標版本才報Updated'
$d.Status='Error';Assert ((Get-SetupDriverReadback -Plan $p -Devices @($d)).Status -eq 'Unverified') '版本吻合但裝置錯誤不得報更新完成'
Write-Host 'ALL PASS: 13 driver plan assertions; no host changes.'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_integrity_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
[IO.File]::WriteAllText((Join-Path $fixture 'driver.inf'),'fixture INF');[IO.File]::WriteAllText((Join-Path $fixture 'driver.cat'),'fixture CAT')
$t=[pscustomobject]@{InfPath='driver.inf';CatalogPath='driver.cat';InfSHA256=(Get-FileHash (Join-Path $fixture 'driver.inf')).Hash;CatalogSHA256=(Get-FileHash (Join-Path $fixture 'driver.cat')).Hash}
function Get-AuthenticodeSignature {[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation'}}}
$integrity=$false;try{$integrity=Assert-SetupDriverTargetIntegrity -Target $t -Root $fixture}catch{}
Assert $integrity '安裝前真正核對INF及CAT釘選hash與CAT簽章'
[IO.File]::AppendAllText((Join-Path $fixture 'driver.inf'),'tampered');$failed=$false;try{Assert-SetupDriverTargetIntegrity -Target $t -Root $fixture}catch{$failed=$true};Assert $failed '已簽CAT不能掩蓋INF遭修改'
[IO.File]::WriteAllText((Join-Path $fixture 'driver.inf'),'fixture INF');function Get-AuthenticodeSignature {[pscustomobject]@{Status='NotSigned';SignerCertificate=$null}}
$failed=$false;try{Assert-SetupDriverTargetIntegrity -Target $t -Root $fixture}catch{$failed=$true};Assert $failed 'hash相符但CAT無有效簽章拒絕'
$t.InfPath='../outside.inf';$failed=$false;try{Assert-SetupDriverTargetIntegrity -Target $t -Root $fixture}catch{$failed=$true};Assert $failed '拒絕INF越出展開根目錄'