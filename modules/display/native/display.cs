using System;
using System.Runtime.InteropServices;
namespace NUC8Display {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 public struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmDeviceName;
  public ushort dmSpecVersion,dmDriverVersion,dmSize,dmDriverExtra;
  public uint dmFields;
  public int dmPositionX,dmPositionY;
  public uint dmDisplayOrientation,dmDisplayFixedOutput;
  public short dmColor,dmDuplex,dmYResolution,dmTTOption,dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmFormName;
  public ushort dmLogPixels;
  public uint dmBitsPerPel,dmPelsWidth,dmPelsHeight,dmDisplayFlags,dmDisplayFrequency;
  public uint dmICMMethod,dmICMIntent,dmMediaType,dmDitherType,dmReserved1,dmReserved2,dmPanningWidth,dmPanningHeight;
 }
 public static class Display {
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string name,int number,ref Mode mode);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettings(ref Mode mode,uint flags);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
  [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags,out uint paths,out uint modes);
  [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags,ref uint paths,IntPtr pathData,ref uint modes,IntPtr modeData,IntPtr topology);
  [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(IntPtr packet);
  [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(IntPtr packet);
  // Per-monitor preset scaling packets, based on lihas/windows-DPI-scaling-sample.
  // Packet types -3/-4 are undocumented; failures are reported instead of falling back to custom scaling.
  static void FillHeader(IntPtr packet,int type,int size,IntPtr path){Marshal.WriteInt32(packet,0,type);Marshal.WriteInt32(packet,4,size);Marshal.WriteInt32(packet,8,Marshal.ReadInt32(path,0));Marshal.WriteInt32(packet,12,Marshal.ReadInt32(path,4));Marshal.WriteInt32(packet,16,Marshal.ReadInt32(path,8));}
  public static uint[] NativeScales(bool apply){
   uint pc,mc;int error=GetDisplayConfigBufferSizes(2,out pc,out mc);if(error!=0)throw new Exception("Display buffer query failed: "+error);
   IntPtr paths=Marshal.AllocHGlobal(checked((int)pc*72)),modes=Marshal.AllocHGlobal(checked((int)mc*64));
   System.Collections.Generic.List<uint> values=new System.Collections.Generic.List<uint>();
   System.Collections.Generic.HashSet<string> seen=new System.Collections.Generic.HashSet<string>();
   uint[] percentages=new uint[]{100,125,150,175,200,225,250,300,350,400,450,500};
   try{
    error=QueryDisplayConfig(2,ref pc,paths,ref mc,modes,IntPtr.Zero);if(error!=0)throw new Exception("Display path query failed: "+error);
    for(int i=0;i<pc;i++){
     IntPtr path=IntPtr.Add(paths,i*72);string id=Marshal.ReadInt32(path,0)+":"+Marshal.ReadInt32(path,4)+":"+Marshal.ReadInt32(path,8);if(!seen.Add(id))continue;
     IntPtr get=Marshal.AllocHGlobal(32),set=Marshal.AllocHGlobal(24);
     try{
      FillHeader(get,-3,32,path);error=DisplayConfigGetDeviceInfo(get);if(error!=0)throw new Exception("Native DPI query failed: "+error);
      int min=Marshal.ReadInt32(get,20),current=Marshal.ReadInt32(get,24);
      if(apply){FillHeader(set,-4,24,path);Marshal.WriteInt32(set,20,min);error=DisplayConfigSetDeviceInfo(set);if(error!=0)throw new Exception("Native DPI change failed: "+error);error=DisplayConfigGetDeviceInfo(get);if(error!=0)throw new Exception("Native DPI verification failed: "+error);current=Marshal.ReadInt32(get,24);}
      int index=Math.Abs(min)+current;if(index<0||index>=percentages.Length)throw new Exception("Unexpected native DPI range.");values.Add(percentages[index]);
     }finally{Marshal.FreeHGlobal(get);Marshal.FreeHGlobal(set);}
    }
   }finally{Marshal.FreeHGlobal(paths);Marshal.FreeHGlobal(modes);}
   if(values.Count==0)throw new Exception("No active display source.");return values.ToArray();
  }
  static Mode NewMode(){Mode m=new Mode();m.dmSize=(ushort)Marshal.SizeOf(typeof(Mode));return m;}
  public static uint[] Read(){SetProcessDPIAware();Mode m=NewMode();if(!EnumDisplaySettings(null,-1,ref m))throw new Exception("Unable to read active primary display mode.");return new uint[]{m.dmPelsWidth,m.dmPelsHeight,NativeScales(false)[0]*96/100};}
  public static uint[] Apply(){
   SetProcessDPIAware();Mode current=NewMode();
   if(!EnumDisplaySettings(null,-1,ref current))throw new Exception("Unable to read active primary display mode.");
   uint oldW=current.dmPelsWidth,oldH=current.dmPelsHeight;
   bool supported=false;
   for(int i=0;i<4096;i++){Mode candidate=NewMode();if(!EnumDisplaySettings(null,i,ref candidate))break;if(candidate.dmPelsWidth==1920 && candidate.dmPelsHeight==1080){supported=true;break;}}
   if(!supported)throw new Exception("The connected primary display does not advertise 1920x1080.");
   current.dmPelsWidth=1920;current.dmPelsHeight=1080;current.dmFields=0x180000;
   int test=ChangeDisplaySettings(ref current,2);if(test!=0)throw new Exception("Display mode test failed: "+test);
   int status=ChangeDisplaySettings(ref current,1);if(status!=0 && status!=1)throw new Exception("Display mode change failed: "+status);
   Mode after=NewMode();EnumDisplaySettings(null,-1,ref after);
   return new uint[]{oldW,oldH,after.dmPelsWidth,after.dmPelsHeight,(uint)status,GetDpiForSystem()};
  }
 }
}