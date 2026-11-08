#Requires -Version 5.1
function Get-SetupSshConnectionInfo {
 param([string]$UserName=$env:USERNAME,[string]$ComputerName=$env:COMPUTERNAME)
 '電腦名稱：'+$ComputerName
 'SSH 登入帳號：'+$UserName+'；使用此帳號既有密碼，這裡不顯示密碼。'
 try{
  $addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object {$_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'}|Select-Object -ExpandProperty IPAddress -Unique)
  if($addresses.Count){foreach($ip in $addresses){'IPv4：'+$ip+'；同網段連線：ssh "'+$UserName+'@'+$ip+'"'}}else{'目前沒有可用 IPv4；接上區域網路後重新執行 SSH 模組查看。'}
 }catch{'目前無法讀取 IPv4；請查看 Windows 網路設定。'}
}
