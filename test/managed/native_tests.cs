using System;
using System.Reflection;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ManagedNativeTests {
 static int assertions;
 static void Assert(bool condition,string name){if(!condition)throw new Exception(name);assertions++;Console.WriteLine("PASS: "+name);}
 static void Throws(Action action,string name,Type expected=null){bool rejected=false;try{action();}catch(Exception error){rejected=error.GetType()==(expected??typeof(InvalidOperationException));}Assert(rejected,name);}
 static void ExplorerCases(){
  uint settings=4;int reads=0,writes=0,broadcasts=0,freed=0;
  var api=new NucExplorerLiveV2.NativeApi();
  api.Allocate=delegate(int size){Assert(size==256,"explorer allocates exact shell settings buffer");return Marshal.AllocHGlobal(size);};
  api.Free=delegate(IntPtr memory){freed++;Marshal.FreeHGlobal(memory);};
  api.Settings=delegate(IntPtr memory,uint mask,bool set){Assert(mask==3,"explorer only requests hidden/extension option mask");if(set){settings=(uint)Marshal.ReadInt32(memory);writes++;}else{reads++;Marshal.WriteInt32(memory,(int)settings);}};
  api.Broadcast=delegate(IntPtr window,uint message,IntPtr value,string text,uint flags,uint timeout,out IntPtr result){result=IntPtr.Zero;broadcasts++;Assert(window==(IntPtr)65535 && message==26 && text=="ShellState" && flags==2 && timeout==2000,"explorer broadcasts exact shell state update");return (IntPtr)1;};
  Assert(NucExplorerLiveV2.Options(false,api)==0 && writes==0 && broadcasts==0 && freed==1,"explorer read mode never writes or broadcasts");
  Assert(NucExplorerLiveV2.Options(true,api)==3 && settings==7 && reads==4 && writes==1 && broadcasts==1 && freed==2,"explorer preserves unrelated bits and reads back changed options");
  api.Settings=delegate(IntPtr memory,uint mask,bool set){throw new InvalidOperationException("settings fixture failure");};
  Throws(delegate{NucExplorerLiveV2.Options(true,api);},"explorer native failure propagates");
  Assert(freed==3,"explorer frees unmanaged settings buffer after failure");
 }
 static void ThemeCases(){
  int releases=0;var api=new NUC8Theme.NativeApi();
  api.Dpi=delegate(IntPtr context){Assert(context==(IntPtr)(-4),"theme requests expected thread DPI context");return IntPtr.Zero;};
  api.Find=delegate(string kind,string title){Assert(kind=="Shell_TrayWnd" && title==null,"theme finds the taskbar class");return (IntPtr)1;};
  api.Rectangle=delegate(IntPtr window,out NUC8Theme.Rect rect){rect=new NUC8Theme.Rect{Left=100,Top=900,Right=1920,Bottom=940};return true;};
  api.DC=delegate(IntPtr window){Assert(window==IntPtr.Zero,"theme samples screen DC");return (IntPtr)2;};
  api.Release=delegate(IntPtr window,IntPtr dc){Assert(window==IntPtr.Zero && dc==(IntPtr)2,"theme releases exact acquired DC");releases++;return 1;};
  api.Pixel=delegate(IntPtr dc,int x,int y){Assert(dc==(IntPtr)2 && x==108 && y==920,"theme reads expected taskbar sample coordinate");return 0x00332211;};
  var rgb=NUC8Theme.TaskbarColor(api);Assert(rgb[0]==17 && rgb[1]==34 && rgb[2]==51 && releases==1,"theme converts COLORREF channels and releases DC");
  api.Find=delegate(string kind,string title){return IntPtr.Zero;};Throws(delegate{NUC8Theme.TaskbarColor(api);},"missing taskbar is rejected",typeof(Exception));
  api.Find=delegate(string kind,string title){return (IntPtr)1;};
  api.Rectangle=delegate(IntPtr window,out NUC8Theme.Rect rect){rect=new NUC8Theme.Rect();return false;};Throws(delegate{NUC8Theme.TaskbarColor(api);},"failed taskbar rectangle query is rejected",typeof(Exception));
  api.Rectangle=delegate(IntPtr window,out NUC8Theme.Rect rect){rect=new NUC8Theme.Rect{Top=10,Bottom=10};return true;};Throws(delegate{NUC8Theme.TaskbarColor(api);},"empty taskbar rectangle is rejected",typeof(Exception));
  api.Rectangle=delegate(IntPtr window,out NUC8Theme.Rect rect){rect=new NUC8Theme.Rect{Top=900,Bottom=940};return true;};
  api.Pixel=delegate(IntPtr dc,int x,int y){return 0xffffffff;};Throws(delegate{NUC8Theme.TaskbarColor(api);},"invalid pixel result is rejected",typeof(Exception));
  Assert(releases==2,"theme releases DC when pixel read reports failure");
  api.Pixel=delegate(IntPtr dc,int x,int y){throw new InvalidOperationException("pixel fixture failure");};Throws(delegate{NUC8Theme.TaskbarColor(api);},"pixel exception propagates");
  Assert(releases==3,"theme releases DC when pixel read throws");
 }
 static void HotkeyCases(){
  var log=new List<string>();int unregistered=0,messages=0,launched=0;
  var api=new NucTerminalHotkey.NativeApi();
  api.Register=delegate(IntPtr window,int id,uint modifiers,uint key){Assert(window==IntPtr.Zero && id==1 && modifiers==0x4003 && key==0x54,"hotkey registers Ctrl+Alt+T with no-repeat modifier");return false;};
  api.Unregister=delegate(IntPtr window,int id){Assert(window==IntPtr.Zero && id==1,"hotkey releases its own registration");unregistered++;return true;};
  api.Error=delegate{return 37;};api.PID=delegate{return 1234;};api.Time=delegate{return "fixture-time";};
  api.Write=delegate(string path,string text){Assert(path=="fixture.log","hotkey writes only requested status log");log.Clear();log.Add(text);};
  api.Append=delegate(string path,string text){Assert(path=="fixture.log","hotkey appends only requested status log");log.Add(text);};
  api.Next=delegate(out NucTerminalHotkey.MSG message,IntPtr window,uint min,uint max){message=new NucTerminalHotkey.MSG();messages++;return 0;};
  api.Launch=delegate(string terminal,string home){Assert(terminal=="terminal fixture.exe" && home=="home with spaces","hotkey forwards dynamic terminal and user home");launched++;};
  NucTerminalHotkey.Run("terminal fixture.exe","fixture.log","home with spaces",api);
  Assert(log.Count==1 && log[0]=="FAILED: 37" && messages==0 && unregistered==0,"failed registration neither enters loop nor unregisters someone else's hotkey");
  api.Register=delegate(IntPtr window,int id,uint modifiers,uint key){return true;};
  api.Next=delegate(out NucTerminalHotkey.MSG message,IntPtr window,uint min,uint max){message=new NucTerminalHotkey.MSG();int number=messages++;if(number==0){message.message=0x100;return 1;}if(number==1){message.message=0x312;message.wParam=(UIntPtr)1;return 1;}return 0;};
  NucTerminalHotkey.Run("terminal fixture.exe","fixture.log","home with spaces",api);
  Assert(launched==1 && unregistered==1 && log[0].Contains("REGISTERED: PID=1234 fixture-time") && log[1].Contains("LAUNCHED: fixture-time"),"hotkey ignores unrelated messages and launches terminal only for its registration");
  messages=0;api.Next=delegate(out NucTerminalHotkey.MSG message,IntPtr window,uint min,uint max){message=new NucTerminalHotkey.MSG{message=0x312,wParam=(UIntPtr)1};return messages++==0?1:0;};
  api.Launch=delegate(string terminal,string home){throw new InvalidOperationException("launch fixture failure");};
  NucTerminalHotkey.Run("terminal fixture.exe","fixture.log","home with spaces",api);
  Assert(log[1].Contains("LAUNCH FAILED: launch fixture failure") && unregistered==2,"terminal launch failure is logged and registration is released");
  api.Next=delegate(out NucTerminalHotkey.MSG message,IntPtr window,uint min,uint max){message=new NucTerminalHotkey.MSG();return -1;};
  NucTerminalHotkey.Run("terminal fixture.exe","fixture.log","home with spaces",api);
  Assert(log[1].Contains("MESSAGE LOOP FAILED: 37") && unregistered==3,"message-loop native error cannot leave a misleading registered status");
  api.Write=delegate(string path,string text){throw new InvalidOperationException("log fixture failure");};
  Throws(delegate{NucTerminalHotkey.Run("terminal fixture.exe","fixture.log","home with spaces",api);},"startup log failure propagates");
  Assert(unregistered==4,"startup log failure still unregisters the acquired hotkey");
  var start=NucTerminalHotkey.CreateStartInfo("terminal fixture.exe","home with spaces");Assert(start.UseShellExecute && start.FileName=="terminal fixture.exe" && start.WorkingDirectory=="home with spaces","production launch options preserve dynamic paths without starting a process");
 }
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
  ExplorerCases();ThemeCases();HotkeyCases();
  Console.WriteLine("ALL PASS: "+assertions+" managed source assertions; no native OS functions invoked");
 }
}