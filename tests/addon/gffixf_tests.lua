-- GF-FIX-F: fixes from the 0.16.6 review (GF-REVIEW-01, batch F): item data
-- events, item requests, the 找物品 → 全部 reload, the radar and 臨時黑箱
-- redraws; and the 自動集料 / 手動刊登 switches on 綠皮調貨所. Each test name
-- carries the review item. Offline only; made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local CLOTH, HERB, POTION, RING, NOPE = 9102, 9106, 9103, 9104, 990777
    local TYPE = { [0] = "消耗品", [4] = "護甲", [7] = "商品" }
    local function baseItems()
        return {
            [CLOTH] = { name = "測試布", classID = 7, sub = 5 },
            [HERB] = { name = "測試草", classID = 7, sub = 9 },
            [POTION] = { name = "測試藥水", classID = 0, sub = 1 },
            [RING] = { name = "測試指環", classID = 4, sub = 0, bindType = 1 },
        }
    end

    local G
    local function installGame(opts)
        G = { bag = opts.bag or {}, items = opts.items or baseItems(), asked = {}, askN = 0, slots = 0, infoCalls = 0 }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag == 0 then G.slots = G.slots + 1 end
                return bag == 0 and 20 or 0
            end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            G.infoCalls = G.infoCalls + 1
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1,
                TYPE[it.classID] or "", "", 20, "", 134939, 0, it.classID, it.sub or 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function(id) G.asked[id] = (G.asked[id] or 0) + 1; G.askN = G.askN + 1 end,
            IsItemDataCachedByID = function(id) return G.items[id] ~= nil end,
            DoesItemExistByID = function(id) return id ~= NOPE end,
        }
        ChatFrame_SendTellWithMessage = function() end
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        if not opts.catalog then ns.SupplyCatalogData = nil end
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        wow.state.sent = {}
        return ns
    end
    local function counter(tbl, key)
        local c = { n = 0 }
        local real = tbl[key]
        tbl[key] = function(...) c.n = c.n + 1; return real(...) end
        c.restore = function() tbl[key] = real end
        return c
    end
    local function prices(ns, n)
        for i = 1, n do
            ns.Prices.storeReagents(70000 + i, { output = 80000 + i, yield = 1, list = { { id = 81000 + i, n = 2 }, { id = CLOTH, n = 1 } } })
        end
    end
    -- 100 item data answers for items nobody here asked for, 0.05 s apart.
    local function noise(from)
        for i = 1, 100 do
            wow.fire("ITEM_DATA_LOAD_RESULT", (from or 60000) + i, true)
            wow.advance(0.05)
        end
        wow.advance(1)
    end

    ---------------------------------------------------------------------------
    -- 5. Measurements (printed for the report)
    ---------------------------------------------------------------------------

    test("GF-FIX-F measure: 100 unrelated ITEM_DATA_LOAD_RESULT, one 找物品 → 全部 reload", done(function()
        local ns = login({ bag = { { CLOTH, 5 }, { HERB, 2 } }, catalog = true })
        prices(ns, 200)
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        UI.setTab("guild")
        wow.advance(1)
        local r = counter(UI, "refresh")
        noise(60000)
        local pageRedraws = r.n
        UI.openForm()
        local d0 = counter(ns.Prices, "decodeReagents")
        G.slots = 0
        UI.openPicker("all")
        local openScans, openDecodes = G.slots, d0.n
        d0.restore()
        wow.advance(1)
        local p = counter(UI, "pickReload")
        r.n = 0
        noise(61000)
        local pickReloads, pageRedraws2 = p.n, r.n
        p.restore(); r.restore()
        local d = counter(ns.Prices, "decodeReagents")
        G.slots = 0
        UI.pickReload()
        local scans, decodes = G.slots, d.n
        G.slots, d.n = 0, 0
        UI.pickSearch("測試")
        local scans2, decodes2 = G.slots, d.n
        d.restore()
        realPrint(string.format("     [GF-FIX-F measure] 100 unrelated events: page open %d redraws; finder open %d reloads + %d page redraws | 找物品→全部 (200 reagent lists): opening %d bag scans, %d decodes; reload %d bag scans, %d decodes; search %d bag scans, %d decodes",
            pageRedraws, pickReloads, pageRedraws2, openScans, openDecodes, scans, decodes, scans2, decodes2))
        ok(true)
    end))

    ---------------------------------------------------------------------------
    -- 1. 中-16: unrelated item data events
    ---------------------------------------------------------------------------

    test("GF-FIX-F 中-16 unrelated ITEM_DATA_LOAD_RESULT: no redraw, no finder reload, no request", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        UI.openForm()
        UI.openPicker("all")
        wow.advance(1)
        local r, p = counter(UI, "refresh"), counter(UI, "pickReload")
        local d = counter(UI, "drawList")
        local asked = G.askN
        noise(62000)
        wow.fire("GET_ITEM_INFO_RECEIVED", 62500, true)
        wow.advance(1)
        eq(r.n, 0, "page not redrawn"); eq(p.n, 0, "finder not reloaded"); eq(d.n, 0, "rows not drawn")
        eq(G.askN, asked, "nothing asked")
        ok(ns.Widgets.itemEventStats.seen >= 101, "the events arrived")
        r.restore(); p.restore(); d.restore()
    end))

    test("GF-FIX-F 中-16 our own item arrives: the row on screen shows it at once", done(function()
        local items = baseItems()
        local late = items[HERB]; items[HERB] = nil
        local ns = login({ items = items })
        local L, UI = ns.SupplyListings, ns.SupplyUI
        ok(L.create({ direction = "need", itemID = CLOTH, quantity = 1, days = 14, note = "" }), "listed")
        ns.Framework.open("supply")
        UI.setTab("mine")
        -- A second listing of an item the client does not have yet (made before it left the cache).
        items[HERB] = late
        ok(L.create({ direction = "need", itemID = HERB, quantity = 2, days = 14, note = "" }), "listed")
        items[HERB] = nil
        UI.refresh()
        local row
        for i = 1, UI.ROWS do
            local d = UI.state.items[UI.state.offset + i]
            if d and d.itemID == HERB then row = i end
        end
        ok(row, "the herb row is on screen")
        ok(ns.Widgets.itemRequested(HERB), "asked for once")
        items[HERB] = late
        wow.fire("ITEM_DATA_LOAD_RESULT", HERB, true)
        -- No time passes: drawn now.
        local texts = {}
        for _, t in ipairs(wow.allTexts()) do texts[t] = true end
        ok(texts["測試草"], "the name is on the page without waiting")
        ok(not ns.Widgets.itemRequested(HERB), "answered")
    end))

    ---------------------------------------------------------------------------
    -- 2. 中-17: one request per item; success = false remembered
    ---------------------------------------------------------------------------

    test("GF-FIX-F 中-17 one request per item; a missing item is never asked again; redraws do not ask", done(function()
        local ns = login({})
        local Wd, L, UI = ns.Widgets, ns.SupplyListings, ns.SupplyUI
        G.askN = 0
        for _ = 1, 5 do ns.Supply.itemLabel(NOPE) end
        eq(G.asked[NOPE], 1, "asked once for five reads")
        wow.fire("ITEM_DATA_LOAD_RESULT", NOPE, false)
        ok(Wd.itemFailed(NOPE), "remembered: no such item")
        eq(L.failed[NOPE], true, "the form's table is the same one")
        for _ = 1, 5 do ns.Supply.itemLabel(NOPE); L.itemInfo(NOPE) end
        eq(G.asked[NOPE], 1, "never asked again")
        eq((ns.Supply.itemLabel(NOPE)), Wd.TEXT.itemMissing, "the row says it is not found")
        -- An item row (W.itemRow) of a missing item stops waiting.
        local row = Wd.itemRow(UIParent, 200)
        row.set(NOPE, 1)
        eq(Wd.itemsWaiting(), 0, "no row waits for it"); eq(row.name._text, Wd.TEXT.itemMissing, "row text")
        -- No answer: asked again only after REQUEST_AGAIN seconds.
        ns.Supply.itemLabel(990778)
        ns.Supply.itemLabel(990778)
        eq(G.asked[990778], 1, "once")
        wow.advance(Wd.REQUEST_AGAIN + 1)
        ns.Supply.itemLabel(990778)
        eq(G.asked[990778], 2, "again after the wait")
        -- The page drawn many times asks nothing more.
        ns.Framework.open("supply")
        local n = G.askN
        for _ = 1, 10 do UI.refresh() end
        eq(G.askN, n, "redraws do not ask")
    end))

    test("GF-FIX-F 中-17 shownOnPage reads only cached items (no hidden GetItemInfo request)", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        local calls = G.infoCalls
        ok(L.shownOnPage({ itemID = 990779, manual = { quantity = 1 } }), "unknown: shown")
        eq(G.infoCalls, calls, "GetItemInfo not called for an item the client lacks")
        eq(G.asked[990779], nil, "not asked")
        ok(not L.shownOnPage({ itemID = RING, manual = { quantity = 1 } }), "a known bind-on-pickup item: hidden")
    end))

    ---------------------------------------------------------------------------
    -- 3. 中-18: 找物品 → 全部 reloads
    ---------------------------------------------------------------------------

    test("GF-FIX-F 中-18 全部: one bag read per opening, again only after BAG_UPDATE_DELAYED; reagents decoded once", done(function()
        local ns = login({ bag = { { CLOTH, 5 } }, catalog = true })
        prices(ns, 50)
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        UI.openForm()
        local d = counter(ns.Prices, "decodeReagents")
        G.slots = 0
        UI.openPicker("all")
        eq(G.slots, 1, "one bag read when it opens"); eq(d.n, 50, "each reagent text decoded")
        G.slots, d.n = 0, 0
        UI.pickSearch("測試"); UI.pickSearch(""); UI.pickSource("bag"); UI.pickSource("all")
        eq(G.slots, 0, "no bag read for searches and tabs"); eq(d.n, 0, "nothing decoded again")
        -- The bags change: read again (and the new stack shows).
        G.bag[2] = { HERB, 3 }
        wow.fire("BAG_UPDATE_DELAYED")
        UI.pickSource("bag")
        eq(G.slots, 1, "read after the bag event")
        local ids = {}
        for _, e in ipairs(UI.pickState.items) do ids[e.itemID] = e.count end
        eq(ids[HERB], 3, "the new stack is there")
        -- A new reagent list: only that one is decoded.
        ns.Prices.storeReagents(79999, { output = 89999, yield = 1, list = { { id = HERB, n = 1 } } })
        d.n = 0
        UI.pickSource("all")
        eq(d.n, 1, "only the new text")
        d.restore()
    end))

    test("GF-FIX-F 低-22 a catalog row makes its info once", done(function()
        local ns = login({ catalog = true })
        local L = ns.SupplyListings
        local list = L.catalog({ source = "all", text = "" })
        local row
        for _, e in ipairs(list) do if rawget(e, "ci") and rawget(e, "info") == nil then row = e; break end end
        ok(row, "a catalog-only row")
        local a = row.info
        ok(a ~= nil and row.info == a, "the same table on the second read")
    end))

    ---------------------------------------------------------------------------
    -- 4. 低-18 … 低-22
    ---------------------------------------------------------------------------

    test("GF-FIX-F 低-19 the reagent bag is in the bag picker when the client has one", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        Enum = Enum or {}
        local oldBag = Enum.BagIndex
        Enum.BagIndex = { ReagentBag = 5 }
        local slots = C_Container.GetContainerNumSlots
        C_Container.GetContainerNumSlots = function(bag) if bag == 5 then return 4 end return slots(bag) end
        local info = C_Container.GetContainerItemInfo
        C_Container.GetContainerItemInfo = function(bag, slot)
            if bag == 5 and slot == 1 then return { itemID = HERB, stackCount = 7, isBound = false, iconFileID = 1 } end
            return info(bag, slot)
        end
        eq(table.concat(L.bagIndexes(), ","), "0,1,2,3,4,5", "0-4 and 5")
        local found
        for _, e in ipairs(L.bagItems()) do if e.itemID == HERB then found = e.count end end
        eq(found, 7, "a reagent bag stack is offered")
        eq(ns.Supply.BAGS, 4, "the automatic collection still reads 0-4 (PM decision)")
        Enum.BagIndex = oldBag
    end))

    test("GF-FIX-F 低-20 the item box waits 0.25 s for typed digits; a link and Enter are read at once", done(function()
        local ns = login({})
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        UI.openForm()
        local f = UI.form()
        local box = f.itemBox
        G.askN = 0
        for _, t in ipairs({ "9", "99", "990", "9907", "99078", "990780" }) do
            box._text = t
            box._scripts.OnTextChanged(box, true)
        end
        eq(G.askN, 0, "nothing asked while typing")
        wow.advance(UI.ITEM_TYPE_WAIT + 0.01)
        eq(G.asked[990780], 1, "the whole number, once"); eq(G.asked[9907], nil, "not the parts")
        eq(UI.formState.itemID, 990780, "the form has it")
        box._text = "|cffffffff|Hitem:" .. CLOTH .. "::::::::|h[測試布]|h|r"
        box._scripts.OnTextChanged(box, true)
        eq(UI.formState.itemID, CLOTH, "a link at once")
        box._text = tostring(POTION)
        box._scripts.OnTextChanged(box, true)
        box._scripts.OnEnterPressed(box)
        eq(UI.formState.itemID, POTION, "Enter at once")
    end))

    test("GF-FIX-F 低-22 the radar reads the entries once per check; an unchanged scan tells nobody", done(function()
        local ns = login({ bag = { { CLOTH, 5 } } })
        local e = counter(ns.Supply, "entries")
        ns.SupplyRadar.checkNow()
        eq(e.n, 1, "one read for the matches and the bag check")
        e.restore()
        ns.Supply.setAuto(true)
        local n = 0
        local real = ns.Supply.onChanged
        ns.Supply.onChanged = function() n = n + 1 end
        ns.Supply.scanNow()
        ns.Supply.scanNow()
        ns.Supply.onChanged = real
        eq(n, 0, "nothing changed: no redraw")
    end))

    ---------------------------------------------------------------------------
    -- 臨時黑箱 (低-18, 低-21): its own login (bank_tests' way)
    ---------------------------------------------------------------------------

    local A = "0000-0000000A"
    local function bankLogin()
        local r = wow.defaultRoster()
        r[1].rank = "會長"; r[2].rank = "會員"
        wow.reset({ roster = r })
        IsGuildLeader = function() return true end
        local ns = wow.loadAddon(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Supply then ns.Supply.rand = function(a) return a end end
        wow.fire("PLAYER_LOGIN"); wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        ns.Bank.invalidate()
        return ns
    end
    local function bankDone(fn) return function() local okRun, err = pcall(fn); IsGuildLeader = nil; if not okRun then error(err, 0) end end end

    test("GF-FIX-F 低-18 臨時黑箱: other records do not redraw it; a K change does; Bank.current read once per change", bankDone(function()
        local ns = bankLogin()
        local Bk = ns.Bank
        ns.Framework.open("bank")
        local r = counter(ns.BankUI, "refresh")
        -- A change of another group (my manual listings) is not about the custodian list.
        ns.Share.ownRecord("L", "")
        ns.Share.ownRecord("C1", "1//")
        eq(r.n, 0, "not redrawn")
        eq(Bk.appoint("0000-0000000B", "b"), "ok", "appointed")
        ok(r.n >= 1, "redrawn for the K change")
        r.restore()
        local reads = 0
        local dec = ns.Share.decoded
        ns.Share.decoded = function(a, g) if g == Bk.GROUP then reads = reads + 1 end return dec(a, g) end
        ns.BankUI.refresh()
        ns.Share.decoded = dec
        ok(reads <= 1, "the list decoded at most once per draw (" .. reads .. ")")
    end))

    test("GF-FIX-F 低-21 Bank.decode refuses a long value or too many entries before reading them all", bankDone(function()
        local ns = bankLogin()
        local Bk = ns.Bank
        local t = ns.Share.b36(math.floor(ns.Share.serverNow()))
        eq(Bk.decode(nil, "1;" .. t .. ";" .. A .. ";" .. string.rep("x", Bk.MAX_VALUE)), nil, "too long")
        local parts = {}
        for i = 1, Bk.MAX_ACTIVE + Bk.MAX_REVOKED + 1 do parts[i] = string.format("0000-%07d,b,0,%s", i, t) end
        eq(Bk.decode(nil, "1;" .. t .. ";" .. A .. ";" .. table.concat(parts, "/")), nil, "too many")
        ok(Bk.decode(nil, "1;" .. t .. ";" .. A .. ";" .. parts[1]) ~= nil, "a normal one still reads")
    end))

    ---------------------------------------------------------------------------
    -- Part 2: the switches (owner: 「如果是開關，要很明確地展現」)
    ---------------------------------------------------------------------------

    test("GF-FIX-F switches: 開／關 in words, the line says what it does now, clicks turn it over", done(function()
        local ns = login({})
        local UI, S = ns.SupplyUI, ns.Supply
        ns.Framework.open("supply")
        local a, m = UI.autoBox, UI.manualBox
        eq(a.label._text, "自動集料", "name"); eq(m.label._text, "手動刊登", "name")
        eq(S.autoOn(), false, "自動集料 off by default (experimental rule)")
        eq(a.stateText._text, "關", "reads 關"); eq(a.line._text, UI.SWITCH_LINE.auto.off, "off line")
        eq(m.stateText._text, "開", "reads 開"); eq(m.line._text, UI.SWITCH_LINE.manual.on, "on line")
        -- GF-009-15: 「開｜關」 cells; a click on a cell sets that state.
        a.cells.on._scripts.OnClick(a.cells.on)
        eq(S.autoOn(), true, "on"); eq(a.stateText._text, "開", "now 開"); eq(a.line._text, UI.SWITCH_LINE.auto.on, "on line")
        m.cells.off._scripts.OnClick(m.cells.off)
        eq(S.manualOn(), false, "off"); eq(m.stateText._text, "關", "now 關"); eq(m.line._text, UI.SWITCH_LINE.manual.off, "off line")
        eq(UI.postButton.disabled, true, "刊登 cannot be pressed")
        -- Fixed place, apart from the tabs and 收集組 on the left; inside the page.
        local F = ns.Framework
        for _, c in ipairs({ a, m }) do
            local pt = c._points[1]
            ok(pt[4] >= UI.DETAIL_X, "on the right (" .. pt[4] .. ")")
            ok(UI.SWITCH_RIGHT <= F.PANEL_WIDTH - UI.LIST_X, "keeps the right margin")
            ok(-pt[5] + c._h <= -UI.HEAD_Y, "above the column header")
            ok(c.cells.on.tip and c.cells.on.tip ~= "", "a tooltip")
            ok(ns.labelWidth(c.line._text) <= c.line._fixedWidth, "the line fits: " .. c.line._text)
        end
        eq(a._points[1][5], UI.BAR_Y, "自動集料 on the first row"); eq(m._points[1][5], UI.TOOL_Y, "手動刊登 on the second")
        local last = UI.tabs.buttons[#UI.tabs.buttons]
        ok(last._points[1][4] + last._w + 8 <= UI.SWITCH_X.name, "the tabs end before the switches")
        -- GF-009-16: 收集組 is on the filter row, under the switches' rows.
        ok(-UI.FILTER_Y >= -UI.TOOL_Y + ns.BUTTON_H + 4, "收集組 under the switches")
        -- The words: no jokes on the switches themselves.
        for _, t in ipairs({ UI.SWITCH_STATE.on, UI.SWITCH_STATE.off, UI.AUTO_TEXT, UI.MANUAL_TEXT,
            UI.SWITCH_HELP.auto.text }) do -- GF-UI-S: 手動刊登's 說明 is gone
            ok(ns.labelWidth(t) < 120, "short: " .. t)
        end
    end))

    test("GF-FIX-F 自動集料 card: what it does, what it shares and not, why off; items come from SupplyRules", done(function()
        local ns = login({})
        local UI, Rules = ns.SupplyUI, ns.SupplyRules
        ns.Framework.open("supply")
        UI.autoBox.help._scripts.OnClick(UI.autoBox.help)
        local f = UI.card("auto")
        ok(f and f:IsShown(), "the card opens next to the switch")
        -- GF-UI-S: the card is 集料項目 (the items only); its sentences moved to the 說明 mode.
        eq(f.title._text, "集料項目", "title")
        eq(#f.lines, 0, "no sentences on the card")
        local all = ns.Help.TEXT.supply_auto[2]
        for _, word in ipairs({ "任務進度", "不公開背包", "交易", "實驗功能", "預設關" }) do
            ok(all:find(word, 1, true), "說明 mode says: " .. word)
        end
        -- Every item of every usable rule, in the rule's order, nothing else.
        local want = {}
        for _, r in ipairs(Rules.list) do
            if r.usable then for _, ch in ipairs(r.chapters) do for _, it in ipairs(ch.items) do want[#want + 1] = it.itemID end end end
        end
        local got = {}
        for _, row in ipairs(f.itemRows) do if row:IsShown() then got[#got + 1] = row.itemID end end
        eq(table.concat(got, ","), table.concat(want, ","), "the rows are the rule's items")
        eq(#got, 15, "荊棘谷書頁: 15 pages")
        ok(f.itemRows[1].icon ~= nil and f.itemRows[1].name._text == Rules.list[1].chapters[1].items[1].label, "icon row named by its page (GF-UI-N)")
        -- A rule added to the data shows up without touching the page.
        Rules.list[#Rules.list + 1] = { collectionID = "test_rule", num = 9, rulesVersion = 1, state = "experimental", title = "測試收集",
            perItemRequired = 1, chapters = { { questID = 1, title = "第一章", pages = { 1 } } },
            itemIDFor = function() return 990901 end }
        Rules.validate()
        UI.drawCard("auto")
        local n = 0
        for _, row in ipairs(f.itemRows) do if row:IsShown() then n = n + 1 end end
        eq(n, 16, "one more row from the data")
        eq(UI.collectionGroups()[2].title, "測試收集", "its group")
        table.remove(Rules.list); Rules.validate()
        -- Closes with the page.
        ns.Framework.open("bank")
        ok(not f:IsShown(), "gone with the page")
    end))

    test("GF-FIX-F 手動刊登: what turning it off does (GF-UI-S: in the 說明 mode)", done(function()
        local ns = login({})
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        -- GF-UI-S: no 手動刊登說明 card; what it said is in the 說明 mode.
        eq(UI.manualBox.help, nil, "no 說明 button")
        eq(UI.openCard("manual"), nil, "no card")
        local all = ns.Help.TEXT.supply_manual[2]
        for _, word in ipairs({ "關掉後", "不分享也不顯示刊登", "再打開就恢復" }) do
            ok(all:find(word, 1, true), "says: " .. word)
        end
    end))
end
