-- GF-014-05: the (c) reminders of 委託 / 冒險 as 業務通知 (Notify.lua), and the
-- confirm box after learning the recipe of my own 圖紙 徵求 (RecipeLink.lua).
--   order_guild  a guild order I can make (default OFF)
--   order_remind 逾期 (stale) / 工匠 14 天可結案 (close)
--   adv_update   隊長改了內容 (edited), 過期 / 未成行 (成行: nothing)
--   adv_remind   開打前 60 / 15 分鐘
--   adv_leader   待定案 (due), 成員遞補 (refill), 候補的職工單過期 (worker-gone); 重開: nothing
-- Time reminders come from the existing once-a-minute maintenance (Init.lua →
-- Orders.maintain / Adventure.maintain), never a timer of their own.
-- Offline only; made-up names only. Run alone: run_lupa.py --only gf01405

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local H, DAY = 3600, 86400
    local RECIPE, ITEM, SKILL = 2660, 2862, 164

    local function login(saved)
        wow.reset()
        local ns = wow.login(ADDON_DIR, saved)
        ns.Orders.resetSession(); ns.Adventure.resetSession(); ns.Notify.resetSession()
        return ns
    end
    local function settle() wow.advance(3) end
    -- Time passes without running every timer in between (days in one step).
    local function jump(sec) wow.state.now = wow.state.now + sec end
    local function of(ns, module)
        local out = {}
        for _, e in ipairs(ns.Notify.list()) do if e.module == module then out[#out + 1] = e end end
        return out
    end
    local function offer(ns, ledger, a, g, v, t)
        t = t or ns.Share.serverNow()
        return ledger:offer(a, g, t, ns.Share.hash(v), v)
    end
    local function orders(ns, a, list, t) return offer(ns, ns.Orders.ledger, a, "W", ns.Orders.encodeList(list), t) end
    local function w(ns, id, extra)
        local t = ns.Share.serverNow()
        local e = { id = id, src = "g", ver = 1, cr = t, rc = RECIPE, it = ITEM, sk = SKILL, q = 1, cf = A, fe = 0, st = "o", sa = t }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local function advOffer(ns, a, g, list, t)
        local r = offer(ns, ns.Adventure.ledger, a, g, ns.Adventure.encodeList(list), t)
        ns.Adventure.refresh()
        return r
    end
    -- I know RECIPE (my own 鍛造 list), so guild orders of it are ones I can make.
    local function iKnow(ns, ids)
        return ns.Share.ownRecord("R" .. SKILL, ns.Share.encodeValue("R" .. SKILL, ids or { RECIPE }))
    end
    -- C's ticket, auto mode, one slot (final by itself) at start; seats t / h / d.
    local function cTicket(ns, id, start, over)
        local t = ns.Share.serverNow()
        local e = { id = id, src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = ns.Adventure.encodeTimes({ { id = 1, s = start, d = 2 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t }
        for k, v in pairs(over or {}) do e[k] = v end
        return e
    end
    local function has(list, text)
        for _, e in ipairs(list) do if e.text:find(text, 1, true) then return e end end
        return nil
    end

    ---------------------------------------------------------------------------
    -- 委託
    ---------------------------------------------------------------------------

    test("gf01405 order_guild: default off; switched on, a guild order I can make notifies once", function()
        local ns = login()
        local N = ns.Notify
        wow.advance(130) -- sharing started (it rewrites my own lists first)
        iKnow(ns)
        eq(N.enabled("order_guild"), false, "starts switched off")
        local g1 = w(ns, "gB.1", { cf = "*" })
        orders(ns, B, { g1 })
        settle()
        eq(#of(ns, "order_guild"), 0, "off: nothing")
        N.setEnabled("order_guild", true)
        eq(N.enabled("order_guild"), true, "switched on")
        eq(ns.Framework.moduleSettings("notify").off.order_guild, false, "kept as off.order_guild = false")
        settle(); ns.Orders.notifyScan()
        eq(#of(ns, "order_guild"), 0, "the one seen while off does not come back")
        wow.advance(5)
        local t = ns.Share.serverNow()
        orders(ns, B, { g1, w(ns, "gB.2", { cf = "*" }),
            w(ns, "gB.3", { cf = "*", rc = 9999 }) }, t)
        settle()
        local list = of(ns, "order_guild")
        eq(#list, 1, "one notice: gB.2 (gB.3 is a recipe I do not know)")
        ok(list[1].text:find("公會委託", 1, true) and list[1].text:find("測試乙", 1, true), "text: " .. list[1].text)
        eq(list[1].target.page, "orders", "page"); eq(list[1].target.id, "gB.2", "that order")
        eq(#of(ns, "order_new"), 0, "not an order to me by name")
        eq(ns.Orders.notifyScan(), 0, "again: nothing")
        -- My own guild order: never.
        ok(ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" }), "my own guild order")
        settle()
        eq(#of(ns, "order_guild"), 1, "my own order: nothing")
        -- Off again: the default (off) is kept as nil.
        N.setEnabled("order_guild", false)
        eq(ns.Framework.moduleSettings("notify").off.order_guild, true, "off")
    end)

    test("gf01405 order_remind: stale through the once-a-minute maintenance, once per period", function()
        local ns = login()
        local O = ns.Orders
        wow.advance(120) -- the maintenance loop runs (Init.lua, every 60 s)
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" })
        ok(id, "my guild order")
        settle()
        eq(#of(ns, "order_remind"), 0, "new: nothing")
        local scans = O.notifyStats.scans
        jump(2 * DAY + 10)
        wow.advance(61) -- only the existing loop: no call from the test
        ok(O.notifyStats.scans > scans, "the maintenance asked for the scan")
        local list = of(ns, "order_remind")
        eq(#list, 1, "one reminder")
        ok(list[1].text:find("沒有人接單", 1, true) and list[1].text:find("2 天", 1, true), "text: " .. list[1].text)
        eq(list[1].target.id, id, "that order")
        wow.advance(120)
        eq(of(ns, "order_remind")[1].count, 1, "the same period: not again")
        jump(2 * DAY)
        wow.advance(61)
        list = of(ns, "order_remind")
        eq(#list, 1, "still one notice per order")
        eq(list[1].count, 2, "the next period merges into it")
        ok(list[1].text:find("4 天", 1, true), "newest text: " .. list[1].text)
        -- Switched off: the next period says nothing.
        ns.Notify.setEnabled("order_remind", false)
        jump(2 * DAY); wow.advance(61)
        ns.Notify.setEnabled("order_remind", true)
        eq(of(ns, "order_remind")[1].count, 2, "off: not counted, not later either")
    end)

    test("gf01405 order_remind events: making stale for both sides, the crafter's 14-day close; others not", function()
        local ns = login()
        local O = ns.Orders
        local t = ns.Share.serverNow()
        local guid = ns.Data.player().guid
        local function codes(v)
            local out = {}
            for _, ev in ipairs(O.notifyEvents(v, A, guid, t)) do if ev.module == "order_remind" then out[#out + 1] = ev.code end end
            table.sort(out)
            return table.concat(out, ",")
        end
        eq(codes({ id = "gB.1", customer = B, crafter = A, state = "making", since = t - 4 * DAY }), "stale-making", "crafter: making 4 days")
        eq(codes({ id = "gA.1", customer = A, crafter = B, state = "making", since = t - 4 * DAY }), "stale-making", "customer: making 4 days")
        eq(codes({ id = "gB.2", customer = B, crafter = A, state = "making", since = t - 4 * DAY, returned = true }), "", "returned: its own notice")
        eq(codes({ id = "gB.3", customer = B, crafter = A, state = "checking", since = t - 15 * DAY }), "close", "crafter: 14 days, may close")
        eq(codes({ id = "gB.4", customer = B, crafter = A, state = "checking", since = t - 13 * DAY }), "", "13 days: not yet")
        eq(codes({ id = "gB.5", customer = B, crafter = A, state = "deal", since = t - 30 * DAY }), "", "closed: nothing")
        eq(codes({ id = "gC.1", customer = C, crafter = B, state = "making", since = t - 9 * DAY }), "", "not mine")
        local v = { id = "gB.3", customer = B, crafter = A, state = "checking", since = t - 15 * DAY, item = ITEM }
        local ev
        for _, e in ipairs(O.notifyEvents(v, A, guid, t)) do if e.code == "close" then ev = e end end
        ok(O.notifyText(v, ev):find("可以結案", 1, true), "close text: " .. O.notifyText(v, ev))
        eq(ev.at, v.since + O.CRAFTER_CLOSE, "its time: when the 14 days were up")
    end)

    test("gf01405 order_remind waits in combat, comes after combat", function()
        local ns = login()
        wow.advance(120)
        ok(ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" }), "my guild order")
        settle()
        wow.enterCombat()
        jump(2 * DAY + 10)
        wow.advance(61)
        eq(#of(ns, "order_remind"), 0, "in combat: nothing")
        ok(ns.Orders.notifyStats.waited >= 1, "the scan waited")
        wow.leaveCombat(); wow.advance(1)
        eq(#of(ns, "order_remind"), 1, "after combat: the reminder")
    end)

    ---------------------------------------------------------------------------
    -- 冒險：參加者
    ---------------------------------------------------------------------------

    test("gf01405 adv_update: the leader edits; 過期 and 未成行 notify, 成行 does not", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local c1 = cTicket(ns, "accc.1", t + 5 * H)
        local c2 = cTicket(ns, "accc.2", t + 5 * H)
        local c3 = cTicket(ns, "accc.3", t + 5 * H)
        advOffer(ns, C, "T", { c1, c2, c3 }, t)
        settle()
        for _, id in ipairs({ "accc.1", "accc.2", "accc.3" }) do ok(Adv.worker(id, "apply", { 1 }), "I apply " .. id) end
        settle()
        eq(#of(ns, "adv_update"), 0, "my apply: nothing")
        wow.advance(30)
        local t2 = ns.Share.serverNow()
        c1.ed = t2
        advOffer(ns, C, "T", { c1, c2, c3 }, t2)
        settle()
        local e = of(ns, "adv_update")[1]
        ok(e and e.text:find("改了冒險單", 1, true), "edited: " .. tostring(e and e.text))
        eq(e.target.id, "accc.1", "that ticket")
        ok(ns.Notify.open(e) ~= "none", "the click opens it")
        -- c1 expires (過期), c2 formed but not done (未成行), c3 done (成行).
        wow.advance(30)
        local t3 = ns.Share.serverNow()
        c1.st, c1.sa, c1.rs = "x", t3, "time"
        c2.st, c2.sa, c2.rs = "x", t3, "unfinished"
        c3.st, c3.sa = "c", t3
        advOffer(ns, C, "T", { c1, c2, c3 }, t3)
        settle()
        local list = of(ns, "adv_update")
        ok(has(list, "已過期"), "過期 notified")
        ok(has(list, "未成行"), "未成行 notified")
        for _, x in ipairs(list) do ok(x.target.id ~= "accc.3", "成行: no notice") end
        eq(#list, 2, "two tickets: c1 (merged), c2")
        eq(#of(ns, "adv_final"), 0, "not a 取消")
        eq(Adv.notifyScan(), 0, "again: nothing")
    end)

    test("gf01405 adv_remind: 60 and 15 minutes before, through the maintenance; once each", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local start = t + 3 * H
        local c = cTicket(ns, "accc.5", start)
        advOffer(ns, C, "T", { c }, t)
        settle()
        ok(Adv.worker(c.id, "apply", { 1 }), "I apply (auto: in)")
        settle()
        Adv.maintain(); settle()
        eq(#of(ns, "adv_remind"), 0, "3 hours before: nothing")
        jump(start - 3590 - ns.Share.serverNow())
        Adv.maintain(); settle()
        local e = of(ns, "adv_remind")[1]
        ok(e and e.text:find("60 分鐘", 1, true), "60: " .. tostring(e and e.text))
        Adv.maintain(); settle()
        eq(of(ns, "adv_remind")[1].count, 1, "the next minute: not again")
        jump(start - 890 - ns.Share.serverNow())
        Adv.maintain(); settle()
        e = of(ns, "adv_remind")[1]
        ok(e.text:find("15 分鐘", 1, true), "15: " .. e.text)
        eq(e.count, 2, "one notice per ticket, merged")
        -- In combat: waits.
        local d = cTicket(ns, "accc.6", ns.Share.serverNow() + 2 * H)
        advOffer(ns, C, "T", { c, d }, ns.Share.serverNow())
        ok(Adv.worker(d.id, "apply", { 1 }), "I apply to the second")
        settle()
        wow.enterCombat()
        jump(H + 20)
        Adv.maintain(); settle()
        local before = #of(ns, "adv_remind")
        wow.leaveCombat(); wow.advance(1)
        eq(#of(ns, "adv_remind"), before + 1, "after combat: the second ticket's reminder")
    end)

    ---------------------------------------------------------------------------
    -- 冒險：隊長
    ---------------------------------------------------------------------------

    test("gf01405 adv_leader: 待定案 by time, 成員遞補; 重開 says nothing", function()
        local ns = login()
        local Adv, N = ns.Adventure, ns.Notify
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 0 }, leaderRole = "d",
            slots = { { s = t + 2 * H, d = 2 * H }, { s = t + 26 * H, d = 2 * H } } })
        ok(id, "my ticket, two slots")
        settle()
        Adv.maintain(); settle()
        eq(#of(ns, "adv_leader"), 0, "2 hours before: nothing")
        jump(H + 60)
        Adv.maintain(); settle()
        local e = of(ns, "adv_leader")[1]
        ok(e and e.text:find("還沒定案", 1, true), "due: " .. tostring(e and e.text))
        eq(e.target.id, id, "that ticket")
        Adv.maintain(); settle()
        eq(of(ns, "adv_leader")[1].count, 1, "not again")
        -- B takes the tank seat, C waits; B withdraws: C moves up (遞補).
        local t1 = ns.Share.serverNow()
        advOffer(ns, B, "A", { { id = id, ac = "ap", at = t1, ap = t1, ak = "ap", ro = "t", rb = "" } }, t1)
        advOffer(ns, C, "A", { { id = id, ac = "ap", at = t1 + 1, ap = t1 + 1, ak = "ap", ro = "t", rb = "" } }, t1 + 1)
        settle()
        wow.advance(20)
        local t2 = ns.Share.serverNow()
        advOffer(ns, B, "A", { { id = id, ac = "wd", at = t2, ap = t1, ak = "ap", ro = "t", rb = "" } }, t2)
        settle()
        e = of(ns, "adv_leader")[1]
        ok(e.text:find("遞補進了", 1, true) and e.text:find("測試丙", 1, true), "refill: " .. e.text)
        eq(e.count, 2, "merged per ticket")
        -- 重開 (the reopen prompt) is not announced.
        local count = e.count
        Adv.local_().reopen[id] = true
        local v = Adv.get(id)
        for _, ev in ipairs(Adv.notifyEvents(v, A, nil, ns.Share.serverNow())) do
            ok(not tostring(ev.key):find("reopen", 1, true), "no reopen event: " .. ev.key)
        end
        Adv.notifyScan()
        eq(of(ns, "adv_leader")[1].count, count, "reopen: nothing")
        -- Switch off: the next leader event says nothing.
        N.setEnabled("adv_leader", false)
        eq(N.push({ module = "adv_leader", key = "x", text = "x" }), "off", "off")
    end)

    test("gf01405 adv_leader worker-gone: a waiting signup left because its worker ticket expired", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local v = { id = "aaaa.9", leader = A, closed = false, dungeon = "smg", quests = {}, members = {}, waitlist = {}, pending = {}, invited = {},
            kicked = {}, slots = {}, workerGone = { { a = C, at = t - 60 } } }
        local found
        for _, ev in ipairs(Adv.notifyEvents(v, A, nil, t)) do if ev.module == "adv_leader" then found = ev end end
        ok(found and found.text:find("職工單過期", 1, true) and found.text:find("測試丙", 1, true), "text: " .. tostring(found and found.text))
        eq(found.key, "aaaa.9|gone|" .. C .. "|" .. (t - 60), "one event per signup and time")
        v.workerGone[1].at = t - 2 * DAY
        for _, ev in ipairs(Adv.notifyEvents(v, A, nil, t)) do ok(ev.module ~= "adv_leader", "older than a day: nothing") end
        -- Not the leader: no leader events.
        v.leader, v.workerGone[1].at = B, t - 60
        for _, ev in ipairs(Adv.notifyEvents(v, A, nil, t)) do ok(ev.module ~= "adv_leader", "a member: nothing") end
    end)

    ---------------------------------------------------------------------------
    -- Settings and cost
    ---------------------------------------------------------------------------

    test("gf01405 settings: 19 switches in two columns, every one inside the list, labels inside their column", function()
        local ns = login()
        local UI = ns.NotifyUI
        local parent = CreateFrame("Frame", nil, UIParent)
        local boxes = UI.buildSettings(parent, 16, UI.TOP)
        eq(#boxes, 20, "20 rows (GF-012-D: 黑箱申領)")
        local keys, cols = {}, { [0] = 0, [1] = 0 }
        for i, c in ipairs(boxes) do
            keys[c.key] = c
            cols[c.col] = cols[c.col] + 1
            ok(-UI.TOP + c.line * c.step + 28 <= UI.ROWS * UI.ROW_H + 76 - 8, "inside: " .. c.key)
            ok(16 + c.col * UI.SETTING_COL_W + (c.sub and 28 or 0) + 34 + ns.labelWidth(c.text:GetText()) <= 16 + (c.col + 1) * UI.SETTING_COL_W,
                "label inside its column: " .. c.text:GetText())
            if c.sub then ok(boxes[i - 1].col == c.col, "a sub row stays with its module: " .. c.key) end
        end
        ok(cols[0] > 0 and cols[1] > 0, "two columns")
        ok(boxes[1].step >= UI.SETTING_MIN, "step " .. boxes[1].step)
        for _, k in ipairs({ "order_guild", "order_remind", "adv_update", "adv_remind", "adv_leader" }) do
            ok(keys[k], "a switch: " .. k)
            ok(UI.MODULE_SHORT[k], "a tag: " .. k)
        end
        eq(keys.order_guild.gfOn, false, "公會委託 unchecked by default")
        eq(keys.order_remind.gfOn, true, "the others checked")
    end)

    -- 25 more members, n / 25 orders each (half guild orders of a recipe I
    -- know, half to me) and n / 25 tickets each (I signed up for every third).
    local function bigGuild(n)
        local roster = wow.defaultRoster()
        local authors = {}
        for k = 1, 25 do
            local a = string.format("0000-%08d", 1000 + k)
            authors[k] = a
            roster[#roster + 1] = { name = "測試員" .. k .. "-測試伺服器", rank = "會員", level = 40, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = k % 2 == 0, guid = "Player-" .. a }
        end
        wow.reset({ roster = roster })
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession(); ns.Notify.resetSession()
        ns.Notify.setEnabled("order_guild", true)
        iKnow(ns)
        local t = ns.Share.serverNow()
        local per = n / 25
        local mine = {}
        for k, a in ipairs(authors) do
            local ws, ts = {}, {}
            for j = 1, per do
                ws[#ws + 1] = w(ns, "g" .. k .. "." .. j, { cf = (j % 2 == 0) and A or "*" })
                local id = "a" .. k .. "." .. j
                ts[#ts + 1] = { id = id, src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
                    ts = ns.Adventure.encodeTimes({ { id = 1, s = t + 2 * H, d = 2 * H } }),
                    rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t }
                if j % 3 == 0 then mine[#mine + 1] = { id = id, ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "d", rb = "" } end
            end
            orders(ns, a, ws, t)
            advOffer(ns, a, "T", ts, t)
        end
        advOffer(ns, A, "A", mine, t + 1)
        settle()
        return ns
    end
    local function perScan(fn, rounds)
        fn()
        local clock = os.clock()
        local pushed = 0
        for _ = 1, rounds do pushed = pushed + fn() end
        return (os.clock() - clock) * 1000 / rounds, pushed
    end

    test("gf01405 one scan with nothing new, the new kinds on: 100 and 300 records under 5 ms (printed)", function()
        for _, n in ipairs({ 100, 300 }) do
            local ns = bigGuild(n)
            local guild = #of(ns, "order_guild")
            ok(guild > 0, "guild orders I can make were seen: " .. guild)
            local oMs, oPushed = perScan(ns.Orders.notifyScan, 20)
            local aMs, aPushed = perScan(ns.Adventure.notifyScan, 20)
            eq(oPushed + aPushed, 0, "nothing new: nothing pushed")
            T.realPrint(string.format("     GF-014-05 idle scan, %d records: Orders.notifyScan %.2f ms, Adv.notifyScan %.2f ms", n, oMs, aMs))
            ok(oMs < 5, string.format("Orders.notifyScan at %d: %.2f ms < 5 ms", n, oMs))
            ok(aMs < 5, string.format("Adv.notifyScan at %d: %.2f ms < 5 ms", n, aMs))
        end
    end)

    ---------------------------------------------------------------------------
    -- B. Learned the recipe of my own 圖紙 徵求: the confirm box
    ---------------------------------------------------------------------------

    local PEER_GUID = "Player-0000-0000000B"
    local LEATHER, SOUP, OWN = 7001, 7005, 7100
    local NAMES = { [LEATHER] = "測試皮甲", [SOUP] = "測試魚湯", [OWN] = "自己的皮護腕" }
    local P_LEATHER, P_SOUP = 5001, 5004
    local function catalog()
        return { v = 2, build = "test", locale = "zhTW", n = 2, groups = {
            [9] = P_LEATHER .. "\t1\t0\t圖樣：測試皮甲\n" .. P_SOUP .. "\t5\t0\t食譜：測試魚湯\n" } }
    end
    local function installGame()
        local ITEMS = {
            [P_LEATHER] = { name = "圖樣：測試皮甲", classID = 9, sub = 1 },
            [P_SOUP] = { name = "食譜：測試魚湯", classID = 9, sub = 5 },
        }
        GetItemInfo = function(id)
            local it = ITEMS[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1,
                "配方", "", 20, "", 134939, 0, it.classID, it.sub, 0
        end
        C_Item = {
            GetItemIconByID = function(id) return ITEMS[id] and 134939 or nil end,
            GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name or nil end,
            RequestLoadItemDataByID = function() end,
            IsItemDataCachedByID = function(id) return ITEMS[id] ~= nil end,
            DoesItemExistByID = function() return true end,
        }
        local base = C_Spell and C_Spell.GetSpellName
        C_Spell = C_Spell or {}
        C_Spell.GetSpellName = function(id)
            if NAMES[id] then return NAMES[id] end
            if base then return base(id) end
            return nil
        end
    end
    local function done(fn)
        return function()
            local okRun, err = pcall(fn)
            GetItemInfo, C_Item = nil, nil
            if wow.state and wow.state.combat then wow.leaveCombat() end
            if not okRun then error(err, 0) end
        end
    end
    local function rOffer(ns, a, g, ids, t)
        local v = ns.Share.encodeValue(g, ids)
        return ns.Share.offer(a, g, t or (wow.state.now - 60), ns.Share.hash(v), v, true, a)
    end
    local function setOwn(ns, skill, ids) return ns.Share.ownRecord("R" .. skill, ns.Share.encodeValue("R" .. skill, ids)) end
    local function rLogin()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        installGame()
        ns.SupplyCatalogData = catalog()
        ns.SupplyCatalog.resetSession()
        ns.RecipeLink.resetSession()
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.advance(130)
        local peer = ns.Share.authorOf(PEER_GUID)
        rOffer(ns, peer, "R165", { LEATHER })
        rOffer(ns, peer, "R185", { SOUP })
        setOwn(ns, 165, { OWN })
        setOwn(ns, 185, { OWN })
        return ns
    end
    local function need(ns, itemID)
        return assert(ns.SupplyListings.create({ direction = "need", itemID = itemID, quantity = 1, days = 14, note = "" }))
    end
    local function notices(ns)
        local out = {}
        for _, e in ipairs(ns.Notify.list()) do if e.module == ns.RecipeLink.NOTIFY_MODULE then out[#out + 1] = e end end
        return out
    end
    -- 先留著: the box's second button (the mock's cancelPopup only closes it).
    local function keep()
        local f = wow.popup()
        assert(f, "a box is open")
        local d = StaticPopupDialogs[f.which]
        wow.cancelPopup()
        if d.OnCancel then d.OnCancel(f, f.data) end
        if d.OnHide then d.OnHide(f) end
    end

    test("gf01405 learned: the confirm box names the recipe and the 徵求; 結束徵求 ends it", done(function()
        local ns = rLogin()
        local L, RL = ns.SupplyListings, ns.RecipeLink
        local l = need(ns, P_LEATHER)
        eq(wow.popup(), nil, "no box before")
        setOwn(ns, 165, { OWN, LEATHER })
        local f = wow.popup()
        ok(f and f.which == RL.POPUP, "the box is open")
        ok(f.text:find("測試皮甲", 1, true) and f.text:find("圖樣：測試皮甲 x1", 1, true), "names the recipe and the 徵求: " .. f.text)
        local d = StaticPopupDialogs[RL.POPUP]
        eq(d.button1, "結束徵求", "button 1"); eq(d.button2, "先留著", "button 2")
        eq(#notices(ns), 1, "the notice is there too")
        eq(L.mine().list[l.id].status, "active", "not ended before the click")
        ok(wow.acceptPopup(), "結束徵求")
        eq(L.mine().list[l.id].status, "closed", "ended")
        eq(#notices(ns), 0, "its notice goes")
        wow.advance(1)
        eq(wow.popup(), nil, "no other box")
    end))

    test("gf01405 先留著: the 徵求 stays, never asked again; the notice and its button stay", done(function()
        local ns = rLogin()
        local L, N = ns.SupplyListings, ns.Notify
        local l = need(ns, P_LEATHER)
        setOwn(ns, 165, { OWN, LEATHER })
        keep()
        wow.advance(1)
        eq(wow.popup(), nil, "closed")
        eq(L.mine().list[l.id].status, "active", "kept")
        setOwn(ns, 165, { OWN, LEATHER, 7200 })
        wow.advance(1)
        eq(wow.popup(), nil, "not asked again")
        eq(N.memory("recipe").prompted[l.id], true, "asked: kept in mem.recipe.prompted")
        local list = notices(ns)
        eq(#list, 1, "the notice stays")
        eq(N.action(list[1], "end"), "ended", "its 結束徵求 still works")
        eq(L.mine().list[l.id].status, "closed", "ended later by the notice")
    end))

    test("gf01405 the switch off: no box, no notice", done(function()
        local ns = rLogin()
        ns.Notify.setEnabled("recipe", false)
        need(ns, P_LEATHER)
        setOwn(ns, 165, { OWN, LEATHER })
        wow.advance(1)
        eq(wow.popup(), nil, "no box")
        eq(#notices(ns), 0, "no notice")
    end))

    test("gf01405 combat: no box in combat; after combat it comes", done(function()
        local ns = rLogin()
        local l = need(ns, P_LEATHER)
        wow.enterCombat()
        setOwn(ns, 165, { OWN, LEATHER })
        wow.advance(1)
        eq(wow.popup(), nil, "in combat: no box")
        wow.leaveCombat()
        wow.advance(1)
        local f = wow.popup()
        ok(f and f.text:find("測試皮甲", 1, true), "after combat: the box")
        ok(wow.acceptPopup(), "結束徵求")
        eq(ns.SupplyListings.mine().list[l.id].status, "closed", "ended")
    end))

    test("gf01405 two learned at once: one box at a time, the second after the first", done(function()
        local ns = rLogin()
        local L = ns.SupplyListings
        local a = need(ns, P_LEATHER)
        local b = need(ns, P_SOUP)
        wow.enterCombat()
        setOwn(ns, 165, { OWN, LEATHER })
        setOwn(ns, 185, { OWN, SOUP })
        wow.leaveCombat()
        wow.advance(1)
        local first = wow.popup()
        ok(first, "one box")
        local firstLeather = first.text:find("測試皮甲", 1, true) ~= nil
        ok(ns.RecipeLink.askState.queue[1] ~= nil, "the other waits")
        keep()
        wow.advance(1)
        local second = wow.popup()
        ok(second and second ~= first, "then the second")
        ok(second.text:find(firstLeather and "測試魚湯" or "測試皮甲", 1, true), "the other one: " .. second.text)
        ok(wow.acceptPopup(), "結束徵求 on the second")
        wow.advance(1)
        eq(wow.popup(), nil, "no third box")
        local closed = 0
        for _, l in ipairs({ a, b }) do if L.mine().list[l.id].status == "closed" then closed = closed + 1 end end
        eq(closed, 1, "only the one confirmed ended")
        eq(#notices(ns), 1, "the kept one's notice stays")
    end))
end
