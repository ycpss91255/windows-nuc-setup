# Hosts 與依網路同步設定

這個資料夾是目前使用者的 `%USERPROFILE%\.config\hosts`，位置維持不變。
它存放本工具的規則與來源，並不是 Windows 系統的 hosts 檔。
真正供 Windows 名稱解析使用的檔案位於 `%WINDIR%\System32\drivers\etc\hosts`，用途類似 Ubuntu 的 `/etc/hosts`。

## 檔案用途

- `sites.json`：依網路選擇站點的規則與 Hosts／SSH 個別開關。
- `hosts.d\global.hosts`：所有網路都使用的名稱與 IP 對照。
- `hosts.d\<站點ID>.hosts`：該站點啟用時匯入的名稱與 IP 對照。
- `readme.md`：本說明；重裝時保留既有內容，不覆寫你的修改。

## 修改方式

已有站點只新增主機：修改對應的 `.hosts` 檔，每行格式為 `IP 名稱 [其他別名]`。
新增網路站點：先在 `sites.json` 的 `Sites` 陣列新增唯一 `Id` 與 `Rules`，再建立同名 `hosts.d\<Id>.hosts`。
站點不限六組。規則可用 `SSID`、`NetworkProfile`、`IPv4Cidr`、網卡名稱等；規則欄位範例與說明見 USB 工具包 `modules\ssh\custom_hosts_sync\usage.txt`。
讀取 SSID 受 Windows 定位權限限制時，可改用 NetworkProfile 或 IPv4Cidr；程式不會自行開啟定位。

安裝同步框架後，背景程式預設每 10 秒重讀規則與來源。也可從 USB 工具包執行 `modules\ssh\sync_hosts.cmd` 立即同步，或 `modules\ssh\sync_hosts.cmd -VerifyOnly` 只檢查。
程式僅管理系統 hosts 的 `# BEGIN custom-hosts` 到 `# END custom-hosts` 區塊，其餘內容保留；請修改來源，避免直接修改自動管理區塊。
未提供真實主機清單時，來源只是空白範本，不會自行產生主機 IP。

## Hosts 與 SSH 可以獨立或搭配

- 只用 Hosts：名稱可供 ping、瀏覽器等解析，不需要 SSH。
- 只用 SSH：在 `%USERPROFILE%\.ssh\config` 或其載入的設定中將 `HostName` 填 IP／可解析名稱，不需要自訂 hosts。
- 搭配使用：Hosts 定義名稱與 IP，SSH 的 `HostName` 使用該名稱，再設定遠端帳號、連接埠與金鑰。

`sites.json` 的 `Outputs` 分別控制 `Hosts` 和 `SSH`。設為 `false` 表示停止管理該輸出，保留目前內容，不會自動清除既有匯入。
若要移除某站的匯入內容，先停用該站並讓輸出同步一次，再關閉對應輸出。
只需要 Hosts 時不用建立 SSH 來源；只需要 SSH 時不用建立 hosts.d 來源。
共享規則 JSON 無效時兩邊保留上次輸出；單側來源有錯時另一側仍可更新。

## 狀態與注意事項

狀態檔為 `%ProgramData%\CustomHostsSync\status.json`；背景工作名稱是 `CustomHostsSync`。
系統 hosts 是全機共用，本同步工具每台只允許一個使用者管理，避免不同帳號互相覆寫。
`.local` 的 mDNS 名稱解析是另一種機制，不需要為此必然新增 hosts 紀錄。
這份 README 不會被當成同步來源，也不會改變規則或主機設定。
