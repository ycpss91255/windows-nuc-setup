#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$reader=Join-Path $root 'script/test/managed_catalog.ps1'
Assert (Test-Path -LiteralPath $reader -PathType Leaf) 'portable PDB catalog has an independent reader'
$rejectionReader=Join-Path $root 'test/powershell/fixtures/read_managed_catalog_rejection.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pdb_catalog_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$dotnet=(Get-Command dotnet -ErrorAction Stop).Source
$sdks=@(& $dotnet --list-sdks|ForEach-Object {if($_ -match '^([0-9.]+)\s+\[(.+)\]$'){Join-Path (Join-Path $Matches[2] $Matches[1]) 'Roslyn/bincore/csc.dll'}})
$compiler=$sdks[-1];$refs=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$source=Join-Path $temp 'fixture.cs';$dll=Join-Path $temp 'fixture.dll';$pdb=Join-Path $temp 'fixture.pdb';$catalog=Join-Path $temp 'catalog.json'
[IO.File]::WriteAllText($source,"using System.Runtime.InteropServices;`r`npublic static class Fixture {`r`n[DllImport(`"kernel32.dll`")] public static extern uint GetCurrentProcessId();`r`npublic static int Code(bool x){ if(x)return 1;return 2; }`r`n}")
$compilerArgs=@($compiler,'/nologo','/noconfig','/nostdlib+','/target:library','/debug:portable','/optimize-',('/out:'+$dll),('/pdb:'+$pdb),('/reference:'+(Join-Path $refs 'mscorlib.dll')),('/reference:'+(Join-Path $refs 'System.dll')),$source)
& $dotnet @compilerArgs
if($LASTEXITCODE -ne 0){throw 'Fixture compiler failed'}
if($PSVersionTable.PSVersion.Major -ge 7 -and [Environment]::Version.Major -ge 8){
 . $reader
 $result=Get-ManagedPortableCatalog -SourceRoot $temp -AssemblyPath $dll -PDBPath $pdb
 [IO.File]::WriteAllText($catalog,($result|ConvertTo-Json -Depth 12))
 $nativeExit=0
}else{
 $savedPreference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& pwsh.exe -NoProfile -File $reader -SourceRoot $temp -AssemblyPath $dll -PDBPath $pdb -OutputPath $catalog;$nativeExit=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
}
Assert ($nativeExit -eq 0 -and (Test-Path $catalog)) 'reader validates PE and portable PDB without running assembly'
$c=[IO.File]::ReadAllText($catalog)|ConvertFrom-Json
Assert ($c.PDBContentID -ceq $c.PEPDBContentID -and $c.AssemblyMVID -match '^[a-f0-9-]{36}$') 'catalog binds exact PE debug identity and assembly MVID'
Assert ($c.Documents.Count -eq 1 -and $c.Documents[0].Path -eq 'fixture.cs' -and $c.Documents[0].SHA256 -ieq (Get-FileHash $source).Hash) 'catalog binds compiler source checksum rather than re-derived lines'
$native=@($c.Methods|Where-Object {-not $_.HasBody})
$managed=@($c.Methods|Where-Object {$_.Points.Count -gt 0})
Assert ($native.Count -eq 1 -and $native[0].Points.Count -eq 0) 'extern declaration is a proven non-body method'
Assert ($managed.Count -eq 1 -and $managed[0].Token -match '^0x[0-9a-f]{8}$' -and $managed[0].Points.Count -ge 4) 'all visible managed compiler sequence points retain exact method token'
Assert (@($managed[0].Points|Where-Object {$_.Path -ne 'fixture.cs' -or $_.StartLine -ne 4 -or $_.EndLine -ne 4 -or $_.Offset -lt 0}).Count -eq 0) 'same-line fine points retain spans and IL offsets'
$other=Join-Path $temp 'other.dll';$otherPdb=Join-Path $temp 'other.pdb'
[IO.File]::WriteAllText($source,[IO.File]::ReadAllText($source).Replace('return 2','return 3'))
$compilerArgs=@($compiler,'/nologo','/noconfig','/nostdlib+','/target:library','/debug:portable','/optimize-',('/out:'+$other),('/pdb:'+$otherPdb),('/reference:'+(Join-Path $refs 'mscorlib.dll')),('/reference:'+(Join-Path $refs 'System.dll')),$source)
& $dotnet @compilerArgs
if($LASTEXITCODE -ne 0){throw 'Second fixture compiler failed'}
if($PSVersionTable.PSVersion.Major -ge 7 -and [Environment]::Version.Major -ge 8){
 $rejected=$false;try{Get-ManagedPortableCatalog -SourceRoot $temp -AssemblyPath $dll -PDBPath $otherPdb|Out-Null}catch{$rejected=$true}
}else{
 $savedPreference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& pwsh.exe -NoProfile -File $reader -SourceRoot $temp -AssemblyPath $dll -PDBPath $otherPdb -OutputPath (Join-Path $temp 'invalid.json') *> (Join-Path $temp 'mismatch.log');$rejected=($LASTEXITCODE -ne 0)}finally{$ErrorActionPreference=$savedPreference}
}
Assert ($rejected -and -not(Test-Path (Join-Path $temp 'invalid.json'))) 'swapped PDB cannot publish a valid source catalog'
function Assert-CatalogRejected {
 param([string]$SourceDirectory,[string]$PE,[string]$Symbols,[string]$Expected,[string]$Name)
 if($PSVersionTable.PSVersion.Major -ge 7 -and [Environment]::Version.Major -ge 8){
  $message='';try{Get-ManagedPortableCatalog -SourceRoot $SourceDirectory -AssemblyPath $PE -PDBPath $Symbols|Out-Null}catch{$message=$_.Exception.Message}
 }else{
  $log=Join-Path $temp ('rejected_'+[guid]::NewGuid().ToString('N')+'.log');$target=Join-Path $temp ('rejected_'+[guid]::NewGuid().ToString('N')+'.json')
  $savedPreference=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';& pwsh.exe -NoProfile -File $rejectionReader -ReaderPath $reader -TestSourceRoot $SourceDirectory -TestAssemblyPath $PE -TestPdbPath $Symbols -ErrorPath $target *> $log;$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
  if($exitCode -eq 0 -or -not(Test-Path -LiteralPath $target)){throw ('Expected semantic rejection evidence; exit='+$exitCode+'; actual='+[IO.File]::ReadAllText($log))}
  $errorEvidence=[IO.File]::ReadAllText($target)|ConvertFrom-Json
  $message=[string]$errorEvidence.Message
  if($errorEvidence.SchemaVersion -ne 1 -or $errorEvidence.ExceptionType -cne 'System.Management.Automation.RuntimeException'){throw ('Unexpected rejection type: '+($errorEvidence|ConvertTo-Json -Compress))}
 }
 if($message -notmatch [regex]::Escape($Expected)){Write-Host ('Actual raw exception: '+$message)}
 Assert ($message -match [regex]::Escape($Expected)) $Name
}
Assert-CatalogRejected $temp $dll $pdb 'Compiler PDB source checksum differs' 'modified source cannot be accepted using old compiler checksum'
Assert-CatalogRejected (Join-Path $temp 'unrelated') $other $otherPdb 'outside the declared source root' 'compiler source document cannot escape declared source root'
$noDebug=Join-Path $temp 'no_debug.dll'
& $dotnet $compiler /nologo /noconfig /nostdlib+ /target:library /debug- ('/out:'+$noDebug) ('/reference:'+(Join-Path $refs 'mscorlib.dll')) $source
if($LASTEXITCODE -ne 0){throw 'No-debug fixture compilation failed'}
Assert-CatalogRejected $temp $noDebug $otherPdb 'exactly one portable PDB' 'assembly without debug identity is rejected'
$sha1=Join-Path $temp 'sha1.dll';$sha1Pdb=Join-Path $temp 'sha1.pdb'
& $dotnet $compiler /nologo /noconfig /nostdlib+ /target:library /debug:portable /checksumalgorithm:sha1 ('/out:'+$sha1) ('/pdb:'+$sha1Pdb) ('/reference:'+(Join-Path $refs 'mscorlib.dll')) $source
if($LASTEXITCODE -ne 0){throw 'SHA1 fixture compilation failed'}
Assert-CatalogRejected $temp $sha1 $sha1Pdb 'checksums must use SHA256' 'weak compiler source checksum is rejected'
Write-Host ('ALL PASS: '+$script:count+' actual PE/portable PDB catalog assertions; no assembly code invoked')
