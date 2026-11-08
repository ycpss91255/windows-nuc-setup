#Requires -Version 5.1
#Requires -RunAsAdministrator
param([Parameter(Mandatory=$true)][string]$Role,[Parameter(Mandatory=$true)][string]$RunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'gui_stage_library.ps1')
Invoke-SetupGuiWorker -CodeRoot (Split-Path $PSScriptRoot -Parent) -Role $Role -RunId $RunId