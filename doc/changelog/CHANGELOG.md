# 版本變更紀錄

本文件記錄使用者可見的行為、相容性及遷移要求。詳細實作與驗證紀錄見中文 Git 提交；發布版本與來源提交以 GitHub Release 為準。

## [Unreleased]

### Added（新增）

- 依真實斷言與程序結果自動產生分層 HTML／JSON／JUnit 報表及 SVG 徽章；main 公開報表由 Pages 更新，PR 僅保留七天去識別附件。
- 明列 System／E2E 未執行與 Coverage 未量測，新增報表失敗、跳過、編碼與資料隱藏的隔離測試。
- 品質頁補上一般使用者結論、版本／分支範圍、變更與限制、來源下載及可查閱 JSON／JUnit；比較與不穩定性無證據時明示 Unknown。
- 版本品質快照由 Release 長期保存，Pages 使用原始量測時間重建；舊版沒有快照時不回填假結果。

### Fixed（修正）

- 主流程遇失敗先寫結果再回傳非零退出碼；驅動解壓快取依雜湊隔離，驗證以本輪識別與擁有者拒絕舊報告，Windows Update 核對完整結果數量。



### Changed（變更）

- 依使用者決定，在取得合適 Windows 11 x64 可丟棄測試環境前暫緩 System／完整安裝 E2E；保留未驗證狀態與 v0.2.0 預覽標記，合併仍需 PR／ci-rollup。
- 第三方來源與授權說明移至 doc/THIRD_PARTY.md，根 README 引用；修正相對連結與獨立驅動包位置。AGENTS.md 保留根目錄供工具自動發現，第三方授權檔不搬動。

## [v0.2.0] — 2026-11-07

### Changed（變更）

- Windows 主流程以通用 Windows 為預設；驅動移至獨立可攜包，只有相符 NUC 主機板且明確選包才安裝，直接 Enter 預設略過。其他機型不再因 NUC 機型檢查被阻擋。
- 版本檔、版本準備命令、PR 與 ci-rollup 統一發布流程；標籤須對應 main 歷史、版本檔與 changelog。
- RC 發布標為預覽版；正式版整合同版 RC 紀錄。使用 GitHub 內建來源下載，不再上傳重複的來源 ZIP 與 SHA256。

- 測試分為 Unit／Integration／System，CI 明示 System／E2E 未執行，避免將隔離測試當作完整安裝驗證。
- 自有目錄改小寫與底線，更新入口與路徑映射；維護工具分至 script/test、script/release、script/package，交付執行樹不依賴測試或發布工具。新驅動日誌使用 driver_logs；既有 ProgramData／排程識別及第三方原始內容保留。

- 通用流程不代表已在每種硬體完成實機驗收。現有 NUC 驅動僅提供給相符設定檔，其他硬體需使用自己的 Windows Update 或原廠驅動。
- v0.1.x 既有 Release、來源資產與標籤保持原樣。

## v0.1.2 — 2026-11-07

### Changed（變更）

- 完整安裝、來源包準備、獨立模組、測試及發布說明集中於根目錄 README.md，依正式專案格式提供目錄與快速開始。
- 版本紀錄移至 doc/changelog；移除重複的 Docs 文件。舊「使用說明.txt」路徑別名仍解析到 README.md。

### Removed（移除）

- 不再維護根目錄 CHANGELOG.md 或重複使用說明。從舊版本找文件時，請改讀 README.md 與本文件。

## 初始公開版本系列（v0.1.x）

### Added（新增）

- Init 提供本機帳號及 SSH 初始化；Windows 入口依模組執行設定，支援重新開機後續跑及只讀驗收。
- 提供自動登入、電源、分頁檔、更新、預裝 App／OneDrive 清理、工作列、桌面、深色背景、英文美式鍵盤與 Terminal 快捷鍵模組。
- SSH 與 hosts 可獨立同步，站點規則由目前使用者動態維護；公開範本不包含私人主機清單或金鑰。
- Windows CI 執行語法與隔離測試；版本標籤通過測試後發布來源 ZIP 與 SHA256。CI 報告短期保存，實機續跑紀錄留在原機。

### Changed（變更）

- 對外產品名稱為 Windows 設定工具，儲存庫為 windows_setup；發布包採 windows_setup_vX.Y.Z_source.zip，根目錄 windows_setup/。
- 完整工具包可整包搬移到可寫入且非桌面的路徑，動態取得帳號與工具包位置，不固定使用者名稱或磁碟代號。
- 目前 Windows 一鍵硬體設定檔與內建驅動仍限定 NUC8i7HV/HN；其他硬體並未因改名而自動支援。既有 ProgramData 與續跑識別保留。

### Security（資料保護）

- Git 與來源發布包排除帳號暫存、私鑰、個人網路規則、每機紀錄及安裝二進位；完整包仍須自行補齊可信來源的 Autologon 與驅動並通過檢查。

### 驗證界限

雲端測試驗證來源與隔離邏輯，不能代替新電腦的 OOBE、更新、驅動、登入與顯示驗收。Windows 版本與硬體差異可能影響結果。