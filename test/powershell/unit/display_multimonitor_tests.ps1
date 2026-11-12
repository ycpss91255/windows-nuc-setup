#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source=Get-Content -Raw (Join-Path $root 'modules/display/native/display.cs')
$source=$source.Replace('new NativeApi()','DisplayFixture.Api()')
$fixture=@'
namespace NUC8Display {
 public static class DisplayFixture {
  public static int[] Steps={-2,0}; public static bool Fail; public static int Queries;
  internal static Display.NativeApi Api(){
   var a=new Display.NativeApi();
   a.Aware=delegate{return true;};
   a.Enumerate=delegate(string name,int index,ref Mode m){m.dmPelsWidth=1920;m.dmPelsHeight=1080;return true;};
   a.Buffer=delegate(uint flags,out uint paths,out uint modes){paths=(uint)Steps.Length;modes=1;return Fail?7:0;};
   a.Query=delegate(uint flags,ref uint paths,System.IntPtr p,ref uint modes,System.IntPtr m,System.IntPtr t){Queries++;for(int i=0;i<Steps.Length;i++){System.Runtime.InteropServices.Marshal.WriteInt32(p,i*72,11);System.Runtime.InteropServices.Marshal.WriteInt32(p,i*72+4,12);System.Runtime.InteropServices.Marshal.WriteInt32(p,i*72+8,i);}return 0;};
   a.Get=delegate(System.IntPtr p){int id=System.Runtime.InteropServices.Marshal.ReadInt32(p,16);System.Runtime.InteropServices.Marshal.WriteInt32(p,20,-2);System.Runtime.InteropServices.Marshal.WriteInt32(p,24,Steps[id]);return 0;};
   return a;
  }
 }
}
'@
Add-Type -TypeDefinition ($source+"`n"+$fixture)
. (Join-Path $root 'modules/display/display_settings_library.ps1')
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{Win8DpiScaling=0}}
function Assert([bool]$condition,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$condition}|ConvertTo-Json -Compress));if(-not $condition){throw $name}}
$module=Join-Path $root 'modules/display'
foreach($case in @(@{Steps=@(-2,0);Success=$false},@{Steps=@(0,-2);Success=$false},@{Steps=@(-2,-2);Success=$true},@{Steps=@(-2);Success=$true})){
 [NUC8Display.DisplayFixture]::Steps=$case.Steps;[NUC8Display.DisplayFixture]::Queries=0
 $r=Invoke-SetupDisplaySettings -ModuleRoot $module -VerifyOnly
 Assert ($r.Success -eq $case.Success -and [NUC8Display.DisplayFixture]::Queries -eq 1) ('VerifyOnly validates every source in one query: '+($case.Steps -join ','))
}
[NUC8Display.DisplayFixture]::Fail=$true;$failed=$false;try{Invoke-SetupDisplaySettings -ModuleRoot $module -VerifyOnly|Out-Null}catch{$failed=$true};Assert $failed 'native failure rejects verification'
[NUC8Display.DisplayFixture]::Fail=$false;[NUC8Display.DisplayFixture]::Steps=@();$failed=$false;try{Invoke-SetupDisplaySettings -ModuleRoot $module -VerifyOnly|Out-Null}catch{$failed=$true};Assert $failed 'empty active sources reject verification'