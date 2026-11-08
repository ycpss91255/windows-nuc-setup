#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$support=Join-Path $root 'test/powershell/support/runner_fixture.ps1'
Assert (Test-Path -LiteralPath $support) 'owned fixture 清理具有可執行的完整路徑與程序身份防護'
. $support
$parent=(Get-Item -LiteralPath $env:TEMP -Force).FullName
$name='runner_native_'+[guid]::NewGuid().ToString('N')
$owned=Join-Path $parent $name
$null=New-Item -ItemType Directory -Path $owned
try {
 Assert ((Assert-RunnerOwnedDirectory -Path $owned -Parent $parent -Name $name) -ceq $owned) '精確 owned 唯一 GUID 目錄通過'
 foreach($case in @(@{Path=$parent;Parent=$parent;Name=$name},@{Path=$owned;Parent=(Split-Path $parent -Parent);Name=$name},@{Path=$owned;Parent=$parent;Name='runner_native_wrong'})){
  $rejected=$false;try{Assert-RunnerOwnedDirectory @case|Out-Null}catch{$rejected=$true}
  Assert $rejected '錯路徑／父目錄／名稱一律拒絕遞迴刪除'
 }
 $link=Join-Path $owned ('runner_native_'+[guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Junction -Path $link -Target $parent
 try {
  $rejected=$false;try{Assert-RunnerOwnedDirectory -Path $link -Parent $owned -Name (Split-Path $link -Leaf)|Out-Null}catch{$rejected=$true}
  Assert $rejected '真 owned junction 拒絕刪除並保護外部目錄'
  $rejected=$false;try{Assert-RunnerOwnedDirectory -Path $owned -Parent $parent -Name $name|Out-Null}catch{$rejected=$true}
  Assert $rejected 'owned 目錄包含子 junction 時拒絕整個遞迴刪除'
 }finally{[IO.Directory]::Delete($link)}
 $self=[Diagnostics.Process]::GetCurrentProcess();$ticks=$self.StartTime.ToUniversalTime().Ticks
 Assert (Test-RunnerProcessIdentity -Process $self -Identifier $PID -StartTicks $ticks) '真程序 handle 與 PID／StartTime 相符'
 Assert (-not(Test-RunnerProcessIdentity -Process $self -Identifier $PID -StartTicks ($ticks+1))) 'PID 相同但 StartTime 不同拒絕身份'
 Assert (-not(Test-RunnerProcessIdentity -Process $self -Identifier ($PID+1) -StartTicks $ticks)) 'PID 不同拒絕身份'
}finally{
 $checked=Assert-RunnerOwnedDirectory -Path $owned -Parent $parent -Name $name
 Remove-Item -LiteralPath $checked -Recurse -Force
}
