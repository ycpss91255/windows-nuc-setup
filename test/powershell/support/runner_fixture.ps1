#Requires -Version 5.1
function Assert-RunnerOwnedDirectory {
 param([string]$Path,[string]$Parent,[string]$Name)
 if(-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Path]::IsPathRooted($Parent) -or $Name -cnotmatch '\Arunner_native_[a-f0-9]{32}\z'){throw 'Invalid owned fixture cleanup identity.'}
 $expectedParent=(Get-Item -LiteralPath $Parent -Force -ErrorAction Stop).FullName
 $expected=[IO.Path]::GetFullPath((Join-Path $expectedParent $Name))
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item -isnot [IO.DirectoryInfo] -or $item.FullName -cne $expected -or [IO.Path]::GetFullPath($Path) -cne $expected -or $item.Parent.FullName -cne $expectedParent){throw 'Owned fixture cleanup target is not its exact created directory.'}
 $ancestor=$item
 while($null -ne $ancestor){
  if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Owned fixture cleanup cannot cross a reparse point.'}
  $ancestor=$ancestor.Parent
 }
 $pending=New-Object 'Collections.Generic.Queue[IO.DirectoryInfo]'
 $pending.Enqueue($item)
 while($pending.Count -gt 0){
  foreach($child in @(Get-ChildItem -LiteralPath $pending.Dequeue().FullName -Force -ErrorAction Stop)){
   if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Owned fixture cleanup contains a reparse point.'}
   if($child -is [IO.DirectoryInfo]){$pending.Enqueue($child)}
  }
 }
 return $item.FullName
}
function Test-RunnerProcessIdentity {
 param([Diagnostics.Process]$Process,[int]$Identifier,[long]$StartTicks)
 try {
  # Retain this exact OS process handle before examining identity or terminating it.
  $null=$Process.Handle
  return (-not $Process.HasExited -and $Process.Id -eq $Identifier -and $Process.StartTime.ToUniversalTime().Ticks -eq $StartTicks)
 }catch{return $false}
}
