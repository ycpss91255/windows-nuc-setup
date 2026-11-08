using System;
using System.Reflection;
using System.Runtime.InteropServices;
public static class ManagedNativeTests {
 static int assertions;
 static void Assert(bool condition,string name){if(!condition)throw new Exception(name);assertions++;Console.WriteLine("PASS: "+name);}
 public static void Main(string[] args){
  Assert(typeof(NUC8Icons.Desktop).GetMethod("Capture")!=null,"desktop capture API is available");
  Assert(typeof(NUC8Theme).GetMethod("TaskbarColor")!=null,"theme API is available");
  Assert(typeof(NucExplorerLiveV2).GetMethod("Options")!=null,"explorer API is available");
  Assert(typeof(NucTerminalHotkey).GetMethod("Run")!=null,"hotkey API is available");
  Assert(typeof(WindowsSetup.OobeWimReader).GetMethod("Extract")!=null,"WIM read API is available");
  var method=typeof(NUC8Display.Display).GetMethod("NewMode",BindingFlags.NonPublic|BindingFlags.Static);
  var mode=(NUC8Display.Mode)method.Invoke(null,new object[0]);
  Assert(mode.dmSize==220 && Marshal.SizeOf(typeof(NUC8Display.Mode))==220,"DEVMODEW managed initializer preserves native ABI");
  IntPtr packet=Marshal.AllocHGlobal(32),path=Marshal.AllocHGlobal(72);
  try{
   Marshal.WriteInt32(path,0,19);Marshal.WriteInt32(path,4,23);Marshal.WriteInt32(path,8,29);
   typeof(NUC8Display.Display).GetMethod("FillHeader",BindingFlags.NonPublic|BindingFlags.Static).Invoke(null,new object[]{packet,-3,32,path});
   Assert(Marshal.ReadInt32(packet,0)==-3 && Marshal.ReadInt32(packet,4)==32,"display packet type and size are written");
   Assert(Marshal.ReadInt32(packet,8)==19 && Marshal.ReadInt32(packet,12)==23 && Marshal.ReadInt32(packet,16)==29,"display packet carries exact adapter identity");
  }finally{Marshal.FreeHGlobal(packet);Marshal.FreeHGlobal(path);}
  Console.WriteLine("ALL PASS: "+assertions+" managed source assertions; no native OS functions invoked");
 }
}