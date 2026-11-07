#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'hardware.ps1')
$script:NucPackageRoot=Split-Path -Parent $PSScriptRoot
$script:NucPathMap=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'paths.json'))|ConvertFrom-Json
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
 return Join-Path (Join-Path $script:NucPackageRoot 'reports') $Name
}
function Initialize-NucReports {
 $path=Join-Path $script:NucPackageRoot 'reports'
 if(-not(Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Path $path|Out-Null}
}

# 舊版本續跑記錄中的模組識別仍可解析；輸出統一使用新檔名。
function Resolve-NucModuleName {
 param([Parameter(Mandatory=$true)][string]$Name)
 foreach($property in $script:NucPathMap.PSObject.Properties){
  if($property.Name -eq $Name -and $property.Value -match '\.ps1$'){return [IO.Path]::GetFileName($property.Value)}
 }
 return $Name
}
