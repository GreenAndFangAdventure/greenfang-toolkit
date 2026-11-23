# 契約：GF Sync ↔ 網站上傳 API（v1.5）

- 版本：
  - v1（2026-11-17 claude-pm 依 Q-005 與實作結果定稿）
  - **v1.1（2026-11-20 claude-addon，D-014）**：新 kind `member.share`、`recipe.names`、`character.self.recipes`、`capturedAtServer`、`reason: "unknown_kind"`、撤回、上線順序。依 claude-sync 審查修正後定稿
  - **v1.1（2026-11-20 claude-addon，D-015）**：`withdrawn` 只剩 `recipes`（放棄專業）；工具箱沒有同步開關
  - **v1.1（2026-11-20 claude-addon，GF-001-D14，AddOn 0.10.0）**：格式不變。補充：大公會時的筆數、配方 `ids` 分批（§2「數量」、§3 第 6 點）
  - **v1.2（2026-11-20 claude-addon，GF-001-D17，claude-pm 指派）**：新增以下四項，都是新增，舊的用戶端照舊能用：
    - HTTP 426 `client_too_old`（§2a）
    - 單筆 `reason: "addon_too_old"`（§2 的 reason 表）
    - 請求層級的 `client.addonVersion`（§2）
    - GF Sync 的更新清單端點 `GET /api/sync/gfsync-manifest.json`（§7）

    依據：GF Sync 的 `docs/UPDATE_MANIFEST.md` §2
  - **v1.3（2026-11-22 claude-addon，GF-001-D24，AddOn 0.9.8／0.10.0；與 GearBot 議定）**：新增選填欄位 `uploader.fullName`（每一種 kind）與 `member.share`／`member.report` 的 `payload.subject.fullName`：角色全名「名字 姓氏」，和網站名冊（Blizzard API）的寫法一樣。用來修正 `character_not_in_roster`（§3 第 2、6 點）。格式其餘不變
  - **v1.5（2026-11-23 claude-pm，GF-002-B，AddOn 0.12.0）**：`character.self`、`member.share` 的 payload 多一個選填欄位 `adventure`（冒險單、職工單、動作；savedvariables §adventure）。網站規則見 §3 第 11 點。不是新的 kind
  - **v1.4a（2026-11-23 claude-pm，GearBot 與審查的回饋）**：`j` 每位工匠一份；決勝規則；新增 `w.returnedAt`、`j.statusAt`
  - **v1.4（2026-11-23 claude-pm，GF-006-B，AddOn 0.11.0）**：`character.self` 和 `member.share` 的 payload 多一個選填欄位 `crafting`（製作服務與訂單，格式見 savedvariables §crafting）。網站的處理規則見 §3 第 10 點，上線順序見 §5。不是新的 kind，舊的用戶端照舊能用
- 實作位置：網站 repo `green-and-fang-site`，位於 `functions/api/sync/*`（D-002）。PR 送到 `dev`
- 資料表一律用 `migrations/00xx_*.sql` 建立，不在執行時用 `CREATE TABLE IF NOT EXISTS` 建表

## 1. 裝置配對（只需做一次，給玩家的步驟要簡單）

流程類似電視登入：GF Sync 顯示一組短碼，並自動開啟瀏覽器。玩家用 Discord 登入網站後按「允許」，配對就完成了。

| 端點 | 說明 |
| --- | --- |
| `POST /api/sync/device/start` | 請求 `{label, clientVersion}`：`label` 是電腦名稱，會顯示在配對頁上。回傳 `{deviceCode, userCode, verifyUrl, interval, expiresIn}`；GF Sync 太舊時回 426（§2a）。`userCode` 是 8 碼，10 分鐘內有效。`verifyUrl` 必須和 API 同一個 scheme 與 host，否則用戶端會改開 `<base>/pages/sync-pair?code=<userCode>` |
| `GET /pages/sync-pair?code=XXXX` | 網站頁面：需要 Discord 登入，按「允許這台電腦同步」 |
| `POST /api/sync/device/poll` | `{deviceCode}` → 還沒核准：200 `{pending:true, interval}`；核准：200 `{token, deviceId}`，token 只回傳這一次；被拒絕：403 `{error:'denied'}`；過期或無效：4xx；太頻繁：429，附 `Retry-After` |
| `GET /pages/sync-devices` | 玩家查看自己配對過的裝置，可以撤銷 |

- token：32 bytes 隨機值。伺服器只存 SHA-256 雜湊；GF Sync 用 Windows DPAPI 加密保存在本機。
- 資料表 `sync_devices(id, discord_user_id, token_hash, label, created_at, last_seen_at, revoked_at)`。

## 2. 上傳

`POST /api/sync/upload`，Header `Authorization: Bearer <token>`

```json
{ "client": { "name": "GFSync", "version": "0.2.0", "addonVersion": "0.10.0" },
  "items": [ <SavedVariables outbox entry，原樣轉成 JSON（member.share 由 GF Sync 白名單重建）> ] }
```

- `client.version`：GF Sync 的版本，網站用它判斷 426（§2a）。
- **`client.addonVersion`**（v1.2，可選）：寫出這一批資料的工具箱版本。
  - 來源：GF Sync 從 SavedVariables 最上層的 `addonVersion`（`GreenFangToolkitDB.addonVersion`，savedvariables §1）**原樣複製**，不做任何轉換。
  - **一次請求只放同一個 SavedVariables 檔案的資料**。同一台電腦有多個帳號（多個 `WTF/Account/*`）時，每個檔案的 `addonVersion` 可能不同，GF Sync 要分開送。
  - 網站用它判斷單筆的 `addon_too_old`（下面的 reason 表）。比較規則同 §2a。
  - 沒有這個欄位（舊版 GF Sync），或版本看不懂（例如開發版的 `"dev"`）時，網站**不要**回 `addon_too_old`，當成可以接受。
  - 工具箱不需要改：`addonVersion` 一直都在 SavedVariables 裡，outbox 的每一筆不帶版本。

- 單次上限：1MB、50 筆。每台裝置每小時最多 60 次。
- **數量**（AddOn 0.10.0）：1,000 人的公會，一台電腦第一次可能有一千多筆 `member.share`（約 20 批），之後每次登出只有變動的成員。一次登出的 `member.share` 合計最多帶 50,000 個配方 ID（約 1 MB 的 JSON 以內），其餘的清單分到之後的登出。
- 回應：`{ "results": [ { "id": "...", "status": "accepted" | "duplicate" | "rejected", "reason": "...", "skipped": 0, "fields": { ... } } ] }`
  - `skipped` 只會出現在 `roster.snapshot`，表示名冊裡找不到而被略過的成員人數。
  - `fields`（可選）只會出現在 `member.share`，例如 `{ "level": "accepted", "location": "older" }`，方便除錯。
- `reason` 的值：

  | reason | 意思 | GF Sync 怎麼做 |
  |---|---|---|
  | `wrong_world`、`wrong_guild`、`wrong_realm` | 驗證失敗（§3 第 1 點） | 記成已回覆，不再送 |
  | `unknown_subject` | `member.share` 的 subject 在網站名冊找不到 | 記成已回覆 |
  | `future` | 時間比伺服器晚 10 分鐘以上 | 記成已回覆 |
  | **`unknown_kind`** | 網站還不認得這種 kind（例如舊版網站收到 `member.share`） | **不記成已回覆**，24 小時後再試 |
  | **`addon_too_old`**（v1.2） | 寫出這筆資料的工具箱版本（`client.addonVersion`）比網站接受的最低版本舊 | **不記成已回覆**，24 小時後再試（和 `unknown_kind` 一樣），並提示玩家更新工具箱 |
  | 其他 | 格式錯誤等 | 記成已回覆 |

  - `unknown_kind` 和 `addon_too_old` 都是「暫時不收」：網站**不要記住**這些 id 的狀態，之後同一個 id 送來時要能照一般規則接受（不是回 `duplicate`）。
  - `addon_too_old` 是單筆的結果，HTTP 狀態照樣是 200。同一批裡可以有的被接受、有的回 `addon_too_old`（例如網站只擋某些 kind）。
  - v0.1.0 的 GF Sync 不認得 `addon_too_old`，會把那一筆記成已回覆、不再送。太舊的工具箱寫的資料丟掉是可以接受的；這和 GF Sync 本身太舊不同，後者一定要用 426（§2a）。

- 錯誤碼：
  - 401／403：token 無效或已撤銷。用戶端要刪掉 token，並提示重新配對
  - 426：GF Sync 太舊（§2a）
  - 429：超過頻率上限，附 `Retry-After`（秒）
  - 400／413：整批內容有問題或太大。用戶端可以拆半重送，單筆仍失敗就不再重送
- `results` 裡沒有列出的 id，用戶端之後可以重送，伺服器會回 `duplicate`
- Lua 的空表格 `{}` 轉成 JSON 時是空陣列 `[]`。AddOn 依 savedvariables §2a 不寫空表格的鍵，網站收到 `[]` 時也要當成「空」處理，不要回錯誤
- **冪等**：同一個 `id` 第二次送來時回 `duplicate`，不會重複寫入，所以 GF Sync 可以放心重試。內容改變時 AddOn 一定會換 `id`（savedvariables §2a 第 2 點）

## 2a. GF Sync 太舊：HTTP 426 `client_too_old`（v1.2）

網站要停止接受某個版本以下的 GF Sync 時，**只能回 426**，不能用其他狀態碼。

**為什麼只能用 426：** v0.1.0 已經在玩家電腦上，行為改不了。它遇到各種回應時會這樣處理：

| 網站回應 | v0.1.0 會怎樣 |
|---|---|
| 400、413 | 把一批切半重送，切到 1 筆還失敗就把那筆記成已回覆，**資料不見** |
| 200 加 `rejected` | 記成已回覆，**資料不見** |
| 401、403 | **刪掉配對 token**，要求玩家重新配對 |
| **426** | 當成伺服器錯誤，退避之後重試，**資料留在電腦上** |

**適用的端點：**

| 端點 | 判斷用的版本 |
|---|---|
| `POST /api/sync/upload` | body 的 `client.version` |
| `POST /api/sync/device/start` | body 的 `clientVersion` |

- **`POST /api/sync/device/poll` 絕不回 426**：舊版會把它當成配對失敗，顯示錯的訊息。擋住 start 就夠了，沒有 start 就不會有 poll。
- 版本比較：`x.y.z` 三段都當整數比；`x.y.z-標籤` 比 `x.y.z` 舊（`0.2.0-beta1` < `0.2.0`）。
- 沒有版本，或版本看不懂時，**不要擋**，當成可以接受。

**回應：**

```http
HTTP/1.1 426 Upgrade Required
Content-Type: application/json; charset=utf-8

{"error":"client_too_old","minVersion":"0.2.0","download":"https://<網站網域>/pages/sync"}
```

| 欄位 | 說明 |
|---|---|
| `error` | 固定 `"client_too_old"` |
| `minVersion` | 網站接受的最低 GF Sync 版本，`x.y.z` |
| `download` | GF Sync 的下載頁。**必須和 API 同一個 scheme 與 host**，否則 GF Sync 改開 GitHub 的 Release 頁。路徑由網站決定 |

- 426 不在 `results` 裡，整批都沒有處理。網站不要記住這一批的任何 id。
- 網站可以不把 426 算進每小時 60 次的上限。
- 新版 GF Sync 遇到 426 時：
  - 不把任何一筆記成已回覆，停止上傳 6 小時
  - 提示玩家更新，並立刻檢查更新
  - 配對時遇到 426 也一樣，不開瀏覽器
- 上線方式：
  1. 先只**記錄**會被擋的版本，不擋，觀察一段時間
  2. 確認大家都更新之後，才開始回 426
  3. 上線順序照舊：網站 → GF Sync → AddOn（§5）

## 3. 伺服器驗證（上傳內容一律視為「待查證」）

1. `game.world == "forever"`，`uploader.guild` 必須完全等於「綠皮與獠牙冒險事務所」，`realm` 必須和網站名冊的伺服器一致，否則回 `rejected`。**每一種 kind 都要有共通欄位**（`capturedAt`、`game`、`uploader`），`recipe.names` 也一樣。
2. `character.self`：角色名稱必須和 Blizzard 名冊**完全一致且唯一**。
   - **比對上傳者（v1.3，每一種 kind）**：先用 `uploader.guid`；沒有對到時用 `uploader.fullName`（「名字 姓氏」，中間是一般空白 U+0020，和名冊完全一致），最後才用 `uploader.name`。`uploader.name` 是遊戲 `UnitName` 的名字部分，**沒有姓氏**，單獨比對會對不到有姓氏的角色。
   - `fullName` 只在 AddOn 用 GUID 在遊戲內公會名冊找到時才有，找不到就沒有這個欄位（不猜）。沒有這個欄位時照舊用 `name`。
   - 網站部署這個比對之前收到的 `fullName` 會被忽略，上傳照樣失敗，這是預期的。可以補上 AddOn 才有的欄位（例如 Blizzard API 沒收錄的專業），但依照既有 `forever-roster.js` 的規則，**不能覆蓋較新的值或人工鎖定的欄位**。
   - `recipes[<skillLineID>]`（0.9.x 第 4 段起）：依每個專業的 `recordedAt` 比新舊。
3. `roster.snapshot`：優先序最低，只用來填補缺漏，不覆蓋 API 資料或 `character.self` 的資料。
4. **時間**：`capturedAtServer` 有數字時用它，沒有時用 `capturedAt`，不能比伺服器時間晚超過 10 分鐘，也就是不接受「未來」的資料。`member.share` 的欄位 `recordedAt` 比伺服器時間晚 10 分鐘以上時，只略過那個欄位，不讓整筆失敗。
5. 某台裝置第一次上傳 `character.self` 時，記錄「這個 Discord 使用者聲稱擁有這個角色」。這只是記錄，不會因此給任何權限。正式的角色綁定沿用入會 BOT 的流程（規格 §2）。
6. **`member.share`**（D-014）：
   - `subject` 用 `guid` 對應角色；沒有的話用 `fullName`（v1.3，「名字 姓氏」），再沒有才用 `name`，規則和 `character.self` 一樣（完全一致而且唯一）。GF Sync 重建 `subject` 時要保留 `fullName`。找不到就 `rejected`，`reason: "unknown_subject"`。
   - **每個欄位各自比較** `recordedAt` 和網站目前那個欄位的時間，比較新而且非空才採用（D-008、D-014 第 3 點）。整筆比較新，不代表每個欄位都採用。和 `character.self`、Blizzard API 的比較也一律比欄位的時間。
   - 人工鎖定的欄位永遠不覆蓋（D-008）。
   - `recipes[<skillLineID>]`：
     - 有 `ids`：時間較新就採用，並記下 `hash`。
     - 沒有 `ids`，而且 `hash` 和網站記下的一樣：只把 `recordedAt` 往後推。
     - 沒有 `ids`，而且 `hash` 不一樣：略過，等帶 `ids` 的那一筆。**這是正常情況**，不是錯誤：AddOn 0.10.0 每次登出只帶一部分清單的 `ids`（savedvariables §member.share「配方 ID 分批」），同一份清單之後的登出會帶。整筆照樣 `accepted`。
     - 內容只少了 `ids`、其他都一樣的重寫（新的 `id`）也是正常的：AddOn 把帶過 `ids` 的項目改寫成不帶，讓存檔變小。照上一條「沒有 `ids`、`hash` 一樣」處理即可。
   - `via` 只是參考，可以存起來，不影響新舊規則。
7. **撤回 `withdrawn`**（`member.share`；D-015 起只有放棄專業）：
   - `recipes[<skillLineID>]`：原作者在這個時間放棄了那個專業。刪除那個專業時間早於它的配方。
   - 網站要記住墓碑時間。之後收到比墓碑舊的同一個專業的配方一律不採用，因為那可能來自很晚才上傳的別人。
   - 不會有 `all`、`location`（D-015 拿掉了隱私用的撤回）；收到也忽略。
   - `withdrawn` 不算隱私欄位，`private_field` 檢查要把它排除在外。
8. **`recipe.names`**：存成 `recipe_names(recipe_id, locale, name, first_seen_at)`。同一個 ID、同一個語系已經有名稱就不覆蓋。不需要驗證 subject。
9. **隱私**：`member.share` 的 `location`（`{ value: { zone, subZone }, recordedAt, via }`）和 `character.self`、`member.report` 的 `location` 一樣可以接受；其他地方的 `zone`、`online`、`location` 照舊拒絕或忽略。

10. **`crafting`**（v1.4，GF-006-B；savedvariables §crafting）：
    - **歸屬**：`character.self` 的 `w`／`j` 必須屬於 `uploader`，`member.share` 的必須屬於 `subject`（`w.customer` 是本人；`j` 的本人是這張單的 `crafter`，公會單是 `lock` 或接單的人）。不屬於的那一半略過，不讓整筆失敗。
    - **合併**：依訂單 `id` 存一份訂單；`w` 只有一份，`j` **每位工匠一份**（訂單 `id`＋作者 GUID，作者就是那一筆的 uploader 或 subject）。各份依 `recordedAt` 比新舊，只採用比較新的；整筆比較新不代表每一份都採用。和順序無關：收到舊的就忽略。`j` 比 `w` 先到時先存起來，`w` 到了再算狀態。第 1.5 版起還有網站自己的那一份。
    - **決勝規則**：照 savedvariables §crafting「決勝規則」（公會單接單者、`lock` 退單、兩份結案、14 天工匠結案、`recordedAt` 相同）。
    - **狀態**：照規格 R-6.1～R-6.6 由各半算出（等接單、製作中、待驗收、成交、取消）。成交和取消要分開顯示；成交裡「客人確認或自動判斷」和「工匠結案」（`closedBy = "crafter"`、`closeHow = "timeout"`）也要分開。結案之後收到的非結案資料不能把訂單改回進行中。
    - **製作服務**：`services` 依 `recordedAt` 整份比新舊。工匠服務頁：接單中（`active`）排前面；工錢分三種顯示：**沒有鍵＝沒填**、`0`＝免費、數字＝金額。`feeQuoted` 也一樣。
    - **檢查**：GUID、訂單 `id` 的格式；列舉值只接受契約列出的；數字是非負整數；`qty` ≥ 1。不合格的那張單或那個專業略過。
    - **隱私**：`crafting` 裡沒有名字和自由文字；顯示名字時用網站名冊依 GUID 對應。全公會成員都看得到訂單（規格 R-5.5），公開頁面不顯示。
    - **時間**：公會單還沒有 `w.lock` 時，用各工匠 `j.acceptedAt` 最早的那位當作暫定的接單者（和遊戲同樣的規則，R-5.3）。`j.deliveredAt` 用來判斷待驗收的天數（14 天工匠結案、太久沒動）。`cst = "review"` 顯示成待驗收。
    - **網站要自己檢查**：GF Sync 0.1.0 的 `character.self` 是原樣傳的，`crafting` 不會經過 GF Sync 的白名單（0.2.0 起才有）。所以上面的格式檢查網站一定要做，不能只靠 GF Sync。
    - 第一版只顯示和通知，網站不能建立或修改訂單（規格 R-9.1）。

11. **`adventure`**（v1.5，GF-002-B；savedvariables §adventure）：
    - **歸屬**：`tickets` 屬於團長、`worker` 和 `actions` 屬於職工，作者就是 uploader（`character.self`）或 subject（`member.share`）。不屬於的略過。
    - **合併**：`tickets`、`worker`、`actions` 各自依 `recordedAt` 整份比新舊。冒險單的錄取、候補、遞補由所有事件重新算出（排序規則見 savedvariables §adventure），和收到的順序無關。
    - **顯示**：冒險單和職工單分開，**和製作訂單也分開**（標題、圖示不同，規格 R-8.4）；只給公會成員看。職工單也只給公會成員看。
    - **`note`**：唯一的自由文字。網站一定要自己再檢查長度（40 個字元）、去掉控制字元，並**一律當純文字轉義顯示**；GF Sync 0.1.0 的 `character.self` 不會先過濾。
    - **Discord**（綠皮 BOT）：開單、錄取、遞補（通知被遞補的人和團長）、開始前 60／15 分鐘、取消時通知；事件要去重。
    - 第一版只顯示和通知；網站和 Discord 開單、報名之後另寫（id 開頭 `x`、`y` 先保留）。

## 4. 撤回

- 工具箱 0.9.1 起沒有同步開關（D-015）：裝了就會分享。想停止上傳，就暫停或解除安裝 GF Sync；不想被分享的成員不要安裝工具箱。已上傳的資料依規格 §4 的資料政策處理，屆時另行實作刪除端點。
- 在 `/pages/sync-devices` 撤銷裝置：該 token 立即失效。

## 5. 上線順序（D-014 的新 kind）

**固定為：網站 → GF Sync → AddOn 的上傳段（0.9.x 第 4 段）。**

1. 網站先能接受 `member.share`、`recipe.names`、`character.self.recipes`、`capturedAtServer`，以及 `unknown_kind`。
2. 然後 GF Sync 支援白名單重建（savedvariables §3 第 8 點）和 `unknown_kind` 重試。
3. 最後 AddOn 才開始寫新 kind。

AddOn 0.9 的第 1～3 段不寫新 kind，可以先上線。

**`crafting`（v1.4）也照同樣的順序**：網站先能接受並忽略不認得的 `crafting` → GF Sync 的 `member.share` 白名單加上 `crafting` → AddOn 0.11.0 開始寫。`character.self.crafting` 不用等 GF Sync（GF Sync 0.1.0 起原樣傳），但網站要先準備好。網站還沒處理 `crafting` 時照常 `accepted`、忽略這個欄位即可。

## 6. 資料表（建議，GearBot 決定）

- `member_field_values(character_id, field, value_json, recorded_at, hash, source, via, uploaded_by_device, updated_at)`，`field` 例如 `level`、`professions`、`location`、`recipes:164`
- `member_withdrawals(character_id, field, withdrawn_at)`
- `recipe_names(recipe_id, locale, name, first_seen_at)`

## 7. GF Sync 的更新清單：`GET /api/sync/gfsync-manifest.json`（v1.2）

詳細格式和 GF Sync 怎麼核對，見 GF Sync repo 的 `docs/UPDATE_MANIFEST.md`。網站這邊要做的：

- **不用登入、不用 token**。
- 內容：**最新一個已發布（不是草稿）的 GF Sync Release 附件 `gfsync-manifest.json`，位元組完全一樣**。
  - 不要重新排版，不要改換行，不要加 BOM，也不要轉碼
  - GF Sync 會用同一個 Release 的 `SHA256SUMS.txt` 核對 SHA-256，改一個位元組就不會被採用
- `Content-Type: application/json`。可以快取，建議 `Cache-Control: max-age=3600`。
- 還沒有任何清單時回 **404**，GF Sync 會改去 GitHub 拿。其他錯誤（5xx）GF Sync 會等下一次再試。
- 怎麼取得由網站決定，例如：
  - 定時抓 `https://github.com/GreenAndFangAdventure/gf-sync/releases/latest/download/gfsync-manifest.json` 存起來
  - 或者 owner 發布後手動上傳
- 網站可以**晚一點**才換成新版本（例如分批推送或暫緩），但**不能改內容**。
- 這個端點不受 426 影響（§2a 只適用 upload 和 device/start）：太舊的 GF Sync 正需要它來找新版。
- 工具箱的 `addon-manifest.json` 照同樣的原則原樣提供，格式見 `docs/contracts/addon-manifest.md`。
