using System;using System.Runtime.InteropServices;
public static class NucExplorerLiveV2{
 [DllImport("shell32.dll")]static extern void SHGetSetSettings(IntPtr p,uint mask,bool set);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr SendMessageTimeout(IntPtr w,uint m,IntPtr a,string b,uint f,uint t,out IntPtr r);
 public static uint Options(bool set){IntPtr p=Marshal.AllocHGlobal(256);try{
  for(int i=0;i<256;i++)Marshal.WriteByte(p,i,0);
  SHGetSetSettings(p,3,false);
  if(set){Marshal.WriteInt32(p,Marshal.ReadInt32(p)|3);SHGetSetSettings(p,3,true);IntPtr r;SendMessageTimeout((IntPtr)65535,26,IntPtr.Zero,"ShellState",2,2000,out r);}
  SHGetSetSettings(p,3,false);return ((uint)Marshal.ReadInt32(p))&3;
 }finally{Marshal.FreeHGlobal(p);}}
}