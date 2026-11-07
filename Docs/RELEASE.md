# CI 與 CD 版本發布

CI 在提交、Pull Request 或手動觸發時執行 Windows PowerShell 5.1 的語法、路徑與隔離測試，不設定實際帳號、不安裝驅動，也不執行 Sysprep。

CD 由 `v主版.次版.修訂` 標籤觸發，例如 `v1.0.0`。它先執行相同 CI；成功後才建立該提交的來源 ZIP、SHA256 清單及中文 GitHub Release。無效標籤或測試失敗都不發布。既有版本不會被覆寫。

## 發布方式

確認 main 的 CI 通過、更新中文 CHANGELOG，並完成 [公開前檢查](GITHUB.md) 後，在要發布的提交執行：

```powershell
git tag -a v1.0.0 -m "發布 v1.0.0：Windows 初始化與模組設定"
git push origin v1.0.0
```

標籤會觸發 GitHub 上的「Windows 版本發布」流程。版本號應逐次增加，不要移動或重用已發布的標籤。此文件只是操作說明，建立工作流程不代表已建立任何版本標籤。

## 下載內容與保留期限

來源包命名為 `windows_setup_vX.Y.Z_source.zip`，ZIP 根目錄是 `windows_setup/`，版本標題為「Windows 設定工具」。儲存庫名稱為 `windows_setup`。目前一鍵流程仍使用 NUC8i7HV／HN 硬體設定檔；改名不會擴大硬體支援範圍。

- Release ZIP 只含該提交的 Git 來源，不包含 `.git`、驅動 ZIP、Autologon EXE、實機 Reports 或密碼暫存；打包器會拒絕已被錯誤追蹤的這些檔案。
- 依 [GITHUB.md](GITHUB.md) 補齊二進位後才是完整安裝工具包，不能把來源 ZIP 當成完整離線安裝包。
- Release ZIP 與 SHA256 是版本交付物，會持續保留，除非維護者手動刪除該版本。
- CI／CD 測試報告作為 Actions artifact 保留 7 天，不提交進 Git。實機續跑紀錄不受 Actions 清理影響。
- CD 只發布版本檔，不會連線或部署到任何電腦；OOBE、驅動、自動登入及硬體功能仍須實機驗證。

## 本機試打包

對已提交、且不包含私密資料的來源可執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Core\Build-SourceRelease.ps1 -Version v1.0.0 -OutputDirectory "$env:TEMP\windows_setup_source_release_check"
```

這只產生本機版本檔，不建立標籤、不推送、不發布；目的檔已存在時會停止，避免覆寫。
