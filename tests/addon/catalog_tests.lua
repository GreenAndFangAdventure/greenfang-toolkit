-- GF-009-12: the 找物品 item catalog (GreenFangToolkit_Catalog, LoadOnDemand).
-- Uses the shipped CatalogData.lua itself (Forever build export) with a small
-- fake game client below that knows nothing until an item is asked for.
-- Offline only; not checked in the Forever client. Made-up player names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local DATA_FILE = ADDON_DIR .. "/../GreenFangToolkit_Catalog/CatalogData.lua"
    local TOC_FILE = ADDON_DIR .. "/../GreenFangToolkit_Catalog/GreenFangToolkit_Catalog.toc"
    local BRONZE, PATTERN, FOREVER_NEW, OFF_LIST = 2841, 7975, 289334, 990001

    local cached -- the catalog table, read once
    local function catalogTable()
        if not cached then cached = assert(loadfile(DATA_FILE))() or _G.GreenFangToolkit_CatalogData end
        return cached
    end
    local function indexOf(id)
        for i, v in ipairs(catalogTable().id) do if v == id then return i end end
    end

    local G
    local function installGame(opts)
        opts = opts or {}
        G = { known = {}, asked = {}, infoCalls = 0, infoIDs = {}, loads = 0, cursor = nil, exists = {}, bag = opts.bag or {} }
        -- The client's real data, given only once an item was asked for.
        G.server = opts.server or {}
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = false, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            G.infoCalls = G.infoCalls + 1
            G.infoIDs[id] = true
            local it = G.known[id]
            if not it then G.asked[id] = true; return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "",
                it.icon or 134939, 0, it.classID, it.sub or 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.known[id] and (G.known[id].icon or 134939) or nil end,
            RequestLoadItemDataByID = function(id) G.asked[id] = true end,
            DoesItemExistByID = function(id) if G.exists[id] == false then return false end return true end,
            IsItemDataCachedByID = function(id) return G.known[id] ~= nil end,
        }
        -- Put on C_AddOns after the AddOn loaded (the mock sets C_AddOns then).
        if opts.noCatalog then
            G.loader = function(name)
                if name ~= "GreenFangToolkit_Catalog" then return false, "MISSING" end -- e.g. GF Sync's Inbox
                G.loads = G.loads + 1; return false, "MISSING"
            end
        else
            G.loader = function(name)
                if name ~= "GreenFangToolkit_Catalog" then return false, "MISSING" end
                G.loads = G.loads + 1
                _G.GreenFangToolkit_CatalogData = catalogTable()
                return true
            end
        end
        GetCursorInfo = function() if G.cursor then return "item", G.cursor end return nil end
        ClearCursor = function() G.cursor = nil end
        ChatFrame_SendTellWithMessage = function() end
    end
    -- The server answers: the item becomes known (GET_ITEM_INFO_RECEIVED).
    local function answer(id)
        local it = G.server[id]
        if it then G.known[id] = it end
        wow.fire("GET_ITEM_INFO_RECEIVED", id, it ~= nil)
    end
    local function removeGame()
        C_Container, GetItemInfo, C_Item, GetCursorInfo, ClearCursor, ChatFrame_SendTellWithMessage =
            nil, nil, nil, nil, nil, nil
        if type(C_AddOns) == "table" then C_AddOns.LoadAddOn = nil end
        _G.GreenFangToolkit_CatalogData = nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end
    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        if type(C_AddOns) ~= "table" then C_AddOns = {} end
        C_AddOns.LoadAddOn = G.loader
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession(); ns.SupplyCatalog.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        wow.state.sent = {}
        return ns
    end
    local function openFinder(ns)
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm()
        UI.openPicker("all")
        return UI, UI.picker()
    end
    local function rowIDs(UI)
        local out = {}
        for _, it in ipairs(UI.pickState.items) do out[#out + 1] = it.itemID end
        return out
    end
    local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end

    test("GF-009-12 catalog file: LoadOnDemand AddOn, schema, >3000 items, only tradeable groups, sizes", function()
        local f = assert(io.open(TOC_FILE, "rb")); local toc = f:read("*a"); f:close()
        ok(toc:find("## LoadOnDemand: 1", 1, true), "LoadOnDemand")
        ok(toc:find("## Interface: 16001", 1, true), "interface as the main AddOn")
        ok(toc:find("## Dependencies: GreenFangToolkit", 1, true), "needs the main AddOn")
        ok(toc:find("\nCatalogData.lua", 1, true), "one data file")
        local f2 = assert(io.open(DATA_FILE, "rb")); local src = f2:read("*a"); f2:close()
        local before = collectgarbage("count")
        local t = assert(loadfile(DATA_FILE))
        t()
        local c = _G.GreenFangToolkit_CatalogData
        _G.GreenFangToolkit_CatalogData = nil
        local mem = collectgarbage("count") - before
        eq(c.v, 1, "schema"); eq(c.locale, "zhTW", "locale"); ok(c.build ~= nil and c.build ~= "", "build recorded")
        ok(#c.id > 3000, "more than 3000 items: " .. #c.id)
        eq(#c.name, #c.id, "names"); eq(#c.kind, #c.id, "kinds"); eq(#c.icon, #c.id, "icons")
        local seen, noIcon = {}, 0
        for i, id in ipairs(c.id) do
            ok(not seen[id], "unique " .. id); seen[id] = true
            ok(type(c.name[i]) == "string" and c.name[i] ~= "", "name for " .. id)
            if c.icon[i] == 0 then noIcon = noIcon + 1 end
        end
        ok(seen[BRONZE] and seen[PATTERN] and seen[FOREVER_NEW], "青銅錠, a pattern and a Forever item are in")
        T.realPrint(string.format("     CATALOG GF-009-12: %d items, data file %d bytes, Lua memory after load %.0f KB, %d without icon",
            #c.id, #src, mem, noIcon))
    end)

    test("GF-009-12 not at login: no catalog load, no item requests; 背包 never loads it; 全部 loads it once", done(function()
        local ns = login({})
        eq(G.loads, 0, "not loaded at login")
        wow.fire("AUCTION_ITEM_LIST_UPDATE"); wow.enterCombat(); wow.advance(30); wow.leaveCombat(); wow.advance(30)
        eq(G.loads, 0, "not loaded by the AH or combat")
        eq(next(G.asked), nil, "no item asked for")
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm(); UI.openPicker("bag")
        eq(G.loads, 0, "從背包選 does not load it")
        UI.pickSource("all")
        eq(G.loads, 1, "全部 loads it")
        UI.pickSearch("青銅"); UI.pickSource("bag"); UI.pickSource("all")
        eq(G.loads, 1, "only once")
        eq(ns.db.supplyItems, nil, "nothing copied into SavedVariables")
        -- A GF-009-11 test build's cache is dropped; listings stay.
        ns.db.supplyItems = { v = 1, items = { [2841] = "x" } }
        local own = #ns.SupplyListings.own()
        wow.fire("PLAYER_ENTERING_WORLD")
        eq(ns.db.supplyItems, nil, "old cache dropped")
        eq(#ns.SupplyListings.own(), own, "listings untouched")
        ok(ns.SupplyCatalog.diagText():find("已載入", 1, true), "diag: loaded")
    end))

    test("GF-009-12 acceptance: empty client cache, part of a zhTW name finds never-owned items; the client is asked only for the chosen one", done(function()
        local ns = login({ server = { [PATTERN] = { name = "設計圖：秘銀短褲", classID = 9, sub = 3 } } })
        local UI, picker = openFinder(ns)
        G.infoIDs = {}
        local list = UI.pickSearch("青銅")
        ok(#list > 0 and has(rowIDs(UI), BRONZE), "青銅 finds 青銅錠")
        for _, it in ipairs(list) do ok(it.info.name:find("青銅", 1, true), "only names with 青銅: " .. it.info.name) end
        UI.pickSearch("秘銀短褲")
        ok(has(rowIDs(UI), PATTERN), "the pattern by name")
        for id in pairs(G.infoIDs) do ok(not indexOf(id), "no client lookup for catalog item " .. id) end
        for id in pairs(G.asked) do ok(not indexOf(id), "no server request for catalog item " .. id) end
        -- Rows: the catalog's name and native icon number.
        local row
        for i = 1, UI.PICK_ROWS do if picker.rows[i].item and picker.rows[i].item.itemID == PATTERN then row = picker.rows[i] end end
        ok(row, "the row is shown")
        eq(row.name._text, catalogTable().name[indexOf(PATTERN)], "catalog name")
        eq(row.icon._texture, catalogTable().icon[indexOf(PATTERN)], "native icon number")
        -- A Forever-only item.
        local fi = indexOf(FOREVER_NEW)
        UI.pickSearch(catalogTable().name[fi])
        ok(has(rowIDs(UI), FOREVER_NEW), "a Forever item by its name")
        -- Choose the pattern: its own ItemID, the client is asked for that one only.
        UI.pickSearch("秘銀短褲")
        local idx
        for i, it in ipairs(UI.pickState.items) do if it.itemID == PATTERN then idx = i end end
        UI.pickChoose(idx - UI.pickState.offset)
        eq(UI.formState.itemID, PATTERN, "the pattern's own ItemID")
        eq(UI.formState.preview, "loading", "waits for the game")
        ok(G.asked[PATTERN], "asked the server for the chosen item")
        local n = 0
        for id in pairs(G.asked) do if indexOf(id) then n = n + 1 end end
        eq(n, 1, "only that catalog item")
        answer(PATTERN)
        eq(UI.formState.preview, "ready", "ready when the game answered")
        eq(UI.formState.category, "recipe", "類型 from the game")
        UI.form().qty:SetText("1")
        local l = UI.submitForm()
        ok(l and l.itemID == PATTERN, "徵求 of the pattern itself")
    end))

    test("GF-009-12 no cut-off: every catalog item is reachable; rows past 3000 page in; the position text", done(function()
        local ns = login({})
        local UI, picker = openFinder(ns)
        local all = UI.pickSearch("")
        eq(#all, #catalogTable().id, "the empty search lists the whole catalog")
        ok(#all > ns.SupplyListings.CATALOG_MAX, "more than the old 3000 cap")
        eq(picker.pos._text, string.format(UI.PICK_POS, 1, UI.PICK_ROWS, #all), "1-10／共 N")
        -- The catalog's last item, by name.
        local c = catalogTable()
        local lastName = c.name[#c.id]
        UI.pickSearch(lastName)
        ok(has(rowIDs(UI), c.id[#c.id]), "the last item found by name")
        -- Item 3001+ in a class filter still there.
        UI.pickSearch("")
        local late = all[3500]
        UI.pickClass(late.info.classID)
        ok(has(rowIDs(UI), late.itemID), "row 3500 still in its class")
        -- Scroll to the end.
        UI.pickClass(nil)
        picker.rows[1]:GetScript("OnMouseWheel")(picker.rows[1], -100000)
        eq(picker.pos._text, string.format(UI.PICK_POS, #all - UI.PICK_ROWS + 1, #all, #all), "last page")
        local t0 = os.clock()
        for _ = 1, 20 do UI.pickSearch("藥水"); UI.pickSearch("") end
        T.realPrint(string.format("     CATALOG GF-009-12: %d rows; search+sort+draw %.1f ms each (offline Lua 5.1); last search %.2f ms",
            #all, (os.clock() - t0) * 1000 / 40, ns.SupplyCatalog.stats().lastMs or -1))
    end))

    test("GF-009-12 four ways in give the same item: name, drag (form and finder), link (form and finder), ItemID", done(function()
        local srv = { [BRONZE] = { name = "青銅錠", classID = 7, sub = 7 } }
        local ns = login({ server = srv })
        local UI = openFinder(ns)
        local f = UI.form()
        -- 1 name
        UI.pickSearch("青銅錠")
        local i
        for k, it in ipairs(UI.pickState.items) do if it.itemID == BRONZE then i = k end end
        UI.pickChoose(i - UI.pickState.offset)
        eq(UI.formState.itemID, BRONZE, "name")
        answer(BRONZE)
        eq(UI.formState.preview, "ready", "ready")
        -- 2 drag onto the form's slot, and onto the finder
        UI.setFormItem(nil)
        G.cursor = BRONZE
        f.slot:GetScript("OnReceiveDrag")(f.slot)
        eq(UI.formState.itemID, BRONZE, "drag to the slot"); eq(G.cursor, nil, "cursor cleared")
        UI.setFormItem(nil)
        UI.openPicker("all")
        G.cursor = BRONZE
        UI.picker():GetScript("OnReceiveDrag")(UI.picker())
        eq(UI.formState.itemID, BRONZE, "drag to the finder")
        ok(not UI.picker():IsShown(), "the finder closes")
        -- 3 link: into the form box, and into the finder's search
        local link = "|cffffffff|Hitem:" .. BRONZE .. "::::::::|h[青銅錠]|h|r"
        UI.setFormItem(nil)
        UI.formFromText(link)
        eq(UI.formState.itemID, BRONZE, "link in the form")
        UI.openPicker("all")
        UI.picker().search.HasFocus = function() return true end
        ok(UI.pickLink(link), "link into the search")
        eq(#UI.pickState.items, 1, "one row"); eq(UI.pickState.items[1].itemID, BRONZE, "that item")
        -- 4 ItemID
        UI.setFormItem(nil)
        UI.formFromText(tostring(BRONZE))
        eq(UI.formState.itemID, BRONZE, "ItemID")
        UI.pickSearch(tostring(BRONZE))
        eq(UI.pickState.items[1].itemID, BRONZE, "ItemID in the search")
    end))

    test("GF-009-12 off the list, mismatches, bad input, no catalog; the draft stays", done(function()
        local srv = {
            [OFF_LIST] = { name = "目錄外的布", classID = 7, sub = 5 },
            -- The game says bind on pickup: the catalog row goes away.
            [BRONZE] = { name = "青銅錠（遊戲名）", classID = 7, sub = 7 },
        }
        local ns = login({ server = srv })
        local UI = openFinder(ns)
        local f = UI.form()
        -- Draft fields first.
        f.qty:SetText("7"); f.note:SetText("測試草稿")
        UI.pickSearch("青銅錠")
        UI.pickClass(UI.pickState.items[1].info.classID)
        -- Off-list ItemID: the game resolves it, it may be listed.
        UI.formFromText(tostring(OFF_LIST))
        eq(UI.formState.preview, "loading", "waits")
        answer(OFF_LIST)
        eq(UI.formState.preview, "ready", "an item outside the catalog")
        eq(f.qty:GetText(), "7", "quantity kept"); eq(f.note:GetText(), "測試草稿", "note kept")
        ok(UI.submitForm(), "listed")
        -- The game's name wins once it knows the item.
        G.known[BRONZE] = srv[BRONZE]
        UI.openPicker("all")
        UI.pickSearch("青銅錠")
        local row = UI.pickState.items[1]
        eq(row.info.name, "青銅錠（遊戲名）", "the client's name")
        -- The game says it cannot be traded: not offered.
        G.known[BRONZE] = { name = "青銅錠", classID = 7, sub = 7, bindType = 1 }
        UI.pickSearch("青銅錠")
        ok(not has(rowIDs(UI), BRONZE), "untradeable in the game: not in the list")
        -- Unknown ID: missing after the wait.
        UI.formFromText("990777")
        wow.advance(ns.SupplyListings.LOAD_WAIT + 1)
        eq(UI.formState.preview, "missing", "no such item")
        eq(UI.form().msg._text, UI.PREVIEW_TEXT.missing, "says so")
        UI.formFromText("not an item")
        eq(UI.form().msg._text, UI.PREVIEW_TEXT.bad, "bad text")
    end))

    test("GF-009-12 without the catalog AddOn: 全部 says so, links / IDs / bags still work", done(function()
        local ns = login({ noCatalog = true, bag = { { 2589, 5 } },
            server = { [2589] = { name = "亞麻布", classID = 7, sub = 5 } } })
        G.known[2589] = G.server[2589]
        local UI, picker = openFinder(ns)
        eq(G.loads, 1, "tried to load")
        ok(not ns.SupplyCatalog.loaded(), "not loaded")
        UI.pickSearch("不存在的名字")
        eq(picker.empty._text, UI.PICK_NO_CATALOG, "沒有物品目錄")
        UI.pickSearch("亞麻")
        ok(has(rowIDs(UI), 2589), "bag items still searchable")
        UI.formFromText("2589")
        eq(UI.formState.preview, "ready", "an ID still works")
        ok(ns.SupplyCatalog.diagText():find("沒有安裝", 1, true), "diag: not installed")
    end))
end
