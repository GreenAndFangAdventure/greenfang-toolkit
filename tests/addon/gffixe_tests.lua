-- GF-FIX-E: fixes from the 0.16.6 review (GF-REVIEW-01, batch E): prices
-- cap, delivery by mail, pasted web orders, order data, guild notes. Each
-- test name carries the review item. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local A, B = "0000-0000000A", "0000-0000000B"
    local RECIPE, ITEM, SKILL = 2660, 2862, 164

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Prices.resetSession(); ns.Delivery.resetSession()
        return ns
    end
    local function peer(ns, ledger, a, g, v, t)
        t = t or ns.Share.serverNow()
        return ledger:offer(a, g, t, ns.Share.hash(v), v)
    end
    local function groupOf(ns, rk, day, b) return ns.Prices.rkCode(rk) .. ":" .. ns.Share.b36(day) .. ":" .. b end
    local function share(ns, from, to, m)
        local items = {}
        for id = from, to do items[id] = { m = m or 50, q = 1 } end
        return ns.Prices.encodeShare("測試伺服器", "horde", items)
    end
    local function countDecodes(P, fn)
        local n, real = 0, P.decodeShare
        P.decodeShare = function(...) n = n + 1; return real(...) end
        local okRun, err = pcall(fn)
        P.decodeShare = real
        if not okRun then error(err, 2) end
        return n
    end

    ---------------------------------------------------------------------------
    -- Prices (H-6, M-19, M-20, M-21)
    ---------------------------------------------------------------------------

    test("GF-FIX-E H-6 cap at 8,000: one read per record, one ledger change, no full decode; refused until changed", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 8000 do P.record(rk, id, 10, 1, today) end
        local now = ns.Share.serverNow()
        for r = 1, 7 do
            for b = 0, 32 do
                local first = 100000 * r + b * 250
                eq(peer(ns, P.ledger, "trep00" .. r, groupOf(ns, rk, today, ns.Share.b36(b)), share(ns, first + 1, first + 250),
                    now - r * 40 - b), "new", "record stored")
            end
        end
        local v0 = P.ledger.version
        local dropped
        local t0 = os.clock()
        local decodes = countDecodes(P, function() dropped = P.enforceCap(rk) end)
        local ms = (os.clock() - t0) * 1000
        eq(dropped, 231, "every shared record dropped (own prices fill the 8,000)")
        eq(decodes, 0, "no full decode")
        eq(P.capReads, 231, "each record read once")
        eq(P.ledger.version - v0, 1, "one ledger change")
        eq(P.ledger:count(), 0, "records gone")
        eq(P.itemCount(rk), 8000, "within 8,000")
        io.write(string.format("     PERF GF-FIX-E: enforceCap at 8,000 own items, 231 records: %.0f ms, %d decodes, %d version step(s)\n",
            ms, decodes, P.ledger.version - v0))
        -- The same record again (another member still has it): refused, not stored and dropped again.
        local g = groupOf(ns, rk, today, "0")
        eq(peer(ns, P.ledger, "trep001", g, share(ns, 100001, 100250), now - 40), "invalid", "same record refused")
        -- A newer record of that author and group (other prices): taken at once.
        eq(peer(ns, P.ledger, "trep001", g, share(ns, 100001, 100250, 60), now), "new", "a changed record is taken")
    end)

    test("GF-FIX-E H-6 cap: oldest first, only as many as needed; a record of own items frees nothing", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 7900 do P.record(rk, id, 10, 1, today) end
        local now = ns.Share.serverNow()
        local g0, g1, g2 = groupOf(ns, rk, today, "0"), groupOf(ns, rk, today, "1"), groupOf(ns, rk, today, "2")
        peer(ns, P.ledger, "trep001", g0, share(ns, 1, 100), now - 300)          -- oldest: own items only
        peer(ns, P.ledger, "trep001", g1, share(ns, 20001, 20100), now - 200)    -- 100 new items
        peer(ns, P.ledger, "trep002", g2, share(ns, 30001, 30100), now - 100)    -- 100 new items
        eq(P.itemCount(rk), 8100, "over by 100")
        eq(P.enforceCap(rk), 2, "the two oldest")
        eq(P.ledger:get("trep001", g0), nil, "oldest dropped"); eq(P.ledger:get("trep001", g1), nil, "next dropped")
        ok(P.ledger:get("trep002", g2) ~= nil, "newest kept")
        eq(P.itemCount(rk), 8000, "exactly 8,000")
        eq(P.enforceCap(rk), 0, "fits now: nothing more")
    end)

    test("GF-FIX-E M-19 enforceCapAll: prefix only, no full decode; nothing again while the ledger is unchanged", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        local now = ns.Share.serverNow()
        for b = 0, 9 do peer(ns, P.ledger, "trep001", groupOf(ns, rk, today, ns.Share.b36(b)), share(ns, b * 100 + 1, b * 100 + 100), now) end
        local n
        eq(countDecodes(P, function() n = P.enforceCapAll() end), 0, "no decodeShare")
        eq(n, 1, "one realm + type checked")
        eq(P.enforceCapAll(), 0, "unchanged: nothing done")
        peer(ns, P.ledger, "trep002", groupOf(ns, rk, today, "a"), share(ns, 5001, 5010), now)
        eq(P.enforceCapAll(), 1, "changed: checked again at once")
    end)

    test("GF-FIX-E M-20 full table: candidates built once, oldest go first, open-order items stay", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 8000 do P.record(rk, id, 10, 1, today - 20 + (id % 10)) end
        local keep = { [10] = true, [20] = true } -- day today-20, the oldest
        P.evictBuilds = 0
        for id = 10001, 10500 do ok(P.record(rk, id, 10, 1, today, nil, keep), "stored " .. id) end
        eq(P.evictBuilds, 1, "one candidate list for 500 new items")
        ok(P.items(rk)[10] and P.items(rk)[20], "open-order items kept")
        eq(P.items(rk)[30], nil, "an oldest-day item went")
        ok(P.items(rk)[21], "a newer-day item stayed")
        local n = 0
        for _ in pairs(P.items(rk)) do n = n + 1 end
        eq(n, 8000, "still 8,000")
    end)

    test("GF-FIX-E M-20 scan commit: new items fit into the free places; never push out each other", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 7990 do P.record(rk, id, 10, 1, today) end            -- today: not evictable
        for id = 7991, 8000 do P.record(rk, id, 10, 1, today - 5) end      -- 10 older items
        local agg = { [5] = { m = 9, q = 1 } }                             -- known: always updated
        for id = 20001, 20050 do agg[id] = { m = 20, q = id - 20000 } end  -- 50 new items
        agg[30001] = { m = 20, q = 1 }
        local ids, left = P.fitScan(rk, agg, { [30001] = true })
        eq(#ids, 1 + 10, "known + the 10 places of older items")
        eq(left, 41, "41 left out")
        local set = {}
        for _, id in ipairs(ids) do set[id] = true end
        ok(set[5], "known item updated"); ok(set[30001], "an open order's item first")
        ok(set[20050] and set[20042] and not set[20041], "then the most offered")
        for _, id in ipairs(ids) do P.record(rk, id, agg[id].m, agg[id].q, today, nil, {}) end
        for _, id in ipairs(ids) do ok(P.items(rk)[id], "kept " .. id) end
    end)

    test("GF-FIX-E M-21 record limit: never our own records; the pushed-out record is refused until it changes", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        local now = ns.Share.serverNow()
        local max = P.ledger.cfg.maxRecords
        P.ledger.cfg.maxRecords = 3
        local mine = P.token()
        peer(ns, P.ledger, mine, groupOf(ns, rk, today, "0"), share(ns, 1, 5), now - 500)
        peer(ns, P.ledger, "trep001", groupOf(ns, rk, today, "1"), share(ns, 11, 15), now - 400)
        peer(ns, P.ledger, "trep002", groupOf(ns, rk, today, "2"), share(ns, 21, 25), now - 300)
        eq(peer(ns, P.ledger, "trep003", groupOf(ns, rk, today, "3"), share(ns, 31, 35), now - 200), "new", "fourth stored")
        ok(P.ledger:get(mine, groupOf(ns, rk, today, "0")) ~= nil, "own record kept")
        eq(P.ledger:get("trep001", groupOf(ns, rk, today, "1")), nil, "oldest other record pushed out")
        eq(peer(ns, P.ledger, "trep001", groupOf(ns, rk, today, "1"), share(ns, 11, 15), now - 400), "invalid", "refused")
        P.ledger.cfg.maxRecords = max
    end)

    ---------------------------------------------------------------------------
    -- Delivery by mail (M-22, M-23)
    ---------------------------------------------------------------------------

    local function mailClient(withCount)
        local st = { inbox = {}, bags = {}, itemReads = 0 }
        hooksecurefunc = function(name, fn)
            local orig = _G[name]
            _G[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
        end
        SendMail = function() end
        GetSendMailItem = function() end
        GetInboxNumItems = function() return #st.inbox end
        GetInboxHeaderInfo = function(i)
            local m = st.inbox[i]
            if not m then return end
            local has = true
            if withCount then has = #m.items > 0 and #m.items or nil end
            return nil, nil, m.sender, "s", 0, m.cod or 0, 30, has, false, m.returned or false
        end
        GetInboxItem = function(i, j)
            st.itemReads = st.itemReads + 1
            local m = st.inbox[i]; local a = m and m.items[j]
            if a then return "x", a.id, 1, a.n end
        end
        TakeInboxItem = function() end
        AutoLootMailItem = function() end
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        st.restore = function()
            hooksecurefunc, SendMail, GetSendMailItem, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil, nil, nil
            TakeInboxItem, AutoLootMailItem, C_Item, GetInboxNumItems = nil, nil, nil, nil
        end
        return st
    end
    local function acceptedOrder(ns, qty)
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = qty or 2, crafter = B })
        peer(ns, ns.Orders.ledger, B, "J", ns.Orders.encodeList({ { id = id, cu = A, st = "a",
            ac = ns.Share.serverNow(), sa = ns.Share.serverNow() } }))
        return id
    end

    test("GF-FIX-E M-22 MAIL_INBOX_UPDATE: no open order = no mail read; header without items = no slot read", function()
        local st = mailClient(true)
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        for i = 1, 20 do st.inbox[i] = { sender = "測試丁", items = {} } end
        st.inbox[21] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        eq(ns.Delivery.inboxReads, 0, "no open order: nothing read")
        eq(st.itemReads, 0, "no attachment read")
        acceptedOrder(ns, 3)
        wow.fire("MAIL_INBOX_UPDATE")
        eq(ns.Delivery.inboxReads, 21, "open order: every header read")
        eq(st.itemReads, ns.Delivery.RECEIVE_SLOTS, "slots read only for the mail with items")
        st.restore()
    end)

    test("GF-FIX-E M-22 a take with no open order still reads the mail live (可用 evidence kept)", function()
        local st = mailClient(true)
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        eq(TakeInboxItem(1, 1), nil, "hooked call")
        st.bags[ITEM] = 1
        wow.advance(4)
        eq(ns.Delivery.status("mailTake"), "ok", "the take was judged")
        st.restore()
    end)

    test("GF-FIX-E M-23 two mails taken from slot 1 within one second both count; a repeated hook counts once", function()
        local st = mailClient(false)
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        local id = acceptedOrder(ns, 3)
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        st.inbox[2] = { sender = "測試乙", items = { { id = ITEM, n = 2 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        eq(ns.Delivery.onTake(1, 1), "waiting", "first mail")
        eq(ns.Delivery.onTake(1, 1), "duplicate", "the same take reported again")
        -- The first mail is gone; the second moves into slot 1 (same second).
        table.remove(st.inbox, 1)
        eq(ns.Delivery.onTake(1, 1), "waiting", "next mail, other items: not a repeat")
        -- Same sender and items again, after the inbox changed: not a repeat either.
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 2 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        eq(ns.Delivery.onTake(1, 1), "waiting", "after MAIL_INBOX_UPDATE: counted")
        st.restore()
        ok(id, "order")
    end)

    test("GF-FIX-E M-23 both mails reach the order (3 of 3 by mail closes it)", function()
        local st = mailClient(false)
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        local id = acceptedOrder(ns, 3)
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        st.inbox[2] = { sender = "測試乙", items = { { id = ITEM, n = 2 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        TakeInboxItem(1, 1)
        table.remove(st.inbox, 1)
        TakeInboxItem(1, 1)
        st.bags[ITEM] = 3
        wow.advance(4)
        local v = ns.Orders.get(id)
        eq(v.progress, 3, "both mails counted"); eq(v.state, "deal", "成交 by mail")
        st.restore()
    end)

    ---------------------------------------------------------------------------
    -- Web orders (M-24, L-27)
    ---------------------------------------------------------------------------

    local REALM, GUILD = "測試伺服器", "綠皮與獠牙冒險事務所"
    local function build(ns, customers)
        local W = ns.WebOrders
        local now = ns.Share.serverNow()
        local n = 0
        for _, c in ipairs(customers) do n = n + #c.orders end
        local parts = { string.format("H;realm=%s;guild=%s;at=%d;n=%d", W.pctEncode(REALM), W.pctEncode(GUILD), now, n) }
        for _, c in ipairs(customers) do
            parts[#parts + 1] = string.format("C;cu=%s;t=%d", c.cu, now - 50)
            for _, o in ipairs(c.orders) do parts[#parts + 1] = "O;" .. o end
        end
        local rest = table.concat(parts, "~")
        return "GFIN1~" .. W.sum(rest) .. "~c2lnbmF0dXJl~" .. rest
    end
    local function order(ns, id, mats)
        local now = ns.Share.serverNow()
        return string.format("cf=*;cr=%d;fe=500;id=%s;it=2862;m=%s;q=5;rc=2660;sa=%d;sk=164;st=open", now - 100, id,
            mats or "2835*5", now - 100)
    end

    test("GF-FIX-E M-24 a pasted code brings in my own orders only; the Inbox is not limited", function()
        local ns = login()
        local s = build(ns, { { cu = "Player-" .. A, orders = { order(ns, "w1") } },
            { cu = "Player-" .. B, orders = { order(ns, "w2"), order(ns, "w3") } } })
        local r = ns.WebOrders.import(s, "paste")
        eq(r.code, "ok", "parsed"); eq(r.imported, 1, "mine imported")
        eq(r.skipped["not-self"], 2, "another customer's orders skipped")
        eq(ns.Orders.ledger:get(B, "M"), nil, "no M record in B's name")
        ok(ns.Orders.get("w1") ~= nil and ns.Orders.get("w2") == nil, "only mine")
        ok(ns.WebOrders.diagText():find("not-self 2", 1, true), "diagnostics say why")
        r = ns.WebOrders.import(s, "inbox")
        eq(r.imported, 2, "the Inbox brings B's orders")
        ok(ns.Orders.get("w2") ~= nil, "B's order from the Inbox")
    end)

    test("GF-FIX-E L-27 the same material twice skips that order as bad-field", function()
        local ns = login()
        local s = build(ns, { { cu = "Player-" .. A, orders = { order(ns, "w1", "2835*5+2835*3"), order(ns, "w2") } } })
        local r = ns.WebOrders.parse(s, ns.WebOrders.context())
        eq(r.code, "ok", "parsed"); eq(r.total, 1, "one order kept")
        eq(r.skipped["bad-field"], 1, "the broken one skipped")
    end)

    ---------------------------------------------------------------------------
    -- Order data (L-25)
    ---------------------------------------------------------------------------

    test("GF-FIX-E L-25 customer actions report a list that did not fit; reagents may be asked again after 5 minutes", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 2, crafter = B })
        ok(id, "placed")
        local max = O.MAX_VALUE
        O.MAX_VALUE = 10
        local okSave, why = O.customer(id, "got", 1)
        O.MAX_VALUE = max
        eq(okSave, false, "not saved"); eq(why, "full", "full")
        eq(O.get(id).received or 0, 0, "page and record agree: nothing received")
        wow.state.sent = {}
        ok(O.askReagents(9001) ~= false, "asked")
        eq(O.askReagents(9001), false, "not twice at once")
        wow.advance(O.ASK_AGAIN + 1)
        ok(O.askReagents(9001) ~= false, "asked again after 5 minutes")
    end)

    ---------------------------------------------------------------------------
    -- Guild notes (M-26)
    ---------------------------------------------------------------------------

    local ALL = { invite = true, promote = true, demote = true, remove = true, publicNote = true, officerNote = true,
        viewOfficer = true, motd = true, info = true }
    local C = "測試丙-測試伺服器"
    local function memberOf(ns, name)
        for _, row in ipairs(ns.UI.rows()) do if row:IsShown() and row.memberName == name then return row.member end end
    end
    local function press(ns, name, key)
        for _, it in ipairs(ns.UI.memberMenuItems(memberOf(ns, name))) do
            if it.key == key then it.fn(); return true end
        end
    end
    local function indexOf(name)
        for i, m in ipairs(wow.state.roster) do if m.name == name then return i end end
    end

    test("GF-FIX-E M-26 notes: the roster moved before saving -> written at the member's new index", function()
        wow.reset({ guildPerms = ALL, myRankIndex = 1 })
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        local before = indexOf(C)
        ok(press(ns, C, "publicNote"), "menu")
        -- Someone above leaves while the box is open: everybody moves up one.
        local gone = table.remove(wow.state.roster, 1)
        ok(gone and gone.name ~= C, "another member left")
        wow.state.guildCalls = {}
        wow.acceptPopup("新的公會註記")
        eq(table.concat(wow.state.guildCalls, ","), "publicNote:" .. (before - 1) .. ":新的公會註記", "the new index")
        eq(wow.state.roster[before - 1].name, C, "on the right member")
        -- Officer note the same way.
        ok(press(ns, C, "officerNote"), "menu")
        table.insert(wow.state.roster, 1, gone)
        wow.state.guildCalls = {}
        wow.acceptPopup("新的幹部註記")
        eq(table.concat(wow.state.guildCalls, ","), "officerNote:" .. before .. ":新的幹部註記", "back at the old index")
    end)

    test("GF-FIX-E M-26 notes: the member left before saving -> nothing written, a message", function()
        wow.reset({ guildPerms = ALL, myRankIndex = 1 })
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        ok(press(ns, C, "officerNote"), "menu")
        table.remove(wow.state.roster, indexOf(C))
        wow.state.guildCalls = {}
        wow.clearPrinted()
        wow.acceptPopup("新的幹部註記")
        eq(#wow.state.guildCalls, 0, "nothing written")
        local said = false
        for _, line in ipairs(wow.printed()) do if line:find("沒有寫入", 1, true) then said = true end end
        ok(said, "told why")
        -- The officer note never reaches SavedVariables.
        local found = false
        local function scan(t, depth)
            if depth > 12 or type(t) ~= "table" then return end
            for _, v in pairs(t) do
                if v == "新的幹部註記" then found = true elseif type(v) == "table" then scan(v, depth + 1) end
            end
        end
        scan(GreenFangToolkitDB, 0)
        ok(not found, "not saved")
    end)
end
