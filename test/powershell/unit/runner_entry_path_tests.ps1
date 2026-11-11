#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
. (Join-Path $root 'test/powershell/support/runner_fixture.ps1')
$parent=(Get-Item -LiteralPath $env:TEMP -Force).FullName
$name='runner_native_'+[guid]::NewGuid().ToString('N')
$owned=Join-Path $parent $name
$null=New-Item -ItemType Directory -Path $owned
$previous=@{PATH=$env:PATH;GITHUB_ACTIONS=$env:GITHUB_ACTIONS;RUNNER_ENVIRONMENT=$env:RUNNER_ENVIRONMENT;RUNNER_OS=$env:RUNNER_OS}
try {
 $first=Join-Path $owned 'first';$second=Join-Path $owned 'second'
 $null=New-Item -ItemType Directory -Path $first,$second
 $binary=Join-Path $first 'docker.exe'
 Add-Type -OutputAssembly $binary -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
public class OwnedPathProbe {
 public static int Main(string[] args) {
  string folder=Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
  File.AppendAllText(Path.Combine(folder,"calls"),"called\n");
  string mode=File.ReadAllText(Path.Combine(folder,"mode"));
  if(mode=="fail")return 17;
  Console.Write("{\"OSType\":\""+mode+"\"}");return 0;
 }
}
'@
 Copy-Item -LiteralPath $binary -Destination (Join-Path $second 'docker.exe')
 # Keep this child's PATH entirely owned except the inherited tail. Both
 # matching executables are ours; no real daemon or service can be reached.
 $env:PATH=$first+';'+$second+';'+$previous.PATH
 $env:GITHUB_ACTIONS='';$env:RUNNER_ENVIRONMENT='';$env:RUNNER_OS=''
 $matches=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)
 Assert ($matches.Count -ge 2 -and $matches[0].Source -ceq $binary -and $matches[1].Source -ceq (Join-Path $second 'docker.exe')) 'PATH 前兩份同名 native 程式均為 owned fixture'
 foreach($scenario in @(@{First='windows';Second='linux';Success=$true},@{First='linux';Second='windows';Success=$false},@{First='fail';Second='windows';Success=$false})){
  [IO.File]::WriteAllText((Join-Path $first 'mode'),$scenario.First)
  [IO.File]::WriteAllText((Join-Path $second 'mode'),$scenario.Second)
  [IO.File]::WriteAllText((Join-Path $first 'calls'),'')
  [IO.File]::WriteAllText((Join-Path $second 'calls'),'')
  $entry=Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'script/docker/runner_daemon.ps1')) -TimeoutMilliseconds 10000
  Assert (($entry.ExitCode -eq 0) -eq $scenario.Success) ('入口只依 PATH 第一份 native 結果決定成敗：'+$scenario.First)
  Assert ([IO.File]::ReadAllLines((Join-Path $first 'calls')).Count -eq 1) 'PATH 第一份 native 精確執行一次'
  Assert ([IO.File]::ReadAllLines((Join-Path $second 'calls')).Count -eq 0) '第一份失敗也不改用後方 native'
 }
} finally {
 $env:PATH=$previous.PATH;$env:GITHUB_ACTIONS=$previous.GITHUB_ACTIONS;$env:RUNNER_ENVIRONMENT=$previous.RUNNER_ENVIRONMENT;$env:RUNNER_OS=$previous.RUNNER_OS
 $checked=Assert-RunnerOwnedDirectory -Path $owned -Parent $parent -Name $name
 Remove-Item -LiteralPath $checked -Recurse -Force
}
