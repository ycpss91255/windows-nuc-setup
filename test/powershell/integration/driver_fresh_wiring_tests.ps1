#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/verification_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupDriverFreshVerification -ErrorAction SilentlyContinue)) '最終驗收具有綁本輪同機SID的freshdriver讀回路由'
$fixture=Join-Path $env:TEMP ('driver_fresh_wiring_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$library=Join-Path $fixture 'driver_installation_library.ps1'
@'
function Invoke-SetupDriverVerification {param($DriverRoot,$VerificationRunId)
 $result=[pscustomobject]@{Success=($global:DriverFreshMode -ne 'failed');VerificationRunId=$VerificationRunId;Computer=[Environment]::MachineName;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Targets=@([pscustomobject]@{Status='Current'});Root=$DriverRoot}
 switch($global:DriverFreshMode){stale{$result.VerificationRunId=[guid]::NewGuid().ToString()} computer{$result.Computer='another-computer'} user{$result.UserSID='S-1-0-0'} boolean{$result.Success='true'} }
 return $result
}
'@|Set-Content -LiteralPath $library -Encoding UTF8
function Resolve-NucPath {param($Name) if($Name -ne 'driver_installation_library.ps1'){throw 'unexpected resolver'};$library}
$run=[guid]::NewGuid().ToString();$global:DriverFreshMode='pass'
$r=Invoke-SetupDriverFreshVerification -DriverPackagePath $fixture -VerificationRunId $run
Assert ($r.Success -and $r.Root -ceq $fixture) '真fresh路由傳動態已選包與本輪識別'
foreach($mode in @('stale','computer','user','boolean')){$global:DriverFreshMode=$mode;$rejected=$false;try{Invoke-SetupDriverFreshVerification -DriverPackagePath $fixture -VerificationRunId $run}catch{$rejected=$_.Exception.Message -match '本輪'};Assert $rejected ('拒絕不可信driver結果 '+$mode)}
$global:DriverFreshMode='failed';$r=Invoke-SetupDriverFreshVerification -DriverPackagePath $fixture -VerificationRunId $run
Assert (-not $r.Success) '真失敗結果保留，不能被綁定檢查改為成功'
Remove-Variable DriverFreshMode -Scope Global
