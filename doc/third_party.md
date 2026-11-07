# 第三方來源與授權

本文件列出工具包使用的第三方內容；各自的授權不代表本專案自有程式已採用相同授權。本專案自有程式目前尚未選定對外散布授權，公開發布前需由維護者決定，不能把下列 MIT 授權套用到整個工具包。

## Win11Debloat

- 上游：[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)。
- 本包釘選提交：`5d88bfe9ef2be5a8a643166a6400eb78a30c46ec`，依據 [debloat_profile.json](../modules/debloat/debloat_profile.json)。
- 原始碼與必要資產保存在 `modules/debloat/win11debloat`，包括上游的 `Assets/Images/menu.png` 與空白開始選單資產 `Assets/Start/start2.bin`。
- 保留上游 [MIT LICENSE](../modules/debloat/win11debloat/LICENSE)、作者聲明及 README。`start2.bin` 的用途見同目錄的 `What is this file.txt`；它是上游提供的空白範本，不是從使用者電腦匯出的個人開始選單。
- 本工具透過 CLI 呼叫上游，採用的清理項目另由 `debloat_apps.txt`、`debloat_profile.json` 控制。

## Microsoft Sysinternals Autologon

- 官方來源：[Autologon](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon)。
- 本機完整包使用 `modules/accounts/Autologon64.exe`，檔案版本為 3.10；執行模組會驗證 Microsoft 數位簽章。
- 此 EXE 不納入 Git。從官方取得工具並遵守其授權；不要因本專案包含呼叫腳本就推定可重新散布該二進位。

## 裝置驅動

四個驅動封存檔保留於主程式之外的可選獨立包 `windows_driver_packages/nuc8`，不納入 Git。檔名及已核對的 SHA256 範本見 [nuc8.json](../modules/drivers/manifests/nuc8.json)；獨立包自身使用 `manifest.json` 核對完整性。

目前用途為晶片組、Serial IO、UCM 及 AMD 顯示驅動。這些檔案具有各供應商自己的授權，不能把本專案或 Win11Debloat 的授權視為驅動的散布許可。儲存庫只追蹤雜湊清單，不承諾第三方下載位置永久有效。

## Windows 內建元件

OpenSSH Server、Windows Update、Sysprep 與 Windows PowerShell 使用目標系統提供的元件；沒有把它們的二進位加入 Git。離線環境若尚未快取 OpenSSH 安裝來源，仍須接網或另外準備符合目標 Windows 的元件來源。

## Go 維護工具與 HTML5 解析器

- 工具鏈使用 [Go 官方下載](https://go.dev/dl/)的 Go 1.27.3，Windows 容器 ZIP 的 SHA256 釘選於 `script/docker/install_go.ps1`；SDK 不提交 Git，也不要求一般設定使用者安裝。
- HTML5 解析使用 Go 官方專案 [golang.org/x/net/html](https://pkg.go.dev/golang.org/x/net/html)，釘選模組 `golang.org/x/net v0.62.0`，由根目錄 `go.mod`／`go.sum` 記錄。這是額外依賴，不宣稱僅使用標準庫。
- `go mod vendor` 保留實際需要的 html 與 atom 原始碼；[BSD 類授權 LICENSE](../vendor/golang.org/x/net/LICENSE)及[PATENTS](../vendor/golang.org/x/net/PATENTS)維持上游原名與內容。自有檔名規則僅在此明確第三方路徑例外，不修改上游來源。
- CI 與容器使用 `-mod=vendor`、`GOPROXY=off`、`GOTOOLCHAIN=local`；固定 SDK 在建置階段準備，執行驗收時不自動下載模組或切換工具鏈。
