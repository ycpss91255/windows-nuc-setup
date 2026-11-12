#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$job=[regex]::Match($workflow,'(?ms)^  verify-deployment:\s*$(.*?)(?=^  [a-z][a-z-]*:|\z)').Groups[1].Value
$condition=[regex]::Match($job,'(?m)^    if: (.+)$').Groups[1].Value
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Evaluate([string]$Event,[string]$Ref,[string]$Deployment){
 $expr=$condition
 $expr=$expr.Replace('always()', '$true')
 $expr=$expr.Replace("startsWith(github.ref, 'refs/tags/v')", $(if($Ref.StartsWith('refs/tags/v')){'$true'}else{'$false'}))
 $expr=$expr.Replace("github.event_name == 'push'", $(if($Event -ceq 'push'){'$true'}else{'$false'}))
 $expr=$expr.Replace("github.ref == 'refs/heads/main'", $(if($Ref -ceq 'refs/heads/main'){'$true'}else{'$false'}))
 $expr=$expr.Replace("needs.publish-reports.result == 'success'", $(if($Deployment -ceq 'success'){'$true'}else{'$false'}))
 $expr=$expr.Replace('&&','-and').Replace('||','-or')
 if($expr -notmatch '^[\s\$truefals()\-andor]+$'){throw ('unexpected workflow condition: '+$expr)}
 return [bool](& ([scriptblock]::Create($expr)))
}
foreach($c in @(
 @{Event='push';Ref='refs/heads/main';Deploy='success';Expected=$true;Name='main success'},
 @{Event='push';Ref='refs/tags/v0.2.4';Deploy='success';Expected=$true;Name='tag success'},
 @{Event='push';Ref='refs/tags/v0.2.4';Deploy='failure';Expected=$false;Name='tag failed deploy'},
 @{Event='pull_request';Ref='refs/tags/v0.2.4';Deploy='success';Expected=$false;Name='PR tag-like ref'},
 @{Event='workflow_dispatch';Ref='refs/heads/main';Deploy='success';Expected=$false;Name='manual main'},
 @{Event='push';Ref='refs/heads/feature';Deploy='success';Expected=$false;Name='feature branch'}
)){Assert ((Evaluate $c.Event $c.Ref $c.Deploy) -eq $c.Expected) ('deployment condition: '+$c.Name)}
