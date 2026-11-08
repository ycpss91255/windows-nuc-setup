# NUC8i7HVK／NUC8i7HNK 驅動設定檔

查核日期：2026-11-08。設定檔 `nuc8i7hvk_hnk`，架構 x64，獨立包目錄 `nuc8`。

| 整機／套件型號 | 主機板 Product |
| --- | --- |
| NUC8i7HVK；同板 NUC8i7HVKVA／NUC8i7HVKVAW | NUC8i7HVB |
| NUC8i7HNK；同板 NUC8i7HNKQC | NUC8i7HNB |

依 [ASUS 官方產品規格索引](https://zentalk.asus.com/t5/faq/nuc-technical-product-specifications-for-nuc-products/ta-p/451363) 的 Hades Canyon 板號對照；不是所有 NUC8 都適用。Intel 顯示官方支援處理器清單包含 i7-8809G／i7-8705G。精準硬體 ID 仍是每個目標的第二道條件，未枚舉裝置不強行建立。

## 官方版本與組件

以下套件版號與 INF 裝置版號分開。完整 HardwareIds、INF／CAT 路徑與 SHA256、每個 payload 檔案 SHA256 均在 [manifest.json](manifest.json)。`SourceUrl` 是原廠原始封存檔，`File` 是交付 ZIP；從 EXE／MSI／CAB 唯讀擷取的 ZIP 不等於原始檔雜湊。`Provenance.OfficialPublishedHash`（或 PublishedSHA512）有值才是官方公布值，其他 SHA256 為實際計算，不冒稱 ASUS 已公布雜湊。

| 套件 | 套件版本 | INF／組件版本 | 官方原始下載 |
| --- | --- | --- | --- |
| `chipset` | 10.1.19376.8374 | `kabylakesystem`: 10.1.10.5<br>`skylakesystem`: 10.1.7.4<br>`skylakesystemgmm`: 10.1.7.4<br>`sunrisepoint_hsystem`: 10.1.6.2<br>`sunrisepoint_hsystemlpss`: 10.1.6.2<br>`sunrisepoint_hsystemthermal`: 10.1.6.2 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_7_Board/Chipset-Win10_Win11-10.1.19376.8374.zip) |
| `serial_io` | 30.100.1914.3 | `ialpss2_gpio2_skl`: 30.100.1914.3<br>`ialpss2_i2c_skl`: 30.100.1914.3<br>`ialpss2_spi_skl`: 30.100.1914.3<br>`ialpss2_uart2_skl`: 30.100.1914.3 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Rugged_Kit/SerialIO-WIn10_Win11-30.100.1914.3.zip) |
| `ucm` | 1.0.10.3 | `tps659xx`: 1.0.10.3 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Pro_Board/UCM-WIN11-1.0.10.3.zip) |
| `radeon_vega_m` | 23.10.01.46 | `u0393589`: 31.0.21001.46001<br>`atihdwt6`: 10.0.1.27<br>`uwppair`: 31.2310.0.0<br>`amdocl`: 31.0.21001.46001<br>`amdwin_u0393589`: 31.0.21001.46001<br>`amdfendr`: 23.10.0.6<br>`amdfdans`: 1.0.2310.1 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/Intel_NUC_Board/GFX-Radeon-Win10-23.10.01.46.zip) |
| `wifi_8265` | 22.200.2 | `wifi_8265`: 20.70.32.1 | [官方來源](https://downloadmirror.intel.com/777193/WiFi-22.200.2-Driver64-Win10-Win11.exe) |
| `bluetooth_8265` | 22.200.0 | `bluetooth_8265`: 22.200.0.2 | [官方來源](https://downloadmirror.intel.com/774201/BT-22.200.0-64UWD-Win10-Win11.exe) |
| `intel_lan` | 31.3 | `i219`: 12.19.2.64<br>`i210`: 14.1.28.0 | [官方來源](https://downloadmirror.intel.com/931390/Wired_driver_31.3_x64.zip) |
| `realtek_audio` | 6.0.9456.1 | `realtek_audio`: 6.0.9456.1 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Rugged_Kit/Audio-Win10_Win11-6.0.9456.1.zip) |
| `mei_software_components` | 11.8.93.4323 | `mei`: 2220.3.1.0<br>`mei_dal`: 1.41.2021.0121<br>`mei_icls`: 1.64.1234.0<br>`mei_wmi`: 2219.3.0.0 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Rugged_Kit/ME_Consumer-Win10_Win11-11.8.93.4323.zip) |
| `sd_reader` | 2.1.101.10640 | `sd_reader`: 2.1.101.10640 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Rugged_Kit/SDCard-Win10_Win11-2.1.101.10640.zip) |
| `cir` | 5.5.2.1 | `cir`: 5.5.2.1 | [官方來源](https://dlcdnets.asus.com/pub/ASUS/NUC/NUC_8_Rugged_Kit/CIR-WIn11-5.5.2.1.zip) |
| `intel_graphics` | 31.0.101.2145 | `intel_graphics`: 31.0.101.2145<br>`intel_graphics_cui`: 31.0.101.2145<br>`intel_graphics_igcc`: 31.0.101.2145<br>`intel_display_audio`: 10.27.0.14 | [官方來源](https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe) |

## 安裝與讀回契約

- 12 包、33 個 INF 裝置目標、1 個 AMD Extension；ZIP 約 1.636 GiB，封存檔與 1,211 個 payload 檔案雜湊已核對。35 組 INF／CAT（含不適用 Win11 的 Intel 控制器擴充研究項）使用 Microsoft SDK signtool `/pa /c` 原生驗證，實際退出碼均為 0；CAT 成員驗證與目前裝置是否採用該驅動是不同檢查。
- 晶片組套件 10.1.19376.8374 不代表每個 INF 都是這版；各 INF 保留 10.1.10.5／10.1.7.4／10.1.6.2。Serial IO GPIO／I2C／SPI／UART 與 UCM TPS659xx 依精準 ID 個別判斷。
- Wi-Fi／藍牙採 Intel 最後支援 8265 的官方套件。LAN 31.3 採官方 `W11` 路線，I219 12.19.2.64、I210 14.1.28.0；不得因 NDIS68 版號較大就選錯 OS。最低系統為官方套件與 INF 裝飾的交集，LAN 至少 Windows 11 build 22000。
- MEI A13A 對應 `TEE_DDI_x64_LEGACY.Components`：父裝置 2220.3.1.0；DAL 1.41.2021.0121、ICLS 1.64.1234.0、WMI 2219.3.0.0。先預加入三個 SWC INF，再安裝父裝置、重新枚舉並逐個讀回；父裝置存在時，初始沒看到孩子不算成功略過。此安裝 section 不要求 ES_ONLY。保留完整 INF 依賴，不執行 SetupME 或韌體更新程式。
- AMD GPU 31.0.21001.46001 與 HDMI 音效 10.0.1.27 分開。GPU 必要 SWC：`SWC\VID1002&PID0001`（31.2310.0.0）、`SWC\AMDOCL-23.10`、`SWC\AMDWIN-23.10`（後兩者 31.0.21001.46001）。`amdfendr` 是 System／`ROOT\AMDLOG` 23.10.0.6，不是 Extension；已有才更新，不建立 ROOT 裝置。`SWC\AMDFDANS-1.0.0` 1.0.2310.1 也是已有才處理。
- AMD 真正 Extension 是 `amdwddme.inf`，ExtensionId `{07A2A561-D001-4503-B239-EF2FE0379EFB}`；必須核對該版本、provider、ID 與目前 GPU 的 active 關聯，不能只看已進 Driver Store。官方 [驅動盤點](https://learn.microsoft.com/en-us/windows-hardware/drivers/driversecurity/create-a-driver-inventory) 的 PnPUtil XML 可區別裝置關聯；不具備該能力時明確拒絕把 staged 當 active，無杜撰裝置屬性。此 AMD 官方套件標示 Windows 10 x64，NT10 INF 匹配與 Windows 11 執行結果不等於原廠 Windows 11 認證。
- Intel Graphics 31.0.101.2145 包含顯示、CUI／IGCC SWC 與可選音效。主機未枚舉 Intel GPU 時整包略過，不預加入孩子。`HdBusExt.inf` 的 A171 只在較舊 Models17704，Win11 選 Models18362 沒有該項；不強裝也不列缺漏。原理見 Microsoft [INF Models](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-models-section)。
- SD 控制器可能顯示泛用 SDA Standard Compliant 名稱；以 PCI 1217:8621、NUC subsystem 與原廠 INF 判斷。CIR 只有枚舉 `ACPI\ITE8704`／`ITE8708`／`ITE8713` 才處理。
- 保留較新已安裝官方驅動，不為了吻合清單而降版。不同 provider 的版本不直接作數字比較；不把 Microsoft 泛用驅動版本當 Realtek／BayHub 的較新原廠版本。

不包含 BIOS、Thunderbolt／ME 韌體更新；UCM 是 USB Type-C Power Delivery 驅動。ASUS [Hades Canyon USB Type-C 說明](https://www.asus.com/support/faq/1052592/) 與目前官方清單沒有要求另執行本包未提供的 TBT 韌體工具。完整原始 AMD 及 MEI INF 依賴樹保留，安裝器僅使用列出的 INF，不執行來源 Setup.exe。

## 來源及封存查核

ASUS [官方機型下載](https://www.asus.com/supportonly/nuc8i7hvk/helpdesk_download/)／[下載 API](https://www.asus.com/support/webapi/ProductV2/GetPDDrivers?website=uk&model=nuc8i7hvk&pdhashedid=&pdid=99999&cpu=&osid=52&siteID=www&sitelang=)；Intel [8265 Wi-Fi](https://www.intel.com/content/www/us/en/download/777192/)、[8265 藍牙](https://www.intel.com/content/www/us/en/download/774186/)、[LAN](https://www.intel.com/content/www/us/en/download/727998/)、[7–10 代顯示](https://www.intel.com/content/www/us/en/download/776137/intel-7th-10th-gen-processor-graphics-windows.html)。原始封存檔 SHA256 與有公布的原廠 digest 保存在每包 Provenance；重新包裝後 ZIP 的 SHA256 位於套件頂層。CAT 驗證未執行任何驅動／韌體安裝。
