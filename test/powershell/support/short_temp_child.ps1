#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SuitePath,[Parameter(Mandatory=$true)][string]$SourceRoot)
$ErrorActionPreference='Stop'
try{& $SuitePath;exit 0}catch{
 $failure=$_
 $type=$failure.Exception.GetType().Name
 if($type -cnotin @('RuntimeException','PathTooLongException','DirectoryNotFoundException','FileNotFoundException','UnauthorizedAccessException','MethodInvocationException','ItemNotFoundException','IOException','ParameterBindingException')){$type='OtherException'}
 $innerType='None';$innerHResult=0
 if($failure.Exception.InnerException){$innerType=$failure.Exception.InnerException.GetType().Name;$innerHResult=[int]$failure.Exception.InnerException.HResult;if($innerType -cnotin @('ArgumentException','PathTooLongException','DirectoryNotFoundException','FileNotFoundException','UnauthorizedAccessException','IOException','NotSupportedException','SecurityException')){$innerType='OtherException'}}
 $relative='outside_source';$line=0
 $prefix=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')+'\'
 $file=[string]$failure.InvocationInfo.ScriptName
 if($file -and $file.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
  $candidate=$file.Substring($prefix.Length).Replace('\','/')
  if($candidate -cmatch '^(core|modules|script|test)/[a-z0-9_/.-]+\.ps1$'){$relative=$candidate;$line=[int]$failure.InvocationInfo.ScriptLineNumber}
 }
 Write-Host ('@@SHORT_TEMP_ERROR@@'+(@{Type=$type;Source=$relative;Line=$line;Reason='ChildException';HResult=[int]$failure.Exception.HResult;InnerType=$innerType;InnerHResult=$innerHResult}|ConvertTo-Json -Compress))
 exit 1
}
