#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SuitePath,[Parameter(Mandatory=$true)][string]$SourceRoot)
Describe 'unchanged standalone suite under original-file coverage' {
 It 'runs one safe suite in this worker process' {
  $relative=[IO.Path]::GetFullPath($SuitePath).Substring([IO.Path]::GetFullPath($SourceRoot).TrimEnd('\').Length+1).Replace('\','/')
  if($relative -notmatch '^test/powershell/(unit|integration)/[a-z_]+_tests\.ps1$' -or $relative -match 'powershell_coverage'){throw '僅允許獨立安全 suite，禁止遞迴收集器。'}
  if($relative -eq 'test/powershell/integration/layout_tests.ps1'){
   & $SuitePath -PackageRoot $SourceRoot -SourceOnly
  }else{& $SuitePath}
 }
}
