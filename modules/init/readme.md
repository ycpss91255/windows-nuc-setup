# Init：帳號與 OOBE 初始化

一般使用步驟以根目錄 [readme.md](../../readme.md) 的快速開始 A／B 為準。初始設定從 USB 按 Shift+F10 呼叫 init.cmd；不要求切換稽核模式。已有正式帳號時，直接執行 windows.cmd，不需要再次執行 Init；SSH 由 Windows 第 4 階段處理。

## 已用 Ctrl+Shift+F3，Init 跑完接著做什麼？

1. `Ctrl+Shift+F3` 會重新啟動到稽核模式的 Administrator 桌面；先取消自動出現的 Sysprep 視窗。
2. 從 USB 執行 `windows_setup\init.cmd`，Init 自動檢查帳號與 OOBE 準備條件，不需要輸入 `AUDIT`；同意受限的帳號／OOBE 變更並輸入 `YES` 後，再輸入新正式本機帳號、密碼及確認密碼。
3. 看到 **「帳號設定已準備完成」**，表示這一階段成功，接著才手動重新啟動。可由開始選單操作，或在 CMD 輸入 `shutdown /r /t 0`。腳本不會自行替你重新啟動。
4. 重開後完成剩餘 OOBE，登入新正式本機帳號；不要在稽核模式 Administrator 身分直接套用 Windows 設定。
5. 在新帳號桌面接上網路，直接從完整工具包執行 `windows.cmd`；不需要第二次 Init。SSH 由 Windows 第 4 階段安裝。

如果出現錯誤、非零退出碼，或沒有「帳號設定已準備完成」，這一階段尚未成功；先保留錯誤畫面並修正問題，不以命令視窗關閉代表完成。若帳號準備成功但尚未重開，下一步就是手動重新啟動，而不是重複建立帳號。

這條可選路線不取代初始設定畫面 `Shift+F10` 直接執行 Init 的路線。兩條路線最後都在新正式帳號桌面直接執行 Windows 設定。

## 發行完整性

OOBE 入口需要 assets/hide_oobe.ppkg、hide_oobe.xml、provenance.json，發行包另包含 CI 內容檢驗使用的 payload_baseline.json。這是本專案自身產生的小型設定資產，只含 OOBE/Desktop/HideOobe=True，不包含帳密或 Microsoft 編譯工具。原始 XML、固定官方 ICD 身分與輸出 SHA256 都由 provenance 追溯；產物不是位元完全可重現，不能只以重新編譯 hash 相同作驗收。

設定包與已審查的 payload_baseline.json 一同保存；基線由 CI 真正抽取的七份 XML 逐檔重算 SHA256，經主代理及獨立代理確認。缺檔、hash、來源 XML、package ID／名稱／版本不符時，入口在帳號建立前拒絕。單元測試使用的合成檔案不能代替真包。

## OOBE 安全順序

1. 確認 Windows 11 22H2 以上 x64 桌面版、SYSTEM、非 WinPE；官方唯讀 OOBEComplete API 必須成功且回報初始設定未完成。Setup 旗標與程序清單僅為診斷。
2. 唯讀核對完整設定資產；於 ProgramData 建立受保護的 preparing 目錄，複製自身執行依賴、儲存不含密碼的初始狀態後，才原子更名為 windows_setup_init。失敗保留明確診斷目錄，不刪未知檔案。
3. 準備同層 windows_setup_init.cmd 公開唯讀啟動器；此檔先 UAC，再讀私有 runtime。既有啟動器須通過位置、owner、ACL 與內容 hash，不覆寫來源不明的同名檔。
4. 詢問新帳號與兩次 SecureString 密碼。拒絕既有同名帳號；不重設密碼或提升既有帳號。建立後讀回 SID、啟用狀態及 Administrators 群組 SID 成員。
5. 先記錄 ApplyPending，再清楚提示 Windows 可能立即重新啟動；輸入 YES 才套用設定包。取消保留帳號及 AwaitingConsent；重跑不需重建帳號。SYSTEM 分支不使用 Sysprep。
6. 正式帳號登入後，直接執行完整工具包的 windows.cmd。既有 UAC 後、任何設定前會核對機器、目標 SID、ProfileList、Explorer 桌面、正式帳號與群組及已安裝設定包，再記錄 AccountConfirmed。此狀態只代表帳號／OOBE 確認；SSH 在 Windows 第 4 階段安裝。沒有 Init 狀態的既有正式帳號不需要此檢查。

私有狀態與 runtime 只供 SYSTEM／管理員存取。狀態不包含明文、編碼或加密後的密碼；密碼僅在帳號建立呼叫中使用。公開啟動器只給 Users 讀取及執行，不能寫入私有資料。

## 失敗與恢復

- 取消或中斷 OOBE：可使用受保護的公開啟動器恢復；正常正式登入後直接執行 windows.cmd，不必再跑 Init。
- 舊版 SshPending／Complete：通過同機、SID、profile、帳號與設定包驗證後，先保存受保護的 state_before_account_confirmation.json，再轉為 AccountConfirmed；不刪除舊 stage，不假稱 SSH 完成。
- Windows 第 4 階段缺少網路或 OpenSSH 元件：連網後重跑 Windows 或 modules/ssh/apply_ssh_settings.cmd；Init 不安裝 SSH。
- 套包已成功但回應中斷：以已安裝的 package ID／版本／名稱恢復，不盲目重複套用。
- 帳號已建立、SID 已儲存但群組失敗：只能恢復相同 SID，驗證後繼續。
- 帳號已建立但所有權狀態寫入失敗：保留帳號，停止而不刪除／接管同名帳號。這種情況不宣稱可以自動恢復，需先查看錯誤及受保護紀錄。
- 狀態檔 ACL／owner、machine ID、SID 或設定包改變：拒絕續跑，不清除紀錄硬闖。

非 SYSTEM 稽核路線保留為可選操作方式，適用於已使用 Ctrl+Shift+F3 進入 Administrator 的情況。若曾使用舊版 answer file，cleanup_oobe.ps1 仍依唯一標記清理自己的暫存；不刪除其他 OEM answer file。

## 維護與內容驗證

維護者可以檢閱 script/package/build_oobe_asset.ps1；它只接受固定官方 ICD 的簽章、版本與 SHA256，建立自己的 XML／設定包／provenance，不下載、安裝或套用設定。一般使用者不需要 ADK／WCD。

CI 的 oobe_payload_inspection 獨立使用 script/test/verify_oobe_payload.ps1，以原生 WIM 唯讀列檔和抽取七個允許路徑；所有 XML 禁止 DTD／外部實體，並限制大小。沒有已由主代理及獨立審查確認的 payload_baseline.json 時會失敗，保留七天內容證據供審查，不能視為通過。這是設定資產檢查，不是 Windows 安裝 E2E。

官方依據：[OOBEComplete](https://learn.microsoft.com/en-us/windows/win32/api/oobenotification/nf-oobenotification-oobecomplete)、[WCD OOBE 設定](https://learn.microsoft.com/en-us/windows/configuration/wcd/wcd-oobe)、[設定包命令列建置](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-command-line)。

來源與原生 metadata 分層：Assert-InitProvisioningAssetSource 只核對三檔來源；runtime 使用的 Assert-InitProvisioningAsset 始終再呼叫 Windows 11 client 原生 API，缺少命令或 metadata 不符即失敗。Server CI 的真 WIM 內容檢驗不冒稱 client metadata 測試；本機唯讀六項檢查命令見根目錄 README 的 Windows CI 章節。

## 自動判斷的範圍

此入口判斷的是受控帳號／OOBE 準備條件，並非呼叫 Windows 的正式 Audit 模式識別 API。它同時要求 Windows 11 client x64、非 WinPE、原生 OOBEComplete 成功且未完成、目前管理員 token 對應的本機內建 Administrator SID500（不要求 SAM 帳號 Enabled；稽核登入後帳號可能停用）、同工作階段桌面擁有權與原生／登錄家目錄一致、已知未完成 ImageState、沒有同工作階段 OOBE／Setup／Sysprep 程序。ImageState 不單獨證明目前模式，也不使用猜測的 AuditBoot registry 結構。未公開文件定義的 Setup registry 旗標只保留原型別作診斷，不把缺省值轉成 0 或當成模式證明。未知、讀取失敗或矛盾會於帳密與任何寫入前停止。

完成 OOBE 的正式帳號桌面只提示執行 windows.cmd，不重新準備帳號。受控準備仍保留現有 answer file、Sysprep 程序、S mode、暫存擁有權及清理防護；同意後只執行 /oobe /quit，不執行 generalize 或自動重開。

依據：[OOBEComplete](https://learn.microsoft.com/en-us/windows/win32/api/oobenotification/nf-oobenotification-oobecomplete)、[Windows Setup States](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-states?view=windows-11)、[Sysprep 選項](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11)。此路線用於全新安裝前置，不用來修復已交付或損壞的 Windows。

原生帳號狀態依據：[Microsoft KB3141410](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/fail-to-turn-off-computer-from-audit-mode)，Audit 的內建 Administrator 可於登入後立即停用；本工具不因此啟用它。
