#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Get-MaintenanceReferences([string]$Path){
 $text=[IO.File]::ReadAllText($Path)
 if([IO.Path]::GetExtension($Path) -eq '.ps1'){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ('Parse failed: '+$Path)}
  # AST excludes comments; inspect executable command elements and path literals.
  $values=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -or $node -is [Management.Automation.Language.ExpandableStringExpressionAst]},$true)|ForEach-Object {$_.Value})
 }elseif([IO.Path]::GetExtension($Path) -eq '.cmd'){$values=@($text -split '\r?\n'|Where-Object {$_ -notmatch '^\s*(@?rem\b|::)'})}
 elseif([IO.Path]::GetExtension($Path) -eq '.json'){$values=@(($text|ConvertFrom-Json).PSObject.Properties|ForEach-Object {[string]$_.Value})}
 else{return}
 @($values|Where-Object {$_ -match '(?i)(^|[\\/])(?:script|test|\.github)(?:[\\/]|$)'})
}
$runtime=@(Get-ChildItem (Join-Path $root 'core') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'modules') -Recurse -File|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-Item (Join-Path $root 'Init.cmd'),(Join-Path $root 'Windows.cmd'))
$violations=@(foreach($file in $runtime|Where-Object Extension -in @('.ps1','.cmd','.json')){foreach($reference in @(Get-MaintenanceReferences $file.FullName)){[pscustomobject]@{File=$file.FullName;Reference=$reference}}})
Assert ($violations.Count -eq 0) ('執行樹不引用維護／測試／CI 路徑：'+($violations.File -join ', '))
$entrypoints=@(foreach($dir in @('core','modules','script','test')){Get-ChildItem (Join-Path $root $dir) -Recurse -Filter 'Run-CI.ps1' -File|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]'})
Assert ($entrypoints.Count -eq 1 -and $entrypoints[0].FullName -eq (Join-Path $root 'script\test\Run-CI.ps1')) '只有 script/test 維護測試聚合入口'
foreach($name in @('Prepare-Release','Build-SourceRelease','Release')){Assert (Test-Path (Join-Path $root ('script/release/'+$name+'.ps1'))) ('發布維護工具位於 script/release：'+$name)}
Assert (Test-Path (Join-Path $root 'script/package/Export-DriverPackage.ps1')) '打包維護工具位於 script/package'
# Prove the dependency check rejects a real path import but ignores a comment.
$fixture=Join-Path $env:TEMP ('windows_setup_architecture_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$sample=Join-Path $fixture 'runtime.ps1'
[IO.File]::WriteAllText($sample,"# . ..\script\test\Run-CI.ps1`nWrite-Output 'safe'")
Assert (@(Get-MaintenanceReferences $sample).Count -eq 0) '註解中的維護路徑不誤判'
[IO.File]::WriteAllText($sample,". (Join-Path `$PSScriptRoot '..\script\test\Run-CI.ps1')")
Assert (@(Get-MaintenanceReferences $sample).Count -gt 0) '真正的 runtime 到維護工具引用會失敗'
Write-Host ('ALL PASS: '+$count+' architecture assertions; source inspection and temporary fixture only.')