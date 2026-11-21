# 點配方可以做什麼（GF-001-D19、D20，AddOn 0.9.4、0.9.5，公開版 0.10.0）

- 查證：claude-addon 2026-11-20
- 方法：只讀公開資料，沒有進遊戲。來源和 `forever-api-16001.md` 相同，主要是 FA（[zmarotrix/ForeverAPI](https://github.com/zmarotrix/ForeverAPI)，客戶端 1.60.1 的傾印）
- 狀態：全部**未實機驗證**，要照 `tests/addon/MANUAL.md` §3p、§3q、§3r 在遊戲裡確認

## 結論

| 想做的事 | 做法 | 依據 | 狀態 |
|---|---|---|---|
| 滑鼠移到配方：看配方內容 | `GameTooltip:SetSpellByID(配方 ID)`（0.9.0 起就有） | 配方 ID 就是製作法術的 ID | 0.9.x 已在用；是否列出材料要看客戶端 |
| **點一下別人的配方**（或自己的配方打不開時）：把配方說明釘在畫面上 | `ItemRefTooltip:SetHyperlink(連結)`，連結先用 `C_TradeSkillUI.GetRecipeLink(id)`，沒有的話用 `C_Spell.GetSpellLink(id)`，都沒有就用 `spell:<id>` | FA TradeSkillUI.md：`GetRecipeLink` 存在（沒有說明文件）；Spell.md：`C_Spell.GetSpellLink` 已查證 | 推測可用。客戶端沒有 `ItemRefTooltip` 時什麼都不做 |
| **Shift＋點**：把配方貼到聊天 | 同上的連結，用 `ChatFrameUtil.InsertLink`（舊名 `ChatEdit_InsertLink`）；聊天框沒開時用 `ChatFrameUtil.OpenChat`（舊名 `ChatFrame_OpenChat`）打開並放進去 | FA relocated.md：兩個舊名都還在（相容層） | 推測可用 |
| **右鍵**：選單裡每位在線、會做的人一行「密語〈名字〉」（0.9.5 起；0.9.4 是滑鼠移過去才出現的按鈕） | `ChatFrameUtil.SendTellWithMessage`（舊名 `ChatFrame_SendTellWithMessage`）打開對他的密語，內容是「可以幫我做〔配方〕嗎？」；沒有的話用 `SendTell` 只打開密語 | FA relocated.md、globals-undocumented.md | 推測可用。**工具箱不會自己送出**，要玩家按 Enter |
| **點一下自己的配方**：在自己的專業視窗裡打開（0.9.5 起；0.9.4 是「打開」按鈕） | `C_TradeSkillUI.OpenRecipe(配方 ID)`，只在戰鬥外、而且是自己會的配方 | FA TradeSkillUI.md：已查證存在 | **不確定**：沒有資料說它是不是受保護的函式。呼叫失敗時改成釘住配方說明；但如果客戶端擋下時沒有回報錯誤（畫面上出現「功能因插件失效」），工具箱看不出來，請回報 |

## 做不到或沒做的

- **列出材料**：`C_TradeSkillUI.GetRecipeSchematic` 存在，但只對**自己開著的專業視窗**裡的配方可靠；別人的配方我們只有 ID，沒有材料資料。所以材料只靠滑鼠提示（客戶端自己的法術說明）
- **配方分類、需要的技能等級**：分享的資料只有配方 ID。要做的話得在讀自己的專業視窗時多記分類和等級，而且要改分享格式（Share.lua 的 `R` 記錄）。這次沒做
- **打開別人的專業視窗**（看他的配方清單）：需要對方把專業連結貼到聊天，工具箱不能代替
- **自動密語或自動送出**：不做。所有訊息都由玩家自己送

## 畫面上的樣子（0.9.5 起）

- 0.9.4 的「密語」「打開」按鈕拿掉了。它們的程式在滑鼠離開時把**那一列自己也藏起來**（藏按鈕的迴圈連「目前那一列」也一起藏了），這就是 owner 看到「滑鼠移上去配方就不見」的原因
- 現在：點一下打開或釘住，Shift＋點貼到聊天，右鍵密語；滑鼠移上去只有淡淡的反白，字一直看得到
- 沒有在線、會做的人（自己不算）時，右鍵沒有選單
- 不另外加說明文字：Shift＋點、右鍵選單都是遊戲內通用的做法
- **需要技能、分類的篩選**：做不到，理由同上（分享的資料只有配方 ID）

## 專業篩選和圖示（GF-001-D21，0.9.6 起）

- **0.9.5 的錯誤**：選「烹飪」卻列出急救和熔煉的配方。原因不在畫面：自己的專業視窗打開時，`C_TradeSkillUI.GetAllRecipeIDs()` 也列出角色**其他專業**學會的配方（推測，從 owner 的截圖判斷：混進來的都是 owner 自己的專業），工具箱把它們全部記在當時打開的專業下面，也分享給別人
- **修正**：每個配方都問客戶端它屬於哪個專業，讀專業視窗時和整理配方頁時都會問（0.9.0～0.9.5 分享出去的清單也是混的）
  1. `C_TradeSkillUI.GetProfessionInfoByRecipeID(id)` 的 `parentProfessionID` 或 `professionID`（FA：已查證存在）
  2. 沒有的話 `C_TradeSkillUI.GetTradeSkillLineForRecipe(id)`（FA：存在，沒有說明文件）
  3. 再沒有的話 `C_TradeSkillUI.IsRecipeInSkillLine(id, 專業)`（FA：已查證存在）
  - 客戶端說不出來的配方照樣保留。結果記在快取裡
  - 自己存過的混合清單，下次打開那個專業視窗時改成乾淨的；有篩選時也一樣
  - **未實機驗證**：這三個函式對別人的配方 ID 是否也有答案。沒有的話，別人的舊清單要等對方升級到 0.9.6、打開專業視窗後才會變乾淨
- **圖示**：依序用做出來的物品圖示（`GetRecipeSchematic(id, false).outputItemID` → `C_Item.GetItemIconByID`，沒有的話 `GetItemIcon`）、專業視窗給的 `icon`、配方法術的圖示（`C_Spell.GetSpellTexture`），都沒有時用專業圖示。找到的才記在快取裡（物品資料可能晚一點才載入）

