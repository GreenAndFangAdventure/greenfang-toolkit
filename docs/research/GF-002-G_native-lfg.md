# GF-002-G 遊戲內建「尋求組隊」（C_LFGList）在 16001 能做到什麼

- 查證：claude-addon 2026-11-24
- owner 的問題：「是否能同步內建集合時（遊戲內建的尋求組隊）的內容？如果時間是現在，無論職工單或冒險單，都可以去對應、建議現在有的地城及內容。」
- 方法：只讀公開資料（ForeverAPI 傾印），沒有進遊戲。下面寫「已查證」的是傾印裡確實有；「受保護」只看得到暴雪文件的標記，16001 實際行為**要實機確認**（`tests/addon/MANUAL.md` §3ac）。

## 來源

| 代號 | 來源 |
| --- | --- |
| FA | [zmarotrix/ForeverAPI](https://github.com/zmarotrix/ForeverAPI)（預設分支 `master`）：用 ApiProbe 0.2.2 從客戶端 1.60.1.70862（Interface 16001，enUS）傾印，2026-11-08 產生。讀了 `docs/index.md`、`docs/systems/LFGList.md`、`docs/systems/LFGInfo.md`、`docs/restrictions.md`，以及 `docs/events.md`、`docs/relocated.md` 的前段 |

## 結論

| 函式／事件 | 16001 有沒有 | 受保護？ | 工具箱怎麼用 |
| --- | --- | --- | --- |
| `C_LFGList.GetSearchResults()` | 已查證（✅，回傳 `total, results`） | 沒有標記 | 讀「上一次搜尋」的結果 |
| `C_LFGList.GetSearchResultInfo(id)` | 已查證（✅） | 暴雪文件：聊天封鎖時是 secret | 讀隊長、人數、說明、活動 |
| `C_LFGList.GetSearchResultMemberCounts(id)` | 有（🆕，沒有簽名） | 沒有標記 | 讀各職責還缺幾個（`TANK_REMAINING` 等；欄位名稱沿用 Mainline，要實機確認） |
| `C_LFGList.GetActivityInfoTable(activityID)` | 已查證（✅） | 沒有標記 | 用 `mapID` 對到工具箱的地城（`AdventureData` 的 `instance`），對不到再比名稱 |
| `C_LFGList.GetAvailableActivities(...)` | 有（🆕，沒有簽名） | 沒有標記 | 上架前找地城的 activityID；先試 `(2)`（地城類別），不行再不帶參數 |
| `C_LFGList.Search(categoryID, ...)` | 已查證（✅） | 暴雪文件：「某些情況受限制」；Mainline 要硬體事件 | **只在玩家按「搜尋尋求組隊」時呼叫**，類別 2（地城） |
| `C_LFGList.CreateListing(createData)` | 已查證（✅） | 暴雪文件：「某些情況受限制」；Mainline 要硬體事件 | **只在玩家按「開單」時**（而且勾了「同時在尋求組隊上架」） |
| `C_LFGList.ApplyToGroup(...)` | 有（🆕，沒有簽名） | 沒有標記；Mainline 要硬體事件 | 只在玩家按列上的「申請」時；參數照 Mainline（resultID, 坦, 補, 輸出） |
| `C_LFGList.UpdateListing`、`RemoveListing`、`GetActiveEntryInfo` | 有 | 同上 | 這次沒有用（見「沒做的」） |
| 事件 `LFG_LIST_SEARCH_RESULTS_RECEIVED` | 已查證（✅，傾印時觸發 7 次） | — | 收到就重新讀結果（玩家在原生介面搜尋也會觸發） |
| 事件 `LFG_LIST_SEARCH_RESULT_UPDATED` | 已查證（✅） | — | 同上 |
| `docs/restrictions.md` | 沒有任何 LFG 函式列在「被阻擋的動作」；`IsProtectedFunction: 1` 沒寫是哪一個 | — | — |

## 做得到（0.12.6 有做）

1. **讀搜尋結果**（b）：玩家在遊戲的尋求組隊搜尋，或在工具箱按「搜尋尋求組隊」之後，工具箱讀結果，只留**工具箱地城表裡有的地城**。冒險頁多一節「尋求組隊（遊戲內建）」，列出和**我的職工單或我開的冒險單地城相同**的隊伍：地城、人數、缺哪些職責、隊長、說明。列上有「密語」（隊長）和「申請」（用我職工單的職責，沒有職工單就用職業預設）。
2. **現在有人在找的地城**（c）：選目的地時，如果時間是「現在」，地城格子下面寫「現在 N 隊」；職工單選地城時，時段是「現在」也一樣。
3. **上架**（a）：開冒險單時，時間是「現在」而且選了地城，多一個勾選「同時在尋求組隊上架」。按「開單」時（這一下點擊就是硬體事件）用同一個地城的 activityID 和備註呼叫 `CreateListing`。
4. **同步與診斷**：冒險段多一行「尋求組隊：C_LFGList N / 9（沒有：…）｜上次結果：N 隊」。
5. **函式不存在就隱藏**：沒有 `C_LFGList` 時，「搜尋尋求組隊」按鈕、上架勾選、尋求組隊那一節都不出現。每次呼叫都用 `pcall`，失敗就當作沒有結果。

## 做不到或沒做

- **自動同步**：AddOn 不能自己在背景搜尋（`Search` 在 Mainline 要硬體事件），所以工具箱只能讀「最近一次有人按過的搜尋」。冒險頁不會自己更新尋求組隊的內容，要玩家按「搜尋尋求組隊」或在遊戲介面搜尋。
- **把尋求組隊的隊伍變成工具箱的冒險單**：兩邊的人員、錄取和候補規則不同，硬轉會讓雙方狀態不一致，所以只顯示、密語、申請。
- **上架後同步修改或下架**（`UpdateListing`、`RemoveListing`）：編輯冒險單時不會自動改尋求組隊的上架內容。原因：要硬體事件，而且 `CreateListing` 的標題和說明在 Mainline 是從原生介面的輸入框讀，AddOn 給的 `comment` 欄位可能被忽略。要先實機確認上架結果，再決定要不要做。
- **任務單上架**：尋求組隊的任務活動要 questID 對應（`GetActivityIDForQuestID`），先只做地城。
- **跨陣營、語言、評分**等進階篩選：用遊戲原生介面。

## 要 owner 實機查證（MANUAL §3ac）

1. `C_LFGList` 這些函式是不是都存在。
2. 按「搜尋尋求組隊」有沒有被阻擋（聊天框出現「介面動作被阻擋」就是受保護的）。
3. 搜尋後冒險頁有沒有出現「尋求組隊（遊戲內建）」的隊伍，地城、缺的職責對不對（`GetSearchResultMemberCounts` 的欄位名稱）。
4. 勾「同時在尋求組隊上架」再開單，遊戲的尋求組隊裡有沒有自己的隊伍，說明是不是冒險單的備註。
5. 列上的「申請」有沒有真的送出申請。
