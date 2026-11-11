#Requires -Version 5.1
param([string]$Collector,[string]$Manifest,[string]$Output,[string]$PesterModule,[string]$ObservationPath)
$ErrorActionPreference='Stop'
# Load the unchanged official module once; the import hook below keeps the
# injected provider commands when the actual collector requests the same module.
$global:RegistryFixtureModulePath=$PesterModule
$module=Microsoft.PowerShell.Core\Import-Module -Name $PesterModule -Force -Global -PassThru
$global:RegistryFixtureRealInvoke=(Get-Command -Name Invoke-Pester -Module Pester).ScriptBlock
$global:RegistryFixtureObserved=$null
& $module {
 $script:FixtureOriginalTest=$script:SafeCommands['Test-Path'];$script:FixtureOriginalNew=$script:SafeCommands['New-Item'];$script:FixtureOriginalRemove=$script:SafeCommands['Remove-Item']
 $script:FixtureParentAttempts=0
 function script:Test-RegistryParentFixture {
  [CmdletBinding()]param($Path,$LiteralPath,$PathType)
  if([string]$Path -ceq 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Pester'){return $false}
  & $script:FixtureOriginalTest @PSBoundParameters
 }
 function script:New-RegistryParentFixture {
  [CmdletBinding()]param($Path,$ItemType,$Name,$Value,[switch]$Force)
  if([string]$Path -ceq 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Pester'){
   $script:FixtureParentAttempts++
   throw [IO.IOException]::new('fixture registry parent was created by a parallel peer')
  }
  if([string]$Path -match '(?i)Registry::|^(HKCU|HKLM|TestRegistry):'){throw 'Fixture forbids real registry creation.'}
  & $script:FixtureOriginalNew @PSBoundParameters
 }
 function script:Remove-RegistryFixture {
  [CmdletBinding()]param($Path,$LiteralPath,[switch]$Force,[switch]$Recurse,[switch]$Confirm)
  if(([string]$Path+' '+[string]$LiteralPath) -match '(?i)Registry::|\b(HKCU|HKLM|TestRegistry):'){throw 'Fixture forbids real registry removal.'}
  & $script:FixtureOriginalRemove @PSBoundParameters
 }
 $script:SafeCommands['Test-Path']=$ExecutionContext.InvokeCommand.GetCommand('Test-RegistryParentFixture','Function')
 $script:SafeCommands['New-Item']=$ExecutionContext.InvokeCommand.GetCommand('New-RegistryParentFixture','Function')
 $script:SafeCommands['Remove-Item']=$ExecutionContext.InvokeCommand.GetCommand('Remove-RegistryFixture','Function')
}
function global:Import-Module {
 [CmdletBinding()]param($Name,[switch]$Force)
 if([string]$Name -ieq $global:RegistryFixtureModulePath){return}
 Microsoft.PowerShell.Core\Import-Module @PSBoundParameters
}
function global:Invoke-Pester {
 [CmdletBinding()]param($Configuration)
 $global:RegistryFixtureObserved=[pscustomobject]@{
  TestRegistryEnabled=[bool]$Configuration.TestRegistry.Enabled.Value
  TestDriveEnabled=[bool]$Configuration.TestDrive.Enabled.Value
  CodeCoverageEnabled=[bool]$Configuration.CodeCoverage.Enabled.Value
  CoveragePathCount=@($Configuration.CodeCoverage.Path.Value).Count
  PassThru=[bool]$Configuration.Run.PassThru.Value
 }
 & $global:RegistryFixtureRealInvoke -Configuration $Configuration
}
try{& $Collector -ManifestPath $Manifest -OutputDirectory $Output -WorkerIndex 0 -PesterModule $PesterModule}
finally{
 $attempts=& $module {$script:FixtureParentAttempts}
 $value=[ordered]@{Observed=$global:RegistryFixtureObserved;ParentCreateAttempts=$attempts;ActualRegistryWrites=0;EngineVersion=$PSVersionTable.PSVersion.ToString()}
 [IO.File]::WriteAllText($ObservationPath,($value|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
