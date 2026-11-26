-- GF-009-12: the 找物品 item catalog (SupplyCatalogData.lua in the main TOC,
-- decoded on the first 找物品 → 全部) and the owner-only /gftk catalogscan.
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
                return { itemID = it[1], stackCount = it[2], isBound = false, isLocked = false, iconFileID = 134939 }
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
        ns.Supply.resetSession(); ns.SupplyListings.resetSession(); ns.SupplyCatalog.resetSession(); ns.CatalogScan.resetSession()
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
        local strKB = #keep.scan
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
        -- Unknown ID: missing after the wait.
        UI.formFromText("990777")
        wow.advance(ns.SupplyListings.LOAD_WAIT + 1)
        eq(UI.formState.preview, "missing", "no such item")
        eq(UI.form().msg._text, UI.PREVIEW_TEXT.missing, "says so")
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
    -- /gftk catalogscan (owner only)
    ---------------------------------------------------------------------------

    local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
    local function b36(n)
        if n == 0 then return "0" end
        local s = ""
        while n > 0 do local r = n % 36; s = B36:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) end
        return s
    end
    local function pack(ids)
        local out, last = {}, 0
        for _, i in ipairs(ids) do out[#out + 1] = b36(i - last); last = i end
        return table.concat(out, ",")
    end
    local SCAN_IDS = {}
    for i = 1, 40 do SCAN_IDS[i] = 500000 + i * 3 end
    local function scanServer()
        local srv = {}
        for i, id in ipairs(SCAN_IDS) do
            if i % 10 ~= 0 then
                srv[id] = { name = "掃描物品" .. i, classID = 7, sub = 5, quality = 1, ilvl = 10 + i, icon = 1000 + i }
            end
        end
        return srv
    end
    -- The fake server answers every request one second later.
    local function serve(seconds)
        for _ = 1, seconds * 4 do
            wow.advance(0.25)
            for _, r in ipairs(G.requests) do
                if not r.answered and wow.state.now - r.t >= 1 then
                    r.answered = true
                    answer(r.id)
                end
            end
        end
    end

    test("GF-009-12 catalogscan: the shipped list is the export's unnamed IDs; hidden from help; off until typed", done(function()
        local ns = login({})
        local list = ns.SupplyCatalog.scanIDs()
        ok(#list > 10000, "scan list: " .. #list)
        for i = 2, #list do if list[i] <= list[i - 1] then error("not sorted at " .. i) end end
        for _, id in ipairs(list) do if indexOf(id) then error("catalog item in the scan list: " .. id) end end
        wow.clearPrinted()
        ns.handleSlash("help")
        for _, line in ipairs(wow.printed()) do ok(not tostring(line):find("catalogscan", 1, true), "not in help") end
        wow.advance(600)
        eq(ns.db.devCatalogScan, nil, "nothing runs unless typed")
        eq(next(G.asked), nil, "no requests")
        T.realPrint(string.format("     CATALOGSCAN GF-009-12: %d IDs, about %.0f minutes at 4 per second", #list, #list / 4 / 60))
    end))

    test("GF-009-12 catalogscan: 4 per second, 8 waiting, combat and instance pause, stop / resume across logins, item fields only", done(function()
        local ns = login({ scan = pack(SCAN_IDS), server = scanServer() })
        local S = ns.CatalogScan
        ns.handleSlash("catalogscan start")
        ok(ns.db.devCatalogScan and ns.db.devCatalogScan.running, "started")
        -- Rate: no answers for 5 s: at most 8 waiting, never more than 4 in any second.
        local saved = G.server
        wow.advance(5)
        ok(#G.requests <= 8 and #G.requests >= 4, "8 waiting at most: " .. #G.requests)
        for i = 5, #G.requests do ok(G.requests[i].t - G.requests[i - 4].t >= 1 - 1e-6, "4 per second") end
        G.server = saved
        local n0 = #G.requests
        wow.enterCombat()
        wow.advance(20)
        eq(#G.requests, n0, "nothing asked in combat")
        wow.leaveCombat()
        G.instance = true
        wow.advance(20)
        eq(#G.requests, n0, "nothing asked in an instance")
        G.instance = false
        serve(6)
        local d = ns.db.devCatalogScan
        ok(d.pos > 8, "moving on after the pause: " .. d.pos)
        -- Stop: nothing more.
        ns.handleSlash("catalogscan stop")
        local pos = d.pos
        serve(3)
        eq(ns.db.devCatalogScan.pos, pos, "stopped")
        -- Start again, log out and in: it resumes a minute after login.
        ns.handleSlash("catalogscan start")
        local sv = wow.logout()
        ns = login({ saved = sv, scan = pack(SCAN_IDS), server = scanServer(), wait = 1 })
        d = ns.db.devCatalogScan
        ok(d.running, "still on after login")
        local p1 = d.pos
        serve(30)
        eq(ns.db.devCatalogScan.pos, p1, "waits after login")
        serve(150)
        d = ns.db.devCatalogScan
        ok(not d.running and d.finished, "finished")
        local got, none = 0, 0
        for id, r in pairs(d.got) do
            got = got + 1
            eq(#r, 7, "seven fields")
            ok(type(r[1]) == "string" and r[1]:find("掃描物品", 1, true) ~= nil, "name")
            for k = 2, 7 do ok(type(r[k]) == "number", "number field " .. k) end
            ok(has(SCAN_IDS, id), "an ID from the list")
        end
        for _ in pairs(d.none) do none = none + 1 end
        eq(got, 36, "answers kept"); eq(none, 4, "no answer counted")
        local allowed = { v = 1, locale = 1, build = 1, pos = 1, got = 1, none = 1, running = 1, finished = 1 }
        for k in pairs(d) do ok(allowed[k], "only scan fields: " .. tostring(k)) end
        ok(S.statusText():find("完成", 1, true) ~= nil or ns.CatalogScan.statusText():find("完成", 1, true) ~= nil, "status: 完成")
        local text = wow.serializeSV("GreenFangToolkitDB", ns.db.devCatalogScan)
        ok(not text:find("Player%-"), "no GUIDs")
        ns.handleSlash("catalogscan reset")
        eq(ns.db.devCatalogScan, nil, "reset forgets it")
    end))
end
