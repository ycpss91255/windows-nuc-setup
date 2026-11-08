using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace WindowsSetup {
 public static class Taskbar {
  [StructLayout(LayoutKind.Sequential)] public struct AppBarData {
   public int Size; public IntPtr Window; public uint Callback,Edge;
   public int Left,Top,Right,Bottom; public IntPtr Parameter;
  }
  public delegate ulong MessageCall(uint message,ref AppBarData data);
  public sealed class NativeApi {
   public Func<IntPtr> Find=delegate{return FindWindow("Shell_TrayWnd",null);};
   public Func<int> CurrentSession=delegate{return Process.GetCurrentProcess().SessionId;};
   public Func<IntPtr,int> WindowSession=delegate(IntPtr window){uint pid;GetWindowThreadProcessId(window,out pid);if(pid==0)throw new InvalidOperationException("Cannot resolve taskbar process.");using(var process=Process.GetProcessById((int)pid)){return process.SessionId;}};
   public MessageCall Message=delegate(uint message,ref AppBarData data){return SHAppBarMessage(message,ref data).ToUInt64();};
  }
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string className,string title);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint message,ref AppBarData data);
  static uint ReadState(NativeApi api,ref AppBarData data){ulong state=api.Message(4,ref data);if(state>3)throw new InvalidOperationException("Undocumented taskbar state; no changes made.");return (uint)state;}
  public static uint AutoHide(bool apply,NativeApi api){
   if(api==null)api=new NativeApi();
   IntPtr window=api.Find();
   if(window==IntPtr.Zero || api.WindowSession(window)!=api.CurrentSession())throw new InvalidOperationException("No taskbar in the current interactive session.");
   var data=new AppBarData{Size=Marshal.SizeOf(typeof(AppBarData)),Window=window};
   if(api.Message(5,ref data)==0)throw new InvalidOperationException("Taskbar position query failed; no changes made.");
   uint before=ReadState(api,ref data);
   if(!apply || (before&1)!=0)return before;
   uint desired=before|1;
   data.Parameter=new IntPtr((long)desired);
   api.Message(10,ref data); // ABM_SETSTATE always returns TRUE; verify the actual state instead.
   uint after=ReadState(api,ref data);
   if(after!=desired)throw new InvalidOperationException("Taskbar auto-hide readback differs from requested state.");
   return after;
  }
 }
}