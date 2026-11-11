#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Register-SetupDriverExtractionLease -ErrorAction SilentlyContinue) -and [bool](Get-Command Remove-SetupDriverExtractionRoot -ErrorAction SilentlyContinue)) '本輪驅動解壓有記憶體lease與安全清理入口'
$fixture=[IO.Path]::GetFullPath((Join-Path $env:TEMP ('driver_cleanup_'+[guid]::NewGuid().ToString('N'))));[void][IO.Directory]::CreateDirectory($fixture)
$fixture=[IO.Path]::GetFullPath($fixture)
$parent=Join-Path $fixture 'windows_setup_driver_cache';[void][IO.Directory]::CreateDirectory($parent)
function Get-SetupDriverCacheParent {$parent}
function Assert-SetupUpdateProtectedPath {param($Path,[switch]$Directory) if($script:denyAcl){throw 'fixture owner/acl rejected'}}
function Assert-SetupUpdatePlainPath {param($Path)}
function Assert-SetupUpdateAncestors {param($CommonDataRoot)}
function Assert-SetupUpdateAcl {param($Acl,[switch]$Directory)}
function NewStage { $p=Join-Path $parent ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($p);[IO.File]::WriteAllText((Join-Path $p 'payload.sys'),'owned');Register-SetupDriverExtractionLease -Path $p;return $p }
$one=NewStage;$two=NewStage
Assert ((Remove-SetupDriverExtractionRoot -Path $one) -and -not(Test-Path $one) -and (Test-Path $two)) '只刪本輪指定lease，不碰兄弟stage'
function Get-SetupDriverPnpTool {'Invoke-CacheNativeDouble'}
function Invoke-CacheNativeDouble {
 $script:busyDuringNative=$lease.NativeActive
 $script:cleanupDuringNative=Remove-SetupDriverExtractionRoot -Path $two
 if($script:abortNative){throw 'native completion unknown'}
 $global:LASTEXITCODE=0
}
$native=Invoke-SetupDriverInfInstall -InfPath (Join-Path $two 'payload.sys') -LogPath (Join-Path $fixture 'native.log')
Assert ($script:busyDuringNative -and -not $script:cleanupDuringNative -and -not $script:SetupDriverExtractionLeases[$two].NativeActive -and $native.ExitCode -eq 0) '真同步原生邊界完成後才釋放Busy，期間不能清理'
$script:abortNative=$true;$threw=$false;try{Invoke-SetupDriverInfInstall -InfPath (Join-Path $two 'payload.sys') -LogPath (Join-Path $fixture 'native.log')}catch{$threw=$true}
$busyAfter=$script:SetupDriverExtractionLeases[$two].NativeActive
$cleanupAfter=$null;if($threw -and $busyAfter){$cleanupAfter=Remove-SetupDriverExtractionRoot -Path $two}
Assert ($threw -and $busyAfter -and -not $cleanupAfter) ('原生完成狀態未知時不在finally冒充已完成並刪檔; threw='+$threw+' busy='+$busyAfter+' cleanup='+$cleanupAfter)
$script:SetupDriverExtractionLeases[$two].NativeActive=$false
$outside=Join-Path $fixture ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($outside)
Assert (-not(Remove-SetupDriverExtractionRoot -Path $outside) -and (Test-Path $outside)) '外部及未租用路徑不刪除'
$old=Join-Path $parent ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($old)
Assert (-not(Remove-SetupDriverExtractionRoot -Path $old) -and (Test-Path $old)) '既有未租用GUID目錄不當成自己的快取'
$script:denyAcl=$true;$blocked=$false;try{Remove-SetupDriverExtractionRoot -Path $two}catch{$blocked=$true};$script:denyAcl=$false
Assert ($blocked -and (Test-Path $two)) '擁有者或ACL不可信時保留而拒絕清理'
$script:SetupDriverExtractionLeases[$two].NativeActive=$true
Assert (-not(Remove-SetupDriverExtractionRoot -Path $two) -and (Test-Path $two)) '原生程序尚未明確結束不清理payload'
$script:SetupDriverExtractionLeases[$two].NativeActive=$false
$link=Join-Path $two 'linked';$null=New-Item -ItemType Junction -Path $link -Target $outside
$blocked=$false;try{Remove-SetupDriverExtractionRoot -Path $two}catch{$blocked=$true}
Assert ($blocked -and (Test-Path $outside) -and (Test-Path $two)) 'junction拒絕清理且不碰其外部目標'
Remove-Item -LiteralPath $link -Force
Assert ((Remove-SetupDriverExtractionRoot -Path $two) -and (Test-Path $outside) -and (Test-Path $old)) '移除junction後只清租用目錄，不連帶清舊資料'
