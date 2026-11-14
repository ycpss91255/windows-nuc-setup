#Requires -Version 5.1
function Invoke-SetupStartMenuDispatch {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive)
 & $Path -VerifyOnly:$VerifyOnly -ApplyPolicy:($ApplyPolicy -and -not $VerifyOnly) -NonInteractive:$NonInteractive
}
