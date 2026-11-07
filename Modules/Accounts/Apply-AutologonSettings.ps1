#Requires -Version 5.1
#Requires -RunAsAdministrator
param([string]$UserName=$env:USERNAME,[string]$AutoLogonPassword)
$ErrorActionPreference='Stop'
    if($UserName -ine $env:USERNAME){throw '請以要自動登入的本機帳號執行。'}
    if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) { throw '找不到指定的本機帳號。' }
    if (-not $AutoLogonPassword) {
        $secure=Read-Host '請輸入自動登入帳號的現有密碼' -AsSecureString
        $AutoLogonPassword=[Net.NetworkCredential]::new('', $secure).Password
    }
    $exe=Join-Path $PSScriptRoot 'Autologon64.exe'
    $sig=Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Autologon 微軟數位簽章驗證失敗。' }
    function Quote-NativeArgument([string]$Value){
        '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
    }
    $arguments=(@('/accepteula',$UserName,$env:COMPUTERNAME,$AutoLogonPassword)|ForEach-Object {Quote-NativeArgument $_}) -join ' '
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru
    $AutoLogonPassword=$null;$arguments=$null
    if ($process.ExitCode -ne 0) { throw ('Autologon 結束代碼：'+$process.ExitCode) }
    $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $auto=Get-ItemProperty $key
    if ($auto.AutoAdminLogon -ne '1' -or $auto.DefaultUserName -ne $UserName) { throw '自動登入設定驗證失敗。' }
    Write-Host '自動登入設定已寫入；需下次重新開機才能驗證實際登入。' -ForegroundColor Green




