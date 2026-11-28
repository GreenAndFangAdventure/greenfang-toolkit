-- Probe (GF-PROBE: WORK-TALENT-PROBE, WORK-BANK-PROBE, GF-009-01).
-- /gftk probe records, in one go, which 16001 APIs and events this client
-- has, what the read-only ones return (types and field names only), whether
-- a bank or guild bank is open, and whether the Stranglethorn pages
-- (items 2725-2751) and quests 338-342 exist. /gftk probe bank adds a second
-- record while the bank or guild bank is open. The result is kept in
-- GreenFangToolkitDB.probe (GF Sync does not read it) and shown as copyable
-- text; the 同步與診斷 window has a short summary.
--
-- Safety: nothing runs in combat; no call changes state, spends money, sends
-- a request to the server or is restricted (no LoadConfig / CommitConfig /
-- SwitchTo* / ViewLoadout / NotifyInspect / QueryGuildBank* / PurchaseBankTab,
-- no trade or mail actions). Every call is wrapped in pcall.
-- Privacy: no character, account or guild names, no GUIDs, no item links or
-- import strings, no bag contents: only "exists", value types, field names,
-- counts and lengths. Item and quest names are kept only for the fixed
-- public game IDs below.
-- Evidence: GreenFang_Toolkit docs/research/GF-PROBE_api-evidence.md.

local _, ns = ...

local Probe = {}
ns.Probe = Probe

Probe.SCHEMA = 1
Probe.PAGE_ITEMS = { first = 2725, last = 2751 } -- 2724 + page 1..27 (classic data)
Probe.QUESTS = { 338, 339, 340, 341, 342 }
Probe.MAX_FIELDS = 40

-- Every name the probe checks for existence.
Probe.APIS = {
    -- talents and specialization
    "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
    "C_SpecializationInfo.GetActiveSpecGroup", "C_SpecializationInfo.GetCombatConfigIDForSpecGroup",
    "C_SpecializationInfo.GetInspectSpecialization", "C_SpecializationInfo.GetTalentInfo",
    "C_SpecializationInfo.IsInitialized", "C_SpecializationInfo.CanPlayerUseTalentUI",
    "C_ClassTalents.GetActiveConfigID", "C_ClassTalents.InitializeViewLoadout", "C_ClassTalents.ViewLoadout",
    "C_ClassTalents.GetConfigIDsBySpecID", "C_ClassTalents.GetTraitTreeForSpec",
    "C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo",
    "C_Traits.GetDefinitionInfo", "C_Traits.GetTreeInfo", "C_Traits.GetGroupDisplayInfoByTreeID",
    "C_Traits.GetGroupCurrencyInfo", "C_Traits.GetTreeCurrencyInfo", "C_Traits.GenerateImportString",
    "C_Traits.GenerateInspectImportString", "C_Traits.HasValidInspectData", "C_Traits.GetLoadoutSerializationVersion",
    "GetSpecializationInfoForSpecID", "GetNumSpecializations", "IsDualSpecUnlocked",
    "GetTalentInfo", "GetTalentTabInfo", "GetNumTalentTabs", "GetActiveTalentGroup", "GetUnspentTalentPoints",
    "LinkUtil.FormatLink", "LinkTypes.TalentBuild", "PlayerSpellsFrame_LoadUI", "PlayerSpellsUtil.OpenToClassTalentsTab",
    "PlayerSpellsUtil.InspectLoadout",
    -- GF-011-B 「天賦樹」: the ways into the game's own talent window
    "PlayerSpellsUtil.ToggleClassTalentFrame", "TogglePlayerSpellsFrame", "ToggleTalentFrame", "SetItemRef",
    "HideUIPanel",
    -- inspect
    "CanInspect", "NotifyInspect", "ClearInspectPlayer", "InspectUnit", "InspectFrame_Show",
    "C_PaperDollInfo.GetInspectItemLevel", "C_PaperDollInfo.GetInspectGuildInfo",
    -- bank and guild bank
    "C_Bank.CanViewBank", "C_Bank.CanUseBank", "C_Bank.FetchNumPurchasedBankTabs", "C_Bank.FetchPurchasedBankTabIDs",
    "C_Bank.FetchPurchasedBankTabData", "C_Bank.FetchViewableBankTypes", "C_Bank.AreAnyBankTypesViewable",
    "C_Bank.FetchDepositedMoney", "C_PlayerInteractionManager.IsInteractingWithNpcOfType",
    "GetNumBankSlots", "BankButtonIDToInvSlotID",
    "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
    "GetCurrentGuildBankTab", "QueryGuildBankTab", "GetGuildBankMoney", "GetGuildBankWithdrawMoney",
    "CanWithdrawGuildBankMoney", "GetGuildBankTabPermissions", "GetNumGuildBankTransactions", "QueryGuildBankLog",
    "GuildBankFrame_LoadUI", "CanGuildBankRepair",
    -- GF-017: the guild bank gold log (Forever Blizzard_GuildBankUI money log)
    "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction", "MAX_GUILDBANK_TABS",
    -- bags and items
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo", "C_Container.GetContainerItemID",
    "C_Container.GetContainerItemLink", "C_Container.GetContainerNumFreeSlots", "C_Container.GetBagName",
    "GetContainerItemInfo", "GetContainerNumSlots",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.DoesItemExistByID", "C_Item.IsItemDataCachedByID",
    "C_Item.RequestLoadItemDataByID", "C_Item.GetItemNameByID", "C_Item.GetItemCount", "C_Item.IsBound",
    "GetItemInfo", "GetItemInfoInstant", "GetItemCount", "ItemLocation.CreateFromBagAndSlot",
    -- quests
    "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.IsQuestFlaggedCompletedOnAccount",
    "C_QuestLog.GetQuestTagInfo", "C_QuestLog.GetSuggestedGroupSize", "C_QuestLog.GetInfo",
    "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetTitleForQuestID",
    "C_QuestLog.IsOnQuest", "C_QuestLog.IsComplete", "C_QuestLog.ReadyForTurnIn", "C_QuestLog.RequestLoadQuestByID",
    "C_QuestLog.GetQuestDifficultyLevel", "C_QuestLog.GetQuestType", "C_QuestLog.GetAllCompletedQuestIDs",
    "GetQuestLogTitle", "GetQuestTagInfo", "IsQuestFlaggedCompleted", "GetQuestsCompleted",
    -- mail and trade
    "C_Mail.CanCheckInbox", "C_Mail.HasInboxMoney", "C_Mail.IsCommandPending",
    "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "TakeInboxItem", "CheckInbox",
    "GetTradePlayerItemInfo", "GetTradeTargetItemInfo", "GetTradePlayerItemLink", "InitiateTrade",
    -- professions
    "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfo",
    "C_TradeSkillUI.GetProfessionInfoBySkillLineID", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.OpenTradeSkill",
    "C_TradeSkillUI.IsNPCCrafting", "C_TradeSkillUI.GetAllRecipeIDs", "GetProfessions", "GetProfessionInfo",
    "GetNumTradeSkills", "GetTradeSkillLine",
    -- GF-011-B 「製作」: the ways into the profession window
    "ProfessionsUtil.OpenProfessionFrameToRecipe", "C_TradeSkillUI.OpenRecipe", "OpenProfessionUIToSkillLine",
    "ProfessionsFrame_LoadUI", "C_TradeSkillUI.GetTradeSkillLineForRecipe", "C_TradeSkillUI.IsRecipeProfessionLearned",
    -- general
    "InCombatLockdown", "issecretvalue", "GetBuildInfo",
    -- GF-UI-K: the personnel file's race head (Icons.setPortrait)
    "UnitSex", "C_Texture.GetAtlasInfo", "C_CreatureInfo.GetRaceInfo",
    -- GF-UI-M: the character's own portrait (Icons.setUnitPortrait)
    "SetPortraitTexture", "UnitExists",
}

Probe.EVENTS = {
    "INSPECT_READY", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED",
    "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_TREE_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "CHARACTER_POINTS_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS",
    "GUILDBANKLOG_UPDATE", "GUILDBANK_UPDATE_MONEY",
    "GUILDBANK_UPDATE_WITHDRAWMONEY", -- GF-017
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
    "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT", "QUEST_ACCEPTED",
    "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_SUCCESS",
    "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED", -- GF-UI-M
}

-- Global frames whose existence / visibility is recorded.
Probe.FRAMES = {
    "BankFrame", "GuildBankFrame", "InspectFrame", "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame",
    "ProfessionsFrame", "TradeSkillFrame", "MailFrame", "TradeFrame", "GreenFangToolkit_MainWindow",
}

-- Enum.PlayerInteractionType (Forever docs): Banker 8, GuildBanker 10, MailInfo 17.
local BANKER, GUILD_BANKER = 8, 10

---------------------------------------------------------------------------
-- Pure helpers (offline tests)
---------------------------------------------------------------------------

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s == true
end

function Probe.typeOf(v)
    if v ~= nil and isSecret(v) then return "secret" end
    return type(v)
end

-- Resolve "A.B.C" from the global table; nil when any part is missing.
function Probe.resolve(path)
    local v = _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        local ok, nxt = pcall(function() return v[part] end)
        if not ok then return nil end
        v = nxt
    end
    return v
end

-- Sorted string keys of a table (at most MAX_FIELDS); a list gives "[n]".
function Probe.fields(t)
    if type(t) ~= "table" or isSecret(t) then return nil end
    local keys, n = {}, 0
    for k in pairs(t) do
        if type(k) == "string" then keys[#keys + 1] = k else n = n + 1 end
    end
    table.sort(keys)
    while #keys > Probe.MAX_FIELDS do table.remove(keys) end
    if #keys == 0 then
        if n == 0 then return "{}" end
        -- A list of tables: the first element's fields too.
        local first = t[1]
        local inner = (type(first) == "table" and not isSecret(first)) and Probe.fields(first) or nil
        return "[" .. n .. "]" .. (inner and not inner:find("^%[") and ("{" .. inner .. "}") or "")
    end
    local s = table.concat(keys, ",")
    if n > 0 then s = s .. ",[" .. n .. "]" end
    return s
end

local function count(t)
    if type(t) ~= "table" or isSecret(t) then return nil end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
Probe.count = count

-- Short error text without file paths.
local function errText(e)
    local s, n = tostring(e), 1
    while n > 0 do s, n = s:gsub("^[^\n]-:%d+: ", "", 1) end
    if #s > 80 then s = s:sub(1, 80) end
    return s
end

-- Call a function by path; returns summary, results.
-- summary: "nil" (missing), "err:<msg>", or "ok:<type>,<type>" with {fields} of the first table.
function Probe.try(path, ...)
    local fn = Probe.resolve(path)
    if type(fn) ~= "function" then return "nil" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "err:" .. errText(res[2]) end
    local n = table.maxn(res) - 1
    if n <= 0 then return "ok:-" end
    local types, fieldText = {}, nil
    for i = 2, math.min(n + 1, 16) do
        local v = res[i]
        types[#types + 1] = Probe.typeOf(v)
        if not fieldText and type(v) == "table" then fieldText = Probe.fields(v) end
    end
    local s = "ok:" .. table.concat(types, ",")
    if fieldText then s = s .. "{" .. fieldText .. "}" end
    return s, unpack(res, 2, n + 1)
end

local function plain(v)
    if v == nil or isSecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------

-- existing = true: only a store that is already there (the event counters
-- start after the first /gftk probe, so a plain login writes nothing).
function Probe.store(existing)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.probe) ~= "table" then
        if existing then return nil end
        db.probe = {}
    end
    local p = db.probe
    p.schema = Probe.SCHEMA
    if type(p.seen) ~= "table" then p.seen = {} end
    return p
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

local function apis()
    local have, missing = {}, {}
    for _, path in ipairs(Probe.APIS) do
        local t = Probe.typeOf(Probe.resolve(path))
        if t == "nil" then missing[#missing + 1] = path else have[#have + 1] = path .. "=" .. t end
    end
    return { total = #Probe.APIS, present = #have, missing = missing, have = have }
end

local probeFrame
local function events()
    probeFrame = probeFrame or CreateFrame("Frame")
    local missing, ok = {}, 0
    for _, e in ipairs(Probe.EVENTS) do
        local good = pcall(probeFrame.RegisterEvent, probeFrame, e)
        if good then
            ok = ok + 1
            pcall(probeFrame.UnregisterEvent, probeFrame, e)
        else
            missing[#missing + 1] = e
        end
    end
    return { total = #Probe.EVENTS, ok = ok, missing = missing }
end

local function frames()
    local out = {}
    for _, name in ipairs(Probe.FRAMES) do
        local f = _G[name]
        local s = "nil"
        if type(f) == "table" then
            local okShown, shown = pcall(function() return f:IsShown() end)
            s = (okShown and shown) and "shown" or "hidden"
        end
        out[#out + 1] = name .. "=" .. s
    end
    return out
end

local function talents()
    local c = {}
    local _, spec
    c.isInitialized = Probe.try("C_SpecializationInfo.IsInitialized")
    c.canUseTalentUI = Probe.try("C_SpecializationInfo.CanPlayerUseTalentUI")
    c.getSpecialization, spec = Probe.try("C_SpecializationInfo.GetSpecialization")
    spec = plain(spec)
    if type(spec) == "number" then
        c.getSpecializationInfo = Probe.try("C_SpecializationInfo.GetSpecializationInfo", spec)
    end
    local group, cfgCombat, cfgActive
    c.getActiveSpecGroup, group = Probe.try("C_SpecializationInfo.GetActiveSpecGroup")
    group = plain(group)
    if type(group) == "number" then
        c.getCombatConfigIDForSpecGroup, cfgCombat = Probe.try("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", group)
    end
    c.getActiveConfigID, cfgActive = Probe.try("C_ClassTalents.GetActiveConfigID")
    c.isDualSpecUnlocked = Probe.try("IsDualSpecUnlocked")
    c.getNumSpecializations = Probe.try("GetNumSpecializations")
    local cfg = plain(cfgCombat) or plain(cfgActive)
    c.sameConfig = tostring(plain(cfgCombat) ~= nil and plain(cfgCombat) == plain(cfgActive))
    if type(cfg) == "number" then
        local info, tree
        c.getConfigInfo, info = Probe.try("C_Traits.GetConfigInfo", cfg)
        if type(info) == "table" and type(info.treeIDs) == "table" then
            c.treeCount = #info.treeIDs
            tree = plain(info.treeIDs[1])
        end
        if type(tree) == "number" then
            local nodes, groups
            c.getTreeInfo = Probe.try("C_Traits.GetTreeInfo", cfg, tree)
            c.getTreeNodes, nodes = Probe.try("C_Traits.GetTreeNodes", tree)
            c.getGroupDisplayInfoByTreeID, groups = Probe.try("C_Traits.GetGroupDisplayInfoByTreeID", tree)
            c.groupCount = count(groups)
            c.getTreeCurrencyInfo = Probe.try("C_Traits.GetTreeCurrencyInfo", cfg, tree, false)
            if type(nodes) == "table" then
                c.nodeCount = #nodes
                local ranked, visible = 0, 0
                local nodeFn = Probe.resolve("C_Traits.GetNodeInfo")
                for i = 1, math.min(#nodes, 600) do
                    local okN, ni = pcall(nodeFn, cfg, nodes[i])
                    if okN and type(ni) == "table" then
                        if (plain(ni.activeRank) or plain(ni.currentRank) or 0) > 0 then ranked = ranked + 1 end
                        if ni.isVisible then visible = visible + 1 end
                    end
                end
                c.nodesWithRank, c.nodesVisible = ranked, visible
                local node
                c.getNodeInfo, node = Probe.try("C_Traits.GetNodeInfo", cfg, nodes[1])
                local entryID = type(node) == "table" and type(node.entryIDs) == "table" and plain(node.entryIDs[1]) or nil
                if entryID then
                    local entry
                    c.getEntryInfo, entry = Probe.try("C_Traits.GetEntryInfo", cfg, entryID)
                    local def = type(entry) == "table" and plain(entry.definitionID) or nil
                    if def then c.getDefinitionInfo = Probe.try("C_Traits.GetDefinitionInfo", def) end
                end
            end
            if type(groups) == "table" and type(groups[1]) == "table" then
                local ids = {}
                for _, g in ipairs(groups) do if type(g) == "table" and plain(g.groupID) then ids[#ids + 1] = g.groupID end end
                if #ids > 0 then c.getGroupCurrencyInfo = Probe.try("C_Traits.GetGroupCurrencyInfo", cfg, ids) end
            end
        end
        local _, str = Probe.try("C_Traits.GenerateImportString", cfg)
        c.importStringLength = type(str) == "string" and #str or Probe.typeOf(str)
    end
    c.serializationVersion = tostring(plain((select(2, Probe.try("C_Traits.GetLoadoutSerializationVersion")))))
    c.linkTypeTalentBuild = tostring(plain(Probe.resolve("LinkTypes.TalentBuild")))
    c.hasValidInspectData = Probe.try("C_Traits.HasValidInspectData")
    -- GF-011: what the roster reads (points per tab, GF-011-C: Talents.assignTabs),
    -- and the chat functions the 「天賦連結」 action uses.
    if ns.Talents then
        local okT, line = pcall(ns.Talents.summaryLine)
        c.gf011 = okT and line or ("err:" .. errText(line))
    end
    c.chatInsertLink = Probe.typeOf((type(ChatFrameUtil) == "table" and ChatFrameUtil.InsertLink) or _G.ChatEdit_InsertLink)
    c.chatOpenChat = Probe.typeOf((type(ChatFrameUtil) == "table" and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat)
    -- Classic-style API (expected missing on Forever): existence only, no call.
    return c
end

local function unitIsPlayer(unit)
    local okE, e = pcall(UnitExists, unit)
    local okP, p = pcall(UnitIsPlayer, unit)
    return okE and e and okP and p and true or false
end

local function inspect()
    local c = {}
    c.targetIsPlayer = tostring(unitIsPlayer("target"))
    if c.targetIsPlayer == "true" then
        c.canInspectTarget = Probe.try("CanInspect", "target")
    end
    return c
end

local function interacting(kind)
    local _, v = Probe.try("C_PlayerInteractionManager.IsInteractingWithNpcOfType", kind)
    return plain(v) == true
end

local function frameShown(name)
    local f = _G[name]
    if type(f) ~= "table" then return false end
    local ok, s = pcall(function() return f:IsShown() end)
    return ok and s and true or false
end

function Probe.bankOpen()
    return interacting(BANKER) or frameShown("BankFrame")
end
function Probe.guildBankOpen()
    return interacting(GUILD_BANKER) or frameShown("GuildBankFrame")
end

-- Slots and used slots of one container; field names of the first item.
local function container(bag)
    local _, slots = Probe.try("C_Container.GetContainerNumSlots", bag)
    slots = plain(slots)
    if type(slots) ~= "number" then return nil end
    local used, fieldText, boundKnown = 0, nil, 0
    local infoFn = Probe.resolve("C_Container.GetContainerItemInfo")
    for slot = 1, math.min(slots, 200) do
        if type(infoFn) == "function" then
            local ok, info = pcall(infoFn, bag, slot)
            if ok and type(info) == "table" then
                used = used + 1
                if info.isBound ~= nil then boundKnown = boundKnown + 1 end
                fieldText = fieldText or Probe.fields(info)
            end
        end
    end
    return { slots = slots, used = used, boundKnown = boundKnown, fields = fieldText }
end

local function bags(includeBank)
    local out = {}
    local list = { 0, 1, 2, 3, 4, 5 }
    if includeBank then
        list[#list + 1] = -1 -- old BANK_CONTAINER
        for b = 6, 23 do list[#list + 1] = b end -- CharacterBankTab_1..9, AccountBankTab_1..9
    end
    for _, b in ipairs(list) do
        local r = container(b)
        if r and (r.slots > 0 or b <= 5) then
            out[#out + 1] = string.format("%d:%d/%d%s", b, r.used, r.slots, r.used > 0 and ("b" .. r.boundKnown) or "")
            out.fields = out.fields or r.fields
        end
    end
    return out
end

local function bank(deep)
    local c = {}
    c.bankOpen = tostring(Probe.bankOpen())
    c.guildBankOpen = tostring(Probe.guildBankOpen())
    c.interactBanker = tostring(interacting(BANKER))
    c.interactGuildBanker = tostring(interacting(GUILD_BANKER))
    c.anyViewable = Probe.try("C_Bank.AreAnyBankTypesViewable")
    local _, types = Probe.try("C_Bank.FetchViewableBankTypes")
    c.viewableTypes = type(types) == "table" and table.concat((function()
        local t = {}
        for _, v in ipairs(types) do t[#t + 1] = tostring(plain(v)) end
        return t
    end)(), ",") or Probe.typeOf(types)
    for _, bt in ipairs({ 0, 1, 2 }) do
        c["canViewBank" .. bt] = Probe.try("C_Bank.CanViewBank", bt)
        local _, n = Probe.try("C_Bank.FetchNumPurchasedBankTabs", bt)
        c["purchasedTabs" .. bt] = tostring(plain(n))
        if deep then
            c["tabData" .. bt] = Probe.try("C_Bank.FetchPurchasedBankTabData", bt)
        end
    end
    c.numBankSlots = Probe.try("GetNumBankSlots")
    local open = Probe.bankOpen()
    local b = bags(open)
    c.bags = table.concat(b, " ")
    c.containerItemFields = b.fields
    -- Guild bank: read-only calls on the current tab, only while it is open.
    c.numGuildBankTabs = Probe.try("GetNumGuildBankTabs")
    if Probe.guildBankOpen() then
        local _, tab = Probe.try("GetCurrentGuildBankTab")
        tab = plain(tab)
        c.currentGuildBankTab = tostring(tab)
        if type(tab) == "number" then
            c.guildBankTabInfo = Probe.try("GetGuildBankTabInfo", tab)
            local used, firstItem = 0, nil
            local fn = Probe.resolve("GetGuildBankItemInfo")
            for slot = 1, 98 do
                if type(fn) == "function" then
                    local ok, tex = pcall(fn, tab, slot)
                    if ok and tex ~= nil then
                        used = used + 1
                        firstItem = firstItem or slot
                    end
                end
            end
            c.guildBankUsedSlots = used
            if firstItem then
                c.guildBankItemInfo = Probe.try("GetGuildBankItemInfo", tab, firstItem)
                local _, link = Probe.try("GetGuildBankItemLink", tab, firstItem)
                c.guildBankItemLink = Probe.typeOf(link)
            end
        end
        c.guildBankMoney = Probe.try("GetGuildBankMoney")
        c.guildBankWithdrawMoney = Probe.try("GetGuildBankWithdrawMoney")
        c.canWithdrawGuildBankMoney = Probe.try("CanWithdrawGuildBankMoney")
        c.numGuildBankTransactions = Probe.try("GetNumGuildBankTransactions", tab or 1)
        -- GF-017: the gold log, read only (the money log tab asks the server for it;
        -- the probe never asks: what is there after that tab was opened, or after the
        -- toolkit's own request in GuildBank.lua). Types and counts only, no names.
        local _, nMoney = Probe.try("GetNumGuildBankMoneyTransactions")
        c.numGuildBankMoneyTransactions = Probe.typeOf(nMoney) .. ":" .. tostring(plain(nMoney))
        if type(plain(nMoney)) == "number" and plain(nMoney) > 0 then
            local summary, kind = Probe.try("GetGuildBankMoneyTransaction", 1)
            c.guildBankMoneyTransaction1 = summary
            kind = plain(kind)
            c.guildBankMoneyKind1 = (ns.GuildBank and type(kind) == "string" and ns.GuildBank.LETTER[kind]) and kind
                or Probe.typeOf(kind)
        end
        c.maxGuildBankTabs = tostring(plain(rawget(_G, "MAX_GUILDBANK_TABS")))
        c.toolkitGuildBank = ns.GuildBank and string.format("open=%s money=%s log=%s", tostring(ns.GuildBank.open),
            tostring(ns.GuildBank.lastMoney), tostring(ns.GuildBank.lastLog)) or "nil"
    end
    return c
end

-- GF-009-01: the Stranglethorn pages and quests.
local requested = {}
local function pageItem(id)
    local r = {}
    local _, exists = Probe.try("C_Item.DoesItemExistByID", id)
    local _, instant = Probe.try("C_Item.GetItemInfoInstant", id)
    if instant == nil then _, instant = Probe.try("GetItemInfoInstant", id) end
    r.exists = plain(exists) == true or plain(instant) ~= nil
    local _, cached = Probe.try("C_Item.IsItemDataCachedByID", id)
    r.cached = plain(cached)
    local getInfo = Probe.resolve("C_Item.GetItemInfo") or Probe.resolve("GetItemInfo")
    if type(getInfo) == "function" then
        local res = { pcall(getInfo, id) }
        if res[1] and res[2] ~= nil then
            r.name = plain(res[2])
            r.bindType = plain(res[15]) -- 14th return
            r.stack = plain(res[9])     -- 8th return: max stack
        end
    end
    if r.exists and r.name == nil and not requested[id] then
        requested[id] = true
        Probe.try("C_Item.RequestLoadItemDataByID", id)
    end
    -- Tradable: not bound (0) or bind on equip (2) / use (3); unknown without the data.
    if type(r.bindType) == "number" then
        r.trade = (r.bindType == 0 or r.bindType == 2 or r.bindType == 3) and "yes" or "no"
    else
        r.trade = "unknown"
    end
    return r
end

local function questInfo(id)
    local r = {}
    local _, title = Probe.try("C_QuestLog.GetTitleForQuestID", id)
    r.title = plain(title)
    if r.title == nil then Probe.try("C_QuestLog.RequestLoadQuestByID", id) end
    local _, done = Probe.try("C_QuestLog.IsQuestFlaggedCompleted", id)
    if done == nil then _, done = Probe.try("IsQuestFlaggedCompleted", id) end
    r.completed = plain(done)
    local _, on = Probe.try("C_QuestLog.IsOnQuest", id)
    r.onQuest = plain(on)
    local _, objectives = Probe.try("C_QuestLog.GetQuestObjectives", id)
    r.objectives = count(objectives)
    local _, size = Probe.try("C_QuestLog.GetSuggestedGroupSize", id)
    r.groupSize = plain(size)
    return r
end

local function stv()
    local pages, ok, tradable, cached = {}, 0, 0, 0
    for id = Probe.PAGE_ITEMS.first, Probe.PAGE_ITEMS.last do
        local r = pageItem(id)
        pages[id] = r
        if r.exists then ok = ok + 1 end
        if r.trade == "yes" then tradable = tradable + 1 end
        if r.name then cached = cached + 1 end
    end
    local quests = {}
    for _, id in ipairs(Probe.QUESTS) do quests[id] = questInfo(id) end
    return { pages = pages, quests = quests, pagesExist = ok, pagesTradable = tradable, pagesCached = cached }
end

-- Quest log: counts and field names only (titles are not kept).
local function questLog()
    local c = {}
    local _, shown, quests = Probe.try("C_QuestLog.GetNumQuestLogEntries")
    c.entries = tostring(plain(shown)) .. "/" .. tostring(plain(quests))
    local elite, group, tagged, objectives = 0, 0, 0, 0
    local n = type(plain(shown)) == "number" and math.min(shown, 60) or 0
    for i = 1, n do
        local _, info = Probe.try("C_QuestLog.GetInfo", i)
        if type(info) == "table" then
            c.infoFields = c.infoFields or Probe.fields(info)
            local qid = plain(info.questID)
            if not info.isHeader and type(qid) == "number" then
                if (plain(info.suggestedGroup) or 0) > 1 then group = group + 1 end
                local s, tag = Probe.try("C_QuestLog.GetQuestTagInfo", qid)
                if type(tag) == "table" then
                    tagged = tagged + 1
                    c.tagInfo = c.tagInfo or s
                    if tag.isElite then elite = elite + 1 end
                end
                local s2, obj = Probe.try("C_QuestLog.GetQuestObjectives", qid)
                if type(obj) == "table" and type(obj[1]) == "table" then
                    objectives = objectives + 1
                    c.objectiveFields = c.objectiveFields or Probe.fields(obj[1])
                elseif not c.objectivesCall then
                    c.objectivesCall = s2
                end
            end
        end
    end
    c.suggestedGroup, c.tagged, c.elite, c.withObjectives = group, tagged, elite, objectives
    return c
end

local function professions()
    local c = {}
    c.getProfessions = Probe.try("GetProfessions")
    c.baseProfessionInfo = Probe.try("C_TradeSkillUI.GetBaseProfessionInfo")
    c.isNPCCrafting = Probe.try("C_TradeSkillUI.IsNPCCrafting")
    c.tradeSkillOpen = tostring(frameShown("ProfessionsFrame") or frameShown("TradeSkillFrame"))
    c.toolkitShown = tostring(frameShown("GreenFangToolkit_MainWindow"))
    return c
end

local function mail()
    local c = {}
    c.canCheckInbox = Probe.try("C_Mail.CanCheckInbox")
    c.mailOpen = tostring(frameShown("MailFrame"))
    return c
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

-- GF-UI-K: which race-head atlases the client has (Icons.setPortrait): the
-- character's sex (2 male, 3 female), the race files of 天裔精靈 (raceID 96,
-- 95; public game data) and yes / no for every atlas name tried.
local function portraits()
    local I = ns.Icons
    local out = { sex = tostring((ns.call(rawget(_G, "UnitSex"), "player"))) } -- GF-UI-M: nil, not an error
    -- GF-UI-M: the own portrait: does the API exist, what the page shows
    -- (unit = the own portrait, atlas = race head, class = class icon; nil =
    -- the page was not opened yet), how often the game asked for a redraw.
    out.unitPortrait = type(rawget(_G, "SetPortraitTexture")) == "function" and "yes" or "no"
    local Ch = ns.Character
    out.shown = Ch and tostring(Ch.portrait) or "nil"
    out.redraws = Ch and tostring(Ch.portraitRedraws or 0) or "0"
    -- GF-UI-M: the left bar's 職工檔案 icon (nil: the file icon).
    out.nav = tostring(I.navPortraitAtlas())
    for _, id in ipairs(I.PORTRAIT_FEMALE_RACES) do out["race" .. id] = I.raceFile(id) or "nil" end
    for _, sex in ipairs({ I.SEX_MALE, I.SEX_FEMALE }) do
        for _, name in ipairs(I.portraitAtlases(sex)) do out[name] = I.atlasExists(name) and "yes" or "no" end
    end
    return out
end
Probe.portraits = portraits

local function header(kind)
    local res = { pcall(GetBuildInfo) }
    return {
        kind = kind, at = ns.now(), version = ns.VERSION,
        build = res[1] and tostring(plain(res[3])) or "?",
        gameVersion = res[1] and tostring(plain(res[2])) or "?",
        interface = res[1] and tostring(plain(res[5])) or tostring(ns.Data and ns.Data.interface and ns.Data.interface()),
    }
end

function Probe.inCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, v = pcall(InCombatLockdown)
    return ok and v == true
end

-- kind: "main" (everything) or "bank" (bank / guild bank and bags again).
function Probe.run(kind)
    kind = kind == "bank" and "bank" or "main"
    local p = Probe.store()
    if not p then return nil, "nodb" end
    if Probe.inCombat() then return nil, "combat" end
    local r = header(kind)
    local function section(name, fn, ...)
        local ok, v = pcall(fn, ...)
        r[name] = ok and v or { error = errText(v) }
    end
    if kind == "main" then
        section("apis", apis)
        section("events", events)
        section("talents", talents)
        section("inspect", inspect)
        section("stv", stv)
        section("questLog", questLog)
        section("professions", professions)
        section("mail", mail)
        section("portraits", portraits)
    end
    section("bank", bank, kind == "bank")
    section("frames", frames)
    p[kind] = r
    return r
end

---------------------------------------------------------------------------
-- What the client sends meanwhile (counts only; no GUIDs).
---------------------------------------------------------------------------

local function bump(name)
    local p = Probe.store(true)
    if not p then return nil end
    local s = p.seen
    s[name] = (tonumber(s[name]) or 0) + 1
    s[name .. "At"] = ns.now()
    return s
end

function Probe.onEvent(event, arg1)
    if event == "INSPECT_READY" then
        local s = bump("INSPECT_READY")
        if not s then return end
        -- Right after INSPECT_READY the inspect data is valid: record what it gives.
        local unit
        for _, u in ipairs({ "target", "mouseover", "focus" }) do
            local ok, g = pcall(UnitGUID, u)
            if ok and g ~= nil and arg1 ~= nil and not isSecret(g) and not isSecret(arg1) and g == arg1 then unit = u; break end
        end
        local i = { at = ns.now(), unit = unit or "other" }
        i.hasValidInspectData = Probe.try("C_Traits.HasValidInspectData")
        if unit then
            local _, str = Probe.try("C_Traits.GenerateInspectImportString", unit)
            i.importStringLength = type(str) == "string" and #str or Probe.typeOf(str)
            i.inspectSpecialization = Probe.try("C_SpecializationInfo.GetInspectSpecialization", unit)
            i.inspectItemLevel = Probe.try("C_PaperDollInfo.GetInspectItemLevel", unit)
            i.activeSpecGroupInspect = Probe.try("C_SpecializationInfo.GetActiveSpecGroup", true)
        end
        s.inspect = i
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local t = plain(arg1)
        if t == BANKER or t == GUILD_BANKER then bump("interaction" .. t) end
    elseif event == "TRADE_SKILL_SHOW" then
        bump(event)
        -- GF-PROBE (PM handoff §3 item 5): is the toolkit still shown after the profession window opens?
        local before = frameShown("GreenFangToolkit_MainWindow")
        ns.after(0.5, function()
            local p = Probe.store(true)
            if not p then return end
            p.seen.tradeSkill = {
                at = ns.now(), toolkitBefore = before, toolkitAfter = frameShown("GreenFangToolkit_MainWindow"),
                professionsFrame = frameShown("ProfessionsFrame"), tradeSkillFrame = frameShown("TradeSkillFrame"),
            }
        end)
    else
        bump(event)
    end
end

Probe.LISTEN = { "INSPECT_READY", "BANKFRAME_OPENED", "GUILDBANKFRAME_OPENED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "TRADE_SKILL_SHOW" }
do
    local f = CreateFrame("Frame")
    Probe.listener = f
    for _, e in ipairs(Probe.LISTEN) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, event, ...) pcall(Probe.onEvent, event, ...) end)
end

---------------------------------------------------------------------------
-- Text (copy window and diag)
---------------------------------------------------------------------------

local function sortedPairs(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local i = 0
    return function() i = i + 1; local k = keys[i]; if k ~= nil then return k, t[k] end end
end

local function kv(t)
    local parts = {}
    for k, v in sortedPairs(t) do
        if type(v) ~= "table" then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    return table.concat(parts, " ; ")
end

local function runText(r, out)
    out[#out + 1] = string.format("== %s %s | gftk %s | game %s build %s | ui %s",
        r.kind, ns.localTime and ns.localTime(r.at) or tostring(r.at), tostring(r.version), r.gameVersion, r.build, r.interface)
    if r.apis then
        out[#out + 1] = string.format("api %d/%d; missing: %s", r.apis.present or 0, r.apis.total or 0,
            table.concat(r.apis.missing or {}, ","))
        local nonFn = {}
        for _, h in ipairs(r.apis.have or {}) do if not h:find("=function$") then nonFn[#nonFn + 1] = h end end
        if #nonFn > 0 then out[#out + 1] = "api not function: " .. table.concat(nonFn, ",") end
    end
    if r.events then
        out[#out + 1] = string.format("events %d/%d; missing: %s", r.events.ok or 0, r.events.total or 0,
            table.concat(r.events.missing or {}, ","))
    end
    for _, name in ipairs({ "talents", "inspect", "questLog", "professions", "mail", "bank", "portraits" }) do
        if type(r[name]) == "table" then out[#out + 1] = name .. ": " .. kv(r[name]) end
    end
    if r.stv then
        local s = r.stv
        out[#out + 1] = string.format("stv pages exist %d/27, cached %d, tradable %d", s.pagesExist or 0, s.pagesCached or 0, s.pagesTradable or 0)
        local items = {}
        for id, p in sortedPairs(s.pages or {}) do
            items[#items + 1] = string.format("%d:%s/%s/b%s/%s", id, p.exists and "y" or "n", p.name and "c" or "-",
                tostring(p.bindType), p.trade)
        end
        out[#out + 1] = "stv items: " .. table.concat(items, " ")
        local qs = {}
        for id, q in sortedPairs(s.quests or {}) do
            qs[#qs + 1] = string.format("%d:%s/done=%s/on=%s/obj=%s/grp=%s", id, q.title and ("「" .. q.title .. "」") or "-",
                tostring(q.completed), tostring(q.onQuest), tostring(q.objectives), tostring(q.groupSize))
        end
        out[#out + 1] = "stv quests: " .. table.concat(qs, " ")
        local first = s.pages and s.pages[Probe.PAGE_ITEMS.first]
        if first and first.name then out[#out + 1] = "stv first page name: " .. tostring(first.name) end
    end
    if r.frames then out[#out + 1] = "frames: " .. table.concat(r.frames, " ") end
end

function Probe.text()
    local p = ns.db and ns.db.probe
    if type(p) ~= "table" or (not p.main and not p.bank) then
        return "還沒有探測結果：打 /gftk probe"
    end
    local out = { "GFTK-PROBE schema " .. tostring(p.schema) }
    if p.main then runText(p.main, out) end
    if p.bank then runText(p.bank, out) end
    local s = p.seen or {}
    out[#out + 1] = "seen: " .. kv(s)
    if type(s.inspect) == "table" then out[#out + 1] = "seen inspect: " .. kv(s.inspect) end
    if type(s.tradeSkill) == "table" then out[#out + 1] = "seen tradeSkill: " .. kv(s.tradeSkill) end
    return table.concat(out, "\n")
end

-- One line for 同步與診斷.
function Probe.diagText()
    local p = ns.db and ns.db.probe
    if type(p) ~= "table" or (not p.main and not p.bank) then
        return "還沒有跑過。打 /gftk probe 記錄這台客戶端有哪些功能（開著銀行時再打 /gftk probe bank）。"
    end
    local parts = {}
    if p.main then
        local m = p.main
        parts[#parts + 1] = string.format("上次 %s", ns.localTime and ns.localTime(m.at) or tostring(m.at))
        if m.apis then parts[#parts + 1] = string.format("API %d／%d", m.apis.present or 0, m.apis.total or 0) end
        if m.events then parts[#parts + 1] = string.format("事件 %d／%d", m.events.ok or 0, m.events.total or 0) end
        if m.stv then parts[#parts + 1] = string.format("荊棘谷書頁 %d／27", m.stv.pagesExist or 0) end
    end
    parts[#parts + 1] = p.bank and string.format("銀行補記 %s", ns.localTime and ns.localTime(p.bank.at) or "") or "銀行還沒補記"
    local seen = p.seen or {}
    parts[#parts + 1] = string.format("觀察 %d 次", tonumber(seen.INSPECT_READY) or 0)
    parts[#parts + 1] = "/gftk probe copy 開啟可複製的全文"
    return table.concat(parts, "｜")
end

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------

Probe.WINDOW_NAME = "GreenFangToolkit_ProbeWindow"
local window, edit

function Probe.showCopy()
    if not window then
        local f = ns.popupWindow(Probe.WINDOW_NAME, 760, 520)
        f:SetPoint("CENTER", 0, 10)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        if f.TitleText then f.TitleText:SetText("綠皮冒險工具箱｜探測結果") end
        local tip = f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
        tip:SetPoint("TOPLEFT", 20, -37)
        tip:SetJustifyH("LEFT")
        tip:SetText("按 Ctrl+A 全選、Ctrl+C 複製，整段貼給 claude-pm。")
        local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -64)
        scroll:SetPoint("BOTTOMRIGHT", -37, 20)
        edit = CreateFrame("EditBox", nil, scroll)
        if edit.SetMultiLine then edit:SetMultiLine(true) end
        edit:SetAutoFocus(false)
        edit:SetFontObject(ns.LABEL_FONT)
        edit:SetWidth(690)
        edit:SetHeight(420)
        if edit.SetMaxLetters then edit:SetMaxLetters(0) end
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(edit)
        window = f
    end
    local text = Probe.text()
    edit:SetText(text)
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    edit:SetHeight(math.max(420, lines * 40))
    window:Show()
    edit:SetFocus()
    if edit.HighlightText then edit:HighlightText() end
    return window
end
function Probe.copyText() return edit and edit:GetText() or nil end

---------------------------------------------------------------------------
-- /gftk probe [bank|copy]
---------------------------------------------------------------------------

function Probe.command(rest)
    local sub = ns.str(rest):lower():match("^(%S*)") or ""
    if sub == "copy" then Probe.showCopy(); return true end
    local kind = sub == "bank" and "bank" or "main"
    if kind == "bank" and not (Probe.bankOpen() or Probe.guildBankOpen()) then
        ns.say("探測：現在沒有開著銀行或公會銀行；照樣記一次，請開著銀行再打一次 /gftk probe bank。")
    end
    local r, why = Probe.run(kind)
    if not r then
        ns.say(why == "combat" and "探測：戰鬥中不能跑，脫離戰鬥再打一次。" or "探測：存檔還沒載入，等一下再打。")
        return false
    end
    ns.say("探測完成：" .. Probe.diagText())
    Probe.showCopy()
    return true
end
