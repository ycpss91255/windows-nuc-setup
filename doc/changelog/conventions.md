# 版本紀錄撰寫規則

- 使用繁體中文，記錄讀者可見的影響與必要操作，不複製代理對話、測試日誌或實機個資。
- 日常變更放在 `## [Unreleased]`；發布使用 `script/release/prepare_release.ps1 -Version vX.Y.Z`，將內容提升為 `## [vX.Y.Z] — YYYY-MM-DD` 並同步 `.version`。RC 使用 `vX.Y.Z-rcN`。
- 版本經 PR 與 `ci-rollup`，合併到 main 後才建立對應標籤。Prepare-Release 不提交、不推送、不建立標籤；版本標題代表已準備發布，實際發布狀態以 GitHub Release 為準。
- 依需要使用 Added（新增）、Changed（變更）、Fixed（修正）、Removed（移除）、Security（安全）分類；沒有內容的分類省略。
- 正式版包含同版本 RC 的紀錄；不要重寫已發布版本或移動舊標籤。舊 v0.1.x 的歷史標題保留。
- 破壞相容性時明確標示 BREAKING，說明受影響範圍與遷移步驟。
- 測試方式與限制放 README；實際結果放中文 Git 提交、Actions 或 Release，不維護容易過時的手動測試總數。
- 歷史很大時才按版本系列拆檔並維護索引。第三方原始碼的 changelog 保持上游原狀。
- 未來 Release 與版本紀錄以讀者能理解的變更與操作為主；原始發布證明與 CI 脈絡保留在報表及 Actions。既有歷史不重寫。
