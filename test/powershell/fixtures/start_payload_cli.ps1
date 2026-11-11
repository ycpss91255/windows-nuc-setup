#Requires -Version 5.1
param([string]$TargetScript,[string]$PackagePath,[string]$EvidenceDirectory,[string]$BaselinePath)
$ErrorActionPreference='Stop'
# A fresh child executes the real public script entry after preloading an inert reader.
# No WIM library is loaded and no Windows provisioning API is invoked.
Add-Type -TypeDefinition @"
using System;
using System.IO;
namespace WindowsSetup {
 public static class OobeWimReader {
  public static void Extract(string package,string destination,string[] allowed) {
   if(File.ReadAllText(package)!="synthetic test fixture")throw new Exception("Unexpected CLI package argument.");
   foreach(string name in allowed){string path=Path.Combine(destination,name.Replace('/',Path.DirectorySeparatorChar));Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,"<fixture xmlns='urn:cli-test'/>");}
  }
 }
}
"@
& $TargetScript -PackagePath $PackagePath -EvidenceDirectory $EvidenceDirectory -BaselinePath $BaselinePath