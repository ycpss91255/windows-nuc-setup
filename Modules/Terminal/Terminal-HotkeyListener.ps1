$ErrorActionPreference='Stop'
$folder=Join-Path $env:LOCALAPPDATA 'NUC8-Setup\TerminalHotkey'
$log=Join-Path $folder 'status.log'
New-Item -ItemType Directory $folder -Force|Out-Null
$mutex=New-Object Threading.Mutex($false,'Local\NUC8TerminalHotkey')
if(-not $mutex.WaitOne(0)){exit}
try{
Add-Type -TypeDefinition @"
using System;using System.Diagnostics;using System.Runtime.InteropServices;using System.IO;
public static class NucTerminalHotkey {
 [StructLayout(LayoutKind.Sequential)]struct POINT{public int x,y;}
 [StructLayout(LayoutKind.Sequential)]struct MSG{public IntPtr hwnd;public uint message;public UIntPtr wParam;public IntPtr lParam;public uint time;public POINT pt;public uint lPrivate;}
 [DllImport("user32.dll",SetLastError=true)]static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
 [DllImport("user32.dll")]static extern bool UnregisterHotKey(IntPtr hwnd,int id);
 [DllImport("user32.dll")]static extern int GetMessage(out MSG message,IntPtr hwnd,uint min,uint max);
 public static void Run(string terminal,string log,string home){
  if(!RegisterHotKey(IntPtr.Zero,1,0x4003,0x54)){File.WriteAllText(log,"FAILED: "+Marshal.GetLastWin32Error());return;}
  File.WriteAllText(log,"REGISTERED: PID="+Process.GetCurrentProcess().Id+" "+DateTime.Now.ToString("o")+Environment.NewLine);
  try{MSG msg;while(GetMessage(out msg,IntPtr.Zero,0,0)>0){if(msg.message==0x0312&&msg.wParam.ToUInt64()==1){try{Process.Start(new ProcessStartInfo(terminal){UseShellExecute=true,WorkingDirectory=home});File.AppendAllText(log,"LAUNCHED: "+DateTime.Now.ToString("o")+Environment.NewLine);}catch(Exception e){File.AppendAllText(log,"LAUNCH FAILED: "+e.Message+Environment.NewLine);}}}}finally{UnregisterHotKey(IntPtr.Zero,1);}
 }
}
"@
[NucTerminalHotkey]::Run((Get-Command wt.exe -ErrorAction Stop).Source,$log,$env:USERPROFILE)
}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
