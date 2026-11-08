#Requires -Version 5.1
$ErrorActionPreference='Stop'
$library=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_launcher_library.ps1'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert (Test-Path -LiteralPath $library) 'public launcher implementation can be loaded without executing UAC'
. $library
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_launcher_'+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $temp '中文 空白 stage';New-Item -ItemType Directory -Path $stage -Force|Out-Null
function Assert-InitPlainPath {param($Path)}
function Assert-InitProtectedDirectory {param($Path)}
$script:protected=$false
function Protect-InitPublicLauncher {param($Path) $script:protected=$true}
function Assert-InitPublicLauncherAcl {param($Path) if(-not $script:protected){throw 'synthetic untrusted ACL'}}
$path=New-InitPublicLauncher -StageRoot $stage
Assert ($path -eq ($stage+'.cmd') -and (Test-Path -LiteralPath $path)) 'public launcher is a sibling outside private root'
$text=[IO.File]::ReadAllText($path)
$match=[regex]::Match($text,'-EncodedCommand ([A-Za-z0-9+/=]+)')
Assert $match.Success 'CMD carries a Unicode-safe encoded bootstrap'
$bootstrap=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($match.Groups[1].Value))
$script:captured=$null
function Start-Process {param($FilePath,$Verb,$ArgumentList,[switch]$Wait) $script:captured=@{File=$FilePath;Verb=$Verb;Arguments=$ArgumentList;Wait=$Wait}}
& ([scriptblock]::Create($bootstrap))
Assert ($script:captured.Verb -eq 'RunAs' -and $script:captured.Wait) 'bootstrap requests UAC before reading private runtime'
$encoded=[regex]::Match($script:captured.Arguments,'-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
$command=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
Assert ($command.Contains((Join-Path $stage 'runtime\modules\init\initialize_nuc.ps1')) -and $command.Contains((Join-Path $stage 'state.json'))) 'elevated command preserves exact Chinese and space paths'
Assert ($command.Contains('-ExpectedUserSID') -and $command.Contains([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) 'elevation forwards the original dynamic user SID'
Assert ($command -notmatch '-UserName|-Password') 'launcher contains no account name or password'
Assert ((New-InitPublicLauncher -StageRoot $stage) -eq $path) 'trusted exact launcher is reusable'
[IO.File]::AppendAllText($path,'tamper')
$before=[IO.File]::ReadAllText($path);$rejected=$false
try{New-InitPublicLauncher -StageRoot $stage}catch{$rejected=$true}
Assert ($rejected -and [IO.File]::ReadAllText($path) -ceq $before) 'existing altered launcher is rejected without overwrite'
Write-Host ('ALL PASS: '+$script:count+' launcher assertions; TEMP and UAC/ACL mocks only')
