#Requires -Version 5.1
# This registry provides process-local ownership, not ACL or same-user race protection.
if(-not (Get-Variable -Name ReportOwnedTempRegistry -Scope Script -ErrorAction SilentlyContinue)){
 $script:ReportOwnedTempRegistry=New-Object 'Collections.Generic.List[object]'
}
function Assert-ReportOrdinaryDirectory([string]$Path){
 $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
 $resolved=(Resolve-Path -LiteralPath $full -ErrorAction Stop).ProviderPath.TrimEnd('\','/')
 if(-not [string]::Equals($resolved,$full,[StringComparison]::OrdinalIgnoreCase)){throw '暫存目錄解析不一致。'}
 $dir=[IO.DirectoryInfo]::new($full)
 while($null -ne $dir){
  $item=Get-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
  if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '暫存目錄或祖先不是一般目錄。'}
  $dir=$dir.Parent
 }
 return $full
}
function New-ReportOwnedTemp {
 param([ValidateSet('Portal','Release')][string]$Purpose='Portal')
 $base=Assert-ReportOrdinaryDirectory ([IO.Path]::GetTempPath())
 $prefix=if($Purpose -eq 'Portal'){'portal_zip_'}else{'release_verified_'}
 $nonce=[guid]::NewGuid().ToString('N')
 $path=Join-Path $base ($prefix+$nonce)
 New-Item -ItemType Directory -Path $path -ErrorAction Stop|Out-Null
 $path=Assert-ReportOrdinaryDirectory $path
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($path),$base,[StringComparison]::OrdinalIgnoreCase) -or @(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop).Count){throw '驗證目錄不是空白直接子目錄。'}
 $handle=[pscustomobject]@{Path=$path;Root=$base;Nonce=$nonce}
 $script:ReportOwnedTempRegistry.Add([pscustomobject]@{Handle=$handle;Path=$path;Root=$base;Nonce=$nonce})
 return $handle
}
function Remove-ReportOwnedTemp {
 param([Parameter(Mandatory=$true)]$Handle)
 $record=$null
 foreach($candidate in $script:ReportOwnedTempRegistry){if([object]::ReferenceEquals($candidate.Handle,$Handle)){$record=$candidate;break}}
 if($null -eq $record -or $Handle.Path -cne $record.Path -or $Handle.Root -cne $record.Root -or $Handle.Nonce -cne $record.Nonce){throw '不是本次簽發的暫存目錄 handle。'}
 $base=Assert-ReportOrdinaryDirectory $record.Root
 $full=Assert-ReportOrdinaryDirectory $record.Path
 if($base -ine $record.Root -or $full -ine $record.Path -or [IO.Path]::GetDirectoryName($full) -ine $base -or [IO.Path]::GetFileName($full) -cnotmatch '^(portal_zip_|release_verified_)[a-f0-9]{32}$'){throw '暫存清理範圍不符。'}
 $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($full)
 while($pending.Count){
  $current=$pending.Pop()
  foreach($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)){
   $child=[IO.Path]::GetFullPath($item.FullName)
   if(-not $child.StartsWith($full+'\',[StringComparison]::OrdinalIgnoreCase) -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '暫存目錄含不安全子項，保留供檢查。'}
   if($item.PSIsContainer){$pending.Push($child)}
  }
 }
 $null=Assert-ReportOrdinaryDirectory $full
 Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
 $null=$script:ReportOwnedTempRegistry.Remove($record)
}
