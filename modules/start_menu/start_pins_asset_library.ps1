#Requires -Version 5.1
# Definitions only. This library never builds or installs a provisioning package.
function Get-StartPinsSourceXml {
 return @'
<?xml version="1.0" encoding="utf-8"?>
<WindowsCustomizations>
  <PackageConfig xmlns="urn:schemas-Microsoft-com:Windows-ICD-Package-Config.v1.0">
    <ID>{73C18F23-529E-4379-A458-4C9B3A8D5B92}</ID>
    <Name>windows_setup_empty_start</Name>
    <Version>1.0</Version>
    <OwnerType>ITAdmin</OwnerType>
    <Rank>0</Rank>
  </PackageConfig>
  <Settings xmlns="urn:schemas-microsoft-com:windows-provisioning">
    <Customizations><Common><Policies><Start><ConfigureStartPins>{"pinnedList":[]}</ConfigureStartPins></Start></Policies></Common></Customizations>
  </Settings>
</WindowsCustomizations>
'@
}
function New-StartPinsProvenance {
 param([string]$SourcePath,[string]$PackagePath)
 return [pscustomobject][ordered]@{
  SchemaVersion=1;PackageId='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName='windows_setup_empty_start';PackageVersion='1.0'
  PackageSHA256=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash;SourceSHA256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
  OnlySetting='Policies/Start/ConfigureStartPins={"pinnedList":[]}';ADKVersion='10.1.26100.9457';CompilerVersion='10.0.26100.9457'
  CompilerSHA256='E89F844A375BBEF9D5D98AE3920C68CFB75973FCA0CAC1202354A8AEA36842F0'
  CompilerAuthenticode='Valid Microsoft Corporation'
  OfficialSource='https://download.microsoft.com/download/8e0c0f5a-abb5-4358-a51b-168eb40b1590/adk/adksetup.exe'
  BootstrapSHA256='AC6A930FDB5C2980BA5FEFE606D47EDAAFCF5F647B4337411500D158EA77300F'
  BuildCommand='ICD.exe /Build-ProvisioningPackage /CustomizationXML:empty_start.xml /PackagePath:empty_start.ppkg /StoreFile:Microsoft-Desktop-Provisioning.dat'
  ByteReproducible=$false;PayloadInspection='Requires independent read-only WIM content validation; source and package metadata alone do not prove payload contents'
  RedistributedMicrosoftTools=$false
 }
}
function Assert-StartPinsPlainPath {
 param([string]$Path)
 $current=[IO.Path]::GetFullPath($Path)
 while($current){
  if(Test-Path -LiteralPath $current){if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '設定包路徑不可使用重新解析點。'}}
  $parent=Split-Path $current -Parent;if($parent -eq $current){break};$current=$parent
 }
}
function ConvertTo-StartPinsXml {
 param([string]$Text)
 $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
 $input=New-Object IO.StringReader($Text);$reader=[Xml.XmlReader]::Create($input,$settings)
 try{$doc=New-Object Xml.XmlDocument;$doc.PreserveWhitespace=$false;$doc.XmlResolver=$null;$doc.Load($reader);return ,$doc}finally{$reader.Dispose();$input.Dispose()}
}
function Assert-StartPinsAssetSource {
 param([Parameter(Mandatory=$true)][string]$AssetRoot)
 $root=[IO.Path]::GetFullPath($AssetRoot)
 foreach($name in @('empty_start.xml','empty_start.ppkg','provenance.json')){
  $path=Join-Path $root $name;Assert-StartPinsPlainPath $path
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('缺少開始選單資產：'+$name+'；未套用政策。')}
 }
 $source=Join-Path $root 'empty_start.xml';$package=Join-Path $root 'empty_start.ppkg'
 $manifest=[IO.File]::ReadAllText((Join-Path $root 'provenance.json'))|ConvertFrom-Json
 $expected=New-StartPinsProvenance -SourcePath $source -PackagePath $package
 $fields=@($expected.PSObject.Properties.Name)
 if($null -eq $manifest -or @($manifest.PSObject.Properties).Count -ne $fields.Count -or @($manifest.PSObject.Properties.Name|Where-Object {$_ -notin $fields}).Count){throw '開始選單來源 manifest 欄位不符。'}
 foreach($name in $fields){
  if($expected.$name -is [bool]){if($manifest.$name -isnot [bool] -or $manifest.$name -ne $expected.$name){throw ('開始選單來源值不符：'+$name)}}
  elseif([string]$manifest.$name -cne [string]$expected.$name){throw ('開始選單來源或 SHA256 不符：'+$name)}
 }
 $xml=ConvertTo-StartPinsXml ([IO.File]::ReadAllText($source));$expectedXml=ConvertTo-StartPinsXml (Get-StartPinsSourceXml)
 if($xml.DocumentElement.OuterXml -cne $expectedXml.DocumentElement.OuterXml -or @($xml.ChildNodes|Where-Object {$_.NodeType -notin @([Xml.XmlNodeType]::XmlDeclaration,[Xml.XmlNodeType]::Element)}).Count){throw '開始選單 XML 必須僅包含固定身分與 空 pinnedList；不允許帳密或額外設定。'}
 return $manifest
}
