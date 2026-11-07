#Requires -Version 5.1
function Get-ContainerAcceptancePlan {
 param([string]$ReportDirectory,[string]$FixtureDirectory,[string]$Commit=$env:GITHUB_SHA,[string]$Repository=$env:GITHUB_REPOSITORY,[string]$RunId=$env:GITHUB_RUN_ID,[string]$RefType=$env:GITHUB_REF_TYPE,[string]$RefName=$env:GITHUB_REF_NAME)
 $parts=@($Commit,$Repository,$RunId,$RefType,$RefName|Where-Object {$_})
 if($parts.Count -eq 0){return [pscustomobject]@{Mode='LocalSynthetic';ArtifactDirectory=(Join-Path $FixtureDirectory 'synthetic_snapshot');Commit=('f'*40);RunUrl='https://github.com/example/fixture/actions/runs/1'}}
 if($parts.Count -ne 5 -or $RefType -cnotin @('branch','tag') -or $Commit -notmatch '^[a-fA-F0-9]{40}$' -or $Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $RunId -notmatch '^[0-9]+$'){throw 'Incomplete or invalid CI provenance; refusing to downgrade to local synthetic mode.'}
 [pscustomobject]@{Mode='CIActual';ArtifactDirectory=(Join-Path $ReportDirectory 'public');Commit=$Commit;RunUrl=('https://github.com/'+$Repository+'/actions/runs/'+$RunId)}
}
function Invoke-ContainerPython {
 param([string[]]$Arguments)
 $preference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue'; & python.exe -X utf8 -B @Arguments; $pythonExit=$LASTEXITCODE}finally{$ErrorActionPreference=$preference}
 if($pythonExit -ne 0){throw ('Python acceptance failed with exit code '+$pythonExit)}
}
