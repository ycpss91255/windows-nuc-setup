#Requires -Version 5.1
# 共用版本與人工整理的變更紀錄契約，不執行 Git 寫入。
function Get-ReleaseVersion([string]$Version) {
 if($Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'){throw '版本必須是 vX.Y.Z 或 vX.Y.Z-rcN。'}
 [pscustomobject]@{Version=$Version;Base=($Version -replace '-rc[0-9]+$','');Prerelease=($Version -match '-rc[0-9]+$')}
}
function Get-ReleaseDownloadGuide([string]$Version) {
 $null=Get-ReleaseVersion $Version
 $guide="## $Version 下載與使用`n`n- 通用工具：下載 Source code ZIP，依 README 另行取得 Microsoft 官方 Autologon；來源 ZIP 不含 Autologon。`n- 測試報表：在 Assets 下載本版本報表 ZIP。"
 if($Version -ceq 'v0.2.5'){$guide+="`n- 可選驅動：Assets 的 NUC8 驅動包適用 NUC8i7HVK／NUC8i7HNK，主機板 HVB／HNB。"}
 return $guide
}
function Assert-ReleaseDownloadGuide([string]$Version,[string]$Notes) {
 $expected=(Get-ReleaseDownloadGuide $Version)+"`n`n"
 if(-not $Notes.StartsWith($expected,[StringComparison]::Ordinal)){throw '版本說明缺少正確的下載指引。'}
}
function Get-UserFacingReleaseNotes([string]$Version,[string]$Changelog) {
 $body=Get-ReleaseNotes $Version $Changelog
 if($Version -ceq 'v0.2.5'){
  $omit=@(
   '- Actions 執行名稱清楚標示觸發事件與來源。',
   '- 版本發布自動封裝同次原生與容器測試報告，驗證後以單一 ZIP 保存，版本說明直接提供下載。',
   '- 維護者可先核對不可變附件摘要，再驗證歷史報表 ZIP 及其中記載的執行脈絡。',
   '- 維護者可將完整驗證後的報表 ZIP 原始檔與摘要輸出至專用目錄，供後續消費者核對。',
   '- 維護工具可將同次 Windows 原生與容器的公開測試證據封裝、核對為版本專屬 ZIP，保留原始內容與容器未量測狀態。',
   '- 新版本的 Release 說明頂端提供該版本專屬測試報表入口，方便查看對應的測試與覆蓋率證據。',
   '- 標籤部署後驗證公開版本頁、同次來源與不可變 Release 證據，缺件、來源不符或覆蓋率未達門檻時不再回報部署驗收成功。'
  )
  foreach($line in $omit){$body=$body.Replace($line,'')}
  $body=[regex]::Replace($body,'(?ms)^### Added（新增）\s*(?=^### |\z)','').Trim()
 }
 return (Get-ReleaseDownloadGuide $Version)+"`n`n"+$body
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
