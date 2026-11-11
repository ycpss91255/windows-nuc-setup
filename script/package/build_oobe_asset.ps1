#Requires -Version 5.1
param([string]$CompilerPath,[string]$OutputDirectory)
# Maintainer-only source. Dot-sourcing defines functions; it never invokes ICD.
# No download, installation, account operation, or package application is performed.
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\modules\init\provisioning_asset_library.ps1')))
function Get-InitBuildCompilerIdentity {
 param([string]$Path)
 $signature=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
 return [pscustomobject]@{Status=[string]$signature.Status;Subject=[string]$signature.SignerCertificate.Subject;SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;Version=(Get-Item -LiteralPath $Path).VersionInfo.FileVersion}
}
function Invoke-BuildOobeAsset {
 param([Parameter(Mandatory=$true)][string]$CompilerPath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
 $ErrorActionPreference='Stop'
 $compiler=[IO.Path]::GetFullPath($CompilerPath);$output=[IO.Path]::GetFullPath($OutputDirectory)
 $store=Join-Path (Split-Path $compiler -Parent) 'Microsoft-Desktop-Provisioning.dat'
 foreach($path in @($compiler,$store)){Assert-InitAssetPlainPath $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('缺少已安裝或已備妥的官方 WCD 檔案：'+$path)}}
 Assert-InitAssetPlainPath $output
 if(Test-Path -LiteralPath $output){throw '輸出路徑已存在；請指定新的空白路徑，不覆寫既有產物。'}
 $identity=Get-InitBuildCompilerIdentity $compiler
 if($identity.Status -ne 'Valid' -or $identity.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)' -or $identity.SHA256 -cne 'E89F844A375BBEF9D5D98AE3920C68CFB75973FCA0CAC1202354A8AEA36842F0' -or $identity.Version -ne '10.0.26100.9457'){throw 'WCD compiler 簽章、發行者、版本或固定 SHA256 不符；未建立輸出。'}
 New-Item -ItemType Directory -Path $output|Out-Null
 $source=Join-Path $output 'hide_oobe.xml';$package=Join-Path $output 'hide_oobe.ppkg'
 [IO.File]::WriteAllText($source,(Get-InitProvisioningSourceXml),(New-Object Text.UTF8Encoding($false)))
 $arguments='/Build-ProvisioningPackage /CustomizationXML:"'+$source+'" /PackagePath:"'+$package+'" /StoreFile:"'+$store+'"'
 $process=Start-Process -FilePath $compiler -ArgumentList $arguments -WorkingDirectory $output -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $output 'compiler_stdout.log') -RedirectStandardError (Join-Path $output 'compiler_stderr.log')
 if($process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $package -PathType Leaf)){throw 'WCD 編譯失敗；保留本次目錄供檢查，不產生成功來源紀錄。'}
 $manifest=New-InitProvisioningProvenance -SourcePath $source -PackagePath $package
 [IO.File]::WriteAllText((Join-Path $output 'provenance.json'),($manifest|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
 $verified=Assert-InitProvisioningAsset -AssetRoot $output
 Write-Host '建置與來源／metadata 驗證完成；未套用設定包。內容仍須由 CI 唯讀 WIM 驗證。' -ForegroundColor Green
 return $verified
}
if($MyInvocation.InvocationName -ne '.'){
 if([string]::IsNullOrWhiteSpace($CompilerPath) -or [string]::IsNullOrWhiteSpace($OutputDirectory)){throw '請提供 -CompilerPath（已備妥的官方 ICD.exe）與全新 -OutputDirectory。此腳本不下載或安裝工具。'}
 Invoke-BuildOobeAsset -CompilerPath $CompilerPath -OutputDirectory $OutputDirectory
}
