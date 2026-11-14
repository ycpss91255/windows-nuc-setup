# 維護者指南

## 專案架構與依賴方向

本專案對齊 base 將「交付給使用者的執行程式」與「維護儲存庫的工具」分開；Windows 執行樹保留 `core`／`modules`，不將 Linux／Docker 專用的 `dist` 照字面搬入。

| 位置 | 職責 |
| --- | --- |
| `core`、`modules`、根目錄 Init／Windows 入口 | Windows 交付執行樹：帳號、設定、驗收與獨立功能 |
| `script/test` | 測試調度與報告產生 |
| `script/release` | 版本準備、發布門檻與 Release 說明 |
| `script/package` | 從可信來源建立獨立驅動包 |
| `test/powershell/unit`、`integration` | 單元及隔離整合測試案例 |
| `.github/workflows` | 雲端 CI 與發布編排 |

依賴方向為維護工具／測試 → 交付執行樹。`core`／`modules` 不依賴 `script`、`test` 或 `.github`；一般使用與獨立驅動安裝不需要儲存庫維護工具。

自有原始檔與目錄使用小寫與底線，新驅動安裝日誌位於 `modules\drivers/driver_logs`。為保留已部署電腦的續跑資料，`%ProgramData%\NUC8-Setup`、`NUC-Init`、`CustomHostsSync` 及既有排程工作名稱維持相容；這些是系統既存識別，不是新增的儲存庫目錄。第三方 `win11debloat` 內部目錄及內容保持上游原樣。

## 維護者版本發布

版本發布參考 base 的 PR、CI gate 與標籤流程；Windows 測試及來源檢查保留本專案的實作。不是每次合併都自動增加 patch 版本。維護者先選擇版本、整理使用者可見的變更，再經 PR、CI 與標籤發布。

### 準備版本與 Pull Request

日常變更寫入 `doc/changelog/changelog.md` 的 `## [Unreleased]`。要發布時，先選擇尚未使用的新版本（不是目前 `.version` 或既有標籤），在工作分支執行：

```powershell
$newVersion = Read-Host '輸入尚未使用的新版本（vX.Y.Z 或 vX.Y.Z-rcN）'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\release\prepare_release.ps1 -Version $newVersion
```

此命令將 Unreleased 區段提升為指定版本、寫入 `.version`，不提交、不建立標籤也不推送。審查版本內容後，以中文提交並開啟 Pull Request。主分支要求 `ci-rollup` 通過；合併與提交規範見 [維護規範](../agents.md)。版本必須符合 `vX.Y.Z` 或 `vX.Y.Z-rcN`。

### 標籤與發布門檻

合併後，確認 main 的 CI 通過、版本檔與 changelog 一致，再在該提交建立標籤：

```powershell
git switch main
git pull --ff-only
$version = (Get-Content -LiteralPath .\.version -Raw).Trim()
git tag -a $version -m $version
git push origin "refs/tags/$version"
```

同一個 Windows workflow 接受 main 推送、Pull Request、手動執行與版本標籤。`isolated-tests` 完成後由 `ci-rollup` 統一回報；只有版本標籤通過測試，且提交位於 main 歷史、`.version` 與 changelog 精確匹配，才發布 Release。RC 標為預覽版；正式版本整合同版 RC 的版本紀錄。既有標籤與版本不應刪除、移動或重用。

主分支與 `v*` 標籤使用要求 `ci-rollup` 的保護，管理員也遵守；禁止強制推送或刪除。遠端設定的實際啟用狀態以 GitHub Rules／Branch protection 為準，檔案本身不能啟用遠端保護。

### 下載內容與保留期限

從 GitHub Release 使用內建 **Source code (zip)** 或 **Source code (tar.gz)** 下載來源，不額外上傳重複來源 ZIP／SHA256。內建來源封存檔的根目錄名稱由 GitHub 決定。若使用快速開始的 USB 自動尋找指令，請改名為 `windows_setup` 並放在 USB 根目錄；腳本本身可放任意路徑，手動呼叫該位置的 `init.cmd` 即可。

需要特定型號驅動時，依 [準備獨立驅動包](../readme.md#準備獨立驅動包) 下載同版 Release 的型號獨立 ZIP 並解壓；執行 `windows.cmd` 時選取該資料夾。一般電腦可略過，不需下載驅動。資產檔名、大小、SHA256、機型設定檔與包內 manifest 雜湊，列在該版來源的 [驅動資產清單](../script/release/driver_release_assets.json)；只選擇自己機型對應的包，不把其他型號包套用到本機。

- 來源不包含 `.git`、驅動 ZIP、Autologon EXE、實機 Reports 或密碼暫存；來源檢查會拒絕錯誤追蹤的敏感檔案。
- 依 [來源包準備說明](../readme.md#從原始碼準備完整工具包) 補齊所選功能需要的二進位，不能把來源 ZIP 當成完整離線安裝包。
- Actions 的 CI 報告附件保留 7 天；Actions 日誌保留期由儲存庫設定決定。實機續跑紀錄仍留在原機，不提交進 Git。
- Release 提供來源、品質證據與該版明確宣告的可選驅動資產，不會連線部署到任何電腦。
- v0.1.x 已發布的舊來源 ZIP／SHA256 保持原樣，新流程不回寫舊版本。

### 維護者準備獨立驅動資產

一般使用者只需下載與解壓，不需執行本節命令。維護者先完成獨立驅動包的離線完整性驗證，再於來源目錄載入打包函式，將已驗證的完整包封存到來源樹外的新檔案：

```powershell
. .\script\release\driver_release_library.ps1
New-DeterministicDriverArchive -PackageDirectory '已驗證的獨立包資料夾' -OutputPath '來源樹外的資料夾\driver_機型.zip'
```

封存使用固定 UTC 時間、相對路徑與排序，且不重壓包內現成 ZIP。將實際檔名、位元數、SHA256、ProfileId、manifest SHA256 加入上述資產清單的當版紀錄，經 PR、CI 與獨立審查後再合併、建立該版標籤。歷史版本紀錄保留；未宣告驅動資產的其他版本不受影響。

推送標籤後，立即從該標籤的來源目錄建立一次性草稿：

```powershell
.\script\release\stage_driver_release.ps1 -Version vX.Y.Z -Repository ycpss91255/windows_setup -AssetDirectory '已封存的資產資料夾'
```

此命令只建立尚未公開的暫時草稿，先核對標籤位於 main、遠端提交一致以及本地資產雜湊。標籤 CI 全綠後，CD 才會核對草稿身分、既有驅動與全部品質附件，最後一次發布為不可變 Release。已有其他草稿、上傳不完整或雜湊不符會停止，保留現場供維護者檢查，不覆寫或刪除既有版本。若建立草稿太晚造成 CD 失敗，先核對草稿完整，再選擇該次執行的「重新執行所有工作」，重新產生同 attempt 的分片及品質證據；勿只重跑發布工作、移動標籤或跳過品質門檻。

### 本機檢查發布內容

對已提交、版本檔及 changelog 已一致的來源執行：

```powershell
$version = (Get-Content -LiteralPath .\.version -Raw).Trim()
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\release\build_source_release.ps1 -Version $version -OutputDirectory "$env:TEMP\windows_setup_release_check"
```

此命令驗證來源並產生 Release 說明，不再重複打包來源 ZIP；不建立標籤、不推送、不發布，也不代表雲端 CI 已通過。

### 檔名與舊版相容性

本專案的自有檔案統一小寫 snake_case，例如 `init.cmd`、`windows.cmd`、`script/test/run_ci.ps1`；Windows 不分大小寫不代表 Linux／GitHub 也能接受舊拼法。`agents.md` 也依此命名，部分工具不再自動發現原本大寫 AGENTS.md 的規範，維護時須主動讀取本檔。

第三方 Win11Debloat 原始碼、授權及供應的 Autologon／驅動封存檔保留原始檔名，不改上游契約或內容。既有每機報告、排程 worker、ProgramData 目錄與系統固定名稱也保留既有契約，避免失去續跑資料；這些不是新的儲存庫原始檔。舊報告內的模組檔名會映射到新的腳本名稱，仍檢查同一電腦與使用者，不代表允許沿用他機結果。請用新版入口，不另保留重複的舊檔名腳本。

### 自動需求驗收與獨立審查

PR 與 main 的 `requirements-gate` 讀取同一次 PS5.1 測試產物，驗證來源、統計、JUnit／JSON 狀態、文件連結、隱私與 base 徽章規格，並用破壞性負例確認錯誤會被拒絕；`ci-rollup` 必須同時取得測試與需求驗收成功才能合併。PR 的證據保留原分支身分，不會冒充 main。

Pages 部署後匿名讀取首頁、main 報表、JSON／Markdown／JUnit、整體及分層 SVG、README 的原生 CI／整體 coverage 徽章，以及歷史版本頁。驗收會重算 `repo_coverage.json`、`coverage_inventory.json`、`coverage.xml`，核對本次提交、Actions 來源與實際 checkout 的自有原始碼清單；整體量測必須完整，且 `Covered × 100 >= Executable × 80` 才能通過。分項資訊保留在報表與 Actions 摘要，不要求 README 顯示分項徽章。CDN 只有限重試，舊證據或不一致會失敗，無需 agent 代替腳本處理。

實作、freeze、主代理與未參與實作的獨立代理完整審查流程見 [維護規範](../agents.md)。發現問題必須修正後重新全需求審查，不能把上次 PASS 沿用到修改後版本。

測試與提交規範以 [維護規範](../agents.md) 為準。

### 提交訊息輔助檢查

維護者可選擇安裝 `commit-msg` hook；需要 Git、Go 1.27.3 及提交時可用的 Go 執行環境。在本儲存庫根目錄執行 `powershell -File script/test/commitlint/install.ps1`；指定其他目標可加 `-Repository <路徑>`。安裝尊重 Git 的 hooks 路徑，若已有 `commit-msg` 便停止，不覆蓋原檔。移除時請先確認內容，再自行刪除安裝的 hook。hook 參照此工作樹中的工具來源，移動或刪除工作樹後須重新安裝。

也可單獨執行 `go run ./script/test/commitlint lint <訊息檔>`；退出碼 0 代表通過，非 0 代表未通過或執行失敗。檢查標題含漢字，以及訊息中的常見家目錄路徑和憑證指定模式；錯誤不回印原文。這只是有限的提示，可能誤判或漏判，不能證明沒有機密，也不能判定是否為單一任務、TDD 證據是否真實；仍須人工審查。僅檢查啟用後的新提交，不回溯舊歷史。

## 建立獨立驅動包

以下重新建包指令僅供維護者使用，使用者下載與解壓即可。準備符合 [drivers/nuc8i7hvk_hnk/manifest.json](../drivers/nuc8i7hvk_hnk/manifest.json) 的十二個封存檔，並將此範本複製為來源目錄的 `manifest.json`，再執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\package\export_driver_package.ps1 -SourceDirectory "已核對的驅動來源目錄" -OutputDirectory "新的獨立包目錄"
```

設定檔依主機板 Product 精準選擇，沒有對應型號或未選獨立包時略過；已知其他板號不能手動偽裝成 NUC。機型與套件／INF 版本、依賴及官方來源見 [驅動設定檔](../drivers/readme.md)。新增電腦設定檔使用相同安裝引擎，另建立板號白名單與已查核 manifest，不複製安裝程式。

輸出目錄必須不存在。導出會驗證全部封存檔雜湊、產生可攜入口及設定檔雜湊綁定的機型識別；不安裝驅動。取得新驅動應使用原廠可信來源，改版需要重新驗證，不能直接修改 SHA256 來略過檢查。
