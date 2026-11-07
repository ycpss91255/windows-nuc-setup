#Requires -Version 5.1
$script:NucPackageRoot=Split-Path -Parent $PSScriptRoot
$script:NucPathMap=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Paths.json'))|ConvertFrom-Json
function Resolve-NucPath {
 param([Parameter(Mandatory=$true)][string]$Name)
 $normalized=$Name.Replace('\','/')
 foreach($property in $script:NucPathMap.PSObject.Properties){
  $key=$property.Name.Replace('\','/')
  if($normalized -eq $key){return Join-Path $script:NucPackageRoot $property.Value}
  if($key -in @('CustomHostsSync','Win11Debloat') -and $normalized.StartsWith($key+'/',[StringComparison]::OrdinalIgnoreCase)){
   return Join-Path (Join-Path $script:NucPackageRoot $property.Value) $normalized.Substring($key.Length+1)
  }
 }
 if($normalized -match '[/\\]' -or $normalized -match '\.(ps1|cmd|exe)$'){throw ('未登錄的套件路徑：'+$Name)}
 return Join-Path (Join-Path $script:NucPackageRoot 'Reports') $Name
}
function Get-NucDriverRoot {
 foreach($candidate in @((Join-Path $script:NucPackageRoot 'Modules\Drivers\Payload'),(Join-Path $script:NucPackageRoot 'Drivers'),(Join-Path $script:NucPackageRoot 'Driver'),(Join-Path (Split-Path $script:NucPackageRoot -Parent) 'Driver'))){
  if(Test-Path -LiteralPath (Join-Path $candidate 'manifest.json') -PathType Leaf){return $candidate}
 }
 throw '找不到驅動 manifest.json；請保留 OneClick 旁邊的 Driver 資料夾，或 Modules\Drivers\Payload。'
}
function Initialize-NucReports {
 $path=Join-Path $script:NucPackageRoot 'Reports'
 if(-not(Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Path $path|Out-Null}
}
