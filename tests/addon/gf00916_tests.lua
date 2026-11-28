-- GF-009-16: the owner's 0.16.19 screenshots of 綠皮調貨所 — 「調貨所 清單中沒有
-- 看到黑箱資料／且供應與需求這樣表現無法篩選／調貨看板請再確認每個看板的用途與
-- 必要性／如果是比較像篩選器的功能，請用篩選器做」.
-- (A) my own 臨時黑箱 custody is on 調貨看板 too (marked, 聯絡 grey); (B) 徵求,
-- 供應 and 黑箱 are columns of their own and 種類 filters them; (C) the tabs are
-- 調貨看板｜我的刊登, 我缺的／我可能有多的 are 範圍 in the filter row (搜尋, 種類,
-- 範圍, 收集組); (D) the list scrolls, rows use Widgets.rowTip; typing waits
-- at most 0.15 s; filtered rows are kept until the data or a filter changes.
-- Offline only (made-up names, GUIDs and item IDs); nothing checked in game.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, C, E = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000E"
    local PEER_B = "測試乙-測試伺服器"
    local STOCKED, WANTED, OFFERED, MYNEED = 9301, 9302, 9303, 9304

    local function roster()
        local r = wow.defaultRoster()
        r[#r + 1] = { name = "測試戊-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
            zone = "奧格瑪", online = true, guid = "Player-" .. E }
        return r
    end

    local G
    local NAMES = { [STOCKED] = "測試火藥", [WANTED] = "測試炸藥", [OFFERED] = "測試螺栓", [MYNEED] = "測試布" }
    local function installGame()
        G = { bags = {}, whispers = {} }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bags[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = false, isLocked = false, iconFileID = 134939,
                    hyperlink = "|cffffffff|Hitem:" .. it[1] .. "::::::::|h[物品]|h|r" }
            end,
        }
        G.enum = Enum
        Enum = {}
        for k, v in pairs(G.enum or {}) do Enum[k] = v end
        Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, AccountBankTab_1 = 15 }
        for i = 1, 9 do Enum.BagIndex["CharacterBankTab_" .. i] = 5 + i end
        C_Item = {
            GetItemIconByID = function() return 134939 end,
            GetItemNameByID = function(id) return NAMES[id] or ("物品" .. id) end,
            RequestLoadItemDataByID = function() end,
            GetItemInfoInstant = function(id) return id, "類別", "子類別", "", 134939, 7, 0 end,
            IsItemDataCachedByID = function() return true end,
        }
        GetItemInfo = function(id)
            local n = NAMES[id] or ("物品" .. id)
            return n, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. n .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939, 0, 7, 0, 0
        end
        ChatFrame_SendTellWithMessage = function(name, text) G.whispers[#G.whispers + 1] = { name = name, text = text } end
    end
    local function removeGame()
        C_QuestLog, C_Container, C_Item, GetItemInfo, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil
        if G then Enum = G.enum end
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function list(ns, epoch, entries)
        local d = { epoch = epoch, leader = B, entries = {} }
        for _, e in ipairs(entries) do d.entries[#d.entries + 1] = { a = e[1], kinds = e[2], enabled = true, epoch = epoch } end
        return assert(ns.Bank.encode(d))
    end
    local function offer(ns, a, g, v, t) return ns.Share.offer(a, g, t or T0(), ns.Share.hash(v), v, true, a) end
    local function offerStock(ns, a, bags, t)
        local K = ns.BankStock
        t = t or T0()
        offer(ns, a, "KSB", (K.encodePart(bags)), t)
        return offer(ns, a, "KS", K.encodeHead({ bags = "1", tabs = {} }), t)
    end
    -- Member B's manual listings (the 「L」 group).
    local function peerListings(ns, list)
        local t = T0() - 60
        local out = {}
        for i, l in ipairs(list) do
            out[i] = { id = i, direction = l[1], category = "other", itemID = l[2], quantity = l[3] or 1, createdAt = t,
                expiresAt = t + 86400, rev = 1, note = l[4] or "" }
        end
        from(ns, PEER_B, vMsg(ns, B, "L", t, ns.SupplyListings.encode(out)))
    end

    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = roster() })
        installGame()
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        wow.state.sent = {}
        ns.Bank.invalidate()
        return ns
    end
    -- I (A) am the only custodian, as in the owner's screenshot; my bag holds STOCKED.
    local function custodian(opts)
        opts = opts or {}
        local ns = login(opts)
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, "K", t, list(ns, t, opts.entries or { { A, "bk" } })))
        ns.Bank.setScope("bags", 0, true)
        ns.BankStock.setConsent(true)
        G.bags[1] = { STOCKED, 5 }
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01)
        wow.advance(5)
        return ns
    end
    local function find(UI, id)
        for i, d in ipairs(UI.state.items) do if d.itemID == id then return d, i end end
        return nil
    end
    local function rowShowing(UI, idx)
        UI.state.offset = math.max(0, idx - 1); UI.drawList()
        for _, r in ipairs(UI.rows()) do if r.index == idx and r:IsShown() then return r end end
        return nil
    end

    ---------------------------------------------------------------------------
    -- A. 黑箱 data on 調貨看板
    ---------------------------------------------------------------------------

    test("GF-009-16 A: my own 臨時黑箱 custody is on 調貨看板 (it was left out), marked, 聯絡 grey", done(function()
        local ns = custodian()
        ok(#ns.BankStock.rows() > 0, "the stock is there (BankStock.rows)")
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        eq(UI.state.tab, "guild", "調貨看板 is the first page")
        local d, idx = find(UI, STOCKED)
        ok(d, "my custody is listed")
        eq(d.cells[3], "5 個", "黑箱 column")
        eq(d.cells[1], "", "no 徵求"); eq(d.cells[2], "", "no 供應")
        ok(d.stockLine and d.stockLine:find("黑箱 5 個（1 位保管人，含我）", 1, true), "the mark says it is mine: " .. tostring(d.stockLine))
        local r = rowShowing(UI, idx)
        ok(r and r.where:GetText():find("含我", 1, true), "the row's second line")
        UI.select(idx)
        local dr = UI.detailRowList()[1]
        eq(dr.name:GetText(), UI.STOCK_OWN_NAME, "the detail line: 我保管的黑箱")
        ok(dr.contact:IsShown(), "聯絡 there")
        eq(dr.contact.disabled, true, "聯絡 grey: it is me")
        -- 種類 黑箱 keeps it, 徵求 hides it.
        UI.setKind("stock"); ok(find(UI, STOCKED), "種類 黑箱")
        UI.setKind("need"); eq(find(UI, STOCKED), nil, "種類 徵求")
    end))

    test("GF-009-16 A: mine and another custodian's: one row, both counted, the other one can be contacted", done(function()
        local ns = custodian({ entries = { { A, "bk" }, { E, "bk" } } })
        offerStock(ns, E, { [STOCKED] = 3 })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.refresh()
        local d, idx = find(UI, STOCKED)
        ok(d, "listed")
        eq(d.cells[3], "8 個", "5 mine + 3 theirs")
        ok(d.stockLine:find("（2 位保管人，含我）", 1, true), "two custodians: " .. d.stockLine)
        UI.select(idx)
        local rows = UI.detailRowList()
        eq(rows[1].name:GetText(), UI.STOCK_NAME, "the other custodian first")
        ok(not rows[1].contact.disabled, "聯絡 works")
        eq(rows[2].name:GetText(), UI.STOCK_OWN_NAME, "mine after")
        eq(rows[2].contact.disabled, true, "mine grey")
        wow.click(rows[1].contact)
        eq(G.whispers[#G.whispers].name, "測試戊-測試伺服器", "whispers the other custodian")
    end))

    ---------------------------------------------------------------------------
    -- B. 徵求／供應: own columns, filtered by 種類
    ---------------------------------------------------------------------------

    test("GF-009-16 B: 徵求, 供應 and 黑箱 columns; 種類 全部／徵求／供應／黑箱; the detail follows 種類", done(function()
        local ns = custodian()
        ns.Supply.setManual(true)
        peerListings(ns, { { "need", WANTED, 1, "123123" }, { "offer", OFFERED, 2 }, { "need", STOCKED, 1 } })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.refresh()
        local heads = {}
        for i = 1, #UI.HEADINGS.guild do heads[i] = UI.header.cells[i]:GetText() end
        eq(table.concat(heads, ","), "物品,徵求,供應,黑箱,在線,時效", "one column each")
        local w = find(UI, WANTED)
        eq(w.cells[1], "1 位", "徵求 1"); eq(w.cells[2], "", "供應 none")
        local o = find(UI, OFFERED)
        eq(o.cells[1], "", "徵求 none"); eq(o.cells[2], "1 位", "供應 1")
        local s = find(UI, STOCKED)
        eq(s.cells[1], "1 位", "someone asks for what is in 黑箱"); eq(s.cells[3], "5 個", "and 黑箱 has it")
        -- The cells' colours: 徵求 gold, 供應 green, 黑箱 purple.
        eq(UI.BOARD_CELL_COLORS[1], UI.NEED_COLOR); eq(UI.BOARD_CELL_COLORS[2], UI.OFFER_COLOR); eq(UI.BOARD_CELL_COLORS[3], UI.STOCK_COLOR)
        local function ids()
            local t = {}
            for _, d in ipairs(UI.state.items) do t[d.itemID] = true end
            return t
        end
        UI.kindDrop.choose("need")
        local k = ids(); ok(k[WANTED] and k[STOCKED] and not k[OFFERED], "只看徵求")
        UI.kindDrop.choose("offer")
        k = ids(); ok(k[OFFERED] and not k[WANTED] and not k[STOCKED], "只看供應")
        UI.kindDrop.choose("stock")
        k = ids(); ok(k[STOCKED] and not k[WANTED] and not k[OFFERED], "只看黑箱")
        -- The detail of 測試火藥 under 種類 徵求: only the person asking.
        UI.kindDrop.choose("need")
        local _, idx = find(UI, STOCKED)
        UI.select(idx)
        eq(#UI.peopleOf(UI.state.items[idx]), 1, "only the 徵求 line")
        ok(UI.detailRowList()[1].what:GetText():find("徵求", 1, true), "徵求 1")
        UI.kindDrop.choose("all")
        _, idx = find(UI, STOCKED)
        eq(#UI.peopleOf(UI.state.items[idx]), 2, "全部: 徵求 and my 黑箱")
        ok(UI.detail.sub:GetText():find("徵求 1 位｜黑箱 5 個", 1, true), "the detail line: " .. UI.detail.sub:GetText())
    end))

    ---------------------------------------------------------------------------
    -- C. Two tabs, the filter row
    ---------------------------------------------------------------------------

    test("GF-009-16 C: tabs 調貨看板｜我的刊登; one filter row 搜尋／種類／範圍／收集組, inside the page, nothing overlaps", done(function()
        local ns = login()
        ns.Framework.open("supply")
        local UI, F = ns.SupplyUI, ns.Framework
        local texts = {}
        for _, b in ipairs(UI.tabs.buttons) do texts[#texts + 1] = b._text or b.text and b.text._text end
        eq(#UI.tabs.buttons, 2, "two tabs")
        eq(UI.TABS[1].text .. "," .. UI.TABS[2].text, "調貨看板,我的刊登", "their names")
        local function rect(o, w)
            local pt = o._points[1]
            return { l = pt[4], t = -pt[5], r = pt[4] + (w or o._w), b = -pt[5] + (o._h or 30) }
        end
        local boxes = {
            rect(UI.searchLabel, wow.textWidth("搜尋", ns.FIELD_FONT)), rect(UI.searchBox),
            rect(UI.kindLabel, wow.textWidth("種類", ns.FIELD_FONT)), rect(UI.kindDrop),
            rect(UI.scopeLabel, wow.textWidth("範圍", ns.FIELD_FONT)), rect(UI.scopeDrop),
            rect(UI.groupLabel, wow.textWidth("收集組", ns.FIELD_FONT)), rect(UI.groupButton),
        }
        for i, b in ipairs(boxes) do
            eq(b.t, -UI.FILTER_Y + (i % 2 == 1 and 6 or 0), "on the filter row")
            ok(b.r <= F.PANEL_WIDTH - UI.LIST_X, "inside the page")
            ok(-UI.FILTER_Y + 30 <= -UI.HEAD_Y, "above the column header")
            if i > 1 then ok(boxes[i - 1].r + 4 <= b.l, "a gap after the one before (" .. i .. ")") end
        end
        ok(-UI.TOOL_Y + 30 <= -UI.FILTER_Y, "under the tool row")
        ok(-(UI.TOP - UI.ROWS * UI.ROW_H) <= F.PANEL_HEIGHT - 20, "the last row inside the page")
        -- 我的刊登: 搜尋 and 種類 (全部／徵求／供應) only.
        UI.showTab("mine")
        ok(UI.searchBox:IsShown() and UI.kindDrop:IsShown(), "搜尋, 種類")
        ok(not UI.scopeDrop:IsShown() and not UI.groupButton:IsShown(), "no 範圍, no 收集組")
        eq(#UI.kindDrop.items, 3, "全部／徵求／供應")
        UI.showTab("guild")
        ok(UI.scopeDrop:IsShown() and UI.groupButton:IsShown(), "back on 調貨看板")
        eq(#UI.kindDrop.items, 4, "全部／徵求／供應／黑箱")
    end))

    test("GF-009-16 C: 範圍 我缺的／我可能有多的／和我有關的; the old tab keys still open them (notices)", done(function()
        local ns = custodian()
        ns.Supply.setManual(true)
        local L = ns.SupplyListings
        ok(L.create({ direction = "need", itemID = MYNEED, quantity = 2, days = 14, note = "" }), "my need, nobody offers")
        ok(L.create({ direction = "need", itemID = OFFERED, quantity = 1, days = 14, note = "" }), "my need, B offers")
        ok(L.create({ direction = "offer", itemID = WANTED, quantity = 1, days = 14, note = "" }), "my offer, B asks")
        peerListings(ns, { { "need", WANTED, 1 }, { "offer", OFFERED, 2 } })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.refresh()
        local function ids()
            local t, n = {}, 0
            for _, d in ipairs(UI.state.items) do t[d.itemID] = true; n = n + 1 end
            return t, n
        end
        local all, n = ids()
        ok(all[MYNEED] and all[OFFERED] and all[WANTED] and all[STOCKED], "全部: everything (" .. n .. ")")
        local d = find(UI, MYNEED)
        eq(d.mineText, "我徵求 2", "my own part on the row")
        eq(d.cells[1], "1 位", "I am counted in 徵求")
        UI.scopeDrop.choose("need")
        local k = ids(); ok(k[MYNEED] and k[OFFERED] and not k[WANTED] and not k[STOCKED], "我缺的")
        UI.scopeDrop.choose("offer")
        k = ids(); ok(k[WANTED] and not k[MYNEED], "我可能有多的")
        UI.scopeDrop.choose("match")
        k = ids(); ok(k[OFFERED] and k[WANTED] and not k[MYNEED] and not k[STOCKED], "和我有關的: someone answers")
        -- A notice's jump with the old key: filters off, then 範圍; the same list as UI.listFor.
        UI.setKind("offer")
        UI.setTab("need")
        eq(UI.state.tab, "guild", "on 調貨看板")
        eq(UI.state.filter.scope, "need", "範圍 我缺的"); eq(UI.state.filter.kind, "all", "種類 back to 全部")
        local lf = UI.listFor("need")
        eq(#lf, #UI.state.items, "listFor = the page")
        for i, x in ipairs(lf) do eq(x.itemID, UI.state.items[i].itemID, "same order " .. i) end
        ok(ns.SupplyRadar.focusSupply(OFFERED, { tab = "need" }), "the radar's jump finds it")
        eq(UI.state.items[UI.state.selected].itemID, OFFERED, "chosen")
        -- 我的刊登 keeps its own rows and buttons; 種類 filters them by direction.
        UI.showTab("mine")
        eq(#UI.state.items, 3, "my three listings")
        UI.setKind("offer")
        eq(#UI.state.items, 1, "只看供應")
        ok(UI.detail.edit:IsShown(), "修改 there")
    end))

    ---------------------------------------------------------------------------
    -- D. Search, cache, scroll bar, row tooltips, nothing every frame
    ---------------------------------------------------------------------------

    test("GF-009-16 D: 搜尋 waits at most 0.15 s; filters reuse the kept rows; the rows are read again only on new data", done(function()
        local ns = custodian()
        ns.Supply.setManual(true)
        peerListings(ns, { { "need", WANTED, 1 }, { "offer", OFFERED, 2 } })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.refresh()
        ok(UI.SEARCH_DELAY <= 0.15, "at most 0.15 s")
        local st = UI.filterStats
        local base0 = st.base
        UI.searchBox:SetText("炸藥")
        UI.searchBox._scripts.OnTextChanged(UI.searchBox, true)
        ok(#UI.state.items > 1, "not yet")
        wow.advance(UI.SEARCH_DELAY + 0.01)
        eq(#UI.state.items, 1, "one match"); eq(UI.state.items[1].itemID, WANTED, "測試炸藥")
        UI.setSearch("測試乙")
        ok(find(UI, WANTED) and find(UI, OFFERED) and not find(UI, STOCKED), "by the member's name")
        UI.setSearch("沒有這個")
        eq(#UI.state.items, 0, "nothing")
        eq(UI.pageState(), "empty"); eq(UI.statePanel.text._text, UI.EMPTY_FILTERED, "says the filters hide them")
        UI.setSearch("")
        eq(st.base, base0, "filters never read the data again")
        -- The same filters again: kept.
        local built, hits = st.built, st.hits
        UI.applyFilters()
        eq(st.built, built, "not filtered again"); eq(st.hits, hits + 1, "kept")
        UI.setKind("need")
        eq(st.built, built + 1, "a new filter: filtered once")
        -- New data: read once, filtered again.
        UI.refresh()
        eq(st.base, base0 + 1, "new data read")
        eq(st.built, built + 2, "and filtered")
    end))

    test("GF-009-16 D: the list scrolls with its bar; row tooltips use Widgets.rowTip; no OnUpdate or ticker", done(function()
        local ns = custodian()
        for i = 2, 16 do G.bags[i] = { 9400 + i, 1 } end -- 16 kinds in my custody
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01); wow.advance(5)
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.refresh()
        ok(#UI.state.items > UI.ROWS, "more rows than fit: " .. #UI.state.items)
        ok(UI.listBar and UI.listBar:IsShown(), "the scroll bar")
        local n = 0
        for _, r in pairs(UI.rows()) do n = n + 1 end
        eq(n, UI.ROWS, "only the visible rows have frames")
        UI.scroll(-3)
        eq(UI.state.offset, 3, "the wheel moves the list")
        eq(UI.listBar.offset or UI.state.offset, 3, "the bar follows")
        local calls = 0
        local orig = ns.Widgets.rowTip
        ns.Widgets.rowTip = function(o) calls = calls + 1; return orig(o) end
        local r = UI.rows()[1]
        r._scripts.OnEnter(r)
        ns.Widgets.rowTip = orig
        eq(calls, 1, "Widgets.rowTip")
        local src = io.open(ADDON_DIR .. "/SupplyUI.lua"):read("*a")
        local _, k = src:gsub("OnUpdate", "")
        eq(k, 0, "SupplyUI: no OnUpdate")
        ok(not src:find("NewTicker", 1, true), "no ticker")
    end))
end
