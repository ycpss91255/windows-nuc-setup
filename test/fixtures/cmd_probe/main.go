// Test-only substitute: never invokes PowerShell or any Windows setup action.
package main

import("encoding/json";"os";"strconv")
func main(){cwd,_:=os.Getwd();data,_:=json.Marshal(struct{Arguments []string; Directory string}{os.Args[1:],cwd});f,err:=os.OpenFile(os.Getenv("CMD_PROBE_OUTPUT"),os.O_APPEND|os.O_CREATE|os.O_WRONLY,0600);if err!=nil{os.Exit(111)};f.Write(append(data,'\n'));f.Close();code,err:=strconv.Atoi(os.Getenv("CMD_PROBE_EXIT"));if err!=nil{os.Exit(112)};os.Exit(code)}
