#Requires -Version 5.1
# Fixed Taskbar protocol only. Loading definitions never registers tasks or changes settings.
function Get-SetupTaskbarFinalizeCommand {
 param([string]$RunId)
 $null=Get-SetupGuiRunPaths -CommonDataRoot ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) -Role TaskbarFinalize -RunId $RunId
 $system=[Environment]::GetFolderPath([Environment+SpecialFolder]::System)
 $powershell=Join-Path $system 'WindowsPowerShell/v1.0/powershell.exe';$scheduler=Join-Path $system 'schtasks.exe'
 return ('"'+$powershell+'" -NoProfile -WindowStyle Hidden -Command "& '''+$scheduler.Replace("'","''")+''' /Run /TN ''WindowsSetup-Gui-TaskbarFinalize-'+$RunId+'''"')
}
function Get-SetupTaskbarLayoutBinding {
 param([string]$CommonDataRoot,$Context)
 $role=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role Taskbar -RunId $Context.RunId
 $pointer=Join-Path $role.RoleRoot ('current_layout_'+$Context.UserSID+'.json');Assert-SetupGuiProtectedPath $pointer
 $record=Get-Content -LiteralPath $pointer -Raw -Encoding UTF8|ConvertFrom-Json
 if($null -eq $record -or (@($record.PSObject.Properties.Name|Sort-Object) -join '|') -cne 'ApplyRunID|Computer|UserSID' -or $record.UserSID -cne $Context.UserSID -or $record.Computer -cne $Context.Computer){throw '工作列配置指標不是原帳號與原電腦的固定資料。'}
 $apply=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role Taskbar -RunId $record.ApplyRunID
 Assert-SetupGuiProtectedPath $apply.DataRoot -Directory -UserSid $Context.UserSID
 $layout=Join-Path $apply.DataRoot 'TaskbarLayout.xml';Assert-SetupGuiProtectedPath $layout -UserSid $Context.UserSID
 $pending=Get-ScheduledTask -TaskName ('WindowsSetup-Gui-TaskbarFinalize-'+$record.ApplyRunID) -ErrorAction SilentlyContinue
 [pscustomobject]@{ApplyRunID=$record.ApplyRunID;LayoutPath=$layout;FinalizeCommand=(Get-SetupTaskbarFinalizeCommand $record.ApplyRunID);PendingFinalizeTask=($null -ne $pending)}
}
function Register-SetupTaskbarFinalize {
 param($Stage,$Scope)
 $context=Read-SetupGuiContext -CodeRoot $Stage.CodeRoot -CommonDataRoot $Stage.CommonDataRoot -Role Taskbar -RunId $Stage.Context.RunId
 if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($Stage.Context|ConvertTo-Json -Depth 8 -Compress) -or $context.VerifyOnly){throw '工作列收尾只能由原 Apply 受保護 context 建立。'}
 $layout=Join-Path $Stage.DataRoot 'TaskbarLayout.xml';Assert-SetupGuiProtectedPath $layout -UserSid $context.UserSID
 if(-not(Test-SetupTaskbarLayout $layout)){throw '工作列收尾缺少原 Apply 的精確 Edge Replace 配置。'}
 $final=New-SetupGuiStage -SourceRoot $Stage.CodeRoot -CommonDataRoot $Stage.CommonDataRoot -Role TaskbarFinalize -RunId $context.RunId -UserSid $context.UserSID -CallerSession $context.CallerSession -DesktopSession $context.DesktopSession -Computer $context.Computer
 try{
  $name='WindowsSetup-Gui-TaskbarFinalize-'+$context.RunId
  if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){throw '工作列收尾 GUID 工作已存在，拒絕接管。'}
  $worker=Join-Path $final.CodeRoot 'core/gui_worker.ps1';Assert-SetupGuiProtectedPath $worker
  $action=New-ScheduledTaskAction -Execute $Scope.PowerShell -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$worker+'" -Role TaskbarFinalize -RunId '+$context.RunId)
  $principal=New-ScheduledTaskPrincipal -UserId $context.UserSID -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -ErrorAction Stop|Out-Null
  $runOnce='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  if(-not(Test-Path $runOnce)){New-Item $runOnce -Force|Out-Null}
  New-ItemProperty $runOnce -Name NUC8FinalizeTaskbar -Value (Get-SetupTaskbarFinalizeCommand $context.RunId) -PropertyType String -Force|Out-Null
  $pointer=Join-Path (Split-Path $Stage.CodeRoot -Parent|Split-Path -Parent) ('current_layout_'+$context.UserSID+'.json')
  Write-SetupGuiAtomicJson -Path $pointer -Value ([ordered]@{UserSID=$context.UserSID;Computer=$context.Computer;ApplyRunID=$context.RunId})
 }finally{$final.Lock.Dispose()}
}
function Invoke-SetupTaskbarBoundFinalize {
 param([string]$CommonDataRoot,$Context)
 $binding=Get-SetupTaskbarLayoutBinding -CommonDataRoot $CommonDataRoot -Context $Context
 if($binding.ApplyRunID -cne $Context.ApplyRunID){return [pscustomobject]@{Success=$false;Status='Obsolete';TemporaryLayoutPolicyRemoved=$false;Error='工作列已有更新的 Apply，本工作未解除任何政策。'}}
 Invoke-SetupTaskbarFinalize -LayoutPath $binding.LayoutPath
}
function Complete-SetupTaskbarFinalizeTask {
 param([string]$RunId)
 $null=Get-SetupGuiRunPaths -CommonDataRoot ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) -Role TaskbarFinalize -RunId $RunId
 $name='WindowsSetup-Gui-TaskbarFinalize-'+$RunId
 if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop}
}
function Invoke-SetupTaskbarFinalizePending {
 $scope=Get-SetupGuiIdentity
 $context=[pscustomobject]@{RunId=([guid]::NewGuid().ToString('D'));UserSID=$scope.UserSID;Computer=$scope.Computer}
 $binding=Get-SetupTaskbarLayoutBinding -CommonDataRoot $scope.CommonDataRoot -Context $context
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $scope.CommonDataRoot -Role TaskbarFinalize -RunId $binding.ApplyRunID
 Invoke-SetupGuiWorker -CodeRoot $paths.CodeRoot -Role TaskbarFinalize -RunId $binding.ApplyRunID
}
