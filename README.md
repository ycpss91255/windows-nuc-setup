# windows_setup

[![Windows CI](https://github.com/ycpss91255/windows_setup/actions/workflows/windows-tests.yml/badge.svg)](https://github.com/ycpss91255/windows_setup/actions/workflows/windows-tests.yml)

Windows 設定工具：以 Init 與 Windows 兩個入口完成帳號初始化、模組設定與後續驗收。本文以繁體中文提供完整操作說明；版本摘要見 [變更紀錄](doc/changelog/CHANGELOG.md)，實作與驗證細節以中文 Git 提交及 GitHub Release 為準。

## 目錄

- [快速開始](#快速開始)
- [執行前提](#執行前提)
- [概覽與適用範圍](#概覽與適用範圍)
- [初始安裝操作](#先看目前在哪個階段)
- [模組與獨立執行](#模組補充說明)
- [SSH 與 hosts](#ssh-與-hosts-後續維護)
- [來源包準備](#從原始碼準備完整工具包)
- [CI 與本機測試](#windows-ci)
- [版本發布](#維護者版本發布)
- [目錄索引](#模組資料夾索引)

## 快速開始

先確認已取得完整包，並符合下方機型與系統前提；不要直接在 OOBE 執行 Windows.cmd。

```powershell
# 正式帳號桌面：完成 SSH 初始化後執行設定
.\Init.cmd
.\Windows.cmd

# 依提示手動重開機後，回到同一份工具包續跑
.\Windows.cmd -AfterRestart

# 僅檢查，不重套設定
.\Windows.cmd -VerifyOnly
```

若仍在 Windows 初始設定畫面，先照「初始安裝操作」進入稽核模式，再呼叫 Init，不直接套用上面的桌面流程。

## 執行前提

- 目前一鍵硬體設定檔：Intel NUC8i7HVB／NUC8i7HNB；其他主機板會被拒絕。模組可獨立執行，但不代表所有硬體已驗證。
- 64 位元 Windows 11 22H2 或更新，專業／企業／教育版；Windows 流程須在正式目標本機管理員桌面執行。
- 完整工具包必須可寫入，不能放在將被清理的桌面；使用者名稱與磁碟代號動態取得。
- Windows Update 與未快取的 OpenSSH 元件需要網路。UAC、密碼及提示的重新開機需使用者操作。
- 桌面清理會刪除一般桌面檔案、資料夾與捷徑；先取走要保留的內容。桌面排列範本以繁體中文、1920×1080、100% 縮放為準。

## 概覽與適用範圍

Git／GitHub 版本與目前本機完整包不同：驅動及 Autologon EXE 不納入 Git，從原始碼取得後須依 [來源包準備說明](#從原始碼準備完整工具包) 補齊再檢查。第三方來源及授權見 [THIRD_PARTY.md](THIRD_PARTY.md)。公開來源的網路 Sites 預設為空集合；請在本機維護個人規則。

本工具依上方前提選用既有硬體設定檔，Windows 模組亦提供獨立入口。依目前階段先執行 Init，再執行 Windows；不需要 agent、SSH 遙控或預先手動安裝 OpenSSH。使用者名稱、家目錄與 SID 由腳本動態取得；工具包位置依目前檔案所在目錄解析，不綁定固定帳號或磁碟代號。

目前 Downloads 內的 `windows_setup` 是自包含主版本；資料夾可改名，腳本依所在位置解析。要換電腦使用時，完整複製這個資料夾（包含內建驅動）到任意可寫入、非桌面的路徑即可，不強制放在 Downloads。USB 只是可選的搬運媒介；舊 USB 副本不會自動更新，也不作為本輪主版本。

完整流程需要你允許管理員權限、輸入現有帳號密碼，以及依提示手動重新開機，並非完全無人值守。腳本不會自行重新開機或關機。

## 先看目前在哪個階段

兩個入口各有用途：`Init.cmd` 處理初始帳號與 SSH；`Windows.cmd` 處理正式帳號登入後的驅動、更新、清理與偏好。不要在 OOBE 或稽核用 Administrator 桌面執行 Windows.cmd。

### 還在 Windows 初始設定／連接 Wi-Fi 畫面

1. 保持離線，按 `Ctrl+Shift+F3`（部分鍵盤需加 Fn），Windows 會重新啟動進入「稽核模式」。這一步不會重新安裝 Windows。若已按 Shift+F10 開啟命令窗，可先關閉它再按快捷鍵。
2. 進入內建 Administrator 桌面後，按「取消」關閉自動出現的「系統準備工具」視窗，避免兩個 Sysprep 同時執行。
3. 打開已完整複製的 windows_setup 資料夾，雙擊 `Init.cmd`。依畫面確認這是剛安裝系統的稽核模式，再輸入要建立的本機帳號、密碼與確認密碼。
4. Init 使用 Windows answer file 建立本機管理員並準備返回 OOBE。成功後依提示手動重新開機。不要在此稽核帳號執行 Windows.cmd。
5. 完成仍顯示的地區、隱私等設定，以新帳號登入。此流程不替你同意授權或隱私選項。

同一 Init.cmd 若從 OOBE 的 Shift+F10 命令窗呼叫，只會辨識環境並引導進入稽核模式；不會在 SYSTEM 身分直接執行 Sysprep。Microsoft 不支援以 SYSTEM 執行 Sysprep，因此這個方式需要上述稽核模式切換，不能保證在 Wi-Fi 畫面一次呼叫就直接進桌面。

帳號建立時的必要 answer file 只暫存在本機受管理員／SYSTEM 權限保護的目錄，不存於 USB；其中密碼可還原，不應視為加密。首次正式帳號登入會清理本工具的密碼 answer file，保留不含密碼的狀態與清理紀錄。詳細限制與清理紀錄見 `Modules\Init\README.md`。此 OOBE 新流程尚未在實機完整跑過，失敗時查看提示並停止，不要手動修改 Setup 狀態強行略過。

### 已用正式本機帳號進入桌面

先接上網路，再雙擊 `Init.cmd`，允許管理員權限。這個階段不會重新建立帳號或改密碼；它會安裝／啟用 OpenSSH Server、設定區域網路防火牆，並建立目前使用者的 SSH／hosts 框架。離線且缺少 SSH 安裝元件時會明確失敗，接網後重新執行 Init 即可。

Init 成功後，依下方步驟執行 Windows.cmd。SSH 為可重複執行模組，Windows 第 04 模組也會再次確認，不會因此改用其他帳號。

以下是正式帳號桌面的後續流程。已完成上方 Init 的使用者，不必再建立帳號；直接確認前提並從步驟 2 繼續。

## 1. 完成 Windows 初始設定

1. 進入 Windows 桌面，登入之後要長期使用的本機管理員帳號。
2. 設定並記住該帳號的現有密碼。帳號可自行命名；自動登入會使用目前帳號，不會要求所有電腦使用同一組帳密。
3. 接上網路並保持電源穩定。完整流程需要下載 Windows Update 與尚未安裝的 OpenSSH 元件。
4. 多臺電腦請先各自設定唯一電腦名稱，例如 `NUC-001`、`NUC-002`；名稱變更要求重開時先完成重開，再開始下列流程。
5. 取走桌面上需要保留的資料。桌面清理模組會刪除使用者桌面及共用桌面的普通檔案、資料夾和捷徑，最後只留下四個系統圖示。

## 2. 完整複製工具包

從主版本的 Downloads 複製整個 `windows_setup` 資料夾到目標電腦。可放在該電腦的 Downloads 或其他可寫入位置，不限磁碟代號，也不強制資料夾位於某個使用者的家目錄。

```text
windows_setup\
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
└─ doc\changelog\            版本摘要與紀錄規範
```

內建驅動位於 `Modules\Drivers\Payload`，包含晶片組、Serial IO、UCM 與 AMD 顯示驅動及雜湊清單；不需要另外找 USB 旁邊的 Driver 資料夾。不要只複製單一 `.cmd`／`.ps1`，也不要漏掉 Payload。`.git` 僅在需要維護版本歷史時保留，執行設定不需要它，來源發布包也不包含它。

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

1. 開啟這臺電腦先前執行的同一份 `windows_setup` 資料夾。
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

各模組資料夾內另有獨立 `.cmd` 入口，例如 `Modules\Input\Apply-InputMethodSettings.cmd`，詳見下方模組補充說明。不要因某一模組失敗就手動更動其他無關模組。

## SSH 與 hosts 後續維護

第 04 模組會建立目前使用者的設定與中文說明：

- `%USERPROFILE%\.ssh\README.md`：SSH 連線別名、帳號、連接埠等用途與修改方式。
- `%USERPROFILE%\.config\hosts\README.md`：網路規則及 hosts 對照來源的用途與修改方式。

hosts 設定資料夾保留在 `.config\hosts`，不改成 `.hosts`。Windows 系統 hosts 仍是 `%WINDIR%\System32\drivers\etc\hosts`。

SSH 與 hosts 可獨立或配合使用。這套工具目前提供可修改的網路規則與空白主機範本，不會自行填入真實主機 IP、遠端帳號或 SSH 私鑰。需要時依資料夾內 README 編輯；`active-sites.conf` 是自動產生的載入清單，不要手動修改。既有自訂 README 會保留。

## 範圍、版本與結果紀錄

Windows 啟用由使用者另外處理；本工具不處理 Ubuntu 分割或安裝。Windows 不允許移除的系統元件會保留，清理數量會隨 Windows 狀態而不同。

這套工具已在原 NUC 驗證；第二臺全新 Windows 的完整安裝尚未實跑。請以目前這臺電腦的驗收結果為準，不保證不同 Windows 版本、硬體或螢幕得到完全相同的更新版本及刪除數量。

使用者可見的修改見 [變更紀錄](doc/changelog/CHANGELOG.md)；詳細驗證結果與限制以中文 Git 提交及 GitHub Release 說明記錄。工具包內已建立本機 Git，但執行設定不需要安裝 Git；若要查看歷史，可在工具包目錄執行 `git log -5 --oneline`。每機執行結果不納入 Git，請保留需要的診斷紀錄。

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

## 模組補充說明

### 各模組行為

1. Apply-AutologonSettings：以目前帳號設定自動登入；密碼透過 Microsoft Autologon 儲存，不寫在工具包腳本。
2. Apply-PagefileSettings：停用磁碟分頁檔；重開機後完全生效。
3. Apply-PowerSettings：插電時停用自動睡眠和休眠；保留螢幕逾時設定。
4. Apply-SSHSettings：安裝並啟用 OpenSSH Server；自動啟動，防火牆限制 LocalSubnet。
5. Install-Drivers：核對機型、驅動 SHA256，安裝適用驅動並檢查異常裝置。
6. Apply-AMDPrivacySettings：拒絕 AMD Software 地理位置存取。已顯示的提示需手動關閉。
7. Install-WindowsUpdates：執行本輪 Windows 建議更新，顯示心跳進度並記錄是否需要重開機。
8. Apply-Debloat：先呼叫 Remove-OneDrive.ps1 解除安裝 OneDrive，再依 Debloat-Apps.txt 清理預裝 App，包含 Xbox App、Game Bar、相關登入與語音元件，以及存在時的 Gaming Services。Windows 不可移除的 XboxGameCallableUI 保留。
9. Apply-CopilotSettings：移除獨立桌面版 Copilot。
10. Apply-TaskbarSettings：隱藏搜尋、天氣/小工具與工作檢視；僅釘選 Edge。登入後自動解除暫時釘選原則。
11. Apply-StartMenuSettings：清空釘選、隱藏推薦及全部應用程式分類區；保留搜尋、帳號和電源。程式本體仍可搜尋啟動。
12. Apply-DisplaySettings：1920×1080、標準原生100%縮放，關閉自訂縮放。
13. Apply-DesktopSettings：清空普通桌面項目，顯示本機、網路、控制台、資源回收筒。
14. Apply-ThemeSettings：Windows/應用程式深色、純黑背景；必要時重新載入 Explorer。
15. Apply-InputMethodSettings：缺少時新增英文（美國）與美式鍵盤，再設為預設；保留中文及其他語言與鍵盤順序。Win+Space 切換，已開啟視窗可能保留原輸入法，下次登入使用新預設。驗證同時核對 en-US、美式鍵盤與預設值，不只檢查順序或 override。
16. Apply-TerminalHotkey：Ctrl+Alt+T 開啟 Windows Terminal，以一般使用者權限執行。使用 RegisterHotKey 背景監聽程式，登入時透過 Startup 自動啟動。

17. Apply-ExplorerSettings：設定登錄值與 Shell 即時狀態，重新整理已開啟的檔案總管以顯示一般隱藏檔；受保護系統檔保持隱藏。

18. Remove-SetupResidue：清除空的 Windows.old、預設聯絡人/遊戲等空資料夾及具名預設捷徑；含有其他資料時保留並記錄。

19. Desktop-IconLayout：最後套用四個圖示座標，避免先前的檔案總管重新整理影響排列。重開驗收入口也會最後套用此範本。

### 額外入口與快捷鍵排錯

- Modules\Desktop\Save-Desktop-Layout.cmd：圖示移動後，將目前位置儲存成新範本。
- Modules\Updates\Show-Update-Status.cmd：查看更新進度；關閉進度視窗不會停止更新。
- Windows.cmd -VerifyOnly：檢查設定、目前顯示比例、圖示座標、開始釘選匯出、App清理、輸入法及快捷鍵程序。
- Terminal 快捷鍵日誌：%LOCALAPPDATA%\NUC8-Setup\TerminalHotkey\status.log。
  REGISTERED 表示成功註冊；LAUNCHED 表示收到按鍵並呼叫 Terminal；FAILED 1409 表示快捷鍵衝突，需要排查。

### 主機名稱與區域網路

- 連線時使用自己的帳號與主機名稱，例如 ssh your_user@nuc-001.local；名稱解析與連線須在實機確認。
- .local 用於同網段 mDNS，訪客網路、隔離網路或跨VLAN可能無法使用。
- 多臺電腦建議路由器固定 DHCP 租約；需要跨網段時使用區域 DNS，例如 nuc-001.home.arpa。
- 沒有寫入固定 IP、個人 SSH 私鑰、hosts 站點資料或其他人的 SSH config。


## 清理與網路規則補充

OneDrive 獨立入口為 `Modules\Debloat\Remove-OneDrive.cmd`；解除安裝後僅清除空的預設資料夾，不刪除個人或雲端資料。清理模組對 Windows.old、Contacts、Saved Games、Favorites、Links、Searches 只清除符合空目錄條件的項目；含資料或連結時保留。具名預設 Bing 書籤、捷徑與內建搜尋定義可清除，其他自訂內容保留；不可移除及僅 Staged 的 Windows 元件不代表一般已安裝 App 未清理。

Hosts／SSH 獨立入口為 `Modules\SSH\Apply-HostsSync.cmd`、`Sync-Hosts.cmd`、`Sync-SSH.cmd`。目前使用者的 `.config\hosts\sites.json` 支援任意站點，透過 Outputs 分別啟用 Hosts／SSH；每 10 秒重新讀取來源，未變更不重寫。SSID 若受定位權限限制，可用 NetworkProfile 或 IPv4Cidr，不會強制開啟定位。框架沒有實際主機清單或私鑰；詳細範例保留在模組內 `Modules\SSH\CustomHostsSync\使用方式.txt` 與 SSH／hosts README。

`.ssh` 具有 Windows Hidden 屬性；啟用顯示隱藏項目時仍可看見。第 04 模組設定 LocalSubnet 的 IPv4／IPv6 Ping 入站規則，名稱解析與 Ping 分開驗證，沒有關閉防火牆。rsync、SSH-agent、Tab 補全及金鑰部署尚未納入。

## 來源包與完整工具包

### 兩種取得方式

目前 Downloads 的完整工具包資料夾（`windows_setup`）包含驅動與必要工具，可依根目錄 README 整包複製使用。

Git 儲存庫則只保存程式、文件、範本、測試及必要的上游來源資產。**從 GitHub clone 或下載原始碼 ZIP，不等於取得完整可執行工具包。** GitHub 上的程式也不會自動下載所有二進位。

### 從原始碼準備完整工具包

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
5. 通過後依根目錄 [初始設定操作](#先看目前在哪個階段) 執行 Init／Windows 流程。完整 OOBE 實機驗證限制仍適用。

`Package-Hashes.json` 是本機交付包的雜湊快照，不追蹤於 Git；Git clone 不會帶有此檔。前置檢查使用受追蹤的驅動 manifest，不以缺少這份交付快照當成程式損壞。

### 不納入 Git 的內容

- 驅動 ZIP、Autologon EXE、安裝封存檔與其他大型二進位。
- 各機 `Reports`、進度、結果、快取、備份與執行日誌。
- `.ssh`、私鑰、known_hosts、密碼、Token、Init answer file、owner/runtime/state 等實機資料。
- 本機套件雜湊快照與暫存測試副本。

忽略規則不會刪除本機完整包的必要檔案。不要為了讓 Git 工作樹乾淨而刪除驅動或使用者自訂設定。

### 公開來源與授權注意事項

公開版 `Modules/SSH/CustomHostsSync/sites.json` 使用空白 Sites，不帶公司、SSID 或實際網段；個人規則只在各機的使用者設定目錄維護。公開倉庫採乾淨新歷史，不推送曾含私人環境資訊的舊提交。

發布前仍須掃描來源與提交歷史，確認沒有密碼、私鑰、個人網路規則或實機報告。Git 作者資訊應使用適合公開的身分。

- 發布前核對目前 remote 指向的 windows_setup 儲存庫。
- 自有程式對外使用的授權；目前沒有擅自加入 MIT 或其他授權。
- 若要提供完整二進位下載包，先確認各第三方再散布權限；不能直接把忽略中的驅動和 EXE 全數上傳。

第三方來源與各自授權見 [THIRD_PARTY.md](THIRD_PARTY.md)。儲存庫可設定 remote 並依維護者授權發布；請以目前 Git remote 與 GitHub 狀態為準。

## Windows CI

工作流程位於 .github/workflows/windows-tests.yml：使用 windows-2022、Windows PowerShell 5.1、唯讀 contents 權限，設定 15 分鐘上限與相同分支舊執行取消。Action 固定到已核對的 commit。main 推送、Pull Request 與 workflow_dispatch 都可觸發。

本機測試指令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-CI.ps1
```

Tests/Run-CI.ps1 可在本機以 Windows PowerShell 5.1 執行，預設把報告放在新建暫存目錄；不套用任何實際使用者設定。它執行自有 PowerShell 語法檢查、Layout.Tests.ps1 -SourceOnly、Init.Tests.ps1、InputMethod.Tests.ps1、SourceRelease.Tests.ps1、HostsSync.Tests.ps1。SourceOnly 只略過 Git 不含的 Autologon EXE 存在檢查，仍核對所有來源、必要資產、驅動 manifest 與入口。實機 Core/Test-SetupPrerequisites.ps1 -PackageOnly 未降低標準，仍要求 EXE 與四個驅動實體檔案及雜湊正確。

每次 CI 將各套件 log 與 summary 上傳為 windows-test-reports artifact，保留 7 天。只上傳明確的 CI 報告資料夾，不上傳測試 fixture、帳號 answer XML、每機 Reports 或秘密。Actions 本身執行 log 的保留天數另由儲存庫設定控制，不是 YAML artifact 保留期。

實機 Setup-Result.json、Setup-Progress.json、Acceptance-Result.json 與驗證結果是續跑或排錯資料，原有 Git 忽略規則保留；CI 不清理這些檔案。設定未完成時不要刪除 Setup-Result.json。雲端通過僅代表來源／隔離測試成功，不表示 NUC 硬體或 OOBE 已通過實機驗收。

## 維護者版本發布

CI 在提交、Pull Request 或手動觸發時執行 Windows PowerShell 5.1 的語法、路徑與隔離測試，不設定實際帳號、不安裝驅動，也不執行 Sysprep。

CD 由 `v主版.次版.修訂` 標籤觸發，例如 `v1.0.0`。它先執行相同 CI；成功後才建立該提交的來源 ZIP、SHA256 清單及中文 GitHub Release。無效標籤或測試失敗都不發布。既有版本不會被覆寫。

### 發布方式

確認 main 的 CI 通過、準備中文 Git 提交與版本說明，並完成 [公開來源與授權注意事項](#公開來源與授權注意事項) 後，在要發布的提交執行：

```powershell
git tag -a v1.0.0 -m "發布 v1.0.0：Windows 初始化與模組設定"
git push origin v1.0.0
```

標籤會觸發 GitHub 上的「Windows 版本發布」流程。版本號應逐次增加，不要移動或重用已發布的標籤。此文件只是操作說明，建立工作流程不代表已建立任何版本標籤。

### 下載內容與保留期限

來源包命名為 `windows_setup_vX.Y.Z_source.zip`，ZIP 根目錄是 `windows_setup/`，版本標題為「Windows 設定工具」。儲存庫名稱為 `windows_setup`。目前一鍵流程仍使用 NUC8i7HV／HN 硬體設定檔；改名不會擴大硬體支援範圍。

- Release ZIP 只含該提交的 Git 來源，不包含 `.git`、驅動 ZIP、Autologon EXE、實機 Reports 或密碼暫存；打包器會拒絕已被錯誤追蹤的這些檔案。
- 依 [來源包準備說明](#從原始碼準備完整工具包) 補齊二進位後才是完整安裝工具包，不能把來源 ZIP 當成完整離線安裝包。
- Release ZIP 與 SHA256 是版本交付物，會持續保留，除非維護者手動刪除該版本。
- CI／CD 測試報告作為 Actions artifact 保留 7 天，不提交進 Git。實機續跑紀錄不受 Actions 清理影響。
- CD 只發布版本檔，不會連線或部署到任何電腦；OOBE、驅動、自動登入及硬體功能仍須實機驗證。

### 本機試打包

對已提交、且不包含私密資料的來源可執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Core\Build-SourceRelease.ps1 -Version v1.0.0 -OutputDirectory "$env:TEMP\windows_setup_source_release_check"
```

這只產生本機版本檔，不建立標籤、不推送、不發布；目的檔已存在時會停止，避免覆寫。
