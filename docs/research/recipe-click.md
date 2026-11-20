# 點配方可以做什麼（GF-001-D19，AddOn 0.9.4，公開版 0.10.0）

- 查證：claude-addon 2026-11-20
- 方法：只讀公開資料，沒有進遊戲。來源和 `forever-api-16001.md` 相同，主要是 FA（[zmarotrix/ForeverAPI](https://github.com/zmarotrix/ForeverAPI)，客戶端 1.60.1 的傾印）
- 狀態：全部**未實機驗證**，要照 `tests/addon/MANUAL.md` §3p 在遊戲裡確認

## 結論

| 想做的事 | 做法 | 依據 | 狀態 |
|---|---|---|---|
| 滑鼠移到配方：看配方內容 | `GameTooltip:SetSpellByID(配方 ID)`（0.9.0 起就有） | 配方 ID 就是製作法術的 ID | 0.9.x 已在用；是否列出材料要看客戶端 |
| **點一下**：把配方說明釘在畫面上 | `ItemRefTooltip:SetHyperlink(連結)`，連結先用 `C_TradeSkillUI.GetRecipeLink(id)`，沒有的話用 `C_Spell.GetSpellLink(id)`，都沒有就用 `spell:<id>` | FA TradeSkillUI.md：`GetRecipeLink` 存在（沒有說明文件）；Spell.md：`C_Spell.GetSpellLink` 已查證 | 推測可用。客戶端沒有 `ItemRefTooltip` 時什麼都不做 |
| **Shift＋點**：把配方貼到聊天 | 同上的連結，用 `ChatFrameUtil.InsertLink`（舊名 `ChatEdit_InsertLink`）；聊天框沒開時用 `ChatFrameUtil.OpenChat`（舊名 `ChatFrame_OpenChat`）打開並放進去 | FA relocated.md：兩個舊名都還在（相容層） | 推測可用 |
| **「密語」按鈕**：問在線、會做的人 | `ChatFrameUtil.SendTellWithMessage`（舊名 `ChatFrame_SendTellWithMessage`）打開對他的密語，內容是「可以幫我做〔配方〕嗎？」；沒有的話用 `SendTell` 只打開密語 | FA relocated.md、globals-undocumented.md | 推測可用。**工具箱不會自己送出**，要玩家按 Enter |
| **「打開」按鈕**：在自己的專業視窗裡打開這個配方 | `C_TradeSkillUI.OpenRecipe(配方 ID)`，只在戰鬥外、而且是自己會的配方 | FA TradeSkillUI.md：已查證存在 | **不確定**：沒有資料說它是不是受保護的函式。如果實機出現「功能因插件失效」，下一版就拿掉這個按鈕 |

## 做不到或沒做的

- **列出材料**：`C_TradeSkillUI.GetRecipeSchematic` 存在，但只對**自己開著的專業視窗**裡的配方可靠；別人的配方我們只有 ID，沒有材料資料。所以材料只靠滑鼠提示（客戶端自己的法術說明）
- **配方分類、需要的技能等級**：分享的資料只有配方 ID。要做的話得在讀自己的專業視窗時多記分類和等級，而且要改分享格式（Share.lua 的 `R` 記錄）。這次沒做
- **打開別人的專業視窗**（看他的配方清單）：需要對方把專業連結貼到聊天，工具箱不能代替
- **自動密語或自動送出**：不做。所有訊息都由玩家自己送

## 畫面上的樣子

- 「密語」「打開」只在滑鼠移到那一列時出現在右邊（一頁可能有幾百列，每列都做按鈕會拖慢畫面）
- 沒有在線、會做的人（自己不算）就沒有「密語」；不是自己會的配方、或在戰鬥中，就沒有「打開」
- 不另外加說明文字：Shift＋點貼到聊天是遊戲內通用的做法
