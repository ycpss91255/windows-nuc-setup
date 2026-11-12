#Requires -Version 5.1
# 共用版本與人工整理的變更紀錄契約，不執行 Git 寫入。
function Get-ReleaseVersion([string]$Version) {
 if($Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'){throw '版本必須是 vX.Y.Z 或 vX.Y.Z-rcN。'}
 [pscustomobject]@{Version=$Version;Base=($Version -replace '-rc[0-9]+$','');Prerelease=($Version -match '-rc[0-9]+$')}
}
function Get-ReleaseReportLink([string]$Version) {
 $null=Get-ReleaseVersion $Version
 return ('[此版本測試報表](https://github.com/ycpss91255/windows_setup/releases/download/'+$Version+'/windows_setup_report_'+$Version+'.zip)')
}
function Assert-ReleaseReportLink([string]$Version,[string]$Notes) {
 $expected=(Get-ReleaseReportLink $Version)+"`n`n"
 if($Notes -isnot [string] -or -not $Notes.StartsWith($expected,[StringComparison]::Ordinal)){throw '版本說明缺少正確的該版報表入口。'}
}
function Get-ReleaseNotes([string]$Version,[string]$Changelog) {
 $info=Get-ReleaseVersion $Version
 $sections=@([regex]::Matches($Changelog,'(?ms)^## (?:\[(?<version>v[^\]\r\n]+)\]|(?<version>v\S+))[^\r\n]*\r?\n(?<body>.*?)(?=^## |\z)'))
 $exact=@($sections|Where-Object {$_.Groups['version'].Value -ceq $Version})
 if($exact.Count -ne 1){throw '變更紀錄必須有且只有一個當版章節。'}
 $selected=@($exact)
 if(-not $info.Prerelease){$selected+=@($sections|Where-Object {$_.Groups['version'].Value -cmatch ('^'+[regex]::Escape($Version)+'-rc[1-9][0-9]*$')})}
 if(@($selected | Group-Object { $_.Groups['version'].Value } | Where-Object Count -gt 1).Count){throw 'RC 版本章節重複。'}
 $lead='';$categories=[ordered]@{}
 foreach($section in $selected){
  $body=$section.Groups['body'].Value.Trim()
  $intro=([regex]::Split($body,'(?m)^### '))[0].Trim()
  if($body.StartsWith('### ')){$intro=''}
  if($section -eq $exact[0] -or $intro -match '(?m)^- \S'){$lead+="`n`n"+$intro}
  foreach($part in [regex]::Matches($body,'(?ms)^### (?<category>[^\r\n]+)\r?\n(?<body>.*?)(?=^### |\z)')){
   $key=$part.Groups['category'].Value.Trim();$content=$part.Groups['body'].Value.Trim()
   if($categories.Contains($key)){$categories[$key]+="`n`n"+$content}else{$categories[$key]=$content}
  }
 }
 $notes=$lead
 foreach($key in $categories.Keys){$notes+="`n`n### $key`n`n"+$categories[$key]}
 $notes=$notes.Trim()
 if($notes -notmatch '(?m)^- \S'){throw '版本說明沒有任何變更條目，拒絕空白發布。'}
 if($notes.Length -gt 125000){throw '版本說明超過 GitHub 長度上限。'}
 return $notes
}
function Assert-ReleaseOnMain([string]$PackageRoot,[string]$Revision='HEAD',[string]$MainRef='refs/remotes/origin/main') {
 & git -C $PackageRoot merge-base --is-ancestor $Revision $MainRef
 if($LASTEXITCODE -ne 0){throw '發布提交不屬於 main 歷史，或 main 尚未完整取得。'}
}
