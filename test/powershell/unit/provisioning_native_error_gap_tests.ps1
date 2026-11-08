#Requires -Version 5.1
$ErrorActionPreference='Stop'
# A native-API boundary double: the product function and its failure handling remain original.
Add-Type -TypeDefinition 'namespace WindowsSetup { public static class InitOobeNative { public static bool OOBEComplete(out bool complete) {complete=false; return false;} } }'
. (Join-Path $PSScriptRoot '../../../modules/init/provisioning_library.ps1')
$result=Invoke-InitOobeCompleteNative
$ok=($result.Succeeded -is [bool] -and -not $result.Succeeded -and -not $result.Complete -and $result.ErrorCode -is [int])
Write-Host ('@@ASSERT@@'+(@{Name='原生OOBE查詢失敗保留布林及Win32錯誤，不當作未完成OOBE的有效證明';Passed=$ok}|ConvertTo-Json -Compress))
if(-not $ok){throw 'native OOBE failure contract'}
