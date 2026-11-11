#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_cleanup_scope_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$runner=Join-Path $fixture 'runner.ps1';$log=Join-Path $fixture 'private.log'
$source=@'
param([string]$SourceRoot,[string]$FixtureRoot)
$ErrorActionPreference='Stop'
# Import only the public driver library, as a fresh native process would.
. (Join-Path $SourceRoot 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$parent=Join-Path ([IO.Path]::GetFullPath($FixtureRoot)) 'cache';[void][IO.Directory]::CreateDirectory($parent);$parent=[IO.Path]::GetFullPath($parent)
function Get-SetupDriverCacheParent {$parent}
$script:SetupDriverExtractionLeases=@{};$script:denyAcl=$false;$script:aclReads=0;$script:deletes=0
function Get-Acl {
 param($LiteralPath,$ErrorAction)
 $script:aclReads++
 $directory=(Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force).PSIsContainer
 $acl=if($directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
 $acl.SetAccessRuleProtection($true,$false)
 $owner=if($script:denyAcl){'S-1-5-32-545'}else{'S-1-5-32-544'}
 $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($owner))
 foreach($id in @('S-1-5-18','S-1-5-32-544')){$flags=if($directory){'ContainerInherit,ObjectInherit'}else{'None'};$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl',$flags,'None','Allow'))}
 return $acl
}
function Remove-Item {
 param($LiteralPath,[switch]$Recurse,[switch]$Force,$ErrorAction)
 if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LiteralPath)) -cne $parent -or -not $script:SetupDriverExtractionLeases.ContainsKey($LiteralPath)){throw 'fixture forbids deletion outside owned lease'}
 $script:deletes++;Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
function NewOwned {
 $path=Join-Path $parent ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($path)
 [IO.File]::WriteAllText((Join-Path $path 'payload.sys'),'inert owned fixture')
 $script:SetupDriverExtractionLeases[$path]=[pscustomobject]@{NativeActive=$false;Token=[guid]::NewGuid().ToString('N')}
 return $path
}
$one=NewOwned;$two=NewOwned
$script:SetupDriverExtractionLeases[$one].NativeActive=$true
Assert (-not(Remove-SetupDriverExtractionRoot $one) -and (Test-Path $one) -and $script:deletes -eq 0) '乾淨PS5原生尚未完成仍保留payload且不刪目錄'
$script:SetupDriverExtractionLeases[$one].NativeActive=$false
$errorRecord=$null;$removed=$false;try{$removed=Remove-SetupDriverExtractionRoot $one}catch{$errorRecord=$_;Write-Host ('PRIVATE_FAILURE_TYPE='+$_.Exception.GetType().Name);Write-Host $_.Exception.Message}
Assert ($null -eq $errorRecord -and $removed -and -not(Test-Path $one) -and (Test-Path $two) -and $script:aclReads -gt 0) '只匯入driver library的乾淨PS5清理應能執行真祖先及ACL驗證後刪本輪lease'
$script:denyAcl=$true;$rejected=$false;try{Remove-SetupDriverExtractionRoot $two|Out-Null}catch{$rejected=$_.Exception.Message.Contains('擁有者')};$script:denyAcl=$false
Assert ($rejected -and (Test-Path $two) -and $script:deletes -eq 1) '載入依賴後仍拒絕不可信祖先ACL而不刪payload'
$outside=Join-Path ([IO.Path]::GetFullPath($FixtureRoot)) 'outside';[void][IO.Directory]::CreateDirectory($outside)
$link=Join-Path $two 'junction';$null=New-Item -ItemType Junction -Path $link -Target $outside
$rejected=$false;try{Remove-SetupDriverExtractionRoot $two|Out-Null}catch{$rejected=$_.Exception.Message.Contains('重新解析點')}
Assert ($rejected -and (Test-Path $outside) -and (Test-Path $two) -and $script:deletes -eq 1) '真junction仍拒絕且不碰外部目標'
Microsoft.PowerShell.Management\Remove-Item -LiteralPath $link -Force
Assert ((Remove-SetupDriverExtractionRoot $two) -and (Test-Path $outside) -and $script:deletes -eq 2) '解除junction後真清理完成且不刪兄弟資料'
Assert (-not(Remove-SetupDriverExtractionRoot $outside) -and (Test-Path $outside)) '無lease外部路徑仍拒絕'
'@
[IO.File]::WriteAllText($runner,$source,[Text.UTF8Encoding]::new($true))
$prior=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -SourceRoot $root -FixtureRoot $fixture *> $log;$native=$LASTEXITCODE}
finally{$ErrorActionPreference=$prior}
# Only structured, fixed assertion names leave the private child log.
foreach($line in Get-Content -LiteralPath $log){if($line -match '^@@ASSERT@@\{'){Write-Host $line}}
if($native -ne 0){throw ('Clean driver cleanup scope child failed; native exit '+$native)}
