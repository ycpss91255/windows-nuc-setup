#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
$resultFileName=if($VerifyOnly){'Display-Verification.json'}else{'Display-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Display-Worker.ps1'
 Copy-Item -LiteralPath $PSCommandPath -Destination $workerPath -Force
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Move-Item -LiteralPath $resultPath -Destination (Join-Path $root ('Display-Previous-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Force}
 $name='NUC8-Apply-Display'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 if($VerificationRunId){$workerArgs+=' -VerificationRunId '+$VerificationRunId}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $workerArgs
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 Write-Host '正在目前登入的桌面套用 1920×1080 與 100% 縮放…' -ForegroundColor Cyan
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 $info=Get-ScheduledTaskInfo -TaskName $name
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw ('尚未取得桌面執行結果。請在目標電腦登入桌面後再執行；工作狀態：'+$info.LastTaskResult)}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot $resultFileName)){Copy-Item -LiteralPath $resultPath -Destination (Join-Path $PSScriptRoot $resultFileName) -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
Add-Type -TypeDefinition @"
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
"@
 if($VerifyOnly){
  $actual=[NUC8Display.Display]::Read()
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=($actual[0] -eq 1920 -and $actual[1] -eq 1080 -and $actual[2] -eq 96 -and (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Win8DpiScaling -ne 1);Width=$actual[0];Height=$actual[1];CurrentMonitorDPI=$actual[2];CurrentScalePercent=[math]::Round($actual[2]*100/96);CustomScalingEnabled=((Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Win8DpiScaling -eq 1);VerifiedAt=(Get-Date).ToString('o');Error='解析度或實際 DPI 尚未符合 1920×1080 / 100%，可能需要重新登入。'}
  if($result.Success){$result.Error=$null}
  $result|ConvertTo-Json|Set-Content (Join-Path $root 'Display-Verification.json') -Encoding UTF8
  if((Join-Path $PSScriptRoot 'Display-Verification.json') -ne (Join-Path $root 'Display-Verification.json')){$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'Display-Verification.json') -Encoding UTF8}
  $result|Format-List|Out-Host
  return
 }
 $values=[NUC8Display.Display]::Apply()
 $desktop='HKCU:\Control Panel\Desktop'
 # 關閉先前的全域自訂縮放，改用螢幕的標準縮放預設值。
 New-ItemProperty $desktop -Name Win8DpiScaling -Value 0 -PropertyType DWord -Force|Out-Null
 Remove-ItemProperty $desktop -Name LogPixels -ErrorAction SilentlyContinue
 $nativeScales=@([NUC8Display.Display]::NativeScales($true))
 if(@($nativeScales|Where-Object {$_ -ne 100}).Count){throw '標準縮放尚未成功設定為 100%。'}
 $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=$true;PreviousWidth=$values[0];PreviousHeight=$values[1];Width=$values[2];Height=$values[3];DisplayChangeResult=$values[4];LegacySystemDPI=$values[5];RequestedScalePercent=100;NativeScalePercent=$nativeScales;CustomScalingEnabled=$false;LegacyAppsMayRequireNextSignIn=$true;AppliedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if(-not $Worker){$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot $resultFileName) -Encoding UTF8}
 Write-Host ('目前主螢幕解析度：'+$result.Width+'×'+$result.Height) -ForegroundColor Green
 Write-Host '已改為標準螢幕縮放 100%，自訂縮放已關閉；少數舊程式可能需重新登入後更新。'
}catch{
 @{Success=$false;Error=$_.Exception.Message;AppliedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 throw
}