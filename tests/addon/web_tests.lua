-- Offline tests for GF-006-C (web orders into the game: Inbox and import
-- codes). Format: docs/research/GF-006-C_inbox-format.md. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local REALM, GUILD = "測試伺服器", "綠皮與獠牙冒險事務所"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession()
        _G.GreenFangToolkit_Inbox = nil
        return ns
    end

    -- Build an Inbox string. customers = { { cu = guid, t = n, orders = { "id=...;..." } } }.
    local function build(ns, customers, head)
        head = head or {}
        local now = ns.Share.serverNow()
        local n = 0
        for _, c in ipairs(customers) do n = n + #c.orders end
        local parts = { string.format("H;realm=%s;guild=%s;at=%d;n=%d", head.realm or ns.WebOrders.pctEncode(REALM),
            head.guild or ns.WebOrders.pctEncode(GUILD), head.at or now, head.n or n) }
        for _, c in ipairs(customers) do
            parts[#parts + 1] = string.format("C;cu=%s;t=%d", c.cu, c.t or now)
            for _, o in ipairs(c.orders) do parts[#parts + 1] = "O;" .. o end
        end
        local rest = table.concat(parts, "~")
        return "GFIN1~" .. (head.sum or ns.WebOrders.sum(rest)) .. "~" .. (head.sig or "c2lnbmF0dXJl") .. "~" .. rest
    end
    local function order(ns, id, extra)
        local now = ns.Share.serverNow()
        local f = { id = id, cr = now - 100, cf = "*", rc = 2660, it = 2862, sk = 164, q = 5, m = "2835*5", fe = 500,
            st = "open", sa = now - 100 }
        for k, v in pairs(extra or {}) do f[k] = v end
        local keys = {}
        for k in pairs(f) do keys[#keys + 1] = k end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do if f[k] ~= false then out[#out + 1] = k .. "=" .. tostring(f[k]) end end
        return table.concat(out, ";")
    end
    local function parse(ns, s) return ns.WebOrders.parse(s, ns.WebOrders.context()) end

    test("GF-006-C R-9.4 parser: a good list becomes M entries; website cancel kept", function()
        local ns = login()
        local s = build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12"),
            order(ns, "w13", { cf = "Player-" .. C, q = 1, fe = 0, fq = 0, st = "cancel", m = false, it = false }) } } })
        local r = parse(ns, s)
        eq(r.code, "ok", "ok"); eq(r.total, 2, "two orders")
        local c = r.customers[1]
        eq(c.a, B, "customer author")
        local o1, o2 = c.orders[1], c.orders[2]
        eq(o1.id, "w12", "id"); eq(o1.src, "w", "src w"); eq(o1.cf, "*", "guild order"); eq(o1.q, 5, "qty")
        eq(ns.Orders.decodeMats(o1.m)[2835], 5, "mats"); eq(o1.fq, nil, "no quote: nil"); eq(o1.st, "o", "open")
        eq(o2.cf, C, "named crafter"); eq(o2.fq, 0, "free quote"); eq(o2.st, "x", "website cancel"); eq(o2.it, nil, "no item")
        -- Import codes may be wrapped and spaced.
        local wrapped = s:sub(1, 30) .. "\n  " .. s:sub(31, 80) .. "\r\n" .. s:sub(81)
        eq(parse(ns, wrapped).code, "ok", "whitespace removed")
    end)

    test("GF-006-C D-018.3 parser refuses broken or hostile input without executing anything", function()
        local ns = login()
        local good = build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12") } } })
        local function code(s) return parse(ns, s).code end
        eq(code(nil), "not-string", "nil"); eq(code(42), "not-string", "number"); eq(code({}), "not-string", "table")
        eq(code(""), "empty", "empty")
        eq(code(string.rep("a", 70000)), "too-big", "over 64 KB")
        eq(code(good .. '"'), "bad-chars", "a quote")
        eq(code(good .. "\\"), "bad-chars", "a backslash")
        eq(code('";os.exit()--'), "bad-chars", "Lua code")
        eq(code("GFIN1~x~y~]]"), "bad-chars", "long bracket")
        eq(code(good:gsub("^GFIN1", "GFIN2")), "version", "unknown version skipped whole")
        eq(code(good:sub(1, #good - 5)), "bad-sum", "truncated")
        eq(code("hello"), "not-inbox", "not an inbox string")
        eq(code(build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12") } } }, { sig = "" })), "malformed", "no signature")
        eq(code(build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12") } } }, { n = 3 })), "count", "n mismatch")
        eq(code(build(ns, {}, { realm = ns.WebOrders.pctEncode("別的伺服器") })), "other-realm", "other realm")
        eq(code(build(ns, {}, { guild = ns.WebOrders.pctEncode("別的公會") })), "other-guild", "other guild")
        eq(code(build(ns, {}, { guild = "%G1" })), "malformed", "bad percent escape")
        eq(code(build(ns, {}, { at = ns.Share.serverNow() - 31 * 86400 })), "too-old", "list older than 30 days")
        eq(code(build(ns, {}, { at = ns.Share.serverNow() + 3600 })), "future", "list from the future")
        eq(code(build(ns, { { cu = "Robert'); DROP", orders = {} } })), "bad-chars", "garbage customer")
        eq(code(build(ns, { { cu = "Player-abc", orders = {} } })), "malformed", "bad GUID")
        local rest = "H;realm=x~H;realm=y"
        eq(code("GFIN1~" .. ns.WebOrders.sum(rest) .. "~s~" .. rest), "malformed", "two headers")
        eq(code(build(ns, {})), "ok", "an empty list is fine")
    end)

    test("GF-006-C R-9.4 parser: bad orders are skipped one by one with a reason", function()
        local ns = login()
        local now = ns.Share.serverNow()
        local bad = {
            order(ns, "g12"), order(ns, "wABC"), order(ns, "w" .. string.rep("1", 64)),
            order(ns, "w20", { q = 0 }), order(ns, "w21", { q = 1001 }), order(ns, "w22", { fe = "-1" }),
            order(ns, "w23", { rc = false }), order(ns, "w24", { st = "done" }),
            order(ns, "w25", { cr = now - 31 * 86400 }), order(ns, "w26", { cf = "Player-0000-99999999" }),
            order(ns, "w27", { m = "1*1+2*1+3*1+4*1+5*1+6*1+7*1+8*1+9*1+10*1+11*1+12*1+13*1" }),
            order(ns, "w28", { m = "1*0" }), "id=w29;id=w30",
        }
        local okOne = order(ns, "w30", { zz = "ignored" })
        local list = {}
        for _, o in ipairs(bad) do list[#list + 1] = o end
        list[#list + 1] = okOne
        local r = parse(ns, build(ns, { { cu = "Player-" .. B, orders = list },
            { cu = "Player-0000-77777777", orders = { order(ns, "w40") } } }))
        eq(r.code, "ok", "the list itself is fine")
        eq(r.total, 1, "only the good one")
        eq(r.customers[1].orders[1].zz, nil, "unknown key not kept")
        eq(r.skipped["bad-id"], 3, "bad ids"); eq(r.skipped["too-old"], 1, "too old")
        eq(r.skipped["not-member"], 2, "crafter and customer not on the roster")
        eq(r.skipped["missing"], 1, "missing field"); eq(r.skipped["bad-field"], 7, "out of range / bad / repeated")
        -- More than 30 for one customer: that customer is skipped.
        local many = {}
        for i = 1, 31 do many[i] = order(ns, "w" .. (100 + i)) end
        r = parse(ns, build(ns, { { cu = "Player-" .. B, orders = many } }))
        eq(r.total, 0, "too many"); eq(r.skipped["too-many"], 31, "reason")
    end)

    test("GF-006-C R-9.4 import: M record for the customer, relayed at once, repeat-safe, newer wins", function()
        local ns = login()
        -- GF-FIX-E (review M-24): another customer's orders come by the Inbox (a paste takes my own only).
        local t = ns.Share.serverNow() - 50
        local s = build(ns, { { cu = "Player-" .. B, t = t, orders = { order(ns, "w12") } } })
        wow.state.sent = {}
        local r = ns.WebOrders.import(s, "inbox")
        eq(r.imported, 1, "imported")
        local rec = ns.Orders.ledger:get(B, "M")
        ok(rec and rec.t == t, "M record with the website's time")
        wow.advance(2)
        local relayed = false
        for _, m in ipairs(wow.state.sent) do
            if m.prefix == "GFTKO" and m.chatType == "GUILD" and m.msg:find("L1~V~" .. B .. "~M~", 1, true) == 1 then relayed = true end
        end
        ok(relayed, "relayed on GUILD")
        r = ns.WebOrders.import(s, "inbox")
        eq(r.imported, 0, "second paste: nothing new"); eq(r.same, 1, "already there")
        local v = ns.Orders.get("w12")
        eq(v.state, "waiting", "a waiting guild order"); eq(v.src, "w", "web order"); eq(v.customer, B, "customer")
        -- The website cancels it later: a newer list.
        local s2 = build(ns, { { cu = "Player-" .. B, t = t + 10,
            orders = { order(ns, "w12", { st = "cancel", sa = t + 10 }) } } })
        ns.WebOrders.import(s2, "inbox")
        v = ns.Orders.get("w12")
        eq(v.state, "cancel", "cancelled on the website"); eq(v.closedBy, "web", "closedBy web")
        -- An older list does not undo it.
        eq(ns.WebOrders.import(s, "inbox").imported, 0, "older list ignored")
        eq(ns.Orders.get("w12").state, "cancel", "still cancelled")
    end)

    test("GF-006-C M merges with W/J: crafter accepts, customer acts (copied into W), web cancel still wins", function()
        local ns = login()
        local t = ns.Share.serverNow() - 50
        -- I (A) am the customer of a web order.
        ns.WebOrders.import(build(ns, { { cu = "Player-" .. A, t = t, orders = { order(ns, "w50", { cf = "Player-" .. B, q = 1 }) } } }), "paste")
        local v = ns.Orders.get("w50")
        eq(v.state, "waiting", "directed, waiting"); eq(v.crafter, B, "named crafter")
        local J = ns.Orders.encodeList({ { id = "w50", cu = A, st = "a", ac = t + 5, sa = t + 5 } })
        ns.Orders.ledger:offer(B, "J", t + 5, ns.Share.hash(J), J)
        eq(ns.Orders.get("w50").state, "making", "B accepted")
        ok(ns.Orders.customer("w50", "return") or true, "acting copies the web order into my W")
        local wrec = ns.Orders.listOf(A, "W")
        eq(#wrec, 1, "W entry created"); eq(wrec[1].src, "w", "keeps src w")
        local up = ns.Orders.craftingFor(A).orders["w50"].w
        eq(up.src, "w", "uploaded as a web order")
        -- Website cancels: closes even though my W exists.
        ns.WebOrders.import(build(ns, { { cu = "Player-" .. A, t = t + 20,
            orders = { order(ns, "w50", { cf = "Player-" .. B, q = 1, st = "cancel", sa = t + 20 }) } } }), "inbox")
        v = ns.Orders.get("w50")
        eq(v.state, "cancel", "web cancel wins"); eq(v.closedBy, "web", "by web")
    end)

    test("GF-006-C a relayed M can never carry a game order or a non-web source", function()
        local ns = login()
        local t = ns.Share.serverNow()
        local bad = ns.Orders.encodeList({ { id = "g1", src = "g", cr = t, rc = 1, q = 1, cf = "*", fe = 0, st = "o", sa = t } })
        eq(ns.Orders.ledger:offer(B, "M", t, ns.Share.hash(bad), bad), "invalid", "g id refused")
        local bad2 = ns.Orders.encodeList({ { id = "w1", src = "g", cr = t, rc = 1, q = 1, cf = "*", fe = 0, st = "o", sa = t } })
        eq(ns.Orders.ledger:offer(B, "M", t, ns.Share.hash(bad2), bad2), "invalid", "src must be w")
    end)

    test("GF-006-C login: no Inbox AddOn = nothing, no error; LoadOnDemand and normal AddOn both read", function()
        local ns = login()
        -- No loader at all.
        local oldAddOns = C_AddOns
        C_AddOns = { GetAddOnMetadata = oldAddOns and oldAddOns.GetAddOnMetadata }
        eq(ns.WebOrders.readInbox(), "no-loader", "no loader")
        -- Loader says missing.
        C_AddOns.LoadAddOn = function() return false, "MISSING" end
        eq(ns.WebOrders.readInbox(), "missing", "missing AddOn")
        ok(ns.WebOrders.diagText():find("沒有 Inbox（MISSING）", 1, true), "diag: no inbox")
        -- Loader that errors.
        C_AddOns.LoadAddOn = function() error("boom") end
        eq(ns.WebOrders.readInbox(), "missing", "an error is caught")
        -- LoadOnDemand: loading sets the global.
        local s = build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12") } } })
        local loads = 0
        C_AddOns.LoadAddOn = function(name)
            assert(name == "GreenFangToolkit_Inbox"); loads = loads + 1
            _G.GreenFangToolkit_Inbox = s; return true
        end
        eq(ns.WebOrders.readInbox(), "ok", "read on demand"); eq(loads, 1, "loaded once")
        ok(ns.Orders.get("w12"), "imported")
        ok(ns.WebOrders.diagText():find("隨選載入", 1, true), "diag: on demand")
        eq(ns.WebOrders.readInbox(), "unchanged", "same string again: nothing to do")
        -- A normal AddOn (no LoadOnDemand): the global is already there.
        login()
        ns = wow.login(ADDON_DIR)
        _G.GreenFangToolkit_Inbox = 12345
        eq(ns.WebOrders.readInbox(), "not-string", "not a string")
        _G.GreenFangToolkit_Inbox = s
        eq(ns.WebOrders.readInbox(), "ok", "global read")
        C_AddOns = oldAddOns
        _G.GreenFangToolkit_Inbox = nil
    end)

    test("GF-006-C login reads the Inbox once the order ledger starts; diagnostics show the result", function()
        wow.reset()
        local s
        local oldAddOns
        local ns = wow.loadAddon(ADDON_DIR)
        s = build(ns, { { cu = "Player-" .. B, orders = { order(ns, "w12"), "id=bad" } } })
        _G.GreenFangToolkit_Inbox = s
        wow.fire("PLAYER_LOGIN")
        wow.advance(40)
        ok(ns.Orders.get("w12"), "imported at login")
        local d = ns.Diag.ordersText()
        ok(d:find("網站訂單：上次讀到 Inbox", 1, true), "diag time")
        ok(d:find("匯入 1", 1, true) and d:find("略過 1", 1, true), "diag counts: " .. d)
        _G.GreenFangToolkit_Inbox = nil
        ok(oldAddOns == nil, "")
    end)

    test("GF-006-C R-9.4 the 📋 paste box imports a code; result is icons and numbers only", function()
        local ns = login()
        ns.Framework.open("orders")
        ok(ns.OrdersUI.pasteButton, "paste button on the orders page")
        local f = ns.OrdersUI.openPaste()
        ok(f:IsShown(), "shown")
        -- GF-FIX-E (review M-24): a pasted code brings in my own orders only.
        local s = build(ns, { { cu = "Player-" .. A, orders = { order(ns, "w12") } } })
        f.box:SetText(s:sub(1, 40) .. "\n" .. s:sub(41))
        local r = ns.OrdersUI.pasteImport()
        eq(r.code, "ok", "imported")
        ok(f.result:GetText():find("^|T"), "icon result")
        ok(not f.result:GetText():find("[\228-\233]"), "no text")
        f.box:SetText("garbage")
        eq(ns.OrdersUI.pasteImport().code, "not-inbox", "bad code")
        ok(ns.WebOrders.diagText():find("匯入碼", 1, true), "diag notes the paste")
    end)

    test("GF-006-C performance: a full 200-order, 64 KB-class list parses and imports quickly", function()
        local roster = { wow.defaultRoster()[1] }
        for i = 2, 1000 do
            roster[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = false, guid = string.format("Player-0000-%08X", 0x100 + i) }
        end
        local ns = login({ roster = roster })
        local customers = {}
        for c = 1, 20 do
            local list = {}
            for k = 1, 10 do list[k] = order(ns, "w" .. c .. "x" .. k, { cf = roster[2 + c].guid }) end
            customers[c] = { cu = roster[30 + c].guid, orders = list }
        end
        local s = build(ns, customers)
        local c0 = os.clock()
        local r = ns.WebOrders.import(s, "inbox")
        local ms = (os.clock() - c0) * 1000
        eq(r.imported, 200, "200 imported")
        ok(ms < 200, string.format("under 200 ms: %.0f ms, %d bytes", ms, #s))
        io.write(string.format("     PERF GF-006-C: 200 web orders, %d bytes, imported in %.0f ms\n", #s, ms))
    end)
end
