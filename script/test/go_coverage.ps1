#Requires -Version 5.1
function Assert-GoCoverage {
 param([Parameter(Mandatory=$true)]$Coverage,[Parameter(Mandatory=$true)]$Report)
 foreach($key in @('SchemaVersion','Scope','Metric','CoveredStatements','TotalStatements','Percent','Threshold','Commit','RunUrl','MeasuredAt','SourceState','GoVersion','Environment','ProfileSHA256','Packages')){if($key -notin $Coverage.PSObject.Properties.Name){throw ('Go 覆蓋率缺少欄位：'+$key)}}
 foreach($key in @('SchemaVersion','CoveredStatements','TotalStatements','Threshold')){if($Coverage.$key -isnot [int] -and $Coverage.$key -isnot [long]){throw ('Go 覆蓋率必須使用整數：'+$key)}}
 if($Coverage.SchemaVersion -ne 1 -or $Coverage.Scope -cne 'all-owned-go-including-cli' -or $Coverage.Metric -cne 'statements' -or $Coverage.Threshold -ne 80){throw '不支援的 Go 覆蓋率範圍或門檻。'}
 if($Coverage.TotalStatements -le 0 -or $Coverage.CoveredStatements -lt 0 -or $Coverage.CoveredStatements -gt $Coverage.TotalStatements){throw 'Go 覆蓋率分母或已涵蓋數不合法。'}
 if($Coverage.Percent -isnot [int] -and $Coverage.Percent -isnot [long] -and $Coverage.Percent -isnot [double] -and $Coverage.Percent -isnot [decimal]){throw 'Go 覆蓋率百分比必須是數值。'}
 $calculated=[Math]::Round((100.0*$Coverage.CoveredStatements/$Coverage.TotalStatements),1,[MidpointRounding]::AwayFromZero)
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
 $label='go coverage '+$RefType.ToLowerInvariant();$value=Get-GoCoveragePercentText $Coverage
 $color=if(([decimal]$Coverage.CoveredStatements*100) -ge ([decimal]$Coverage.TotalStatements*$Coverage.Threshold)){'#4c1'}else{'#e05d44'}
 $left=$label.Length*7+12;$right=$value.Length*7+12;$title=$label+': '+$value
 $svg='<svg xmlns="http://www.w3.org/2000/svg" width="'+($left+$right)+'" height="20" role="img" aria-label="'+$title+'"><title>'+$title+'</title><rect width="'+$left+'" height="20" fill="#555"/><rect x="'+$left+'" width="'+$right+'" height="20" fill="'+$color+'"/><g fill="#fff" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11" text-anchor="middle"><text x="'+[Math]::Floor($left/2)+'" y="14">'+$label+'</text><text x="'+($left+[Math]::Floor($right/2))+'" y="14">'+$value+'</text></g></svg>'
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'go_coverage.svg'),$svg,$encoding)
}
