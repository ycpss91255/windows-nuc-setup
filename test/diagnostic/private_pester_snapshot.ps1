#Requires -Version 5.1
# Temporary diagnostic only. This script writes private data and emits nothing.
param([Parameter(Mandatory=$true)][string]$Path,$Result,[Management.Automation.ErrorRecord[]]$InvocationErrors=@())
$ErrorActionPreference='Stop'
$full=[IO.Path]::GetFullPath($Path)
if([IO.Path]::GetFileName($full) -cnotmatch '^worker_[0-9]+\.private\.error\.json$'){throw 'Private snapshot filename is invalid.'}
$parent=Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($full)) -Force
if(-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Private snapshot parent is invalid.'}
function Limit-PrivateText($Value){
 $text=[string]$Value;$utf8=[Text.UTF8Encoding]::new($false)
 $bytes=$utf8.GetBytes($text)
 if($bytes.Length -le 65536){return $text}
 $chars=[char[]]::new(65536);[int]$bytesUsed=0;[int]$charsUsed=0;[bool]$completed=$false
 $utf8.GetDecoder().Convert($bytes,0,65536,$chars,0,$chars.Length,$false,[ref]$bytesUsed,[ref]$charsUsed,[ref]$completed)
 return [string]::new($chars,0,$charsUsed)
}
$records=[Collections.Generic.List[object]]::new()
function Add-PrivateRecord([string]$Scope,[Management.Automation.ErrorRecord]$Record){
 if($null -eq $Record -or $records.Count -ge 16){return}
 foreach($existing in $records){if([object]::ReferenceEquals($existing.Record,$Record)){return}}
 $records.Add([pscustomobject]@{Scope=$Scope;Record=$Record})
}
foreach($record in $InvocationErrors){Add-PrivateRecord 'Invocation' $record}
if($null -ne $Result){
 foreach($group in @(@{Property='FailedContainers';Scope='Container'},@{Property='FailedBlocks';Scope='Block'},@{Property='Failed';Scope='Test'})){
  foreach($failure in @($Result.($group.Property))){foreach($record in @($failure.ErrorRecord)){Add-PrivateRecord $group.Scope $record}}
 }
}
$rows=@(foreach($item in $records){
 $record=$item.Record
 [pscustomobject][ordered]@{
  Scope=$item.Scope
  Message=(Limit-PrivateText $record.Exception.Message)
  ExceptionType=(Limit-PrivateText $record.Exception.GetType().FullName)
  FullyQualifiedErrorId=(Limit-PrivateText $record.FullyQualifiedErrorId)
  InvocationPosition=(Limit-PrivateText $record.InvocationInfo.PositionMessage)
  ScriptStackTrace=(Limit-PrivateText $record.ScriptStackTrace)
  ExceptionDetail=(Limit-PrivateText $record.Exception.ToString())
 }
})
$value=[ordered]@{SchemaVersion=1;Errors=$rows}
$stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
$writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false))
try{$writer.Write(($value|ConvertTo-Json -Depth 6 -Compress))}finally{$writer.Dispose();$stream.Dispose()}
