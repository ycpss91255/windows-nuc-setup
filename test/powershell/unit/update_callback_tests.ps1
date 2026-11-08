#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$file=Join-Path $root 'modules/updates/native/update_callback.cs'
Assert (Test-Path $file) 'WUA使用可檢閱非null Automation callback來源'
Add-Type -Path $file
$callback=New-Object WindowsSetup.UpdateCallback
Assert ($callback.GetType().GetMethod('Invoke').GetParameters().Count -eq 2) 'callback遵循官方job與args雙參數'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class UpdateDispatchProbe {
 [UnmanagedFunctionPointer(CallingConvention.StdCall)]
 delegate int InvokeDelegate(IntPtr self, int id, ref Guid iid, uint lcid, ushort flags, ref DISPPARAMS args, IntPtr result, IntPtr exception, IntPtr argError);
 public static int Call(object callback, int id) {
  IntPtr dispatch=Marshal.GetIDispatchForObject(callback);
  IntPtr variants=Marshal.AllocCoTaskMem((IntPtr.Size==8?24:16)*2);
  try {
   Marshal.GetNativeVariantForObject(null,variants);
   Marshal.GetNativeVariantForObject(null,IntPtr.Add(variants,IntPtr.Size==8?24:16));
   IntPtr table=Marshal.ReadIntPtr(dispatch);
   var invoke=(InvokeDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(table,6*IntPtr.Size),typeof(InvokeDelegate));
   var args=new DISPPARAMS {rgvarg=variants,cArgs=2};
   Guid empty=Guid.Empty;
   return invoke(dispatch,id,ref empty,0,1,ref args,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
  } finally {Marshal.FreeCoTaskMem(variants);Marshal.Release(dispatch);}
 }
}
"@
Assert ([UpdateDispatchProbe]::Call($callback,0) -eq 0) '真IDispatch DISPID0雙參數呼叫S_OK，不啟動更新'
Assert ([UpdateDispatchProbe]::Call($callback,9999) -ne 0) '真COM拒絕不存在DISPID避免假probe'
Write-Host 'ALL PASS: real COM callback dispatch only; no WUA operation'