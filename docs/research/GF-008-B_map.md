# GF-008-B 睡袋指南：地圖標記的做法

日期：2026-11-26。狀態：**離線研究，未在 Forever 上確認**。要確認的部分用 `/gftk probe` 記錄（見最後一節）。

## 問題

owner：「睡袋指南先只有一般模式就好，能否給地圖然後有標記位置呢?」
限制：只用遊戲內建的暴雪美術、不打包圖片或函式庫；短標籤 2–4 字；文字至少 16 px。

## 這個客戶端可能有什麼

Forever 是 Classic 時代的內容跑在新版客戶端引擎上（toc Interface 16001）。新版客戶端（含 Classic Era 1.13 之後）的地圖是 Blizzard_MapCanvas 那一套，而不是 1.12 的舊 WorldMapFrame。依目前已知的 Classic Era API（**全部待 Forever 確認**）：

| API | Classic Era 一般情況 | 用途 |
|---|---|---|
| `C_Map.GetMapInfo(uiMapID)` | 有 | 用 ID 查區域名稱，檢查資料裡的 mapID 對不對 |
| `C_Map.GetMapChildrenInfo(id, type, all)` | 有 | ID 不對時，用區域名稱（中文或英文）找 |
| `C_Map.GetBestMapForUnit("player")` | 有 | 玩家現在所在的地圖（這次沒用到，只記錄） |
| `WorldMapFrame:GetCanvas()`、`:SetMapID()`、`:GetMapID()` | 有（MapCanvasMixin） | 在地圖畫布上放自己的小框架 |
| `OpenWorldMap(id)`／`ToggleWorldMap()` | 有 | 打開世界地圖 |
| `C_Map.SetUserWaypoint`、`UiMapPoint.CreateFromCoordinates` | 不確定：正式服有，Classic Era 客戶端有這個函式但沒有放路標的介面 | 備案 |
| `C_SuperTrack.SetSuperTrackedUserWaypoint` | 不確定 | 讓路標在畫面上追蹤 |
| `C_Map.GetMapArtLayerTextures` | 有 | 取地圖圖塊（方案 c 才需要） |

Classic Era 的區域 uiMapID（資料裡用的）：貧瘠之地 1413、荊棘谷 1434、西部荒野 1436、石爪山脈 1442、洛克莫丹 1432、希爾斯布萊德丘陵 1424；大陸 卡林多 1414、東部王國 1415、艾澤拉斯 947。

## 三個方案

**a. 在暴雪世界地圖上放自己的標記（選這個）**
- 在 `WorldMapFrame:GetCanvas()` 底下放一個小框架，用畫布的寬高乘上 x/100、y/100 定位；只在地圖顯示那一區時出現。
- 美術：遊戲內建的任務驚嘆號 `Interface\GossipFrame\AvailableQuestIcon`，Classic 一直都有。
- 好處：Classic Era 的地圖畫布一定有，不需要函式庫；不動玩家自己的路標。
- 風險：地圖縮放時標記跟著畫布縮放（Classic 地圖通常不縮放）；用 `hooksecurefunc` 跟著換區，不改暴雪函式本身。

**b. `C_Map.SetUserWaypoint` 路標（只當備案）**
- 只有在沒有畫布時才用；會蓋掉玩家自己設的路標，而且 Classic 客戶端可能沒有顯示路標的介面，所以不當主要做法。

**c. 頁面裡自己畫區域小地圖（不做）**
- 要用 `C_Map.GetMapArtLayerTextures` 拼圖塊，每區十幾張貼圖，尺寸與偏移要逐區對；Classic 客戶端回傳格式不確定，工作量大、風險高。

## 實作（SleepingBagMap.lua）

- 「看地圖」（3 字）按鈕只在這一步有 x、y，而且客戶端有畫布或路標時出現；戰鬥中不亮（戰鬥中不能開地圖）。
- 地圖 ID：先用資料的 mapID，`C_Map.GetMapInfo` 的名稱要等於中文或英文區域名；不符時在艾澤拉斯、卡林多、東部王國底下用名稱找；找不到就不出現按鈕。
- 沒有 x、y 的步驟（移動步驟、座標待實地確認）：沒有按鈕、沒有標記。
- 什麼都不存、不送。

## 用 `/gftk probe` 確認

`/gftk probe` 的清單多了上表的地圖 API 與 `WorldMapFrame`，摘要最後多一段「地圖：畫布 有／無｜路標 有／無｜地圖資訊…｜所在地圖…｜做法 畫布標記／路標／沒有」。owner 在 Forever 打一次，把結果貼回來，就知道實際用哪個做法、哪些 API 沒有。

## GF-008-C 追記（owner 在 Forever 試過 0.16.5 之後）

- owner：「睡袋的每一步都應該要有地圖處，不要用驚嘆號或問號，會與實際任務搞混，換個標誌」。
- 標記改成團隊標記的星星 `Interface\TargetingFrame\UI-RaidTargetingIcon_1`（遊戲內建，任務 NPC 與交任務都不用這個圖）；客戶端沒有這個單檔時，改用同一張星星的拼圖 `Interface\TargetingFrame\UI-RaidTargetingIcons`（左上 1/4）。驚嘆號 `AvailableQuestIcon` 已拿掉。
- 每一步都有地圖：沒有固定地點的移動步驟（回卡林多、前往洛克莫丹）打開大陸地圖（卡林多 1414、東部王國 1415），不放標記，頁面寫原因。
- 指南沒有座標的步驟，改用地標的大約位置（地圖知識，不是指南）：格羅姆高營地 32, 29；烈日石居 47, 61（石爪山脈兩步都用它）；索拉丁之牆北段 20, 30（畫在阿拉希高地 1417 的地圖上）。頁面與提示都寫「大約：…」。
