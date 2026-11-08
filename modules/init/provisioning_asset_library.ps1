#Requires -Version 5.1
# Definitions only. This library never builds or installs a provisioning package.
function Get-InitProvisioningSourceXml {
 return @'
<?xml version="1.0" encoding="utf-8"?>
<WindowsCustomizations>
  <PackageConfig xmlns="urn:schemas-Microsoft-com:Windows-ICD-Package-Config.v1.0">
    <ID>{1C2605EA-96AE-42FC-8F11-45FC0CB9D133}</ID>
    <Name>windows_setup_hide_oobe</Name>
    <Version>1.0</Version>
    <OwnerType>ITAdmin</OwnerType>
    <Rank>0</Rank>
  </PackageConfig>
  <Settings xmlns="urn:schemas-microsoft-com:windows-provisioning">
    <Customizations><Common><OOBE><Desktop><HideOobe>True</HideOobe></Desktop></OOBE></Common></Customizations>
  </Settings>
</WindowsCustomizations>
'@
}
function New-InitProvisioningProvenance {
 param([string]$SourcePath,[string]$PackagePath)
 return [pscustomobject][ordered]@{
  SchemaVersion=1;PackageId='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';PackageVersion='1.0'
  PackageSHA256=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash;SourceSHA256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
  OnlySetting='OOBE/Desktop/HideOobe=True';ADKVersion='10.1.26100.9457';CompilerVersion='10.0.26100.9457'
  CompilerSHA256='E89F844A375BBEF9D5D98AE3920C68CFB75973FCA0CAC1202354A8AEA36842F0'
  CompilerAuthenticode='Valid Microsoft Corporation'
  OfficialSource='https://download.microsoft.com/download/8e0c0f5a-abb5-4358-a51b-168eb40b1590/adk/adksetup.exe'
  BootstrapSHA256='AC6A930FDB5C2980BA5FEFE606D47EDAAFCF5F647B4337411500D158EA77300F'
  BuildCommand='ICD.exe /Build-ProvisioningPackage /CustomizationXML:hide_oobe.xml /PackagePath:hide_oobe.ppkg /StoreFile:Microsoft-Desktop-Provisioning.dat'
  ByteReproducible=$false;PayloadInspection='Requires independent read-only WIM content validation; source and package metadata alone do not prove payload contents'
  RedistributedMicrosoftTools=$false
 }
}
function Assert-InitAssetPlainPath {
 param([string]$Path)
 $current=[IO.Path]::GetFullPath($Path)
 while($current){
  if(Test-Path -LiteralPath $current){if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '設定包路徑不可使用重新解析點。'}}
  $parent=Split-Path $current -Parent;if($parent -eq $current){break};$current=$parent
 }
}
function ConvertTo-InitAssetXml {
 param([string]$Text)
 $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
 $input=New-Object IO.StringReader($Text);$reader=[Xml.XmlReader]::Create($input,$settings)
 try{$doc=New-Object Xml.XmlDocument;$doc.PreserveWhitespace=$false;$doc.XmlResolver=$null;$doc.Load($reader);return ,$doc}finally{$reader.Dispose();$input.Dispose()}
}
function Assert-InitProvisioningAsset {
 param([Parameter(Mandatory=$true)][string]$AssetRoot)
 $root=[IO.Path]::GetFullPath($AssetRoot)
 foreach($name in @('hide_oobe.xml','hide_oobe.ppkg','provenance.json')){
  $path=Join-Path $root $name;Assert-InitAssetPlainPath $path
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('缺少初始化資產：'+$name+'；未變更帳號。')}
 }
 $source=Join-Path $root 'hide_oobe.xml';$package=Join-Path $root 'hide_oobe.ppkg'
 $manifest=[IO.File]::ReadAllText((Join-Path $root 'provenance.json'))|ConvertFrom-Json
 $expected=New-InitProvisioningProvenance -SourcePath $source -PackagePath $package
 $fields=@($expected.PSObject.Properties.Name)
 if($null -eq $manifest -or @($manifest.PSObject.Properties).Count -ne $fields.Count -or @($manifest.PSObject.Properties.Name|Where-Object {$_ -notin $fields}).Count){throw '初始化來源 manifest 欄位不符。'}
 foreach($name in $fields){
  if($expected.$name -is [bool]){if($manifest.$name -isnot [bool] -or $manifest.$name -ne $expected.$name){throw ('初始化來源值不符：'+$name)}}
  elseif([string]$manifest.$name -cne [string]$expected.$name){throw ('初始化來源或 SHA256 不符：'+$name)}
 }
 $xml=ConvertTo-InitAssetXml ([IO.File]::ReadAllText($source));$expectedXml=ConvertTo-InitAssetXml (Get-InitProvisioningSourceXml)
 if($xml.DocumentElement.OuterXml -cne $expectedXml.DocumentElement.OuterXml -or @($xml.ChildNodes|Where-Object {$_.NodeType -notin @([Xml.XmlNodeType]::XmlDeclaration,[Xml.XmlNodeType]::Element)}).Count){throw '初始化 XML 必須僅包含固定身分與 HideOobe=True；不允許帳密或額外設定。'}
 $logs=Join-Path ([IO.Path]::GetTempPath()) ('windows_setup_asset_metadata_'+[guid]::NewGuid().ToString('N'))
 $metadata=@(Get-ProvisioningPackage -PackagePath $package -LogsDirectoryPath $logs -ErrorAction Stop|Where-Object {$_.PackageID})
 if($metadata.Count -ne 1 -or $metadata[0].PackageID -ne $manifest.PackageId -or $metadata[0].PackageName -cne $manifest.PackageName -or $metadata[0].Version -ne $manifest.PackageVersion -or [int]$metadata[0].Rank -ne 0 -or [int]$metadata[0].OwnerType -ne 5000){throw '初始化設定包實際 metadata 與來源不一致。'}
 return $manifest
}
