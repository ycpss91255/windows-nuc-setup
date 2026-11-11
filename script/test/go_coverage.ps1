#Requires -Version 5.1
function Assert-GoCoverage {
 param([Parameter(Mandatory=$true)]$Coverage,[Parameter(Mandatory=$true)]$Report)
 foreach($key in @('SchemaVersion','Scope','Metric','Covered','TotalStatements','Percent','Threshold','Commit','RunUrl','MeasuredAt','SourceState','GoVersion','Environment','ProfileSHA256','Packages')){if($key -notin $Coverage.PSObject.Properties.Name){throw ('Go 覆蓋率缺少欄位：'+$key)}}
 foreach($key in @('SchemaVersion','Covered','TotalStatements','Threshold')){if($Coverage.$key -isnot [int] -and $Coverage.$key -isnot [long]){throw ('Go 覆蓋率必須使用整數：'+$key)}}
 if($Coverage.SchemaVersion -ne 1 -or $Coverage.Scope -cne 'all-owned-go-including-cli' -or $Coverage.Metric -cne 'statements' -or $Coverage.Threshold -ne 80){throw '不支援的 Go 覆蓋率範圍或門檻。'}
 if($Coverage.TotalStatements -le 0 -or $Coverage.Covered -lt 0 -or $Coverage.Covered -gt $Coverage.TotalStatements){throw 'Go 覆蓋率分母或已涵蓋數不合法。'}
 if($Coverage.Percent -isnot [int] -and $Coverage.Percent -isnot [long] -and $Coverage.Percent -isnot [double] -and $Coverage.Percent -isnot [decimal]){throw 'Go 覆蓋率百分比必須是數值。'}
 $calculated=[Math]::Round((100.0*$Coverage.Covered/$Coverage.TotalStatements),1,[MidpointRounding]::AwayFromZero)
 if([double]::IsNaN([double]$Coverage.Percent) -or [double]::IsInfinity([double]$Coverage.Percent) -or [Math]::Abs([double]$Coverage.Percent-$calculated) -gt 0.000001){throw 'Go 覆蓋率百分比與原始數量不一致。'}
 if($Coverage.Commit -cne $Report.Commit -or $Coverage.RunUrl -cne $Report.RunUrl -or $Coverage.SourceState -cne $Report.SourceState){throw 'Go 覆蓋率與報表來源身分不一致。'}
 if($Coverage.Commit -cnotmatch '^[a-fA-F0-9]{40}$' -or $Coverage.SourceState -notin @('Clean','Dirty','Unknown') -or $Coverage.GoVersion -cnotmatch '^go[0-9]+\.[0-9]+\.[0-9]+$' -or $Coverage.ProfileSHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Go 覆蓋率來源格式不合法。'}
 $time=[DateTimeOffset]::MinValue
 if(-not [DateTimeOffset]::TryParse([string]$Coverage.MeasuredAt,[ref]$time)){throw 'Go 覆蓋率量測時間不合法。'}
 if($Coverage.Environment -isnot [string] -or [string]::IsNullOrWhiteSpace($Coverage.Environment) -or $Coverage.Environment -match '[A-Za-z]:[\\/]|[\r\n]'){throw 'Go 量測環境不可包含本機路徑。'}
 $packages=@($Coverage.Packages)
 if(-not $packages.Count -or @($packages|Where-Object {$_ -isnot [string] -or $_ -cnotmatch '^windows_setup/script/[a-z0-9_/]+$'}).Count -or @($packages|Select-Object -Unique).Count -ne $packages.Count){throw 'Go 覆蓋率套件範圍不合法。'}
}
function Get-GoCoveragePercentText {
 param($Coverage)
 return ([double]$Coverage.Percent).ToString('F1',[Globalization.CultureInfo]::InvariantCulture)+'%'
}
function Write-GoCoverageView {
 param($Coverage,[string]$RefType,[string]$OutputDirectory)
 $encoding=[Text.UTF8Encoding]::new($false)
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'go_coverage.json'),($Coverage|ConvertTo-Json -Depth 8),$encoding)
 $label='go coverage';$value=Get-GoCoveragePercentText $Coverage
 $color=Get-GoCoverageColor (100.0*$Coverage.Covered/$Coverage.TotalStatements)
 $left=$label.Length*7+12;$right=$value.Length*7+12;$title=$label+' '+$RefType.ToLowerInvariant()+': '+$value
 $svg=New-CoverageBadgeSvg -Label $label -Value $value -Color $color -Scope $RefType.ToLowerInvariant()
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'go_coverage.svg'),$svg,$encoding)
}

function Assert-GoCoverageProfile {
 param($Coverage,[string]$Directory)
 $profile=Join-Path $Directory 'go_coverage.out'
 if(-not(Test-Path -LiteralPath $profile -PathType Leaf) -or (Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Coverage.ProfileSHA256){throw 'Go 原始覆蓋率 profile 缺少或 SHA256 不符。'}
 $lines=[IO.File]::ReadAllLines($profile)
 if($lines.Count -lt 2 -or $lines[0] -cnotmatch '^mode: (set|count|atomic)$'){throw 'Go profile 模式或內容不合法。'}
 $total=0L;$covered=0L;$seen=@{};$packages=@{}
 foreach($line in $lines[1..($lines.Count-1)]){
  $m=[regex]::Match($line,'^(windows_setup/script/test/(?:[a-z0-9_]+/)+[a-z0-9_]+\.go):([0-9]+\.[0-9]+,[0-9]+\.[0-9]+) ([0-9]+) ([0-9]+)$')
  $statements=0L;$hits=0L
  if(-not $m.Success -or $m.Groups[1].Value.EndsWith('_test.go') -or -not [long]::TryParse($m.Groups[3].Value,[ref]$statements) -or $statements -le 0 -or -not [long]::TryParse($m.Groups[4].Value,[ref]$hits)){throw 'Go profile 含私人路徑、非自有來源或不合法區塊。'}
  $id=$m.Groups[1].Value+':'+$m.Groups[2].Value
  if($seen.ContainsKey($id)){throw 'Go profile 區塊重複。'};$seen[$id]=$true
  $package=$m.Groups[1].Value.Substring(0,$m.Groups[1].Value.LastIndexOf('/'))
  if(@($Coverage.Packages) -cnotcontains $package){throw 'Go profile 含未量測套件。'};$packages[$package]=$true
  $total+=$statements;if($hits -gt 0){$covered+=$statements}
 }
 if($total -ne $Coverage.TotalStatements -or $covered -ne $Coverage.Covered -or $packages.Count -ne @($Coverage.Packages).Count){throw 'Go profile 原始計數或套件與量測不符。'}
}
function Get-GoCoverageColor {
 param([double]$Percent)
 if($Percent -ge 90){return '#4c1'}
 if($Percent -ge 80){return '#97ca00'}
 if($Percent -ge 70){return '#a4a61d'}
 if($Percent -ge 60){return '#dfb317'}
 if($Percent -ge 50){return '#fe7d37'}
 return '#e05d44'
}
function New-CoverageBadgeSvg {
 param([string]$Label,[string]$Value,[string]$Color,[string]$Scope)
 $left=$Label.Length*7+12;$right=$Value.Length*7+12;$width=$left+$right
 $title=[Security.SecurityElement]::Escape($Label+' '+$Scope+': '+$Value)
 $labelText=[Security.SecurityElement]::Escape($Label);$valueText=[Security.SecurityElement]::Escape($Value)
 $x1=[Math]::Floor($left/2);$x2=$left+[Math]::Floor($right/2)
 return '<svg xmlns="http://www.w3.org/2000/svg" width="'+$width+'" height="20" role="img" aria-label="'+$title+'"><title>'+$title+'</title><defs><linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="r"><rect width="'+$width+'" height="20" rx="3" fill="#fff"/></clipPath></defs><g clip-path="url(#r)"><rect width="'+$left+'" height="20" fill="#555"/><rect x="'+$left+'" width="'+$right+'" height="20" fill="'+$Color+'"/><rect width="'+$width+'" height="20" fill="url(#s)"/></g><g fill="#fff" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11" text-anchor="middle"><text x="'+$x1+'" y="15" fill="#010101" fill-opacity=".3">'+$labelText+'</text><text x="'+$x1+'" y="14">'+$labelText+'</text><text x="'+$x2+'" y="15" fill="#010101" fill-opacity=".3">'+$valueText+'</text><text x="'+$x2+'" y="14">'+$valueText+'</text></g></svg>'
}