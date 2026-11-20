# 永恆服（Interface 16001）API 查證：綠皮冒險工具箱用到的部分

- 查證：claude-addon 2026-11-17（GF-001-D2）
- 方法：只讀公開資料，沒有下載或執行任何插件，也沒有進遊戲
- 狀態定義：
  - **已查證**：社群從遊戲客戶端實際傾印（dump）出來的資料中有這一項
  - **推測**：沒有直接證據，但從同系列 API 或其他插件的用法推得出來
  - **未知**：找不到資料
- 不論哪一種狀態，最後都要以 GF-001-B 實機測試為準

## 來源

| 代號 | 來源 | 內容與時間 |
| --- | --- | --- |
| FA | [zmarotrix/ForeverAPI](https://github.com/zmarotrix/ForeverAPI) | 用 probe 插件從客戶端 **1.60.1.70862**（enUS）傾印出的資料所產生的文件，2026-11-08 產生。README 寫明「沒有遊戲證實就不寫成事實」。本文引用其中的 `docs/systems/*.md`、`docs/events.md`、`docs/relocated.md`、`docs/globals-undocumented.md`（後者只列 Blizzard 官方文件沒寫的全域函式）。 |
| FPP | [xIGBClutchIx/ForeverPlusPlus `docs/forever-api.md`](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md) | 實際插件作者的筆記，涵蓋 build 70009–70755（2026-09-23～11-03） |
| WFG | [wowforeverguides.com/addons/api-cheatsheet](https://wowforeverguides.com/addons/api-cheatsheet)、[developers](https://wowforeverguides.com/addons/developers) | 社群指南，多半寫於 beta 69913 時期 |
| WW | [warcraft.wiki.gg 斜線指令](https://warcraft.wiki.gg/wiki/Extracting_info_from_a_slash_command) | Mainline 斜線指令機制 |

**基本前提（已查證）**：永恆服用的是**現代 Mainline 系列的 API**，不是經典版的 API。`GetBuildInfo()` 回傳 `"1.60.1", <build>, <date>, 16001`，`WOW_PROJECT_ID` 為 18（FPP）。所以經典版才有的舊全域函式，有一部分在永恆服已經移除，另外還有 Mainline 的「secret value」限制。

## 逐項結果

| 項目 | 狀態 | 依據 | AddOn 的處理 |
| --- | --- | --- | --- |
| `GetProfessions` | 已查證 | FA globals-undocumented：存在，呼叫後回傳 **7 個值** | 讀取回傳的每一個索引，不再只讀前 6 個 |
| `GetProfessionInfo(index)` | 已查證存在；回傳順序是推測 | FA：存在，用法是 `GetProfessionInfo(index)`。回傳順序沒有傾印，沿用 Mainline 的 `name, icon, rank, max, …, skillLine` | 包在 pcall 裡，型別不符時記為 nil；出錯時整份專業記為空陣列，不報錯 |
| `GetNumSkillLines`、`GetSkillLineInfo`（全域） | **已查證：已移除** | FA relocated.md「Gone on Forever」，改由 `C_SkillInfo` 提供；WFG 也說 69913 沒有 | 保留這條路，只在經典版客戶端使用 |
| `C_SkillInfo.GetNumSkillLines`、`C_SkillInfo.GetSkillLineInfo(i)` | 已查證 | FA SkillInfo.md：後者回傳**一個 table**，含 `name, isHeader, rank, maxRank, skillID…` | **新增**為第 2 個備用來源（原本的 v0.4.0 沒有這條） |
| `C_Club.GetGuildClubId`、`GetClubMembers`、`GetMemberInfo` | 已查證 | FA Club.md | 原本就有 pcall；名字和 GUID 改用安全讀取 |
| `ClubMemberInfo` 的 `race`、`profession1ID/Name/Rank`、`profession2*` | 已查證 | FA Club.md 的 ClubMemberInfo 結構 | 照常使用；型別不符時記為 nil |
| `C_GuildInfo.GuildRoster()` | 已查證 | FA GuildInfo.md | 優先使用 |
| `GuildRoster()`（全域） | 推測：已移除 | FA 全域清單裡沒有（只有 `CloseGuildRoster` 等） | 只在沒有 C_GuildInfo 時才用，原本就有判斷 |
| `GetGuildRosterInfo(i)` | 已查證存在；**回傳順序未知** | FA 只記錄了「Usage: GetGuildRosterInfo(index)」，沒有傾印回傳值 | 沿用 Mainline 的 17 個值。**新增驗證**：guid 必須是 `Player-` 開頭，classToken 必須是全大寫英文，等級必須是數字，名字和位置必須是字串，否則記為 nil 或空值。順序錯了也不會寫進錯誤的欄位，只會變成空值。要實機確認 |
| `GetNumGuildMembers` | 已查證 | FA：回傳 2 個數字 | 加上數字驗證 |
| `GetGuildInfo("player")` | 已查證 | FA | 用 `ns.call` 包起來 |
| `IsInGuild` | **未知** | FA 的 GuildInfo.md 和全域清單都沒有 | **新增**：如果沒有 `IsInGuild`，改用 `GetGuildInfo("player")` 有沒有值來判斷，再不行用 `IsPlayerInGuildFromGUID`（FA Unit.md 已查證） |
| `C_CreatureInfo.GetRaceInfo` | 已查證 | FA CreatureInfo.md，回傳 `{clientFileString, raceID, raceName}` | 照常使用 |
| `UnitFactionGroup`、`UnitRace`、`UnitClass`、`UnitGUID`、`UnitName`、`UnitLevel` | 已查證存在 | FA Unit.md；WFG 提醒 `UnitFactionGroup` 和 `UnitName` 可能是 secret | 全部改用 `ns.call` 加上 `ns.str`／`ns.num`。secret 值當成沒有 |
| `issecretvalue` | 已查證 | FA FrameScript.md | `ns.str`／`ns.num` 用它來過濾 |
| `GetPlayerInfoByGUID` | 推測：存在 | FA 沒有收錄；FPP 的 `Lib/Players.lua` 有用到它的第 7 個回傳值 | 原本就有判斷函式存不存在和 pcall |
| `C_TradeSkillUI.GetTradeSkillDisplayName` | 已查證 | FA TradeSkillUI.md | 原本就有 pcall |
| `GetBuildInfo` | 已查證 | FA Build.md、FPP | 第 4 個值是 16001 |
| `InCombatLockdown` | 已查證 | FA、WFG | 照常使用 |
| `C_Timer.After` | **推測：存在** | FA 沒有 Timer 的文件；WFG 範例程式有用到 | **新增** `ns.after`：沒有 `C_Timer` 時改用 OnUpdate 計時 |
| `GetCursorPosition` | 已查證 | FA Input.md | 照常使用（只有拖曳小地圖按鈕時會用到） |
| `SKILL_LINES_CHANGED` | 已查證 | FA SkillInfo.md（觀察到 201 次） | 照常使用 |
| `PLAYER_LEVEL_UP` | 已查證 | FA events.md | 照常使用 |
| `PLAYER_GUILD_UPDATE` | 已查證 | FA GuildInfo.md | 照常使用 |
| `PLAYER_LOGOUT` | 已查證 | FA events.md；WFG「存檔前的最後一個事件」 | 照常使用 |
| `PLAYER_LOGIN`、`ADDON_LOADED`、`PLAYER_REGEN_ENABLED`、`INITIAL_CLUBS_LOADED` | 已查證 | FA events.md | 照常使用 |
| `GUILD_ROSTER_UPDATE` | 已查證 | FA GuildInfo.md，參數是 `canRequestRosterUpdate` | 照常使用 |
| SavedVariables | 已查證可正常存讀 | FPP：beta 早期有寫入後讀不回來的問題，2026-09-24 已修好。WFG：會在 `ADDON_LOADED` 之前載入 | 照常使用 |
| `BasicFrameTemplateWithInset`、`UIPanelButtonTemplate`、`InputBoxTemplate`、`UIPanelScrollFrameTemplate` | 推測：存在 | Mainline 都有這些範本；FA 只出現範本的原始檔名，沒有範本清單 | **新增** `ns.createFrame`：找不到範本時改建一般框架，並自己補上背景、標題和關閉鈕 |
| `GetZoneText`、`GetSubZoneText`、`GetRealZoneText`（GF-001-D6） | **未知** | FA 的 globals-undocumented.md 和 relocated.md 都沒有。前者只列 Blizzard 官方文件沒寫的函式，所以「沒有列出」不代表不存在 | 用 `ns.call` 包起來；`GetZoneText` 取不到時改用 `GetRealZoneText`，再改用 `C_Map.GetBestMapForUnit` + `C_Map.GetMapInfo`；都取不到就不寫 `location` |
| `C_Map.GetBestMapForUnit` | 未知 | FA index 指向 MapUI.md，但查詢時那一頁回 503，沒有確認 | 只當備案，有判斷函式存不存在 |
| `C_ClassColor.GetClassColor` | 已查證 | FA ClassColor.md | 職業顏色的第一來源 |
| `RAID_CLASS_COLORS`、`CLASS_ICON_TCOORDS` | 未知 | FA 不列 FrameXML 表格 | 有就用；沒有就用 Icons.lua 內建的同樣數值 |
| `StatusBar` 元件 | 已查證 | FA widgets.md | 「我的角色」頁的技能點進度條 |
| `C_Texture.GetAtlasInfo` | 已查證 | FA TextureUtils.md | 沒有使用（只用一般材質路徑） |
| `GetFileIDFromPath` | 未知 | FA 全域清單沒有 | 原本小地圖圖示就有備案；圖示一律用 `SetTexture` 的回傳值判斷材質是否存在 |
| `C_Spell.GetSpellTexture` | 已查證：取代舊的全域 `GetSpellTexture` | FA relocated.md | 沒有使用 |
| `C_ChatInfo.RegisterAddonMessagePrefix(prefix)`（GF-001-D7） | 已查證 | FA ChatInfo.md：回傳 `RegisterAddonMessagePrefixResult`，prefix 不能是空字串 | 在 ADDON_LOADED 時註冊 `"GFTK"`，包在 pcall 裡 |
| `C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` | 已查證 | FA ChatInfo.md：回傳 `SendAddonMessageResult`；FA 沒有寫節流限制（只有 `SendAddonMessageLogged` 註明會被記錄與節流） | 只用 `"GUILD"`。自己節流：同一個角色 5 分鐘最多一次。每則 ≤ 255 bytes，需要時分段 |
| 全域 `SendAddonMessage`、`RegisterAddonMessagePrefix` | **已查證：已移除** | FA relocated.md「Gone on Forever」，改成 `C_ChatInfo.*` | 不使用 |
| `CHAT_MSG_ADDON` | 已查證 | FA ChatInfo.md：參數 `prefix, text, channel, sender, target, …`；觀察到 3846 次（752 次在戰鬥中） | `sender` 是資料的主角；只收 GUILD 頻道 |
| `C_ChatInfo.InChatMessagingLockdown`、`AreOutgoingAddonChatMessagesRestricted` | 已查證 | FA ChatInfo.md | 送出前檢查，受限時不送。**GF-001-D10**：GuildForge 在 Forever 實測 `AreOutgoingAddonChatMessagesRestricted()` 幾乎一直是 true、訊息照樣送得到，所以 0.9.0 起只在副本裡參考（`Comm.lua` 和 `Share.lua`） |
| **備案**（沒有 `C_ChatInfo` 時） | — | — | 互傳整個關閉，其他功能照常；不改用其他頻道 |
| `C_UI.Reload()` | 已查證存在，**但插件程式不能直接呼叫** | FA UI.md 只寫存在。owner 實測 0.8.0（2026-11-20）：從工具箱自己的按鈕 OnClick 呼叫，遊戲顯示「功能因插件失效」（ADDON_ACTION_BLOCKED） | 0.8.1 起不再直接呼叫（GF-001-D8），改用下面的安全按鈕跑 `/reload` 巨集；0.8.2 起連按鈕都拿掉（GF-001-D9，D-012），工具箱完全不重新載入 |
| `ReloadUI`（全域） | 已查證存在（FrameXML 函式） | FA ui-functions.md：`ReloadUI`（`Blizzard_SharedXML/InterfaceUtil.lua`）。推測一樣受保護 | 不使用 |
| `SecureActionButtonTemplate`（GF-001-D8） | **推測：有** | FA 只列函式，不列範本名稱。但 ui-functions.md 列出 `SecureActionButton_OnClick`、`SecureActionButton_ShouldUseOnKeyDown`、`SecureButton_GetModifiedAttribute` 等，都在 `Blizzard_FrameXML/SecureTemplates.lua`；這個檔案就是定義此範本的地方 | 0.8.1 的「同步到網站」確認框（0.8.2 起拿掉）、自己專業的點擊區都用它。`RegisterForClicks("AnyUp", "AnyDown")`，不管「按下時施放」怎麼設都能觸發。建立失敗時：確認框改成只記錄並提示輸入 `/reload`；專業不能點 |
| `type="macro"` + `macrotext` | 推測：可用 | SecureTemplates.lua 用到 `RunMacro`（FA globals-undocumented.md）；`C_Macro.RunMacroText` 已查證（FA UIMacros.md） | 0.8.1 用過：`macrotext = "/reload"`。**0.8.2 起不再使用**（按鈕已拿掉，GF-001-D9） |
| `type="spell"` + `spell` | 推測：可用 | SecureTemplates.lua 用到的 `CastSpellByName`、`CastSpellByID` 都在 FA globals-undocumented.md | 用法術**名稱**（會施放角色會的那一級），屬性只在戰鬥外設定 |
| `C_Spell.GetSpellName(spellID)`、`C_Spell.GetSpellInfo(spellID)` | 已查證 | FA Spell.md：後者回傳一個 table（`name, iconID, castTime, …, spellID`），戰鬥中也能用 | 專業法術名稱從這裡取，不寫死中文。對照表是 skillLineID → 第一級法術 ID（鍛造 2018、製皮 2108、裁縫 3908、工程學 4036、鍊金術 2259、附魔 7411、烹飪 2550、急救 3273、採礦 → 熔煉 2656）。**法術 ID 是推測**（經典版的編號），要實機 `/dump C_Spell.GetSpellName(2018)` 確認 |
| 全域 `GetSpellInfo` | **已查證：已移除** | FA relocated.md，改成 `C_Spell.GetSpellInfo` | 只當最後備案 |
| `C_TradeSkillUI.OpenTradeSkill(skillLineID)` | 已查證存在 | FA TradeSkillUI.md；是否受保護未知 | 沒有使用（照指示用安全按鈕施放法術）；如果法術的方式在實機不行，這是下一個可以試的 |
| `PLAYER_REGEN_DISABLED` 時 `InCombatLockdown()` | 推測：還是 false | Mainline 的行為：這個事件在鎖定開始前觸發，是最後可以隱藏安全按鈕的時機 | 這個事件裡先設工具箱自己的戰鬥旗標，再隱藏、取消錨點所有安全按鈕並關掉確認框；戰鬥中完全不碰它們 |
| `ADDON_ACTION_BLOCKED` 事件 | 已查證 | FA events.md、RestrictedActions.md | 沒有監聽；離線測試的 mock 會在插件程式直接呼叫 `C_UI.Reload`／`ReloadUI`，或戰鬥中改安全按鈕時丟出這個錯誤 |
| `StaticPopupDialogs`、`StaticPopup_Show` | 未知 | FA ui-functions.md 抓不到內容 | 不使用；確認框是工具箱自己做的小視窗（0.8.1 起名稱 `GreenFangToolkit_SyncConfirm`） |
| 斜線指令 `/gf` | 推測：可用 | WW 的 `SLASH_<KEY>n` 機制；FA 的 probe 用 `/fapi`，也是同一套機制 | — |
| 斜線指令 `/綠皮`（非 ASCII） | **推測** | 找不到任何資料。聊天框比對指令時會轉換大小寫，對 UTF-8 中文應該沒有影響，但沒有證據 | 一定能用的是 `/gf`。`/綠皮` 只是第二個別名，失敗也不影響功能 |

## 新增的離線測試（`tests/addon/run.lua` 的「16001 fallbacks」段）

涵蓋以下情況：
- 沒有 `IsInGuild`，在公會內和不在公會兩種
- 沒有 `C_Timer`（改用 OnUpdate 執行每一個延遲步驟）
- 只有 `C_SkillInfo` table 版本的技能清單
- `GetProfessions` 回傳 7 個值，中間有空的
- `GetProfessionInfo` 呼叫出錯
- secret 值（陣營、位置、會階）
- 沒有框架範本
- 沒有 `C_Club`、`C_CreatureInfo`、`GetPlayerInfoByGUID`
- `GetGuildRosterInfo` 回傳順序錯一格

合計 33 個測試全部通過。

## 實機要特別確認（已在 QUESTIONS 提給 claude-pm，請整合進 GF-001-B A 段）

1. `/dump GetGuildRosterInfo(1)`：確認第 1、2、4、5、6、9、11、17 個值分別是名字、會階、等級、職業、位置、在線狀態、職業代碼、GUID
2. `/dump GetProfessions()` 和 `/dump GetProfessionInfo((GetProfessions()))`：確認第 1、3、4、7 個值是名稱、目前技能點、上限、skillLineID
3. `/dump IsInGuild`：看是不是 nil。是 nil 的話，備用判斷要正常運作，`/gf sync status` 才會有名冊那一筆
4. `/dump C_Timer and C_Timer.After`：看有沒有這個函式
5. 輸入 `/綠皮`：看會不會開啟視窗（失敗不影響功能，記錄結果就好）
6. 名冊視窗、匯出視窗有沒有正常的外框和標題。如果看到深色方框加上「X」，代表用的是備用框架
7. SavedVariables 的 outbox 裡，`uploader.faction` 不能是空字串。空字串代表 `UnitFactionGroup` 回傳的是 secret 值
8. 練一次技能點、升一級、`/reload` 之後，`character.self` 有跟著更新，藉此確認 `SKILL_LINES_CHANGED`、`PLAYER_LEVEL_UP`、`PLAYER_LOGOUT` 這幾個事件會觸發
| `GetServerTime()`（GF-001-D10） | 已查證（✅） | FA SystemTime.md | 分享記錄的時間 `t`；沒有時退回 `time()` |
| `SendAddonMessage(prefix, msg, "WHISPER", 名字-伺服器)`（GF-001-D12） | 函式已查證；WHISPER 給公會成員**推測可用** | FA ChatInfo.md | 回答請求的資料只 WHISPER 給 0.9.2 以上、剛送過請求的人；對象用名冊的完整名字 |
| `ChatFrameUtil.AddMessageEventFilter`／`ChatFrame_AddMessageEventFilter`（GF-001-D12） | 已查證：舊名是 Blizzard_Deprecated 的 shim | FA relocated.md、globals-undocumented.md | 先用新名，沒有時用舊名；只過濾我們 30 秒內 WHISPER 過的人的「沒有名為 X 的玩家」 |
| `ERR_CHAT_PLAYER_NOT_FOUND_S`（GF-001-D12） | 推測：有 | FA 沒有列出常數 | 用它組比對樣式；沒有時用英文預設 |
