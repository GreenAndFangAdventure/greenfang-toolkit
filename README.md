# 綠皮冒險工具箱（GreenFangToolkit）

綠皮與獠牙冒險事務所的公會外掛，給 **World of Warcraft: Forever**（Interface 16001）使用。

- 公會名冊：等級、職業、專業、所在地，可以排序、匯出
- 配方查詢：公會裡誰會做什麼
- 部落「舒適的睡袋」任務路線助手
- 公會成員之間在遊戲裡自動分享資料。下線後可以由 [GF Sync](https://github.com/GreenAndFangAdventure/gf-sync) 把資料送到[公會網站](https://green-and-fang-site.pages.dev)

外掛本身**不連網路**，只寫自己的 SavedVariables（`GreenFangToolkitDB`）。

## 安裝

任選一種：

- **CurseForge**：搜尋「綠皮冒險工具箱」，遊戲版本選 Forever
- **公會網站**：下載 `GreenFangToolkit-<版本>.zip`，或安裝 GF Sync 讓它幫你安裝和更新
- **手動**：從 [Releases](https://github.com/GreenAndFangAdventure/greenfang-toolkit/releases) 下載 zip，解壓到 `World of Warcraft\_forever_\Interface\AddOns\`

在遊戲裡按小地圖按鈕，或輸入 `/gftk`（也可以用 `/綠皮`）打開。不需要任何設定。

> 裝了工具箱，就代表同意和公會裡也裝了工具箱的人分享你的等級、職業、專業、配方和所在地，而且這些資料可能經由 GF Sync 送到公會網站。不想分享的話，請不要安裝。

更新記錄見 [CHANGELOG.md](CHANGELOG.md)。

## 開發

```
python -m pip install lupa
python tests/addon/run_lupa.py
```

- 測試在 Lua 5.1（lupa）裡跑，搭配 `tests/addon/mock.lua` 模擬遊戲 API。要在遊戲裡手動確認的項目在 `tests/addon/MANUAL.md`
- 資料格式：`docs/contracts/savedvariables.md`（SavedVariables）、`docs/contracts/upload-api.md`（網站上傳 API）、`docs/contracts/addon-manifest.md`（版本 manifest）
- 發布流程：
  1. 改 TOC 的 `## Version:`，在 `CHANGELOG.md` 加這一版的說明
  2. 推 tag `v<版本>`，`.github/workflows/release.yml` 會跑測試和檢查，然後打包、建立 GitHub Release 草稿
  3. 確認後發布草稿
- 本機試建：`python scripts/build_release.py --out dist`
- 發布前的外洩掃描：`python scripts/release_checks.py scan`

## 授權

MIT，見 [LICENSE](LICENSE)。外掛只引用遊戲內建的圖示和材質，沒有附帶任何圖檔或字型。
