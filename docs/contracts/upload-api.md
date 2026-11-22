# 契約：GF Sync ↔ 網站上傳 API（v1.3）

- 版本：
  - v1（2026-11-17 claude-pm 依 Q-005 與實作結果定稿）
  - **v1.1（2026-11-20 claude-addon，D-014）**：新 kind `member.share`、`recipe.names`、`character.self.recipes`、`capturedAtServer`、`reason: "unknown_kind"`、撤回、上線順序。依 claude-sync 審查修正後定稿
  - **v1.1（2026-11-20 claude-addon，D-015）**：`withdrawn` 只剩 `recipes`（放棄專業）；工具箱沒有同步開關
  - **v1.1（2026-11-20 claude-addon，GF-001-D14，AddOn 0.10.0）**：格式不變。補充：大公會時的筆數、配方 `ids` 分批（§2「數量」、§3 第 6 點）
  - **v1.3（2026-11-22 claude-addon，GF-001-D24，AddOn 0.9.8／0.10.0；與 GearBot 議定）**：新增選填欄位 `uploader.fullName`（每一種 kind）與 `member.share`／`member.report` 的 `payload.subject.fullName`：角色全名「名字 姓氏」，和網站名冊（Blizzard API）的寫法一樣。用來修正 `character_not_in_roster`（§3 第 2、6 點）。格式其餘不變
- 實作位置：網站 repo `green-and-fang-site`，位於 `functions/api/sync/*`（D-002）。PR 送到 `dev`
- 資料表一律用 `migrations/00xx_*.sql` 建立，不在執行時用 `CREATE TABLE IF NOT EXISTS` 建表

## 1. 裝置配對（只需做一次，給玩家的步驟要簡單）

流程類似電視登入：GF Sync 顯示一組短碼，並自動開啟瀏覽器。玩家用 Discord 登入網站後按「允許」，配對就完成了。

| 端點 | 說明 |
| --- | --- |
| `POST /api/sync/device/start` | 請求 `{label, clientVersion}`：`label` 是電腦名稱，會顯示在配對頁上。回傳 `{deviceCode, userCode, verifyUrl, interval, expiresIn}`。`userCode` 是 8 碼，10 分鐘內有效。`verifyUrl` 必須和 API 同一個 scheme 與 host，否則用戶端會改開 `<base>/pages/sync-pair?code=<userCode>` |
| `GET /pages/sync-pair?code=XXXX` | 網站頁面：需要 Discord 登入，按「允許這台電腦同步」 |
| `POST /api/sync/device/poll` | `{deviceCode}` → 還沒核准：200 `{pending:true, interval}`；核准：200 `{token, deviceId}`，token 只回傳這一次；被拒絕：403 `{error:'denied'}`；過期或無效：4xx；太頻繁：429，附 `Retry-After` |
| `GET /pages/sync-devices` | 玩家查看自己配對過的裝置，可以撤銷 |

- token：32 bytes 隨機值。伺服器只存 SHA-256 雜湊；GF Sync 用 Windows DPAPI 加密保存在本機。
- 資料表 `sync_devices(id, discord_user_id, token_hash, label, created_at, last_seen_at, revoked_at)`。

## 2. 上傳

`POST /api/sync/upload`，Header `Authorization: Bearer <token>`

```json
{ "client": { "name": "GFSync", "version": "0.1.0" },
  "items": [ <SavedVariables outbox entry，原樣轉成 JSON（member.share 由 GF Sync 白名單重建）> ] }
```

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
  | 其他 | 格式錯誤等 | 記成已回覆 |

- 錯誤碼：
  - 401／403：token 無效或已撤銷。用戶端要刪掉 token，並提示重新配對
  - 429：超過頻率上限，附 `Retry-After`（秒）
  - 400／413：整批內容有問題或太大。用戶端可以拆半重送，單筆仍失敗就不再重送
- `results` 裡沒有列出的 id，用戶端之後可以重送，伺服器會回 `duplicate`
- Lua 的空表格 `{}` 轉成 JSON 時是空陣列 `[]`。AddOn 依 savedvariables §2a 不寫空表格的鍵，網站收到 `[]` 時也要當成「空」處理，不要回錯誤
- **冪等**：同一個 `id` 第二次送來時回 `duplicate`，不會重複寫入，所以 GF Sync 可以放心重試。內容改變時 AddOn 一定會換 `id`（savedvariables §2a 第 2 點）

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

## 4. 撤回

- 工具箱 0.9.1 起沒有同步開關（D-015）：裝了就會分享。想停止上傳，就暫停或解除安裝 GF Sync；不想被分享的成員不要安裝工具箱。已上傳的資料依規格 §4 的資料政策處理，屆時另行實作刪除端點。
- 在 `/pages/sync-devices` 撤銷裝置：該 token 立即失效。

## 5. 上線順序（D-014 的新 kind）

**固定為：網站 → GF Sync → AddOn 的上傳段（0.9.x 第 4 段）。**

1. 網站先能接受 `member.share`、`recipe.names`、`character.self.recipes`、`capturedAtServer`，以及 `unknown_kind`。
2. 然後 GF Sync 支援白名單重建（savedvariables §3 第 8 點）和 `unknown_kind` 重試。
3. 最後 AddOn 才開始寫新 kind。

AddOn 0.9 的第 1～3 段不寫新 kind，可以先上線。

## 6. 資料表（建議，GearBot 決定）

- `member_field_values(character_id, field, value_json, recorded_at, hash, source, via, uploaded_by_device, updated_at)`，`field` 例如 `level`、`professions`、`location`、`recipes:164`
- `member_withdrawals(character_id, field, withdrawn_at)`
- `recipe_names(recipe_id, locale, name, first_seen_at)`
