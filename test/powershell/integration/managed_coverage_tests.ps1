#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/test/managed_coverage.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$output=Join-Path ([IO.Path]::GetTempPath()) ('managed_real_'+[guid]::NewGuid().ToString('N'))
$proof=Invoke-ManagedCoverage -SourceRoot $root -OutputDirectory $output
Assert ($proof.SchemaVersion -eq 1 -and $proof.MergeNative -and $proof.Metric -eq 'complete-executable-lines-v1') 'real compiler and native collector produce a versioned counter proof'
Assert ($proof.Sources.Count -eq @(Get-ManagedSourceInventory $root).Count) 'all owned managed source files remain in measured scope'
$artifacts=@(@{Path=$proof.AssemblyPath;Hash=$proof.AssemblySHA256},@{Path=$proof.PDBPath;Hash=$proof.PDBSHA256},@{Path=$proof.CatalogPath;Hash=$proof.CatalogSHA256},@{Path=$proof.MergedBinaryPath;Hash=$proof.MergedBinarySHA256},@{Path=$proof.MergedXmlPath;Hash=$proof.MergedXmlSHA256})
foreach($shard in $proof.Shards){$artifacts+=@(@{Path=$shard.BinaryPath;Hash=$shard.SHA256},@{Path=$shard.XmlPath;Hash=$shard.XmlSHA256})}
foreach($artifact in $artifacts){Assert ($artifact.Path -notmatch '^[/\\]|^[A-Za-z]:' -and (Get-FileHash -LiteralPath (Join-Path $output $artifact.Path)).Hash.ToLowerInvariant() -ceq $artifact.Hash) ('actual native artifact has canonical path and matching digest: '+$artifact.Path)}
$catalog=[IO.File]::ReadAllText((Join-Path $output $proof.CatalogPath))|ConvertFrom-Json
Assert ($catalog.Documents.Count -eq $proof.Sources.Count -and $catalog.Methods.Count -gt 0 -and $catalog.PDBContentID -ceq $catalog.PEPDBContentID) 'independent complete compiler PDB catalog accompanies the measured assembly'
[xml]$xml=[IO.File]::ReadAllText((Join-Path $output $proof.MergedXmlPath))
$modules=@($xml.results.modules.module)
Assert ($modules.Count -eq 1 -and $modules[0].name -eq 'windows_setup_managed.dll') 'instrumentation measures owned production assembly without test harness pollution'
Assert (@($modules[0].source_files.source_file).Count -eq $proof.Sources.Count) 'native XML retains sources even when managed methods are not hit'
Assert (@($xml.SelectNodes('//range')).Count -gt 0 -and @($xml.SelectNodes('//range[@covered="yes"]')).Count -gt 0) 'original managed statements record actual runtime hits'
Write-Host ('ALL PASS: '+$script:count+' real managed collection assertions; private raw evidence stays in TEMP')