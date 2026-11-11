#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo='ycpss91255/windows_setup'
$target='a77bf7bdcb724998a87aedede644f3201b80a5bd'
$nonce=[guid]::NewGuid().ToString('N')
$dir=Join-Path $env:RUNNER_TEMP ('issue103_probe_'+$nonce)
New-Item -ItemType Directory -Path $dir | Out-Null
"evidence=$dir" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
$utf8=[Text.UTF8Encoding]::new($false)
function Invoke-ProbeApi([string]$Name,[string[]]$Arguments) {
 $output=@(& gh api @Arguments)
 if($LASTEXITCODE -ne 0){throw "API request failed: $Name"}
 [IO.File]::WriteAllText((Join-Path $dir ($Name+'.json')),($output -join "`n"),$utf8)
 return (($output -join "`n")|ConvertFrom-Json)
}
function New-Payload([string]$Name,$Value) {
 $path=Join-Path $dir ($Name+'.json')
 [IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Compress -Depth 5),$utf8)
 return $path
}
function Assert-Probe($Record,[long]$Id,[string]$Tag,[string]$Marker,[bool]$AllowUntagged=$false) {
 $validTag=$Record.tag_name -ceq $Tag -or ($AllowUntagged -and $Record.tag_name -cmatch '^untagged-[a-f0-9]+$')
 if(($Record.id -isnot [int] -and $Record.id -isnot [long]) -or $Record.id -ne $Id -or -not $validTag -or $Record.target_commitish -cne $target -or $Record.name -cne $Tag -or $Record.body -isnot [string] -or -not $Record.body.StartsWith($Marker,[StringComparison]::Ordinal) -or $Record.draft -isnot [bool] -or -not $Record.draft -or $Record.immutable -isnot [bool] -or $Record.immutable -or $Record.prerelease -isnot [bool] -or $Record.prerelease){throw 'Probe identity or state mismatch; preserve all resources.'}
}
function Assert-Ref($Value,[string]$Tag) {
 if($Value.ref -cne ('refs/tags/'+$Tag) -or $Value.object.type -cne 'commit' -or $Value.object.sha -cne $target){throw 'Probe ref mismatch; preserve all resources.'}
}
$records=@{}
foreach($case in @('a','b')) {
 $tag='ci_api_probe_'+$nonce+'_'+$case
 $marker='owner_probe_'+$nonce+'_'+$case
 $refPayload=New-Payload ('ref_request_'+$case) ([ordered]@{ref=('refs/tags/'+$tag);sha=$target})
 $ref=Invoke-ProbeApi ('ref_create_'+$case) @(('repos/'+$repo+'/git/refs'),'--method','POST','--input',$refPayload)
 Assert-Ref $ref $tag
 $ref=Invoke-ProbeApi ('ref_before_create_'+$case) @('repos/'+$repo+'/git/ref/tags/'+$tag)
 Assert-Ref $ref $tag
 $createPayload=New-Payload ('create_request_'+$case) ([ordered]@{tag_name=$tag;target_commitish=$target;name=$tag;body=$marker;draft=$true;prerelease=$false})
 $created=Invoke-ProbeApi ('create_response_'+$case) @(('repos/'+$repo+'/releases'),'--method','POST','--input',$createPayload)
 if(($created.id -isnot [int] -and $created.id -isnot [long]) -or $created.id -le 0){throw 'Invalid created ID; preserve resources.'}
 $id=[long]$created.id
 Assert-Probe $created $id $tag $marker
 $before=Invoke-ProbeApi ('before_'+$case) @('repos/'+$repo+'/releases/'+$id)
 Assert-Probe $before $id $tag $marker
 $ref=Invoke-ProbeApi ('ref_before_patch_'+$case) @('repos/'+$repo+'/git/ref/tags/'+$tag)
 Assert-Ref $ref $tag
 $payload=[ordered]@{target_commitish=$target;name=$tag;prerelease=$false;draft=$true;body=($marker+' notes')}
 if($case -ceq 'b'){$payload['tag_name']=$tag}
 if($payload.draft -isnot [bool] -or -not $payload.draft){throw 'Probe must remain draft.'}
 $path=New-Payload ('patch_request_'+$case) $payload
 $response=Invoke-ProbeApi ('patch_response_'+$case) @(('repos/'+$repo+'/releases/'+$id),'--method','PATCH','--input',$path)
 Assert-Probe $response $id $tag $marker ($case -ceq 'a')
 $after=Invoke-ProbeApi ('after_'+$case) @('repos/'+$repo+'/releases/'+$id)
 Assert-Probe $after $id $tag $marker ($case -ceq 'a')
 if($response.tag_name -cne $after.tag_name -or $after.body -cne ($marker+' notes')){throw 'Probe response and readback mismatch.'}
 $ref=Invoke-ProbeApi ('ref_after_patch_'+$case) @('repos/'+$repo+'/git/ref/tags/'+$tag)
 Assert-Ref $ref $tag
 $records[$case]=[ordered]@{id=$id;originalTag=$tag;afterTag=$after.tag_name;target=$target;marker=$marker}
}
[IO.File]::WriteAllText((Join-Path $dir 'result.json'),($records|ConvertTo-Json -Depth 5),$utf8)
Write-Host 'Draft-only comparison completed; no resource was published or deleted.'
