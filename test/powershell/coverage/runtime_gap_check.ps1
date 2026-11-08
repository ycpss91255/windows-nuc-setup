#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$BaselineXml,[Parameter(Mandatory=$true)][string]$BaselineEvidence,[Parameter(Mandatory=$true)][string]$CoverageXml,[Parameter(Mandatory=$true)][string]$Evidence,[int]$MinimumNewLines=120)
$ErrorActionPreference='Stop'
$files=@('modules/init/provisioning_library.ps1','core/gui_stage_library.ps1','core/hardware.ps1','modules/updates/update_stage_library.ps1')
$before=Get-Content -LiteralPath $BaselineEvidence -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $Evidence -Raw -Encoding UTF8|ConvertFrom-Json
[xml]$beforeXml=Get-Content -LiteralPath $BaselineXml -Raw -Encoding UTF8
[xml]$afterXml=Get-Content -LiteralPath $CoverageXml -Raw -Encoding UTF8
$delta=0;$total=0;$covered=0
foreach($file in $files){
 $old=@($before.Sources|Where-Object File -ceq $file);$new=@($after.Sources|Where-Object File -ceq $file)
 if($old.Count -ne 1 -or $new.Count -ne 1 -or $old[0].SHA256 -cne $new[0].SHA256 -or ($old[0].ExpectedLines -join ',') -cne ($new[0].ExpectedLines -join ',')){throw ('來源或完整分母不一致：'+$file)}
 $oldClass=@($beforeXml.coverage.packages.package.classes.class|Where-Object {$_.filename.Replace('\','/') -ceq $file})
 $newClass=@($afterXml.coverage.packages.package.classes.class|Where-Object {$_.filename.Replace('\','/') -ceq $file})
 if($oldClass.Count -ne 1 -or $newClass.Count -ne 1){throw ('來源缺少原檔XML：'+$file)}
 $oldHits=[Collections.Generic.HashSet[int]]::new();$newHits=[Collections.Generic.HashSet[int]]::new()
 foreach($line in $oldClass[0].lines.line){if([int]$line.hits -gt 0){[void]$oldHits.Add([int]$line.number)}}
 foreach($line in $newClass[0].lines.line){if([int]$line.hits -gt 0){[void]$newHits.Add([int]$line.number)}}
 $added=@($new[0].ExpectedLines|Where-Object {$newHits.Contains([int]$_) -and -not $oldHits.Contains([int]$_)})
 $union=@($new[0].ExpectedLines|Where-Object {$newHits.Contains([int]$_) -or $oldHits.Contains([int]$_)})
 $delta+=$added.Count;$total+=$new[0].ExpectedLines.Count;$covered+=$union.Count
 Write-Host ($file+' 新命中 '+$added.Count+'；完整分母 '+$new[0].ExpectedLines.Count+'；新行 '+($added -join ','))
}
Write-Host ('原始行集合OR聯集 '+$covered+'/'+$total+'；真正新增 '+$delta+'，沒有相加重複命中。')
if($delta -lt $MinimumNewLines){throw ('尚缺有意義的runtime安全案例：新增'+$delta+'，門檻'+$MinimumNewLines)}
