# 迭代紀錄
## 2026-11-07 — 統一本機資料夾名稱與公開發布位置

- 將 Downloads 主包資料夾更名為 `windows_setup`，保留完整驅動與相對路徑結構。
- 更新目前操作文件與維護規範，避免仍指向舊資料夾名稱；歷史紀錄不重寫。
- 公開儲存庫使用 `ycpss91255/windows_setup`；發布前先核對本機雜湊，再等待 GitHub Windows CI 通過。

## 2026-11-07 — 統一 Windows 設定工具名稱與底線發布格式

- 對外名稱改為「Windows 設定工具」，儲存庫名稱為 windows_setup；來源發布包使用 windows_setup_vX.Y.Z_source.zip，ZIP 根目錄為 windows_setup/。
- 同步 README、操作與發布文件、CD 版本標題及封裝測試；本機資料夾可以改名，不更改既有腳本識別、ProgramData 狀態路徑或續跑紀錄。
- 明確區分通用 Windows 模組與現有 NUC8i7HV/HN 一鍵硬體設定檔。保留主流程及驅動主機板限制，沒有宣稱其他硬體已支援。
- Windows PowerShell 5.1 隔離測試通過：Layout 297、Init 29、輸入法 19、來源發布 12、Hosts/SSH 9 項及語法檢查；未執行實機設定，未更動舊 USB。
- 更新本機 Package-Hashes.json，包含既有 Autologon 與驅動檔案，排除 Git、報告及雜湊清單本身。
## 2026-11-07 — 公開來源規則與版本發布流程

- 公開來源的網路 Sites 預設為空集合，移除特定場域的別名例外；保留 global 規則與 Hosts／SSH 各自獨立的同步功能，使用者可在本機設定實際站點。
- 新增 HostsSync 隔離測試 9 項，使用暫存來源規劃，不寫入系統 hosts 或真實 SSH 設定。
- 新增 vX.Y.Z 標籤觸發的 CD：Windows CI 通過後才發布 GitHub Release 的來源 ZIP、SHA256 與中文說明；不包含驅動、EXE、報告或私人資料。
- 新增 SourceRelease 隔離測試 11 項，驗證版本格式、中文空白路徑、校驗碼、來源封裝與拒絕敏感檔／既有輸出覆寫。
- CI 聚合納入發布封裝與通用 hosts 規則測試；雲端與實機驗證仍分開，不因本機打包成功就宣稱實機設定通過。

## 2026-11-07 — 新增 Windows CI 與短期測試報告

- 新增 GitHub Actions Windows Server 2022／PowerShell 5.1 工作流程，支援 main 推送、PR 與手動觸發；使用唯讀權限、固定 Action commit、15 分鐘上限及舊執行取消。
- 新增 Tests/Run-CI.ps1，執行語法、來源結構及 Init／輸入法隔離測試，不執行實際 Windows 設定或 Sysprep。
- Layout 加入明確的 SourceOnly 模式，以支援不含 Autologon EXE／驅動 ZIP 的 Git 原始碼；實機 PackageOnly 依舊要求完整二進位及驅動雜湊。
- 報告寫入 runner 暫存並上傳為保留 7 天的 artifact，不進 Git；保留各機 Reports 和續跑需要的 Setup-Result.json，沒有清除實機紀錄。
- 本機使用僅 Git 追蹤來源加本輪新檔建立乾淨副本，Windows PowerShell 5.1 CI 各套件全通過；雲端執行與實機驗收結果分開記錄。

## 2026-11-07 — 整理 GitHub 原始碼與本機完整包邊界

### 修改理由與內容
- 為後續上傳 GitHub 整理儲存庫；本輪未建立 remote、未建立遠端儲存庫或推送。
- 新增 GitHub 準備指南與第三方來源說明，明確區分可直接複製的本機完整包與不含驅動／Autologon EXE 的 Git 原始碼。
- 保留 Win11Debloat 上游 MIT LICENSE；精準納入其 menu.png 與空白 start2.bin 原始資產，避免 clone 缺少上游檔案。驅動只追蹤 manifest.json，不追蹤四個大型 ZIP。
- 未替本專案自有程式擅選開源授權；Windows 執行流程及本機必要二進位保持不變。
- 發布前排除個人環境資訊；公開規則採空白範本，舊的私人提交不得推送。

### 驗證與限制
- 檢查追蹤檔及既有歷史未發現真實密碼、SSH 私鑰或常見 Token；測試用假密碼與 Windows 內建 SID 不當作使用者憑證。
- 驗證必要資產與 driver manifest 可追蹤，而 EXE／ZIP、每機報告及 Init 密碼暫存仍被忽略；保留本機完整包，不為 Git 清潔刪除驅動。
- 本輪僅文件、忽略規則與原有來源資產納入版本，不執行設定、重啟、Sysprep 或修改 USB。尚未做公開發布，也未重寫提交歷史。

## 2026-11-07 — 明確以自包含 Downloads 主包作為可攜版本

### 修改理由與內容
- 使用者澄清：Downloads 主包應包含所需驅動，整包複製即可使用；USB 是先前資料，不再作為預設同步目標。
- 更新 README、詳細使用說明與 AGENTS 第 5 至 7 條，明確主包可放在任意可寫入、非桌面的路徑，不強制位於 Downloads，也不綁定帳號或磁碟代號。
- 說明內建 Modules/Drivers/Payload 的 4 個驅動封存檔與 manifest.json，不需要 USB 旁邊的 Driver；保留 Init／Windows 原有階段及模組使用方式。
- 本輪沒有實作自動 staging／自動複製功能，沒有修改程式、驅動、實機設定或舊 USB。

### 驗證與限制
- 主包 Windows PowerShell 5.1 PackageOnly 通過 19 個模組、必要檔案與 4 個驅動；內建驅動檔皆存在且 SHA256 符合 manifest。
- Init／Windows 入口及模組解析使用套件相對路徑，驅動優先使用內建 Payload。
- 完整內容（578 檔，含 4 個驅動，排除 .git 與 Reports）複製到不同的中文含空白路徑後，Windows PowerShell 5.1 PackageOnly 通過 19 模組／4 驅動，Layout 287 項通過；驅動來源確認為新位置內的 Payload。這是內容／路徑驗證，未執行實際設定；測試副本保留，沒有宣稱已清除。
- 深入檢查未發現固定 特定使用者 帳號、個人 SID、IP 或家目錄；自動登入使用目前帳號／電腦名稱，桌面工作與 Startup 使用目前身分／已知資料夾，SSH 依當次 SID／profile 安裝。套件未攜帶每機 runtime、私鑰或 answer file；hosts 安裝後的 owner 限制是每機防接管設計，不是固定使用者。
- Init 29 項與輸入法 19 項隔離測試通過，均未改變真實帳號或系統設定。
- 自包含指腳本、資產與驅動齊全，不代表完全離線；Windows Update 與未快取的 OpenSSH 元件仍需要網路，Windows／機型等前置條件仍適用。
- 新 Init／OOBE 流程尚未在實機完整驗證。本輪為文件澄清，不宣稱完成新的實機安裝。


## 2026-11-07 — 拆分 Init／Windows 入口與模組資料夾

### 修改理由與內容
- 使用者需要在 Windows 初始設定階段建立本機帳號與密碼、啟用 SSH，並要求內部依用途分資料夾，避免全部平鋪。
- 根目錄只保留 `Init.cmd` 與 `Windows.cmd` 兩個可執行入口。Init 負責初始帳號／正式帳號 SSH；Windows 保留原本 19 個設定模組，並以 `-AfterRestart`／`-VerifyOnly` 區分續跑與只讀檢查。
- 新 Init 對 SYSTEM/OOBE 只提供進入稽核模式的指引；稽核用內建 Administrator 經確認後才詢問帳號、密碼與確認密碼，使用官方 unattended oobeSystem 與 Sysprep `/oobe /quit /unattend`，不使用 `/generalize`、跳過機器設定旗標或自動重開機。
- 密碼 answer file 僅暫存於本機受 SYSTEM／Administrators ACL 保護的 `%ProgramData%\NUC-Init`；首次正式管理員登入按本工具標記清理密碼檔，保留非秘密狀態紀錄。Base64 不是加密，未把密碼放入 USB、Git 或命令列。
- 正式帳號桌面再次執行 Init，才安裝與啟用 SSH、LocalSubnet 防火牆及該使用者的 SSH／hosts 框架，並顯示主機名稱、使用者、IPv4 與 SSH 連線命令。離線缺少 OpenSSH 來源時如實回報未完成。
- 內部拆為 `Core` 共用流程／路徑表、18 個用途的 `Modules` 資料夾、`Docs` 與 `Tests`；每個模組腳本及依賴資產放在一起，獨立 CMD 仍可執行。
- `Reports` 保存主流程進度與驗收結果，模組紀錄維持在模組或既有 ProgramData；驅動仍可從 USB 旁邊的 `Driver` 取得，Downloads 內建封存檔移至 `Modules/Drivers/Payload`。
- Windows 前置檢查拒絕 SYSTEM、內建 Administrator 或未完成 OOBE 的環境，避免把正式使用者偏好套到稽核帳號；PackageOnly 仍可只讀檢查套件。
- 更新根 README、詳細說明與 SSH／hosts README 的新路徑；精準排除 Init 秘密暫存與各機報告，不刪既有資料或改動同名使用者設定。

### 驗證與限制
- Windows PowerShell 5.1 結構／路徑／安全 stub 分流測試 287 項、Init 隔離測試 29 項、英文輸入法隔離測試 19 項通過；主代理另從 USB 獨立重跑全部測試及 19 模組／4 驅動前置檢查皆通過；沒有建立真實帳號、更改 Windows 偏好或觸發 Sysprep／重新開機。
- 兩包前置檢查核對 19 個模組、必要檔案及 4 個驅動封存檔；共享套件逐檔 SHA256 比對一致。
- 被複製到 ProgramData 的顯示、工作列、桌面、更新等 worker 沒有加入 Core 路徑依賴；SSH watcher 與 Terminal listener 維持本機 runtime。
- 新 Init／OOBE 流程尚未在實機完整跑過，未宣稱安裝成功或無條件支援所有 Windows 映像。未知 Setup 狀態、既有 answer file、S mode 或 Sysprep 錯誤會停止；原有 answer file 不會被盲目刪除。
- Microsoft 不支援 SYSTEM 身分執行 Sysprep，因此 Wi-Fi 畫面需先手動 `Ctrl+Shift+F3` 進入稽核模式，再執行 Init；不能在該畫面一次呼叫就直接完成全部設定。


## 2026-11-07 — 補強英文美式鍵盤建立與完整驗證

### 修改內容
- 第 15 模組確保目前使用者的英文（美國）en-US 與美式鍵盤 0409:00000409 存在，再設定預設輸入法；即使新建語言物件未自帶鍵盤，也明確補齊。
- 保留中文、其他語言、既有鍵盤及原順序，不安裝英文顯示語言包、不改 Windows 介面語言。
- Apply 與 VerifyOnly 都重新讀取實際語言清單、美式鍵盤與預設值；避免只有 override 正確卻誤判成功。結果 JSON 新增各項明確狀態及中文錯誤。
- 更新整體驗收項目與 README 的單獨執行方式，兩包同步。

### 驗證與限制
- PowerShell 5.1 隔離測試 19 項通過：缺英文、缺美式鍵盤、已有正確設定、其他語言與鍵盤保留、VerifyOnly 不呼叫設定指令、設定未實際保存時拒絕成功。
- 主代理另從 USB 獨立執行上述 PowerShell 5.1 測試，19 項全部通過；套件前置檢查通過 19 個模組及 4 個驅動封存檔。
- 測試使用模擬 Windows 語言指令，未更動目前電腦或重裝後 NUC 的實際語言設定；新安裝電腦仍需執行模組並查看實際驗證結果。

## 2026-11-07 — 新增 USB 重裝後完整操作指南

### 修改理由與內容
- 使用者希望重新安裝 Windows 後，直接依 USB 內的說明完成設定，不必回查聊天內容。
- 在工具包根目錄新增繁體中文 `README.md`，涵蓋執行前帳號／網路／桌面資料準備、USB 目錄結構、第一次設定、手動重新開機、重開後驗收及目視確認。
- 列出 19 個模組順序、錯誤與結果檔判讀；區分會重試／更新／清理的 `Verify-AfterRestart.cmd` 與只讀的 `Verify-Only.cmd`。
- 說明第一階段帳密或自動登入失敗需修正後重跑主入口、首次完成必須重新登入，以及目前 SSH／hosts 為空白主機框架、資料夾保持原位置。
- Downloads 與 USB 使用同一份 README；本輪只新增文件及迭代紀錄，不更動系統設定程式。

### 驗證與限制
- 對照 `Configure-NUC.ps1`、`Verify-AfterRestart.ps1` 與既有使用說明核對入口、模組順序與失敗重試行為。
- 兩包 Windows PowerShell 5.1 前置檢查通過 19 個模組、必要檔案與 4 個驅動封存檔；同步後逐檔雜湊比對一致。
- 本輪為文件更新，未執行 NUC 設定、更新、清理或重新開機；第二臺全新電腦完整安裝仍尚未實跑。

## 2026-11-07 — 補齊 SSH 與 Hosts 資料夾的繁體中文 README

### 修改理由與內容
- 使用者希望在實際設定資料夾直接查看中文維護說明；保留目前 `.ssh` 與 `.config/hosts` 路徑，不改變目錄配置。
- 新增 `CustomHostsSync/SSH-README.md` 與 `CustomHostsSync/Hosts-README.md` 範本；初始化時分別建立目前使用者的 `.ssh/README.md`、`.config/hosts/README.md`。
- README 說明各檔案用途、動態規則與 Hosts／SSH 分開控制方式；只在檔案不存在時建立，不覆蓋既有自訂 README。
- 補上套件必要檔案檢查及中文使用說明；同步核心程式與先前版本相同，沒有搬移來源檔、建立新 `.hosts` 目錄或變更同步規則。

### 驗證
- 主代理獨立檢查差異與 README 內容，Windows PowerShell 5.1 installer-isolation 18 項測試全部通過。
- NUC 於 2026-11-07 20:23:00.850（Asia/Taipei）執行 Verify-HostsReadme，12 項全部通過。
- 原有 8 個設定／來源檔 SHA256 不變；沒有新增 `.hosts` 目錄，兩份 README 均存在且含繁體中文。
- 背景 watcher 與 Hosts／SSH 兩種輸出均正常，SSH 初始化及 Hosts 同步模組的 VerifyOnly 皆通過。
- 本輪未重新開機；未把資料夾說明驗證描述成第二臺全新安裝或真實網路切換測試。

## 2026-11-07 — 完成動態網路匯入框架、檔案顯示與 USB 整合驗收

### 修改理由與內容
- 使用者要求依網路自動匯入 Hosts／SSH，站點數量與規則必須可自訂，且兩種輸出需可分開使用。
- 新增 `CustomHostsSync` 框架，從目前使用者的 `.config/hosts/sites.json` 動態讀取任意站點與 `Outputs.Hosts`／`Outputs.SSH` 個別開關；每 10 秒重讀規則與來源。
- 支援使用者自訂站點及 NetworkProfile、IPv4 CIDR 條件；公開範本不預填個人網路規則。
- 新增獨立入口 `Apply-HostsSync.cmd`、`Sync-Hosts.cmd`、`Sync-SSH.cmd`，透過第 04 模組整合；主流程仍維持 19 個模組。
- 依目前帳號動態取得 SID、使用者家目錄；安裝時記錄 owner，避免另一個帳號接管同一個系統 hosts 同步工作。修正中文使用者路徑在 SYSTEM 執行時的 UTF-8 讀取問題。
- SYSTEM 背景工作有 AtStartup 觸發、不限執行時間；ProgramData 程式僅 SYSTEM／管理員可寫，目前使用者可讀，不從 USB 長期執行。
- 保留系統 hosts 管理區塊以外內容；內容未變更時不重寫 Hosts 與 SSH 輸出。套件只建立空白來源範本，不加入真實 IP／主機清單或私鑰。
- 檔案總管顯示副檔名及一般隱藏項目，最後再套用四個桌面圖示位置；相關即時狀態已納入驗證。
- Git 精準排除 CustomHostsSync 每機 runtime、status、owner、錯誤紀錄與 hosts／SSH 備份；保留站點設定來源及測試檔可追蹤。

### 已完成驗證
- 網路規則測試 65 項、同步測試 36 項、獨立審查測試 19 項、安裝器測試 10 項、單模組入口測試 5 項皆通過；安裝器測試另由主代理重跑通過。
- NUC 安裝及重裝成功：SYSTEM 排程工作為 Running、執行時間限制 `PT0S`；ProgramData 程式存取權符合預期。
- 25 秒內兩次 polling 的 heartbeat 前進，Hosts／SSH 輸出均回報成功；兩個輸出檔的修改時間不變，原 hosts 完整前綴保留，實際 HostsMapping 數為 0。
- `.config` 具 Hidden 屬性；副檔名登錄值與 Shell 狀態均為顯示，一般隱藏檔仍顯示；四個圖示座標恢復並通過檢查。
- 曾於實機核對區域網路名稱解析與 IPv4 連線；公開紀錄不保存實機名稱或位址。
- 完整驗收前一次 34 項檢查出現 StartMenu worker 暫態逾時，其餘 33 項通過；晚到結果為 Success=true。20:09:19 的精準 VerifyOnly 確認 PinCount=0，未為此改設定或停止程序。
- 開始選單逾時訊息改為明確說明「60 秒內未取得工作結果，工作可能仍在執行，等待完成後再驗證」；未改 timeout、工作執行或驗證邏輯，Windows PowerShell 5.1 語法檢查通過。
- 2026-11-07 20:10:23（Asia/Taipei）NUC 整體唯讀驗收 Passed=true，34 項全部通過、0 項失敗；主代理另讀取遠端及本機驗收 JSON 核對。
- Downloads 與 USB 的前置檢查均通過：19 個模組、必要檔案與 4 個驅動封存檔完整；USB 557 項套件雜湊逐項核對通過。
- 兩包共享 557 個檔案內容一致；Package-Hashes.json 明確排除 .git，自身與 Drivers 的包裝差異不納入共享檔比對。

### 限制與尚未驗證項目
- 未提供實際主機 IP／別名清單，本輪交付為框架與空範本；目前 ActiveSites 空白不代表故障。
- NUC 關閉定位時 Windows 拒絕 SSID 讀取，狀態明確顯示 SSIDUnavailable；可由使用者選擇 `NetworkProfile` 或 CIDR 條件，不強制啟用定位。
- 尚未做真實 Wi-Fi 切換與重新開機測試；AtStartup 觸發已註冊，但不宣稱已通過開機驗證。
- 第二臺全新 Windows 的完整端到端安裝尚未實跑。Git 僅保存在本機與 USB，未上傳外部倉庫。

## 2026-11-07 — 建立 Git 版本基準（hosts 框架進行中）

### 修改理由與內容
- 使用者要求腳本位置加入 Git，後續每次迭代以中文留下可核對紀錄。
- 將既有 19 個一鍵設定模組、輔助腳本、設定範本、中文說明及 Win11Debloat 原始碼建立版本基準。
- 新增 `.gitignore`、`.gitattributes` 與 `AGENTS.md`，規範中文變更紀錄、提交、測試、動態帳號與 USB 同步方式。
- 保留現有檔案，不將驅動/安裝二進位、密碼與私鑰、各機報告/紀錄或快取加入版本。

### 驗證
- 檢查 Downloads 與 USB OneClick，兩處原本均不是 Git 工作樹。
- 檢查 Win11Debloat，未發現內嵌 `.git`；以一般來源檔案追蹤，不建立意外的 submodule。
- 此提交是現有工具包的初始檢查點；後續提交將補上框架完成後的測試結果。

### 已知限制／未完成
- hosts／SSH 依網路自動匯入框架仍由其他工作項目實作中，尚不能宣稱完成。
- 框架只準備動態規則與空站點範本，使用者尚未提供實際主機 IP／別名資料。
- 第二臺全新 Windows 的完整端到端安裝仍未實跑。
- Git 僅在本機與 USB 建立版本，沒有上傳外部倉庫。
