#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SuitePath,[Parameter(Mandatory=$true)][string]$SourceRoot)
Describe 'unchanged standalone suite under original-file coverage' {
 It 'runs one safe suite in this worker process' {
  $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
  $suite=[IO.Path]::GetFullPath($SuitePath)
  if(-not $suite.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'suite必須位於來源根目錄內。'}
  $relative=$suite.Substring($source.Length+1).Replace('\','/')
  if($relative -notmatch '^test/powershell/(unit|integration)/[a-z0-9_]+_tests\.ps1$'){throw '僅允許獨立安全 suite。'}
  Push-Location -LiteralPath $SourceRoot
  try{
  if($relative -eq 'test/powershell/integration/layout_tests.ps1'){
   & $SuitePath -PackageRoot $SourceRoot -SourceOnly
  }else{& $SuitePath}
  }finally{Pop-Location}
 }
}
