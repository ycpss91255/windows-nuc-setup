#Requires -Version 5.1
param([string]$PackagePath,[string]$EvidenceDirectory,[string]$BaselinePath)
# CI-only inspection: no mounting, package installation, privilege adjustment, or reboot.
# First extraction deliberately fails without a baseline reviewed from the real XML.
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\modules\init\provisioning_asset_library.ps1')))
function Get-OobePayloadPaths {
 return @('Multivariant/Multivariant.xml','Multivariant/0/customizations.xml','Multivariant/0/MasterDatastore.xml','Multivariant/0/Prov/RunTime.xml','Multivariant/0/Prov/RunTime/0__OOBE_Desktop_HideOobe.provxml','CommonSettings/CommonSettings.xml','CommonSettings/1/AnswerFile.xml')
}
function Initialize-OobeWimReader {
 if('WindowsSetup.OobeWimReader' -as [type]){return}
 # Microsoft WIMApplyImage documentation specifies NO_APPLY + PROCESS for listing.
 # WIMExtractImagePath extracts individual files only; WIMGetImageInformation uses LocalFree.
 Add-Type -ReferencedAssemblies 'System.dll','System.Core.dll','System.Xml.dll' -TypeDefinition @'
using System;
using System.IO;
using System.Xml;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace WindowsSetup {
 public static class OobeWimReader {
  delegate uint Callback(uint message, IntPtr w, IntPtr l, IntPtr user);
  [DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr WIMCreateFile(string path,uint access,uint creation,uint flags,uint compression,out uint result);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern uint WIMGetImageCount(IntPtr h);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern IntPtr WIMLoadImage(IntPtr h,uint index);
  [DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WIMSetTemporaryPath(IntPtr h,string path);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern bool WIMGetImageInformation(IntPtr h,out IntPtr data,out uint bytes);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr data);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern uint WIMRegisterMessageCallback(IntPtr h,Callback callback,IntPtr data);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern bool WIMUnregisterMessageCallback(IntPtr h,Callback callback);
  [DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WIMApplyImage(IntPtr h,string path,uint flags);
  [DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WIMExtractImagePath(IntPtr h,string source,string destination,uint flags);
  [DllImport("wimgapi.dll",SetLastError=true)] static extern bool WIMCloseHandle(IntPtr h);
  static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  public static void Extract(string package,string destination,string[] allowed) {
   IntPtr wim=IntPtr.Zero,image=IntPtr.Zero; Callback callback=null; bool registered=false;
   string root=Path.GetFullPath(destination).TrimEnd('\\')+"\\";
   var files=new HashSet<string>(allowed,StringComparer.OrdinalIgnoreCase);
   var entries=new HashSet<string>(files,StringComparer.OrdinalIgnoreCase); entries.Add("");
   foreach(string p in allowed) { string d=p; while(d.Contains("/")){d=d.Substring(0,d.LastIndexOf('/'));entries.Add(d);} }
   try {
    uint opened;wim=WIMCreateFile(package,0x80000000,3,0,0,out opened);Check(wim!=IntPtr.Zero && wim!=new IntPtr(-1));
    if(WIMGetImageCount(wim)!=1) throw new InvalidDataException("Exactly one WIM image is required.");
    Check(WIMSetTemporaryPath(wim,destination));image=WIMLoadImage(wim,1);Check(image!=IntPtr.Zero);
    IntPtr info=IntPtr.Zero;uint size;
    try {
     Check(WIMGetImageInformation(image,out info,out size));if(size>65536)throw new InvalidDataException("Oversized WIM metadata.");
     string text=Marshal.PtrToStringUni(info,(int)size/2).Trim('\0','\ufeff');
     var settings=new XmlReaderSettings();settings.DtdProcessing=DtdProcessing.Prohibit;settings.XmlResolver=null;
     var doc=new XmlDocument();doc.XmlResolver=null;using(var reader=XmlReader.Create(new StringReader(text),settings)){doc.Load(reader);}
     var totals=doc.SelectNodes("//TOTALBYTES");long total;
     if(totals.Count!=1 || !long.TryParse(totals[0].InnerText,out total) || total<0 || total>4194304)throw new InvalidDataException("Untrusted or oversized WIM expanded length.");
    } finally {if(info!=IntPtr.Zero)LocalFree(info);}
    var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);string problem=null;int count=0;
    callback=delegate(uint message,IntPtr w,IntPtr l,IntPtr user) {
     if(message==0x9479) {
      try {
       string full=Path.GetFullPath(Marshal.PtrToStringUni(w));string relative;
       if(full.TrimEnd('\\').Equals(root.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase))relative="";
       else if(full.StartsWith(root,StringComparison.OrdinalIgnoreCase))relative=full.Substring(root.Length).TrimEnd('\\').Replace('\\','/');
       else throw new InvalidDataException("WIM path escapes inspection directory.");
       if(++count>32 || !entries.Contains(relative))throw new InvalidDataException("Unexpected WIM entry: "+relative);
       if(files.Contains(relative))seen.Add(relative);
      } catch(Exception e) {problem=e.Message;return 0xffffffff;}
     }
     return 0;
    };
    if(WIMRegisterMessageCallback(wim,callback,IntPtr.Zero)==0xffffffff)throw new Win32Exception(Marshal.GetLastWin32Error());registered=true;
    bool listed=WIMApplyImage(image,destination,8);if(problem!=null)throw new InvalidDataException(problem);Check(listed);
    if(seen.Count!=allowed.Length)throw new InvalidDataException("Missing expected WIM files.");
    WIMUnregisterMessageCallback(wim,callback);registered=false;
    foreach(string p in allowed) {
     string target=Path.GetFullPath(Path.Combine(destination,p.Replace('/','\\')));
     if(!target.StartsWith(root,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Invalid extraction path.");
     Directory.CreateDirectory(Path.GetDirectoryName(target));Check(WIMExtractImagePath(image,"\\"+p.Replace('/','\\'),target,0));
     var f=new FileInfo(target);if(f.Length>1048576 || (f.Attributes & FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("Unsafe extracted file.");
    }
   } finally {if(registered)WIMUnregisterMessageCallback(wim,callback);if(image!=IntPtr.Zero)WIMCloseHandle(image);if(wim!=IntPtr.Zero && wim!=new IntPtr(-1))WIMCloseHandle(wim);GC.KeepAlive(callback);}
  }
 }
}
'@
}
function Read-OobeWimPayload {
 param([string]$PackagePath,[string]$Destination)
 Initialize-OobeWimReader
 [WindowsSetup.OobeWimReader]::Extract($PackagePath,$Destination,[string[]](Get-OobePayloadPaths))
}
function Invoke-OobePayloadVerification {
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
 Read-OobeWimPayload -PackagePath $PackagePath -Destination $payload
 $expected=@(Get-OobePayloadPaths);$all=@(Get-ChildItem -LiteralPath $payload -Recurse -File -Force)
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
 if($baseline.SchemaVersion -ne 1 -or $baseline.PackageSHA256 -cne $packageHash -or $baseline.OnlySetting -cne 'OOBE/Desktop/HideOobe=True' -or @($baseline.Files).Count -ne 7){throw '已審核內容基線的範圍或設定包 SHA256 不符。'}
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
 Invoke-OobePayloadVerification -PackagePath $PackagePath -EvidenceDirectory $EvidenceDirectory -BaselinePath $BaselinePath
}
