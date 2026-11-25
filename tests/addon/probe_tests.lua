-- GF-PROBE: /gftk probe (Probe.lua). The mock client has none of the probed
-- APIs, so the first tests check that a bare client is safe; the later ones
-- install made-up APIs (Forever 71037 signatures) for one test and remove them.
-- Made-up names and values only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end

    local FAKE_GUID = "Player-0000-0ABCDEF1"
    local FAKE_IMPORT = "BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    local FAKE_TAB = "幹部私房分頁"
    local NAMES = { "C_SpecializationInfo", "C_ClassTalents", "C_Traits", "C_Item", "C_QuestLog", "C_Container",
        "C_Bank", "C_PlayerInteractionManager", "LinkTypes", "UnitExists", "UnitIsPlayer", "GetNumGuildBankTabs",
        "GetCurrentGuildBankTab", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
        "GetGuildBankMoney", "CanWithdrawGuildBankMoney", "GuildBankFrame", "NotifyInspect", "C_TradeSkillUI" }

    -- A Forever-like client: one talent config, a bank and a guild bank open.
    local function install(opts)
        opts = opts or {}
        local calls = {}
        local saved = {}
        for _, n in ipairs(NAMES) do saved[n] = _G[n] end
        local function boom() error("Interface/AddOns/X/Y.lua:12: bad argument") end
        C_SpecializationInfo = {
            IsInitialized = function() return true end,
            GetSpecialization = function() return 2 end,
            GetSpecializationInfo = function(i) return 100 + i, "專精", "說明", 12345, "DAMAGER" end,
            GetActiveSpecGroup = function() return 1 end,
            GetCombatConfigIDForSpecGroup = function(g) return 7000 + g end,
            GetInspectSpecialization = function() return 102 end,
        }
        C_ClassTalents = {
            GetActiveConfigID = function() return 7001 end,
            LoadConfig = function() calls.LoadConfig = true end,
            CommitConfig = function() calls.CommitConfig = true end,
            ViewLoadout = function() calls.ViewLoadout = true end,
            InitializeViewLoadout = function() calls.InitializeViewLoadout = true end,
        }
        C_Traits = {
            GetConfigInfo = function(id) return { ID = id, type = 1, name = "我的配置", treeIDs = { 55 }, usesSharedActionBars = false } end,
            GetTreeNodes = opts.nodesError and boom or function() return { 1, 2, 3 } end,
            GetNodeInfo = function(_, node) return { ID = node, entryIDs = { node * 10 }, activeRank = node == 1 and 1 or 0, isVisible = true } end,
            GetEntryInfo = function(_, e) return { definitionID = e + 1, maxRanks = 1 } end,
            GetDefinitionInfo = function() return { spellID = 1234 } end,
            GetGroupDisplayInfoByTreeID = function() return { { groupID = 1 }, { groupID = 2 }, { groupID = 3 } } end,
            GetGroupCurrencyInfo = function() return { { spent = 1 } } end,
            GenerateImportString = function() return FAKE_IMPORT end,
            GenerateInspectImportString = function() return FAKE_IMPORT end,
            HasValidInspectData = function() return true end,
            GetLoadoutSerializationVersion = function() return 2 end,
        }
        LinkTypes = { TalentBuild = "talentbuild" }
        C_Item = {
            DoesItemExistByID = function(id) return id ~= 2730 end,
            IsItemDataCachedByID = function(id) return id ~= 2731 end,
            GetItemInfo = function(id)
                if id == 2730 or id == 2731 then return nil end
                return "書頁 " .. id, "|cff|Hitem:" .. id .. "|h[x]|h|r", 1, 1, 1, "雜項", "其他", 1, "", 134939, 0, 15, 0,
                    id == 2725 and 1 or 0
            end,
            RequestLoadItemDataByID = function(id) calls.requested = (calls.requested or 0) + 1 end,
        }
        C_QuestLog = {
            GetTitleForQuestID = function(id) if id == 338 then return "荊棘谷的青山" end end,
            IsQuestFlaggedCompleted = function(id) return id == 339 end,
            IsOnQuest = function() return false end,
            GetQuestObjectives = function() return { { text = "x", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } } end,
            GetSuggestedGroupSize = function() return 0 end,
            RequestLoadQuestByID = function() end,
            GetNumQuestLogEntries = function() return 2, 1 end,
            GetInfo = function(i)
                if i == 1 then return { isHeader = true, title = "頭" } end
                return { isHeader = false, questID = 999, title = "某任務", suggestedGroup = 3 }
            end,
            GetQuestTagInfo = function() return { tagID = 1, tagName = "團體", isElite = true } end,
        }
        C_Container = {
            GetContainerNumSlots = function(bag) if bag == 0 or bag == 6 then return 4 end return 0 end,
            GetContainerItemInfo = function(bag, slot)
                if slot == 1 then return { itemID = 2725, stackCount = 1, isBound = false, hyperlink = "|Hitem:2725|h", itemName = "秘密物品" } end
            end,
        }
        C_Bank = {
            AreAnyBankTypesViewable = function() return true end,
            FetchViewableBankTypes = function() return { 0, 2 } end,
            CanViewBank = function(bt) return bt ~= 1 end,
            FetchNumPurchasedBankTabs = function(bt) return bt == 0 and 1 or 0 end,
            FetchPurchasedBankTabData = function() return { { ID = 6, name = "分頁名稱" } } end,
            PurchaseBankTab = function() calls.PurchaseBankTab = true end,
        }
        C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(t) return opts.open == t end }
        UnitExists = function(u) return u == "target" end
        UnitIsPlayer = function(u) return u == "target" end
        NotifyInspect = function() calls.NotifyInspect = true end
        GetNumGuildBankTabs = function() return 2 end
        GetCurrentGuildBankTab = function() return 1 end
        GetGuildBankTabInfo = function() return FAKE_TAB, 134400, true, true, 10, 10 end
        GetGuildBankItemInfo = function(_, slot) if slot <= 3 then return 134400, 5, false, false, 1 end end
        GetGuildBankItemLink = function() return "|Hitem:1|h[秘密]|h" end
        GetGuildBankMoney = function() return 12345 end
        CanWithdrawGuildBankMoney = function() return false end
        C_TradeSkillUI = { GetBaseProfessionInfo = boom }
        local oldGUID = UnitGUID
        UnitGUID = function(u) if u == "target" then return FAKE_GUID end return oldGUID(u) end
        return calls, function()
            for _, n in ipairs(NAMES) do _G[n] = saved[n] end
            UnitGUID = oldGUID
        end
    end

    local function dump(v)
        return wow.serializeSV("x", v)
    end

    test("GF-PROBE: a plain login writes nothing; Probe.lua is in the TOC before Init.lua", function()
        local ns = login()
        ok(ns.Probe, "ns.Probe")
        eq(GreenFangToolkitDB.probe, nil, "no probe table before /gftk probe")
        wow.fire("INSPECT_READY", "Player-0000-00000001")
        wow.fire("BANKFRAME_OPENED")
        eq(GreenFangToolkitDB.probe, nil, "events before the first run write nothing")
        local list = table.concat(wow.TOC_FILES, ",")
        ok(list:find("Probe.lua,Init.lua", 1, true), "Probe.lua right before Init.lua")
    end)

    test("GF-PROBE: /gftk probe on a client with none of the APIs is safe", function()
        local ns = login()
        ns.handleSlash("probe")
        local p = GreenFangToolkitDB.probe
        ok(p and p.main, "main run stored")
        eq(p.schema, 1, "schema")
        ok(p.main.apis.present < p.main.apis.total, "some APIs missing")
        local missing = table.concat(p.main.apis.missing, ",")
        ok(missing:find("C_Traits.GetConfigInfo", 1, true), "C_Traits.GetConfigInfo reported missing")
        eq(p.main.stv.pagesExist, 0, "no pages on the mock")
        eq(p.main.talents.getSpecialization, "nil", "missing function -> nil")
        eq(p.main.bank.bankOpen, "false", "bank not open")
        ok(wow.state and true, "mock state")
        local w = _G[ns.Probe.WINDOW_NAME]
        ok(w and w:IsShown(), "copy window shown")
        ok(ns.Probe.copyText():find("GFTK-PROBE schema 1", 1, true), "copy text")
        ok(ns.Probe.copyText():find("stv items: 2725:", 1, true), "every page listed")
        -- 同步與診斷 has one more section with the summary.
        ns.Diag.open()
        local found
        for i, h in ipairs(ns.Diag.heads()) do
            if h:GetText() == "功能探測（GF-PROBE）" then found = ns.Diag.lines()[i]:GetText() end
        end
        ok(found and found:find("API", 1, true), "diag section shows the summary")
    end)

    test("GF-PROBE: no run in combat", function()
        local ns = login()
        wow.setCombat(true)
        eq(ns.Probe.command(""), false, "refused")
        eq(GreenFangToolkitDB.probe.main, nil, "nothing recorded")
        wow.setCombat(false)
        ok(ns.Probe.command(""), "runs after combat")
    end)

    test("GF-PROBE: diag text before any run", function()
        local ns = login()
        ok(ns.Probe.diagText():find("/gftk probe", 1, true), "tells how to run it")
        ok(ns.Probe.text():find("/gftk probe", 1, true), "copy text too")
    end)

    test("GF-PROBE: Forever-like APIs give types, field names and counts; no state-changing calls", function()
        local ns = login()
        local calls, restore = install({ open = 10 })
        local good, err = pcall(function()
            ns.handleSlash("probe")
            local m = GreenFangToolkitDB.probe.main
            local t = m.talents
            eq(t.treeCount, 1, "trees")
            eq(t.nodeCount, 3, "nodes")
            eq(t.nodesWithRank, 1, "ranked nodes")
            eq(t.groupCount, 3, "groups (three trees)")
            eq(t.importStringLength, #FAKE_IMPORT, "import string length only")
            eq(t.linkTypeTalentBuild, "talentbuild", "link type")
            eq(t.sameConfig, "true", "group 1 config 7001 equals the active config")
            ok(t.getConfigInfo:find("{ID,name,treeIDs,type,usesSharedActionBars}", 1, true), "config field names")
            ok(t.getNodeInfo:find("activeRank", 1, true), "node field names")
            ok(t.getDefinitionInfo:find("spellID", 1, true), "definition reached")
            ok(t.getGroupCurrencyInfo:find("^ok:table"), "group currency")
            eq(m.inspect.targetIsPlayer, "true", "target is a player")
            local s = m.stv
            eq(s.pagesExist, 26, "2730 missing")
            eq(s.pagesCached, 25, "2730 and 2731 have no data")
            eq(s.pages[2725].trade, "no", "bind on pickup")
            eq(s.pages[2726].trade, "yes", "not bound")
            eq(s.pages[2731].trade, "unknown", "not cached -> unknown")
            ok((calls.requested or 0) >= 1, "requested the missing item data")
            eq(s.quests[338].title, "荊棘谷的青山", "quest title")
            eq(s.quests[339].completed, true, "completed flag")
            eq(s.quests[340].objectives, 1, "objectives counted")
            eq(m.questLog.suggestedGroup, 1, "group quest counted")
            eq(m.questLog.elite, 1, "elite tag counted")
            ok(m.professions.baseProfessionInfo:find("^err:bad argument"), "error kept without the file path")
            eq(m.bank.guildBankOpen, "true", "guild bank open")
            eq(m.bank.guildBankUsedSlots, 3, "guild bank slots used")
            eq(m.bank.viewableTypes, "0,2", "viewable bank types")
            eq(m.bank.canViewBank1, "ok:boolean", "CanViewBank guild")
            for _, k in ipairs({ "LoadConfig", "CommitConfig", "ViewLoadout", "InitializeViewLoadout", "PurchaseBankTab", "NotifyInspect" }) do
                eq(calls[k], nil, k .. " never called")
            end
            -- /gftk probe bank: the bank tabs too.
            C_PlayerInteractionManager.IsInteractingWithNpcOfType = function(tp) return tp == 8 end
            ns.handleSlash("probe bank")
            local b = GreenFangToolkitDB.probe.bank
            ok(b and not b.apis, "bank run is short")
            eq(b.bank.bankOpen, "true", "bank open")
            ok(b.bank.bags:find("6:1/4", 1, true), "character bank tab 1 read")
            ok(b.bank.containerItemFields:find("isBound", 1, true), "container item field names")
            ok(b.bank.tabData0:find("{ID,name}", 1, true), "tab data field names")
            -- Privacy: none of the values leave the client.
            local all = dump(GreenFangToolkitDB.probe) .. ns.Probe.text()
            for _, secret in ipairs({ FAKE_IMPORT, FAKE_TAB, "秘密", "我的配置", "分頁名稱", "某任務", FAKE_GUID, "|Hitem" }) do
                ok(not all:find(secret, 1, true), "not stored: " .. secret)
            end
            -- After the first run, INSPECT_READY is recorded (no GUID).
            wow.fire("INSPECT_READY", FAKE_GUID)
            local i = GreenFangToolkitDB.probe.seen.inspect
            eq(i.unit, "target", "matched the target")
            eq(i.importStringLength, #FAKE_IMPORT, "inspect import string length")
            eq(GreenFangToolkitDB.probe.seen.INSPECT_READY, 1, "counted")
            ok(not dump(GreenFangToolkitDB.probe):find(FAKE_GUID, 1, true), "no GUID stored")
        end)
        restore()
        if not good then error(err, 0) end
    end)

    test("GF-PROBE: a raising API in the middle does not stop the run", function()
        local ns = login()
        local _, restore = install({ nodesError = true })
        local good, err = pcall(function()
            ok(ns.Probe.command(""), "ran")
            local t = GreenFangToolkitDB.probe.main.talents
            ok(t.getTreeNodes:find("^err:"), "error recorded")
            eq(t.nodeCount, nil, "no node count")
            ok(GreenFangToolkitDB.probe.main.stv.pagesExist > 0, "later sections still ran")
        end)
        restore()
        if not good then error(err, 0) end
    end)

    test("GF-PROBE: /gftk probe bank without a bank says so; /gftk probe copy opens the window", function()
        local ns = login()
        wow.clearPrinted()
        ns.handleSlash("probe bank")
        local said = table.concat(wow.printed(), "\n")
        ok(said:find("沒有開著銀行", 1, true), "tells the owner to open the bank")
        ok(GreenFangToolkitDB.probe.bank, "still recorded")
        _G[ns.Probe.WINDOW_NAME]:Hide()
        ns.handleSlash("probe copy")
        ok(_G[ns.Probe.WINDOW_NAME]:IsShown(), "copy window")
    end)
end
