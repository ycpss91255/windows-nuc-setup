using System;
using System.Text;
using System.Runtime.InteropServices;
public static class NUC8Theme {
 [StructLayout(LayoutKind.Sequential)]public struct Rect{public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
 [DllImport("user32.dll")]static extern IntPtr GetDC(IntPtr hwnd);
 [DllImport("user32.dll")]static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
 [DllImport("gdi32.dll")]static extern uint GetPixel(IntPtr dc,int x,int y);
 [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 internal delegate bool RectangleCall(IntPtr window,out Rect rect);
 internal sealed class NativeApi {
  internal Func<IntPtr,IntPtr> Dpi=SetThreadDpiAwarenessContext;
  internal Func<string,string,IntPtr> Find=FindWindow;
  internal RectangleCall Rectangle=GetWindowRect;
  internal Func<IntPtr,IntPtr> DC=GetDC;
  internal Func<IntPtr,IntPtr,int> Release=ReleaseDC;
  internal Func<IntPtr,int,int,uint> Pixel=GetPixel;
 }
 public static int[] TaskbarColor(){return TaskbarColor(new NativeApi());}
 internal static int[] TaskbarColor(NativeApi api){
  api.Dpi(new IntPtr(-4));
  IntPtr bar=api.Find("Shell_TrayWnd",null);
  Rect r;
  if(bar==IntPtr.Zero||!api.Rectangle(bar,out r)||r.Bottom<=r.Top)throw new Exception("Taskbar is not ready.");
  IntPtr dc=api.DC(IntPtr.Zero);
  try{
   uint color=api.Pixel(dc,r.Left+8,r.Top+(r.Bottom-r.Top)/2);
   if(color==0xffffffff)throw new Exception("Unable to read taskbar color.");
   return new int[]{(int)(color&255),(int)((color>>8)&255),(int)((color>>16)&255)};
  }finally{api.Release(IntPtr.Zero,dc);}
 }
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool SystemParametersInfo(uint action,uint param,string value,uint flags);
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool ReadWallpaper(uint action,uint param,StringBuilder value,uint flags);
 [DllImport("user32.dll")]public static extern bool SetSysColors(int count,int[] elements,uint[] colors);
 [DllImport("user32.dll")]public static extern uint GetSysColor(int index);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,IntPtr wp,string lp,uint flags,uint timeout,out IntPtr result);
}