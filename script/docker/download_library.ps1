#Requires -Version 5.1
function Test-ContainerTransientDownload {
 param([Exception]$Exception)
 $current=$Exception
 for($depth=0;$null -ne $current -and $depth -lt 5;$depth++){
  if($current -is [Net.WebException] -and $current.Status -eq [Net.WebExceptionStatus]::Timeout){return $true}
  if($null -ne $current.Response -and $null -ne $current.Response.StatusCode){$status=[int]$current.Response.StatusCode;if($status -eq 408 -or $status -eq 429 -or ($status -ge 500 -and $status -le 599)){return $true}}
  $current=$current.InnerException
 }
 return $false
}
function Invoke-ContainerOfficialDownload {
 param([Parameter(Mandatory=$true)][uri]$Uri,[Parameter(Mandatory=$true)][string]$OutFile)
 if(-not $Uri.IsAbsoluteUri -or $Uri.Scheme -cne 'https' -or $Uri.UserInfo){throw 'Official download must use HTTPS without credentials.'}
 $output=[IO.Path]::GetFullPath($OutFile)
 if(Test-Path -LiteralPath $output){throw 'Download output already exists; no unknown cache or overwrite.'}
 for($attempt=1;$attempt -le 3;$attempt++){
  $partial=Join-Path ([IO.Path]::GetDirectoryName($output)) ([guid]::NewGuid().ToString('N')+'.partial')
  try{
   Invoke-WebRequest -UseBasicParsing -Uri $Uri.AbsoluteUri -OutFile $partial -TimeoutSec 120 -ErrorAction Stop
   if(-not(Test-Path -LiteralPath $partial -PathType Leaf) -or (Get-Item -LiteralPath $partial).Length -le 0){throw 'Official download produced no complete file.'}
   [IO.File]::Move($partial,$output)
   return
  }catch{
   if($attempt -ge 3 -or -not(Test-ContainerTransientDownload -Exception $_.Exception)){throw}
  }finally{if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}}
  Start-Sleep -Seconds $attempt
 }
}
