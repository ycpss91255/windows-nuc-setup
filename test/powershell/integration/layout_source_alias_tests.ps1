#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('layout_source_alias_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$archive=Join-Path $fixture 'source.zip';$source=Join-Path $fixture 'source package long'
& git -C $root archive --format=zip ('--output='+$archive) HEAD
if($LASTEXITCODE -ne 0){throw 'Unable to archive the exact tracked source fixture.'}
Expand-Archive -LiteralPath $archive -DestinationPath $source
$long=(Get-Item -LiteralPath $source).FullName
Assert (-not(Test-Path -LiteralPath (Join-Path $long '.git'))) '完整來源ZIP fixture沒有Git中繼資料，真正執行檔案枚舉分支'
$filesystem=New-Object -ComObject Scripting.FileSystemObject
$short=$filesystem.GetFolder($long).ShortPath
$inputs=@([pscustomobject]@{Name='long';Path=$long})
if($short -cne $long){$inputs+=@([pscustomobject]@{Name='short';Path=$short})}
$literalSource=Join-Path $fixture 'source [literal] 中文'
Expand-Archive -LiteralPath $archive -DestinationPath $literalSource
$literalLong=(Get-Item -LiteralPath $literalSource).FullName
$literalShort=$filesystem.GetFolder($literalLong).ShortPath
Assert (-not(Test-Path -LiteralPath (Join-Path $literalLong '.git')) -and (Test-Path -LiteralPath (Join-Path $literalLong 'vendor/golang.org/x/net/LICENSE'))) '含字面括號及中文的完整來源ZIP確實保留必要上游授權'
$inputs+=@([pscustomobject]@{Name='literal_long';Path=$literalLong})
if($literalShort -cne $literalLong){$inputs+=@([pscustomobject]@{Name='literal_short';Path=$literalShort})}
function Invoke-LayoutFixture([string]$PackageRoot,[string]$Name){
 $log=Join-Path $fixture ($Name+'.private.log');$prior=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test/powershell/integration/layout_tests.ps1') -PackageRoot $PackageRoot -SourceOnly *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
 $assertions=@(Get-Content -LiteralPath $log|Where-Object {$_.StartsWith('@@ASSERT@@')}|ForEach-Object {$_.Substring(10)|ConvertFrom-Json})
 [pscustomobject]@{ExitCode=$code;Assertions=$assertions}
}
$baseline=$null
foreach($inputRoot in $inputs){
 $result=Invoke-LayoutFixture $inputRoot.Path ($inputRoot.Name+'_complete')
 Assert ($result.ExitCode -eq 0 -and $result.Assertions.Count -gt 0 -and @($result.Assertions|Where-Object {-not $_.Passed}).Count -eq 0) ('原生 '+$inputRoot.Name+' 套件路徑通過完整來源版面及路由檢查')
 if($null -eq $baseline){$baseline=@($result.Assertions.Name)}else{Assert (($result.Assertions.Name -join "`n") -ceq ($baseline -join "`n")) '相同完整來源內容的長短與字面路徑保留相同斷言集合'}
}
# Remove only these owned fixture files; missing upstream notices must still fail.
foreach($sourceRoot in @($long,$literalLong)){
 $license=Join-Path $sourceRoot 'vendor/golang.org/x/net/LICENSE'
 Remove-Item -LiteralPath $license -Force
}
foreach($inputRoot in $inputs){
 $result=Invoke-LayoutFixture $inputRoot.Path ($inputRoot.Name+'_missing_license')
 $failed=@($result.Assertions|Where-Object {-not $_.Passed})
 Assert ($result.ExitCode -ne 0 -and $failed.Count -eq 1 -and $failed[0].Name -ceq 'official HTML parser license retains upstream spelling: vendor/golang.org/x/net/LICENSE') ('原生 '+$inputRoot.Name+' 路徑不會略過真正缺少的上游授權')
}
$global:LASTEXITCODE=0
