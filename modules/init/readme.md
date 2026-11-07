# Init：建立本機帳號與準備 SSH

根目錄只需兩個入口：`init.cmd` 負責帳號初始化與 SSH；`windows.cmd` 負責登入後的 19 個 Windows 設定模組。兩者不會自動重新開機。

## 正在初始設定的 Wi-Fi 畫面

1. 保持離線，按 `Shift+F10` 開命令視窗（部分鍵盤需 `Fn+Shift+F10`）。從 USB 的工具包執行 `init.cmd`，磁碟代號可不同。
2. 此時命令視窗通常是 SYSTEM；Microsoft 不支援以 SYSTEM 執行 Sysprep。Init 會辨識並顯示下一步，不會在此寫密碼或建立帳號。
3. 關閉命令視窗，在設定畫面按 `Ctrl+Shift+F3`。**這個快捷鍵會重新開機**並進入稽核模式的 Administrator 桌面。
4. 按「取消」關閉自動出現的 Sysprep 對話框，從 USB 再執行同一個 `init.cmd`。
5. 輸入 `AUDIT` 確認你是由上述快捷鍵進入。這個確認是必要護欄：系統狀態與 Administrator 帳號不能單獨證明目前是稽核模式。
6. 輸入要建立的本機管理員帳號、密碼，再確認密碼。帳號最多 20 字，不可與現有帳號重複；密碼非空、最多 127 字，仍須符合這份 Windows 映像的密碼政策。
7. Init 用 Windows 支援的 answer file 與 `Sysprep /oobe /quit /unattend` 準備下一輪初始設定。它不使用 generalize，不假造 Setup 完成旗標，也不使用已被部分版本移除的 bypass 命令。
8. 顯示準備成功後，**手動重新啟動**。完成 Windows 仍要求的地區、隱私等設定，用剛才的本機帳號登入；不需要 Microsoft 帳號。

此流程不能保證所有 Windows 映像都可直接執行。若有既有 answer file、未知安裝狀態、S mode、仍開啟的 Sysprep、或 Sysprep 錯誤，Init 會停止並顯示原因；不要反覆重跑或假稱初始化完成。原生 Windows 安裝產生的 answer file 快取也可能觸發保守拒絕，並不代表一定是 OEM 衝突；請先了解來源，**不要任意刪除既有 answer file**。第一次部署尚需在實際全新 Windows 驗證。

## 正式使用者桌面：啟用 SSH

1. 登入剛建立的正式本機管理員帳號，再執行 `init.cmd` 並允許目前帳號提權。這個階段沿用帳號，不會再詢問或重設密碼。
2. Init 呼叫 SSH 模組安裝 OpenSSH Server、啟動服務與設定區域網路防火牆，並在這個正式使用者下準備 `.ssh` 與 hosts 同步框架。它不會把這些使用者設定放進稽核模式的 Administrator。
3. 如果離線且系統沒有 OpenSSH 安裝來源，安裝可能失敗。請連網後重跑 `init.cmd`；只有服務實際啟動且模組完成才會顯示成功。成功後會顯示電腦名稱、目前帳號、可用 IPv4 及 `ssh 帳號@IP` 連線範例，不顯示密碼；沒有 IPv4 時會提示先接上區域網路。
4. 接著執行 `windows.cmd` 完成 Windows 設定。更新要求重開時等整輪結束，再手動重開，依根目錄 README 執行重開後驗收。

## 密碼暫存與失敗處理

帳號密碼不會寫進 USB、Git 或輸出紀錄。Windows answer file 需要可還原的密碼編碼；**Base64 不是加密**。Init 只將它寫到本機 `%ProgramData%\NUC-Init`，資料夾限 SYSTEM 與管理員讀寫，並於正式帳號首次登入時清理自己的來源檔及可確認屬於本工具的 Windows 快取。

狀態看 `%ProgramData%\NUC-init\cleanup-result.json`。清理依本輪唯一標記辨認檔案，不刪除其他工具／OEM 的 answer file。若安裝未完成或清理失敗，暫存檔可能仍存在；必須先確認並處理，不能當作沒有密碼殘留。Init 發現先前暫存資料會拒絕覆寫，需先檢查原因；它不會自動刪除不明資料來強行重跑。

本工具無法保證安全清除磁碟上的舊資料區塊；檔案刪除也不是磁碟抹除。Windows 自身是否已處理其他快取，以其安裝狀態為準。

## 官方依據

- [以 Ctrl+Shift+F3 進入稽核模式](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/boot-windows-to-audit-mode-or-oobe?view=windows-11)
- [Sysprep 概觀與限制](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview?view=windows-11)
- [Sysprep 命令列選項](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11)
- [自動化 OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)
- [LocalAccount 群組名稱的跨語言行為](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts-localaccount-group)
- [Windows Setup 狀態](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-states?view=windows-11)
