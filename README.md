# NUC Windows 重裝後完整操作步驟

Git／GitHub 版本與目前本機完整包不同：驅動及 Autologon EXE 不納入 Git，從原始碼取得後須依 [GitHub 準備說明](Docs/GITHUB.md) 補齊再檢查。第三方來源及授權見 [THIRD_PARTY.md](THIRD_PARTY.md)。本儲存庫尚未發布；現有網路規則及提交歷史仍須在公開前做隱私處理。

適用於本工具包支援的 Intel NUC8i7HV／HN 電腦。依目前階段先執行 Init，再執行 Windows；不需要 agent、SSH 遙控或預先手動安裝 OpenSSH。使用者名稱、家目錄與 SID 由腳本動態取得；工具包位置依目前檔案所在目錄解析，不綁定固定帳號或磁碟代號。

Downloads 內的 `Windows-NUC-Setup` 是自包含主版本。要換電腦使用時，完整複製這個資料夾（包含內建驅動）到任意可寫入、非桌面的路徑即可，不強制放在 Downloads。USB 只是可選的搬運媒介；舊 USB 副本不會自動更新，也不作為本輪主版本。

完整流程需要你允許管理員權限、輸入現有帳號密碼，以及依提示手動重新開機，並非完全無人值守。腳本不會自行重新開機或關機。

## 先看目前在哪個階段

兩個入口各有用途：`Init.cmd` 處理初始帳號與 SSH；`Windows.cmd` 處理正式帳號登入後的驅動、更新、清理與偏好。不要在 OOBE 或稽核用 Administrator 桌面執行 Windows.cmd。

### 還在 Windows 初始設定／連接 Wi-Fi 畫面

1. 保持離線，按 `Ctrl+Shift+F3`（部分鍵盤需加 Fn），Windows 會重新啟動進入「稽核模式」。這一步不會重新安裝 Windows。若已按 Shift+F10 開啟命令窗，可先關閉它再按快捷鍵。
2. 進入內建 Administrator 桌面後，按「取消」關閉自動出現的「系統準備工具」視窗，避免兩個 Sysprep 同時執行。
3. 打開已完整複製的 Windows-NUC-Setup 資料夾，雙擊 `Init.cmd`。依畫面確認這是剛安裝系統的稽核模式，再輸入要建立的本機帳號、密碼與確認密碼。
4. Init 使用 Windows answer file 建立本機管理員並準備返回 OOBE。成功後依提示手動重新開機。不要在此稽核帳號執行 Windows.cmd。
5. 完成仍顯示的地區、隱私等設定，以新帳號登入。此流程不替你同意授權或隱私選項。

同一 Init.cmd 若從 OOBE 的 Shift+F10 命令窗呼叫，只會辨識環境並引導進入稽核模式；不會在 SYSTEM 身分直接執行 Sysprep。Microsoft 不支援以 SYSTEM 執行 Sysprep，因此這個方式需要上述稽核模式切換，不能保證在 Wi-Fi 畫面一次呼叫就直接進桌面。

帳號建立時的必要 answer file 只暫存在本機受管理員／SYSTEM 權限保護的目錄，不存於 USB；其中密碼可還原，不應視為加密。首次正式帳號登入會清理本工具的密碼 answer file，保留不含密碼的狀態與清理紀錄。詳細限制與清理紀錄見 `Modules\Init\README.md`。此 OOBE 新流程尚未在實機完整跑過，失敗時查看提示並停止，不要手動修改 Setup 狀態強行略過。

### 已用正式本機帳號進入桌面

先接上網路，再雙擊 `Init.cmd`，允許管理員權限。這個階段不會重新建立帳號或改密碼；它會安裝／啟用 OpenSSH Server、設定區域網路防火牆，並建立目前使用者的 SSH／hosts 框架。離線且缺少 SSH 安裝元件時會明確失敗，接網後重新執行 Init 即可。

Init 成功後，依下方步驟執行 Windows.cmd。SSH 為可重複執行模組，Windows 第 04 模組也會再次確認，不會因此改用其他帳號。

## 1. 完成 Windows 初始設定

1. 進入 Windows 桌面，登入之後要長期使用的本機管理員帳號。
2. 設定並記住該帳號的現有密碼。帳號可自行命名；自動登入會使用目前帳號，不會要求所有電腦使用同一組帳密。
3. 接上網路並保持電源穩定。完整流程需要下載 Windows Update 與尚未安裝的 OpenSSH 元件。
4. 多臺電腦請先各自設定唯一電腦名稱，例如 `NUC-001`、`NUC-002`；名稱變更要求重開時先完成重開，再開始下列流程。
5. 取走桌面上需要保留的資料。桌面清理模組會刪除使用者桌面及共用桌面的普通檔案、資料夾和捷徑，最後只留下四個系統圖示。

## 2. 完整複製工具包

從主版本的 Downloads 複製整個 `Windows-NUC-Setup` 資料夾到目標電腦。可放在該電腦的 Downloads 或其他可寫入位置，不限磁碟代號，也不強制資料夾位於某個使用者的家目錄。

```text
Windows-NUC-Setup\
├─ Init.cmd                    初始帳號／SSH
├─ Windows.cmd                 正式帳號桌面設定
├─ README.md                   本文件
├─ Core\                      主流程、驗證與路徑表
├─ Modules\                   每個功能自己的腳本、資產與獨立入口
│  ├─ Init\                   OOBE／稽核模式帳號建立
│  ├─ SSH\                    SSH 及 hosts 同步
│  ├─ Drivers\
│  │  └─ Payload\             4 個驅動封存檔與 manifest.json
│  ├─ Updates\                Windows Update
│  ├─ Debloat\                清理與 Win11Debloat
│  └─ …                        帳號、記憶體、電源、桌面、輸入法等
├─ Reports\                   本機整體進度、結果與紀錄（不納入 Git）
├─ Tests\                     不改系統的隔離測試
└─ Docs\                      詳細功能說明
```

內建驅動位於 `Modules\Drivers\Payload`，包含晶片組、Serial IO、UCM 與 AMD 顯示驅動及雜湊清單；不需要另外找 USB 旁邊的 Driver 資料夾。不要只複製單一 `.cmd`／`.ps1`，也不要漏掉 Payload 或隱藏的 `.git` 版本資料夾。

工具包不要放在桌面或其子資料夾內，以免桌面清理刪到工具包。完整複製到本機後，執行本機這份；不需要 USB 持續連接。若自行選擇直接從外接磁碟執行，該磁碟必須可寫入且全程保持連接。

腳本不會自行把工具包複製到 Downloads，也不會自動同步其他副本。要更新別臺電腦時，由你選擇要複製的完整主版本；先保留目的地的自訂檔及需要的執行紀錄，避免直接覆蓋。

## 3. 執行第一次設定

1. 雙擊 `Windows.cmd`。
2. Windows 管理員權限提示選「是」。請用目前登入的目標帳號執行，不要輸入另一個管理員帳號代替。
3. 依提示輸入目前帳號的現有密碼，用來設定開機自動登入。密碼不會寫入工具包腳本。
4. 等待視窗中的 19 個模組執行完畢。進度與結果以中文顯示；Windows Update 可能需要較久。

執行期間不要關閉主視窗、移動工具包、關機或提早重開機；若從外接磁碟執行，不要拔出該磁碟。即使畫面顯示某一個模組完成，也要等整輪結束。

若有錯誤，記下模組名稱與訊息，並查看工具包內的 `Reports\Setup-Result.json`。腳本可能繼續後面的模組，因此「本輪執行結束」不一定代表所有模組成功。進度可查看 `Reports\Setup-Progress.json`；更新進度可另開 `Modules\Updates\Show-Update-Status.cmd`。

如果在最前面的帳號密碼／自動登入階段就中止，這個失敗不會加入後續模組重試清單；先修正密碼或畫面指出的問題，再執行 `Windows.cmd`。不要把上次留下的結果檔當成本輪已完成。

## 4. 等整輪結束後手動重新開機

主視窗完成全部階段並提示重新開機後，再由 Windows 電源選單選「重新啟動」。

第一次設定完成後仍應重新開機一次，讓登入後設定生效，不要只因更新沒有標示待重開機就跳過這一步。

重新進入桌面時，確認是否自動登入正確帳號。如果沒有自動登入，先手動登入原本同一個帳號並記下現象，不要換帳號繼續。

## 5. 執行重開機後驗收

1. 開啟這臺電腦先前執行的同一份 `Windows-NUC-Setup` 資料夾。
2. 在此資料夾的終端執行 `.\Windows.cmd -AfterRestart`，允許管理員權限；也可雙擊 `Core\Verify-AfterRestart.cmd`。
3. 等待本輪結束。這個入口會重試同一臺電腦、同一帳號先前失敗且可重試的模組，重新掃描更新，再做清理及驗證。
4. 若更新或驗收提示仍需重新開機，等本輪結束後手動重開，再執行一次 `Windows.cmd -AfterRestart`。
5. 直到顯示驗收通過、沒有未解決失敗，也沒有待重新開機提示，再做下面的目視確認。

更新可能分成多輪。若相同錯誤持續出現，不要只靠一直重跑；查看 `Reports\Acceptance-Result.json` 的 `Errors`／`FailedChecks`、`Reports\Verification-Result.json` 及畫面訊息。另一臺電腦的舊結果不代表目前這臺成功。

如果只是想檢查現況，在此資料夾的終端執行 `.\Windows.cmd -VerifyOnly`（或雙擊 `Core\Verify-Only.cmd`）；它不安裝更新或重新套用偏好。若開始選單驗證顯示工作尚未回傳結果，先等該工作結束，再重新驗證。

## 6. 最後目視確認

- 開機自動登入的是正確帳號。
- 解析度為 `1920×1080`，縮放為 Windows 標準 `100%`，不是自訂縮放。
- Windows 與應用程式使用深色模式，桌面背景是純黑色。
- 桌面只顯示控制台、本機、網路、資源回收筒，位置符合範本。
- 工作列只釘選 Edge，搜尋欄、天氣／小工具與工作檢視按鈕隱藏。執行中的其他程式仍可能顯示在工作列。
- 開始選單釘選清空；按 Windows 鍵仍可搜尋程式。
- 檔案總管顯示一般隱藏項目與副檔名；受保護的系統檔仍保持隱藏。
- 預設輸入為英文美式鍵盤，需要中文時按 `Win+Space` 切換。
- 按 `Ctrl+Alt+T` 能開啟 Windows Terminal。
- AMD Software 不再於登入時詢問位置權限。如果舊提示已經顯示在畫面上，先手動關閉該提示，再於下次登入確認。

四個桌面圖示的排列範本以繁體中文 Windows、1920×1080、100% 縮放為準。自動檢查不能取代上述登入與畫面觀察。

## 19 個模組的執行順序

| 順序 | 處理內容 |
| --- | --- |
| 01 | 目前帳號開機自動登入 |
| 02 | 停用磁碟分頁檔（虛擬記憶體） |
| 03 | 插電時停用自動睡眠／休眠 |
| 04 | OpenSSH Server、區域網路防火牆、SSH 目錄與 hosts／SSH 同步框架 |
| 05 | 核對並安裝適用驅動 |
| 06 | 拒絕 AMD Software 位置存取 |
| 07 | Windows Update 建議更新 |
| 08 | Win11Debloat、OneDrive 與可移除的預裝 App 清理 |
| 09 | 獨立版 Copilot 清理 |
| 10 | 工作列顯示與 Edge 釘選 |
| 11 | 開始選單釘選與推薦清理 |
| 12 | 1920×1080、原生 100% 縮放 |
| 13 | 桌面清理與四個系統圖示 |
| 14 | 深色模式與純黑背景 |
| 15 | 自動補齊英文（美國）與美式鍵盤，並設為預設 |
| 16 | Ctrl+Alt+T 開啟 Terminal |
| 17 | 顯示一般隱藏項目與副檔名 |
| 18 | 清除符合條件的舊系統／預設資料夾殘留 |
| 19 | 最後套用桌面圖示排列 |

第 15 模組會在缺少時新增英文（美國）`en-US`，並確保存在美式鍵盤 `0409:00000409`，再設為預設輸入法；保留中文、其他語言、既有鍵盤與順序，不安裝英文顯示語言包或切換 Windows 介面語言。若只要補英文鍵盤，可雙擊 `Modules\Input\Apply-InputMethodSettings.cmd`；只檢查可在工具包目錄執行 `Modules\Input\Apply-InputMethodSettings.cmd -VerifyOnly`。檢查會同時確認英文語言、美式鍵盤及預設輸入法，結果寫入 `%ProgramData%\NUC8-Setup\InputMethod-Result.json`。

各模組資料夾內另有獨立 `.cmd` 入口，例如 `Modules\Input\Apply-InputMethodSettings.cmd`，詳見 [使用說明.txt](Docs/使用說明.txt)。不要因某一模組失敗就手動更動其他無關模組。

## SSH 與 hosts 後續維護

第 04 模組會建立目前使用者的設定與中文說明：

- `%USERPROFILE%\.ssh\README.md`：SSH 連線別名、帳號、連接埠等用途與修改方式。
- `%USERPROFILE%\.config\hosts\README.md`：網路規則及 hosts 對照來源的用途與修改方式。

hosts 設定資料夾保留在 `.config\hosts`，不改成 `.hosts`。Windows 系統 hosts 仍是 `%WINDIR%\System32\drivers\etc\hosts`。

SSH 與 hosts 可獨立或配合使用。這套工具目前提供可修改的網路規則與空白主機範本，不會自行填入真實主機 IP、遠端帳號或 SSH 私鑰。需要時依資料夾內 README 編輯；`active-sites.conf` 是自動產生的載入清單，不要手動修改。既有自訂 README 會保留。

## 範圍、版本與結果紀錄

Windows 啟用由使用者另外處理；本工具不處理 Ubuntu 分割或安裝。Windows 不允許移除的系統元件會保留，清理數量會隨 Windows 狀態而不同。

這套工具已在原 NUC 驗證；第二臺全新 Windows 的完整安裝尚未實跑。請以目前這臺電腦的驗收結果為準，不保證不同 Windows 版本、硬體或螢幕得到完全相同的更新版本及刪除數量。

中文迭代紀錄見 [CHANGELOG.md](CHANGELOG.md)。工具包內已建立本機 Git，但執行設定不需要安裝 Git；若要查看歷史，可在工具包目錄執行 `git log -5 --oneline`。每機執行結果不納入 Git，請保留需要的診斷紀錄。

## 模組資料夾索引

| 資料夾 | 用途 |
| --- | --- |
| `Modules\Init` | 初始帳號建立 |
| `Modules\Accounts` | 自動登入 |
| `Modules\Memory` | 分頁檔 |
| `Modules\Power` | 電源與睡眠 |
| `Modules\SSH` | SSH 與 hosts 同步 |
| `Modules\Drivers` | 驅動 |
| `Modules\AMD` | AMD 位置權限 |
| `Modules\Updates` | 更新與進度 |
| `Modules\Debloat` | 預載 App、OneDrive、Copilot 清理 |
| `Modules\Taskbar` | 工作列 |
| `Modules\StartMenu` | 開始選單 |
| `Modules\Display` | 解析度與縮放 |
| `Modules\Desktop` | 桌面圖示與排列 |
| `Modules\Theme` | 深色與背景 |
| `Modules\Input` | 英文美式鍵盤 |
| `Modules\Terminal` | Terminal 快捷鍵 |
| `Modules\Explorer` | 隱藏檔與副檔名 |
| `Modules\Cleanup` | 舊系統與資料夾殘留 |

主流程結果位於 `Reports`；各模組的執行紀錄位於各自資料夾或畫面提示的 `%ProgramData%\NUC8-Setup`。既有程式碼不再全部平鋪在根目錄，請勿只取出其中一支腳本執行。

## Windows 自動測試與報告保留

GitHub Actions 使用固定的 Windows Server 2022 runner 與 Windows PowerShell 5.1，在 main 推送、Pull Request 或手動觸發時執行語法、來源結構、Init、輸入法、來源封裝與 Hosts／SSH 規劃隔離測試。CI 不執行初始化、SSH、驅動安裝、Sysprep、桌面清理或重新開機。它不能取代實機 OOBE、驅動、登入與畫面驗收。

測試報告寫在 runner 暫存目錄，Actions artifact 只保留 7 天，不納入 Git。實機 Reports、Setup-Result.json 等仍由原流程使用；CI 不讀取或刪除它們，設定尚未完成時請保留續跑紀錄。詳細測試方式見 Docs/GITHUB.md。

## 版本發布（CD）

維護者推送 v主版.次版.修訂 標籤（例如 v1.0.0）時，Windows 版本發布工作流程先執行同一套隔離測試，全部通過才建立 GitHub Release。版本附件為來源 ZIP 與 SHA256 校驗檔，不包含驅動 ZIP、Autologon EXE、實機報告或私人設定；不是完整離線安裝包。詳細步驟見 Docs/RELEASE.md。
