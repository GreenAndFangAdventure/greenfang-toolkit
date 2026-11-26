# GF-009-12／13 找物品目錄：資料來源與散布條件

## 來源

| 項目 | 內容 |
|---|---|
| 資料 | 魔獸世界用戶端的 DB2 資料表 `Item` 與 `ItemSparse`（繁中 zhTW） |
| 版本 | Forever 用戶端，product `wowf`，build **1.60.1.71139**（本機 `.build.info`） |
| 取得方式 | wago.tools 的 DB2 CSV 匯出（https://wago.tools/db2/Item 、https://wago.tools/db2/ItemSparse ，locale zhTW），claude-pm 用瀏覽器下載（GF-009-12） |
| 檔案 sha256 | `Item.1.60.1.71139.csv` 0f3a75bdd765a2138181e771f68a93be8a0f5124468164c40615b1e664582744；`ItemSparse.1.60.1.71139.zhTW.csv` b91911460f99c6fe3a47f2d872af0d7c95e775f9aa6435efd5e40e07f1c21c91 |
| 用到的欄位 | Item：ID、ClassID、SubclassID、IconFileDataID。ItemSparse：ID、Display_lang（名稱）、Bonding、OverallQualityID、ItemLevel |
| 產生器 | `scripts/build_item_catalog.py`（只用標準函式庫，用 `python -I` 跑）。匯出檔不進 repo |
| 產出 | `addon/GreenFangToolkit/SupplyCatalogData.lua`（公會版）、`addon/GreenFangToolkit_Dev/CatalogScanData.lua`（開發版，不在公會發布包裡） |

## 權利與散布條件

- 物品名稱、分類、圖示編號是 **Blizzard Entertainment 的遊戲資料**，不是我們寫的。wago.tools 是第三方網站，只是把用戶端資料表整理成可下載的格式，和 Blizzard 沒有關係。
- AddOn 的 MIT 授權（`LICENSE`、TOC 的 `X-License`）只涵蓋我們自己的程式碼，**不涵蓋這份資料**。產生的資料檔檔頭有寫明這一點。
- 我們的做法：
  - 資料只放在免費的 AddOn 裡面，用途是讓 AddOn 能用名稱找物品；
  - 不單獨提供、不拿去賣、不放在要付費才能用的地方；
  - 資料檔是一般看得懂的文字，沒有加密或混淆。

  這是依照 Blizzard「UI Add-On Development Policy」的要求：AddOn 要免費，程式碼不能混淆。許多 AddOn 也都內建遊戲資料。
- **待確認**（不是法律意見）：
  - wago.tools 自己的使用條款這邊沒辦法離線查證，請 claude-pm 或會長看一下網站上的說明；
  - 如果 Blizzard 或 wago.tools 要求移除，見下面的「移除」。

## 移除

- 只拿掉資料：把 `SupplyCatalogData.lua` 從 TOC 拿掉。「找物品 → 全部」會回到沒有目錄的樣子，背包、連結、物品編號、拖曳照樣能用（有測試）。
- 整個退回：`git revert` GF-009-12 和 GF-009-13 的 commit。

## SavedVariables

- 公會版不再寫 `GreenFangToolkitDB.devCatalogScan`。開發版的掃描結果在自己的 `GreenFangToolkitDevDB`（檔案 `GreenFangToolkit_Dev.lua`）。
- GF Sync 只讀 `GreenFangToolkit.lua`，所以 SavedVariables 契約不用改。
- 0.16.3 如果有人跑過舊的 `/gftk catalogscan`，存檔裡會留下一個 `devCatalogScan` 鍵。新版不讀也不刪它：GF Sync 本來就會略過不認得的欄位。
