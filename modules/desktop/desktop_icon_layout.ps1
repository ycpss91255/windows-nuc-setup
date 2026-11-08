#Requires -Version 5.1

param([ValidateSet('Save','Load','Verify')][string]$Mode='Load',[switch]$Worker,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId,[string]$ExpectedUserSID)
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號儲存或套用桌面排列。'}
if($Mode -ne 'Save' -and (Get-UICulture).Name -ne 'zh-TW'){Write-Host '[略過] 目前桌面排列範本僅適用繁體中文，未套用座標。';[pscustomobject]@{Status='Skipped';Module='desktop_icon_layout.ps1';Reason='目前排列範本使用繁體中文圖示名稱'};return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"' -Mode "+$Mode
 if($Worker){$command+=' -Worker'}
 if($VerificationRunId){$command+=" -VerificationRunId '"+$VerificationRunId+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'IconLayout-Worker.ps1'
 Copy-Item $PSCommandPath $workerPath -Force
 $reference=Join-Path $PSScriptRoot 'desktop_layout.json'
 if($Mode -ne 'Save' -and $reference -ne (Join-Path $root 'desktop_layout.json')){Copy-Item $reference (Join-Path $root 'desktop_layout.json') -Force}
 $resultPath=Join-Path $root 'IconLayout-Result.json'
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Desktop-IconLayout'
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker -Mode '+$Mode+$(if($VerificationRunId){' -VerificationRunId '+$VerificationRunId}else{''}))
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '未取得桌面圖示位置結果，請先登入桌面。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot 'IconLayout-Result.json')){Copy-Item $resultPath (Join-Path $PSScriptRoot 'IconLayout-Result.json') -Force}
 if($Mode -eq 'Save' -and (Join-Path $root 'desktop_layout.json') -ne $reference){Copy-Item (Join-Path $root 'desktop_layout.json') $reference -Force}
 $result|ConvertTo-Json -Depth 6|Write-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace NUC8Icons {
 public class Icon {public int Index;public string Name;public int X;public int Y;}
 public class Layout {public int Width;public int Height;public bool AutoArrange;public Icon[] Icons;}
 [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Item {public uint mask;public int iItem,iSubItem;public uint state,stateMask;public IntPtr pszText;public int cchTextMax,iImage;public IntPtr lParam;public int iIndent,iGroupId;public uint cColumns;public IntPtr puColumns,piColFmt;public int iGroup;}
 public static class Desktop {
  delegate bool EnumProc(IntPtr hwnd,IntPtr lparam);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindow(string cls,string title);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
  [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc proc,IntPtr data);
  [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint id);
  [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
  [DllImport("user32.dll")]static extern bool GetClientRect(IntPtr hwnd,out Rect r);
  [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]static extern IntPtr GetStyle(IntPtr hwnd,int index);
  [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")]static extern IntPtr SetStyle(IntPtr hwnd,int index,IntPtr value);
  [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenProcess(uint access,bool inherit,uint id);
  [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr VirtualAllocEx(IntPtr process,IntPtr address,UIntPtr size,uint type,uint protect);
  [DllImport("kernel32.dll")]static extern bool VirtualFreeEx(IntPtr process,IntPtr address,UIntPtr size,uint type);
  [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool ReadProcessMemory(IntPtr process,IntPtr address,byte[] buffer,IntPtr size,out IntPtr read);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool WriteProcessMemory(IntPtr process,IntPtr address,byte[] buffer,IntPtr size,out IntPtr written);
  static IntPtr Msg(IntPtr hwnd,uint msg,int index,IntPtr data){IntPtr result;if(SendMessageTimeout(hwnd,msg,new IntPtr(index),data,2,3000,out result)==IntPtr.Zero)throw new Exception("Desktop message timed out.");return result;}
  static IntPtr View(){SetThreadDpiAwarenessContext(new IntPtr(-4));IntPtr v=FindWindowEx(FindWindow("Progman",null),IntPtr.Zero,"SHELLDLL_DefView",null);if(v==IntPtr.Zero)EnumWindows(delegate(IntPtr h,IntPtr p){v=FindWindowEx(h,IntPtr.Zero,"SHELLDLL_DefView",null);return v==IntPtr.Zero;},IntPtr.Zero);IntPtr list=FindWindowEx(v,IntPtr.Zero,"SysListView32",null);if(list==IntPtr.Zero)throw new Exception("Desktop icon list not found.");return list;}
  static byte[] Read(IntPtr p,IntPtr a,int size){byte[] b=new byte[size];IntPtr n;if(!ReadProcessMemory(p,a,b,new IntPtr(size),out n)||n.ToInt64()!=size)throw new Exception("Unable to read desktop icon data.");return b;}
  static void Write(IntPtr p,IntPtr a,byte[] data){IntPtr n;if(!WriteProcessMemory(p,a,data,new IntPtr(data.Length),out n)||n.ToInt64()!=data.Length)throw new Exception("Unable to write desktop icon message.");}
  public static Layout Capture(){
   if(IntPtr.Size!=8)throw new Exception("64-bit PowerShell is required.");IntPtr view=View();uint pid;GetWindowThreadProcessId(view,out pid);IntPtr process=OpenProcess(0x438,false,pid);if(process==IntPtr.Zero)throw new Exception("Unable to access Explorer desktop.");IntPtr memory=VirtualAllocEx(process,IntPtr.Zero,new UIntPtr(4096),0x3000,4);if(memory==IntPtr.Zero){CloseHandle(process);throw new Exception("Unable to allocate desktop message memory.");}
   try{int count=Msg(view,0x1004,0,IntPtr.Zero).ToInt32();if(count<0||count>256)throw new Exception("Unexpected desktop icon count.");List<Icon> icons=new List<Icon>();for(int i=0;i<count;i++){Item item=new Item();item.mask=1;item.iSubItem=0;item.pszText=IntPtr.Add(memory,256);item.cchTextMax=512;int size=Marshal.SizeOf(typeof(Item));IntPtr local=Marshal.AllocHGlobal(size);try{Marshal.StructureToPtr(item,local,false);byte[] data=new byte[size];Marshal.Copy(local,data,0,size);Write(process,memory,data);}finally{Marshal.FreeHGlobal(local);}Msg(view,0x1073,i,memory);string label=Encoding.Unicode.GetString(Read(process,IntPtr.Add(memory,256),1024)).Split('\0')[0];if(label.Length==0)throw new Exception("Desktop icon label is empty.");if(Msg(view,0x1010,i,IntPtr.Add(memory,128))==IntPtr.Zero)throw new Exception("Unable to read icon coordinates.");byte[] point=Read(process,IntPtr.Add(memory,128),8);icons.Add(new Icon{Index=i,Name=label,X=BitConverter.ToInt32(point,0),Y=BitConverter.ToInt32(point,4)});}Rect rect;GetClientRect(view,out rect);return new Layout{Width=rect.Right-rect.Left,Height=rect.Bottom-rect.Top,AutoArrange=(GetStyle(view,-16).ToInt64()&0x100)!=0,Icons=icons.ToArray()};}
   finally{VirtualFreeEx(process,memory,UIntPtr.Zero,0x8000);CloseHandle(process);}
  }
  public static void Position(int index,int x,int y){IntPtr view=View();SetStyle(view,-16,new IntPtr(GetStyle(view,-16).ToInt64()&~0x100L));uint pid;GetWindowThreadProcessId(view,out pid);IntPtr process=OpenProcess(0x438,false,pid);if(process==IntPtr.Zero)throw new Exception("Unable to access Explorer desktop.");IntPtr memory=VirtualAllocEx(process,IntPtr.Zero,new UIntPtr(8),0x3000,4);if(memory==IntPtr.Zero){CloseHandle(process);throw new Exception("Unable to allocate position buffer.");}try{byte[] point=new byte[8];Array.Copy(BitConverter.GetBytes(x),0,point,0,4);Array.Copy(BitConverter.GetBytes(y),0,point,4,4);Write(process,memory,point);Msg(view,0x1031,index,memory);}finally{VirtualFreeEx(process,memory,UIntPtr.Zero,0x8000);CloseHandle(process);}}
 }
}
"@
 $snapshot=[NUC8Icons.Desktop]::Capture()
 $referencePath=Join-Path $PSScriptRoot 'desktop_layout.json'
 if($Mode -eq 'Save'){
  if($snapshot.Icons.Count -ne 4){throw ('目前桌面不是四個圖示，請先確認：'+$snapshot.Icons.Count)}
  $reference=[ordered]@{Width=$snapshot.Width;Height=$snapshot.Height;Icons=@($snapshot.Icons|Select-Object Name,X,Y);SavedAt=(Get-Date).ToString('o')}
  $reference|ConvertTo-Json -Depth 5|Set-Content $referencePath -Encoding UTF8
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=$true;Mode=$Mode;Reference=$reference}
 }else{
  $reference=Get-Content $referencePath -Raw|ConvertFrom-Json
  if($snapshot.Width -ne $reference.Width -or $snapshot.Height -ne $reference.Height){throw '桌面範圍與範本不同，請確認解析度、縮放及螢幕數量。'}
  $differences=@()
  foreach($expected in $reference.Icons){
   $actual=@($snapshot.Icons|Where-Object Name -eq $expected.Name)
   if($actual.Count -ne 1){$differences+=('找不到唯一圖示：'+$expected.Name);continue}
   if($Mode -eq 'Load'){[NUC8Icons.Desktop]::Position($actual[0].Index,[int]$expected.X,[int]$expected.Y)}
  }
  if($Mode -eq 'Load'){
   $key='HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
   $flags=(Get-ItemProperty $key -ErrorAction SilentlyContinue).FFlags
   if($null -ne $flags){Set-ItemProperty $key -Name FFlags -Value ($flags -band (-bnot 1))}
   Start-Sleep -Milliseconds 500
  }
  $after=[NUC8Icons.Desktop]::Capture()
  foreach($expected in $reference.Icons){$actual=@($after.Icons|Where-Object Name -eq $expected.Name);if($actual.Count -eq 1 -and ([math]::Abs($actual[0].X-$expected.X) -gt 2 -or [math]::Abs($actual[0].Y-$expected.Y) -gt 2)){$differences+=('位置不符：'+$expected.Name)}}
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=($differences.Count -eq 0);Mode=$Mode;Differences=$differences;Actual=@($after.Icons|Select-Object Name,X,Y);Error=($differences -join '；')}
 }
 $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'IconLayout-Result.json') -Encoding UTF8
 if((Join-Path $PSScriptRoot 'IconLayout-Result.json') -ne (Join-Path $root 'IconLayout-Result.json')){$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'IconLayout-Result.json') -Encoding UTF8}
 $result|ConvertTo-Json -Depth 6|Write-Host
 if(-not $result.Success){throw $result.Error}
}catch{
 @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'IconLayout-Result.json') -Encoding UTF8
 throw
}