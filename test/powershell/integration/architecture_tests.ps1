#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
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
$runtime=@(Get-ChildItem (Join-Path $root 'core') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'modules') -Recurse -File|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-Item (Join-Path $root 'init.cmd'),(Join-Path $root 'windows.cmd'))
$violations=@(foreach($file in $runtime|Where-Object Extension -in @('.ps1','.cmd','.json')){foreach($reference in @(Get-MaintenanceReferences $file.FullName)){[pscustomobject]@{File=$file.FullName;Reference=$reference}}})
Assert ($violations.Count -eq 0) ('執行樹不引用維護／測試／CI 路徑：'+($violations.File -join ', '))
$entrypoints=@(foreach($dir in @('core','modules','script','test')){Get-ChildItem (Join-Path $root $dir) -Recurse -Filter 'run_ci.ps1' -File|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]'})
Assert ($entrypoints.Count -eq 1 -and $entrypoints[0].FullName -eq (Join-Path $root 'script\test\run_ci.ps1')) '只有 script/test 維護測試聚合入口'
foreach($name in @('prepare_release','build_source_release','release')){Assert (Test-Path (Join-Path $root ('script/release/'+$name+'.ps1'))) ('發布維護工具位於 script/release：'+$name)}
Assert (Test-Path (Join-Path $root 'script/package/export_driver_package.ps1')) '打包維護工具位於 script/package'
# Prove the dependency check rejects a real path import but ignores a comment.
$fixture=Join-Path $env:TEMP ('windows_setup_architecture_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$sample=Join-Path $fixture 'runtime.ps1'
[IO.File]::WriteAllText($sample,"# . ..\script\test\run_ci.ps1`nWrite-Output 'safe'")
Assert (@(Get-MaintenanceReferences $sample).Count -eq 0) '註解中的維護路徑不誤判'
[IO.File]::WriteAllText($sample,". (Join-Path `$PSScriptRoot '..\script\test\run_ci.ps1')")
Assert (@(Get-MaintenanceReferences $sample).Count -gt 0) '真正的 runtime 到維護工具引用會失敗'
$readme=[IO.File]::ReadAllText((Join-Path $root 'readme.md'))
foreach($match in [regex]::Matches($readme,'modules[\\/]([A-Za-z_]+)')){
 $name=$match.Groups[1].Value;$directory=Join-Path $root ('modules/'+$name)
 Assert ((Test-Path -LiteralPath $directory -PathType Container) -and (Get-Item -LiteralPath $directory).Name -ceq $name) ('README 模組路徑存在且大小寫一致：'+$name)
}
foreach($match in [regex]::Matches($readme,'\]\(([^)]+)\)')){
 $link=$match.Groups[1].Value
 if($link -notmatch '^(https?://|#)' -and $link -notmatch '\$| '){$target=($link -split '#')[0];if($target){Assert (Test-Path -LiteralPath (Join-Path $root $target)) ('README 本機連結存在：'+$target)}}
}
# A skipped release ancestor must not suppress main's post-deployment verification.
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$deployment=[regex]::Match($workflow,'(?ms)^  verify-deployment:\s*$(.*?)(?=^  [a-z][a-z-]*:|\z)').Groups[1].Value
$condition=[regex]::Match($deployment,'(?m)^    if: (.+)$').Groups[1].Value
Assert ($condition -match 'always\(\)' -and $condition.Contains("github.ref == 'refs/heads/main'") -and $condition.Contains("needs.publish-reports.result == 'success'")) 'main 公開驗收明確處理略過的祖先工作，且只在發布成功後執行'
Assert ($condition.Contains("startsWith(github.ref, 'refs/tags/v')") -and $deployment.Contains('--mode release') -and $deployment.Contains('--release-metadata')) 'Tag 部署成功後必須執行版本證據驗收'
Write-Host ('ALL PASS: '+$count+' architecture assertions; source inspection and temporary fixture only.')