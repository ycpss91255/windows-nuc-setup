# Init：初始設定與正式帳號 SSH

一般使用步驟以根目錄 [readme.md](../../readme.md) 的快速開始 A／B 為準。初始設定從 USB 按 Shift+F10 呼叫 init.cmd；不要求切換稽核模式。已有正式帳號時，沿用目前帳號安裝 SSH，不重設密碼。

## 發行完整性

OOBE 入口需要 assets/hide_oobe.ppkg、hide_oobe.xml、provenance.json，發行包另包含 CI 內容檢驗使用的 payload_baseline.json。這是本專案自身產生的小型設定資產，只含 OOBE/Desktop/HideOobe=True，不包含帳密或 Microsoft 編譯工具。原始 XML、固定官方 ICD 身分與輸出 SHA256 都由 provenance 追溯；產物不是位元完全可重現，不能只以重新編譯 hash 相同作驗收。

設定包與已審查的 payload_baseline.json 一同保存；基線由 CI 真正抽取的七份 XML 逐檔重算 SHA256，經主代理及獨立代理確認。缺檔、hash、來源 XML、package ID／名稱／版本不符時，入口在帳號建立前拒絕。單元測試使用的合成檔案不能代替真包。

## OOBE 安全順序

1. 確認 Windows 11 22H2 以上 x64 桌面版、SYSTEM、非 WinPE；官方唯讀 OOBEComplete API 必須成功且回報初始設定未完成。Setup 旗標與程序清單僅為診斷。
2. 唯讀核對完整設定資產；於 ProgramData 建立受保護的 preparing 目錄，複製自身執行依賴、儲存不含密碼的初始狀態後，才原子更名為 windows_setup_init。失敗保留明確診斷目錄，不刪未知檔案。
3. 準備同層 windows_setup_init.cmd 公開唯讀啟動器；此檔先 UAC，再讀私有 runtime。既有啟動器須通過位置、owner、ACL 與內容 hash，不覆寫來源不明的同名檔。
4. 詢問新帳號與兩次 SecureString 密碼。拒絕既有同名帳號；不重設密碼或提升既有帳號。建立後讀回 SID、啟用狀態及 Administrators 群組 SID 成員。
5. 先記錄 ApplyPending，再清楚提示 Windows 可能立即重新啟動；輸入 YES 才套用設定包。取消保留帳號及 AwaitingConsent；重跑不需重建帳號。SYSTEM 分支不使用 Sysprep。
6. 正式帳號登入後，開啟 %ProgramData%\windows_setup_init.cmd，同意同帳號提權。續跑核對機器、目標 SID、ProfileList 與 Explorer 桌面，再呼叫完整 SSH 模組；不依原 USB 代號。SSH 服務 Running／Auto 及防火牆驗證都成功後才顯示完成與中文連線資訊。

私有狀態與 runtime 只供 SYSTEM／管理員存取。狀態不包含明文、編碼或加密後的密碼；密碼僅在帳號建立呼叫中使用。公開啟動器只給 Users 讀取及執行，不能寫入私有資料。

## 失敗與恢復

- 缺少網路或 OpenSSH 元件來源：保持 SshPending，連網後執行同一公開入口重試。
- 套包已成功但回應中斷：以已安裝的 package ID／版本／名稱恢復，不盲目重複套用。
- 帳號已建立、SID 已儲存但群組失敗：只能恢復相同 SID，驗證後繼續。
- 帳號已建立但所有權狀態寫入失敗：保留帳號，停止而不刪除／接管同名帳號。這種情況不宣稱可以自動恢復，需先查看錯誤及受保護紀錄。
- 狀態檔 ACL／owner、machine ID、SID 或設定包改變：拒絕續跑，不清除紀錄硬闖。

既有非 SYSTEM 稽核維護程式保留相容用途，不作一般使用者安裝流程。若曾使用舊版 answer file，cleanup_oobe.ps1 仍依唯一標記清理自己的暫存；不刪除其他 OEM answer file。

## 維護與內容驗證

維護者可以檢閱 script/package/build_oobe_asset.ps1；它只接受固定官方 ICD 的簽章、版本與 SHA256，建立自己的 XML／設定包／provenance，不下載、安裝或套用設定。一般使用者不需要 ADK／WCD。

CI 的 oobe_payload_inspection 獨立使用 script/test/verify_oobe_payload.ps1，以原生 WIM 唯讀列檔和抽取七個允許路徑；所有 XML 禁止 DTD／外部實體，並限制大小。沒有已由主代理及獨立審查確認的 payload_baseline.json 時會失敗，保留七天內容證據供審查，不能視為通過。這是設定資產檢查，不是 Windows 安裝 E2E。

官方依據：[OOBEComplete](https://learn.microsoft.com/en-us/windows/win32/api/oobenotification/nf-oobenotification-oobecomplete)、[WCD OOBE 設定](https://learn.microsoft.com/en-us/windows/configuration/wcd/wcd-oobe)、[設定包命令列建置](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-command-line)。

來源與原生 metadata 分層：Assert-InitProvisioningAssetSource 只核對三檔來源；runtime 使用的 Assert-InitProvisioningAsset 始終再呼叫 Windows 11 client 原生 API，缺少命令或 metadata 不符即失敗。Server CI 的真 WIM 內容檢驗不冒稱 client metadata 測試；本機唯讀六項檢查命令見根目錄 README 的 Windows CI 章節。
