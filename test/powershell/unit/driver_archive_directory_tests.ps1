#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_archive_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_archive_dirs_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$path=Join-Path $fixture 'windows.zip';$zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
try{[void]$zip.CreateEntry('empty\');[void]$zip.CreateEntry('forward/');$entry=$zip.CreateEntry('driver.inf');$stream=$entry.Open();try{$bytes=[Text.Encoding]::UTF8.GetBytes('inert INF');$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
$destination=Join-Path $fixture 'expanded';[void][IO.Directory]::CreateDirectory($destination);$failure=''
try{Expand-DriverArchive -Archive $path -Destination $destination}catch{$failure=$_.Exception.Message}
Assert (-not $failure -and (Test-Path -LiteralPath (Join-Path $destination 'empty') -PathType Container)) ('合法Windows反斜線目錄entry不能被當檔案：'+$failure)
Assert ((Test-Path -LiteralPath (Join-Path $destination 'forward') -PathType Container) -and [IO.File]::ReadAllText((Join-Path $destination 'driver.inf')) -ceq 'inert INF') '正反分隔目錄及正常payload皆正確展開'
