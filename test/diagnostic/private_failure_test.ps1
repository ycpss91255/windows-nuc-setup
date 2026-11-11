#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('private-pester-test-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source';[void][IO.Directory]::CreateDirectory($source)
function Assert-PrivateFailure([bool]$Value,[string]$Name){if(-not $Value){throw $Name};Write-Output ('PASS '+$Name)}
foreach($directory in @('core','script/test','test/diagnostic','test/powershell/unit','test/powershell/coverage')){[void][IO.Directory]::CreateDirectory((Join-Path $source $directory))}
foreach($name in @('powershell_coverage.ps1','powershell_worker_diagnostics.ps1')){Copy-Item -LiteralPath (Join-Path $root ('script/test/'+$name)) -Destination (Join-Path $source ('script/test/'+$name))}
$snapshotSource=Join-Path $PSScriptRoot 'private_pester_snapshot.ps1'
if(Test-Path -LiteralPath $snapshotSource -PathType Leaf){Copy-Item -LiteralPath $snapshotSource -Destination (Join-Path $source 'test/diagnostic/private_pester_snapshot.ps1')}
[IO.File]::WriteAllText((Join-Path $source 'core/example.ps1'),'function Example { return 1 }')
[IO.File]::WriteAllText((Join-Path $source 'test/powershell/unit/example_tests.ps1'),'throw ''test body must not run''')
$marker='PRIVATE_RUNTIME_MARKER_'+[guid]::NewGuid().ToString('N')
$wrapper="param(`$SuitePath,`$SourceRoot)`nBeforeAll { throw '$marker' }`nDescribe 'fixture' { It 'never runs' { 1 | Should-Be 1 } }"
[IO.File]::WriteAllText((Join-Path $source 'test/powershell/coverage/safe_suite.ps1'),$wrapper,[Text.UTF8Encoding]::new($false))
$manifestPath=Join-Path $fixture 'manifest.json'
$manifest=@{SourceRoot=$source;Sources=@('core/example.ps1');Tests=@('test/powershell/unit/example_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$savedFlag=$env:WINDOWS_SETUP_PRIVATE_FAILURE_DIAGNOSTIC;$savedPackage=$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH
try{
 $env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=Join-Path ([IO.Path]::GetTempPath()) 'windows_setup_pester_6_0_0/pester.zip'
 if(-not(Test-Path -LiteralPath $env:WINDOWS_SETUP_PESTER_PACKAGE_PATH -PathType Leaf)){throw 'Pinned package precondition missing.'}
 foreach($flag in @('1','0')){
  $env:WINDOWS_SETUP_PRIVATE_FAILURE_DIAGNOSTIC=$flag
  if($flag -ceq '0'){
   $copied=Join-Path $source 'test/diagnostic/private_pester_snapshot.ps1'
   if(Test-Path -LiteralPath $copied){
    if(-not [IO.Path]::GetFullPath($copied).StartsWith([IO.Path]::GetFullPath($fixture)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture removal escaped owned root.'}
    Remove-Item -LiteralPath $copied
   }
  }
  $output=Join-Path $fixture ('private_'+$flag);$stdout=Join-Path $fixture ('manager_'+$flag+'.stdout');$stderr=Join-Path $fixture ('manager_'+$flag+'.stderr')
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'script/test/powershell_coverage.ps1'),'-ManifestPath',$manifestPath,'-OutputDirectory',$output)
  $process=Start-Process -FilePath powershell.exe -ArgumentList @($args|ForEach-Object {'"'+$_+'"'}) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $null=$process.Handle
  if(-not $process.WaitForExit(120000)){$process.Kill();[void]$process.WaitForExit(5000);throw 'Native diagnostic fixture exceeded deadline.'}
  Assert-PrivateFailure ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) 'original native failure remains nonzero'
  $publicText=[IO.File]::ReadAllText($stdout)+[IO.File]::ReadAllText($stderr)
  Assert-PrivateFailure (-not $publicText.Contains($marker)) 'original error message never enters manager public streams'
  $raw=Join-Path $output 'worker_0.private.error.json'
  if($flag -ceq '1'){
   Assert-PrivateFailure (Test-Path -LiteralPath $raw -PathType Leaf) 'enabled flag writes the actual private ErrorRecord'
   $snapshot=Get-Content -LiteralPath $raw -Raw -Encoding UTF8|ConvertFrom-Json
   Assert-PrivateFailure ($snapshot.Errors.Count -ge 1 -and $snapshot.Errors[0].Message.Contains($marker) -and $snapshot.Errors[0].ExceptionDetail.Contains($marker)) 'private message and exception detail preserve the original runtime reason'
   Assert-PrivateFailure ([bool]$snapshot.Errors[0].ExceptionType -and [bool]$snapshot.Errors[0].FullyQualifiedErrorId -and [bool]$snapshot.Errors[0].ScriptStackTrace) 'private snapshot retains exception identity and original stack'
  }else{Assert-PrivateFailure (-not(Test-Path -LiteralPath $raw)) 'disabled flag writes nothing and needs no snapshot helper'}
 }
 $direct=Join-Path $fixture 'worker_99.private.error.json';$records=@()
 for($i=0;$i -lt 20;$i++){$records+=@([Management.Automation.ErrorRecord]::new([Exception]::new([string]::new([char]0x6f22,30000)),('fixture_'+$i),[Management.Automation.ErrorCategory]::NotSpecified,$null))}
 & $snapshotSource -Path $direct -InvocationErrors $records
 $bounded=Get-Content -LiteralPath $direct -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-PrivateFailure ($bounded.Errors.Count -eq 16) 'private error collection has a sixteen-record limit'
 foreach($row in $bounded.Errors){foreach($property in $row.PSObject.Properties){if($property.Value -is [string]){Assert-PrivateFailure ([Text.Encoding]::UTF8.GetByteCount($property.Value) -le 65536) 'each private UTF8 field is at most sixty-four KiB'}}}
 $empty=Join-Path $fixture 'worker_100.private.error.json'
 try{throw 'unrelated old global error'}catch{}
 & $snapshotSource -Path $empty -InvocationErrors @()
 $none=Get-Content -LiteralPath $empty -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-PrivateFailure ($none.Errors.Count -eq 0) 'snapshot never borrows an unrelated global error'
}finally{$env:WINDOWS_SETUP_PRIVATE_FAILURE_DIAGNOSTIC=$savedFlag;$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$savedPackage}
