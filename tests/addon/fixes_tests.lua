-- GF-006-B2: one reproducing test per fix from the 0.11.0 review
-- (side-session-notes review-0.11.0.md) and contract v1.4a. Each test name
-- carries the review item. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local NAME = { [B] = "測試乙-測試伺服器", [C] = "測試丙-測試伺服器" }
    local DAY = 86400
    local RECIPE, ITEM, SKILL, ORE = 2660, 2862, 164, 2770

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
    local function w(id, extra)
        local e = { id = id, src = "g", ver = 1, cr = 1763000000, rc = RECIPE, it = ITEM, sk = SKILL, q = 2, cf = "*",
            fe = 0, st = "o", sa = 1763000000 }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local function sentOf(prefix)
        local n = 0
        for _, m in ipairs(wow.state.sent) do if m.prefix == prefix then n = n + 1 end end
        return n
    end

    ---------------------------------------------------------------------------
    -- Top 10
    ---------------------------------------------------------------------------

    test("GF-006-B2 review 1-1: a long record sent at the real rate (0.5/s) still arrives", function()
        local ns = login()
        local list = {}
        for i = 1, 100 do list[i] = w("gbbb.x" .. i, { cf = C, sk = 100 + i }) end
        local v = ns.Orders.encodeList(list)
        ok(#v > 9000, "about 9 KB: " .. #v)
        peer(ns, ns.Orders.ledger, B, "W", v)
        wow.state.sent = {}
        ns.Orders.ledger.lastHeard[ns.keyName(NAME[C])] = ns.now() + 1000 -- C just asked
        ns.Orders.ledger:sendRecord(B, "W", NAME[C])
        local parts = {}
        for _ = 1, 400 do
            wow.advance(1)
            if #wow.state.sent > #parts then
                for i = #parts + 1, #wow.state.sent do parts[i] = wow.state.sent[i] end
            end
            if #parts > 0 and #ns.Orders.ledger.queue == 0 then break end
        end
        local data = {}
        for _, m in ipairs(parts) do
            if m.prefix == "GFTKO" and (m.msg:find("L1~B~", 1, true) == 1 or m.msg:find("L1~D~", 1, true) == 1) then data[#data + 1] = m.msg end
        end
        parts = data
        ok(#parts > 40, "many parts: " .. #parts)
        -- Deliver them to a fresh client 2 seconds apart (slower than the 60 s the old timeout allowed).
        ns = login()
        local last
        for _, m in ipairs(parts) do
            last = ns.Orders.ledger:onMessage("GFTKO", m, "WHISPER", NAME[C])
            wow.advance(2)
        end
        eq(last, "new", "completed")
        eq(#ns.Orders.listOf(B, "W"), 100, "all 100 orders")
    end)

    test("GF-006-B2 review 1-2: a full W never reports success without storing; closed rows make room", function()
        local ns = login()
        local O = ns.Orders
        local okAll = true
        for i = 1, 140 do
            local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, mats = { [ORE] = 9999 } })
            if not id or not O.get(id) then okAll = false; break end
            O.customer(id, "cancel")
        end
        ok(okAll, "every place returned an id only when it was stored")
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        ok(id and O.get(id), "still room: the oldest closed rows were moved to history")
        ok(#O.local_().history["Player-0000-0000000A"] > 0, "moved to history")
        -- All open and too big: an honest failure.
        ns = login()
        O = ns.Orders
        local big = {}
        for i = 1, 30 do big[i] = { recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, mats = {} } end
        for i = 1, 30 do for k = 1, 40 do big[i].mats[1000000 + i * 100 + k] = 9999 end end
        local failed
        for i = 1, 30 do
            local r, why = O.place(big[i])
            if not r then failed = why; break end
            ok(O.get(r), "stored when it says so")
        end
        eq(failed, "full", "reports full")
    end)

    test("GF-006-B2 review 1-3: whispers to someone who left: the system line is hidden and the queue dropped", function()
        local ns = login()
        local L = ns.Prices.ledger
        L.lastHeard[ns.keyName(NAME[B])] = ns.now()
        for i = 1, 5 do L:enqueue(L:msg("V", "tab0001", "g" .. i, "1", "h", "x"), NAME[B]) end
        wow.advance(1)
        ok(sentOf("GFTKP") >= 1, "one went out")
        local hidden = wow.systemMessage(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, "測試乙"))
        ok(hidden, "'No player named ...' hidden")
        eq(L:queued(), 0, "the rest dropped")
    end)

    test("GF-006-B2 review 1-4: SendAddonMessage returning false (throttled) keeps the message", function()
        local ns = login()
        local L = ns.Orders.ledger
        local real = C_ChatInfo.SendAddonMessage
        local calls = 0
        C_ChatInfo.SendAddonMessage = function(...)
            calls = calls + 1
            if calls == 1 then return false end
            return real(...)
        end
        wow.state.sent = {}
        L:enqueue(L:msg("Q", "q", "0", "0", "b"), nil, true)
        wow.advance(10)
        eq(sentOf("GFTKO"), 1, "sent after the throttle"); eq(L.stats.throttled, 1, "counted as throttled")
        C_ChatInfo.SendAddonMessage = real
    end)

    test("GF-006-B2 review 1-5: login folding and publishing run in steps, not in one frame", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for r = 1, 4 do
            for b = 0, 7 do
                local items = {}
                for id = b * 250 + 1, b * 250 + 250 do items[id] = { m = 100 + id % 7, q = 1 } end
                eq(peer(ns, P.ledger, "trep00" .. r, P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":" .. b,
                    P.encodeShare("測試伺服器", "horde", items)), "new", "stored")
            end
        end
        wow.state.now = wow.state.now + 3 * DAY
        P.login()
        ok(P.ledger:count() > 0, "not all folded inside the call")
        wow.advance(30)
        eq(P.ledger:count(), 0, "folded over later frames")
        ok(P.items(rk)[5], "day value stored")
        -- Publishing 8,000 items is also spread out.
        for id = 1, 8000 do P.record(rk, id, 10, 1, P.today()) end
        P.publish(rk)
        eq(P.ledger:count(), 0, "publish has not run inside the call")
        wow.advance(30)
        ok(P.ledger:count() > 0, "published later")
    end)

    test("GF-006-B2 review 1-6: shared prices count toward the 8,000 items; records capped", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 2000 do P.record(rk, id, 10, 1, today) end
        for r = 1, 2 do
            for b = 0, 23 do
                local items = {}
                for id = 1, 250 do items[10000 * r + b * 250 + id] = { m = 50, q = 1 } end
                peer(ns, P.ledger, "trep00" .. r, P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":" .. b,
                    P.encodeShare("測試伺服器", "horde", items))
            end
        end
        P.enforceCap(rk)
        wow.advance(10)
        local n = P.itemCount(rk)
        ok(n <= 8000, "own + shared within 8,000: " .. n)
        ok(P.ledger.cfg.maxRecords <= 700, "records capped: " .. P.ledger.cfg.maxRecords)
        eq(P.items(rk)[1] ~= nil, true, "own prices kept first")
    end)

    test("GF-006-B2 review 1-7: seen keys and unsure marks of gone orders are cleaned", function()
        local ns = login()
        local o = ns.Orders.local_()
        o.seen["gone.1|new"] = true
        o.seen["gone.2|stale|3"] = true
        o.unsure["gone.3"] = ns.now() - 3600
        ns.Orders.maintain()
        eq(next(o.seen), nil, "seen cleaned"); eq(next(o.unsure), nil, "unsure cleaned")
    end)

    test("GF-006-B2 review 3-1 (#7) / v1.4a: the locked crafter drops -> back to 等接單, no hand-over", function()
        local ns = login()
        local O = ns.Orders
        local jobs = { [C] = { id = "g1", st = "b", ac = 1763000200, sa = 1763000400 },
            [B] = { id = "g1", st = "a", ac = 1763000100, sa = 1763000100 } }
        local v = O.view(w("g1", { lk = C, lt = 1763000300 }), jobs, A)
        eq(v.state, "waiting", "waiting again"); eq(v.crafter, nil, "nobody")
        -- Someone accepting after the drop can take it.
        jobs[D] = { id = "g1", st = "a", ac = 1763000500, sa = 1763000500 }
        eq(O.view(w("g1", { lk = C, lt = 1763000300 }), jobs, A).crafter, D, "a new accept after the drop")
    end)

    test("GF-006-B2 review 2-2 (#8): trade completes without (1,1) and with the message in arg1; diag 未確認 until seen", function()
        local ns = login()
        local st = { mine = {}, theirs = {}, bags = {} }
        local oldName = UnitName
        UnitName = function(u) if u == "NPC" then return "測試乙" end return oldName(u) end
        GetTradePlayerItemLink = function(i) local s = st.mine[i]; return s and ("item:" .. s.id) end
        GetTradePlayerItemInfo = function(i) local s = st.mine[i]; if s then return "x", 1, s.n end end
        GetTradeTargetItemLink = function(i) local s = st.theirs[i]; return s and ("item:" .. s.id) end
        GetTradeTargetItemInfo = function(i) local s = st.theirs[i]; if s then return "x", 1, s.n end end
        ERR_TRADE_COMPLETE = "交易完成。"
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        ok(ns.Diag.ordersText():find("交易判斷 未確認", 1, true), "未確認 before any trade")
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = B })
        local J = ns.Orders.encodeList({ { id = id, cu = A, st = "a", ac = ns.Share.serverNow(), sa = ns.Share.serverNow() } })
        peer(ns, ns.Orders.ledger, B, "J", J)
        wow.fire("TRADE_SHOW")
        st.theirs = { { id = ITEM, n = 1 } }
        wow.fire("TRADE_TARGET_ITEM_CHANGED", 1)
        wow.fire("TRADE_ACCEPT_UPDATE", 1, 0) -- only one side; no (1,1) before completion
        st.bags[ITEM] = 1
        wow.fire("UI_INFO_MESSAGE", ERR_TRADE_COMPLETE) -- message in the first argument
        wow.fire("TRADE_CLOSED")
        wow.advance(4)
        eq(ns.Orders.get(id).state, "deal", "auto deal")
        ok(ns.Diag.ordersText():find("交易判斷 可用", 1, true), "可用 once seen")
        UnitName = oldName
        GetTradePlayerItemLink, GetTradePlayerItemInfo, GetTradeTargetItemLink, GetTradeTargetItemInfo = nil, nil, nil, nil
        ERR_TRADE_COMPLETE, C_Item = nil, nil
    end)

    test("GF-006-B2 review 3-2 (#9) / v1.4a: every crafter's j is uploaded with statusAt; returnedAt in w", function()
        local ns = login()
        local O = ns.Orders
        local t = ns.Share.serverNow()
        peer(ns, O.ledger, B, "W", O.encodeList({ w("gbbb.1", { cr = t - 100 }) }))
        O.press(O.get("gbbb.1"), "accept")
        local j = O.craftingFor(A).orders["gbbb.1"].j
        ok(type(j.statusAt) == "number", "statusAt")
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        O.customer(id, "return")
        ok(type(O.craftingFor(A).orders[id].w.returnedAt) == "number", "returnedAt")
    end)

    test("GF-006-B2 review 5-1 (#10): quote is not written when it cannot be computed", function()
        local ns = login()
        local U = ns.OrdersUI
        local d = U.newDraft({ recipe = 99999, skill = SKILL, crafters = {} })
        local id = U.submit(d)
        eq(ns.Orders.get(id).quote, nil, "no reagent list: no quote")
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 1 } } })
        d = U.newDraft({ recipe = RECIPE, skill = SKILL, crafters = {} })
        id = U.submit(d)
        eq(ns.Orders.get(id).quote, nil, "a missing price: no quote")
        local up = ns.Orders.craftingFor(A).orders[id].w
        eq(up.quote, nil, "not uploaded")
    end)

    ---------------------------------------------------------------------------
    -- Other errors and misjudgements
    ---------------------------------------------------------------------------

    test("GF-006-B2 review 2-4: two mails taken within 3 s are both counted", function()
        local st = { inbox = {}, bags = {} }
        hooksecurefunc = function(name, fn) local o = _G[name]; _G[name] = function(...) o(...); fn(...) end end
        SendMail, GetSendMailItem = function() end, function() end
        GetInboxHeaderInfo = function(i) local m = st.inbox[i]; if m then return nil, nil, m.sender, "s", 0, 0, 30, true, false, false end end
        GetInboxItem = function(i, j) local m = st.inbox[i]; local a = m and m.items[j]; if a then return "x", a.id, 1, a.n end end
        TakeInboxItem, AutoLootMailItem = function() end, function() end
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 3, crafter = B })
        peer(ns, ns.Orders.ledger, B, "J", ns.Orders.encodeList({ { id = id, cu = A, st = "a", ac = 1, sa = 1 } }))
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        st.inbox[2] = { sender = "測試乙", items = { { id = ITEM, n = 2 } } }
        TakeInboxItem(1, 1); st.bags[ITEM] = 1
        wow.advance(1)
        TakeInboxItem(2, 1); st.bags[ITEM] = 3
        wow.advance(5)
        eq(ns.Orders.get(id).state, "deal", "both mails counted (1 + 2)")
        hooksecurefunc, SendMail, GetSendMailItem, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil, nil, nil
        TakeInboxItem, AutoLootMailItem, C_Item = nil, nil, nil
    end)

    test("GF-006-B2 review 2-5: attachments cleared after the call: the inbox cache is used", function()
        local st = { inbox = {}, bags = {} }
        hooksecurefunc = function(name, fn) local o = _G[name]; _G[name] = function(...) o(...); fn(...) end end
        SendMail, GetSendMailItem = function() end, function() end
        GetInboxHeaderInfo = function(i) local m = st.inbox[i]; if m then return nil, nil, m.sender, "s", 0, 0, 30, true, false, false end end
        GetInboxItem = function(i, j) local m = st.inbox[i]; local a = m and m.items[j]; if a then return "x", a.id, 1, a.n end end
        TakeInboxItem = function(i) st.inbox[i] = nil end -- the client clears it at once
        AutoLootMailItem = function() end
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = B })
        peer(ns, ns.Orders.ledger, B, "J", ns.Orders.encodeList({ { id = id, cu = A, st = "a", ac = 1, sa = 1 } }))
        st.inbox[1] = { sender = "測試乙", items = { { id = ITEM, n = 1 } } }
        wow.fire("MAIL_INBOX_UPDATE")
        TakeInboxItem(1, 1); st.bags[ITEM] = 1
        wow.advance(5)
        eq(ns.Orders.get(id).state, "deal", "judged from the cache")
        hooksecurefunc, SendMail, GetSendMailItem, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil, nil, nil
        TakeInboxItem, AutoLootMailItem, C_Item = nil, nil, nil
    end)

    test("GF-006-B2 review 3-3: an older copy of my own W from another computer is merged, not lost", function()
        local ns = login()
        local O = ns.Orders
        local mine = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        local t = O.ledger:get(A, "W").t
        local other = O.encodeList({ w("gzzz.1", { cr = t - 50, sa = t - 50 }) })
        local r = peer(ns, O.ledger, A, "W", other, t - 10)
        eq(r, "older", "older by time")
        wow.advance(3)
        ok(O.get(mine), "mine kept"); ok(O.get("gzzz.1"), "the other computer's order merged in")
    end)

    test("GF-006-B2 review 3-4: nothing changes the crafter's half after the order closed", function()
        local ns = login()
        local O = ns.Orders
        peer(ns, O.ledger, B, "W", O.encodeList({ w("gbbb.1", { cf = A, st = "d", sa = 1763000500 }) }))
        local v = O.get("gbbb.1")
        eq(v.state, "deal", "closed")
        local okR, why = O.crafter(v, "release")
        ok(not okR and why == "closed", "refused: " .. tostring(why))
    end)

    test("GF-006-B2 review 5-2: the fee popup left empty saves 'not filled in', 0 saves free", function()
        local ns = login()
        local U = ns.OrdersUI
        local f = U.editFee({ skill = SKILL })
        f.boxes[1]:SetText(""); f.boxes[2]:SetText(""); f.boxes[3]:SetText("")
        U.saveFee(f.boxes.get())
        eq(ns.Orders.feeFor("Player-" .. A, SKILL), nil, "empty = not filled in")
        f = U.editFee({ skill = SKILL })
        f.boxes[3]:SetText("0")
        U.saveFee(f.boxes.get())
        eq(ns.Orders.feeFor("Player-" .. A, SKILL), 0, "0 = free")
    end)

    test("GF-006-B2 review 5-3: the row shows the fee the customer wrote, not the quote", function()
        local ns = login()
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, fee = 0, feeQuoted = 500 })
        ns.Framework.open("orders")
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do
            if r.view and r.view.id == id then
                ok(not r.fee:GetText():find("5", 1, true), "not the 500 quote: " .. r.fee:GetText())
            end
        end
    end)

    test("GF-006-B2 review 5-4: a crafter's job without a known order is not uploaded", function()
        local ns = login()
        local O = ns.Orders
        O.ledger:put("J", O.encodeList({ { id = "gold.1", cu = B, st = "a", ac = 1, sa = 1 } }))
        local c = O.craftingFor(A)
        ok(not (c and c.orders and c.orders["gold.1"]), "orphan job skipped")
    end)

    test("GF-006-B2 review 7-4: an interrupted trade reminds the crafter too", function()
        local ns = login()
        local O = ns.Orders
        peer(ns, O.ledger, B, "W", O.encodeList({ w("gbbb.1", { cf = A }) }))
        O.press(O.get("gbbb.1"), "accept")
        O.local_().unsure["gbbb.1"] = ns.now()
        local att = O.attention(O.get("gbbb.1"), A, "Player-" .. A, ns.Share.serverNow())
        ok(att and att.decide and att.code == "unsure", "crafter reminded")
        O.press(O.get("gbbb.1"), "deliver")
        eq(O.local_().unsure["gbbb.1"], nil, "cleared after acting")
    end)

    test("GF-006-B2 review 7-5: a guild answer never overwrites a reagent list we already have", function()
        local ns = login()
        local P = ns.Prices
        P.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 2 } } })
        ns.Orders.ledger:onMessage("GFTKO", "L1~S~" .. ns.Share.b36(RECIPE) .. "~" .. ITEM .. ".1.9*9", "GUILD", NAME[B])
        eq(P.cachedReagents(RECIPE).list[1].id, ORE, "kept ours")
    end)

    test("GF-006-B2 review 3-5: more than 7 reporters: the same value in any order", function()
        local ns = login()
        local P = ns.Prices
        local base = { t01 = 95, t02 = 105, t03 = 90, t04 = 110, t05 = 100, t06 = 85, t07 = 115, t08 = 80, t09 = 120 }
        local first = P.dayValue(nil, base)
        for k = 1, 20 do
            local copy = {}
            local keys = {}
            for key in pairs(base) do keys[#keys + 1] = key end
            for i = #keys, 2, -1 do local j = (i * 7 + k) % i + 1; keys[i], keys[j] = keys[j], keys[i] end
            for _, key in ipairs(keys) do copy[key] = base[key] end
            eq(P.dayValue(nil, copy), first, "permutation " .. k)
        end
    end)

    test("GF-006-B2 review 1-8: records of members who left are dropped (catalogs can agree)", function()
        local ns = login()
        local O = ns.Orders
        O.ledger:offer(B, "O", ns.Share.serverNow(), ns.Share.hash("a=164"), "a=164")
        local s = O.ledger:store()
        s.rec["0000-77777777"] = { O = { t = ns.Share.serverNow(), h = ns.Share.hash("a=1"), v = "a=1" } }
        O.maintain()
        eq(O.ledger:get("0000-77777777", "O"), nil, "gone member dropped"); ok(O.ledger:get(B, "O"), "member kept")
    end)

    ---------------------------------------------------------------------------
    -- Contract v1.4a tie rules
    ---------------------------------------------------------------------------

    test("GF-006-B2 v1.4a: same accept time -> smaller GUID by bytes; same closedAt -> the customer's", function()
        local ns = login()
        local O = ns.Orders
        -- "0000-0000000a" vs "0000-0000000B": byte order puts "B" (0x42) before "a" (0x61).
        local jobs = { ["0000-0000000a"] = { id = "g1", st = "a", ac = 100 }, ["0000-0000000B"] = { id = "g1", st = "a", ac = 100 } }
        eq(O.view(w("g1"), jobs, A).crafter, "0000-0000000B", "byte order")
        ok(O.guidLess("Player-0000-0000000B", "Player-0000-0000000a"), "guidLess is byte-wise")
        local v = O.view(w("g1", { cf = B, st = "d", sa = 500 }), { [B] = { id = "g1", st = "n", sa = 500 } }, A)
        eq(v.state, "deal", "same second: the customer's close"); eq(v.closedBy, "customer", "by customer")
    end)

    test("GF-006-B2 v1.4a: 14-day close needs returnedAt not after deliveredAt", function()
        local ns = login()
        local O = ns.Orders
        local dt = 1763000000
        local job = { [B] = { id = "g1", st = "c", ac = dt - 9, dt = dt, sa = dt + 15 * DAY } }
        eq(O.view(w("g1", { rt = dt - 5 }), job, A).state, "deal", "returned before delivery: valid")
        eq(O.view(w("g1", { rt = dt + 5 }), job, A).state ~= "deal", true, "returned after delivery: not a close")
    end)

    ---------------------------------------------------------------------------
    -- Small items and test gaps
    ---------------------------------------------------------------------------

    test("GF-006-B2 review §9.6: the minimap button shows the real number", function()
        local ns = login()
        local O = ns.Orders
        peer(ns, O.ledger, B, "W", O.encodeList({ w("gbbb.1", { cf = A, cr = ns.Share.serverNow() }) }))
        ns.OrdersUI.updateBadge()
        eq(ns.Framework.minimapButton.ordersBadge:GetText(), "1", "badge 1")
        O.press(O.get("gbbb.1"), "accept")
        ns.OrdersUI.updateBadge()
        eq(ns.Framework.minimapButton.ordersBadge:GetText(), "", "badge cleared")
    end)

    test("GF-006-B2 review 7-6: 下單給 from the roster is forgotten after use; declined orders do not count as open", function()
        local ns = login()
        local U, O = ns.OrdersUI, ns.Orders
        U.pendingCrafter = B
        local items = U.recipeMenuItems({ id = RECIPE, skill = SKILL, crafters = { { guid = "Player-" .. B, name = "測試乙" } } })
        items[1].fn()
        eq(U.pendingCrafter, nil, "used once")
        U.rosterMenuItems({ guid = "Player-" .. C, name = "測試丙-測試伺服器" }, SKILL)[1].fn()
        eq(U.pendingCrafter, C, "set from the roster")
        wow.advance(130)
        eq(U.pendingCrafter, nil, "forgotten after two minutes")
        for i = 1, 30 do
            local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = B })
            peer(ns, O.ledger, B, "J", O.encodeList({ { id = id, cu = A, st = "n", sa = ns.Share.serverNow() } }),
                ns.Share.serverNow() + i)
        end
        ok(O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 }), "declined ones are not open")
    end)

    test("GF-006-B2 review 7-6: a crafter dropping my guild order reminds me once", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        local t = ns.Share.serverNow()
        peer(ns, O.ledger, B, "J", O.encodeList({ { id = id, cu = A, st = "b", ac = t - 5, sa = t } }))
        local v = O.get(id)
        eq(v.state, "waiting", "open again")
        local att = O.attention(v, A, "Player-" .. A, t)
        ok(att and att.code == "dropped" and not att.decide, "notified")
        O.markSeen()
        eq(O.attentionCount(), 0, "seen")
    end)

    test("GF-006-B2 review 7-1/7-2: lookups wait for the client; browse does not double count or run in combat", function()
        local ns = login()
        local P = ns.Prices
        local oldFaction = UnitFactionGroup
        UnitFactionGroup = function(u) if u == "npc" then return "Horde" end return oldFaction(u) end
        local results = {}
        local ready = false
        local searches = 0
        C_AuctionHouse = {
            IsThrottledMessageSystemReady = function() return ready end,
            MakeItemKey = function(id) return { itemID = id } end,
            SendSearchQuery = function() searches = searches + 1 end,
            SendBrowseQuery = function() end,
            GetBrowseResults = function() return results end,
            HasFullBrowseResults = function() return false end,
            RequestMoreBrowseResults = function() end,
        }
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        ok(id, "an order")
        P.onAuctionShow()
        wow.advance(5)
        eq(searches, 0, "client not ready: no lookups")
        ready = true
        wow.advance(5)
        ok(searches > 0, "ready: lookups")
        eq(P.startScan(), "started", "browse")
        results = { { itemKey = { itemID = 5 }, minPrice = 100, totalQuantity = 3 } }
        P.onBrowseResults()
        results = { { itemKey = { itemID = 5 }, minPrice = 100, totalQuantity = 3 }, { itemKey = { itemID = 6 }, minPrice = 7, totalQuantity = 1 } }
        P.onBrowseResults()
        eq(P.scanState().classAgg[5].q, 3, "cumulative results not double counted")
        wow.enterCombat()
        P.onBrowseResults()
        ok(P.scanState().state ~= "running", "stopped in combat")
        wow.leaveCombat()
        C_AuctionHouse = nil
        UnitFactionGroup = oldFaction
    end)
end
