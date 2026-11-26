-- GF-009-12: the 找物品 item catalog (SupplyCatalogData.lua in the main TOC,
-- decoded on the first 找物品 → 全部). GF-009-13: the scan moved to the dev-only
-- GreenFangToolkit_Dev AddOn (tests/addon/catalog_dev_tests.lua).
-- Uses the shipped data file itself (Forever build export) with a small fake
-- game client below that knows nothing until an item is asked for.
-- Offline only; not checked in the Forever client. Made-up player names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local DATA_FILE = ADDON_DIR .. "/SupplyCatalogData.lua"
    local TOC_FILE = ADDON_DIR .. "/GreenFangToolkit.toc"
    local BRONZE, PATTERN, FOREVER_NEW, OFF_LIST = 2841, 7975, 289334, 990001

    -- The data file run on its own (as the game does at login), and its
    -- records decoded here independently of SupplyCatalog.lua.
    local function runDataFile()
        local fake = {}
        assert(loadfile(DATA_FILE))("GreenFangToolkit", fake)
        return fake.SupplyCatalogData
    end
    local cached
    local function catalogTable()
        if cached then return cached end
        local src = runDataFile()
        local c, classes = { id = {}, name = {}, icon = {}, kind = {} }, {}
        for k in pairs(src.groups) do classes[#classes + 1] = k end
        table.sort(classes)
        for _, k in ipairs(classes) do
            for i, sub, ic, nm in src.groups[k]:gmatch("(%d+)\t(%d+)\t(%d+)\t([^\n]+)") do
                local n = #c.id + 1
                c.id[n], c.kind[n], c.icon[n], c.name[n] = tonumber(i), k * 100 + tonumber(sub), tonumber(ic), nm
            end
        end
        cached = c
        return c
    end
    local indexByID
    local function indexOf(id)
        if not indexByID then
            indexByID = {}
            for i, v in ipairs(catalogTable().id) do indexByID[v] = i end
        end
        return indexByID[id]
    end

    local G
    local function installGame(opts)
        opts = opts or {}
        G = { known = {}, asked = {}, infoCalls = 0, infoIDs = {}, cursor = nil, exists = {}, bag = opts.bag or {},
            requests = {}, instance = false }
        -- The client's real data, given only once an item was asked for.
        G.server = opts.server or {}
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            G.infoCalls = G.infoCalls + 1
            G.infoIDs[id] = true
            local it = G.known[id]
            if not it then G.asked[id] = true; return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", it.quality or 1, it.ilvl or 1, 1,
                "", "", 20, "", it.icon or 134939, 0, it.classID, it.sub or 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.known[id] and (G.known[id].icon or 134939) or nil end,
            RequestLoadItemDataByID = function(id)
                G.asked[id] = true
                G.requests[#G.requests + 1] = { id = id, t = wow.state.now }
            end,
            DoesItemExistByID = function(id) if G.exists[id] == false then return false end return true end,
            IsItemDataCachedByID = function(id) return G.known[id] ~= nil end,
        }
        IsInInstance = function() return G.instance end
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
        C_Container, GetItemInfo, C_Item, GetCursorInfo, ClearCursor, ChatFrame_SendTellWithMessage, IsInInstance =
            nil, nil, nil, nil, nil, nil, nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end
    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        if opts.noCatalog then ns.SupplyCatalogData = nil end
        if opts.scan then ns.SupplyCatalogData.scan = opts.scan end
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession(); ns.SupplyCatalog.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(opts.wait or 70)
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
    local function memNow() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") end

    test("GF-009-12 catalog file: in the main TOC, packed strings, >3000 items, sizes and memory", function()
        local f = assert(io.open(TOC_FILE, "rb")); local toc = f:read("*a"); f:close()
        ok(toc:find("\nSupplyCatalogData.lua", 1, true), "listed in the main TOC")
        ok(not toc:find("LoadOnDemand", 1, true), "no LoadOnDemand")
        local f2 = assert(io.open(DATA_FILE, "rb")); local bytes = #f2:read("*a"); f2:close()
        -- Login with and without the data file (the whole AddOn loaded each time).
        local function loadCost(withData)
            local files, saved = wow.TOC_FILES, nil
            if not withData then
                for i, name in ipairs(files) do if name == "SupplyCatalogData.lua" then saved = i; table.remove(files, i); break end end
            end
            wow.reset({}); installGame({})
            local m0 = memNow()
            local ns = wow.loadAddon(ADDON_DIR)
            local cost = memNow() - m0
            if saved then table.insert(files, saved, "SupplyCatalogData.lua") end
            removeGame()
            return cost, ns
        end
        loadCost(true); loadCost(false)
        local withKB, without = 0, 0
        for _ = 1, 3 do withKB = withKB + loadCost(true); without = without + loadCost(false) end
        withKB, without = withKB / 3, without / 3
        local keep = runDataFile()
        local strKB = 0 -- GF-009-13: no scan list in the guild file
        for _, v in pairs(keep.groups) do strKB = strKB + #v end
        strKB = strKB / 1024
        eq(keep.v, 2, "schema"); eq(keep.locale, "zhTW", "locale"); ok(keep.build ~= nil and keep.build ~= "", "build recorded")
        for k, v in pairs(keep.groups) do ok(type(k) == "number" and type(v) == "string", "one string per ClassID") end
        local c = catalogTable()
        ok(#c.id > 3000, "more than 3000 items: " .. #c.id)
        eq(#c.id, keep.n, "count in the header")
        local seen, noIcon = {}, 0
        for i, id in ipairs(c.id) do
            ok(not seen[id], "unique " .. id); seen[id] = true
            ok(c.name[i] ~= "" and not c.name[i]:find("\t", 1, true), "name for " .. id)
            if c.icon[i] == 0 then noIcon = noIcon + 1 end
        end
        ok(seen[BRONZE] and seen[PATTERN] and seen[FOREVER_NEW], "青銅錠, a pattern and a Forever item are in")
        keep = nil
        T.realPrint(string.format("     CATALOG GF-009-12: %d items, %d without icon; data file %d bytes (strings %.0f KB); AddOn at login %.0f KB with it, %.0f KB without (+%.0f KB)",
            #c.id, noIcon, bytes, strKB, withKB, without, withKB - without))
    end)

    test("GF-009-12 not at login: decoded only by 找物品 → 全部, once; strings let go; no item requests", done(function()
        local ns = login({})
        local cat = ns.SupplyCatalog
        ok(not cat.loaded(), "not decoded at login")
        ok(type(ns.SupplyCatalogData.groups) == "table", "the strings are there")
        wow.fire("AUCTION_ITEM_LIST_UPDATE"); wow.enterCombat(); wow.advance(30); wow.leaveCombat(); wow.advance(30)
        ok(not cat.loaded(), "not by the AH or combat")
        eq(next(G.asked), nil, "no item asked for")
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm(); UI.openPicker("bag")
        ok(not cat.loaded(), "從背包選 does not decode it")
        local before = memNow()
        local t0 = os.clock()
        UI.pickSource("all")
        local openMs = (os.clock() - t0) * 1000
        local after = memNow()
        ok(cat.loaded(), "全部 decodes it")
        eq(ns.SupplyCatalogData.groups, nil, "the strings are let go")
        UI.pickSearch("青銅"); UI.pickSource("bag"); UI.pickSource("all")
        eq(cat.stats().decodes, 1, "only once")
        eq(ns.db.supplyItems, nil, "nothing copied into SavedVariables")
        eq(ns.db.devCatalogScan, nil, "no scan data unless the owner runs it")
        -- A GF-009-11 test build's cache is dropped; listings stay.
        ns.db.supplyItems = { v = 1, items = { [2841] = "x" } }
        local own = #ns.SupplyListings.own()
        wow.fire("PLAYER_ENTERING_WORLD")
        eq(ns.db.supplyItems, nil, "old cache dropped")
        eq(#ns.SupplyListings.own(), own, "listings untouched")
        ok(cat.diagText():find("已載入", 1, true), "diag: loaded")
        T.realPrint(string.format("     CATALOG GF-009-12: first 全部 open %.0f ms (decode %.0f ms); Lua memory %+.0f KB after the first open (tables in, strings let go)",
            openMs, cat.stats().decodeMs or -1, after - before))
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
        local whole = (os.clock() - t0) * 1000 / 40
        t0 = os.clock()
        for _ = 1, 200 do ns.SupplyCatalog.search("藥水") end
        T.realPrint(string.format("     CATALOG GF-009-12: %d rows; finder search+list+draw %.1f ms each; name match alone %.2f ms (offline Lua 5.1)",
            #all, whole, (os.clock() - t0) * 1000 / 200))
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
        -- Unknown ID, no answer: a timeout after the wait (GF-009-13: not "missing").
        UI.formFromText("990777")
        wow.advance(ns.SupplyListings.LOAD_WAIT + 1)
        eq(UI.formState.preview, "timeout", "no answer in time")
        eq(UI.form().msg._text, UI.PREVIEW_TEXT.timeout, "says so")
        UI.formFromText("not an item")
        eq(UI.form().msg._text, UI.PREVIEW_TEXT.bad, "bad text")
    end))

    test("GF-009-12 without the catalog data: 全部 says so, links / IDs / bags still work", done(function()
        local ns = login({ noCatalog = true, bag = { { 2589, 5 } },
            server = { [2589] = { name = "亞麻布", classID = 7, sub = 5 } } })
        G.known[2589] = G.server[2589]
        local UI, picker = openFinder(ns)
        ok(not ns.SupplyCatalog.loaded(), "not loaded")
        UI.pickSearch("不存在的名字")
        eq(picker.empty._text, UI.PICK_EMPTY.all, "the usual empty words")
        UI.pickSearch("亞麻")
        ok(has(rowIDs(UI), 2589), "bag items still searchable")
        UI.formFromText("2589")
        eq(UI.formState.preview, "ready", "an ID still works")
        ok(ns.SupplyCatalog.diagText():find("沒有目錄", 1, true), "diag: no catalog")
        -- A damaged file (wrong schema): 全部 says so.
        local ns2 = login({})
        ns2.SupplyCatalogData.v = 99
        local UI2, picker2 = openFinder(ns2)
        UI2.pickSearch("不存在的名字")
        eq(picker2.empty._text, UI2.PICK_NO_CATALOG, "沒有物品目錄")
        ok(ns2.SupplyCatalog.diagText():find("格式不符", 1, true), "diag: bad format")
    end))

    ---------------------------------------------------------------------------
    -- GF-009-13: the release has no scan; cold cache; one resolve path;
    -- bag stacks for 供應; screens, ESC and drafts.
    ---------------------------------------------------------------------------

    local ROOT_DIR = ADDON_DIR:gsub("/addon/GreenFangToolkit$", "")
    local function countKeys(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local function readAll(path) local h = io.open(path, "rb"); if not h then return nil end local s = h:read("*a"); h:close(); return s end

    test("GF-009-13 release: no CatalogScan, no scan list, no /gftk catalogscan; .pkgmeta leaves the dev AddOn out", done(function()
        local toc = readAll(TOC_FILE)
        ok(not toc:find("CatalogScan", 1, true), "not in the main TOC")
        eq(readAll(ADDON_DIR .. "/CatalogScan.lua"), nil, "no CatalogScan.lua in the main folder")
        eq(runDataFile().scan, nil, "no scan list in SupplyCatalogData.lua")
        for line in toc:gmatch("[^\r\n]+") do
            if line:match("^[%w_]+%.lua$") then
                local body = readAll(ADDON_DIR .. "/" .. line) or ""
                ok(not body:lower():find("catalogscan", 1, true), line .. ": no scan code")
                ok(not body:find("gftkdev", 1, true), line .. ": no /gftkdev")
            end
        end
        local pkg = readAll(ROOT_DIR .. "/.pkgmeta")
        ok(pkg and pkg:find("\n  - addon/GreenFangToolkit_Dev", 1, true), ".pkgmeta ignores addon/GreenFangToolkit_Dev")
        ok(readAll(ROOT_DIR .. "/addon/GreenFangToolkit_Dev/GreenFangToolkit_Dev.toc"), "the dev AddOn has its own TOC")
        local ns = login({})
        eq(ns.CatalogScan, nil, "no scan module")
        ns.handleSlash("catalogscan start")
        wow.advance(120)
        eq(ns.db.devCatalogScan, nil, "nothing saved")
        eq(#G.requests, 0, "no requests")
        eq(SlashCmdList.GFTKDEV, nil, "no /gftkdev in the guild AddOn")
    end))

    test("GF-009-13 cold cache: 全部, a name, 類型 / 子類, paging and the filter menus send no item request", done(function()
        for _, noCachedAPI in ipairs({ false, true }) do
            local label = noCachedAPI and " (no IsItemDataCachedByID)" or ""
            local ns = login({ bag = { { 2589, 3 } } })
            G.known[2589] = { name = "亞麻布", classID = 7, sub = 5 } -- in the bags: the client has it
            if noCachedAPI then C_Item.IsItemDataCachedByID = nil end
            ns.Framework.open("supply")
            local UI = ns.SupplyUI
            UI.openForm()
            -- Guild listings of cold items, outside and inside the catalog.
            ns.SupplyListings.activeAll = function() return { { itemID = OFF_LIST }, { itemID = OFF_LIST + 1 }, { itemID = PATTERN } } end
            G.asked, G.requests, G.infoIDs = {}, {}, {}
            UI.openPicker("all")
            local picker = UI.picker()
            UI.pickSearch("布"); UI.pickSearch("青銅"); UI.pickSearch("")
            ok(#UI.pickState.items > 3000, "the whole catalog" .. label)
            local L = ns.SupplyListings
            local classes = L.catalogClasses(UI.pickState.base)
            UI.pickClass(9)
            local subs = L.catalogSubclasses(UI.pickState.base, 9)
            UI.pickSubclass(subs[1] and subs[1].value)
            UI.pickClass(nil)
            local wheel = picker.rows[1]:GetScript("OnMouseWheel")
            wheel(picker.rows[1], -3); wheel(picker.rows[1], -100000); wheel(picker.rows[1], 50)
            UI.pickSearch("藥水"); UI.pickClass(0); UI.pickSearch("秘銀")
            ok(#classes > 3, "the 類型 menu" .. label)
            eq(countKeys(G.asked), 0, "no item asked for" .. label)
            eq(#G.requests, 0, "no RequestLoadItemDataByID" .. label)
            for id in pairs(G.infoIDs) do ok(G.known[id], "GetItemInfo only for items the client has: " .. id .. label) end
            eq(L.requestStats().nameSearch, 0, "the diagnostics count 0 requests in name searches" .. label)
            ok(ns.SupplyCatalog.diagText():find("其中名稱搜尋時 0 次", 1, true), "and say so" .. label)
            ok(ns.SupplyCatalog.diagText():find("清單上次", 1, true), "the list time is shown" .. label)
            -- One typed ItemID is a deliberate request for that item only.
            UI.pickSearch(tostring(OFF_LIST))
            eq(countKeys(G.asked), 1, "a typed ID asks for that one" .. label)
            ok(G.asked[OFF_LIST], "that one" .. label)
        end
    end))

    test("GF-009-13 the catalog's older name, the game's newer one: the game's is shown, searched and listed", done(function()
        local NEW = "青銅錠（新版名稱）"
        local ns = login({ bag = { { BRONZE, 4 } } })
        G.known[BRONZE] = { name = NEW, classID = 7, sub = 7 }
        local old = catalogTable().name[indexOf(BRONZE)]
        ok(old ~= NEW and not old:find("新版", 1, true), "the catalog has the old name: " .. old)
        local UI, picker = openFinder(ns)
        UI.pickSearch("新版名稱")
        ok(has(rowIDs(UI), BRONZE), "found by the game's name")
        eq(picker.rows[1].name._text, NEW, "the row shows the game's name")
        UI.pickSearch(old)
        local idx
        for k, it in ipairs(UI.pickState.items) do if it.itemID == BRONZE then idx = k; eq(it.info.name, NEW, "the old name finds it, the game's is shown") end end
        ok(idx, "still found by the catalog's name")
        UI.pickChoose(idx - UI.pickState.offset)
        eq(UI.formState.preview, "ready", "ready")
        eq(UI.form().itemName._text, NEW, "the form shows the game's name")
        UI.form().qty:SetText("2")
        local l = UI.submitForm()
        ok(l and l.itemID == BRONZE, "listed by ItemID")
    end))

    test("GF-009-13 one resolve path: ID, link, drag (form and finder) give the same preview; timeout, not found and untradeable differ", done(function()
        local COLD, GONE, NOPE, BOP = 990101, 990102, 990103, 990104
        local ns = login({})
        local L = ns.SupplyListings
        G.known[BOP] = { name = "拾綁戒指", classID = 4, sub = 0, bindType = 1 }
        G.exists[GONE] = false
        local UI = openFinder(ns)
        local f = UI.form()
        local function via(way, id)
            UI.setFormItem(nil)
            if way == "id" then UI.formFromText(tostring(id))
            elseif way == "link" then UI.formFromText("|cffffffff|Hitem:" .. id .. "::::::::|h[x]|h|r")
            elseif way == "slot" then G.cursor = id; f.slot:GetScript("OnReceiveDrag")(f.slot)
            else UI.openPicker("all"); G.cursor = id; UI.picker():GetScript("OnReceiveDrag")(UI.picker()) end
            eq(UI.formState.itemID, id, way .. ": the item")
            return UI.formState.preview, f.msg._text
        end
        local msgs = {}
        for _, way in ipairs({ "id", "link", "slot", "finder" }) do
            local st, msg = via(way, GONE)
            eq(st, "missing", way .. ": the client says no such item"); eq(msg, UI.PREVIEW_TEXT.missing, way .. ": 找不到")
            msgs.missing = msg
            st, msg = via(way, BOP)
            eq(st, "blocked", way .. ": bind on pickup"); ok(msg:find("不能交易", 1, true), way .. ": " .. msg)
            msgs.blocked = msg
            st = via(way, NOPE)
            eq(st, "loading", way .. ": asked")
            wow.fire("GET_ITEM_INFO_RECEIVED", NOPE, false)
            eq(UI.formState.preview, "missing", way .. ": the server answered no")
            eq(f.msg._text, UI.PREVIEW_TEXT.missing, way .. ": 找不到 after the answer")
            L.failed[NOPE] = nil
            st = via(way, COLD)
            eq(st, "loading", way .. ": waiting")
            wow.advance(L.LOAD_WAIT + 1)
            eq(UI.formState.preview, "timeout", way .. ": no answer in time")
            eq(f.msg._text, UI.PREVIEW_TEXT.timeout, way .. ": 逾時")
            msgs.timeout = f.msg._text
            local l = UI.submitForm()
            ok(not l, way .. ": a timed-out item is not listed")
        end
        ok(msgs.missing ~= msgs.timeout and msgs.timeout ~= msgs.blocked and msgs.missing ~= msgs.blocked, "three different messages")
    end))

    test("GF-009-13 供應 looks at the bag stacks: all bound refused, one free fine, none in the bags fine; 徵求 unchanged", done(function()
        local CLOTH = 2589
        local ns = login({ bag = { { CLOTH, 2, true } } })
        G.known[CLOTH] = { name = "亞麻布", classID = 7, sub = 5 }
        local L = ns.SupplyListings
        eq(L.bagBound(CLOTH), "bound", "every stack bound")
        local UI = openFinder(ns)
        local f = UI.form()
        UI.formFromText(tostring(CLOTH))
        eq(UI.formState.direction, "need", "徵求 first")
        eq(f.msg._text, "", "徵求: my bags do not matter")
        wow.click(f.dirs.buttons[2])
        eq(UI.formState.direction, "offer", "供應")
        eq(f.msg._text, L.BOUND_OFFER, "供應: the bound stack is refused at once")
        f.qty:SetText("1")
        local l, why = UI.submitForm()
        ok(not l and why == L.BOUND_OFFER, "and on 刊登: " .. tostring(why))
        G.bag[2] = { CLOTH, 1 }
        eq(L.bagBound(CLOTH), "free", "one free stack")
        UI.formRecheck()
        eq(f.msg._text, "", "message cleared")
        ok(UI.submitForm(), "供應 listed")
        G.bag = {}
        eq(L.bagBound(CLOTH), nil, "none in the bags")
        G.known[PATTERN] = { name = "設計圖：秘銀短褲", classID = 9, sub = 3 }
        ok(L.create({ direction = "offer", itemID = PATTERN, quantity = 1, days = 7, note = "" }), "供應 without a stack (it can be made)")
        G.bag = { { CLOTH, 2, true } }
        ok(L.create({ direction = "need", itemID = CLOTH, quantity = 1, days = 7, note = "" }), "徵求 with only bound stacks")
    end))

    -- UIParent at a resolution and UI scale: 768 / scale units high, the
    -- screen's aspect wide (the client's rule).
    local SCREENS = {
        { "1280x720 @0.64", 1280, 720, 0.64 }, { "1280x720 @1.0", 1280, 720, 1.0 },
        { "1920x1080 @0.64", 1920, 1080, 0.64 }, { "1920x1080 @1.0", 1920, 1080, 1.0 },
        { "1024x768 @1.0 (4:3)", 1024, 768, 1.0 },
    }
    local function setScreen(pw, ph, scale)
        local h = 768 / scale
        local w = h * pw / ph
        UIParent.GetWidth = function() return w end
        UIParent.GetHeight = function() return h end
        UIParent.GetEffectiveScale = function() return scale end
        return w, h
    end
    -- left, bottom, right, top of a frame placed by CENTER / TOPLEFT on UIParent.
    local function rectOf(f, w, h, sw, sh)
        local p = f._points[#f._points]
        if p[1] == "CENTER" and p[2] == UIParent then
            local cx, cy = sw / 2 + (p[4] or 0), sh / 2 + (p[5] or 0)
            return cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
        end
        assert(p[1] == "TOPLEFT" and p[2] == UIParent and p[3] == "BOTTOMLEFT", "placed on UIParent: " .. tostring(p[1]))
        return p[4], p[5] - h, p[4] + w, p[5]
    end
    local function inside(name, l, b, r, t, sw, sh)
        ok(l >= 0 and b >= 0 and r <= sw + 0.01 and t <= sh + 0.01,
            string.format("%s on screen: %.0f,%.0f-%.0f,%.0f in %.0fx%.0f", name, l, b, r, t, sw, sh))
    end

    test("GF-009-13 screens: form and 找物品 stay on screen at 1280x720 / 1920x1080 and UI scale 0.64 / 1.0 (and 4:3)", done(function()
        for _, s in ipairs(SCREENS) do
            local ns = login({})
            local sw, sh = setScreen(s[2], s[3], s[4])
            ns.Framework.open("supply")
            local UI = ns.SupplyUI
            UI.openForm()
            local f = UI.form()
            local a1, b1, c1, d1 = rectOf(f, UI.FORM_W, UI.FORM_H, sw, sh)
            inside(s[1] .. " form alone", a1, b1, c1, d1, sw, sh)
            UI.openPicker("all")
            local fl, fb, fr, ft = rectOf(f, UI.FORM_W, UI.FORM_H, sw, sh)
            local pl, pb, pr, pt = rectOf(UI.picker(), UI.PICK_W, UI.pickHeight(), sw, sh)
            inside(s[1] .. " form", fl, fb, fr, ft, sw, sh)
            inside(s[1] .. " 找物品", pl, pb, pr, pt, sw, sh)
            if sw >= UI.FORM_W + UI.PICK_W + UI.PICK_GAP + 2 * UI.SCREEN_EDGE then
                ok(pl >= fr or pr <= fl, s[1] .. ": side by side, not covering the form")
            else
                ok(pr <= sw, s[1] .. ": too narrow for both: the finder covers part of the form")
            end
            ok(math.abs(pt - ft) < 1, s[1] .. ": tops line up")
            -- The form comes back to the middle next time.
            UI.picker():Hide(); UI.closeForm(true); UI.openForm()
            eq(f._points[#f._points][1], "CENTER", s[1] .. ": the form re-centred")
            -- The finder alone (no form) in the middle.
            UI.closeForm(true); UI.openPicker("bag")
            local a2, b2, c2, d2 = rectOf(UI.picker(), UI.PICK_W, UI.pickHeight(), sw, sh)
            inside(s[1] .. " 找物品 alone", a2, b2, c2, d2, sw, sh)
            T.realPrint(string.format("     SCREEN GF-009-13 %-20s UIParent %4.0fx%4.0f: form %4.0f-%4.0f, 找物品 %4.0f-%4.0f", s[1], sw, sh, fl, fr, pl, pr))
        end
    end))

    test("GF-009-13 layoutPair: right, left, moved to fit, or overlapped on a very narrow screen; always inside", function()
        local ns = wow.loadAddon(ADDON_DIR)
        local UI = ns.SupplyUI
        local E = UI.SCREEN_EDGE
        local cases = {
            { 2133, 1200, 766, 1080, "right" },  -- room on the right
            { 2133, 1200, 1500, 1080, "left" },  -- the form moved right by the player: left of it
            { 1365, 768, 382, 659, "moved" },    -- 1280x720 @1.0: the form moves so both fit
            { 1024, 768, 212, 659, "over" },     -- 4:3 @1.0: narrower than both
            { 1365, 300, 382, 1000, "short" },   -- a short screen: pulled down / up
        }
        for _, c in ipairs(cases) do
            local sw, sh = c[1], c[2]
            local fl, ft, px, pt = UI.layoutPair(sw, sh, UI.FORM_W, UI.FORM_H, UI.PICK_W, UI.pickHeight(), c[3], c[4])
            ok(fl >= E - 0.01 and fl + UI.FORM_W <= sw - E + 0.01, c[5] .. ": form x inside")
            ok(px >= E - 0.01 and px + UI.PICK_W <= sw - E + 0.01, c[5] .. ": finder x inside")
            ok(ft <= sh - E + 0.01 and pt <= sh - E + 0.01, c[5] .. ": tops inside")
            if c[5] == "right" then eq(px, c[3] + UI.FORM_W + UI.PICK_GAP, "right of the form") end
            if c[5] == "left" then eq(px, c[3] - UI.PICK_GAP - UI.PICK_W, "left of the form") end
            if c[5] == "moved" then ok(fl < c[3] and px >= fl + UI.FORM_W, "the form moved left, the finder beside it") end
            if c[5] == "over" then ok(px < fl + UI.FORM_W, "covers the form's right side") end
        end
    end)

    test("GF-009-13 ESC, the window's X and tooltips: the finder, then the form (asks), then the window; nothing left behind; the draft comes back", done(function()
        local srv = { [BRONZE] = { name = "青銅錠", classID = 7, sub = 7 } }
        local ns = login({ server = srv })
        G.known[BRONZE] = srv[BRONZE]
        local UI, picker = openFinder(ns)
        local f = UI.form()
        local win = _G[ns.Framework.WINDOW_NAME]
        UI.formFromText(tostring(BRONZE))
        f.qty:SetText("7"); f.note:SetText("測試草稿")
        UI.openPicker("all")
        UI.pickSearch("青銅")
        picker.rows[1]:GetScript("OnEnter")(picker.rows[1])
        eq(GameTooltip:GetOwner(), picker.rows[1], "a row's tooltip")
        -- ESC 1: the finder (and its tooltip).
        wow.pressEscape()
        ok(not picker:IsShown(), "ESC closes the finder first")
        eq(GameTooltip:GetOwner(), nil, "its tooltip went with it")
        ok(f:IsShown() and win:IsShown(), "form and window stay")
        -- ESC 2: the form asks (unsaved changes); 繼續編輯 keeps everything.
        wow.pressEscape()
        ok(wow.popup() ~= nil, "asks before dropping the changes")
        ok(f:IsShown(), "the form is still there")
        wow.cancelPopup()
        eq(f.qty:GetText(), "7", "quantity kept"); eq(f.note:GetText(), "測試草稿", "note kept")
        -- The window's X while the form and the finder are open: nothing stays on screen.
        UI.openPicker("all")
        f.qty.tip = f.qty.tip or "數量"
        win:Hide()
        ok(not f:IsShown(), "the form closed with the window")
        ok(not picker:IsShown(), "the finder closed with the window")
        eq(wow.popup(), nil, "no question when the window went away")
        ok(UI.draft ~= nil, "the form's contents are kept as a draft")
        -- Back: ＋刊登 brings the draft back (still unsaved: ESC asks again).
        ns.Framework.open("supply")
        UI.openForm()
        eq(UI.formState.itemID, BRONZE, "draft item"); eq(f.qty:GetText(), "7", "draft quantity"); eq(f.note:GetText(), "測試草稿", "draft note")
        eq(f.msg._text, UI.DRAFT_BACK, "says it came back")
        ok(UI.formDirty(), "still unsaved")
        eq(UI.draft, nil, "used once")
        -- Saving drops it for good.
        ok(UI.submitForm(), "listed")
        ns.Framework.open("supply"); UI.openForm()
        eq(f.note:GetText(), "", "a new form after saving")
        -- A discarded form leaves no draft.
        f.note:SetText("丟掉"); wow.pressEscape(); wow.acceptPopup()
        ok(not f:IsShown(), "discarded"); eq(UI.draft, nil, "no draft after 放棄")
        -- The roster's member card goes with the window (ESC).
        ns.Framework.open("roster")
        local row
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberGuid then row = r; break end end
        if row then
            ns.UI.showRowTooltip(row, nil)
            ok(ns.UI.rosterCard():IsShown(), "the member card")
            wow.pressEscape()
            ok(not win:IsShown(), "ESC closed the window")
            ok(not ns.UI.rosterCard():IsShown(), "the member card is not left behind")
        else
            ok(false, "a roster row to hover")
        end
    end))

    test("GF-009-13 fix: the form's preview fills on ITEM_DATA_LOAD_RESULT, and a late answer clears 逾時", done(function()
        local A, B = 990201, 990202
        local ns = login({})
        local UI = openFinder(ns)
        UI.formFromText(tostring(A))
        eq(UI.formState.preview, "loading", "asked")
        G.known[A] = { name = "載入事件的布", classID = 7, sub = 5 }
        wow.fire("ITEM_DATA_LOAD_RESULT", A, true)
        eq(UI.formState.preview, "ready", "filled by ITEM_DATA_LOAD_RESULT")
        eq(UI.form().itemName._text, "載入事件的布", "name")
        UI.formFromText(tostring(B))
        wow.advance(ns.SupplyListings.LOAD_WAIT + 1)
        eq(UI.formState.preview, "timeout", "no answer in time")
        G.known[B] = { name = "晚到的布", classID = 7, sub = 5 }
        wow.fire("ITEM_DATA_LOAD_RESULT", B, true)
        eq(UI.formState.preview, "ready", "the late answer clears 逾時")
        UI.formFromText("990203")
        wow.fire("ITEM_DATA_LOAD_RESULT", 990203, false)
        eq(UI.formState.preview, "missing", "a failed load: no such item")
    end))

    test("GF-009-13 fix, the owner's probe: only C_Item.GetItemInfo answers (|cnIQ1: links): preview, finder, link parsing and the item link", done(function()
        local LINEN = 2589
        local ns = login({ bag = { { LINEN, 3 } } })
        local known = { [LINEN] = { name = "亞麻布", classID = 7, sub = 5 } }
        local link = "|cnIQ1:|Hitem:2589::::::::27:1486:::::::::|h[亞麻布]|h|r"
        C_Item.GetItemInfo = function(id)
            local it = known[id]
            if not it then G.asked[id] = true; return nil end
            return it.name, "|cnIQ1:|Hitem:" .. id .. "::::::::27:1486:::::::::|h[" .. it.name .. "]|h|r", 1, 5, 0, "商品", "布料", 20,
                "INVTYPE_NON_EQUIP_IGNORE", 132889, 13, it.classID, it.sub, 0, 0, nil, true, ""
        end
        C_Item.IsItemDataCachedByID = function(id) return known[id] ~= nil end
        GetItemInfo = function() end
        local L = ns.SupplyListings
        eq(L.itemFromText(link), LINEN, "the |cnIQ1: link parses")
        eq(L.parseItemInput(link), LINEN, "in the item box too")
        local UI = openFinder(ns)
        UI.formFromText(link)
        eq(UI.formState.preview, "ready", "preview from a |cnIQ1: link")
        eq(UI.form().itemName._text, "亞麻布", "name")
        eq(UI.form().typeText._text, "商品｜布料", "type from the client's texts")
        UI.formFromText(tostring(LINEN))
        eq(UI.formState.preview, "ready", "preview from the ItemID")
        eq(ns.Supply.itemLink(LINEN), link, "the item link (contact text) through C_Item.GetItemInfo")
        UI.openPicker("all")
        UI.pickSearch("亞麻")
        ok(has(rowIDs(UI), LINEN), "the finder lists it")
        UI.openPicker("bag")
        ok(has(rowIDs(UI), LINEN), "and the bag source")
    end))

    test("GF-009-13 fix, Forever has no classic item / bag / quest / talent globals: no AddOn code calls them except behind a C_ path", function()
        local ITEM = { GetItemInfo = true, GetItemInfoInstant = true, GetItemCount = true }
        -- Where an item global may still be named: the shared helper (C_Item first) and
        -- the dev scan's copy of it, Delivery's count (C_Item.GetItemCount first).
        local ITEM_OK = { ["Core.lua"] = true, ["Delivery.lua"] = true, ["Dev/CatalogScan.lua"] = true }
        local files = {}
        for line in readAll(TOC_FILE):gmatch("[^\r\n]+") do
            if line:match("^[%w_]+%.lua$") then files[#files + 1] = { line, ADDON_DIR .. "/" .. line } end
        end
        files[#files + 1] = { "Dev/CatalogScan.lua", ROOT_DIR .. "/addon/GreenFangToolkit_Dev/CatalogScan.lua" }
        local bad = {}
        for _, f in ipairs(files) do
            if f[1] ~= "Probe.lua" then -- the probe lists API names as text on purpose
                local n = 0
                for raw in (readAll(f[2]) or ""):gmatch("[^\n]*") do
                    n = n + 1
                    local line = raw:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
                    for _, name in ipairs(wow.FOREVER_MISSING) do
                        for pre in line:gmatch("([%w_%.:]?)" .. name .. "%f[^%w_]") do
                            if pre == "" or not pre:match("[%w_%.:]") then
                                local guarded = line:find("type(" .. name .. ")", 1, true) or line:find("fn(" .. name .. ")", 1, true)
                                    or line:find("ns.call(" .. name, 1, true)
                                local okHere = ITEM[name] and ITEM_OK[f[1]] or (not ITEM[name] and guarded)
                                if not okHere then bad[#bad + 1] = f[1] .. ":" .. n .. " " .. name end
                            end
                        end
                    end
                end
            end
        end
        eq(table.concat(bad, ", "), "", "global-only calls")
        -- The Forever profile (mock.lua) is the default; GF_CLASSIC_GLOBALS=1 runs without it.
        if wow.forever then eq(GetItemInfo, nil, "no global GetItemInfo under the Forever profile") end
    end)

    ---------------------------------------------------------------------------
    -- GF-009-14
    ---------------------------------------------------------------------------

    -- The window an object sits in: its strata and the top frame under UIParent.
    local function windowOf(o)
        local strata, f, top = nil, o, o
        while f and f ~= UIParent do
            if f._strata and not strata then strata = f._strata end
            top = f
            f = f._parent
        end
        return strata, top
    end

    test("GF-009-14 IME: no edit box of the 刊登 form or 找物品 sits in TOOLTIP or FULLSCREEN_DIALOG; menus still above, ESC order kept", done(function()
        local ns = login({})
        local UI, picker = openFinder(ns)
        local f = UI.form()
        local boxes = { ["找物品 search"] = picker.search, ["物品框"] = f.itemBox, ["數量"] = f.qty, ["備註"] = f.note }
        for name, box in pairs(boxes) do
            local strata, top = windowOf(box)
            ok(top == f or top == picker, name .. ": in the form or the finder")
            ok(strata ~= "TOOLTIP" and strata ~= "FULLSCREEN_DIALOG", name .. ": strata " .. tostring(strata))
        end
        -- Every edit box the supply windows made.
        local n = 0
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "EditBox" then
                local strata, top = windowOf(o)
                if top == f or top == picker then
                    n = n + 1
                    ok(strata ~= "TOOLTIP" and strata ~= "FULLSCREEN_DIALOG", "edit box strata " .. tostring(strata))
                end
            end
        end
        ok(n >= 4, "edit boxes checked: " .. n)
        eq(f._strata, "DIALOG", "the form: DIALOG")
        eq(picker._strata, "DIALOG", "the finder: DIALOG")
        ok(UI.PICK_LEVEL > UI.FORM_LEVEL, "the finder's frame level above the form's")
        -- The 類型 list opened from the finder still sits above it (TOOLTIP).
        local list = picker.class.menu
        if picker.class.open then picker.class.open() elseif picker.class:GetScript("OnClick") then picker.class:GetScript("OnClick")(picker.class) end
        list = list or picker.class.menu
        ok(list and list._strata == "TOOLTIP", "the drop-down list above the finder: " .. tostring(list and list._strata))
        if ns.closeMenus then ns.closeMenus() end
        ok(picker:IsShown(), "closing the list keeps the finder")
        wow.pressEscape()
        ok(not picker:IsShown() and f:IsShown(), "ESC: the finder first")
    end))

    test("GF-009-14 A scroll bar: 全部 → 配方 → 「皮」 over a page; the thumb reaches first to last, arrows / wheel / range text agree, rows reused", done(function()
        local ns = login({})
        local UI, picker = openFinder(ns)
        UI.pickSearch("皮")
        UI.pickClass(9)
        local n = #UI.pickState.items
        ok(n > UI.PICK_ROWS, "more than one page: " .. n)
        local bar = picker.bar
        local max = n - UI.PICK_ROWS
        ok(bar:IsShown(), "the bar is shown"); eq(bar._max, max, "bar range 0..n-10"); eq(bar._value, 0, "at the top")
        eq(picker.title._text, "找物品", "the title")
        local rows = {}
        for i = 1, UI.PICK_ROWS do rows[i] = picker.rows[i] end
        -- Drag the thumb to the end, then back to the start.
        bar:GetScript("OnValueChanged")(bar, max)
        eq(UI.pickState.offset, max, "thumb at the bottom: the last page")
        eq(picker.pos._text, string.format(UI.PICK_POS, max + 1, n, n), "range text: the last rows")
        eq(picker.rows[UI.PICK_ROWS].item, UI.pickState.items[n], "the last item in the last row")
        for i = 1, UI.PICK_ROWS do ok(picker.rows[i] == rows[i], "row " .. i .. " reused") end
        ok(not picker.up.disabled and picker.down.disabled, "at the end: up on, down off")
        bar:GetScript("OnValueChanged")(bar, 0.4)
        eq(UI.pickState.offset, 0, "thumb at the top: the first row")
        eq(picker.pos._text, string.format(UI.PICK_POS, 1, UI.PICK_ROWS, n), "range text: the first rows")
        -- Arrows and the wheel move the thumb too.
        wow.click(picker.down)
        eq(UI.pickState.offset, 1, "down arrow: one row"); eq(bar._value, 1, "the thumb follows")
        picker:GetScript("OnMouseWheel")(picker, -1)
        eq(UI.pickState.offset, 2, "the wheel on the finder"); eq(bar._value, 2, "the thumb follows the wheel")
        picker.rows[3]:GetScript("OnMouseWheel")(picker.rows[3], -2)
        eq(UI.pickState.offset, 4, "the wheel over a row"); eq(bar._value, 4, "thumb")
        wow.click(picker.up)
        eq(UI.pickState.offset, 3, "up arrow"); eq(bar._value, 3, "thumb")
        bar:GetScript("OnValueChanged")(bar, max + 50)
        eq(UI.pickState.offset, max, "past the end: the last page")
        -- A new search or another class starts from the first row.
        UI.pickSearch("皮革")
        eq(UI.pickState.offset, 0, "new search: first row"); eq(bar._value, 0, "thumb at the top")
        bar:GetScript("OnValueChanged")(bar, 1)
        UI.pickClass(7)
        eq(UI.pickState.offset, 0, "another class: first row")
        -- One page or less: no bar; the bag source keeps the title.
        UI.pickSearch(tostring(BRONZE))
        ok(not bar:IsShown(), "one row: no bar")
        UI.pickSource("bag")
        UI.openPicker("bag")
        eq(picker.title._text, "找物品", "always 找物品")
    end))

    test("GF-009-14 A drag: the title bar moves it; kept for the draft, clamped at UI scale 0.64 / 1.0; a new draft anchors beside the form; picking keeps the draft", done(function()
        local srv = { [BRONZE] = { name = "青銅錠", classID = 7, sub = 7 } }
        local ns = login({ server = srv })
        G.known[BRONZE] = srv[BRONZE]
        local sw, sh = setScreen(1920, 1080, 0.64)
        local UI, picker = openFinder(ns)
        local f = UI.form()
        f.qty:SetText("7"); f.note:SetText("拖曳草稿")
        ok(picker.drag and picker.drag._scripts.OnDragStart, "a drag handle on the title bar")
        -- Drag it somewhere: the client's position after StopMovingOrSizing.
        picker.GetLeft = function() return 200 end
        picker.GetTop = function() return 900 end
        picker.drag._scripts.OnDragStart(picker.drag)
        picker.drag._scripts.OnDragStop(picker.drag)
        eq(UI.formState.pickPos and UI.formState.pickPos[1], 200, "remembered for this draft")
        picker.GetLeft, picker.GetTop = nil, nil
        picker:Hide()
        UI.openPicker("all")
        local p = picker._points[#picker._points]
        eq(p[1] .. "," .. p[4] .. "," .. p[5], "TOPLEFT,200,900", "reopened where it was dragged")
        -- At UI scale 1.0 the same place would be off the bottom / right: clamped.
        picker:Hide()
        UI.formState.pickPos = { 5000, 50 }
        sw, sh = setScreen(1280, 720, 1.0)
        UI.openPicker("all")
        local l, b, r, t = rectOf(picker, UI.PICK_W, UI.pickHeight(), sw, sh)
        inside("dragged off screen at 1.0", l, b, r, t, sw, sh)
        sw, sh = setScreen(1280, 720, 0.64)
        picker:Hide(); UI.formState.pickPos = { -300, 5000 }
        UI.openPicker("all")
        l, b, r, t = rectOf(picker, UI.PICK_W, UI.pickHeight(), sw, sh)
        inside("dragged off screen at 0.64", l, b, r, t, sw, sh)
        -- Pick an item: back in the form, the draft is intact.
        UI.pickSearch("青銅錠")
        local idx
        for k, it in ipairs(UI.pickState.items) do if it.itemID == BRONZE then idx = k end end
        UI.pickChoose(idx - UI.pickState.offset)
        eq(UI.formState.itemID, BRONZE, "picked")
        eq(f.qty:GetText(), "7", "quantity kept"); eq(f.note:GetText(), "拖曳草稿", "note kept")
        ok(UI.formState.pickPos ~= nil, "the dragged place stays for this draft")
        -- A new draft: beside the form again.
        UI.closeForm(true)
        UI.openForm()
        eq(UI.formState.pickPos, nil, "a new draft forgets it")
        UI.openPicker("all")
        local fl, fb, fr, ft = rectOf(f, UI.FORM_W, UI.FORM_H, sw, sh)
        l, b, r, t = rectOf(picker, UI.PICK_W, UI.pickHeight(), sw, sh)
        ok(l >= fr or r <= fl, "beside the form")
        -- The draft stash (window closed) keeps the place too.
        picker.GetLeft = function() return 150 end
        picker.GetTop = function() return 800 end
        picker.drag._scripts.OnDragStop(picker.drag)
        picker.GetLeft, picker.GetTop = nil, nil
        f.note:SetText("改過")
        _G[ns.Framework.WINDOW_NAME]:Hide()
        ns.Framework.open("supply"); UI.openForm()
        eq(UI.formState.pickPos and UI.formState.pickPos[1], 150, "restored with the draft")
    end))
end
