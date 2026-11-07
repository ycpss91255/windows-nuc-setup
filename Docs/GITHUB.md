# Git 儲存庫與完整工具包

## 兩種取得方式

目前 Downloads 的完整 `Windows-NUC-Setup` 資料夾包含驅動與必要工具，可依根目錄 README 整包複製使用。

Git 儲存庫則只保存程式、文件、範本、測試及必要的上游來源資產。**從 GitHub clone 或下載原始碼 ZIP，不等於取得完整可執行工具包。** GitHub 上的程式也不會自動下載所有二進位。

## 從原始碼準備完整工具包

1. 保留整個目錄結構，不只複製 `Init.cmd` 或 `Windows.cmd`。
2. 準備 `Modules/Accounts/Autologon64.exe`：可從自己已核對的完整包複製，或從 [Microsoft Sysinternals 官方頁](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon) 取得；執行時會驗證 Microsoft 簽章。
3. 將下列四個檔案放入 `Modules/Drivers/Payload`，與該目錄的 `manifest.json` 並列：

   - `Chipset-Win10_Win11-10.1.19376.8374.zip`
   - `SerialIO-WIn10_Win11-30.100.1914.3.zip`
   - `UCM-WIN11-1.0.10.3.zip`
   - `GFX-Radeon-Win10-23.10.01.46.zip`

   可從自己已核對的完整包複製。若需重新取得，應使用設備／供應商的可信來源；取得的版本必須符合清單。不要為了繞過檢查直接修改 SHA256。換版是獨立維護工作，需要驗證並留下紀錄。
4. 在工具包目錄執行只讀套件檢查：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Core\Test-SetupPrerequisites.ps1 -PackageOnly
   ```

   缺少 EXE、驅動或雜湊不符時會停止並顯示原因。檢查不會建立帳號或套用 Windows 設定。
5. 通過後依根目錄 [README.md](../README.md) 執行 Init／Windows 流程。完整 OOBE 實機驗證限制仍適用。

`Package-Hashes.json` 是本機交付包的雜湊快照，不追蹤於 Git；Git clone 不會帶有此檔。前置檢查使用受追蹤的驅動 manifest，不以缺少這份交付快照當成程式損壞。

## 不納入 Git 的內容

- 驅動 ZIP、Autologon EXE、安裝封存檔與其他大型二進位。
- 各機 `Reports`、進度、結果、快取、備份與執行日誌。
- `.ssh`、私鑰、known_hosts、密碼、Token、Init answer file、owner/runtime/state 等實機資料。
- 本機套件雜湊快照與暫存測試副本。

忽略規則不會刪除本機完整包的必要檔案。不要為了讓 Git 工作樹乾淨而刪除驅動或使用者自訂設定。

## 發布前仍需決定

公開版 `Modules/SSH/CustomHostsSync/sites.json` 使用空白 Sites，不帶公司、SSID 或實際網段；個人規則只在各機的使用者設定目錄維護。公開倉庫採乾淨新歷史，不推送曾含私人環境資訊的舊提交。

發布前仍須掃描來源與提交歷史，確認沒有密碼、私鑰、個人網路規則或實機報告。Git 作者資訊應使用適合公開的身分。

- 目標 GitHub 帳號、儲存庫名稱及公開／私人可見性。
- 自有程式對外使用的授權；目前沒有擅自加入 MIT 或其他授權。
- 若要提供完整二進位下載包，先確認各第三方再散布權限；不能直接把忽略中的驅動和 EXE 全數上傳。

第三方來源與各自授權見 [THIRD_PARTY.md](../THIRD_PARTY.md)。儲存庫可設定 remote 並依維護者授權發布；請以目前 Git remote 與 GitHub 狀態為準。

## Windows CI

工作流程位於 .github/workflows/windows-tests.yml：使用 windows-2022、Windows PowerShell 5.1、唯讀 contents 權限，設定 15 分鐘上限與相同分支舊執行取消。Action 固定到已核對的 commit。main 推送、Pull Request 與 workflow_dispatch 都可觸發。

Tests/Run-CI.ps1 可在本機以 Windows PowerShell 5.1 執行，預設把報告放在新建暫存目錄；不套用任何實際使用者設定。它執行自有 PowerShell 語法檢查、Layout.Tests.ps1 -SourceOnly、Init.Tests.ps1、InputMethod.Tests.ps1、SourceRelease.Tests.ps1、HostsSync.Tests.ps1。SourceOnly 只略過 Git 不含的 Autologon EXE 存在檢查，仍核對所有來源、必要資產、驅動 manifest 與入口。實機 Core/Test-SetupPrerequisites.ps1 -PackageOnly 未降低標準，仍要求 EXE 與四個驅動實體檔案及雜湊正確。

每次 CI 將各套件 log 與 summary 上傳為 windows-test-reports artifact，保留 7 天。只上傳明確的 CI 報告資料夾，不上傳測試 fixture、帳號 answer XML、每機 Reports 或秘密。Actions 本身執行 log 的保留天數另由儲存庫設定控制，不是 YAML artifact 保留期。

實機 Setup-Result.json、Setup-Progress.json、Acceptance-Result.json 與驗證結果是續跑或排錯資料，原有 Git 忽略規則保留；CI 不清理這些檔案。設定未完成時不要刪除 Setup-Result.json。雲端通過僅代表來源／隔離測試成功，不表示 NUC 硬體或 OOBE 已通過實機驗收。

## 自動發布來源版本

.github/workflows/windows-cd.yml 監聽 v* 標籤，並驗證格式為 vX.Y.Z。先執行 Windows CI，成功後才由獨立的 contents:write 發布工作建立來源 ZIP／SHA256 與中文版本說明。詳見 RELEASE.md。Build-SourceRelease.ps1 只封裝指定 Git 提交，不帶未追蹤的本機驅動、Reports 或 Git metadata；SourceRelease 隔離測試驗證中文空白路徑、校驗值、拒絕覆寫與拒絕敏感檔。CI/CD不會自動建立版本標籤。
