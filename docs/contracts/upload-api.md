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
    - `adventure` 的 v1.6 欄位：時段、定案、成團、成行、成行紀錄 `log`（§3 第 11 點）。**第 1 段 GearBot 回覆待收**
    - 新 kind `adventure.event`（§8）。**第 2 段 GearBot 回覆待收**；工具箱還沒上傳
    - 逐筆回執規則與 `reason: "stale_revision"`、`"test_data"`（§2、§2b）
    - 刪除訊號 `removed`、墓碑、網站後台刪除（§4）
    - 舊資料相容、GUID 保留與查閱權限（§3 第 12、13 點）
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
    - **v1.6 欄位**（AddOn 0.13.0 起已在寫；GearBot 第 1 段回覆待收，欄位名稱可能再調）：
      - `tickets.value[id]`：`times[]`（`{ id, mode, from, length?, to }`，1～5 段；`id` 是時段編號、編輯時不變；沒有 `length` 時 `to = from + 1800`）、`final`、`finalAt`、`formedAt`、`phase`（`open`／`formed`／`done`／`ended`／`unfinished`／`cancel`）、`reason`（`manual`／`offline`／`time`／`unfinished`）、`status` 新增 `unfinished`、`decisions[GUID].slots`。
      - `actions.value[id].slots`：報名的時段編號；沒有＝全部時段。
      - `worker.value.times[]`：多 `id`、`length`、`from`，最多 5 段。
      - `adventure.log`：`{ recordedAt, value: { <冒險單 id>: { dungeon?, quests?, slotStart, formedAt, doneAt?, status: "done"|"unfinished", members: [{ guid, role }], auto? } } }`。依冒險單 `id` 去重、長期保存；來源是 `character.self`（團長電腦最近 30 天／50 筆）和 `member.share`（結束 1 天內還在轉傳的那張單）。
      - 「成行」只算 `log` 裡 `status = "done"`。`phase = "formed"` 只顯示成團；`unfinished`、`ended`、`cancel` 不算成行。退回以團長最新的 `tickets` 為準重算，不累加。
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

## 8. 新 kind `adventure.event`（v1.6 草案；GearBot 第 2 段回覆待收；工具箱還沒上傳）

工具箱 0.16.0 起在本機記背景事件（`GreenFangToolkitDB.events`），還沒接 GF Sync。這一節是我們的提議，等 GearBot 回第 2 段後再定。

- 一筆一個事件。共通欄位 `id` = `<eventID>.<revision>`，同一版本重送回 `duplicate`（§2b）。
- 去重：`(originGUID, eventID)`，以 `revision` 大的為準（GearBot 在第 3 段已用這個鍵）。

| 欄位 | 必填 | 說明 |
|---|---|---|
| `eventID` | 是 | 穩定 ID，同一件事永遠一樣 |
| `schemaVersion` | 是 | 目前 1 |
| `originGUID`、`participantGUID` | 是 | 都是本人；網站要比對上傳者，不能只信客戶端 |
| `adventureID` | 職工單建立以外 | 冒險單 `id` |
| `workerOrderID` | 職工單事件 | |
| `participationPath` | 是 | `leader`／`worker_match`／`direct_signup` |
| `eventType` | 是 | `adventure_created`／`finalized`／`formed`／`done`／`cancelled`／`expired`／`unfinished`、`worker_order_created`／`matched`、`signup_applied`、`participant_admitted`、`participant_done` |
| `activityType` | 是 | `dungeon`／`raid`／`quest`／`zone`／`worker`／`other` |
| `destinationID` | 否 | 地城代碼、`q:<任務 ID>` 或 `z:<區域>` |
| `role` | 否 | `t`／`h`／`d`／`any` |
| `observedAt` | 是 | 第一次觀察到的時間，不會改 |
| `revision` | 是 | |
| `revisedAt` | 否 | |
| `status`、`change` | 是 | `active`／`revoked`；`new`／`correction`／`revocation`／`restore` |
| `revokedReason` | 否 | 目前有 `back`、`no_self_evidence` |
| `evidence` | 是 | 例如 `leader_done`、`auto`、`self_detected`、`self_party` |
| `reopenOf` | 否 | 重開時指向舊的冒險單 `id` |
| `test` | 否 | 工具箱不會送；網站看到 `true` 照 §4c |

- 事件裡沒有任何名字或文字，只有本人的 GUID。成員本人成行要有本人的證據才記，整團 60% 不算個人證據。團本只記建立和報名。
- 「和誰一起冒險」由網站把同一 `adventureID` 的 `participant_done` 合起來算，工具箱不上傳別人的 GUID；第一版不開放給一般成員（§3 第 13 點）。
- 上線順序照 §5：網站 → GF Sync → AddOn。`adventure.event`、事件 Inbox 回執、刪除訊號都不在 GF Sync 0.2.0 的範圍，也不擋 0.2.0 發布。
