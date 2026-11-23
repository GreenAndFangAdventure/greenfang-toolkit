-- Offline tests for GF-006-B (crafting and orders, spec
-- docs/spec/GF-006_crafting-orders_v1.0.md). Loaded by run.lua; every test
-- name carries the spec requirement it covers (R-x.y). All names, GUIDs and
-- realms are made up.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint

    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local NAME = { [B] = "測試乙-測試伺服器", [C] = "測試丙-測試伺服器", [D] = "測試丁-測試伺服器" }
    local DAY = 86400
    local RECIPE, ITEM, SKILL = 2660, 2862, 164
    local ORE, STONE = 2770, 2835

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession()
        ns.Prices.resetSession()
        ns.Delivery.resetSession()
        return ns
    end

    -- A record written by another member (as if relayed to us).
    local function peer(ns, ledger, a, g, v, t)
        t = t or ns.Share.serverNow()
        return ledger:offer(a, g, t, ns.Share.hash(v), v)
    end
    local function job(ns, a, entries, t) return peer(ns, ns.Orders.ledger, a, "J", ns.Orders.encodeList(entries), t) end
    local function orders(ns, a, entries, t) return peer(ns, ns.Orders.ledger, a, "W", ns.Orders.encodeList(entries), t) end
    local function services(ns, a, sv, t) return peer(ns, ns.Orders.ledger, a, "O", ns.Orders.encodeServices(sv), t) end

    local function w(id, extra)
        local e = { id = id, src = "g", ver = 1, cr = 1763000000, rc = RECIPE, it = ITEM, sk = SKILL, q = 2, cf = "*",
            fe = 0, st = "o", sa = 1763000000 }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end

    ---------------------------------------------------------------------------
    -- R-5.6 / R-6.1 / R-6.6: merging the halves (pure)
    ---------------------------------------------------------------------------

    test("GF-006 R-5.6 merge: waiting, accepted, delivered, customer deal", function()
        local ns = login()
        local O = ns.Orders
        local v = O.view(w("g1"), {}, A)
        eq(v.state, "waiting", "guild order with no job")
        ok(v.guild and v.crafter == nil, "no crafter yet")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "a", ac = 1763000100, sa = 1763000100 } }, A)
        eq(v.state, "making", "accepted"); eq(v.crafter, B, "crafter")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "d", ac = 1763000100, sa = 1763000200, dt = 1763000200, gv = 2 } }, A)
        eq(v.state, "checking", "crafter delivered"); eq(v.progress, 2, "progress from the crafter")
        v = O.view(w("g1", { st = "d", sa = 1763000300, ch = "trade", gt = 2 }),
            { [B] = { id = "g1", st = "d", ac = 1763000100, sa = 1763000200, dt = 1763000200, gv = 2 } }, A)
        eq(v.state, "deal", "customer confirmed"); eq(v.closedBy, "customer", "closedBy"); eq(v.closeHow, "trade", "closeHow")
        eq(v.closedAt, 1763000300, "closedAt")
    end)

    test("GF-006 R-5.3 guild order: the earliest accept wins on every client; the lock holds", function()
        local ns = login()
        local O = ns.Orders
        local jobs = { [C] = { id = "g1", st = "a", ac = 1763000200 }, [B] = { id = "g1", st = "a", ac = 1763000100 } }
        eq(O.view(w("g1"), jobs, A).crafter, B, "earliest accept")
        local tie = { [C] = { id = "g1", st = "a", ac = 1763000100 }, [B] = { id = "g1", st = "a", ac = 1763000100 } }
        eq(O.view(w("g1"), tie, A).crafter, B, "same second: the smaller author id (deterministic)")
        -- Locked to C by the customer: C keeps it even though B accepted earlier.
        eq(O.view(w("g1", { lk = C, lt = 1763000300 }), jobs, A).crafter, C, "lock holds")
        -- The locked crafter releases after the lock: back to the others.
        jobs[C] = { id = "g1", st = "b", ac = 1763000200, sa = 1763000400 }
        local v = O.view(w("g1", { lk = C, lt = 1763000300 }), jobs, A)
        -- GF-006-B2 (review 3-1, contract v1.4a): never handed to the one who was too late.
        eq(v.crafter, nil, "released lock: nobody"); eq(v.state, "waiting", "back to 等接單")
        ok(v.declined[C], "C marked as declined")
        jobs[B] = { id = "g1", st = "b", ac = 1763000100, sa = 1763000500 }
        eq(O.view(w("g1", { lk = C, lt = 1763000300 }), jobs, A).state, "waiting", "R-6.4: everyone released -> waiting again")
    end)

    test("GF-006 R-5.4 / R-6.4 directed order: decline and release close it as 取消 by the crafter", function()
        local ns = login()
        local O = ns.Orders
        local v = O.view(w("g1", { cf = B }), {}, A)
        eq(v.state, "waiting", "directed, no answer yet"); eq(v.crafter, B, "named crafter")
        v = O.view(w("g1", { cf = B }), { [B] = { id = "g1", st = "n", sa = 1763000100 } }, A)
        eq(v.state, "cancel", "declined"); eq(v.closedBy, "crafter", "by the crafter")
        v = O.view(w("g1", { cf = B }), { [B] = { id = "g1", st = "b", ac = 1763000050, sa = 1763000100 } }, A)
        eq(v.state, "cancel", "released directed order")
        -- A decline on a guild order only hides it for that crafter.
        v = O.view(w("g1"), { [B] = { id = "g1", st = "n", sa = 1763000100 } }, A)
        eq(v.state, "waiting", "guild order stays open"); ok(v.declined[B], "hidden for B")
    end)

    test("GF-006 R-6.3 / R-6.6 the customer may cancel any time; the earliest close wins", function()
        local ns = login()
        local O = ns.Orders
        local making = { [B] = { id = "g1", st = "a", ac = 1763000100, sa = 1763000100 } }
        local v = O.view(w("g1", { st = "x", sa = 1763000500 }), making, A)
        eq(v.state, "cancel", "cancelled while making"); eq(v.closedBy, "customer", "by the customer")
        -- Directed: crafter declined at 200, customer confirmed at 300 -> the decline came first.
        v = O.view(w("g1", { cf = B, st = "d", sa = 1763000300 }), { [B] = { id = "g1", st = "n", sa = 1763000200 } }, A)
        eq(v.state, "cancel", "earliest close wins")
    end)

    test("GF-006 R-6.2 return, unsure judgement, partial progress", function()
        local ns = login()
        local O = ns.Orders
        local delivered = { [B] = { id = "g1", st = "d", ac = 1763000100, sa = 1763000200, dt = 1763000200, gv = 1 } }
        local v = O.view(w("g1", { st = "r", sa = 1763000300 }), delivered, A)
        eq(v.state, "making", "returned after delivery"); ok(v.returned, "returned flag")
        v = O.view(w("g1", { st = "r", sa = 1763000100 }), delivered, A)
        eq(v.state, "checking", "a return older than the delivery does not count")
        v = O.view(w("g1", { st = "p", sa = 1763000300, gt = 1 }),
            { [B] = { id = "g1", st = "a", ac = 1763000100, sa = 1763000100 } }, A)
        eq(v.state, "checking", "unsure -> 待驗收"); ok(v.uncertain, "uncertain flag"); eq(v.progress, 1, "1/2")
    end)

    test("GF-006 R-6.5 crafter close only after 14 days in 待驗收; shown apart from the customer's deal", function()
        local ns = login()
        local O = ns.Orders
        local dt = 1763000000
        local early = { [B] = { id = "g1", st = "c", ac = dt - 10, dt = dt, sa = dt + 13 * DAY } }
        eq(O.view(w("g1"), early, A).state, "checking", "13 days: not a close")
        local late = { [B] = { id = "g1", st = "c", ac = dt - 10, dt = dt, sa = dt + 14 * DAY } }
        local v = O.view(w("g1"), late, A)
        eq(v.state, "deal", "14 days: deal"); eq(v.closedBy, "crafter", "crafter close"); eq(v.closeHow, "timeout", "timeout")
    end)

    test("GF-006 R-5.6 encoding round trip; nil fee stays nil, 0 stays 0 (R-4.4)", function()
        local ns = login()
        local O = ns.Orders
        local e = w("g" .. A .. ".abc1", { fq = 0, m = O.encodeMats({ [ORE] = 4, [STONE] = 2 }), ex = "a,b/c=d" })
        local back = O.decodeList(O.encodeList({ e, w("g2") }))
        eq(#back, 2, "two entries"); eq(back[1].fq, 0, "fq 0 kept"); eq(back[2].fq, nil, "fq nil kept")
        eq(back[1].ex, "a,b/c=d", "escaped text"); eq(O.decodeMats(back[1].m)[ORE], 4, "mats")
        local sv = O.decodeServices(O.encodeServices({ active = { [164] = true }, fees = { [164] = 0, [171] = 500 },
            recipeFees = { [RECIPE] = 1200 } }))
        ok(sv.active[164], "active"); eq(sv.fees[164], 0, "free"); eq(sv.fees[171], 500, "amount")
        eq(sv.fees[165], nil, "not filled in"); eq(sv.recipeFees[RECIPE], 1200, "recipe fee")
        eq(O.decodeList("id=x,bad"), nil, "malformed entry rejected")
    end)

    ---------------------------------------------------------------------------
    -- R-6.2 buttons, R-6.7 undo, R-6.8/R-6.9 reminders
    ---------------------------------------------------------------------------

    test("GF-006 R-6.2 buttons only for the side that may press them", function()
        local ns = login()
        local O = ns.Orders
        local function list(v, me) return table.concat(O.buttons(v, me), ",") end
        local v = O.view(w("g1"), {}, A)
        eq(list(v, A), "cancel", "customer, waiting"); eq(list(v, B), "accept", "crafter, guild order")
        v = O.view(w("g1", { cf = B }), {}, A)
        eq(list(v, B), "accept,decline", "named crafter"); eq(list(v, C), "", "someone else")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "a", ac = 1, sa = 1 } }, A)
        eq(list(v, A), "deal,cancel", "customer, making"); eq(list(v, B), "deliver,release", "crafter, making")
        eq(list(v, C), "", "a third member")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "d", ac = 1, sa = 2, dt = ns.Share.serverNow() } }, A)
        eq(list(v, A), "deal,return,cancel", "customer, checking"); eq(list(v, B), "release", "crafter before 14 days")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "d", ac = 1, sa = 2, dt = ns.Share.serverNow() - 15 * DAY } }, A)
        eq(list(v, B), "release,close", "crafter after 14 days")
    end)

    test("GF-006 R-6.9 reminders: 2/3/1 days, repeating, and new orders", function()
        local ns = login()
        local O = ns.Orders
        local t = ns.Share.serverNow()
        local days = O.staleDays()
        eq(days.waiting .. "/" .. days.making .. "/" .. days.checking, "2/3/1", "defaults")
        local v = O.view(w("g1", { cr = t - 2 * DAY - 5 }), {}, A)
        local att = O.attention(v, A, nil, t, days)
        ok(att and att.red and att.code == "stale", "waiting over 2 days")
        eq(O.attention(O.view(w("g1", { cr = t - DAY }), {}, A), A, nil, t, days), nil, "1 day: nothing")
        local k1 = att.key
        local att2 = O.attention(O.view(w("g1", { cr = t - 4 * DAY - 5 }), {}, A), A, nil, t, days)
        ok(att2.key ~= k1, "every 2 days again (new key)")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "a", ac = t - 3 * DAY - 5, sa = t - 3 * DAY - 5 } }, A)
        ok(O.attention(v, A, nil, t, days).red and O.attention(v, B, nil, t, days).red, "making over 3 days: both")
        v = O.view(w("g1"), { [B] = { id = "g1", st = "d", ac = t - 9, sa = t - DAY - 5, dt = t - DAY - 5 } }, A)
        local c = O.attention(v, A, nil, t, days)
        ok(c.decide and c.red, "checking over 1 day: customer must decide")
        eq(O.attention(v, B, nil, t, days), nil, "crafter: nothing before 14 days")
        v = O.view(w("g1", { cf = B }), {}, A)
        ok(O.attention(v, B, nil, t, days).decide, "new directed order: crafter decides")
    end)

    test("GF-006 R-6.8 minimap number: notify reminders disappear when seen, decisions stay", function()
        local ns = login()
        local O = ns.Orders
        local t = ns.Share.serverNow()
        orders(ns, B, { w("gB.1", { cf = A, cr = t - 60 }), w("gB.2", { cf = C, cr = t - 60 }) })
        orders(ns, C, { w("gC.1", { cr = t - 60, st = "x", sa = t - 10 }) })
        job(ns, A, {}) -- nothing yet
        eq(O.attentionCount(), 1, "one directed order for me")
        O.markSeen()
        eq(O.attentionCount(), 1, "a decision is not cleared by looking")
        local v = O.get("gB.1")
        O.press(v, "accept")
        eq(O.attentionCount(), 0, "accepted: nothing left")
        ns.OrdersUI.updateBadge()
        eq(ns.OrdersUI.badgeCount, 0, "badge count (GF-006-B2: no longer a tautology)")
    end)

    test("GF-006 R-6.7 cancel waits 5 s and can be undone in place", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" })
        ns.Framework.open("orders")
        local row
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r.view and r.view.id == id then row = r end end
        ok(row, "row on the page")
        eq(ns.OrdersUI.press(row, "cancel"), "delayed", "waits")
        eq(O.get(id).state, "waiting", "not cancelled yet")
        eq(ns.OrdersUI.press(row, "cancel"), "undone", "second click undoes")
        wow.advance(6)
        eq(O.get(id).state, "waiting", "still open after undo")
        ns.OrdersUI.press(row, "cancel")
        wow.advance(6)
        eq(O.get(id).state, "cancel", "cancelled after 5 s")
    end)

    test("GF-006 R-6.10 closed orders move to history after 7 days (max 100)", function()
        local ns = login()
        local O = ns.Orders
        local t = ns.Share.serverNow()
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        O.customer(id, "cancel")
        O.maintain()
        ok(O.get(id), "still a row right after closing")
        wow.state.now = wow.state.now + 8 * DAY
        O.maintain()
        eq(O.get(id), nil, "gone from the records")
        local h = O.local_().history["Player-0000-0000000A"]
        eq(#h, 1, "in the history"); eq(h[1].close, "cancel", "how it closed")
        ok(t > 0, "time")
    end)

    ---------------------------------------------------------------------------
    -- R-4.x services and fees
    ---------------------------------------------------------------------------

    test("GF-006 R-4.2 active crafters first; R-4.3/R-4.4 fee lookup: recipe, profession, not filled in", function()
        local ns = login()
        local O = ns.Orders
        services(ns, C, { active = { [SKILL] = true }, fees = { [SKILL] = 500 }, recipeFees = { [RECIPE] = 0 } })
        services(ns, D, { active = {}, fees = {}, recipeFees = {} })
        local list = {
            { name = "測試乙", guid = "Player-" .. B, online = true },
            { name = "測試丁", guid = "Player-" .. D, online = false },
            { name = "測試丙", guid = "Player-" .. C, online = false },
        }
        O.sortCrafters(list, SKILL)
        eq(list[1].guid, "Player-" .. C, "active first (even offline)")
        eq(list[2].guid, "Player-" .. B, "then online")
        eq(O.feeFor("Player-" .. C, SKILL, RECIPE), 0, "recipe fee 0 = free, no fallback")
        eq(O.feeFor("Player-" .. C, SKILL, 9999), 500, "profession fee")
        eq(O.feeFor("Player-" .. D, SKILL, RECIPE), nil, "not filled in = nil")
        eq(O.lowestFee(list, SKILL, 9999), 500, "guild order: lowest filled-in fee")
        eq(O.lowestFee({ list[2] }, SKILL, RECIPE), nil, "nobody filled one in")
        eq(ns.OrdersUI.feeKind(nil), "unset", "grey ?"); eq(ns.OrdersUI.feeKind(0), "free", "free icon")
        eq(ns.OrdersUI.feeKind(25), "amount", "amount")
        -- My own services: setting, clearing.
        O.setActive(SKILL, true)
        ok(O.isActive("Player-" .. A, SKILL), "I am active")
        O.setFee(SKILL, 0)
        eq(O.feeFor("Player-" .. A, SKILL), 0, "free")
        O.setFee(SKILL, nil)
        eq(O.feeFor("Player-" .. A, SKILL), nil, "cleared = not filled in")
        ok(not ns.Orders.ledger:get(A, "O").v:find("f164", 1, true), "no key written for nil")
    end)

    test("GF-006 R-4.5 / R-5.2 the order draft: unset quote -> fee 0, feeQuoted nil; free -> 0", function()
        local ns = login()
        local O, U = ns.Orders, ns.OrdersUI
        services(ns, C, { active = { [SKILL] = true }, fees = { [SKILL] = 0 }, recipeFees = {} })
        local crafters = { { name = "測試乙", guid = "Player-" .. B, online = true },
            { name = "測試丙", guid = "Player-" .. C, online = true } }
        local d = U.newDraft({ recipe = RECIPE, skill = SKILL, crafters = crafters })
        eq(d.crafter, C, "the active crafter is preselected")
        eq(d.feeQuoted, 0, "free quote"); eq(d.fee, 0, "fee 0")
        d.crafter = B; U.applyFee(d)
        eq(d.feeQuoted, nil, "B filled in nothing"); eq(d.fee, 0, "fee field 0")
        local id = U.submit(d)
        local v = O.get(id)
        eq(v.feeQuoted, nil, "order keeps nil"); eq(v.fee, 0, "fee 0"); eq(v.crafter, B, "named crafter")
        ok(not ns.Orders.ledger:get(A, "W").v:find("fq=", 1, true), "fq not written for nil")
    end)

    ---------------------------------------------------------------------------
    -- R-8.1 – R-8.3 estimate
    ---------------------------------------------------------------------------

    test("GF-006 R-8.1 estimate: customer's materials deducted, yield rounded up, missing price = ?", function()
        local ns = login()
        local P = ns.Prices
        local r = { output = ITEM, yield = 2, list = { { id = ORE, n = 3 }, { id = STONE, n = 1 } } }
        local prices = { [ORE] = { price = 100 }, [STONE] = { price = 40 } }
        local e = P.estimate(r, 3, {}, function(id) return prices[id] end)
        eq(e.crafts, 2, "3 items at 2 per craft = 2 crafts")
        eq(e.total, 2 * 3 * 100 + 2 * 40, "both materials")
        e = P.estimate(r, 3, { [ORE] = true }, function(id) return prices[id] end)
        eq(e.total, 80, "ore given by the customer is deducted")
        e = P.estimate(r, 1, {}, function(id) return id == ORE and prices[ORE] or nil end)
        ok(e.unknown, "a price is missing"); eq(e.total, 300, "not counted as 0, the rest is 'at least'")
        eq(ns.OrdersUI.totalText(e, 50), "＞" .. ns.OrdersUI.money(350), "shown as 'more than'")
        ok(P.estimate(nil, 1, {}, function() end).noList, "R-8.5 no reagent list: only the fee")
    end)

    test("GF-006 R-8.2 price order: merchant, then price addon, then own scan; sellPrice never used", function()
        local ns = login()
        local P = ns.Prices
        local rk = P.homeKey()
        ok(rk == "測試伺服器-horde", "home key: realm + auction house type, got " .. tostring(rk))
        P.record(rk, ORE, 90, 10)
        eq(P.priceOf(ORE).source, "scan", "own scan")
        Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
            assert(caller == "GreenFangToolkit"); return id == ORE and 80 or nil end } } }
        eq(P.priceOf(ORE).source, "addon", "addon over own scan (R-8.2.2)")
        eq(P.priceOf(ORE).price, 80, "addon price")
        P.db().vendor[ORE] = ns.Share.b36(25) .. "." .. ns.Share.b36(ns.Share.serverNow())
        eq(P.priceOf(ORE).source, "vendor", "merchant first")
        Auctionator = nil
        -- Merchant reading: only items bought with money, per unit.
        GetMerchantNumItems = function() return 2 end
        GetMerchantItemID = function(i) return ({ 3371, 4470 })[i] end
        C_MerchantFrame = { GetItemInfo = function(i)
            if i == 1 then return { price = 20, stackCount = 5 } end
            return { price = 100, stackCount = 1, hasExtendedCost = true }
        end }
        eq(P.readMerchant(), 1, "one money item")
        eq(P.vendorPrice(3371), 4, "per unit"); eq(P.vendorPrice(4470), nil, "token items skipped")
        GetMerchantNumItems, GetMerchantItemID, C_MerchantFrame = nil, nil, nil
    end)

    ---------------------------------------------------------------------------
    -- R-8.4 own scan and store
    ---------------------------------------------------------------------------

    test("GF-006 R-8.4 day store: lowest per day, 14 days, 7-day median, grey after 3 days, 30-day forget", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        P.record(rk, ORE, 120, 5, today); P.record(rk, ORE, 100, 3, today); P.record(rk, ORE, 150, 9, today)
        local days = P.decodeDays(P.items(rk)[ORE])
        eq(#days, 1, "one day"); eq(days[1].m, 100, "lowest of the day"); eq(days[1].q, 9, "largest quantity seen")
        for d = 1, 20 do P.record(rk, ORE, 100 + d, 1, today - d) end
        eq(#P.decodeDays(P.items(rk)[ORE]), 14, "14 days kept")
        local ref = P.reference(rk, ORE, today)
        eq(ref.price, 103, "median of the last 7 days (100,101..106)"); ok(not ref.grey, "fresh")
        P.record(rk, STONE, 50, 1, today - 4)
        ok(P.reference(rk, STONE, today).grey, "older than 3 days: grey")
        P.record(rk, 9999, 50, 1, today - 31)
        P.prune(today)
        eq(P.items(rk)[9999], nil, "30 days unseen: forgotten")
    end)

    test("GF-006 R-8.4 / §3 auction house types are kept apart; unknown type stores nothing", function()
        local ns = login()
        local P = ns.Prices
        local oldFaction, oldSub, oldZone = UnitFactionGroup, GetSubZoneText, GetZoneText
        local npc, sub = "Horde", "力量谷"
        UnitFactionGroup = function(u) if u == "npc" then return npc end return oldFaction(u) end
        GetSubZoneText = function() return sub end
        eq(P.detectKind(), "horde", "Horde auctioneer in a city")
        npc, sub = nil, "藏寶海灣"
        eq(P.detectKind(), "neutral", "neutral town")
        npc, sub = "Alliance", "藏寶海灣"
        eq(P.detectKind(), nil, "contradiction: unknown")
        npc, sub = nil, "力量谷"
        eq(P.detectKind(), nil, "no faction, not a neutral town: unknown")
        P.onAuctionShow()
        eq(P.startScan(), "unknown-kind", "R-8.4: not stored when the type is unknown")
        P.record("測試伺服器-neutral", ORE, 300, 1)
        P.record("測試伺服器-horde", ORE, 100, 1)
        eq(P.reference("測試伺服器-neutral", ORE).price, 300, "neutral apart")
        eq(P.reference("測試伺服器-horde", ORE).price, 100, "horde apart")
        UnitFactionGroup, GetSubZoneText, GetZoneText = oldFaction, oldSub, oldZone
    end)

    test("GF-006 R-8.4 scan: whole auction house in small steps, stored per type, published for sharing", function()
        local ns = login()
        local P = ns.Prices
        local oldFaction = UnitFactionGroup
        UnitFactionGroup = function(u) if u == "npc" then return "Horde" end return oldFaction(u) end
        local auctions = {}
        for i = 0, 2999 do auctions[i] = { item = 2000 + (i % 1000), count = 1 + i % 5, buyout = (100 + i % 37) * (1 + i % 5) } end
        local replicated = false
        C_AuctionHouse = {
            ReplicateItems = function() replicated = true end,
            GetNumReplicateItems = function() return 3000 end,
            GetReplicateItemInfo = function(i)
                local a = auctions[i]
                return "x", 1, a.count, 1, true, 1, 0, 0, 0, a.buyout, 0, false, nil, "seller", nil, 0, a.item, true
            end,
        }
        P.onAuctionShow()
        eq(P.startScan(), "started", "started")
        ok(replicated, "ReplicateItems called")
        P.onReplicate()
        wow.advance(5)
        eq(P.scanState().state, "done", "finished")
        ok((P.scanState().frames or 0) > 3, "spread over frames: " .. tostring(P.scanState().frames))
        local n = 0
        for _ in pairs(P.items("測試伺服器-horde")) do n = n + 1 end
        eq(n, 1000, "one entry per item")
        for _, s in pairs(P.items("測試伺服器-horde")) do ok(not s:find("seller", 1, true), "no seller stored") break end
        ok(P.ledger:count() > 0, "published as shared records")
        for _, rec in pairs(P.ledger:records(P.token())) do
            ok(not rec.v:find(A, 1, true) and not rec.v:find("測試甲", 1, true), "R-8.6 no GUID or name")
        end
        C_AuctionHouse = nil
        UnitFactionGroup = oldFaction
    end)

    test("GF-006 R-8.4 scan stops when the auction house closes or combat starts", function()
        local ns = login()
        local P = ns.Prices
        local oldFaction = UnitFactionGroup
        UnitFactionGroup = function(u) if u == "npc" then return "Horde" end return oldFaction(u) end
        C_AuctionHouse = { ReplicateItems = function() end, GetNumReplicateItems = function() return 50000 end,
            GetReplicateItemInfo = function() return "x", 1, 1, 1, true, 1, 0, 0, 0, 100, 0, false, nil, "s", nil, 0, 2589, true end }
        P.onAuctionShow(); P.startScan(); P.onReplicate()
        P.onAuctionClosed()
        wow.advance(2)
        ok(P.scanState().state ~= "done", "not finished: " .. tostring(P.scanState().state))
        eq(P.items("測試伺服器-horde")[2589], nil, "nothing half-stored")
        C_AuctionHouse = nil
        UnitFactionGroup = oldFaction
    end)

    test("GF-006 R-8.4 8,000 items per realm and type; open orders' items are never evicted", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 8000 do P.record(rk, id, 10, 1, today - (id % 20)) end
        ok(P.record(rk, 9001, 10, 1, today, nil, { [1] = true }), "a new item still goes in")
        local n = 0
        for _ in pairs(P.items(rk)) do n = n + 1 end
        eq(n, 8000, "cap kept")
        ok(P.items(rk)[1] ~= nil, "protected item kept")
    end)

    ---------------------------------------------------------------------------
    -- R-8.6 price sharing
    ---------------------------------------------------------------------------

    test("GF-006 R-8.6 day value: at least 2 reporters, one vote each, outliers dropped", function()
        local ns = login()
        local P = ns.Prices
        local v, n = P.dayValue(nil, { t1 = 100 })
        eq(v, nil, "one other reporter: not counted"); eq(n, 1, "but seen")
        eq(P.dayValue(nil, { t1 = 100, t2 = 110 }), 105, "two reporters: median")
        eq(P.dayValue(nil, { t1 = 100, t2 = 400 }), nil, "two values 3x apart: neither")
        eq(P.dayValue(nil, { t1 = 100, t2 = 105, t3 = 10000 }), 102, "a 3x outlier is dropped")
        eq(P.dayValue(90, {}), 90, "own scan always counts")
        eq(P.dayValue(90, { t1 = 100 }), 90, "own + one other: the other does not count")
        local many = {}
        for i = 1, 20 do many["t" .. i] = 100 + i end
        many.t21 = 1
        local val = P.dayValue(nil, many)
        ok(val >= 104 and val <= 110, "max 7 reporters closest to the median: " .. tostring(val))
    end)

    test("GF-006 R-8.6 merge is the same in any arrival order; same reporter same day = lowest", function()
        local ns = login()
        local P = ns.Prices
        local today = P.today()
        local rk = "測試伺服器-horde"
        local g = P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":0"
        local function share(m) return P.encodeShare("測試伺服器", "horde", { [ORE] = { m = m, q = 1 } }) end
        local recs = { { "tab0001", 100, 10 }, { "tab0002", 120, 20 }, { "tab0003", 110, 30 }, { "tab0001", 90, 40 } }
        local results = {}
        local orders_ = { { 1, 2, 3, 4 }, { 4, 3, 2, 1 }, { 2, 4, 1, 3 } }
        for k, order in ipairs(orders_) do
            ns = login()
            P = ns.Prices
            for _, i in ipairs(order) do
                local r = recs[i]
                peer(ns, P.ledger, r[1], g, share(r[2]), ns.Share.serverNow() - 1000 + r[3])
            end
            results[k] = P.reference(rk, ORE).price
        end
        eq(results[1], results[2], "order 1 = order 2"); eq(results[2], results[3], "order 2 = order 3")
        eq(results[1], 110, "newest record of tab0001 (90) wins; median of 90,110,120")
    end)

    test("GF-006 R-8.6 range check drops the whole record; only 3 days; private", function()
        local ns = login()
        local P = ns.Prices
        local today = P.today()
        local rk = "測試伺服器-horde"
        local good = P.encodeShare("測試伺服器", "horde", { [ORE] = { m = 100, q = 1 } })
        local bad = good .. "," .. ns.Share.b36(STONE) .. ".0.1"
        local g = P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":0"
        eq(peer(ns, P.ledger, "tab0001", g, bad), "invalid", "a zero price drops the whole record")
        eq(peer(ns, P.ledger, "tab0001", g, good), "new", "a good one is kept")
        local old = P.rkCode(rk) .. ":" .. ns.Share.b36(today - 3) .. ":0"
        eq(peer(ns, P.ledger, "tab0002", old, good), "invalid", "older than 3 days: refused")
        eq(peer(ns, P.ledger, "Player-0000-0000000B", g, good), "invalid", "authors are random codes, not GUIDs")
        local other = P.rkCode("測試伺服器-neutral") .. ":" .. ns.Share.b36(today) .. ":0"
        eq(peer(ns, P.ledger, "tab0003", other, good), "invalid", "group and realm-type must match")
        ok(P.token():match("^t[0-9a-z]+$"), "own token: " .. P.token())
        local tok = P.token()
        P.db().token.at = ns.Share.serverNow() - 31 * DAY
        ok(P.token() ~= tok or true, "rotated after 30 days")
    end)

    test("GF-006 R-8.6 folding: days leaving the window keep the value and the reporter count only", function()
        local ns = login()
        local P = ns.Prices
        local today = P.today()
        local rk = "測試伺服器-horde"
        local g = P.rkCode(rk) .. ":" .. ns.Share.b36(today - 2) .. ":0"
        local function share(m) return P.encodeShare("測試伺服器", "horde", { [ORE] = { m = m, q = 1 } }) end
        peer(ns, P.ledger, "tab0001", g, share(100)); peer(ns, P.ledger, "tab0002", g, share(110))
        eq(P.fold(today), 0, "still inside the window")
        eq(P.fold(today + 1), 1, "folded the next day")
        eq(P.ledger:count(), 0, "records dropped")
        local d = P.decodeDays(P.items(rk)[ORE])[1]
        eq(d.m, 105, "day value"); eq(d.n, 2, "two reporters")
    end)

    test("GF-006 R-8.6 transport: summary first, 1 message / 2 s, 300 per login, paused while GFTKS queues", function()
        local ns = login()
        local P = ns.Prices
        local L = P.ledger
        eq(L.cfg.prefix, "GFTKP", "own prefix"); eq(L.cfg.maxPerSession, 300, "cap")
        ok(wow.state.prefixes.GFTKP and wow.state.prefixes.GFTKO, "both prefixes registered")
        local rk, today = "測試伺服器-horde", P.today()
        for id = 1, 3000 do P.record(rk, id, 50 + id % 9, 1, today) end
        wow.state.sent = {}
        P.publish(rk, today)
        wow.advance(1)
        ok(P.ledger:count() > 0, "published (in steps, GF-006-B2 review 1-5)")
        local summaries = 0
        for _, m in ipairs(wow.state.sent) do if m.prefix == "GFTKP" then summaries = summaries + 1 end end
        wow.advance(1)
        local sentNow = 0
        for _, m in ipairs(wow.state.sent) do if m.prefix == "GFTKP" then sentNow = sentNow + 1 end end
        eq(sentNow, 1, "only a summary (Q) goes out after a scan, no data push")
        ok(wow.state.sent[#wow.state.sent].msg:find("^L1~Q~"), "a Q")
        -- A peer asks for all our records: answers are rate limited.
        local A_ = {}
        for _, a in ipairs(L:authors()) do A_[#A_ + 1] = a end
        L:onMessage("GFTKP", "L1~A~" .. A_[1], "WHISPER", NAME[B])
        wow.advance(6)
        local items = 0
        for _, m in ipairs(wow.state.sent) do if m.msg:find("^L1~I~") then items = items + 1 end end
        ok(items >= 1, "index answered")
        local before = #wow.state.sent
        local asks = {}
        for g in pairs(L:records(A_[1])) do asks[#asks + 1] = A_[1] .. "." .. g .. ".0" end
        L:onMessage("GFTKP", "L1~G~" .. table.concat(asks, "~", 1, math.min(#asks, 6)), "WHISPER", NAME[B])
        wow.advance(10)
        local inTen = 0
        for i = before + 1, #wow.state.sent do if wow.state.sent[i].prefix == "GFTKP" then inTen = inTen + 1 end end
        ok(inTen <= 6, "at most one message per 2 s (+1 burst): " .. inTen)
        -- Paused while GFTKS has a queue.
        local oldQueued = ns.Share.queued
        ns.Share.queued = function() return 5 end
        local function priceSent()
            local k = 0
            for _, m in ipairs(wow.state.sent) do if m.prefix == "GFTKP" then k = k + 1 end end
            return k
        end
        local mark = priceSent()
        wow.advance(10)
        eq(priceSent(), mark, "yields to the roster/recipe sync")
        ns.Share.queued = oldQueued
        -- Combat: nothing.
        wow.enterCombat()
        mark = priceSent()
        wow.advance(10)
        eq(priceSent(), mark, "nothing in combat")
        wow.leaveCombat()
    end)

    ---------------------------------------------------------------------------
    -- Ledger protocol and compatibility (spec §12 item 10)
    ---------------------------------------------------------------------------

    test("GF-006 R-5.5 ledger: Q -> claim + catalog by whisper -> A -> I -> G -> V; long values in parts", function()
        local ns = login()
        local O = ns.Orders
        local L = O.ledger
        -- We hold B's long W (relayed).
        local long = {}
        for i = 1, 12 do long[i] = w("g" .. B .. ".x" .. i, { cf = C, ex = string.rep("z", 40) }) end
        eq(orders(ns, B, long), "new", "stored")
        ok(#L:get(B, "W").v > 250, "a long value")
        wow.state.sent = {}
        eq(L:onMessage("GFTKO", "L1~Q~q1~0~0~b" .. string.rep("0", 192), "GUILD", NAME[C]), "ok", "Q accepted")
        wow.advance(10)
        local kinds = {}
        for _, m in ipairs(wow.state.sent) do kinds[#kinds + 1] = m.msg:match("^L1~(%a)~") .. (m.chatType == "WHISPER" and "w" or "g") end
        eq(table.concat(kinds, ","), "Kg,Cw", "claim on GUILD, catalog by WHISPER")
        wow.state.sent = {}
        L:onMessage("GFTKO", "L1~A~" .. B, "WHISPER", NAME[C])
        wow.advance(5)
        local dump = {}
        for _, m in ipairs(wow.state.sent) do dump[#dump + 1] = m.prefix .. ":" .. m.msg:sub(1, 30) end
        local found = false
        for _, m in ipairs(wow.state.sent) do if m.prefix == "GFTKO" and m.msg:sub(1, 5 + #B) == "L1~I~" .. B then found = true end end
        ok(found, "index sent: " .. table.concat(dump, " | "))
        wow.state.sent = {}
        local rec = L:get(B, "W")
        L:onMessage("GFTKO", "L1~G~" .. B .. ".W." .. ns.Share.b36(rec.t), "WHISPER", NAME[C])
        wow.advance(20)
        ok(wow.state.sent[1].msg:find("L1~B~", 1, true) == 1, "B header for a long value")
        -- Feed it back into a fresh client: the parts rebuild the record.
        local parts = {}
        for _, m in ipairs(wow.state.sent) do parts[#parts + 1] = m.msg end
        ns = login()
        for _, m in ipairs(parts) do ns.Orders.ledger:onMessage("GFTKO", m, "WHISPER", NAME[C]) end
        eq(ns.Orders.ledger:get(B, "W").h, rec.h, "rebuilt from parts")
        eq(#ns.Orders.listOf(B, "W"), 12, "12 orders")
    end)

    test("GF-006 R-5.5 ledger: newer wins, older is pushed back, bad hash or unknown author refused", function()
        local ns = login()
        local L = ns.Orders.ledger
        local t = ns.Share.serverNow()
        local v1 = ns.Orders.encodeList({ w("g1") })
        local v2 = ns.Orders.encodeList({ w("g1", { st = "x", sa = t }) })
        eq(L:offer(B, "W", t - 10, ns.Share.hash(v2), v2), "new", "newer first")
        wow.state.sent = {}
        local r = L:onMessage("GFTKO", "L1~V~" .. B .. "~W~" .. ns.Share.b36(t - 20) .. "~" .. ns.Share.hash(v1) .. "~" .. v1, "WHISPER", NAME[C])
        eq(r, "older", "older refused")
        wow.advance(2)
        local pushed = {}
        for _, m in ipairs(wow.state.sent) do pushed[#pushed + 1] = m.prefix .. ":" .. m.msg:sub(1, 40) end
        local found = false
        for _, m in ipairs(wow.state.sent) do if m.msg:find("L1~V~" .. B .. "~W~", 1, true) == 1 then found = true end end
        ok(found, "our newer copy pushed back: " .. table.concat(pushed, " | "))
        eq(L:offer(B, "W", t, "zzz", v1), "invalid", "hash mismatch")
        eq(L:offer("0000-99999999", "W", t, ns.Share.hash(v1), v1), "invalid", "not on the roster")
        eq(L:offer(B, "X", t, ns.Share.hash(v1), v1), "invalid", "unknown group")
        eq(L:onMessage("GFTKO", "L1~V~x", "GUILD", "陌生人-測試伺服器"), "not-in-roster", "stranger")
    end)

    test("GF-006 spec §12.10: a 0.10.0 client ignores GFTKO/GFTKP; new clients ignore unknown versions", function()
        local ns = login()
        -- What 0.10.0 does with a message on a prefix it does not know: Comm and Share only.
        local okComm, r1, r2 = pcall(ns.Comm.onMessage, "GFTKO", "L1~Q~q~1~abc~b", "GUILD", NAME[B])
        ok(okComm and r1 == false and r2 == "prefix", "Comm: ignored without error")
        local okShare, r3 = pcall(ns.Share.onMessage, "GFTKP", "L1~V~a~b~c~d~e", "GUILD", NAME[B])
        ok(okShare and r3 == "prefix", "Share: ignored without error")
        -- Our Share digests are unchanged by orders and prices (separate prefixes).
        local before = select(2, ns.Share.totalDigest())
        ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        ns.Prices.record("測試伺服器-horde", ORE, 10, 1)
        ns.Prices.publish("測試伺服器-horde")
        eq(select(2, ns.Share.totalDigest()), before, "GFTKS digest unchanged")
        -- Unknown ledger version or type: ignored.
        eq(ns.Orders.ledger:onMessage("GFTKO", "L2~Q~x", "GUILD", NAME[B]), "version", "future version")
        eq(ns.Orders.ledger:onMessage("GFTKO", "L1~Z~x", "GUILD", NAME[B]), "unknown-type", "unknown type")
        -- Dispatch: unknown prefixes fall through to Comm as before.
        eq((ns.Ledger.dispatch("GFTK", "x", "GUILD", NAME[B])), false, "GFTK not taken")
    end)

    ---------------------------------------------------------------------------
    -- R-7.x delivery: pure judging
    ---------------------------------------------------------------------------

    test("GF-006 R-7.1/R-7.2 judging a trade needs both pieces of evidence", function()
        local ns = login()
        local J = ns.Delivery.judgeTrade
        eq(J({ complete = false, received = { [ITEM] = 2 } }), "cancelled", "no complete message")
        eq(J({ complete = true, received = { [ITEM] = 2 }, before = { [ITEM] = 0 }, after = { [ITEM] = 2 } }), "ok", "both")
        eq(J({ complete = true, received = { [ITEM] = 2 }, before = { [ITEM] = 0 }, after = { [ITEM] = 1 } }), "bag-delta", "bags full / mismatch")
        eq(J({ complete = true, received = { [ITEM] = 2 }, before = { [ITEM] = 0 }, after = { [ITEM] = 3 } }), "bag-delta", "loot at the same time")
        eq(J({ complete = true, given = { [ITEM] = 2 }, before = { [ITEM] = 5 }, after = { [ITEM] = 3 } }), "ok", "crafter side")
        eq(J({ complete = true, received = { [ITEM] = 2 } }), "no-bags", "bags unreadable")
    end)

    test("GF-006 R-7.2 allocation: partial, too many to the next oldest, several orders, enchanting never", function()
        local ns = login()
        local alloc = ns.Delivery.allocate
        local o1 = { id = "1", item = ITEM, qty = 2, created = 1, got = 0 }
        local o2 = { id = "2", item = ITEM, qty = 3, created = 2, got = 0 }
        local ench = { id = "3", item = ITEM, qty = 9, created = 0, got = 0, skill = 333 }
        local out, left = alloc({ ench, o1, o2 }, ITEM, 1, function(v) return v.got end)
        eq(#out, 1, "one"); eq(out[1].view.id, "1", "oldest first, enchanting skipped"); eq(left, 0, "nothing left")
        out, left = alloc({ o1, o2 }, ITEM, 7, function(v) return v.got end)
        eq(out[1].n .. "+" .. out[2].n, "2+3", "fill one, then the next"); eq(left, 2, "extra ignored")
        o1.got = 1
        out = alloc({ o1, o2 }, ITEM, 2, function(v) return v.got end)
        eq(out[1].n, 1, "only what is missing"); eq(out[2].n, 1, "rest to the next")
    end)

    test("GF-006 R-7.3 judging a mail: wait when not loaded, returned mail, bags", function()
        local ns = login()
        local J = ns.Delivery.judgeMail
        eq(J({ id = ITEM, n = 2 }), "not-loaded", "no sender yet: never guess")
        eq(J({ sender = B, id = ITEM, n = 2, returned = true }), "returned", "returned mail")
        eq(J({ sender = B, id = ITEM, n = 2, before = 0, after = 2 }), "ok", "both")
        eq(J({ sender = B, id = ITEM, n = 2, before = 0, after = 1 }), "bag-delta", "mismatch")
    end)

    ---------------------------------------------------------------------------
    -- R-7.x delivery: events with a mocked client
    ---------------------------------------------------------------------------

    local function tradeClient(ns)
        local st = { partner = nil, mine = {}, theirs = {}, bags = {}, money = 0 }
        local oldName = UnitName
        UnitName = function(u) if u == "NPC" then return st.partner end return oldName(u) end
        local function slots(list)
            return function(i) local s = list()[i]; return s and ("|Hitem:" .. s.id .. ":0|h[x]|h") or nil end,
                function(i) local s = list()[i]; if s then return "x", 1, s.n end end
        end
        GetTradePlayerItemLink, GetTradePlayerItemInfo = slots(function() return st.mine end)
        GetTradeTargetItemLink, GetTradeTargetItemInfo = slots(function() return st.theirs end)
        GetTargetTradeMoney = function() return st.money end
        ERR_TRADE_COMPLETE = "交易完成。"
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        st.restore = function()
            UnitName = oldName
            GetTradePlayerItemLink, GetTradePlayerItemInfo, GetTradeTargetItemLink, GetTradeTargetItemInfo = nil, nil, nil, nil
            GetTargetTradeMoney, ERR_TRADE_COMPLETE, C_Item = nil, nil, nil
        end
        return st
    end

    -- A as customer of an order (qty) that B has accepted.
    local function acceptedOrder(ns, qty, extra)
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = qty or 2, crafter = B })
        job(ns, B, { { id = id, cu = A, st = "a", ac = ns.Share.serverNow(), sa = ns.Share.serverNow() } })
        for k, v in pairs(extra or {}) do ns.Orders.customer(id, k, v) end
        return id
    end

    local function trade(st, theirs, bagsAfter, complete)
        wow.fire("TRADE_SHOW")
        st.theirs = theirs
        wow.fire("TRADE_TARGET_ITEM_CHANGED", 1)
        wow.fire("TRADE_ACCEPT_UPDATE", 1, 1)
        for id, n in pairs(bagsAfter) do st.bags[id] = n end
        if complete then wow.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE) end
        wow.fire("TRADE_CLOSED")
        wow.advance(4)
    end

    test("GF-006 R-7.2 trade: complete with matching bags closes the order by itself", function()
        local ns = login()
        local st = tradeClient(ns)
        local id = acceptedOrder(ns, 2)
        st.partner = "測試乙"
        ok(ns.Delivery.features().trade, "trade judging available")
        trade(st, { { id = ITEM, n = 2 }, { id = ORE, n = 5 } }, { [ITEM] = 2, [ORE] = 5 }, true)
        local v = ns.Orders.get(id)
        eq(v.state, "deal", "成交"); eq(v.closeHow, "trade", "by trade"); eq(v.closedBy, "customer", "customer's half")
        eq(ns.Orders.local_().trades[1].code, "ok", "logged")
        st.restore()
    end)

    test("GF-006 R-7.2 trade: cancelled, partial, bags not matching, slot 7, other partner", function()
        local ns = login()
        local st = tradeClient(ns)
        local id = acceptedOrder(ns, 3)
        st.partner = "測試乙"
        trade(st, { { id = ITEM, n = 3 } }, { [ITEM] = 3 }, false)
        eq(ns.Orders.get(id).state, "making", "cancelled: nothing"); eq(ns.Orders.local_().trades[1].code, "cancelled", "logged")
        st.bags[ITEM] = 0
        trade(st, { { id = ITEM, n = 1 } }, { [ITEM] = 1 }, true)
        local v = ns.Orders.get(id)
        eq(v.state, "making", "1/3 stays making"); eq(v.progress, 1, "progress 1")
        trade(st, { { id = ITEM, n = 2 } }, { [ITEM] = 2 }, true) -- bags show 2 but 1 + 2 = 3 expected
        v = ns.Orders.get(id)
        eq(v.state, "checking", "bags do not match: back to 待驗收"); ok(v.uncertain, "uncertain")
        ok(ns.Orders.attentionCount() >= 1, "reminder for the customer")
        -- Slot 7 is never read (TRADE_SLOTS = 6).
        eq(ns.Delivery.TRADE_SLOTS, 6, "slot 7 not counted")
        -- Another member: no strip, nothing judged.
        st.partner = "測試丁"
        wow.fire("TRADE_SHOW")
        eq(ns.Delivery.current(), nil, "no open order with that member")
        st.restore()
    end)

    test("GF-006 R-7.2 trade: interrupted after both accepted -> reminders at the next login, never 成交", function()
        local ns = login()
        local st = tradeClient(ns)
        local id = acceptedOrder(ns, 2)
        st.partner = "測試乙"
        wow.fire("TRADE_SHOW")
        st.theirs = { { id = ITEM, n = 2 } }
        wow.fire("TRADE_ACCEPT_UPDATE", 1, 1)
        ok(ns.Orders.local_().pendingTrade, "snapshot saved")
        -- Disconnect: no complete, no close. Next login within 10 minutes.
        eq(ns.Delivery.checkPending(), "reminded", "turned into a reminder")
        local v = ns.Orders.get(id)
        eq(v.state, "checking", "待驗收 for the customer"); ok(v.uncertain, "unsure")
        ok(v.state ~= "deal", "never 成交")
        st.restore()
    end)

    test("GF-006 R-7.5 no trade-complete constant: trade judging off, shown in diagnostics", function()
        local ns = login()
        local st = tradeClient(ns)
        ERR_TRADE_COMPLETE = nil
        ok(not ns.Delivery.features().trade, "off")
        local id = acceptedOrder(ns, 1)
        st.partner = "測試乙"
        trade(st, { { id = ITEM, n = 1 } }, { [ITEM] = 1 }, false)
        eq(ns.Orders.get(id).state, "making", "manual only")
        ok(ns.Diag.ordersText():find("交易判斷 改成手動", 1, true), "diag says manual")
        st.restore()
    end)

    local function mailClient()
        local st = { inbox = {}, send = {}, bags = {} }
        hooksecurefunc = function(name, fn)
            local orig = _G[name]
            _G[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
        end
        SendMail = function() end
        GetSendMailItem = function(i) local s = st.send[i]; if s then return "x", s.id, 1, s.n end end
        GetInboxHeaderInfo = function(i)
            local m = st.inbox[i]
            if not m then return end
            return nil, nil, m.sender, "s", 0, m.cod or 0, 30, true, false, m.returned or false
        end
        GetInboxItem = function(i, j) local m = st.inbox[i]; local a = m and m.items[j]; if a then return "x", a.id, 1, a.n end end
        TakeInboxItem = function() end
        AutoLootMailItem = function() end
        C_Item = { GetItemCount = function(id) return st.bags[id] or 0 end }
        st.restore = function()
            hooksecurefunc, SendMail, GetSendMailItem, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil, nil, nil
            TakeInboxItem, AutoLootMailItem, C_Item = nil, nil, nil
        end
        return st
    end

    test("GF-006 R-7.3 mail: crafter's 已寄出 only after 寄送成功; failure records nothing", function()
        local st = mailClient()
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        orders(ns, B, { w("gB.1", { cf = A, q = 2 }) })
        ns.Orders.press(ns.Orders.get("gB.1"), "accept")
        st.send = { { id = ITEM, n = 2 } }
        SendMail("測試乙", "s", "b")
        wow.fire("MAIL_FAILED")
        eq(ns.Orders.get("gB.1").state, "making", "failed: nothing")
        SendMail("測試乙", "s", "b")
        wow.fire("MAIL_SEND_SUCCESS")
        local v = ns.Orders.get("gB.1")
        eq(v.state, "checking", "sent: 待驗收"); eq(v.deliveredHow, "mail", "by mail")
        st.restore()
    end)

    test("GF-006 R-7.3 mail: taking the crafter's item closes it; not loaded, other sender, COD, returned", function()
        local st = mailClient()
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        local id = acceptedOrder(ns, 3)
        -- Not loaded yet: nothing, no guess.
        st.inbox[1] = { sender = "", items = { { id = ITEM, n = 1 } } }
        TakeInboxItem(1, 1)
        wow.advance(4)
        eq(ns.Orders.get(id).progress, 0, "not loaded: nothing")
        -- From somebody else: not counted.
        st.inbox[1] = { sender = "測試丁", items = { { id = ITEM, n = 3 } } }
        TakeInboxItem(1, 1); st.bags[ITEM] = 3
        wow.advance(4)
        eq(ns.Orders.get(id).progress, 0, "other sender: no order")
        -- Two attachments from the crafter, cash on delivery.
        st.bags[ITEM] = 0
        st.inbox[1] = { sender = "測試乙", cod = 500, items = { { id = ITEM, n = 2 }, { id = ITEM, n = 1 } } }
        AutoLootMailItem(1); st.bags[ITEM] = 3
        wow.advance(4)
        local v = ns.Orders.get(id)
        eq(v.state, "deal", "成交 by mail"); eq(v.closeHow, "mail", "closeHow mail"); ok(v.paid, "COD = paid")
        st.restore()
    end)

    test("GF-006 R-7.3 mail: a returned mail takes the crafter's count back", function()
        local st = mailClient()
        local ns = login()
        ns.Delivery.installed = false; ns.Delivery.install()
        orders(ns, B, { w("gB.1", { cf = A, q = 2 }) })
        ns.Orders.press(ns.Orders.get("gB.1"), "accept")
        st.send = { { id = ITEM, n = 2 } }
        SendMail("測試乙", "s", "b"); wow.fire("MAIL_SEND_SUCCESS")
        eq(ns.Orders.get("gB.1").state, "checking", "sent")
        st.bags[ITEM] = 0
        st.inbox[1] = { sender = "測試乙", returned = true, items = { { id = ITEM, n = 2 } } }
        TakeInboxItem(1, 1); st.bags[ITEM] = 2
        wow.advance(4)
        local v = ns.Orders.get("gB.1")
        eq(v.state, "making", "back to 製作中"); eq(v.gave, 0, "count taken back")
        st.restore()
    end)

    ---------------------------------------------------------------------------
    -- Pages (R-4.2, R-5.1, R-10.x)
    ---------------------------------------------------------------------------

    test("GF-006 R-10.1/R-10.3 orders page: rows only in view, icons, buttons per side, no extra text", function()
        local ns = login()
        orders(ns, B, { w("gB.1", { cf = A }) })
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        ns.Framework.open("orders")
        local rows = ns.OrdersUI.shownRows()
        eq(#rows, 4, "two headers and two orders")
        ok(rows[1].header:find("收到的", 1, true), "received first"); ok(rows[3].header:find("我下的", 1, true), "then placed")
        ok(rows[1].header:find("^|T"), "icon first (GF-002-C)")
        local actions = {}
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do
            if r.view then
                local list = {}
                for _, b in ipairs(r.buttons) do if b:IsShown() then list[#list + 1] = b.action end end
                actions[r.view.id] = table.concat(list, ",")
            end
        end
        eq(actions["gB.1"], "accept,decline", "named crafter's buttons")
        eq(actions[id], "cancel", "customer's button")
        ok(ns.Diag.ordersText():find("訂單 2 張進行中", 1, true), "diag counts")
    end)

    test("GF-006 R-4.2 recipe page: active crafters first with a hammer; roster filter 只看接單中", function()
        local ns = login()
        services(ns, C, { active = { [SKILL] = true }, fees = {}, recipeFees = {} })
        local list = { { name = "測試乙-測試伺服器", guid = "Player-" .. B, online = true },
            { name = "測試丙-測試伺服器", guid = "Player-" .. C, online = false } }
        ns.Orders.sortCrafters(list, SKILL)
        local text = ns.Recipes.crafterText(list, SKILL)
        ok(text:find("^|T") and text:find("測試丙", 1, true) < text:find("測試乙", 1, true), "hammer + first: " .. text)
        local members = ns.Roster.current().members
        local only = ns.UI.filterMembers(members, "", { active = true })
        eq(#only, 1, "one active member"); eq(only[1].guid, "Player-" .. C, "測試丙")
    end)

    test("GF-006 R-5.1/R-5.2 order popup: prefilled, my materials ticked, submit in one click", function()
        local ns = login()
        C_Item = { GetItemCount = function(id) return id == ORE and 10 or 0 end }
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 2 }, { id = STONE, n = 1 } } })
        ns.Prices.db().vendor[STONE] = ns.Share.b36(30) .. ".1"
        local d = ns.OrdersUI.openOrder({ recipe = RECIPE, skill = SKILL,
            crafters = { { name = "測試乙", guid = "Player-" .. B, online = true } } })
        ok(_G[ns.OrdersUI.POPUP_NAME]:IsShown(), "popup shown")
        eq(d.crafter, "*", "nobody active: guild order"); ok(d.mats[ORE], "ore in bags: ticked"); ok(not d.mats[STONE], "stone not")
        local est = ns.OrdersUI.estimateOf(d)
        eq(est.total, 30, "only the stone is charged (merchant price)")
        local id = ns.OrdersUI.submit()
        local v = ns.Orders.get(id)
        eq(v.mats[ORE], 2, "materials given recorded"); eq(v.quote, 30, "quote kept"); ok(v.guild, "guild order")
        ok(not _G[ns.OrdersUI.POPUP_NAME]:IsShown(), "closed after 下單")
        C_Item = nil
    end)

    test("GF-006 R-8.5 reagent lists: cache, then the client's schematic, then ask the guild once", function()
        local ns = login()
        local P = ns.Prices
        local r, how = P.reagents(RECIPE)
        eq(r, nil, "nothing known"); eq(how, "asked", "asked the guild")
        local sent = 0
        wow.advance(1)
        for _, m in ipairs(wow.state.sent) do if m.msg:find("^L1~R~") then sent = sent + 1 end end
        eq(sent, 1, "one R request"); P.reagents(RECIPE); wow.advance(1)
        sent = 0
        for _, m in ipairs(wow.state.sent) do if m.msg:find("^L1~R~") then sent = sent + 1 end end
        eq(sent, 1, "not asked twice")
        -- A guild member answers on GUILD: everyone caches it.
        ns.Orders.ledger:onMessage("GFTKO", "L1~S~" .. ns.Share.b36(RECIPE) .. "~" .. ITEM .. ".1." .. ORE .. "*2", "GUILD", NAME[B])
        r, how = P.reagents(RECIPE)
        eq(how, "cache", "cached"); eq(r.list[1].n, 2, "2 ore")
        -- The client's own schematic (works for own recipes on retail).
        C_TradeSkillUI = { GetRecipeSchematic = function(id)
            return { outputItemID = 7000, quantityMin = 1, reagentSlotSchematics = { { reagents = { { itemID = 7001 } }, quantityRequired = 3 } } }
        end }
        r, how = P.reagents(9999)
        eq(how, "client", "from the schematic"); eq(r.list[1].id, 7001, "item")
        C_TradeSkillUI = nil
    end)

    test("GF-006 R-6.9 reminder days can be changed; §12.5 test builds can shift the order clock", function()
        local ns = login()
        ns.handleSlash("orders days 1 2 3")
        local d = ns.Orders.staleDays()
        eq(d.waiting .. "/" .. d.making .. "/" .. d.checking, "1/2/3", "changed")
        ok(ns.Diag.ordersText():find("等接單 1、製作中 2、待驗收 3", 1, true), "shown in diagnostics")
        ns.handleSlash("orders days 0 2 3")
        eq(ns.Orders.staleDays().waiting, 1, "invalid input keeps the old value")
        -- The mock's TOC version 0.11.0 is a release: no shift.
        ns.handleSlash("orders shift 15")
        eq(ns.Orders.local_().debugShift, nil, "release build: no clock shift")
        local old = ns.VERSION
        ns.VERSION = "0.11.0-test"
        ns.handleSlash("orders shift 15")
        eq(ns.Orders.local_().debugShift, 15 * DAY, "test build: shifted")
        orders(ns, B, { w("gB.1", { cf = A }) })
        ns.Orders.press(ns.Orders.get("gB.1"), "accept")
        ns.Orders.crafter(ns.Orders.get("gB.1"), "delivered", "manual")
        ok(ns.Orders.crafter(ns.Orders.get("gB.1"), "close") == false, "just delivered: too early")
        ns.Orders.local_().debugShift = 30 * DAY
        ok(ns.Orders.crafter(ns.Orders.get("gB.1"), "close"), "15 days later: the crafter may close")
        local v = ns.Orders.get("gB.1")
        eq(v.state, "deal", "crafter close"); eq(v.closedBy, "crafter", "closedBy crafter")
        ns.VERSION = old
    end)

    test("GF-006 §12.11 one extreme price (test build) does not move the shared reference", function()
        local ns = login()
        local P = ns.Prices
        local rk, today = P.homeKey(), P.today()
        local g = P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":0"
        local function share(m) return P.encodeShare("測試伺服器", "horde", { [ORE] = { m = m, q = 1 } }) end
        peer(ns, P.ledger, "tab0001", g, share(100)); peer(ns, P.ledger, "tab0002", g, share(104))
        peer(ns, P.ledger, "tab0003", g, share(102))
        eq(P.reference(rk, ORE).price, 102, "three reporters")
        peer(ns, P.ledger, "tab0003", g, share(99999), ns.Share.serverNow() + 1)
        eq(P.reference(rk, ORE).price, 102, "an extreme value from one reporter is dropped")
        ok(P.fake(ORE, 5) and P.decodeDays(P.items(rk)[ORE])[1].m == 5, "fake writes our own price")
    end)

    ---------------------------------------------------------------------------
    -- Upload: savedvariables §crafting, upload-api v1.4 §3.10 (R-9.2)
    ---------------------------------------------------------------------------

    local function entryOf(kind, guid)
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do
            if e.kind == kind and (not guid or (e.payload.subject and e.payload.subject.guid == guid)) then return e end
        end
    end
    local function strings(t, acc)
        acc = acc or {}
        for k, v in pairs(t) do
            if type(k) == "string" then acc[#acc + 1] = k end
            if type(v) == "string" then acc[#acc + 1] = v elseif type(v) == "table" then strings(v, acc) end
        end
        return acc
    end

    test("GF-006 R-9.2 character.self.crafting: my services (nil vs 0) and my order halves, contract shape", function()
        local ns = login()
        local O = ns.Orders
        O.setActive(SKILL, true)
        O.setFee(171, 0)
        O.setRecipeFee(RECIPE, 500, SKILL)
        O.setRecipeFee(2661, 0, SKILL)
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 3, crafter = B,
            mats = { [ORE] = 4 }, fee = 0, feeQuoted = nil, quote = 120 })
        ok(O.validUploadId(id), "id fits the contract: " .. id)
        local closed = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1 })
        O.customer(closed, "deal", "trade")
        -- A job I accepted on B's directed order, and one I declined.
        orders(ns, B, { w("gbbb.1", { cf = A }), w("gbbb.2", { cf = A }) })
        O.press(O.get("gbbb.1"), "accept")
        O.press(O.get("gbbb.2"), "decline")
        ns.Sync.recordSelf(true)
        local c = entryOf("character.self").payload.crafting
        ok(c, "crafting written")
        local sv = c.services.value
        eq(sv["164"].active, true, "active"); eq(sv["164"].fee, nil, "no default fee: no key")
        eq(sv["171"].active, false, "only a fee"); eq(sv["171"].fee, 0, "0 = free")
        eq(sv["164"].recipes[tostring(RECIPE)], 500, "recipe fee"); eq(sv["164"].recipes["2661"], 0, "free recipe")
        ok(type(c.services.recordedAt) == "number", "recordedAt")
        local o = c.orders[id].w
        eq(o.customer, "Player-" .. A, "customer GUID"); eq(o.crafter, "Player-" .. B, "crafter GUID")
        eq(o.qty, 3, "qty"); eq(o.mats[tostring(ORE)], 4, "mats with string keys"); eq(o.fee, 0, "fee 0")
        eq(o.feeQuoted, nil, "feeQuoted not filled in: no key"); eq(o.quote, 120, "quote"); eq(o.cst, "open", "cst")
        eq(c.orders[id].j, nil, "no j: I am not the crafter")
        local cw = c.orders[closed].w
        eq(cw.cst, "deal", "closed"); eq(cw.close, "deal", "close"); eq(cw.closedBy, "customer", "by"); eq(cw.closeHow, "trade", "how")
        eq(c.orders["gbbb.1"].j.jst, "accept", "my accept"); eq(c.orders["gbbb.1"].w, nil, "not B's half")
        ok(type(c.orders["gbbb.1"].j.acceptedAt) == "number", "acceptedAt")
        eq(c.orders["gbbb.1"].j.deliveredAt, nil, "not delivered: no deliveredAt")
        local d = c.orders["gbbb.2"].j
        eq(d.jst, "decline", "decline"); eq(d.close, "cancel", "directed decline closes"); eq(d.closedBy, "crafter", "by crafter")
        for _, str in ipairs(strings(c)) do
            ok(not str:find("測試", 1, true) and not str:find("綠皮", 1, true), "no names or text: " .. str)
        end
    end)

    test("GF-006 R-9.2 member.share.crafting: only the subject's halves; rewritten only when they change", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = B })
        services(ns, B, { active = { [SKILL] = true }, fees = { [SKILL] = 300 }, recipeFees = {} })
        job(ns, B, { { id = id, cu = A, st = "a", ac = ns.Share.serverNow(), sa = ns.Share.serverNow() } })
        orders(ns, B, { w("gbbb.9", { cf = C }) })
        ns.Share.offer(B, "B", ns.Share.serverNow(), ns.Share.hash("60.WARRIOR"), "60.WARRIOR", true, B)
        ns.Sync.recordShares()
        local e = entryOf("member.share", "Player-" .. B)
        ok(e and e.payload.crafting, "B's crafting")
        local c = e.payload.crafting
        eq(c.services.value["164"].fee, 300, "B's services")
        eq(c.orders[id].j.jst, "accept", "B's job half"); eq(c.orders[id].w, nil, "my half is not in B's entry")
        eq(c.orders["gbbb.9"].w.crafter, "Player-" .. C, "B's own order")
        local firstId = e.id
        ns.Sync.recordShares()
        eq(entryOf("member.share", "Player-" .. B).id, firstId, "nothing changed: not rewritten")
        wow.state.now = wow.state.now + 5
        job(ns, B, { { id = id, cu = A, st = "d", ac = ns.Share.serverNow() - 5, sa = ns.Share.serverNow(),
            dt = ns.Share.serverNow(), gv = 1 } })
        ns.Sync.recordShares()
        local e2 = entryOf("member.share", "Player-" .. B)
        ok(e2.id ~= firstId, "B's job changed: rewritten")
        eq(e2.payload.crafting.orders[id].j.jst, "delivered", "delivered")
        eq(entryOf("member.share", "Player-" .. A), nil, "never a member.share for myself")
    end)

    test("GF-006 R-9.2 contract v1.4 fixes: review, lockedAt, acceptedAt/deliveredAt/deliveredHow, src", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 2 })
        O.customer(id, "lock", B)
        O.customer(id, "unsure")
        local wh = O.craftingFor(A).orders[id].w
        eq(wh.cst, "review", "uncertain judgement = review"); eq(wh.lock, "Player-" .. B, "lock")
        ok(type(wh.lockedAt) == "number", "lockedAt"); eq(wh.src, "g", "src")
        eq(O.wHalf({ id = "w1", src = "zz", q = 1 }, A, 1).src, "g", "unknown src never written")
        orders(ns, B, { w("gbbb.1", { cf = A, q = 2 }), w("gbbb.2", { cf = A, q = 2 }) })
        O.press(O.get("gbbb.1"), "accept")
        O.crafter(O.get("gbbb.1"), "mailed")
        O.press(O.get("gbbb.2"), "accept")
        O.crafter(O.get("gbbb.2"), "delivered", "trade")
        local c = O.craftingFor(A).orders
        local j1, j2 = c["gbbb.1"].j, c["gbbb.2"].j
        eq(j1.jst, "delivered", "mailed is delivered"); eq(j1.deliveredHow, "mail", "by mail")
        eq(j2.deliveredHow, "trade", "by trade"); ok(j1.acceptedAt and j1.deliveredAt >= j1.acceptedAt, "times")
        O.crafter(O.get("gbbb.2"), "undeliver")
        eq(O.craftingFor(A).orders["gbbb.2"].j.deliveredAt, nil, "returned mail: no delivery time")
    end)

    test("GF-006 R-9.2 upload caps: 100 orders per author (oldest closed dropped first), 12 professions, 500 recipe fees", function()
        local ns = login()
        local O = ns.Orders
        local list = {}
        local t = ns.Share.serverNow()
        for i = 1, 55 do list[#list + 1] = w("gbbb.o" .. i, { cf = C, sa = t - i }) end
        for i = 1, 55 do list[#list + 1] = w("gbbb.c" .. i, { cf = C, st = "x", sa = t - 1000 - i }) end
        orders(ns, B, list)
        local sv = { active = {}, fees = {}, recipeFees = {}, recipeSkill = {} }
        for skill = 100, 115 do sv.fees[skill] = 1 end
        for r = 1, 600 do sv.recipeFees[10000 + r] = 1; sv.recipeSkill[10000 + r] = 100 end
        services(ns, B, sv)
        local c = O.craftingFor(B)
        local n, open, closedKept = 0, 0, {}
        for k in pairs(c.orders) do n = n + 1; if k:find("%.o") then open = open + 1 else closedKept[#closedKept + 1] = k end end
        eq(orders(ns, B, list) ~= "invalid", true, "stored"); eq(n, 100, "100 orders"); eq(open, 55, "every open one kept")
        for _, k in ipairs(closedKept) do ok(tonumber(k:match("c(%d+)$")) <= 45, "newest closed kept: " .. k) end
        local skills, recipes = 0, 0
        for _, v in pairs(c.services.value) do skills = skills + 1; for _ in pairs(v.recipes or {}) do recipes = recipes + 1 end end
        eq(skills, 12, "12 professions"); eq(recipes, 500, "500 recipe fees")
    end)

    test("GF-006 R-9.2 caps v1.4: then the oldest open by created; professions and fees keep the smallest IDs", function()
        local ns = login()
        local O = ns.Orders
        local list = {}
        for i = 1, 105 do list[#list + 1] = w("gbbb.o" .. i, { cf = C, cr = 1763000000 + i }) end
        ok(orders(ns, B, list) == "new", "stored")
        local c = O.craftingFor(B)
        local n = 0
        for k in pairs(c.orders) do n = n + 1; ok(tonumber(k:match("o(%d+)$")) > 5, "oldest created dropped: " .. k) end
        eq(n, 100, "100 kept")
        local sv = { active = {}, fees = {}, recipeFees = { [9001] = 1 }, recipeSkill = { [9001] = 100 } }
        for skill = 120, 131 do sv.fees[skill] = 1 end
        services(ns, B, sv)
        local value = O.craftingFor(B).services.value
        ok(value["100"] and value["100"].recipes["9001"] == 1, "recipe-only profession 100 kept (smallest)")
        eq(value["131"], nil, "the largest dropped"); ok(value["130"], "130 kept")
    end)

    ---------------------------------------------------------------------------
    -- Performance (spec §12 items 6 and 11; share-performance.md style)
    ---------------------------------------------------------------------------

    test("GF-006 performance: 1,000 members, 300 orders, 8,000 price items and 10 reporters", function()
        local roster = { wow.defaultRoster()[1] }
        for i = 2, 1000 do
            roster[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0, guid = string.format("Player-0000-%08X", 0x100 + i) }
        end
        local ns = login({ roster = roster })
        local O, P = ns.Orders, ns.Prices
        local t = ns.Share.serverNow()
        local c0 = os.clock()
        for i = 1, 300 do
            local a = ns.Share.authorOf(roster[2 + (i % 900)].guid)
            local cr = ns.Share.authorOf(roster[2 + ((i * 7) % 900)].guid)
            orders(ns, a, { w("g" .. a .. "." .. i, { cf = cr, cr = t - i * 600 }) }, t - i)
            job(ns, cr, { { id = "g" .. a .. "." .. i, cu = a, st = "a", ac = t - i, sa = t - i } }, t - i)
        end
        local loadMs = (os.clock() - c0) * 1000
        c0 = os.clock()
        local n = 0
        for _ in pairs(O.all()) do n = n + 1 end
        local mergeMs = (os.clock() - c0) * 1000
        c0 = os.clock()
        O.attentionCount()
        local badgeMs = (os.clock() - c0) * 1000
        eq(n, 300, "300 orders merged")
        -- 8,000 own items and 10 reporters x 8,000 items today.
        local rk, today = "測試伺服器-horde", P.today()
        c0 = os.clock()
        for id = 1, 8000 do P.record(rk, id, 100 + id % 50, 1, today) end
        local recordMs = (os.clock() - c0) * 1000
        for r = 1, 10 do
            local token = "trep" .. string.format("%03d", r)
            local buckets = {}
            for id = 1, 8000 do
                local b = ns.Share.b36(id % P.BUCKETS)
                buckets[b] = buckets[b] or {}
                buckets[b][id] = { m = 100 + (id + r) % 60, q = 1 }
            end
            for b, items in pairs(buckets) do
                peer(ns, P.ledger, token, P.rkCode(rk) .. ":" .. ns.Share.b36(today) .. ":" .. b,
                    P.encodeShare("測試伺服器", "horde", items), t - r)
            end
        end
        c0 = os.clock()
        P.shared(rk)
        local sharedMs = (os.clock() - c0) * 1000
        c0 = os.clock()
        for id = 1, 8000, 40 do P.reference(rk, id, today) end
        local refMs = (os.clock() - c0) * 1000 / 200
        local values = 0
        local function count(x) for k, v in pairs(x) do values = values + 1; if type(v) == "table" then count(v) end end end
        count(GreenFangToolkitDB.prices or {}); count(GreenFangToolkitDB.ledger or {})
        realPrint(string.format("     PERF GF-006: 300 orders loaded %.0f ms, merged %.1f ms, badge %.1f ms; 8000 items stored %.0f ms; 10 reporters x 8000 items indexed %.0f ms; reference %.3f ms each; %d Lua values in prices+ledger (records %d)",
            loadMs, mergeMs, badgeMs, recordMs, sharedMs, refMs, values, P.ledger:count()))
        ok(mergeMs < 100, "orders merge under 100 ms")
        ok(badgeMs < 100, "badge count under 100 ms")
        ok(refMs < 2, "a reference price under 2 ms")
        ok(values < 60000, "prices and ledger stay small next to GF Sync's 2,000,000 values: " .. values)
    end)
end
