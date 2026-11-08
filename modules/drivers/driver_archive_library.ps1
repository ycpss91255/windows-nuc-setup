#Requires -Version 5.1
function Expand-DriverArchive {
 param([string]$Archive,[string]$Destination)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
 $root=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
 $total=[double](($zip.Entries|Measure-Object Length -Sum).Sum)
 $done=0.0;$timer=[Diagnostics.Stopwatch]::StartNew();$lastUi=-1;$lastText=-10
 $buffer=New-Object byte[] (1024*1024)
 try{
  foreach($entry in $zip.Entries){
   $target=[IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
   if(-not $target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw '封存檔包含不合法路徑。'}
   if($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')){[void][IO.Directory]::CreateDirectory($target);continue}
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   $inputStream=$entry.Open();$outputStream=[IO.File]::Open($target,[IO.FileMode]::Create,[IO.FileAccess]::Write)
   try{
    while(($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
     $outputStream.Write($buffer,0,$read);$done+=$read
     $percent=if($total -gt 0){[math]::Min(100,[int]($done*100/$total))}else{100}
     if($timer.ElapsedMilliseconds-$lastUi -ge 250){
      Write-Progress -Id 2 -Activity ('驅動解壓縮：'+[IO.Path]::GetFileName($Archive)) -Status ($percent.ToString()+'%') -PercentComplete $percent -CurrentOperation $entry.Name
      $lastUi=$timer.ElapsedMilliseconds
     }
     if($timer.Elapsed.TotalSeconds-$lastText -ge 10){Write-Host ('解壓縮進度：'+$percent+'%；已處理 '+[math]::Round($done/1MB)+' / '+[math]::Round($total/1MB)+' MB');$lastText=$timer.Elapsed.TotalSeconds}
    }
   }finally{$outputStream.Dispose();$inputStream.Dispose()}
  }
  Write-Host '解壓縮進度：100%'
 }finally{$zip.Dispose();Write-Progress -Id 2 -Activity '驅動解壓縮' -Completed}
}
function Expand-CachedDriverArchive {
 param([string]$Archive,[string]$CacheRoot,[string]$SHA256)
 if($SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw '驅動快取需要有效的 SHA256。'}
 $dest=Join-Path $CacheRoot (([IO.Path]::GetFileNameWithoutExtension($Archive))+'-'+$SHA256.ToLowerInvariant())
 $marker=Join-Path $dest '.archive-sha256'
 if(-not(Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne $SHA256){
  Write-Host ('正在解壓縮：'+[IO.Path]::GetFileName($Archive)) -ForegroundColor Cyan
  New-Item -ItemType Directory -Path $dest -Force|Out-Null
  Expand-DriverArchive -Archive $Archive -Destination $dest
  Set-Content -LiteralPath $marker -Value $SHA256 -Encoding ascii
 }
 return $dest
}
