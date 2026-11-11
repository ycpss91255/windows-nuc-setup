#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/test/managed_catalog.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('catalog_guard_'+[guid]::NewGuid().ToString('N'))
Assert ((Get-ManagedCatalogRelativePath -Root $temp -Path (Join-Path $temp 'native/a.cs')) -ceq 'native/a.cs') 'catalog source paths normalize relative to dynamic root'
$rejected=$false;try{Get-ManagedCatalogRelativePath -Root $temp -Path ($temp+'_escape/a.cs')|Out-Null}catch{$rejected=$_.Exception.Message -match 'outside the declared source root'}
Assert $rejected 'catalog prefix siblings cannot masquerade as children'
if($PSVersionTable.PSVersion.Major -lt 7 -or [Environment]::Version.Major -lt 8){
 $rejected=$false;try{Get-ManagedPortableCatalog -SourceRoot $temp -AssemblyPath 'not-read.dll' -PDBPath 'not-read.pdb'|Out-Null}catch{$rejected=$_.Exception.Message -match 'requires pwsh 7.4'}
 Assert $rejected 'CLR4 rejects maintenance reader before opening any files'
}
Write-Host ('ALL PASS: '+$script:count+' catalog environment guard assertions; no filesystem writes')