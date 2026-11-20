# 契約：AddOn ↔ GF Sync（SavedVariables）

- 版本：`schemaVersion = 2`
  - 2026-11-17 claude：初版
  - **2026-11-20 claude-addon：v2 擴充（D-014）**。新 kind `member.share`、`recipe.names`；共通欄位 `capturedAtServer`；`character.self.recipes`；頂層 `share`；outbox 上限；通則 §2a。依 claude-sync 審查（`claude-sync_D-014-contract-review.md`）修正後定稿
  - **2026-11-20 claude-addon：D-015**。工具箱沒有開關了：`sync.enabled` 固定為 `true`、`sync.shareLocation` 不再使用；`withdrawn` 只剩 `recipes`（放棄專業）
  - **2026-11-20 claude-addon：GF-001-D14（AddOn 0.10.0，claude-pm 指派）**。第 4 段上線：開始寫 `member.share`、`recipe.names`、`capturedAtServer`、`character.self.recipes`，不再寫 `member.report`。outbox 上限改成依名冊人數（§2f）。`member.share` 的寫入時機和配方 ID 的分批（§member.share）。GFTKS 的目錄分桶（§遊戲內互傳）。格式（欄位、形狀）沒有改
- 依據：D-003（兩者解耦，只透過 SavedVariables 交換資料）、D-008、D-009、D-011、D-014、D-015
- 負責方：AddOn 負責寫，GF Sync 只讀。要改這份契約，必須先在 `collab/QUESTIONS.md` 提出，並同時通知 AddOn 和 GF Sync 兩邊的負責人

## 1. 名稱（發布後不可改）

| 項目 | 值 | 狀態 |
| --- | --- | --- |
| 遊戲內顯示名稱 | TOC `## Title: 綠皮冒險工具箱`（其他語系也顯示同一個名稱） | 已採納（D-005） |
| 作者／公會 | TOC `## Author: 綠皮與獠牙冒險事務所` | 已採納（D-005） |
| AddOn 資料夾（技術名稱，玩家看不到） | `GreenFangToolkit`（只用英數字，避免中文路徑在 CurseForge、解壓縮、Windows 編碼上出問題） | 已採納（D-005） |
| 帳號層級 SavedVariables | `GreenFangToolkitDB` → 檔案 `WTF/Account/<帳號>/SavedVariables/GreenFangToolkit.lua` | 已採納（D-005） |
| 斜線指令 | `/gftk`、`/綠皮`（0.9.0 起；`/gf` 拿掉，因為 GuildForge 也用） | 已採納（D-005、D-014） |
| 舊資料遷移 | 第一次載入時若偵測到 `GFGuildRosterDB`，把設定與最後一份快照搬進新表；舊表保持原樣，不刪除 | GF-000 |

GF Sync 會掃描 `<WoW>/_forever_/WTF/Account/*/SavedVariables/GreenFangToolkit.lua`。有多個帳號資料夾時，每個檔案各自處理。

## 2. 結構

```lua
GreenFangToolkitDB = {
  schema = "gf.toolkit",
  schemaVersion = 2,
  addonVersion = "0.10.0",
  settings = { ... },            -- 介面設定，GF Sync 忽略
  sync = {
    enabled = true,              -- 0.9.1 起固定為 true（D-015：裝了工具箱就會同步，沒有開關）；舊存檔的 false 在載入時改回 true
    noticeShown = true,          -- 第一次說明顯示過了沒
    noticeVersion = 4,           -- 說明的版本；說明加了新內容時會再顯示一次（2 = 提到所在地，0.7.0；3 = 提到分享給公會成員，0.8.0；4 = D-015 的新說明，0.9.1）
    -- shareLocation：0.9.1 起不再使用（D-015：所在地一律分享）；舊存檔的值在載入時清除。GF Sync 本來就不讀
    outbox = { <entry>, ... },   -- 待上傳的資料，上限見 §2f
  },
  peers = { ["測試乙-測試伺服器"] = { ... } },  -- 0.8.0 起：公會成員的資料，給名冊畫面用；GF Sync 忽略
  share = { ... },               -- 0.9.0 起：遊戲內分享的記錄（GFTKS 協定，docs/research/share-design-d014.md）；GF Sync 忽略
}
```

### 2a. 通則（每一種 kind 都適用）

1. **每一筆 entry 都要有共通欄位**：`id`、`kind`、`capturedAt`（數字）、`game`、`uploader`、`payload`。0.9.0 起再加 `capturedAtServer`。沒有共通欄位的 entry，GF Sync 當成格式錯誤丟掉。
2. **entry 的內容改變時，一定要換新的 `id`。** GF Sync 用 `id` 判斷「已經回覆過」，同一個 `id` 不會再送。合併、改寫、重寫都算改變，`recipe.names` 合併時也一樣。
3. **空的表格不要寫那個鍵。** Lua 的空表格轉 JSON 時會變成 `[]`，不是 `{}`。例如沒有配方就不寫 `recipes`，沒有撤回就不寫 `withdrawn`。
4. 以 skillLineID、配方 ID 為鍵的表格，一律用**字串**鍵（`["171"]`），不用數字鍵。
5. 每個欄位都可能缺少；缺少代表「沒有提供」，不代表「空的」。

### 2b. entry 共通欄位

```lua
{
  id = "Player-1234-ABCDEF01:1763370000:character.self",  -- 掃描者GUID:capturedAt:kind，全域唯一
  kind = "character.self" | "roster.snapshot" | "member.report" | "member.share" | "recipe.names",
  capturedAt = 1763370000,        -- Unix 秒，遊戲客戶端的 time()
  capturedAtServer = 1763370004,  -- 0.9.0 起：GetServerTime()。網站比新舊、檢查「未來」時優先用這個；沒有時退回 capturedAt
  game = { world = "forever", interface = 16001, realm = "...", locale = "zhTW" },
  uploader = { guid = "...", name = "...", realm = "...", faction = "Horde", guild = "...", guildRank = "..." },
  payload = { ... },
}
```

### kind = `character.self`（可信度較高：角色本人回報）

每次登入、升級、專業變動時寫一筆。同一個角色在 outbox 裡只保留最新一筆。

```lua
payload = {
  level = 32, class = "德魯伊", classToken = "DRUID", race = "牛頭人", raceID = 6,
  professions = { { name = "製皮", skillLineID = 165, rank = 151, max = 225 }, ... },
  location = { zone = "雷霆崖", subZone = "長者高地" },   -- 0.7.0 起，見下方
  recipes = {                                              -- 0.9.x 第 4 段起；沒開過專業視窗的專業不會出現；全部沒有就不寫
    ["171"] = { recordedAt = 1763369000, hash = "3fz9q", ids = { 2329, 2330, 3170 } },  -- ids 由小到大
  },
}
```

- `recipes[*].recordedAt`：開專業視窗、讀到清單時的 `GetServerTime()`。`hash` 是 AddOn 對這份清單算的雜湊，用來判斷「內容一樣」。

**`location`（0.7.0 起，D-009）**

- 只會出現在 `character.self`、`member.report`、`member.share`（形狀不同，見各節）。`roster.snapshot` 永遠沒有這個欄位。
- `character.self` 的 `location` 代表**角色本人**寫入那一刻的位置，通常是登出時。
- `zone`：`GetZoneText()` 的結果（取不到時改用 `C_Map`），一定是非空字串。
- `subZone`：`GetSubZoneText()` 的結果；空字串或和 `zone` 相同時**省略**。
- 整個 `location` 可能不存在：客戶端取不到位置。0.9.1 起沒有「不分享所在地」的開關（D-015）。
- 欄位名稱刻意用 `location`，不叫 `zone`：GF Sync 對其他地方「移除 zone 和 online」的保護不變（§3 第 6 點）。
- 不會有在線狀態。

### kind = `roster.snapshot`（可信度較低：某位成員看到的整份公會名冊）

規則同 v0.3.1：名冊數量必須完整才寫入。同一個公會在 outbox 裡只保留最新一份。

```lua
payload = {
  total = 115,
  members = { { name = "Name-Realm", guid = "...", level = 30, classToken = "...",
                race = "...", raceID = 6, guildRank = "...",
                professions = { "採礦", "鍛造" }, professionSource = "guild" } },
}
```

**不包含 `zone` 和 `online`**（D-003）。AddOn 遊戲內的名冊畫面仍可顯示這兩項，只是不會寫進 outbox。

### kind = `member.report`（0.8.0 起，D-011；0.9.x 第 4 段起由 `member.share` 取代）

收到公會成員**本人**在遊戲內分享的資料時寫一筆，由**收到的人**的 GF Sync 上傳。**AddOn 0.10.0（第 4 段）起不再寫這種 kind**；舊存檔裡的會留在 outbox，直到被上限擠掉。GF Sync 和網站繼續接受舊的。

- `uploader`：收到的那個角色，規則和 `character.self` 一樣，必須在目標公會。
- `id`：`<uploader GUID>:<capturedAt>:member.report:<subject GUID 或名字>`，`capturedAt` 是收到並寫入的時間。
- 同一個 `subject` 在 outbox 只保留最新的一筆。
- `subject` 一定是遊戲伺服器在 `CHAT_MSG_ADDON` 標示的發送者本人，而且在收到者看到的公會名冊裡。

```lua
payload = {
  subject = { name = "測試乙-測試伺服器", realm = "測試伺服器", guid = "Player-0000-0000000B" }, -- guid 來自收到者的名冊，可能沒有
  reportedAt = 1763373590,   -- 發送者觀察到這些資料的時間（Unix 秒）
  level = 61, classToken = "WARRIOR",
  professions = { { name = "採礦", skillLineID = 186, rank = 300, max = 300 }, ... }, -- 包括烹飪、釣魚、急救
  location = { zone = "奧格瑪", subZone = "力量谷" },  -- 發送者有送所在地時才有（0.9.1 起一律送，D-015）
}
```

- `reportedAt` 比收到的時間晚超過 10 分鐘的訊息，AddOn 會丟掉。

### kind = `member.share`（0.9.x 第 4 段起，D-014；轉傳的資料）

一位成員（subject）在 outbox 只有一筆，內容是 AddOn 所知道的這位成員**每個欄位的最新值**。每個欄位各自帶「原作者觀察到這個值的伺服器時間」，網站依欄位比新舊。

```lua
{
  id = "<uploader GUID>:<capturedAt>:member.share:<subject GUID>",
  kind = "member.share",
  capturedAt = ..., capturedAtServer = ...,
  game = {...}, uploader = {...},           -- uploader 規則同 character.self，必須在目標公會
  payload = {
    subject = { guid = "Player-0000-0000000B", name = "測試乙-測試伺服器", realm = "測試伺服器" },
    level      = { value = 61, recordedAt = 1763373590, via = "author" },
    classToken = { value = "WARRIOR", recordedAt = 1763373590, via = "author" },
    professions = { recordedAt = 1763373590, via = "relay",
                    value = { { skillLineID = 186, name = "採礦", rank = 300, max = 300 }, ... } },
    location   = { recordedAt = 1763373000, via = "relay", value = { zone = "奧格瑪", subZone = "力量谷" } },
    recipes    = { ["164"] = { recordedAt = 1763300000, via = "relay", hash = "3fz9q", ids = { 2660, 2661 } },
                   ["171"] = { recordedAt = 1763390000, via = "relay", hash = "1k2ab" } },  -- 沒有 ids：只確認時間
    withdrawn  = { recipes = { ["202"] = 1763385000 } },   -- 只有放棄專業（D-015）
  },
}
```

- **欄位的形狀**：`level`、`classToken`、`professions`、`location` 都是 `{ value, recordedAt, via }`；`recipes[<skillLineID>]` 是 `{ recordedAt, via, hash, ids? }`；`withdrawn` 是數字或數字表。除此之外不會有別的鍵。
- `via`：`"author"`（上傳者直接從原作者收到）或 `"relay"`（經過其他成員轉傳）。只是參考，不影響新舊規則。
- `subject`：只有 `guid`、`name`、`realm`；`name` 必填。
- `professions.value[*]`：只有 `skillLineID`、`name`、`rank`、`max`。`name` 是**上傳者**的客戶端翻譯的，網站以 `skillLineID` 為準。
- **`location`**：`{ value = { zone, subZone }, recordedAt, via }`，`zone`、`subZone` 的規則同 `character.self`。D-015 起所在地一律分享和轉傳，沒有開關。
- **`recipes`**：
  - 那個專業的清單內容（`hash`）和這位上傳者上一次寫進 outbox 的不一樣時，才帶 `ids`。
  - 只有時間往後推時，只寫 `recordedAt`、`via`、`hash`，**不帶 `ids`**，以免每次重送約 4 KB。
- **`withdrawn`**（墓碑）：只有 `recipes[<skillLineID>]`，代表原作者在這個時間放棄了那個專業，是為了資料正確。D-015 拿掉了隱私用的撤回（關閉同步、關閉分享所在地），所以不會有 `all`、`location`。沒有撤回就不寫 `withdrawn`。
- **什麼時候寫**：只在登出（含 `/reload`）時寫，戰鬥中不寫。只寫目標公會名冊上的成員，不寫上傳者自己。
- **什麼時候重寫**（避免每次登出都重送）：只有這位成員**任何一個欄位的內容（雜湊）改變**，或**某個欄位的時間比上一次寫入時往後推超過 6 小時**，才重寫這一筆。另外每 6 小時最多一次，把「時間有往後推、內容沒變」的成員也重寫（這部分不帶 `ids`）。什麼都沒變的成員，outbox 裡原本那筆保留不動。重寫時換新的 `id`（§2a 第 2 點），舊的那筆移除。
- **配方 ID 分批**（GF-001-D14，大公會）：
  - 一次登出最多帶 **50,000 個**配方 ID（約 1 MB），記錄時間最新的清單優先。超過的清單這次只寫 `recordedAt`、`via`、`hash`（**不帶 `ids`，而且 `hash` 和網站記下的可能不一樣**），下次登出再帶。網站照 upload-api §3 第 6 點：沒有 `ids`、`hash` 不一樣就略過，等帶 `ids` 的那一筆。
  - 帶過 `ids` 的項目，到下一個 session 的登出時改寫成不帶 `ids`（新的 `id`，內容只少了 `ids`），讓 outbox 不會留著每一份清單。
  - 同一份清單（同一個 `hash`）每 30 天再帶一次 `ids`，以防有一次沒上傳到。
- 上傳者自己不會有 `member.share`，用 `character.self`。

### kind = `recipe.names`（0.9.x 第 4 段起，D-014）

配方 ID 對名稱的表。網站沒有遊戲裡的 `C_Spell`，需要它才能顯示配方名稱。

```lua
{
  id = "<uploader GUID>:<capturedAt>:recipe.names",
  kind = "recipe.names",
  capturedAt = ..., capturedAtServer = ...,
  game = {...}, uploader = {...},           -- 共通欄位全部要有（§2a 第 1 點）
  payload = { locale = "zhTW", names = { ["2660"] = "粗製磨刀石", ["2661"] = "..." } },
}
```

- 只放這台電腦還沒放過的 ID，一筆最多 500 個；outbox 裡只保留一筆。只在登出時寫。
- 合併時新的名稱優先，剩下的位置放上一筆還在 outbox 的名稱；超過 500 個時，舊的名稱可能被擠掉（已經放過，不會再放）。
- 客戶端還不知道名稱的 ID 不放（之後再放）。一次登出最多讀 60 份配方清單找新名稱。
- 有新名稱要併入時，`capturedAt` 和 `id` 都換新（§2a 第 2 點）。
- `names` 是空的就不寫這一筆。

### 2f. outbox 上限

- **0.10.0 起依名冊人數**：`member.share` 最多 `min(1200, max(150, 名冊人數))` 筆（每位成員一筆；1,200 是 GF Sync 每個檔案收的上限），總共再加 50 筆給其他 kind。
  - 115 人：`member.share` 150、總共 200（和 0.9 的數字一樣）
  - 1,000 人：`member.share` 1,000、總共 1,050
- 超過時：`member.report` 最舊的先刪，然後是最舊的 `member.share`，然後才是其他 kind 最舊的。`member.share` 超過自己的上限時，只刪最舊的 `member.share`。
- **給 GF Sync**：一台電腦第一次登出最多可能有一千多筆 `member.share`（1,000 人的公會），之後每次登出只有變動的成員換新 `id`。GF Sync 照 `id` 去重，只送新的。
- **檔案大小**（GF Sync 解析上限 32 MB、2,000,000 個 Lua 值）：AddOn 的分享資料把配方清單存成字串（一份清單是一個值），outbox 的配方 ID 每次登出最多 50,000 個，帶過的下個 session 拿掉。1,000 人離線量測的最高點約 8.2 MB、47 萬個值（每個表格、鍵、值都算），見 `docs/research/share-performance.md`。

### 遊戲內互傳訊息（不經過 GF Sync，記錄在這裡方便其他版本相容）

**`GFTK`（0.8.0 起，D-011）**

- API：`C_ChatInfo.RegisterAddonMessagePrefix("GFTK")`、`C_ChatInfo.SendAddonMessage("GFTK", msg, "GUILD")`、事件 `CHAT_MSG_ADDON`。只用 GUILD 頻道。
- 每則訊息最多 255 bytes：`"<版本>~<msgID>~<第幾段>~<共幾段>~<內容>"`。目前版本是 `1`；版本不認得就整則忽略。最多 8 段，60 秒內沒收齊就丟掉。切段時不會切斷 UTF-8 字元。
- 內容（各段依序接起來）是 `;` 分隔的 `key=value`：
  - `L` 等級，`C` classToken，`T` capturedAt
  - `P` 專業：`<skillLineID>,<rank>,<max>,<name>`，多個用 `/` 分隔
  - `Z` zone，`S` subZone：發送者取得到所在地時才有（0.9.1 起一律送，D-015）
- 值裡的 `% ; = , / ~ |` 和控制字元用 `%XX` 轉碼。不認得的 key 忽略。
- 出現 `N`、`U`、`G`、`R`、`W` 這幾個可能用來指名別人的 key，整則丟掉。
- 送出時機：登入後公會名冊載入時、技能點或等級變動時。同一個角色 5 分鐘最多送一次。0.9.0 起照樣送，讓 0.8.x 看得到；收到的會轉成 `GFTKS` 的記錄。

**`GFTKS`（0.9.0 起，D-014）**

- 自動分享和轉傳：等級、職業、專業技能點、所在地、配方。每一筆帶原作者 GUID 和原作者的伺服器時間，只保留最新的。
- 格式和流程見 `docs/research/share-design-d014.md`（I／Q／C／A／G／V／B／D／X）。
- 0.9.1 起沒有開關（D-015）：裝了工具箱就會分享和轉傳。撤回（`X`）只用在放棄專業（`R<skillLineID>`）。
- 0.9.2 起（GF-001-D12）：回答別人請求的資料用 WHISPER 送給要的人（對方的請求帶 `w2` 時），送之前在 GUILD 送一則認領 `K`；舊版照舊走 GUILD。見 `docs/research/whisper-replies.md`。
- 0.10.0 起（GF-001-D14）：
  - 目錄分桶：作者依 id 的雜湊分成 64 桶。`Q` 在總摘要後面多一個欄位 `b<64 × 3 個字元的桶摘要>`（整則仍在 250 bytes 以內）；0.10.0 只回不一樣的桶，`C` 在段數後面多一個欄位 `k<桶編號，每個 2 個 36 進位字元>`。舊版的 `Q` 沒有這個欄位，照舊回完整目錄；舊版收到新的 `Q` 只讀前三個欄位，照舊運作。
  - 記錄上限 `max(2000, 名冊人數 × 10)`，滿了先忘掉不在名冊上、最久沒聽到的作者。
  - 補資料：在線的人先、最近有變的先；每次登入最多 `max(60, 名冊 × 0.6)` 位的索引、`max(120, 名冊 × 2)` 筆資料，每 10 秒送 2 則 `A`、6 則 `G`。

## 3. GF Sync 的義務

1. **只讀，不寫**：絕不修改 SavedVariables，也絕不碰 `Interface/AddOns/`。
2. **安全解析**：只解析 Lua 的表格字面值（字串、數字、布林、巢狀表），絕不執行 Lua 程式。
3. **觸發時機**：檔案修改時間變更後，等 5 秒確認不再變動才讀。遊戲只在登出、`/reload`、斷線時寫檔。
4. **`sync.enabled ~= true` 時**整個檔案都不上傳（這條不改）。0.9.x 起 AddOn 一定寫 `true`：每次載入都寫 `true`（舊存檔的 `false` 在升級時改成 `true`，依 D-015，裝了工具箱就代表同意），登出前再寫一次。這個欄位保留是為了相容舊版 AddOn 和舊版 GF Sync。
5. **版本相容**：目前只有 `schemaVersion = 2`。`GreenFangToolkitDB` 沒有 v1 版本，舊的 `GFGuildRosterDB`（v0.3.1）沒有 outbox，GF Sync 不讀它。之後推出 v3 時，GF Sync 要能同時讀 v2 與 v3。其他版本值一律略過，並在 GF Sync 視窗顯示「請更新 GF Sync」。未知欄位與未知 kind 一律忽略（**不記成已回覆**，更新 GF Sync 之後仍然會送）。
6. **雙重保險**：上傳前，GF Sync 會再移除 entry 本身、payload 與 `payload.members[*]` 裡的 `zone`、`online`、`location`。例外：
   - `character.self`、`member.report` 的 `payload.location`：以 `{ zone, subZone }` 重建後保留（D-009、D-011）。
   - `member.share`：見第 8 點的白名單。
   - `roster.snapshot` 裡出現 `location` 一律移除；`online` 在任何地方都移除。
7. **本機去重**：已上傳的 `id` 記在 `%APPDATA%\GFSync\state.json`。伺服器端也會以 `id` 去重，所以重送是安全的。網站回 `rejected` 而且 `reason = "unknown_kind"` 時，**不記成已回覆**，24 小時後再試（upload-api §2）。
8. **`member.share` 用白名單重建 payload**（0.9.x 第 4 段起）。只保留：
   - `subject`：`name`（必填）、`realm`、`guid`，每個 64 字元以內；不合格整筆丟掉。
   - `level`、`classToken`、`professions`、`location`：每個只留 `value`、`recordedAt`（數字）、`via`。
     - `professions.value[*]` 只留 `skillLineID`、`name`、`rank`、`max`。
     - `location.value` 只留 `zone`、`subZone`（字串、60 字元以內）；`zone` 不合格就整個 `location` 不送。
   - `recipes[<skillLineID>]`：只留 `recordedAt`、`via`、`hash`、`ids`（數字陣列）。
   - `withdrawn`：只留 `recipes`（`<skillLineID>` → 數字）。其他鍵（例如舊草稿的 `all`、`location`）丟掉。
   - `via` 只接受 `"author"`、`"relay"`，其他值就拿掉這個鍵。
   - 其他鍵一律丟掉。
9. **`capturedAtServer`**：不是數字就拿掉這個欄位，不要讓整筆失敗。
10. `character.self.recipes` 和 `recipe.names` 沒有隱私欄位，原樣傳；頂層的 `zone`、`online` 仍然移除。

## 4. AddOn 的義務

- 不跳視窗。第一次載入時在聊天框顯示一行說明（告知，D-015）：「綠皮冒險工具箱會分享你的等級、職業、專業、配方和所在地給公會內有裝工具箱的人，並可能由他們上傳到公會網站。」已經看過舊版說明的玩家，升級後會再看到一次新版說明（`noticeVersion`）。給玩家看的文字不要求輸入指令；確切文字以 `Sync.NOTICE` 為準。
- **沒有開關**（D-015）：裝了工具箱就代表同意分享、轉傳和上傳。不想分享的成員不要安裝工具箱。GF Sync 本身可以暫停或解除安裝。
- 同步狀態（待上傳筆數等）在「同步與診斷」視窗看得到（D-014 第 6 點），不能只靠指令。
- 分享和轉傳不能影響遊戲：維持頻率限制，戰鬥中和副本裡不送，訊息分散送出。
- 上傳只在登出時寫入（D-011 第 1 點）。0.8.2 起沒有「同步到網站」按鈕（D-012）。
- 戰鬥中不掃描、不寫入。
- outbox 有大小上限（§2f），避免 SavedVariables 一直變大、拖慢載入。
- 遵守 §2a 的通則：共通欄位、內容改變就換 `id`、空表格不寫鍵、字串鍵。
