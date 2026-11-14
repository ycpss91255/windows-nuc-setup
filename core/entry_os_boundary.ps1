#Requires -Version 5.1
function Get-SetupEntryIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
