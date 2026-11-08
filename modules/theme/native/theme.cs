using System;using System.Text;using System.Runtime.InteropServices;
public static class NUC8Theme {
 [StructLayout(LayoutKind.Sequential)]public struct Rect{public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
 [DllImport("user32.dll")]static extern IntPtr GetDC(IntPtr hwnd);
 [DllImport("user32.dll")]static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
 [DllImport("gdi32.dll")]static extern uint GetPixel(IntPtr dc,int x,int y);
 [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 public static int[] TaskbarColor(){SetThreadDpiAwarenessContext(new IntPtr(-4));IntPtr bar=FindWindow("Shell_TrayWnd",null);Rect r;if(bar==IntPtr.Zero||!GetWindowRect(bar,out r)||r.Bottom<=r.Top)throw new Exception("Taskbar is not ready.");IntPtr dc=GetDC(IntPtr.Zero);try{uint color=GetPixel(dc,r.Left+8,r.Top+(r.Bottom-r.Top)/2);if(color==0xffffffff)throw new Exception("Unable to read taskbar color.");return new int[]{(int)(color&255),(int)((color>>8)&255),(int)((color>>16)&255)};}finally{ReleaseDC(IntPtr.Zero,dc);}}
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool SystemParametersInfo(uint action,uint param,string value,uint flags);
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool ReadWallpaper(uint action,uint param,StringBuilder value,uint flags);
 [DllImport("user32.dll")]public static extern bool SetSysColors(int count,int[] elements,uint[] colors);
 [DllImport("user32.dll")]public static extern uint GetSysColor(int index);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,IntPtr wp,string lp,uint flags,uint timeout,out IntPtr result);
}