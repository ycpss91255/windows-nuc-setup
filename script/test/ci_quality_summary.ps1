#Requires -Version 5.1
function New-CIQualitySummary {
 param($Report,[string]$AggregationState)
 $lines=@('## 同次品質摘要','')
 if($AggregationState -cne 'success' -or $null -eq $Report -or $null -eq $Report.RepoCoverage -or -not $Report.RepoCoverage.Result.Complete){return ($lines+@('**失敗或未提供完整量測。**') -join "`n")}
 $t=$Report.Totals
 $lines+=('斷言：'+$t.AssertionsPassed+'/'+$t.AssertionsExecuted+'；失敗 '+$t.AssertionsFailed)
 if(-not $Report.Success){$lines+='**測試失敗**'}
 $lines+=@('','| 範圍 | 覆蓋率 | 可執行行 |','| --- | ---: | ---: |')
 $r=$Report.RepoCoverage.Result
 $items=@([pscustomobject]@{Name='整體';Covered=$r.Covered;Executable=$r.Executable})+@($r.Languages.PSObject.Properties | Sort-Object Name | ForEach-Object {[pscustomobject]@{Name=$_.Name;Covered=$_.Value.Covered;Executable=$_.Value.Executable}})
 foreach($item in $items){$pct=if($item.Executable -gt 0){(100.0*$item.Covered/$item.Executable).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)+'%'}else{'未量測'};$lines+='| '+$item.Name+' | '+$pct+' | '+$item.Covered+'/'+$item.Executable+' |'}
 if($Report.GoCoverage){$g=$Report.GoCoverage;$lines+=@('',('Go 分項：'+([double]$g.Percent).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)+'%（'+$g.Covered+'/'+$g.TotalStatements+' statements；門檻 80%，與可執行行不同）'))}
 return ($lines -join "`n")
}
