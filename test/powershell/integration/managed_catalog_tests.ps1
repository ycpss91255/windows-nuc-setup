#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$reader=Join-Path $root 'script/test/managed_catalog.ps1'
Assert (Test-Path -LiteralPath $reader -PathType Leaf) 'portable PDB catalog has an independent reader'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pdb_catalog_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$dotnet=(Get-Command dotnet -ErrorAction Stop).Source
$sdks=@(& $dotnet --list-sdks|ForEach-Object {if($_ -match '^([0-9.]+)\s+\[(.+)\]$'){Join-Path (Join-Path $Matches[2] $Matches[1]) 'Roslyn/bincore/csc.dll'}})
$compiler=$sdks[-1];$refs=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$source=Join-Path $temp 'fixture.cs';$dll=Join-Path $temp 'fixture.dll';$pdb=Join-Path $temp 'fixture.pdb';$catalog=Join-Path $temp 'catalog.json'
[IO.File]::WriteAllText($source,"using System.Runtime.InteropServices;`r`npublic static class Fixture {`r`n[DllImport(`"kernel32.dll`")] public static extern uint GetCurrentProcessId();`r`npublic static int Code(bool x){ if(x)return 1;return 2; }`r`n}")
$compilerArgs=@($compiler,'/nologo','/noconfig','/nostdlib+','/target:library','/debug:portable','/optimize-',('/out:'+$dll),('/pdb:'+$pdb),('/reference:'+(Join-Path $refs 'mscorlib.dll')),('/reference:'+(Join-Path $refs 'System.dll')),$source)
& $dotnet @compilerArgs
if($LASTEXITCODE -ne 0){throw 'Fixture compiler failed'}
& pwsh.exe -NoProfile -File $reader -SourceRoot $temp -AssemblyPath $dll -PDBPath $pdb -OutputPath $catalog
Assert ($LASTEXITCODE -eq 0 -and (Test-Path $catalog)) 'reader validates PE and portable PDB without running assembly'
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
& pwsh.exe -NoProfile -File $reader -SourceRoot $temp -AssemblyPath $dll -PDBPath $otherPdb -OutputPath (Join-Path $temp 'invalid.json') *> (Join-Path $temp 'mismatch.log')
Assert ($LASTEXITCODE -ne 0 -and -not(Test-Path (Join-Path $temp 'invalid.json'))) 'swapped PDB cannot publish a valid source catalog'
Write-Host ('ALL PASS: '+$script:count+' actual PE/portable PDB catalog assertions; no assembly code invoked')