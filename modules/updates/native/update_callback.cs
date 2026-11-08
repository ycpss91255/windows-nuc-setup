using System.Runtime.InteropServices;
namespace WindowsSetup {
    // WUA supports Automation callbacks with DISPID 0 and (job, callbackArgs).
    // No job reference is retained; the PowerShell owner polls and cleans up outside callbacks.
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.AutoDispatch)]
    public sealed class UpdateCallback {
        [DispId(0)]
        public void Invoke(object job, object callbackArgs) { }
    }
}