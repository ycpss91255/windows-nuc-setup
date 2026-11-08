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