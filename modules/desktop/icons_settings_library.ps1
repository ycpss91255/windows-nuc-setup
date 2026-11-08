#Requires -Version 5.1
function Invoke-SetupIconsSettings {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[ValidateSet('Save','Load','Verify')][string]$Mode='Load',$Reference)
 if(-not ('NUC8Icons.Desktop' -as [type])){Add-Type -Path (Join-Path $ModuleRoot 'native/desktop_icons.cs')}
 $snapshot=[NUC8Icons.Desktop]::Capture()

 if($Mode -eq 'Save'){
  if($snapshot.Icons.Count -ne 4){throw ('目前桌面不是四個圖示，請先確認：'+$snapshot.Icons.Count)}
  $reference=[ordered]@{Width=$snapshot.Width;Height=$snapshot.Height;Icons=@($snapshot.Icons|Select-Object Name,X,Y);SavedAt=(Get-Date).ToString('o')}

  $result=[ordered]@{Success=$true;Mode=$Mode;Reference=$reference}
 }else{

  if($snapshot.Width -ne $reference.Width -or $snapshot.Height -ne $reference.Height){throw '桌面範圍與範本不同，請確認解析度、縮放及螢幕數量。'}
  $differences=@()
  foreach($expected in $reference.Icons){
   $actual=@($snapshot.Icons|Where-Object Name -eq $expected.Name)
   if($actual.Count -ne 1){$differences+=('找不到唯一圖示：'+$expected.Name);continue}
   if($Mode -eq 'Load'){[NUC8Icons.Desktop]::Position($actual[0].Index,[int]$expected.X,[int]$expected.Y)}
  }
  if($Mode -eq 'Load'){
   $key='HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
   $flags=(Get-ItemProperty $key -ErrorAction SilentlyContinue).FFlags
   if($null -ne $flags){Set-ItemProperty $key -Name FFlags -Value ($flags -band (-bnot 1))}
   Start-Sleep -Milliseconds 500
  }
  $after=[NUC8Icons.Desktop]::Capture()
  foreach($expected in $reference.Icons){$actual=@($after.Icons|Where-Object Name -eq $expected.Name);if($actual.Count -eq 1 -and ([math]::Abs($actual[0].X-$expected.X) -gt 2 -or [math]::Abs($actual[0].Y-$expected.Y) -gt 2)){$differences+=('位置不符：'+$expected.Name)}}
  $result=[ordered]@{Success=($differences.Count -eq 0);Mode=$Mode;Differences=$differences;Actual=@($after.Icons|Select-Object Name,X,Y);Error=($differences -join '；')}
 }
 return [pscustomobject]$result
}
