# 合約：AddOn 版本 manifest（`addon-manifest.json`）

- 版本：schema 1（2026-11-20 claude-addon，GF-001-D16；依據 D-017、`docs/research/distribution.md` §3、§6）
- 產生者：GitHub Actions `release.yml`（`scripts/build_release.py`），**每次發布一份**，是 GitHub Release 的附件
- 讀取者：
  - 公會網站：下載頁顯示版本、下載連結和 SHA-256
  - GF Sync：檢查新版、下載、核對、安裝自己裝的那一份（D-017 第 4 點）
- 異動：
  - schema 1（2026-11-20）：第一版

## 1. 在哪裡

| 用途 | 網址 |
|---|---|
| 最新正式版 | `https://github.com/GreenAndFangAdventure/greenfang-toolkit/releases/latest/download/addon-manifest.json` |
| 指定版本 | `https://github.com/GreenAndFangAdventure/greenfang-toolkit/releases/download/<tag>/addon-manifest.json` |

- `latest` 只指向**已發布的正式版**。草稿和 pre-release（beta、alpha）不算，所以 GF Sync 和網站不會拿到測試版。
- 網站可以自己存一份副本（由 GearBot 決定）。內容必須和 GitHub 上的檔案**逐位元相同**，不可以改寫。
- 只能用 HTTPS 讀取。GitHub 會轉址到 `objects.githubusercontent.com`，讀取的一方要允許這個轉址。

## 2. 欄位

```json
{
  "schema": 1,
  "addon": "GreenFangToolkit",
  "displayName": "綠皮冒險工具箱",
  "version": "0.10.0",
  "tag": "v0.10.0",
  "channel": "release",
  "interface": 16001,
  "released": "2026-11-20T00:00:00Z",
  "url": "https://github.com/GreenAndFangAdventure/greenfang-toolkit/releases/download/v0.10.0/GreenFangToolkit-0.10.0.zip",
  "sha256": "<64 個小寫十六進位字元>",
  "size": 86042,
  "minGFSync": "<GF Sync 版本>",
  "savedVariablesSchema": 2,
  "changelog": "https://github.com/GreenAndFangAdventure/greenfang-toolkit/releases/tag/v0.10.0",
  "curseforge": { "projectId": 123456 },
  "files": {
    "GreenFangToolkit/CHANGELOG.md": "<sha256>",
    "GreenFangToolkit/Core.lua": "<sha256>",
    "GreenFangToolkit/GreenFangToolkit.toc": "<sha256>"
  }
}
```

| 欄位 | 型別 | 說明 |
|---|---|---|
| `schema` | 整數 | 這份合約的版本，目前是 `1`。讀取者看到不認得的**更大**版本：網站照樣顯示 `version` 和 `url`；GF Sync 不自動更新，只提醒「有新版」 |
| `addon` | 字串 | 固定 `GreenFangToolkit`，也是 zip 裡唯一的資料夾名稱 |
| `displayName` | 字串 | 玩家看到的名稱，取自 TOC 的 `Title` |
| `version` | 字串 | `x.y.z`，和 TOC 的 `## Version:` 相同。比大小時三段都當整數比 |
| `tag` | 字串 | git tag，例如 `v0.10.0`、`v0.10.0-beta1` |
| `channel` | 字串 | `release`、`beta` 或 `alpha`（從 tag 判斷）。GF Sync 只自動安裝 `release` |
| `interface` | 整數 | TOC 的 `Interface`，Forever 是 `16001` |
| `released` | 字串 | 建置時間，ISO 8601 UTC |
| `url` | 字串 | zip 的下載網址（GitHub Release 附件） |
| `sha256` | 字串 | zip 的 SHA-256。**下載後一定要核對**，不符就不安裝也不提供下載 |
| `size` | 整數 | zip 的位元組數 |
| `minGFSync` | 字串或 `null` | 這一版 AddOn 寫的 outbox 需要哪一版以上的 GF Sync 才能完整上傳。`release` 一定有值（CI 會檢查）；`beta`、`alpha` 可以是 `null` |
| `savedVariablesSchema` | 整數 | `GreenFangToolkitDB.schemaVersion`（savedvariables.md） |
| `changelog` | 字串 | 給玩家看的更新說明頁 |
| `curseforge` | 物件或 `null` | 有 CurseForge 專案時是 `{ "projectId": 整數 }`，之後可能加 `fileId` |
| `files` | 物件 | zip 裡每個檔案的路徑和 SHA-256，路徑一律以 `GreenFangToolkit/` 開頭、用 `/` 分隔 |

- 讀取者必須**忽略不認得的欄位**。新增欄位不會改 `schema`；只有改變既有欄位的意義或移除欄位時，才會改 `schema`。
- 檔案編碼 UTF-8，沒有 BOM。

## 3. zip 的格式

- 檔名 `GreenFangToolkit-<version>.zip`。
- 根目錄只有一個資料夾 `GreenFangToolkit/`，裡面有 TOC、`.lua`、`LICENSE`、`CHANGELOG.md`。
- CurseForge、網站下載、GF Sync、手動安裝都用**同一個檔案**。
- 解壓到 `<WoW>\_forever_\Interface\AddOns\` 就是安裝好了。

## 4. 給 GF Sync（D-017 第 4 點）

- 只更新**自己安裝的那一份**：
  - 安裝記錄放在 AddOn 資料夾**外面**（例如 `%LOCALAPPDATA%\GFSync\addon-install.json`），內容包括版本、安裝時間和當時的 `files`
  - 更新前比對資料夾裡每個檔案的 SHA-256：
    - 和記錄完全相同：可以更新
    - 不同、多了或少了檔案：別人（CurseForge app 或玩家自己）裝過或改過。刪掉記錄，以後只提醒
- 只在遊戲沒有執行時更新。做法：
  1. 解壓到暫存資料夾，用 `files` 逐一核對
  2. 備份舊的資料夾
  3. 換上新的；失敗就還原
- 只動 `Interface\AddOns\GreenFangToolkit\`。**絕不碰** `WTF\`，也不碰其他外掛（包括 `GFGuildRoster`）。
- `channel` 不是 `release` 的不自動安裝。`schema` 比 1 大的只提醒。
- `minGFSync` 比自己的版本新時：先提醒玩家更新 GF Sync（GF Sync 自己的更新流程，D-017 第 5 點），不要只更新 AddOn。

## 5. 給網站

- 下載頁顯示 `displayName`、`version`、`released`，並提供 `url` 和 `sha256`（讓玩家核對）、`changelog` 連結。
- 下載頁的「安裝說明」照 zip 格式寫（§3）。
- 有 `curseforge` 時，可以另外放 CurseForge 專案頁的連結。
