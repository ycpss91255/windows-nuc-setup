#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/debloat/debloat_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('debloat_log_'+[guid]::NewGuid().ToString('N'))
$module=Join-Path $fixture 'readonly_module';$report=Join-Path $fixture 'machine/NUC8-Setup/Debloat-Result.json'
[void][IO.Directory]::CreateDirectory($module)
[IO.File]::WriteAllText((Join-Path $module 'debloat_apps.txt'),'Fixture.App')
[IO.File]::WriteAllText((Join-Path $module 'debloat_profile.json'),'{"Features":["Fixture"]}')
$originalAcl=Get-Acl -LiteralPath $module
try {
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl=Get-Acl -LiteralPath $module
 $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,([Security.AccessControl.FileSystemRights]::CreateFiles -bor [Security.AccessControl.FileSystemRights]::CreateDirectories),[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Deny)
 [void]$acl.AddAccessRule($rule);Set-Acl -LiteralPath $module -AclObject $acl
 $blocked=$false;try{[IO.File]::WriteAllText((Join-Path $module 'must_not_write.txt'),'x')}catch [UnauthorizedAccessException]{$blocked=$true}
 Assert $blocked '唯讀模組 fixture 真正拒絕建立檔案'
 $before=@(Get-ChildItem -LiteralPath $module -Recurse -Force|ForEach-Object FullName)
 function Get-SetupDebloatFeaturePlan {param($ModuleRoot) @()}
 function Test-SetupDebloatFeatures {param($ModuleRoot) [pscustomobject]@{Success=$true;Features=@();Scope='fixture'}}
 $script:oneDriveCalls=0
 function Invoke-SetupDebloatOneDrive {param($ModuleRoot) $script:oneDriveCalls++}
 function Get-AppxPackage {param([switch]$AllUsers)}
 function Get-AppxProvisionedPackage {param([switch]$Online)}
 $script:code=0;$script:logPath='';$script:nativeCalls=0
 $upstream=[IO.File]::ReadAllText((Join-Path $root 'modules/debloat/win11debloat/Win11Debloat.ps1'))
 $match=[regex]::Match($upstream,'(?s)# Log script output to .+?(?=\r?\n# When Group Policy)')
 if(-not $match.Success){throw 'upstream transcript contract missing'}
 $transcript=[scriptblock]::Create($match.Value)
 function Start-Transcript {param($Path,[switch]$Append,[switch]$IncludeInvocationHeader,[switch]$Force) $script:logPath=$Path;[IO.File]::WriteAllText($Path,'safe transcript fixture')}
 function Invoke-SetupDebloatNative {param($Arguments)
  $script:nativeCalls++;$index=[array]::IndexOf($Arguments,'-LogPath');if($index -lt 0){throw 'missing LogPath'}
  $LogPath=$Arguments[$index+1]
  $script:DefaultLogPath=Join-Path $ModuleRoot 'unexpected.log'
  & $transcript
  return $script:code
 }
 $result=Invoke-SetupDebloat -ModuleRoot $module -ReportPath $report
 $saved=Get-Content -LiteralPath $report -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($result.Success -and $result.Log -ceq $script:logPath -and $saved.Log -ceq $script:logPath -and ((Split-Path -Parent (Split-Path -Parent $script:logPath)) -ceq (Split-Path -Parent $report)) -and ([IO.Path]::GetFileName($script:logPath) -ceq 'Win11Debloat.log') -and (Test-Path -LiteralPath $script:logPath -PathType Leaf)) '成功結果與 JSON 指向每機記錄路徑'
 $script:code=7;$failed=$false;try{Invoke-SetupDebloat -ModuleRoot $module -ReportPath $report|Out-Null}catch{$failed=$true}
 $saved=Get-Content -LiteralPath $report -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($failed -and -not $saved.Success -and $saved.ExitCode -eq 7 -and $saved.Log -ceq $script:logPath) '原生失敗仍傳播並保留記錄路徑'
 $calls=$script:nativeCalls;$verify=Invoke-SetupDebloat -ModuleRoot $module -ReportPath $report -VerifyOnly
 Assert ($verify.Success -and $verify.Log -ceq '' -and $script:nativeCalls -eq $calls) 'VerifyOnly 不執行原生程序且記錄路徑為空'
 $badParent=Join-Path $fixture 'not_a_directory';[IO.File]::WriteAllText($badParent,'fixture')
 $calls=$script:nativeCalls;$oneDrive=$script:oneDriveCalls;$failed=$false
 try{Invoke-SetupDebloat -ModuleRoot $module -ReportPath (Join-Path $badParent 'result.json')|Out-Null}catch{$failed=$true}
 Assert ($failed -and $script:nativeCalls -eq $calls -and $script:oneDriveCalls -eq $oneDrive) '無法建立記錄目錄時先停止且不執行清理'
 $after=@(Get-ChildItem -LiteralPath $module -Recurse -Force|ForEach-Object FullName)
 Assert (($before -join "`n") -ceq ($after -join "`n")) '模組目錄沒有新增任何檔案'
} finally {
 Set-Acl -LiteralPath $module -AclObject $originalAcl
 Remove-Item -LiteralPath $fixture -Recurse -Force
}