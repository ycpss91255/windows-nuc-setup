#Requires -Version 5.1
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9-]{36}$')][string]$RunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'mdns_publisher_library.ps1')
Invoke-SetupMdnsPublisherWorker -RunId $RunId -CodeRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')))