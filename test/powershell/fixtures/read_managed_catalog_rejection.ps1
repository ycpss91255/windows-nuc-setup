#Requires -Version 5.1
param([string]$ReaderPath,[string]$TestSourceRoot,[string]$TestAssemblyPath,[string]$TestPdbPath,[string]$ErrorPath)
$ErrorActionPreference='Stop'
# Names intentionally differ from the dot-sourced reader's param block.
# Capture original exception properties before the console host formats them.
. $ReaderPath
try{
 $unexpectedCatalog=Get-ManagedPortableCatalog -SourceRoot $TestSourceRoot -AssemblyPath $TestAssemblyPath -PDBPath $TestPdbPath
 if($unexpectedCatalog){exit 0}
 throw 'Reader returned neither a catalog nor the required rejection.'
}catch{
 $evidence=[pscustomobject]@{SchemaVersion=1;ExceptionType=$_.Exception.GetType().FullName;Message=$_.Exception.Message;FullyQualifiedErrorId=$_.FullyQualifiedErrorId}
 [IO.File]::WriteAllText($ErrorPath,($evidence|ConvertTo-Json -Depth 3),[Text.UTF8Encoding]::new($false))
 exit 1
}