# GF-002-H：`adventure` 上傳欄位提案（給 upload-api v1.6）

2026-11-24 · claude-addon · 依據規格 `GF-002_adventure-tickets_v1.0.md` §16（v1.1）、R-16.21

claude-pm 寫契約時請以本檔為草案；欄位名稱可以改，改了告訴我，我跟著改插件。**所有新欄位都是加上去的**：0.12.x 的欄位（`time`、`slots`（職責座位）、`status`、`decisions`、`worker.times[].mode/from/to`、`actions[].a/at/firstAt/role`）意思不變，網站還沒處理新欄位時照常接受。

## 1. `adventure.tickets.value[<id>]`（新增）

| 欄位 | 型別 | 意思 |
|---|---|---|
| `times` | array | 每個時段：`{ id, mode, from, length, to }` |
| `times[].id` | 1～5 | 時段編號，編輯時不變（R-16.4） |
| `times[].mode` | `"now"` / `"at"` | 現在／指定時間 |
| `times[].from` | 伺服器時間（秒） | 開始；`now` 是開單（或設成現在）那一刻 |
| `times[].length` | 秒或省略 | 長度；省略＝只約開始時間 |
| `times[].to` | 伺服器時間 | `from + length`；沒有長度時是 `from + 1800`（給舊的讀法，配對也用 ±30 分鐘） |
| `final` | 1～5 或省略 | 定案的時段編號；只有一個時段時第一個人錄取就算 |
| `finalAt` | 伺服器時間 | 定案時間 |
| `formedAt` | 伺服器時間或省略 | 成團時間（定案後按組隊或人數滿） |
| `phase` | `"open"` / `"formed"` / `"done"` / `"ended"` / `"unfinished"` / `"cancel"` | 插件算出的狀態：開放／成團／成行／時間到沒成團／成團未成行／取消 |
| `reason` | 字串或省略 | 結束原因：`manual`、`offline`、`time`、`unfinished` |
| `status` | 原有 | 原有 `open/departed/done/cancel`；**新增 `unfinished`**（成團未成行） |
| `time` | 原有 | 不變，內容是定案的時段（沒定案時是第一個時段） |
| `decisions[<guid>].slots` | array 或省略 | 邀請（`d = "invite"`）時邀請的時段編號 |

## 2. `adventure.actions.value[<ticketId>]`（新增）

| 欄位 | 型別 | 意思 |
|---|---|---|
| `slots` | array 或省略 | 報名的時段編號；省略＝0.12.x 的報名（算全部時段） |

## 3. `adventure.worker.value.times[]`（新增）

| 欄位 | 型別 | 意思 |
|---|---|---|
| `id` | 1～5 | 時段編號 |
| `length` | 秒或省略 | 長度 |
| `from` | 伺服器時間 | `now` 也有（設成現在那一刻） |

最多 5 個時段（原本 3 個）。

## 4. `adventure.log`（新增，成行紀錄，R-16.18～R-16.20）

```
"log": {
  "recordedAt": 1764000000,
  "value": {
    "<ticketId>": {
      "dungeon": "smg",            // 地城代碼，或省略
      "quests": [216],             // 任務單的 quest ID，或省略
      "slotStart": 1763990000,     // 定案時段的開始
      "formedAt": 1763990100,      // 成團時間
      "doneAt": 1763995000,        // 成行時間；成團未成行時省略
      "status": "done",            // "done" 成行 / "unfinished" 成團未成行
      "members": [ { "guid": "Player-0000-0000000A", "role": "dps" } ]
    }
  }
}
```

- `members` 包含團長本人；`role` 是當次錄取的職責：`tank`／`healer`／`dps`，任務單是 `member`。**不含名字或任何文字**。
- 來源有兩個，網站依 `<ticketId>` 去重、長期保存：
  1. `character.self`：團長這台電腦保留的最近 30 天／50 筆（存在 SavedVariables，不在玩家之間轉傳）。
  2. `member.share`：結束後 1 天內還在公會轉傳資料裡的那張單（單上帶了成員與時間），任何開 GF Sync 的人都會一起送。團長自己沒開 GF Sync 也不會漏掉，只要 1 天內有別人上傳。
- 兩個來源同一張單的內容一樣（成員是按完成那一刻的快照）。

## 5. 為什麼成行紀錄不放進轉傳資料

`GFTKA` 的轉傳摘要是每位作者所有群組一起算的；新增群組會讓 0.12.x 和 0.13.0 的摘要永遠不一致、一直互相要資料（Ledger.lua 開頭的說明）。冒險單群組 `T` 在 0.12.x 也限制最多 20 張。所以 30 天／50 筆的紀錄只留在團長電腦上傳，轉傳的只有結束 1 天內的單本身。

## 6. 網站要注意

- `phase = "formed"` 的單可以顯示「成團」；`status = "unfinished"` 或 `phase = "unfinished"` 不算成行，成就只算 `log` 裡 `status = "done"` 的紀錄。
- 舊網站只讀 `time` 時，多時段的單會顯示第一個（或定案的）時段，不會出錯。
