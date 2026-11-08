#Requires -Version 5.1
param([string]$PackagePath,[string]$EvidenceDirectory,[string]$BaselinePath)
# CI-only inspection: no mounting, package installation, privilege adjustment, or reboot.
# First extraction deliberately fails without a baseline reviewed from the real XML.
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\modules\init\provisioning_asset_library.ps1')))
. (Join-Path $PSScriptRoot 'verify_oobe_payload.ps1')
function Get-StartPinsPayloadPaths {
 return @('Multivariant/Multivariant.xml','Multivariant/0/customizations.xml','Multivariant/0/MasterDatastore.xml','Multivariant/0/Prov/RunTime.xml','Multivariant/0/Prov/RunTime/0__Policies_Start_ConfigureStartPins.provxml','CommonSettings/CommonSettings.xml','CommonSettings/1/AnswerFile.xml')
}
function Read-StartPinsWimPayload {
 param([string]$PackagePath,[string]$Destination)
 Initialize-OobeWimReader
 [WindowsSetup.OobeWimReader]::Extract($PackagePath,$Destination,[string[]](Get-StartPinsPayloadPaths))
}
function Invoke-StartPinsPayloadVerification {
 param([Parameter(Mandatory=$true)][string]$PackagePath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory,[string]$BaselinePath)
 $ErrorActionPreference='Stop'
 Assert-InitAssetPlainPath $PackagePath
 if(-not(Test-Path -LiteralPath $PackagePath -PathType Leaf) -or (Get-Item -LiteralPath $PackagePath).Length -gt 1048576){throw '設定包不存在或超過 1 MiB，未執行抽取。'}
 $directory=[IO.Path]::GetFullPath($EvidenceDirectory);Assert-InitAssetPlainPath $directory
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $directory.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $directory)){throw '證據目錄必須是 TEMP 內尚未存在的新路徑。'}
 New-Item -ItemType Directory -Path $directory|Out-Null
 $payload=Join-Path $directory 'payload';New-Item -ItemType Directory -Path $payload|Out-Null
 $packageHash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
 try{Read-StartPinsWimPayload -PackagePath $PackagePath -Destination $payload}catch{
  $unexpected=$null
  if($_.Exception.Message -match 'Unexpected WIM entry: (Multivariant/0/Prov/RunTime/[A-Za-z0-9_-]+\.provxml)'){$unexpected=$Matches[1]}
  $diagnostic=[pscustomobject]@{SchemaVersion=1;PackageSHA256=$packageHash;Verified=$false;Files=@();UnexpectedEntry=$unexpected}
  [IO.File]::WriteAllText((Join-Path $directory 'evidence.json'),($diagnostic|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  throw
 }
 $expected=@(Get-StartPinsPayloadPaths);$all=@(Get-ChildItem -LiteralPath $payload -Recurse -File -Force)
 if($all.Count -ne 7){throw '抽取後檔案數量不符。'}
 $files=@(foreach($name in $expected){
  $path=Join-Path $payload $name;Assert-InitAssetPlainPath $path
  if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 1048576){throw '抽取檔案不存在或超過限制。'}
  $doc=ConvertTo-InitAssetXml ([IO.File]::ReadAllText($path))
  [pscustomobject]@{Path=$name;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;RootName=$doc.DocumentElement.LocalName;Namespace=$doc.DocumentElement.NamespaceURI}
 })
 if((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash -cne $packageHash){throw '檢驗期間設定包被修改。'}
 $evidence=[pscustomobject]@{SchemaVersion=1;PackageSHA256=$packageHash;Verified=$false;Files=$files}
 [IO.File]::WriteAllText((Join-Path $directory 'evidence.json'),($evidence|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
 if(-not $BaselinePath -or -not(Test-Path -LiteralPath $BaselinePath -PathType Leaf)){throw ('尚無經主代理與獨立審查者確認的真實 XML 基線，檢驗未通過。請審查：'+$directory)}
 Assert-InitAssetPlainPath $BaselinePath
 $baseline=[IO.File]::ReadAllText($BaselinePath)|ConvertFrom-Json
 if($baseline.SchemaVersion -ne 1 -or $baseline.PackageSHA256 -cne $packageHash -or $baseline.OnlySetting -cne 'Policies/Start/ConfigureStartPins={"pinnedList":[]}' -or @($baseline.Files).Count -ne 7){throw '已審核內容基線的範圍或設定包 SHA256 不符。'}
 foreach($file in $files){
  $matches=@($baseline.Files|Where-Object {$_.Path -ceq $file.Path})
  if($matches.Count -ne 1 -or $matches[0].SHA256 -cne $file.SHA256 -or $matches[0].RootName -cne $file.RootName -or $matches[0].Namespace -cne $file.Namespace){throw ('內容／XML namespace 與已審核基線不符：'+$file.Path)}
 }
 $evidence.Verified=$true
 [IO.File]::WriteAllText((Join-Path $directory 'evidence.json'),($evidence|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
 return $evidence
}
if($MyInvocation.InvocationName -ne '.'){
 if(-not $PackagePath -or -not $EvidenceDirectory){throw '必須提供 -PackagePath 與 TEMP 內全新 -EvidenceDirectory；可另提供已審核 -BaselinePath。'}
 Invoke-StartPinsPayloadVerification -PackagePath $PackagePath -EvidenceDirectory $EvidenceDirectory -BaselinePath $BaselinePath
}
