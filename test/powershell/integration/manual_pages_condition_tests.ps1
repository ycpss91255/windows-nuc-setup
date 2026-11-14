#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Condition([string]$Job){$body=[regex]::Match($workflow,('(?ms)^  '+[regex]::Escape($Job)+':\s*$(.*?)(?=^  [a-z][a-z-]*:|\z)')).Groups[1].Value;return [regex]::Match($body,'(?m)^    if: (.+)$').Groups[1].Value}
function Evaluate([string]$Expression,[string]$Event,[string]$Ref,[string]$Rollup,[string]$Release){
 $expr=$Expression.Replace('always()','$true')
 $expr=$expr.Replace("startsWith(github.ref, 'refs/tags/')",$(if($Ref.StartsWith('refs/tags/')){'$true'}else{'$false'}))
 foreach($candidate in @('push','workflow_dispatch')){$expr=$expr.Replace("github.event_name == '$candidate'",$(if($Event -ceq $candidate){'$true'}else{'$false'}))}
 $expr=$expr.Replace("github.ref == 'refs/heads/main'",$(if($Ref -ceq 'refs/heads/main'){'$true'}else{'$false'}))
 $expr=$expr.Replace("needs.ci-rollup.result == 'success'",$(if($Rollup -ceq 'success'){'$true'}else{'$false'}))
 $expr=$expr.Replace("needs.release.result == 'success'",$(if($Release -ceq 'success'){'$true'}else{'$false'}))
 $expr=$expr.Replace('&&','-and').Replace('||','-or')
 if($expr -notmatch '^[\s\$truefals()\-andor]+$'){throw ('unexpected condition: '+$expr)}
 return [bool](& ([scriptblock]::Create($expr)))
}
$build=Condition 'build-portal';$release=Condition 'release'
foreach($c in @(
 @{Event='workflow_dispatch';Ref='refs/heads/main';Rollup='success';Release='skipped';Build=$true;Publish=$false;Name='手動 main 門檻通過'},
 @{Event='workflow_dispatch';Ref='refs/heads/main';Rollup='failure';Release='skipped';Build=$false;Publish=$false;Name='手動 main 門檻失敗'},
 @{Event='workflow_dispatch';Ref='refs/heads/feature';Rollup='success';Release='skipped';Build=$false;Publish=$false;Name='手動非 main'},
 @{Event='workflow_dispatch';Ref='refs/tags/v0.2.5';Rollup='success';Release='success';Build=$false;Publish=$false;Name='手動 tag'},
 @{Event='merge_group';Ref='refs/heads/gh-readonly-queue/main/pr-123-0123456789abcdef';Rollup='success';Release='success';Build=$false;Publish=$false;Name='merge queue'},
 @{Event='pull_request';Ref='refs/heads/main';Rollup='success';Release='success';Build=$false;Publish=$false;Name='PR'},
 @{Event='push';Ref='refs/heads/main';Rollup='success';Release='skipped';Build=$true;Publish=$false;Name='原 main push'},
 @{Event='push';Ref='refs/tags/v0.2.5';Rollup='success';Release='success';Build=$true;Publish=$true;Name='原 tag push'},
 @{Event='push';Ref='refs/tags/v0.2.5';Rollup='success';Release='failure';Build=$false;Publish=$true;Name='tag 發布失敗'}
)){Assert ((Evaluate $build $c.Event $c.Ref $c.Rollup $c.Release) -eq $c.Build) ('建立入口條件 '+$c.Name);Assert ((Evaluate $release $c.Event $c.Ref $c.Rollup $c.Release) -eq $c.Publish) ('版本發布條件 '+$c.Name)}
