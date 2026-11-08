# windows_setup

[![Windows CI](https://github.com/ycpss91255/windows_setup/actions/workflows/windows_tests.yml/badge.svg)](https://github.com/ycpss91255/windows_setup/actions/workflows/windows_tests.yml)

![Language](https://img.shields.io/badge/Language-Go%20%2F%20PowerShell-blue?style=flat)
![Testing](https://img.shields.io/badge/Testing-Go%20test%20%2F%20PS5.1-orange?style=flat)
[![Coverage](https://ycpss91255.github.io/windows_setup/main/coverage.svg?style=flat-v2)](https://ycpss91255.github.io/windows_setup/main/index.html)

[最新已發布 main 報表](https://ycpss91255.github.io/windows_setup/) · [Actions 與七天報告附件](https://github.com/ycpss91255/windows_setup/actions/workflows/windows_tests.yml)

上方覆蓋率徽章顯示最近一次成功部署 main 的整體自有程式碼覆蓋率，量測範圍、分項及來源可在報表查閱。徽章與報表標示提交及時間；若部署失敗，以 Windows CI 與 Actions 最新執行結果為準。PR 不更新公開報表。
Windows 設定工具：以 Init 與 Windows 兩個入口完成帳號初始化、模組設定與後續驗收。本文以繁體中文提供完整操作說明；版本摘要見 [變更紀錄](doc/changelog/changelog.md)，實作與驗證細節以中文 Git 提交及 GitHub Release 為準。

## 快速開始

第一次使用，先在一臺可上網的 Windows 電腦完成 [Release 下載、解壓與官方 Autologon 準備](#從原始碼準備完整工具包)，再把完整資料夾放到 USB。GitHub 的 Source code ZIP 不包含 Autologon EXE，也不是完整離線包；不需要 Git、Go、Docker 或 agent。準備完成後，以下選符合目前畫面的一種，不必先查磁碟代號。

### A．還在地區／Wi-Fi 初始設定畫面

Init 執行必需的三個資產位於 `modules/init/assets`：`hide_oobe.ppkg`、`hide_oobe.xml` 與 `provenance.json`。這三檔缺少或驗證失敗時，Init 會在詢問帳密、建立帳號前停止；不能只複製腳本或自行用空檔代替。發行包另附經逐檔審查的 `payload_baseline.json`，供 CI 獨立核對內容；它不是一般電腦初始化或續跑的必要檔案。

1. 將完整工具包命名為 `windows_setup`，放在 USB 根目錄。插入 USB，按 `Shift+F10`（部分鍵盤需加 Fn）。在 CMD 輸入以下一行找入口，不需要 diskpart：

```cmd
for %d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do @if exist "%d:\windows_setup\init.cmd" echo %d:\windows_setup\init.cmd
```

2. 使用找到的完整路徑，例如顯示 `E:\windows_setup\init.cmd` 時輸入 `call "E:\windows_setup\init.cmd"`。E: 只是例子；若列出多份，請選你剛準備的完整工具包。
3. 依中文提示輸入新本機帳號、密碼與確認密碼。設定包套用前會明確詢問是否繼續，因 Windows 可能立即重新啟動；輸入 `YES` 才繼續。取消會保留帳號與無密碼續跑紀錄。
4. 登入剛建立的正式帳號，按 `Win+R` 輸入 `%ProgramData%\windows_setup_init.cmd`，允許同一帳號的管理員權限，安裝 SSH。此步不需要 USB；缺少網路／元件來源時，連網後用同一入口重試。
5. 等顯示「Init 完成」及中文 SSH 連線資訊，再執行下面的 Windows 設定流程。
### B．已經進入正式帳號的 Windows 桌面

1. 接上網路，按 `Windows+E` →「本機／此電腦」→ USB → `windows_setup`。
2. 雙擊 `init.cmd` 安裝 SSH，沿用目前帳號，不重建帳號或密碼。

### 接著套用設定

1. Init 完成後，雙擊同資料夾的 `windows.cmd`。依提示允許權限、輸入目前帳號密碼；不裝驅動時直接 Enter 略過選包。
2. 等整輪結束、查看結果後再手動重開機。從 USB 開啟 `windows_setup\core`，雙擊 `verify_after_restart.cmd` 續跑與驗收。
3. 處理畫面列出的失敗，再雙擊 `verify_only.cmd` 檢查，最後依[目視確認](#6-最後目視確認)核對桌面、工具列及顯示。

桌面清理會刪除一般桌面檔案，開始前先移走要保留的資料。套用 Windows 設定與驗收時使用正式目標本機管理員帳號。執行中保持 USB 連接。

找不到 USB 或需要命令列時，再展開下方的排錯說明；初始設定使用 `Shift+F10`；不必用 `diskpart`。

## 目錄

- [快速開始](#快速開始)
- [執行前提](#執行前提)
- [概覽與適用範圍](#概覽與適用範圍)
- [準備 USB](#準備-usb)
- [初始安裝操作](#先看目前在哪個階段)
- [模組與獨立執行](#模組補充說明)
- [SSH 與 hosts](#ssh-與-hosts-後續維護)
- [來源包準備](#從原始碼準備完整工具包)
- [架構與依賴](#專案架構與依賴方向)
- [CI 與本機測試](#windows-ci)
- [版本發布](#維護者版本發布)
- [目錄索引](#模組資料夾索引)

根目錄 README 是使用入口；[第三方來源與授權](doc/third_party.md)及[版本紀錄](doc/changelog/changelog.md)集中於 doc。agents.md 留在根目錄供維護者與工具明確讀取維護規範，不是一般操作說明；第三方 LICENSE 保持上游原位。

## 執行前提

- 預設自動選擇硬體設定檔：Intel NUC8i7HVB／NUC8i7HNB 使用 NUC8 設定檔；驅動包由你選擇，直接 Enter 預設略過驅動安裝，AMD 模組依機型執行；其他主機板使用 Generic，略過這兩個硬體模組，其餘 Windows 設定照常執行。
- 64 位元 Windows 11 22H2 或更新，專業／企業／教育版；Windows 流程須在正式目標本機管理員桌面執行。
- 完整工具包必須可寫入，不能放在將被清理的桌面；使用者名稱與磁碟代號動態取得。
- 正式桌面需有 Windows Terminal（`wt.exe`）與 App Installer／WinGet（`winget.exe`）；缺少時前置檢查會中止，先補齊再重跑。
- Windows Update 與未快取的 OpenSSH 元件需要網路。UAC、密碼及提示的重新開機需使用者操作。
- 桌面清理會刪除一般桌面檔案、資料夾與捷徑；先取走要保留的內容。桌面排列範本以繁體中文、1920×1080、100% 縮放為準。

## 概覽與適用範圍

Git／GitHub 版本與目前本機完整包不同：驅動及 Autologon EXE 不納入 Git，從原始碼取得後須依 [來源包準備說明](#從原始碼準備完整工具包) 補齊再檢查。第三方來源及授權見 [第三方來源與授權](doc/third_party.md)。公開來源的網路 Sites 預設為空集合；請在本機維護個人規則。

本工具依上方前提自動選用 Generic 或 NUC8 設定檔，Windows 模組亦提供獨立入口。依目前階段先執行 Init，再執行 Windows；不需要 agent、SSH 遙控或預先手動安裝 OpenSSH。使用者名稱、家目錄與 SID 由腳本動態取得；工具包位置依目前檔案所在目錄解析，不綁定固定帳號或磁碟代號。

本機維護的 `windows_setup` 可整份複製到 USB；腳本依自己所在位置解析主程式，不綁定 Downloads、USB 磁碟代號或使用者名稱。驅動獨立放在 `windows_driver_packages/nuc8`，主程式不含驅動封存檔。每次換機使用前要確認 USB 是最新完整副本；舊 USB 不會自動同步本機修改。

完整流程需要你允許管理員權限、輸入現有帳號密碼，以及依提示手動重新開機，並非完全無人值守。一般 Windows 設定不自行重新開機或關機；OOBE 套用設定包前會先明確詢問，Windows 可能在同意後重新啟動。

## 準備 USB

先將完整主程式複製到可寫入的 USB，保持以下結構。主程式內所選功能需要的資產也要帶齊；如果使用 GitHub 原始碼下載，先完成 [來源包準備](#從原始碼準備完整工具包)，來源 ZIP 不含驅動及 Autologon EXE。

```text
USB 根目錄\
├─ windows_setup\
│  ├─ init.cmd
│  ├─ windows.cmd
│  ├─ readme.md
│  ├─ core\
│  └─ modules\              保留整份工具包，其餘檔案也一併複製
└─ windows_driver_packages\  可選；不需要 NUC 驅動可不帶
   └─ nuc8\                 保留 install.cmd、manifest、輔助腳本及四個 ZIP
```

不是只複製兩個 `.cmd`。USB 必須可寫入，執行時保持連接，不可放到會被清理的桌面；`.git` 不是執行必要檔案。可以直接在 USB 使用，也可以自行完整複製到其他可寫入位置，無需固定任何使用者的 Downloads。

<details>
<summary>找不到 USB／需要命令列時</summary>

### 還在初始設定畫面：用 Shift+F10 找到 USB

1. 插上已放好完整工具包的 USB。按 `Shift+F10`（部分鍵盤需 `Fn+Shift+F10`），開啟黑色命令提示字元視窗。
2. 這裡是 **CMD，不是 PowerShell**。下面指令一次輸入一行再按 Enter；不要輸入畫面原有的 `C:\...>` 提示字元。
3. 依序輸入以下三行，查看磁碟清單：

```cmd
diskpart
list volume
exit
```

依 USB 的名稱與容量辨認其 `Ltr` 磁碟代號。這三行只查看清單，不會修改磁碟；最後的 `exit` 只退出 DiskPart，會回到 CMD。

4. 假設清單顯示 USB 是 **E:**，輸入以下三行；**E: 只是例子，必須換成你剛查到的代號**：

```cmd
cd /d "E:\windows_setup"
dir init.cmd windows.cmd
call init.cmd
```

`cd /d` 會一起切換磁碟與資料夾；`dir` 應列出兩個入口。請確認前兩行成功才執行第三行，這不是直接把所有指令一次貼上的步驟。

5. 依 Init 畫面提示繼續。缺少設定包時會在帳號建立前停止；完整工具包會先核對環境、資產與權限，再詢問必要帳密。套用前明確同意 Windows 可能重新啟動。

#### 找不到資料夾或 USB 沒有磁碟代號

若已確認 USB 是 E:，但 `cd /d` 顯示找不到路徑，先輸入：

```cmd
dir E:\
```

請確認根目錄有完整的 `windows_setup` 資料夾。若你放在其他位置，例如 `工具\windows_setup`，先用 `dir "E:\工具"` 查看，確認後改用 `cd /d "E:\工具\windows_setup"`，再執行 `dir init.cmd windows.cmd` 與 `call init.cmd`。每個 E: 都換成實際 USB 代號；只查看已確認的 USB，不必搜尋整顆硬碟。

若清單沒有 USB、USB 沒有 `Ltr`，或裡面根本沒有完整工具包，先重新插接或回另一臺電腦確認 USB 與資料夾；不要猜路徑，也不要為了找腳本而變更磁碟設定。整包結構依上方「準備 USB」，不是只帶一個 `init.cmd`。

</details>

### 已進入稽核或正式桌面：用檔案總管開啟 USB 腳本

1. 按 `Windows+E` 開啟檔案總管，左側選「本機／此電腦」，依名稱與容量找到 USB 並雙擊。
2. 打開 USB 裡的 `windows_setup`（若放在其他資料夾，就逐層打開），確認看得到 `init.cmd`、`windows.cmd`、`core`、`modules`。
3. 雙擊 `init.cmd` 即可。若檔案總管隱藏副檔名，可能只顯示 `init`；可在「檢視 → 顯示 → 副檔名」勾選後再辨認，不必先更改此設定才能執行。
4. 需要參數或想用命令呼叫時，在**這個資料夾的位址欄**點一下（或按 `Alt+D`），輸入 `cmd` 後按 Enter。開啟的 CMD 已位於工具包資料夾，先輸入 `dir init.cmd windows.cmd` 確認。

依目前階段只執行對應的一行，**不要將下面整段一次貼上**。入口會啟動 PowerShell 並在結束後保留視窗；只有本輪確實結束、畫面已有結果時，若看到 `PS` 提示字元，輸入 `exit` 返回原 CMD。尚在執行時不要輸入 exit 或關閉視窗。

```cmd
call init.cmd
```

稽核桌面會處理建帳號；正式帳號桌面會處理 SSH。正式帳號的 Init 成功後，先依上面說明輸入 `exit` 離開保留的 PowerShell、回到原 CMD，再執行下一行；也可重新從工具包位址欄開一個 CMD：

```cmd
call windows.cmd
```

整輪完成並手動重開機後，再按上述方式重新找到同一份工具包、開啟 CMD，執行：

```cmd
call windows.cmd -AfterRestart
```

完成續跑後，先離開保留的 PowerShell 回到 CMD，或重新從工具包位址欄開 CMD。只檢查現況使用：

```cmd
call windows.cmd -VerifyOnly
```

若使用本機完整副本，操作完全相同：先在檔案總管打開該資料夾，再從位址欄開 `cmd`，不需要知道或寫死使用者名稱。使用 PowerShell 者則在正確資料夾執行 `.\init.cmd`／`.\windows.cmd`，不要混用 CMD 與 PowerShell 的目錄切換語法。

重開機後 USB 磁碟代號可能改變，請重新從檔案總管確認、再依上述步驟開啟正確資料夾；不要照抄前一次磁碟代號。主程式與驅動包放在同一 USB、相對目錄保持不變時，續跑會用保存的相對位置及驅動包身分重新核對。若驅動包原本在另一個磁碟／USB，則不猜測新位置；舊路徑失效時，從一般 `windows.cmd` 入口重新選包。不要刪除續跑紀錄來跳過失敗。

## 先看目前在哪個階段

兩個入口各有用途：`init.cmd` 處理初始帳號與 SSH；`windows.cmd` 處理正式帳號登入後的驅動、更新、清理與偏好。不要在 OOBE 或稽核用 Administrator 桌面執行 windows.cmd。

### 情境 A：全新安裝，仍在初始設定／連接 Wi-Fi 畫面

依[快速開始 A](#快速開始)從 USB 的 `init.cmd` 執行。腳本要求 Windows 11 22H2 以上 x64 桌面版，使用官方唯讀 `OOBEComplete` 判斷初始設定，並拒絕 WinPE 與一般 SYSTEM 工作。帳號與密碼由你輸入；不重設或提升既有同名帳號。

設定包只包含 `HideOobe=True`，不含帳密或 Microsoft 工具。先建立並讀回確認正式管理員帳號，才會詢問是否套用；Windows 可能因套用設定包重新啟動，因此必須先輸入 `YES` 同意。腳本不會在 SYSTEM 下執行 Sysprep。

續跑檔案放在 `%ProgramData%\windows_setup_init`，只允許 SYSTEM 與管理員讀寫；同層的 `windows_setup_init.cmd` 供一般使用者唯讀啟動提權。正式登入後用此入口繼續；會核對同一臺機器、目標 SID、家目錄與桌面，再真正安裝 OpenSSH Server。USB 可拔除，帳密不保存在設定包或續跑 JSON。中途取消或缺網時保留狀態，可用同一入口重試；若帳號已建立但寫入所有權紀錄失敗，會保留帳號並停止，請先查看錯誤，不會猜測接管同名帳號。

Init 成功後才從完整工具包執行 `windows.cmd`。Windows 更新等流程結束後依提示手動重新開機，使用 `windows.cmd -AfterRestart` 續跑，再用 `windows.cmd -VerifyOnly` 檢查。
### 情境 B：已有正式本機帳號，從 Windows 桌面開始

此情境保留現有帳號，不重新建立帳號。USB 與本機的完整工具包都可使用，不必先移到 Downloads。

1. 登入要套用設定的本機管理員帳號，確認記得現有密碼；先取走桌面要保留的檔案，接上網路並保持電源穩定。
2. 準備完整工具包：可以直接開啟 USB 的 `windows_setup`，或開啟自行完整複製到本機可寫入、非桌面位置的副本。依上方「已進入稽核或正式桌面」的步驟找到資料夾，再從位址欄開啟 CMD。
3. 執行 `init.cmd`，允許目前帳號提權。這個階段不會重新建立帳號或改密碼；會安裝／啟用 OpenSSH Server、設定區域網路防火牆，並建立目前使用者的 SSH／hosts 框架。離線且缺少 SSH 元件時會明確失敗，接網後再執行 Init。
4. Init 成功後執行 `windows.cmd`，依提示輸入目前帳號的現有密碼供自動登入使用。需要 NUC 驅動才選擇獨立包，否則按 Enter 略過。等待整輪 19 個模組完成，不要中途關機。
5. 整輪結束後手動重新開機，以同一帳號登入，再開啟原本使用的同一份完整工具包；USB 請重新確認本次磁碟代號。
6. 在工具包目錄執行 `.\windows.cmd -AfterRestart`。若仍要求重開，等本輪結束後手動重開，再從同一份工具包續跑。
7. 處理所有失敗後執行 `.\windows.cmd -VerifyOnly`，再逐項完成下方「最後目視確認」。有錯誤時查看 `reports` 及畫面，不將舊結果當成本輪成功。

兩種情境都由目前正式使用者與腳本位置解析路徑，不要求固定帳號、磁碟代號或家目錄；請勿使用另一位管理員的帳密代替目前使用者提權。SSH 可重複執行，Windows 第 04 模組也會再次確認。

以下是正式帳號桌面的後續流程。已完成上方 Init 的使用者，不必再建立帳號；直接確認前提並從步驟 2 繼續。

## 1. 完成 Windows 初始設定

1. 進入 Windows 桌面，登入之後要長期使用的本機管理員帳號。
2. 設定並記住該帳號的現有密碼。帳號可自行命名；自動登入會使用目前帳號，不會要求所有電腦使用同一組帳密。
3. 接上網路並保持電源穩定。完整流程需要下載 Windows Update 與尚未安裝的 OpenSSH 元件。
4. 多臺電腦請先各自設定唯一電腦名稱，例如 `NUC-001`、`NUC-002`；名稱變更要求重開時先完成重開，再開始下列流程。
5. 取走桌面上需要保留的資料。桌面清理模組會刪除使用者桌面及共用桌面的普通檔案、資料夾和捷徑，最後只留下四個系統圖示。

## 2. 確認 USB 工具包與可選驅動

已按「準備 USB」完成者，繼續使用同一份 USB 工具包，不必再複製到本機。以下是主程式的完整結構概覽：

```text
windows_setup\
├─ init.cmd                    初始帳號／SSH
├─ windows.cmd                 正式帳號桌面設定
├─ readme.md                   本文件
├─ core\                      主流程、驗證與路徑表
├─ modules\                   每個功能自己的腳本、資產與獨立入口
│  ├─ init\                   OOBE 帳號初始化與正式登入續跑
│  ├─ ssh\                    SSH 及 hosts 同步
│  ├─ drivers\
│  │  └─ manifests\           驅動清單範本（不含封存檔）
│  ├─ updates\                Windows Update
│  ├─ debloat\                清理與 Win11Debloat
│  └─ …                        帳號、記憶體、電源、桌面、輸入法等
├─ reports\                   本機整體進度、結果與紀錄（不納入 Git）
├─ test\powershell\          unit／integration／system 分層測試
└─ doc\changelog\            版本摘要與紀錄規範
```

驅動包獨立於主程式。執行 `windows.cmd` 先顯示偵測主機板：一般電腦自動略過 NUC 驅動；支援 NUC 才提示選包。找到相鄰 `windows_driver_packages/nuc8` 時，輸入 Y 才選用，P 可指定其他位置，Enter 略過。找不到包或包校驗失敗時，可輸入正確目錄或 Enter 略過；也可明確傳入：

```powershell
$driverPath = Read-Host '貼上目前獨立驅動包 nuc8 的完整路徑（不用加引號）'
.\windows.cmd -DriverPackagePath $driverPath
```

偵測失敗或板號空白／明確未知時，選 R 重新偵測、G 或 Enter 使用通用設定，或依下表選擇實際 NUC 整機，再輸入完整板號確認。回報已知其他板號、同時回報多塊板，或重新偵測與確認不符時，不允許強制套用 NUC 驅動。手動確認只影響驅動；AMD 位置設定仍只依自動偵測。原始板號、偵測錯誤與確認值分開保存在該機 reports。獨立包可自行執行 `install.cmd`；只核對完整性用 `install.cmd -PackageOnly`。獨立安裝器使用相同偵測與未知型號確認流程；已知其他機型略過，不能拿 NUC 驅動套用其他硬體。`-PackageOnly` 是離線驗包，不可與手動確認參數混用。續跑只沿用同一電腦與使用者先前明確選擇的驅動包，並核對 package.json／manifest.json 的雜湊；同 USB 相對位置可隨盤符變動解析，包身分變更則拒絕。整包複製至其他電腦不沿用舊選擇。

`-NonInteractive` 僅關閉驅動選擇的詢問，並不代表 Windows 全流程無人值守；自動登入等模組仍可能詢問密碼。無互動主控台時也不等待驅動輸入，未選包即略過。需自動化處理「未知」且已人工確認的實機時，可明確傳入 `-ConfirmedBoard NUC8i7HVB -ConfirmationComputer $env:COMPUTERNAME -DriverPackagePath $driverPath -NonInteractive`（HNK 使用 HNB）；已知其他機型仍拒絕。`windows.cmd -VerifyOnly`／`-AfterRestart` 不接受新的型號或包選擇，只恢復同機同帳號紀錄；重新選擇請走一般入口。明確傳入空路徑表示略過，未提供路徑才允許互動選包。

不要只複製單一 `.cmd`／`.ps1`；主程式與獨立驅動包各自保留完整結構。`.git` 僅在維護版本時需要，執行設定與獨立驅動包不依賴它。
工具包不要放在桌面或其子資料夾內，以免桌面清理刪到工具包。直接使用 USB 時，USB 必須可寫入且本輪全程保持連接；下一輪仍從同一完整副本續跑。若自行改用本機完整副本，才改從本機該份執行。

腳本不會自行把工具包複製到 Downloads，也不會自動同步其他副本。要更新別臺電腦時，由你選擇要複製的完整主版本；先保留目的地的自訂檔及需要的執行紀錄，避免直接覆蓋。

### 獨立驅動包的明確適用型號

主工具的通用 Windows 設定不限定 NUC；下表只限制可選 NUC 驅動包與目前 NUC AMD 模組。

| 整機／套件型號 | 官方 BIOS 主機板識別 | 腳本接受的 Win32_BaseBoard.Product |
| --- | --- | --- |
| Intel NUC8i7HVK（同板整機：NUC8i7HVKVA、NUC8i7HVKVAW） | NUC8i7HVB | `NUC8i7HVB` |
| Intel NUC8i7HNK（同板整機：NUC8i7HNKQC） | NUC8i7HNB | `NUC8i7HNB` |

型號對照依 [ASUS 官方 NUC 規格索引](https://zentalk.asus.com/t5/faq/nuc-technical-product-specifications-for-nuc-products/ta-p/451363)；HVK／HVB 亦見 [Intel 技術規格](https://www.intel.com/content/dam/support/us/en/documents/mini-pcs/nuc-kits/NUC8i7HVK_TechProdSpec.pdf)。官方表列的是 BIOS 識別，腳本實際讀取 SMBIOS 主機板 Product，去除首尾空白後比對白名單；不依外殼貼紙猜型號，也不表示所有 NUC8 都支援。可先執行 `(Get-CimInstance Win32_BaseBoard).Product` 查看。已知非白名單值會安全略過；只有空白／明確未知或讀取失敗才提供受控手動確認，確認不會覆寫報告中的原始偵測值。

這是型號對照與安裝條件，不代表每個整機變體已實測。四個封存檔不是完整的所有裝置驅動集；仍須依裝置管理員與 Windows Update 檢查其他驅動。AMD 封存檔 GFX-Radeon-Win10-23.10.01.46.zip 在官方列為 Windows 10 64-bit，不能宣稱 Windows 11 官方認證；本工具在 Windows 11 的結果須逐機驗證。 驅動來源見 [ASUS NUC8i7HVK 下載頁](https://www.asus.com/uk/supportonly/nuc8i7hvk/helpdesk_download/)。

## 3. 執行第一次設定

1. 在正式目標帳號桌面，從同一 USB 雙擊 `windows.cmd`；不要使用稽核模式的 Administrator。
2. Windows 管理員權限提示選「是」。請用目前登入的目標帳號執行，不要輸入另一個管理員帳號代替。
3. 依提示輸入目前帳號的現有密碼，用來設定開機自動登入。密碼不會寫入工具包腳本。
4. 等待視窗中的 19 個模組執行完畢。進度與結果以中文顯示；Windows Update 可能需要較久。

執行期間不要關閉主視窗、移動工具包、關機或提早重開機；若從外接磁碟執行，不要拔出該磁碟。即使畫面顯示某一個模組完成，也要等整輪結束。

若有錯誤，記下模組名稱與訊息，並查看工具包內的 `reports\Setup-Result.json`。腳本可能繼續後面的模組，因此「本輪執行結束」不一定代表所有模組成功。進度可查看 `reports\Setup-Progress.json`；更新進度可另開 `modules\updates\show_update_status.cmd`。

如果在最前面的帳號密碼／自動登入階段就中止，這個失敗不會加入後續模組重試清單；先修正密碼或畫面指出的問題，再執行 `windows.cmd`。不要把上次留下的結果檔當成本輪已完成。

## 4. 等整輪結束後手動重新開機

主視窗完成全部階段並提示重新開機後，再由 Windows 電源選單選「重新啟動」。

第一次設定完成後仍應重新開機一次，讓登入後設定生效，不要只因更新沒有標示待重開機就跳過這一步。

重新進入桌面時，確認是否自動登入正確帳號。如果沒有自動登入，先手動登入原本同一個帳號並記下現象，不要換帳號繼續。

## 5. 執行重開機後驗收

1. 開啟這臺電腦先前使用的同一 USB 上 `windows_setup`；先重新確認 USB 磁碟代號與終端所在位置。
2. 在此資料夾的終端執行 `.\windows.cmd -AfterRestart`，允許管理員權限；也可雙擊 `core\verify_after_restart.cmd`。
3. 等待本輪結束。這個入口會重試同一臺電腦、同一帳號先前失敗且可重試的模組，重新掃描更新，再做清理及驗證。
4. 若更新或驗收提示仍需重新開機，等本輪結束後手動重開，再執行一次 `windows.cmd -AfterRestart`。
5. 直到顯示驗收通過、沒有未解決失敗，也沒有待重新開機提示，再做下面的目視確認。

更新可能分成多輪。若相同錯誤持續出現，不要只靠一直重跑；查看 `reports\Acceptance-Result.json` 的 `Errors`／`FailedChecks`、`reports\Verification-Result.json` 及畫面訊息。另一臺電腦的舊結果不代表目前這臺成功。

如果只是想檢查現況，在此資料夾的終端執行 `.\windows.cmd -VerifyOnly`（或雙擊 `core\verify_only.cmd`）；它不安裝更新或重新套用偏好。若開始選單驗證顯示工作尚未回傳結果，先等該工作結束，再重新驗證。

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
- NUC8 設定檔：AMD Software 不再於登入時詢問位置權限；Generic 不套用此模組。如果舊提示已經顯示在畫面上，先手動關閉該提示，再於下次登入確認。

四個桌面圖示的排列範本以繁體中文 Windows、1920×1080、100% 縮放為準。自動檢查不能取代上述登入與畫面觀察。

## 19 個模組的執行順序

| 順序 | 處理內容 |
| --- | --- |
| 01 | 目前帳號開機自動登入 |
| 02 | 停用磁碟分頁檔（虛擬記憶體） |
| 03 | 插電時停用自動睡眠／休眠 |
| 04 | OpenSSH Server、區域網路防火牆、SSH 目錄與 hosts／SSH 同步框架 |
| 05 | NUC8 選擇獨立包才安裝；未選包或 Generic 顯示略過 |
| 06 | NUC8 拒絕 AMD Software 位置存取；Generic 顯示略過 |
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

第 15 模組會在缺少時新增英文（美國）`en-US`，並確保存在美式鍵盤 `0409:00000409`，再設為預設輸入法；保留中文、其他語言、既有鍵盤與順序，不安裝英文顯示語言包或切換 Windows 介面語言。若只要補英文鍵盤，可雙擊 `modules\input\apply_input_method_settings.cmd`；只檢查可在工具包目錄執行 `modules\input\apply_input_method_settings.cmd -VerifyOnly`。檢查會同時確認英文語言、美式鍵盤及預設輸入法，結果寫入 `%ProgramData%\NUC8-Setup\InputMethod-Result.json`。

各模組資料夾內另有獨立 `.cmd` 入口，例如 `modules\input\apply_input_method_settings.cmd`，詳見下方模組補充說明。不要因某一模組失敗就手動更動其他無關模組。

## SSH 與 hosts 後續維護

第 04 模組會建立目前使用者的設定與中文說明：

- `%USERPROFILE%\.ssh\readme.md`：SSH 連線別名、帳號、連接埠等用途與修改方式。
- `%USERPROFILE%\.config\hosts\readme.md`：網路規則及 hosts 對照來源的用途與修改方式。

hosts 設定資料夾保留在 `.config\hosts`，不改成 `.hosts`。Windows 系統 hosts 仍是 `%WINDIR%\System32\drivers\etc\hosts`。

SSH 與 hosts 可獨立或配合使用。這套工具目前提供可修改的網路規則與空白主機範本，不會自行填入真實主機 IP、遠端帳號或 SSH 私鑰。需要時依資料夾內 README 編輯；`active-sites.conf` 是自動產生的載入清單，不要手動修改。既有自訂 README 會保留。

## 範圍、版本與結果紀錄

Windows 啟用由使用者另外處理；本工具不處理 Ubuntu 分割或安裝。Windows 不允許移除的系統元件會保留，清理數量會隨 Windows 狀態而不同。

非繁體中文系統略過既有桌面圖示座標範本，但仍處理系統圖示 GUID。硬體或語系不適用項目明確顯示 Skipped，不計為通過；其他語系的電源解析等仍可能需要實機調整。請以目前這臺電腦的驗收結果為準，不保證不同 Windows 版本、硬體或螢幕得到完全相同的更新版本及刪除數量。

使用者可見的修改見 [變更紀錄](doc/changelog/changelog.md)；詳細驗證結果與限制以中文 Git 提交及 GitHub Release 說明記錄。工具包內已建立本機 Git，但執行設定不需要安裝 Git；若要查看歷史，可在工具包目錄執行 `git log -5 --oneline`。每機執行結果不納入 Git，請保留需要的診斷紀錄。

## 模組資料夾索引

| 資料夾 | 用途 |
| --- | --- |
| `modules\init` | 初始帳號建立 |
| `modules\accounts` | 自動登入 |
| `modules\memory` | 分頁檔 |
| `modules\power` | 電源與睡眠 |
| `modules\ssh` | SSH 與 hosts 同步 |
| `modules\drivers` | 驅動 |
| `modules\amd` | AMD 位置權限 |
| `modules\updates` | 更新與進度 |
| `modules\debloat` | 預載 App、OneDrive、Copilot 清理 |
| `modules\taskbar` | 工作列 |
| `modules\start_menu` | 開始選單 |
| `modules\display` | 解析度與縮放 |
| `modules\desktop` | 桌面圖示與排列 |
| `modules\theme` | 深色與背景 |
| `modules\input` | 英文美式鍵盤 |
| `modules\terminal` | Terminal 快捷鍵 |
| `modules\explorer` | 隱藏檔與副檔名 |
| `modules\cleanup` | 舊系統與資料夾殘留 |

主流程結果位於 `reports`；各模組的執行紀錄位於各自資料夾或畫面提示的 `%ProgramData%\NUC8-Setup`。既有程式碼不再全部平鋪在根目錄，請勿只取出其中一支腳本執行。

## 模組補充說明

### 各模組行為

1. Apply-AutologonSettings：以目前帳號設定自動登入；密碼透過 Microsoft Autologon 儲存，不寫在工具包腳本。
2. Apply-PagefileSettings：停用磁碟分頁檔；重開機後完全生效。
3. Apply-PowerSettings：插電時停用自動睡眠和休眠；保留螢幕逾時設定。
4. Apply-SSHSettings：安裝並啟用 OpenSSH Server；自動啟動，防火牆限制 LocalSubnet。
5. Install-Drivers：NUC8 且已選擇獨立包才核對機型與 SHA256 後安裝；未選包或 Generic 略過。異常裝置仍在驗收中檢查。
6. Apply-AMDPrivacySettings：NUC8 拒絕 AMD Software 地理位置存取；Generic 略過。已顯示的提示需手動關閉。
7. Install-WindowsUpdates：執行本輪 Windows 建議更新，顯示心跳進度並記錄是否需要重開機。
8. Apply-Debloat：先呼叫 remove_one_drive.ps1 解除安裝 OneDrive，再依 debloat_apps.txt 清理預裝 App，包含 Xbox App、Game Bar、相關登入與語音元件，以及存在時的 Gaming Services。Windows 不可移除的 XboxGameCallableUI 保留。
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

- modules\desktop\save_desktop_layout.cmd：圖示移動後，將目前位置儲存成新範本。
- modules\updates\show_update_status.cmd：查看更新進度；關閉進度視窗不會停止更新。
- windows.cmd -VerifyOnly：檢查設定、目前顯示比例、圖示座標、開始釘選匯出、App清理、輸入法及快捷鍵程序。
- Terminal 快捷鍵日誌：%LOCALAPPDATA%\NUC8-Setup\TerminalHotkey\status.log。
  REGISTERED 表示成功註冊；LAUNCHED 表示收到按鍵並呼叫 Terminal；FAILED 1409 表示快捷鍵衝突，需要排查。

### 主機名稱與區域網路

- 連線時使用自己的帳號與主機名稱，例如 ssh your_user@nuc-001.local；名稱解析與連線須在實機確認。
- .local 用於同網段 mDNS，訪客網路、隔離網路或跨VLAN可能無法使用。
- 多臺電腦建議路由器固定 DHCP 租約；需要跨網段時使用區域 DNS，例如 nuc-001.home.arpa。
- 沒有寫入固定 IP、個人 SSH 私鑰、hosts 站點資料或其他人的 SSH config。


## 清理與網路規則補充

OneDrive 獨立入口為 `modules\debloat\remove_one_drive.cmd`；解除安裝後僅清除空的預設資料夾，不刪除個人或雲端資料。清理模組對 Windows.old、Contacts、Saved Games、Favorites、Links、Searches 只清除符合空目錄條件的項目；含資料或連結時保留。具名預設 Bing 書籤、捷徑與內建搜尋定義可清除，其他自訂內容保留；不可移除及僅 Staged 的 Windows 元件不代表一般已安裝 App 未清理。

Hosts／SSH 獨立入口為 `modules\ssh\apply_hosts_sync.cmd`、`sync_hosts.cmd`、`sync_ssh.cmd`。目前使用者的 `.config\hosts\sites.json` 支援任意站點，透過 Outputs 分別啟用 Hosts／SSH；每 10 秒重新讀取來源，未變更不重寫。SSID 若受定位權限限制，可用 NetworkProfile 或 IPv4Cidr，不會強制開啟定位。框架沒有實際主機清單或私鑰；詳細範例保留在模組內 `modules\ssh\custom_hosts_sync\usage.txt` 與 SSH／hosts README。

`.ssh` 具有 Windows Hidden 屬性；啟用顯示隱藏項目時仍可看見。第 04 模組設定 LocalSubnet 的 IPv4／IPv6 Ping 入站規則，名稱解析與 Ping 分開驗證，沒有關閉防火牆。rsync、SSH-agent、Tab 補全及金鑰部署尚未納入。

## 來源包與完整工具包

### 主程式與可選驅動包

主程式 `windows_setup` 與 `windows_driver_packages/nuc8` 是兩個獨立資料夾。只做一般 Windows 設定時帶主程式即可；需要 NUC 驅動才另帶驅動包。主程式只提示相鄰標準目錄，仍須明確選擇才使用，並核對包身分與四個封存檔雜湊。

### 從原始碼準備完整工具包

以下可以從全新的 Release 下載開始，不使用任何既有 Downloads／USB 資產。準備電腦需要 Windows 與網路；此階段只準備檔案，不執行 Init、Windows 設定或 Autologon。

1. 開啟 [Releases](https://github.com/ycpss91255/windows_setup/releases)，選擇要使用的版本，先閱讀該版本說明與已知限制。標示 **Pre-release** 的版本是預覽版，不能當作已完成實機驗收。展開該版本的 **Assets**，下載 **Source code (zip)**。
2. 在檔案總管對下載的 ZIP 按右鍵 →「全部解壓縮」。打開解壓後資料夾，直到同一層可看到 `init.cmd`、`windows.cmd`、`readme.md`、`core` 與 `modules`；這一層就是工具包根目錄。可將它重新命名為 `windows_setup`，保留完整內容，**不要直接在 ZIP 視窗內執行**。解壓與執行位置必須可寫入，而且不能是稍後會被清理的桌面。
3. 開啟 [Microsoft Sysinternals Autologon 官方頁](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon)，按 **Download Autologon** 取得 `Autologon.zip`，另行「全部解壓縮」。從中找到 **`Autologon64.exe`**；不要選 `Autologon.exe` 或 `Autologon64a.exe`，這套工具使用 x64 版本。
4. 在 `Autologon64.exe` 按右鍵 →「內容」→「數位簽章」，選擇 Microsoft Corporation 的簽章並按「詳細資料」，確認顯示此數位簽章正常。若沒有簽章、不是 Microsoft 或驗證失敗，先停止，重新從官方取得並排查驗證問題，不要略過。將核對後的 **`Autologon64.exe`** 複製到剛才工具包根目錄的 **`modules\accounts`**，最終位置為 `windows_setup\modules\accounts\Autologon64.exe`；不用雙擊 EXE。
5. 執行前閱讀 [Sysinternals 官方授權條款](https://learn.microsoft.com/en-us/sysinternals/license-terms)及下載包內的授權說明。後續 `windows.cmd` 的自動登入模組會驗證 Microsoft 簽章，並以 `/accepteula` 呼叫 Autologon 接受條款；不接受條款時不要執行該模組或 Windows 一鍵流程。下載與複製檔案本身不會設定自動登入，也不會執行 EXE。
6. 回到工具包根目錄，在檔案總管的**位址欄**輸入 `cmd` 後按 Enter。黑色命令視窗會從這個資料夾開始；貼上以下一行並按 Enter，執行既有的只讀套件檢查：

   ```cmd
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\core\test_setup_prerequisites.ps1 -PackageOnly -HardwareProfile Generic
   ```

   檢查會核對主程式檔案與語法，不安裝軟體、不變更 Windows 設定，也不代表已通過實機驗收；它不取代上一步數位簽章核對。出現缺檔或錯誤時先依訊息修正，不繼續。未選擇驅動包不要求驅動檔；`Generic` 是此離線檢查使用的設定檔，實際套用時仍自動辨識機型，不能用它強制套用特定硬體設定。
7. 檢查成功後，將**整個**工具包根資料夾複製到可寫入的 USB；可保留名稱 `windows_setup`。確認 USB 副本內有兩個入口、`core`、`modules` 及剛補入的 EXE，不只複製 `.cmd`。也可直接在 USB 完成以上準備與檢查；不依賴固定磁碟代號或使用者名稱。
8. 在目標電腦插上 USB：仍在地區／Wi-Fi 畫面時，依快速開始 A 以 Shift+F10 呼叫 Init；已登入正式帳號時依快速開始 B。OOBE 流程需要完整自有設定包；SSH 元件、Windows Update 與未快取下載需要網路。

若要一併檢查已準備的 NUC 獨立包，將上述檢查參數改為 `-PackageOnly -HardwareProfile NUC8 -DriverPackagePath "實際獨立包目錄"`；這只驗證檔案，不安裝驅動。完整來源包準備不代表主程式自帶各硬體驅動，詳見下一節。以上採用官方下載與既有套件檢查，無需額外開發環境。

### 準備獨立 NUC 驅動包

既有可用包放在 `windows_driver_packages/nuc8`，包含 `install.cmd`、自身的 `core`／`modules` helper、`package.json`、`manifest.json` 與四個 ZIP；不依賴原主程式路徑。需要重新建包時，準備符合 `modules\drivers/manifests/nuc8.json` 的四個封存檔，並將此範本複製為來源目錄的 `manifest.json`，再執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\package\export_driver_package.ps1 -SourceDirectory "已核對的驅動來源目錄" -OutputDirectory "新的獨立包目錄"
```

輸出目錄必須不存在。導出會驗證四個封存檔雜湊、產生可攜入口及機型識別；不安裝驅動。取得新驅動應使用原廠可信來源，改版需要重新驗證，不能直接修改 SHA256 來略過檢查。

`package_hashes.json` 是本機主程式交付快照，不追蹤於 Git，也不把外部驅動納入主程式。獨立驅動依自身 manifest 核對；Git clone 缺少交付快照不代表程式損壞。
### 不納入 Git 的內容

- 驅動 ZIP、Autologon EXE、安裝封存檔與其他大型二進位。
- 各機 `reports`、進度、結果、快取、備份與執行日誌。
- `.ssh`、私鑰、known_hosts、密碼、Token、Init answer file、owner/runtime/state 等實機資料。
- 本機套件雜湊快照與暫存測試副本。

忽略規則不會刪除本機完整包的必要檔案。不要為了讓 Git 工作樹乾淨而刪除驅動或使用者自訂設定。

### 公開來源與授權注意事項

公開版 `modules\ssh/custom_hosts_sync/sites.json` 使用空白 Sites，不帶公司、SSID 或實際網段；個人規則只在各機的使用者設定目錄維護。公開倉庫採乾淨新歷史，不推送曾含私人環境資訊的舊提交。

發布前仍須掃描來源與提交歷史，確認沒有密碼、私鑰、個人網路規則或實機報告。Git 作者資訊應使用適合公開的身分。

- 發布前核對目前 remote 指向的 windows_setup 儲存庫。
- 自有程式對外使用的授權；目前沒有擅自加入 MIT 或其他授權。
- 若要提供完整二進位下載包，先確認各第三方再散布權限；不能直接把忽略中的驅動和 EXE 全數上傳。

第三方來源與各自授權見 [第三方來源與授權](doc/third_party.md)。儲存庫可設定 remote 並依維護者授權發布；請以目前 Git remote 與 GitHub 狀態為準。

## 專案架構與依賴方向

本專案對齊 base 將「交付給使用者的執行程式」與「維護儲存庫的工具」分開；Windows 執行樹保留 `core`／`modules`，不將 Linux／Docker 專用的 `dist` 照字面搬入。

| 位置 | 職責 |
| --- | --- |
| `core`、`modules`、根目錄 Init／Windows 入口 | Windows 交付執行樹：帳號、設定、驗收與獨立功能 |
| `script/test` | 測試調度與報告產生 |
| `script/release` | 版本準備、發布門檻與 Release 說明 |
| `script/package` | 從可信來源建立獨立驅動包 |
| `test/powershell/unit`、`integration`、`system` | 各層測試案例；system 需明確指定可丟棄環境 |
| `.github/workflows` | 雲端 CI 與發布編排 |

依賴方向為維護工具／測試 → 交付執行樹。`core`／`modules` 不依賴 `script`、`test` 或 `.github`；一般使用與獨立驅動安裝不需要儲存庫維護工具。

自有原始檔與目錄使用小寫與底線，新驅動安裝日誌位於 `modules\drivers/driver_logs`。為保留已部署電腦的續跑資料，`%ProgramData%\NUC8-Setup`、`NUC-Init`、`CustomHostsSync` 及既有排程工作名稱維持相容；這些是系統既存識別，不是新增的儲存庫目錄。第三方 `win11debloat` 內部目錄及內容保持上游原樣。

## Windows CI

工作流程位於 .github/workflows/windows_tests.yml：使用 windows-2022、Windows PowerShell 5.1、唯讀 contents 權限，設定執行時間上限與併發控制。Action 固定到已核對的 commit。main 推送、版本標籤、Pull Request 與 workflow_dispatch 都可觸發；ci-rollup 統一呈現測試門檻。

### 自動報表與徽章

CI 使用與 base 相同的 GitHub Actions 原生徽章；整體覆蓋率使用儲存庫自行產生的 flat SVG。Pages 保留簡潔報表，提供測試結論、版本、提交、時間、整體覆蓋率、語言明細，以及 Release、README、Actions 與可下載證據。不依賴 Codecov、Coveralls 或外部報表平台。

README 只展示整體覆蓋率，語言分項放在報表與 Actions 摘要。整體以自有正式程式碼的可執行行計算，從各語言量測結果換算相同計量後加總覆蓋行與總行數，不取各語言百分比平均。測試、第三方內容及非執行設定檔依來源清單明確分類；缺來源、未支援語言或缺量測時不公布假的總率。

每次測試從實際斷言事件及程序退出碼產生 JSON、Markdown、自含 HTML、JUnit XML 與徽章。程序崩潰、缺少斷言事件或任何失敗均不能標成通過。新增 `test/powershell/unit` 或 `integration` 測試會自動列入執行清單。公開報表只包含靜態檢查、單元與隔離整合結果。

PR 的去識別測試附件保留七天；main 通過全部必要門檻後更新 Pages，失敗時公開徽章仍保留上次成功部署的證據。Release 長期保存 `repo_coverage.json`、`coverage_inventory.json`、`coverage.xml` 與測試摘要，核對來源、計量、雜湊及計數。歷史版本依原始證據整理頁面並連回不可變原始附件；缺紀錄就如實說明，不以目前測試回填。

各機續跑及排錯的 `reports` 保留於該機，不納入 Git 或 Pages。`windows.cmd -AfterRestart` 與 `windows.cmd -VerifyOnly` 是產品功能，繼續供設定後續跑及檢查。

### 測試分層與本機入口

測試依 base 的 tool-first 方式放在 `test/powershell/<層級>`；純函式／模擬 Windows API 的單元測試與實際跨元件的隔離整合測試分開執行，不把同一套測試重複掛名兩層。

| 層級 | 範圍 | 執行環境與限制 |
| --- | --- | --- |
| `unit` | Init 路由、帳號／密碼與 XML；硬體適用性、略過與結果彙總；輸入法模組 | Windows API 以 mock 取代，不建立真實帳號或修改使用者語言 |
| `integration` | 清理器與暫存 Windows 目錄；硬體入口、包身分／雜湊、獨立驅動包導出；hosts 規劃；真實 Git 發布；來源結構與入口路由 | 使用暫存檔案及隔離 Git，實際組件協作，不安裝驅動或套用系統偏好 |

```powershell
# 全部單元與隔離整合測試（預設）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\test\run_ci.ps1
# 只跑指定層；仍會進行語法檢查
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\test\run_ci.ps1 -Layer Unit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\test\run_ci.ps1 -Layer Integration
```

報告每項包含 `Layer`、`Status`、`Executed`。未選擇的隔離層不宣稱已執行。`SourceOnly` 只略過 Git 不含的安裝二進位，仍檢查程式、資產、驅動中繼資料及入口。

### 開發用 Windows Docker 環境

這是維護者的程式與隔離測試環境。控制入口沿用 base 將維護操作集中於工具腳本的方向，採 Windows 原生 PowerShell；不宣稱與 base 的 Linux／just 指令完全相同。一般使用者從 USB 執行 `init.cmd`／`windows.cmd` 不需要 Docker。

先準備可使用 **Windows containers** 的 Docker engine 與 Compose v2，建議使用乾淨、未放入個人資料的完整 Git checkout（必須包含 `.git` 目錄）。Linux containers 模式不能執行這份 Windows PowerShell 5.1 環境。Windows Server 與 Windows 用戶端的隔離模式相容條件不同，依 [Microsoft 容器需求](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/system-requirements)與[版本相容說明](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility)設定；使用 Docker Desktop 時另依 [Docker 官方 Windows 安裝條件](https://docs.docker.com/desktop/setup/install/windows-install/)。本工具只檢查，不會自動安裝 Docker、切換引擎或啟用主機功能。

在儲存庫根目錄開啟 PowerShell：

```powershell
# 只檢查目前 Docker／Windows container 能力
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\docker\docker.ps1 -Action doctor
# 建立開發映像
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\docker\docker.ps1 -Action build
# 建置最新映像並執行全部單元／隔離整合測試
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\docker\docker.ps1 -Action test
# 開啟容器內的 PowerShell 開發終端
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\docker\docker.ps1 -Action shell
```

預設使用 `process` 隔離；有相容 Hyper-V 環境時可明確加 `-Isolation hyperv`。`test` 自動建置，不會沿用不明版本映像。完整來源 checkout 以唯讀方式掛載，包含 `.git` 與被 Git 忽略的本機檔案，容器能讀取它們；這不是去識別的來源副本。建置 context 另由 `.dockerignore` 白名單限制。容器 shell 用於檢查與執行程式，不能直接編輯唯讀來源；請在主機編輯後重跑測試。報告寫入儲存庫以外的新目錄；預設位置會顯示在輸出，也可用 `-ReportDirectory` 指定一個尚不存在的絕對路徑。容器失敗會回傳非零退出碼，不會以空報告或略過當作通過。

維護工具以 Go 為主要實作語言；Windows 原生設定與 PowerShell 5.1 測試保留 PowerShell，一般使用者執行設定不需要 Go。根目錄 `go.mod` 僅管理 `script/test` 工具與 `test/go` 案例，沒有改變交付程式的依賴方向。HTML5 解析使用固定版本的官方 `golang.org/x/net/html`，其餘驗收使用標準庫；必要上游原碼及授權保存在 `vendor`，離線容器不下載模組。

直接執行 Go 測試時，在完整 checkout 根目錄使用 `go test -mod=vendor -count=1 ./...`，並將 `WINDOWS_SETUP_ARTIFACT_DIR` 指向 PS5.1 產生的 public 報告、`WINDOWS_SETUP_PORTAL_FIXTURE_DIR` 指向 `script/test/create_portal_fixture.ps1` 產生的 portal 目錄。兩者缺少即失敗，不以跳過掩蓋缺證據；上述 Docker `test` 入口會自動準備這些輸入。Go 單元及整合測試包含原有 21 項驗收契約與新增解析／命令列邊界案例，結果獨立於 PS5.1 報表數量。

容器映像提供 Windows PowerShell 5.1、固定版本且核對雜湊的 MinGit 與 Go 1.27.3。一般本機未設定 GitHub 執行來源時，PS5.1 仍測試目前真實 checkout，保留其 Clean／Dirty 狀態；Go 需求合約使用另外明確標示 Synthetic 的暫存樣本，不改寫或冒充本機正式報告。本機模式不產生已通過 80% 的 CI 覆蓋率證據。CI 則必須以本次真實報告驗收，執行 Go 量測並通過 80% 門檻；GitHub 提交、儲存庫、執行 ID、ref 類型與 ref 名稱這五項只要部分存在或格式錯誤就停止，不會降級成合成證據通過。

CI 的 `docker-tests` 使用真正的 `windows-2022` runner 執行 Docker build/run；容器內執行全部 PS5.1 單元／隔離整合測試，再產生明確的合成首頁樣本並執行 Go 需求正負例、全套 Go 覆蓋率量測與產物驗收。主機另核對容器報告中的提交、執行來源、測試狀態與環境，不以主機驗收代替容器內 Go 執行。PS5.1 報表的套件／斷言統計不把 Go 驗收數量混入；Go 結果與實際退出碼另列於 Docker 工作日誌。`ci-rollup` 同時要求主機測試、需求驗收及 Docker 測試成功。在 [Actions](https://github.com/ycpss91255/windows_setup/actions/workflows/windows_tests.yml) 開啟該次執行，於 Artifacts 下載 `docker-test-reports-執行ID-重試次數`，解壓後開 `index.html`；這是容器的獨立 public 報告，只保留七天。原始 logs 不上傳。Pages 仍展示 Windows runner 的報告，與明確標記 Windows container 的短期報告分開；Docker 門檻未通過時不發布新的 Pages 報表，避免混淆兩個環境的證據。

每次 CI 將去識別的 HTML／JSON／Markdown／JUnit 與徽章上傳為 windows-test-reports artifact，保留 7 天；原始套件 log 不上傳。另有 requirements-fixture artifact，只含程式明確建立的合成首頁樣本，固定假 SHA、示例執行網址及 Synthetic 環境標記，不含帳密或實機資料，同樣保留 7 天供需求門檻驗證。這份樣本不是正式測試證據，不混入 windows-test-reports、Release 或 Pages。其他測試副本、帳號 answer XML、每機 Reports 與秘密均不上傳。Actions 本身執行 log 的保留天數另由儲存庫設定控制，不是 YAML artifact 保留期。

實機 Setup-Result.json、Setup-Progress.json、Acceptance-Result.json 與驗證結果是續跑或排錯資料，原有 Git 忽略規則保留；CI 不清理這些檔案。設定未完成時不要刪除 Setup-Result.json。


## 維護者版本發布

版本發布參考 base 的 PR、CI gate 與標籤流程；Windows 測試及來源檢查保留本專案的實作。不是每次合併都自動增加 patch 版本。維護者先選擇版本、整理使用者可見的變更，再經 PR、CI 與標籤發布。

### 準備版本與 Pull Request

日常變更寫入 `doc/changelog/changelog.md` 的 `## [Unreleased]`。要發布時，在工作分支執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\release\prepare_release.ps1 -Version v0.2.0
```

此命令將 Unreleased 區段提升為指定版本、寫入 `.version`，不提交、不建立標籤也不推送。審查版本內容後，以中文提交並開啟 Pull Request。主分支要求 `ci-rollup` 通過；使用保留各階段提交的 rebase merge，不以 squash 抹掉 TDD 證據。版本必須符合 `vX.Y.Z` 或 `vX.Y.Z-rcN`。

### 標籤與發布門檻

合併後，確認 main 的 CI 通過、版本檔與 changelog 一致，再在該提交建立標籤：

```powershell
git switch main
git pull --ff-only
git tag -a v0.2.0 -m "發布 v0.2.0：通用 Windows 設定與版本流程"
git push origin v0.2.0
```

同一個 Windows workflow 接受 main 推送、Pull Request、手動執行與版本標籤。`isolated-tests` 完成後由 `ci-rollup` 統一回報；只有版本標籤通過測試，且提交位於 main 歷史、`.version` 與 changelog 精確匹配，才發布 Release。RC 標為預覽版；正式版本整合同版 RC 的版本紀錄。既有標籤與版本不應刪除、移動或重用。

主分支與 `v*` 標籤使用要求 `ci-rollup` 的保護，管理員也遵守；禁止強制推送或刪除。遠端設定的實際啟用狀態以 GitHub Rules／Branch protection 為準，檔案本身不能啟用遠端保護。

### 下載內容與保留期限

從 GitHub Release 使用內建 **Source code (zip)** 或 **Source code (tar.gz)** 下載來源，不額外上傳重複來源 ZIP／SHA256。內建來源封存檔的根目錄名稱由 GitHub 決定。若使用快速開始的 USB 自動尋找指令，請改名為 `windows_setup` 並放在 USB 根目錄；腳本本身可放任意路徑，手動呼叫該位置的 `init.cmd` 即可。

- 來源不包含 `.git`、驅動 ZIP、Autologon EXE、實機 Reports 或密碼暫存；來源檢查會拒絕錯誤追蹤的敏感檔案。
- 依 [來源包準備說明](#從原始碼準備完整工具包) 補齊所選功能需要的二進位，不能把來源 ZIP 當成完整離線安裝包。
- CI 報告與 Actions 日誌短期保留 7 天，不提交進 Git；實機續跑紀錄仍留在原機。
- Release 只發布來源與版本說明，不會連線部署到任何電腦。OOBE、驅動、自動登入及硬體功能仍須實機驗證。
- v0.1.x 已發布的舊來源 ZIP／SHA256 保持原樣，新流程不回寫舊版本。

### 本機檢查發布內容

對已提交、版本檔及 changelog 已一致的來源執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\release\build_source_release.ps1 -Version v0.2.0 -OutputDirectory "$env:TEMP\windows_setup_release_check"
```

此命令驗證來源並產生 Release 說明，不再重複打包來源 ZIP；不建立標籤、不推送、不發布，也不代表雲端 CI 已通過。

### 檔名與舊版相容性

本專案的自有檔案統一小寫 snake_case，例如 `init.cmd`、`windows.cmd`、`script/test/run_ci.ps1`；Windows 不分大小寫不代表 Linux／GitHub 也能接受舊拼法。`agents.md` 也依此命名，部分工具不再自動發現原本大寫 AGENTS.md 的規範，維護時須主動讀取本檔。

第三方 Win11Debloat 原始碼、授權及供應的 Autologon／驅動封存檔保留原始檔名，不改上游契約或內容。既有每機報告、排程 worker、ProgramData 目錄與系統固定名稱也保留既有契約，避免失去續跑資料；這些不是新的儲存庫原始檔。舊報告內的模組檔名會映射到新的腳本名稱，仍檢查同一電腦與使用者，不代表允許沿用他機結果。請用新版入口，不另保留重複的舊檔名腳本。

### 自動需求驗收與獨立審查

PR 與 main 的 `requirements-gate` 讀取同一次 PS5.1 測試產物，驗證來源、統計、JUnit／JSON 狀態、文件連結、隱私與 base 徽章規格，並用破壞性負例確認錯誤會被拒絕；`ci-rollup` 必須同時取得測試與需求驗收成功才能合併。PR 的證據保留原分支身分，不會冒充 main。

Pages 部署後會匿名 GET 公開首頁、main 報表、JSON／Markdown／JUnit、unit／integration／system／PowerShell coverage 四個 SVG、Go coverage SVG、README 的 CI／Go coverage／PowerShell coverage 實際網址及歷史版本頁；提交與 Actions 執行必須屬於本次 main。Language／Testing 是靜態說明徽章，載入與外觀另由人工目視確認。CDN 延遲只有限重試，舊報表或不一致會使 workflow 失敗。這些是可重複的自動驗收，不需要 agent 才能續跑；人工視覺檢查另由審查者確認。

實作、freeze、主代理與未參與實作的獨立代理完整審查流程見 [維護規範](agents.md)。發現問題必須修正後重新全需求審查，不能把上次 PASS 沿用到修改後版本。

每個問題／功能採嚴格 TDD，以獨立中文提交保留「測試（紅）→ 修改（綠）→ 優化（綠，可選）」及實跑命令、原因與結果；最終必要 CI 全綠才合併，歷史紅燈提交保留。純文件修改只記錄真實文件核對，不偽造失敗測試；既有歷史不追造 TDD。完整規則集中於 [維護規範](agents.md#嚴格-tdd-與中文提交證據)。
