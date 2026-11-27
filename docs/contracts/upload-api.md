# 契約：GF Sync ↔ 網站上傳 API（v1.6）

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
  - **v1.6（2026-11-25 claude-pm，AddOn 0.13.0～0.16.x；GearBot 2026-11-25 回覆第 3～7 段，owner 同日定案政策）**：都是新增，舊的用戶端照舊能用。網站都還沒實作。
    - `adventure` 的 v1.6 欄位：時段、定案、成團、成行、成行紀錄 `log`（§3 第 11 點）。**GearBot 2026-11-27 確認（見下一條）**
    - 新 kind `adventure.event`（§8）。**GearBot 2026-11-27 確認**；工具箱還沒上傳
    - 逐筆回執規則與 `reason: "stale_revision"`、`"test_data"`（§2、§2b）
    - 刪除訊號 `removed`、墓碑、網站後台刪除（§4）
    - 舊資料相容、GUID 保留與查閱權限（§3 第 12、13 點）
  - **v1.6 定稿（2026-11-27 claude-pm；GearBot 2026-11-27 第三～七次回覆逐點確認，owner 同日定案政策）**：§3 第 11 點的 `log` 權威來源、版本、撤銷與離會規則，`slots` 空陣列；§8 `adventure.event` 的欄位格式、上限、驗證順序、不認得的值、`evidence` 對照表。這是**契約文字**定稿，不代表網站已實作或核准上線。標「工具箱尚未寫」的欄位（`log` 的 `at`、`by`、`status: "revoked"`，`tickets`／`log` 的 `revision`）工具箱還沒送出
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
  | **`stale_revision`**（v1.6，和 `duplicate` 一起） | 已經有更高的 `revision` | 記成已回覆（§2b） |
  | **`test_data`**（v1.6，和 `rejected` 一起） | 帶 `test: true` | 記成已回覆，工具箱停止重送（§4c） |
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

## 2b. 逐筆回執與頻率（v1.6，GearBot 2026-11-25 同意）

- **頻率**：每台裝置每個**固定整點小時** 60 次上傳請求，所有 kind 共用（是請求數，不是筆數）。每次 1～50 筆 items，整個 request body 最多 1,000,000 bytes。超過回 429＋`Retry-After`。沒有另外的每小時事件筆數限制。
- **GF Sync**：事件和既有資料分批、共用額度；429 遵守 `Retry-After`；網路錯誤、503 退避重試；沒有逐筆確認的資料不清掉。沒收到回執時每 6 小時重送一次，加少量隨機錯開。
- **網站回應**（有 `revision` 的資料，目前只有 `adventure.event`）：

  | 情況 | status | reason |
  |---|---|---|
  | 新的版本，資料和回執都成功寫入後 | `accepted` | |
  | 同一個版本重送 | `duplicate` | |
  | 舊版本：身分與格式驗證通過，網站已存同一 `(originGUID, eventID)` 更高的 `revision` | `duplicate` | `stale_revision`（可附，方便診斷） |
  | 同一個版本、內容不同 | `rejected` | 例如 `revision_conflict` |
  | 帶 `test: true` | `rejected` | `test_data` |

  - `accepted` 一定要等資料和回執都提交成功才回。
  - 舊版本回 `duplicate` 的意思是「這版已經被涵蓋，可以清佇列」：不覆寫新版、不重複計數。
- **工具箱**：
  - 只清除回執對應的**確切版本**；舊版本的回執不能清掉還沒確認的新版本。
  - `rejected` 不算成功：保留在佇列並記下原因，等修正。**例外**：`rejected`＋`test_data` 是終止，不再重送，直接清掉。
  - 回執經 `GreenFangToolkit_Inbox`（D-018）延遲回到遊戲，下次登入時處理。
  - 佇列每個角色最多 1,000 筆，800 筆時警告，滿了不收新事件，**不丟掉還沒確認的事件**。

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
    - **v1.6 欄位**（AddOn 0.13.0 起已在寫；GearBot 2026-11-27 確認）：
      - `tickets.value[id]`：`times[]`（`{ id, mode, from, length?, to }`，1～5 段）、`final`、`finalAt`、`formedAt`、`phase`（`open`／`formed`／`done`／`ended`／`unfinished`／`cancel`）、`reason`（`manual`／`offline`／`time`／`unfinished`）、`status` 新增 `unfinished`、`decisions[GUID].slots`、`revision`（**工具箱尚未寫**；見下面「版本序列」）。
        - **時段檢查**：`times[].id` 在同一張單內唯一，編輯時不變。`final`、`decisions[GUID].slots`、`actions.value[id].slots` 都必須指向這張單存在的 `times[].id`；指向不存在的時段，那個欄位略過。`length` 有填時是正整數，`to` 必須等於 `from + length`；沒填才用相容的 `to = from + 1800`。不符的那個時段略過。
        - **`phase` 與 `status`**：`phase = "done"` 時 `status` 可能還是 `open`／`departed`（團長還沒寫回），允許暫時不同步。成行統計一律只看 `log`，不看 `phase`。
      - `actions.value[id].slots`、`decisions[GUID].slots`：時段編號的陣列。**省略＝全部時段**（0.12.x 的報名）。**空陣列＝不參與任何時段**，網站記診斷、其他有效欄位照收（不是 `rejected`）；工具箱正常不會送空陣列。非陣列、重複的編號、不存在的時段編號不適用這個寬容規則，照上面的時段檢查當格式錯誤處理。
      - `worker.value.times[]`：多 `id`、`length`、`from`，最多 5 段。
      - `adventure.log`：`{ recordedAt, value: { <冒險單 id>: { dungeon?, quests?, slotStart, formedAt, doneAt?, status: "done"|"unfinished"|"revoked", members: [{ guid, role }], auto?, at?, by?, revision? } } }`。
        - `members[].role` 是 `tank`／`healer`／`dps`／`member`（任務單），和事件的 `role`（`t`／`h`／`d`／`any`）是不同字彙。
        - `at`（團長寫這筆的時間）、`by`（`leader`／`seen`）、`revision`、`status: "revoked"`：名稱已確認，**工具箱尚未寫**。
        - 來源：`character.self`（團長電腦最近 30 天／50 筆）和 `member.share`（結束約 1 天內還在轉傳的那張單，subject＝團長）。
      - **`log` 是長期紀錄**：上傳的 30 天／50 筆、1 天轉傳只是上傳範圍，不能整份取代網站已存的紀錄。新上傳沒帶某張舊單，不代表刪除或撤銷；刪除只來自 §4a `removed`。`log` 逐筆合併，不套用上面「合併」那條的「依 `recordedAt` 整份比新舊」。
      - **成行只算有效的 `log.status = "done"`**：`phase = "formed"` 只顯示成團；`unfinished`、`ended`、`cancel`、被撤銷的 `done` 都不算成行。「已確認來源」不等於算成行。不能只靠單 id 去重或最新收到的轉傳，規則如下。
      - **`log` 的權威來源、版本與撤銷**：
        1. **歸屬**：`log` 的作者是團長（`character.self` 的 uploader、`member.share` 的 subject），先通過既有的作者／角色驗證。網站在通過驗證的團長送來 `tickets.value[id]` 時綁定單與團長；「第一次收到」不是所有權證明。不同作者撞同一個單 id 不改綁、記衝突。綁定前先到的孤立 `log` 只能待確認，不能占用所有權。`members` 不含團長的那筆略過。同一包的 `tickets` 與 `log` 的 id、作者、狀態必須一致。
        2. **來源等級**：
           - A＝團長本人的 `character.self`。
           - B＝`member.share` 轉傳，同一包 `tickets.value[id].status` 和 `log.status` 一致；或同一包沒有這張單、而且這筆沒有 `auto`（這是契約採信的轉傳等級，不代表網站另外驗證了團長本人）。
           - C＝臨時：同一包那張單 `status` 是 `open`／`departed`，或同一包沒有這張單、而且 `auto = true`。
           - 同一包那張單是其他非完成狀態（例如 `cancel`）或狀態不一致 → 不落入 B，記衝突、不計入。
           - A、B 是已確認來源；C 只顯示「待團長確認」，不計入、不覆蓋 A／B、不自動升級。
           - `by` 是客戶端聲明，不能直接信，仍要驗作者、來源與歸屬。
        3. **版本序列（新格式，帶 `revision`）**：`revision` 是同一張單、由團長維護的遞增版本；**`tickets` 和 `log` 共用同一個序列，不各自累加**。有 `revision` 時它是主要順序，`at` 只當時間與診斷。較高的有效 `revision` 贏，同一秒內退回再成行也照 `revision` 排。同一 `revision` 內容不同 → 留成候選、標衝突、暫不計數，等更高的有效版本；不能用 `at` 打破平手。某張單收過新格式之後，沒有 `revision` 的資料不能再改變它的狀態或撤銷水位。
        4. **相容格式（沒有 `revision`）**：用團長的狀態時間比，不用收到先後或上傳者的 `capturedAt`。這筆有 `at` 時用 `at`；沒有時 `done` 用 `doneAt`，`unfinished` 用同一包 `tickets.value[id].statusAt`，都沒有就視為時間不明、不能覆蓋已存的 `done`。`doneAt` 只表示實際成行時間。時間大的贏；同時間 A > B > C。同時間、同等級、內容不同：兩份留成候選、標衝突、暫不計數，等更高的有效版本。C 之間保留 `doneAt` 最早的那份，只作待確認的展示，不作正式成行時間。只帶 `at`、`by` 而沒有 `revision` 的過渡資料仍屬相容格式：撤銷與同一秒排序的問題要到 `revoked` 與 `revision` 都寫上才算解決。
        5. **撤銷（團長退回）**：收到通過作者與單歸屬驗證的團長 `tickets.value[id]`，`statusAt` 是有效時間，而且 `status ≠ "done"`、版本晚於已存的 `done`（新格式比 `revision`，相容格式比時間）→ 那筆 `done` 標成已撤銷（保留），記下撤銷水位，衍生統計重算。工具箱寫 `status: "revoked"` 之後也可以直接用那筆。
        6. **防復活**：撤銷後，更新的 `done` 才恢復。新格式看 `revision` 較高；相容格式要時間**嚴格晚於**撤銷水位，相等不恢復（同一秒內退回再成行在相容格式下不恢復，等後續有效版本）。更早的一律忽略。
        7. **和 `removed` 分工**：退回是狀態改變，單還在、可再成行，網站保存撤銷水位防復活；`removed` 刪單、它的 `log`、團長這張單的事件，留永久墓碑（§4a）。墓碑只留必要的防重資料，不永久保留作者、`members` 等個人關聯；不刪成員自己提交的事件和報名。
        8. **離會**：uploader／subject 不在名冊就拒收，所以不會再有新版本。已存的 A／B 有效成行保留，C 維持待確認。確認離會後 180 天清除作者、`members` 和其他能回溯到個人的關聯，包括原始 payload、衍生表、診斷紀錄；只留不能反查個人的公會彙總，彙總也不能藉冒險單 id 連回個人。
        9. **已知限制**：工具箱寫 `revoked` 之前，退回的訊號只在單上，單只在結束後約 1 天內、每次最多 20 張的範圍上傳；這段期間沒人上傳，網站會留著舊的 `done`。寫了 `revoked` 之後，30 天視窗只是改善漏傳，團長離線超過 30 天後仍可能補不回來。
      - 舊網站只讀 `time` 時顯示定案的時段（沒定案時是第一段），不會出錯。
      - 欄位詳見 `docs/research/GF-002-H_adventure-upload-v1.6.md`。
    - **刪除**：`removed` 見 §4a。

12. **舊資料相容**（v1.6，GearBot 2026-11-25 同意）：
    - 0.9.x～0.15.x 的上傳都繼續接受：沒有 `times` 只有 `time`、職工單最多 3 段、`actions` 沒有 `slots`、沒有 `phase`／`final`／`log`、`status` 沒有 `unfinished`、`member.report`（只有 0.8.x～0.9.x 寫過）。
    - **缺新欄位＝不知道**：不補成 0 或空值，不因此拒收，不加 `addon_too_old`。網站沒有依工具箱版本號擋上傳。
    - 舊包仍會碰到的既有拒收條件（MAIN #307 程式碼，沒有拿各版樣本驗證）：
      - 共通：id 無效、未知 kind、world／guild／realm 不符、payload 無效。
      - 時間：缺有效的 `capturedAtServer`／`capturedAt`、早於 2020 年、超前網站時間 600 秒以上。沒有「太舊」期限。
      - 身分：uploader 不在名冊；有 GUID 但查不到時不改用名字比對。
      - `character.self`：角色識別不足或 level 不合法。
      - `member.share`：subject 查不到或有歧義 → `unknown_subject`。
      - `member.report`：要有整數 `reportedAt`、`subject.realm` 要明確等於該 realm（**缺 `subject.realm` 會被拒**）、subject 在名冊、通過角色／level 驗證。
      - `roster.snapshot`：`total` 1～2,000 且等於 `members` 筆數；成員名稱無效或重複會拒收。

13. **不上傳的資料與 GUID**（v1.6，GearBot 2026-11-25 同意）：
    - 不上傳：職責定位、天賦、物資供需（自動集料、手動刊登）、黑庫、幹部註記、功能探測紀錄、拍賣場價格、任務名稱（只上傳 quest ID）。事件不含角色名稱。網站的天賦資料來自 Blizzard API。
    - 事件裡的 GUID：成員在會期間保留；**確認離會後 180 天**刪除原始事件和可回溯到個人的關聯。180 天內確認重新入會就取消倒數；刪除後再入會不恢復。
    - 離會判定：要由成功且完整的名冊同步確認，並記下確認離會的時間；一次 API 失敗、404 或名冊不完整都不能開始倒數。
    - 查閱：公會成員只看不含個人明細的彙總；原始事件和 GUID 只有網站管理員能查，一般幹部不自動有權限。「和誰一起冒險」第一版不開放給一般成員。
    - 彙總要不能反查個人：GUID 換成固定雜湊不算匿名。

## 4. 撤回與刪除

- 工具箱 0.9.1 起沒有同步開關（D-015）：裝了就會分享。想停止上傳，就暫停或解除安裝 GF Sync；不想被分享的成員不要安裝工具箱。
- 在 `/pages/sync-devices` 撤銷裝置：該 token 立即失效。

### 4a. 作者本人刪除：`removed`（v1.6，GearBot 2026-11-25 同意；工具箱、GF Sync、網站都還沒實作）

- `adventure` 和 `crafting` 各加一個選填的 `removed`：`{ recordedAt, value: { "<單 id>": { at, why: "test" | "owner" } } }`。
- 只有作者能刪自己的單：冒險單是團長、訂單是客人。網站比對作者 GUID 和 uploader（`character.self`）或 subject（`member.share`），不是作者的略過。
- `removed` 是**累積的**：下一份清單沒帶某個 id，不代表取消刪除，墓碑照留。
- **刪除範圍**（owner 2026-11-25）：
  - 刪：那張單本身、它的成行紀錄（`log`）、那位作者這張單的事件。
  - 不刪：其他角色自己提交的紀錄（例如成員自己的 `participant_done` 事件、報名動作）。
  - 衍生統計重算，不保留個人明細。
- **墓碑**（owner 2026-11-25 採 GearBot 建議）：
  - **長期保留、不自動到期**（舊存檔可能很久以後才重送）。
  - 內容是最小的防重放標記：資料類別、單 id、刪除時間，加上能比對作者、但**不是明文 GUID** 的值；不能永久保留明文作者 GUID。
  - 之後再收到同一個 id 的資料一律不採用。同一個 id 永不復用；重開要用新 id（工具箱的重開本來就換 id）。
  - 舊回執、關聯表、備份還原都要遵守刪除規則，避免資料復活。

### 4b. 幹部刪除別人的資料：網站後台

- 不經過工具箱。網站用自己的資料判斷權限，不信客戶端自稱幹部。
- 第一版（owner 2026-11-25 同意，之後可能再改）：沿用現有後台的 Discord 登入＋網站設定的 `ADMIN_DISCORD_USER_IDS` 白名單，不看 Discord 身分組或名冊會階。要開放一般幹部時，網站另外加明確的刪除權限。

### 4c. 測試資料

- 工具箱的測試版（版本是 `dev` 或帶 `-`）不分享、不上傳。
- 網站收到帶 `test: true` 的資料：不進業務資料、不計數，逐筆回 `rejected`＋`reason: "test_data"`（§2b），工具箱看到就停止重送。
- 0.14 版測試時上傳過的測試訂單和冒險單：MAIN #307 沒有解析或寫入 `crafting`／`adventure`，接收端也不把完整 payload 寫進資料庫或 console log，所以**沒有業務內容要刪**。網站留有上傳回執 metadata（id、裝置、kind、資料時間、接收時間），同一包裡角色、專業等欄位照常儲存。正式環境的其他日誌和備份還沒查。

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

## 8. 新 kind `adventure.event`（v1.6；GearBot 2026-11-27 確認；工具箱還沒上傳）

工具箱 0.16.0 起在本機記背景事件（`GreenFangToolkitDB.events`），還沒接 GF Sync。

- 一筆一個事件。共通欄位 `id` = `<eventID>.<revision>`，同一版本重送回 `duplicate`（§2b）。
- 去重：`(originGUID, eventID)`。
- **身分**：`originGUID` 必須等於 `participantGUID`，而且要對應可信的上傳者角色身分（依 §3 第 2 點比對到的 uploader）；只驗證 GUID 在名冊裡不夠。不符 → `rejected`。
- **`revision`**：正整數。同版本內容不同 → `rejected`（`revision_conflict`）；低版本不覆蓋（`duplicate`＋`stale_revision`）；高版本撤銷後，延遲到的舊版本不能讓它復活。較高的版本可以先到，網站不能要求一定先收到前一版。網站不為任何欄位（例如 `reopenOf`）開同版本衝突的特例。
- **`observedAt` 固定不變**：同一個 `eventID` 的所有版本都一樣；不同 → 當成內容衝突。

### 8.1 欄位

| 欄位 | 必填 | 允許值／格式 |
|---|---|---|
| `eventID` | 是 | v1：`^e[0-9a-z]{2,10}$`；外層上限 16 字元，v1 不因此放寬 |
| `schemaVersion` | 是 | `1`；其他值照 §8.2「不認得的值」處理，只驗共通封套 |
| `originGUID`、`participantGUID` | 是 | 本人 GUID，兩者相同，40 字元內 |
| `adventureID` | `worker_order_created` 以外 | 冒險單 `id`：`a` 開頭、`[0-9a-z.]`、64 字元內 |
| `workerOrderID` | 職工單事件；走職工媒合的 `participant_admitted`／`participant_done` | `^w[0-9a-z]{1,5}\.[0-9a-z]{1,7}$`，4～14 字元（`w`＋作者雜湊的 base36＋`.`＋職工單建立時間的 base36）。這只是語法範圍：網站依正則與上限驗證，不憑雜湊反推作者；所有權仍走可信角色驗證 |
| `participationPath` | 是 | `leader`／`worker_match`／`direct_signup` |
| `eventType` | 是 | `adventure_created`、`adventure_finalized`、`adventure_formed`、`adventure_done`、`adventure_cancelled`、`adventure_expired`、`adventure_unfinished`、`worker_order_created`、`worker_order_matched`、`signup_applied`、`participant_admitted`、`participant_done` |
| `activityType` | 是 | `dungeon`／`raid`／`quest`／`zone`／`worker`／`other` |
| `destinationID` | 否 | 地城代碼 `^[a-z0-9]{1,12}$`；`q:` 加 1～5 個 quest ID（正整數 1～9,999,999）用 `.` 連接；`z:` 加**受長度限制的區域名稱**（遊戲內地名，40 個 Unicode 字元內）；整體 200 bytes 內 |
| `role` | 否 | `t`／`h`／`d`／`any` |
| `observedAt` | 是 | 第一次記錄時的事實時間（Unix 秒），所有版本相同；可能比收到時間早很多，不因此拒收 |
| `revision` | 是 | 1～10,000 |
| `revisedAt` | `revision ≥ 2` 應提供 | 工具箱寫這一版的時間。缺少或早於 `observedAt` → 照收、記診斷；型別錯誤或超出允許時間範圍 → `rejected`。只顯示和診斷，不用來排序版本 |
| `status`、`change` | 是 | `active`／`revoked`；`new`／`correction`／`revocation`／`restore`。`new` ⇒ `revision = 1` 且 `active`；`revocation` ⇒ `revoked`；`restore`、`correction` ⇒ `active` |
| `revokedReason` | `revoked` 時 | `back`／`no_self_evidence` |
| `evidence` | 是 | 依 §8.3 對照表 |
| `reopenOf` | 否 | 只在 `adventure_created`；格式同 `adventureID` |
| `test` | 否 | 工具箱不會送；網站看到 `true` 照 §4c |

### 8.2 上限、驗證順序、不認得的值

- **定義**：bytes 一律 UTF-8；字元按 Unicode code point 計，不是 UTF-16 長度。每筆事件上限 2,048 bytes，指網站解析後以固定緊湊 JSON 重新序列化的 UTF-8 bytes，未知欄位也算。
- **網站獨立驗證**：quest ID 是正整數、個數、有效 UTF-8、`z:` 清理後的長度，網站都自己驗，不只信工具箱已處理；`z:` 去掉控制字元、當純文字轉義顯示。
- **驗證順序**：先驗身分、大小、共通封套；已知 schema 再驗必填、格式和已知值之間的搭配（已知欄位之間的矛盾不能靠另一個未知值繞過）；最後才把含未知值的事件送進待解析。
- 超過上限、格式不符、已知值的組合不合法（含 `evidence` 是認得的值但和事件類型不對應）→ 那一筆 `rejected`（`invalid_field`），同一次請求的其他筆照常。
- **不認得的值不拒收**（owner 2026-11-27：AddOn 不應該被網站功能擋住）：
  - 列舉欄位出現不認得的值，或 `schemaVersion` 不是 1 → **成功持久化後**回 `accepted`＋`reason: "unknown_value"`，標成待解析，不進任何統計。
  - 未知 `schemaVersion` 只驗共通封套，不套用 v1 的事件特定必填與 `destinationID` 格式，也不照 v1 解讀內容。
  - 待解析事件也參與 `revision` 排序：較高版本是未知值時，較低版本不能繼續當有效版本計數。
  - 保留有界限的原始 payload＋診斷計數；不保存 token 等傳輸憑證；重新解析可重跑、不重複計數；遵守 §3 第 13 點的 GUID 刪除政策。
  - 代價：工具箱收到 `accepted` 就不再重送，網站之後才支援的新類型要靠保存的原始 payload 自己補算。
- 不認得的欄位：不影響接收，但不能直接拿來顯示或統計。

### 8.3 `evidence` 對照表

`evidence` 是**工具箱回報的證據類型**，不是網站已驗證的遊戲行為。

| `eventType` | `participationPath` | `evidence` |
|---|---|---|
| `adventure_created` | `leader` | `self` |
| `adventure_finalized` | `leader` | `slot` |
| `adventure_formed` | `leader` | `full`／`group`／`party`／`kept`／`formed` |
| `adventure_done` | `leader` | `leader_done`／`auto` |
| `adventure_cancelled` | `leader` | `manual`／`offline`／`state` |
| `adventure_expired` | `leader` | `time` |
| `adventure_unfinished` | `leader` | `unfinished` |
| `worker_order_created` | `worker_match` | `self` |
| `worker_order_matched` | `worker_match` | `invited` |
| `signup_applied` | `direct_signup` | `self` |
| `participant_admitted` | `worker_match`／`direct_signup` | `seat` |
| `participant_done` | `leader` | `leader_done`／`self_detected`／`self_party` |
| `participant_done` | `worker_match`／`direct_signup` | `self_detected`／`self_party` |

- 團本（`raid`）只會有 `adventure_created`、`signup_applied`。`adventure_done` 的 `auto` 是單的成行，不是任何人的個人證據。
- `evidence` 是上表認得的值、但不屬於該事件類型 → `rejected`（`invalid_field`）；上表都沒有的值 → 照 §8.2「不認得的值」處理。

### 8.4 語意

- 事件裡沒有任何人名，只有本人的 GUID；唯一的文字是 `destinationID` 的 `z:` 區域名稱（地名）。成員本人成行要有本人的證據才記，整團 60% 不算個人證據。團本只記建立和報名。
- **`log` 和 `event` 分工，不相加**：`log` 管整團的成行（一張單算一次），`event` 管個人參與（`participant_done`，同一冒險同一角色算一次）。兩者不相加計次，也不互相補。`participant_done` 撤銷或恢復時，衍生統計跟著重算。
- **這次成行的時間**：`participant_done` 恢復時 `observedAt` 不變，網站不拿它當這次成行的時間；看該單 `log` 的 `doneAt`，`log` 還沒到時顯示未知、不推測。
- 工具箱本機會刪除已確認且超過 180 天的事件，不送任何東西；網站不要把「之後沒再收到」當刪除。
- 「和誰一起冒險」由網站把同一 `adventureID` 的 `participant_done` 合起來算，工具箱不上傳別人的 GUID；第一版不開放給一般成員（§3 第 13 點）。
- 上線順序照 §5：網站 → GF Sync → AddOn。`adventure.event`、事件 Inbox 回執、刪除訊號都不在 GF Sync 0.2.0 的範圍，也不擋 0.2.0 發布。
