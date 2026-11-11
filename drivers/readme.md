# 驅動設定檔

通用 Windows 設定與機型驅動分開。`core/hardware.ps1` 讀取本目錄各 `profile.json`，精準比對 `Win32_BaseBoard.Product`；相同板號被兩個設定檔宣告時拒絕選型。未登錄的電腦或未選擇獨立驅動包時略過驅動，其他通用模組仍可使用。

| 設定檔 | 主機板 Product | 相鄰獨立包目錄 | 說明 |
| --- | --- | --- | --- |
| `nuc8i7hvk_hnk` | `NUC8i7HVB`、`NUC8i7HNB` | `windows_driver_packages/nuc8` | [機型、版本與依賴](nuc8i7hvk_hnk/readme.md) |

每個設定檔的 `profile.json` 保存安全的小寫單段 ProfileId／PackageDirectory、x64 架構與板號白名單；`manifest.json` 保存官方來源、原始及衍生包雜湊、逐 INF／CAT 與完整 payload 檔案雜湊。ZIP 不納入 Git。獨立包同時攜帶設定檔原始檔，`package.json` 的版本 2 身分綁定其 SHA256 與板號；僅修改套件自宣板號不能讓其他電腦通過。

新增其他機型時建立自己的設定檔及實際官方來源清單，再以共用 export 指定 `-ProfileId`。不要把別款驅動複製進 NUC 清單，也不要放寬板號或以類別 ID 代替精確裝置 ID。未知型號的現有 NUC 雙重確認流程保留，已知不相符的板號拒絕強制。舊四檔版本 1 身分只保留原兩款 NUC 相容讀取。

匯出命令與完整 USB 操作見根目錄 [readme.md](../readme.md)。
