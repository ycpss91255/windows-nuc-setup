using System;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
namespace WindowsSetup {
 public static class MdnsPublisher {
  public sealed class Advertisement { public string HostName,ServiceName,IPv4,IPv6;public uint InterfaceIndex;public int Port; }
  [StructLayout(LayoutKind.Sequential)] public struct Instance {
   public IntPtr Name,Host,IPv4,IPv6;public ushort Port,Priority,Weight;public uint PropertyCount;public IntPtr Keys,Values;public uint InterfaceIndex;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Request {
   public uint Version,InterfaceIndex;public IntPtr Instance,Callback,Context,Credentials;public int Unicast;
  }
  [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void Completion(uint status,IntPtr context,IntPtr instance);
  public delegate uint RequestCall(uint operation,IntPtr request,IntPtr cancel);
  public sealed class NativeApi {
   public Func<Advertisement,IntPtr> Construct=NativeConstruct;
   public Func<IntPtr,Advertisement> Read=ReadInstance;
   public Action<IntPtr> Free=NativeFree;
   public RequestCall Request=delegate(uint operation,IntPtr request,IntPtr cancel){return operation==0?DnsServiceRegister(request,cancel):DnsServiceDeRegister(request,IntPtr.Zero);};
   public Func<IntPtr,uint> Cancel=DnsServiceRegisterCancel;
   public Func<WaitHandle,int,bool> Wait=delegate(WaitHandle signal,int milliseconds){return signal.WaitOne(milliseconds);};
  }
  [DllImport("dnsapi.dll",CharSet=CharSet.Unicode)] static extern IntPtr DnsServiceConstructInstance(string service,string host,IntPtr ipv4,IntPtr ipv6,ushort port,ushort priority,ushort weight,uint propertyCount,IntPtr keys,IntPtr values);
  [DllImport("dnsapi.dll")] static extern void DnsServiceFreeInstance(IntPtr instance);
  [DllImport("dnsapi.dll")] static extern uint DnsServiceRegister(IntPtr request,IntPtr cancel);
  [DllImport("dnsapi.dll")] static extern uint DnsServiceDeRegister(IntPtr request,IntPtr cancel);
  [DllImport("dnsapi.dll")] static extern uint DnsServiceRegisterCancel(IntPtr cancel);
  static bool SameName(string a,string b){return String.Equals((a??"").TrimEnd('.'),(b??"").TrimEnd('.'),StringComparison.OrdinalIgnoreCase);}
  static IPAddress Address(string value,AddressFamily family){
   if(String.IsNullOrEmpty(value))return null;
   IPAddress ip;if(!IPAddress.TryParse(value,out ip) || ip.AddressFamily!=family || IPAddress.IsLoopback(ip) || ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any) || ip.IsIPv6Multicast || (family==AddressFamily.InterNetwork && ip.GetAddressBytes()[0]>=224))throw new InvalidOperationException("Invalid publication address.");
   return ip;
  }
  static bool SameAddress(string a,string b,AddressFamily family){var x=Address(a,family);var y=Address(b,family);if(x==null || y==null)return x==null && y==null;byte[] xb=x.GetAddressBytes(),yb=y.GetAddressBytes();for(int i=0;i<xb.Length;i++)if(xb[i]!=yb[i])return false;return true;}
  static bool Matches(Advertisement actual,Advertisement expected){return actual!=null && SameName(actual.HostName,expected.HostName) && SameName(actual.ServiceName,expected.ServiceName) && actual.Port==expected.Port && SameAddress(actual.IPv4,expected.IPv4,AddressFamily.InterNetwork) && SameAddress(actual.IPv6,expected.IPv6,AddressFamily.InterNetworkV6) && (actual.InterfaceIndex==0 || actual.InterfaceIndex==expected.InterfaceIndex);}
  static void Validate(Advertisement ad){
   if(ad==null || ad.InterfaceIndex==0 || ad.Port!=22 || ad.HostName==null || !ad.HostName.EndsWith(".local",StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Invalid fixed publication schema.");
   string label=ad.HostName.Substring(0,ad.HostName.Length-6);
   if(!Regex.IsMatch(label,@"^[\p{L}\p{Nd}_][\p{L}\p{Nd}_-]*$") || Encoding.UTF8.GetByteCount(label)>63 || !SameName(ad.ServiceName,label+"._ssh._tcp.local"))throw new InvalidOperationException("Invalid publication name.");
   if(Address(ad.IPv4,AddressFamily.InterNetwork)==null && Address(ad.IPv6,AddressFamily.InterNetworkV6)==null)throw new InvalidOperationException("Publication needs an address.");
  }
  // Safe allocation-only ABI entry: constructing/freeing does not advertise a service.
  public static IntPtr NativeConstruct(Advertisement ad){
   Validate(ad);IntPtr v4=IntPtr.Zero,v6=IntPtr.Zero;
   try{
    foreach(bool six in new[]{false,true}){var ip=Address(six?ad.IPv6:ad.IPv4,six?AddressFamily.InterNetworkV6:AddressFamily.InterNetwork);if(ip==null)continue;byte[] bytes=ip.GetAddressBytes();IntPtr memory=Marshal.AllocHGlobal(bytes.Length);Marshal.Copy(bytes,0,memory,bytes.Length);if(six)v6=memory;else v4=memory;}
    return DnsServiceConstructInstance(ad.ServiceName,ad.HostName,v4,v6,22,0,0,0,IntPtr.Zero,IntPtr.Zero);
   }finally{if(v4!=IntPtr.Zero)Marshal.FreeHGlobal(v4);if(v6!=IntPtr.Zero)Marshal.FreeHGlobal(v6);}
  }
  public static Advertisement ReadInstance(IntPtr instance){
   if(instance==IntPtr.Zero)throw new InvalidOperationException("Native instance is missing.");
   var value=(Instance)Marshal.PtrToStructure(instance,typeof(Instance));string v4=null,v6=null;
   if(value.IPv4!=IntPtr.Zero){var bytes=new byte[4];Marshal.Copy(value.IPv4,bytes,0,4);v4=new IPAddress(bytes).ToString();}
   if(value.IPv6!=IntPtr.Zero){var bytes=new byte[16];Marshal.Copy(value.IPv6,bytes,0,16);v6=new IPAddress(bytes).ToString();}
   return new Advertisement{HostName=Marshal.PtrToStringUni(value.Host),ServiceName=Marshal.PtrToStringUni(value.Name),IPv4=v4,IPv6=v6,Port=value.Port,InterfaceIndex=value.InterfaceIndex};
  }
  public static void NativeFree(IntPtr instance){if(instance!=IntPtr.Zero)DnsServiceFreeInstance(instance);}
  public static Registration Begin(Advertisement ad,NativeApi api,int timeout){
   Validate(ad);if(api==null)api=new NativeApi();if(timeout<1 || timeout>60000)throw new InvalidOperationException("Invalid native callback deadline.");
   var lease=new Registration(ad,api,timeout);
   try{lease.Start();return lease;}catch{try{lease.Dispose();}catch{};throw;}
  }
  public sealed class Registration:IDisposable {
   readonly object gate=new object();readonly NativeApi api;readonly Advertisement ad;readonly int timeout;
   readonly ManualResetEvent completed=new ManualResetEvent(false);Completion callback;GCHandle root;
   IntPtr instance,request,cancel;bool pending,registered,disposeRequested,freed,cancelSent;int sending;uint operation,status;string error;
   public bool Registered {get{lock(gate)return registered && !disposeRequested;}}
   internal Registration(Advertisement row,NativeApi native,int deadline){ad=row;api=native;timeout=deadline;}
   internal void Start(){
    instance=api.Construct(ad);if(instance==IntPtr.Zero)throw new InvalidOperationException("Cannot construct native publication.");
    var actual=api.Read(instance);
    if(!SameName(actual.HostName,ad.HostName) || !SameName(actual.ServiceName,ad.ServiceName) || actual.Port!=22 || !SameAddress(actual.IPv4,ad.IPv4,AddressFamily.InterNetwork) || !SameAddress(actual.IPv6,ad.IPv6,AddressFamily.InterNetworkV6))throw new InvalidOperationException("Native constructor readback differs.");
    callback=OnCompleted;root=GCHandle.Alloc(this);
    request=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Request)));cancel=Marshal.AllocHGlobal(IntPtr.Size);Marshal.WriteIntPtr(cancel,IntPtr.Zero);
    var r=new Request{Version=1,InterfaceIndex=ad.InterfaceIndex,Instance=instance,Callback=Marshal.GetFunctionPointerForDelegate(callback),Context=IntPtr.Zero,Credentials=IntPtr.Zero,Unicast=0};Marshal.StructureToPtr(r,request,false);
    Send(0);if(!api.Wait(completed,timeout))throw new TimeoutException("Native mDNS registration callback timed out.");
    lock(gate){if(error!=null || status!=0 || !registered)throw new InvalidOperationException(error??("Native registration failed: "+status));}
   }
   void Send(uint kind){
    lock(gate){if(freed)throw new InvalidOperationException("Publication has been disposed.");operation=kind;pending=true;error=null;completed.Reset();sending++;}
    uint code;
    try{code=api.Request(kind,request,kind==0?cancel:IntPtr.Zero);}catch{lock(gate){pending=false;error="Native request threw.";completed.Set();}throw;}
    finally{lock(gate){sending--;}}
    lock(gate){if(code!=9506){pending=false;error="Native request did not return DNS_REQUEST_PENDING: "+code;status=code;completed.Set();}Cleanup();}
   }
   // This callback is entirely managed C#. No PowerShell scriptblock is invoked on native threads.
   void OnCompleted(uint result,IntPtr context,IntPtr copy){
    bool stop=false;
    try{
     lock(gate){
      status=result;
      if(operation==0){
       if(result==0){registered=true;if(copy==IntPtr.Zero || !Matches(api.Read(copy),ad)){status=13;error="Native registration callback schema differs or has no instance.";}else registered=true;}
       else{registered=false;error="Native registration callback failed: "+result;}
      }else{if(result==0)registered=false;else error="Native deregistration callback failed: "+result;}
     }
    }catch(Exception failure){lock(gate){status=13;error="Native callback read failed: "+failure.Message;}}
    finally{
     try{if(copy!=IntPtr.Zero && copy!=instance)api.Free(copy);}catch(Exception failure){lock(gate){status=13;error="Native callback free failed: "+failure.Message;}}
     lock(gate){pending=false;stop=disposeRequested && registered && operation==0;completed.Set();Cleanup();}
    }
    if(stop){try{Send(1);}catch{}}
    GC.KeepAlive(this);
   }
   void Cleanup(){
    if(freed || !disposeRequested || pending || registered || sending!=0)return;
    if(instance!=IntPtr.Zero){api.Free(instance);instance=IntPtr.Zero;}
    if(request!=IntPtr.Zero){Marshal.FreeHGlobal(request);request=IntPtr.Zero;}
    if(cancel!=IntPtr.Zero){Marshal.FreeHGlobal(cancel);cancel=IntPtr.Zero;}
    freed=true;if(root.IsAllocated)root.Free();
    // WaitHandle is released by its SafeHandle finalizer after any waiting caller leaves.
   }
   public void Dispose(){
    bool cancelNow=false,stop=false;
    lock(gate){if(freed)return;disposeRequested=true;if(pending && operation==0 && !cancelSent){cancelSent=true;cancelNow=true;}else if(!pending && registered)stop=true;Cleanup();}
    if(cancelNow){uint code;lock(gate){sending++;}try{code=api.Cancel(cancel);}finally{lock(gate){sending--;Cleanup();}}if(code!=0)throw new InvalidOperationException("Native registration cancellation failed: "+code);}
    if(stop)Send(1);
    bool wait;lock(gate)wait=pending;
    if(wait && !api.Wait(completed,timeout))throw new TimeoutException("Native cancellation/deregistration is still pending; memory retained until its callback or process exit.");
    lock(gate){Cleanup();if(!freed)throw new InvalidOperationException(error??"Native deregistration did not complete.");}
    GC.KeepAlive(callback);
   }
  }
 }
}