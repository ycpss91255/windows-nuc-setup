# SSH 客戶端設定

這是目前使用者的 `%USERPROFILE%\.ssh`，相當於 Ubuntu 家目錄下的 `~/.ssh`。
它用來設定「從本機連到其他主機」的 SSH 客戶端；不是 Windows SSH 伺服器的 `%ProgramData%\ssh\sshd_config`。

## 檔案用途

- `config`：OpenSSH 主設定。工具保留既有內容；全域的 `Include active-sites.conf` 載入自動選擇的來源。
- `active-sites.conf`：同步框架自動產生的載入清單，請不要手動修改。
- `config.d\global.conf`：安裝同步框架後，所有網路皆載入的 SSH 設定。
- `config.d\<站點ID>.conf`：符合網路站點時載入的 SSH 設定。
- `known_hosts`：SSH 連線時確認過的伺服器主機金鑰。
- `readme.md`：本說明；重裝時保留你的既有內容。

工具不會替你產生或複製私鑰。私鑰請妥善保管，不要提交到 Git 或共用 USB。

## 一般新增 SSH 主機

已有站點時，只需編輯對應的 `config.d\<站點ID>.conf`，不用每次修改 `config` 或 `active-sites.conf`。
以下是說明用範例，IP 與帳號必須換成實際資料：

```sshconfig
Host my-server
    HostName 192.0.2.10
    User remote_user
    Port 22
```

之後執行 `ssh my-server`。遠端帳號不一定等於目前 Windows 使用者名稱。
`192.0.2.10` 是文件範例 IP，不是實際設備。
不使用網路同步框架時，也可直接在 `config` 寫 `Host` 區段；自訂內容會保留，不受站點切換控制。

## 依網路切換

規則位於 `%USERPROFILE%\.config\hosts\sites.json`。新增站點需新增 `Sites` 物件，並建立相同 Id 的 `config.d\<Id>.conf`。
背景程式預設每 10 秒重讀規則；也可在 USB 工具包執行 `modules\ssh\sync_ssh.cmd` 立即同步，或加 `-VerifyOnly` 只檢查。
只用 SSH 時可將 `Outputs.Hosts` 設為 `false`，保留 `Outputs.SSH` 為 `true`；不需要建立 hosts.d 檔案。
停用輸出只停止管理，保留目前輸出；若要移除某站已匯入設定，先停用該站並同步一次，再關閉輸出。
完整網路規則說明見 USB 工具包 `modules\ssh\custom_hosts_sync\usage.txt`。

## 與 Hosts 的關係

兩者可以獨立使用：SSH 的 HostName 可直接填 IP 或 DNS／mDNS 可解析名稱。
也可以配合：系統 hosts 定義名稱與 IP，SSH 的 HostName 使用該名稱。
SSH 的 `Host my-server` 是 SSH 專用別名；它本身不會讓 `ping my-server` 或瀏覽器自動認得。
Windows 系統 hosts 位於 `%WINDIR%\System32\drivers\etc\hosts`，用途類似 Ubuntu `/etc/hosts`；本工具的來源則在 `%USERPROFILE%\.config\hosts\hosts.d`。

本資料夾設為 Windows 隱藏資料夾；已啟用顯示隱藏項目時仍看得到。
README 不會被當成 SSH 設定或同步來源。
