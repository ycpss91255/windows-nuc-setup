#Requires -Version 5.1
param([string]$SourceRoot,[string]$AssemblyPath,[string]$PDBPath,[string]$OutputPath)
# Maintenance-only reader: invoke with pwsh 7.4+ / .NET 8+, never the deployed PS5.1 runtime.
function Get-ManagedCatalogRelativePath {
 param([string]$Root,[string]$Path)
 $prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 $full=[IO.Path]::GetFullPath($Path)
 if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'PDB source path is outside the declared source root.'}
 return $full.Substring($prefix.Length).Replace('\','/')
}
function Get-ManagedPortableCatalog {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$PDBPath)
 if([Environment]::Version.Major -lt 8 -or $PSVersionTable.PSVersion.Major -lt 7){throw 'Portable PDB maintenance requires pwsh 7.4+ with .NET 8 or newer; deployed Windows scripts still use PS5.1.'}
 Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction Stop
 $assemblyHash=(Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
 $pdbHash=(Get-FileHash -LiteralPath $PDBPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
 $assemblyStream=$null;$pdbStream=$null;$pe=$null;$provider=$null
 try{
  $assemblyStream=[IO.File]::OpenRead($AssemblyPath)
  $pe=[Reflection.PortableExecutable.PEReader]::new($assemblyStream)
  $metadata=[Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
  $pdbStream=[IO.File]::OpenRead($PDBPath)
  $provider=[Reflection.Metadata.MetadataReaderProvider]::FromPortablePdbStream($pdbStream)
  $debug=$provider.GetMetadataReader()
  [byte[]]$id=$debug.DebugMetadataHeader.Id
  if($id.Length -ne 20){throw 'Portable PDB content identity has an unsupported shape.'}
  $pdbId=[Guid]::new([byte[]]($id[0..15])).ToString('D')+'/'+[BitConverter]::ToUInt32($id,16).ToString('x8')
  $entries=@($pe.ReadDebugDirectory()|Where-Object {$_.Type -eq 'CodeView'})
  if($entries.Count -ne 1){throw 'Assembly must identify exactly one portable PDB.'}
  $codeView=$pe.ReadCodeViewDebugDirectoryData($entries[0])
  $peId=$codeView.Guid.ToString('D')+'/'+$entries[0].Stamp.ToString('x8')
  if($codeView.Age -ne 1 -or $pdbId -cne $peId){throw 'Assembly debug identity and supplied PDB do not match.'}
  if($debug.MethodDebugInformation.Count -ne $metadata.MethodDefinitions.Count){throw 'PDB method debug table is incomplete.'}
  $documents=New-Object 'Collections.Generic.List[object]';$paths=@{}
  foreach($handle in $debug.Documents){
   $document=$debug.GetDocument($handle);$path=$debug.GetString($document.Name)
   $relative=Get-ManagedCatalogRelativePath -Root $SourceRoot -Path $path
   if($paths.ContainsKey($relative)){throw 'PDB contains duplicate source documents.'}
   if($debug.GetGuid($document.HashAlgorithm).ToString('D') -ne '8829d00f-11b8-4213-878b-770e8597ac16'){throw 'PDB source checksums must use SHA256.'}
   $checksum=([BitConverter]::ToString($debug.GetBlobBytes($document.Hash))).Replace('-','').ToLowerInvariant()
   if($checksum -cne (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()){throw 'Compiler PDB source checksum differs from the actual source.'}
   $paths[$relative]=$true
   $documents.Add([pscustomobject]@{Path=$relative;SHA256=$checksum})
  }
  if($documents.Count -eq 0){throw 'PDB has no actual source documents.'}
  $methods=New-Object 'Collections.Generic.List[object]'
  foreach($handle in $metadata.MethodDefinitions){
   $definition=$metadata.GetMethodDefinition($handle)
   $row=[Reflection.Metadata.Ecma335.MetadataTokens]::GetRowNumber([Reflection.Metadata.EntityHandle]$handle)
   $information=$debug.GetMethodDebugInformation([Reflection.Metadata.Ecma335.MetadataTokens]::MethodDebugInformationHandle($row))
   $points=New-Object 'Collections.Generic.List[object]';$hidden=0
   foreach($point in $information.GetSequencePoints()){
    if($point.IsHidden){$hidden++;continue}
    $documentHandle=$point.Document;if($documentHandle.IsNil){$documentHandle=$information.Document}
    if($documentHandle.IsNil){throw 'Visible compiler sequence point has no source document.'}
    $document=$debug.GetDocument($documentHandle)
    $relative=Get-ManagedCatalogRelativePath -Root $SourceRoot -Path ($debug.GetString($document.Name))
    if(-not $paths.ContainsKey($relative)){throw 'Visible point refers to an unknown source document.'}
    $points.Add([pscustomobject]@{Path=$relative;StartLine=$point.StartLine;StartColumn=$point.StartColumn;EndLine=$point.EndLine;EndColumn=$point.EndColumn;Offset=$point.Offset})
   }
   $methods.Add([pscustomobject]@{Token=('0x{0:x8}' -f (0x06000000+$row));HasBody=($definition.RelativeVirtualAddress -ne 0);HiddenPoints=$hidden;Points=[object[]]$points.ToArray()})
  }
  return [pscustomobject][ordered]@{SchemaVersion=1;AssemblySHA256=$assemblyHash;PDBSHA256=$pdbHash;AssemblyMVID=$metadata.GetGuid($metadata.GetModuleDefinition().Mvid).ToString('D');PDBContentID=$pdbId;PEPDBContentID=$peId;Documents=[object[]]$documents.ToArray();Methods=[object[]]$methods.ToArray()}
 }finally{
  if($provider){$provider.Dispose()};if($pe){$pe.Dispose()};if($pdbStream){$pdbStream.Dispose()};if($assemblyStream){$assemblyStream.Dispose()}
 }
}
if($MyInvocation.InvocationName -ne '.'){
 $ErrorActionPreference='Stop'
 if(-not $SourceRoot -or -not $AssemblyPath -or -not $PDBPath -or -not $OutputPath){throw 'SourceRoot, AssemblyPath, PDBPath and OutputPath are required.'}
 $catalog=Get-ManagedPortableCatalog -SourceRoot $SourceRoot -AssemblyPath $AssemblyPath -PDBPath $PDBPath
 [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($catalog|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}