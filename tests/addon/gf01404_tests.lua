-- GF-014-04: what others do in 委託業務 / 冒險業務 / 臨時黑箱 becomes a 業務通知
-- (Notify.lua): order_new, order_status, adv_signup, adv_result, adv_final,
-- bank_keeper. Each: made, once only (a relay, a resend, /reload), never for my
-- own steps, its own switch, held in combat, a click opens that record, and
-- 100 events in a row only merge. Offline only; made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local H = 3600
    local RECIPE, ITEM, SKILL = 2660, 2862, 164

    local function login(saved)
        wow.reset()
        local ns = wow.login(ADDON_DIR, saved)
        ns.Orders.resetSession(); ns.Adventure.resetSession(); ns.Notify.resetSession()
        return ns
    end
    local function settle() wow.advance(3) end
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
    local function jobs(ns, a, list, t) return offer(ns, ns.Orders.ledger, a, "J", ns.Orders.encodeList(list), t) end
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
    local function bTicket(ns, over)
        local t = ns.Share.serverNow()
        local e = { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = ns.Adventure.encodeTimes({ { id = 1, s = t + 2 * H, d = 2 * H }, { id = 2, s = t + 26 * H, d = 2 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "c", mc = t - 10, st = "o", sa = t }
        for k, v in pairs(over or {}) do e[k] = v end
        advOffer(ns, B, "T", { e }, t + (over and over.bump or 0))
        return e
    end

    ---------------------------------------------------------------------------
    -- 委託業務
    ---------------------------------------------------------------------------

    test("GF-014-04 order_new: someone orders from me by name; one notice, the click opens that order", function()
        local ns = login()
        local N = ns.Notify
        orders(ns, B, { w(ns, "gB.1") })
        settle()
        local list = of(ns, "order_new")
        eq(#list, 1, "one notice")
        local e = list[1]
        eq(e.key, "new|gB.1", "key per order")
        ok(e.text:find("測試乙", 1, true) and e.text:find("指定你做", 1, true), "text: " .. e.text)
        eq(e.target.page, "orders", "page"); eq(e.target.id, "gB.1", "that order")
        eq(N.open(e), "focused", "the click focuses it")
        eq(ns.OrdersUI.focusId, "gB.1", "OrdersUI.focus on that order")
        -- A guild order (anyone may take it) is not "to me": no order_new.
        orders(ns, B, { w(ns, "gB.1"), w(ns, "gB.2", { cf = "*" }) }, ns.Share.serverNow() + 1)
        settle()
        eq(#of(ns, "order_new"), 1, "guild-wide order: no order_new")
    end)

    test("GF-014-04 order_status: taken, delivered merge into one notice per order; my own steps say nothing", function()
        local ns = login()
        local O = ns.Orders
        local id = O.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" })
        ok(id, "my guild order")
        settle()
        eq(#of(ns, "order_status"), 0, "placing my own order: nothing")
        local t = ns.Share.serverNow()
        jobs(ns, B, { { id = id, st = "a", ac = t, sa = t } }, t)
        settle()
        local e = of(ns, "order_status")[1]
        ok(e and e.text:find("接了你的委託", 1, true), "taken: " .. tostring(e and e.text))
        eq(e.target.id, id, "target: that order")
        wow.advance(60)
        local t2 = ns.Share.serverNow()
        jobs(ns, B, { { id = id, st = "d", ac = t, sa = t2, dt = t2, gv = 1 } }, t2)
        settle()
        local list = of(ns, "order_status")
        eq(#list, 1, "still one notice for the order")
        ok(list[1].text:find("交貨了", 1, true), "delivered: " .. list[1].text)
        eq(list[1].count, 2, "merged")
        -- I confirm (my own step): nothing new.
        ok(O.customer(id, "deal", "manual"), "I close it")
        settle()
        eq(of(ns, "order_status")[1].count, 2, "my deal: no notice")
    end)

    test("GF-014-04 order_status for the crafter: the customer returns or cancels; my accept says nothing", function()
        local ns = login()
        local O = ns.Orders
        orders(ns, B, { w(ns, "gB.5") })
        settle()
        eq(#of(ns, "order_new"), 1, "ordered from me")
        ok(O.crafter(O.get("gB.5"), "accept"), "I accept")
        settle()
        eq(#of(ns, "order_status"), 0, "my accept: nothing")
        wow.advance(30)
        orders(ns, B, { w(ns, "gB.5", { st = "x", sa = ns.Share.serverNow() }) }, ns.Share.serverNow())
        settle()
        local e = of(ns, "order_status")[1]
        ok(e and e.text:find("取消了委託", 1, true), "cancel by the customer: " .. tostring(e and e.text))
    end)

    test("GF-014-04 once only: a resend, a relay and /reload do not notify again; read stays read", function()
        local ns = login()
        local N = ns.Notify
        local t = ns.Share.serverNow()
        orders(ns, B, { w(ns, "gB.1") }, t)
        settle()
        local e = of(ns, "order_new")[1]
        N.markRead(e)
        -- The same record again (a resend / a relay through C), and a scan after the throttle.
        orders(ns, B, { w(ns, "gB.1") }, t)
        ns.Orders.notifyScan()
        wow.advance(N.THROTTLE + 60)
        ns.Orders.notifyScan()
        eq(#of(ns, "order_new"), 1, "one")
        eq(of(ns, "order_new")[1].count, 1, "not pushed again")
        eq(of(ns, "order_new")[1].unread, false, "read stays read")
        -- /reload: the saved ledger is read again; nothing new.
        local saved = wow.logout()
        ns = login(saved)
        ns.Orders.notifyScan(); ns.Adventure.notifyScan(); ns.Bank.notifyScan()
        settle()
        eq(#of(ns, "order_new"), 1, "after /reload: still one")
        eq(of(ns, "order_new")[1].count, 1, "after /reload: not again")
        eq(of(ns, "order_new")[1].unread, false, "after /reload: still read")
    end)

    test("GF-014-04 switches: each kind off on its own; an event while off does not come back later", function()
        local ns = login()
        local N = ns.Notify
        local keys = {}
        for _, m in ipairs(N.MODULES) do keys[m.key] = true end
        for _, k in ipairs({ "order_new", "order_status", "adv_signup", "adv_result", "adv_final", "bank_keeper" }) do
            ok(keys[k], "a switch: " .. k)
            ok(ns.NotifyUI.MODULE_SHORT[k], "a tag: " .. k)
        end
        N.setEnabled("order_new", false)
        orders(ns, B, { w(ns, "gB.1") })
        settle()
        eq(#of(ns, "order_new"), 0, "off: nothing")
        N.setEnabled("order_new", true)
        ns.Orders.notifyScan()
        eq(#of(ns, "order_new"), 0, "on again: the old event stays gone")
        -- order_status is still on while order_new is off.
        N.setEnabled("order_new", false)
        local id = ns.Orders.place({ recipe = RECIPE, item = ITEM, skill = SKILL, qty = 1, crafter = "*" })
        local t = ns.Share.serverNow()
        jobs(ns, C, { { id = id, st = "a", ac = t, sa = t } }, t)
        settle()
        eq(#of(ns, "order_status"), 1, "the other switch is its own")
        -- GF-009-10's recipe notices have their switch here too.
        ok(keys.recipe, "a switch: recipe"); eq(ns.NotifyUI.MODULE_SHORT.recipe, "調貨", "recipe tag")
        N.setEnabled("recipe", false)
        eq(N.push({ module = "recipe", key = "learned|1", text = "已學會" }), "off", "recipe off: push says off")
        N.setEnabled("recipe", true)
        eq(N.push({ module = "recipe", key = "learned|1", text = "已學會" }), "stored", "recipe on again")
        -- The settings list draws every switch inside the list.
        local parent = CreateFrame("Frame", nil, UIParent)
        local boxes = ns.NotifyUI.buildSettings(parent, 16, ns.NotifyUI.TOP)
        local UI = ns.NotifyUI
        local step = UI.settingStep(#boxes)
        ok(-UI.TOP + (#boxes - 1) * step + 28 <= UI.ROWS * UI.ROW_H + 76 - 8, string.format("%d switches fit (step %d)", #boxes, step))
        eq(#boxes, 14, "14 rows (9 modules, WorkerMatch's 4 rows, 聊天框提示)")
    end)

    test("GF-014-04 combat: the scan waits, the notice comes after combat", function()
        local ns = login()
        wow.enterCombat()
        orders(ns, B, { w(ns, "gB.1") })
        settle()
        eq(#of(ns, "order_new"), 0, "in combat: nothing yet")
        ok(ns.Orders.notifyStats.waited >= 1, "the scan waited")
        eq(ns.Orders.notifyStats.scans, 0, "no scan in combat")
        wow.leaveCombat()
        wow.advance(1)
        eq(#of(ns, "order_new"), 1, "after combat: the notice")
    end)

    ---------------------------------------------------------------------------
    -- 冒險業務
    ---------------------------------------------------------------------------

    test("GF-014-04 adv_signup: someone signs up for my ticket; my own ticket and steps say nothing", function()
        local ns = login()
        local Adv, N = ns.Adventure, ns.Notify
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { s = t + 2 * H, d = 2 * H } } })
        ok(id, "my ticket")
        settle()
        eq(#of(ns, "adv_signup"), 0, "opening my ticket: nothing")
        wow.advance(10)
        local t1 = ns.Share.serverNow()
        advOffer(ns, B, "A", { { id = id, ac = "ap", at = t1, ap = t1, ak = "ap", ro = "t", rb = "" } }, t1)
        settle()
        local e = of(ns, "adv_signup")[1]
        ok(e and e.text:find("測試乙", 1, true) and e.text:find("報名了你的冒險單", 1, true), "text: " .. tostring(e and e.text))
        eq(e.target.page, "adventure", "page"); eq(e.target.id, id, "that ticket")
        eq(N.open(e), "focused", "the click focuses it")
        eq(ns.AdventureUI.focusId, id, "AdventureUI.focus on it")
        -- C signs up too: the same notice, merged.
        advOffer(ns, C, "A", { { id = id, ac = "ap", at = t1 + 5, ap = t1 + 5, ak = "ap", ro = "h", rb = "" } }, t1 + 5)
        settle()
        eq(#of(ns, "adv_signup"), 1, "one notice per ticket")
        eq(of(ns, "adv_signup")[1].count, 2, "merged")
        ok(of(ns, "adv_signup")[1].text:find("測試丙", 1, true), "newest name")
    end)

    test("GF-014-04 adv_result: 錄取 after 待審核, 遞補, 邀請, 移出; my apply says nothing", function()
        local ns = login()
        local Adv = ns.Adventure
        local tk = bTicket(ns)
        settle()
        ok(Adv.worker(tk.id, "apply", { 1, 2 }), "I apply (consent mode: 待審核)")
        settle()
        eq(#of(ns, "adv_result"), 0, "my apply: nothing")
        eq(#(Adv.get(tk.id).pending), 1, "pending")
        wow.advance(20)
        local t = ns.Share.serverNow()
        bTicket(ns, { dc = A .. ":p:" .. ns.Share.b36(t), bump = 20 })
        settle()
        local e = of(ns, "adv_result")[1]
        ok(e and e.text:find("錄取了你", 1, true), "admitted: " .. tostring(e and e.text))
        eq(e.target.id, tk.id, "that ticket")
        -- Sent away by the leader.
        wow.advance(20)
        local t2 = ns.Share.serverNow()
        bTicket(ns, { dc = A .. ":p:" .. ns.Share.b36(t) .. ";" .. A .. ":k:" .. ns.Share.b36(t2), bump = 40 })
        settle()
        e = of(ns, "adv_result")[1]
        ok(e.text:find("移出", 1, true), "kicked: " .. e.text)
        eq(e.count, 2, "one notice per ticket, merged")
        -- An invitation on another ticket of C.
        local t3 = ns.Share.serverNow()
        local c = { id = "accc.1", src = "g", ver = 1, cr = t3, ds = "smg", qs = "", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, s = t3 + 2 * H, d = 2 * H } }), rt = 1, rh = 1, rd = 3, lr = "d", tg = 0,
            md = "a", st = "o", sa = t3, dc = A .. ":i:" .. ns.Share.b36(t3) }
        advOffer(ns, C, "T", { c }, t3)
        settle()
        local inv
        for _, x in ipairs(of(ns, "adv_result")) do if x.target.id == "accc.1" then inv = x end end
        ok(inv and inv.text:find("邀請你加入", 1, true), "invited: " .. tostring(inv and inv.text))
    end)

    test("GF-014-04 adv_result 遞補 and adv_final 定案 / 取消", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        -- C's ticket, auto mode, one tank seat: D... B takes it first, I wait.
        local c = { id = "accc.2", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, s = t + 2 * H, d = 2 * H }, { id = 2, s = t + 26 * H, d = 2 * H } }),
            rt = 1, rh = 0, rd = 0, lr = "d", tg = 0, md = "a", st = "o", sa = t }
        advOffer(ns, C, "T", { c }, t)
        advOffer(ns, B, "A", { { id = c.id, ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "t", rb = "" } }, t + 1)
        settle()
        wow.advance(5)
        ok(Adv.worker(c.id, "apply", { 1, 2 }), "I apply")
        settle()
        eq(#(Adv.get(c.id).waitlist), 1, "I wait")
        eq(#of(ns, "adv_result"), 0, "nothing yet")
        -- B withdraws: I move up.
        wow.advance(20)
        local t2 = ns.Share.serverNow()
        advOffer(ns, B, "A", { { id = c.id, ac = "wd", at = t2, ap = t + 1, ak = "ap", ro = "t", rb = "" } }, t2)
        settle()
        local e = of(ns, "adv_result")[1]
        ok(e and e.text:find("遞補", 1, true), "refilled: " .. tostring(e and e.text))
        -- C finalizes slot 2.
        wow.advance(20)
        local t3 = ns.Share.serverNow()
        c.fx, c.fa, c.ed = 2, t3, nil
        advOffer(ns, C, "T", { c }, t3)
        settle()
        local f = of(ns, "adv_final")[1]
        ok(f and f.text:find("定案", 1, true), "finalized: " .. tostring(f and f.text))
        eq(f.target.id, c.id, "that ticket")
        -- C cancels.
        wow.advance(20)
        local t4 = ns.Share.serverNow()
        c.st, c.sa, c.rs = "x", t4, "manual"
        advOffer(ns, C, "T", { c }, t4)
        settle()
        f = of(ns, "adv_final")[1]
        ok(f.text:find("取消了冒險單", 1, true), "cancelled: " .. f.text)
        eq(f.count, 2, "merged per ticket")
        -- /reload replays it all: nothing new.
        local before = {}
        for _, m in ipairs({ "adv_result", "adv_final" }) do before[m] = of(ns, m)[1].count end
        local saved = wow.logout()
        ns = login(saved)
        ns.Adventure.notifyScan()
        settle()
        for _, m in ipairs({ "adv_result", "adv_final" }) do eq(of(ns, m)[1].count, before[m], "after /reload: " .. m .. " not again") end
    end)

    test("GF-014-04 adv switches and combat", function()
        local ns = login()
        local N = ns.Notify
        N.setEnabled("adv_result", false)
        local tk = bTicket(ns)
        ok(ns.Adventure.worker(tk.id, "apply", { 1, 2 }), "I apply")
        settle()
        wow.advance(20)
        wow.enterCombat()
        local t = ns.Share.serverNow()
        bTicket(ns, { dc = A .. ":p:" .. ns.Share.b36(t), bump = 20 })
        settle()
        ok(ns.Adventure.notifyStats.waited >= 1, "in combat: the scan waits")
        wow.leaveCombat(); wow.advance(1)
        eq(#of(ns, "adv_result"), 0, "adv_result off: no notice after combat either")
    end)

    ---------------------------------------------------------------------------
    -- 臨時黑箱
    ---------------------------------------------------------------------------

    test("GF-014-04 bank_keeper: named custodian, scope changed, revoked; the page opens; once only", function()
        local ns = login()
        local N = ns.Notify
        wow.state.roster = wow.defaultRoster()
        wow.state.roster[2].rank = "會長"; wow.state.roster[1].rank = "會員"
        ns.Bank.invalidate()
        local function list(epoch, kinds, enabled)
            return assert(ns.Bank.encode({ epoch = epoch, leader = B, entries = { { a = A, kinds = kinds, enabled = enabled, epoch = epoch } } }))
        end
        local function send(epoch, kinds, enabled)
            local v = list(epoch, kinds, enabled)
            ns.Share.onMessage("GFTKS", "S1~V~" .. B .. "~K~" .. ns.Share.b36(epoch) .. "~" .. ns.Share.hash(v) .. "~" .. v,
                "GUILD", "測試乙-測試伺服器")
            ns.Bank.invalidate()
            settle()
        end
        local t = ns.Share.serverNow()
        send(t, "bk", true)
        eq(ns.Bank.myRole(), "custodian", "I am custodian")
        local e = of(ns, "bank_keeper")[1]
        ok(e and e.text:find("指定你為", 1, true), "named: " .. tostring(e and e.text))
        eq(e.target.page, "bank", "the 黑箱 page")
        ok(N.open(e) ~= "none", "the click opens the page")
        eq(ns.Framework.isModuleShown("bank"), true, "黑箱 shown")
        -- The same list again (relay): nothing new.
        send(t, "bk", true)
        eq(of(ns, "bank_keeper")[1].count, 1, "relay: not again")
        wow.advance(30)
        send(t + 30, "b", true)
        ok(of(ns, "bank_keeper")[1].text:find("改成背包", 1, true), "scope changed")
        wow.advance(30)
        send(t + 60, "b", false)
        e = of(ns, "bank_keeper")[1]
        ok(e.text:find("撤銷", 1, true), "revoked: " .. e.text)
        eq(e.count, 3, "one notice, merged")
    end)

    test("GF-014-04 bank_keeper: the guild master's own list does not notify the master", function()
        local ns = login()
        IsGuildLeader = function() return true end
        wow.state.roster = wow.defaultRoster()
        wow.state.roster[1].rank = "會長"; wow.state.roster[2].rank = "會員"
        ns.Bank.invalidate()
        eq(ns.Bank.appoint("測試丙-測試伺服器"), "ok", "I name C")
        settle()
        ns.Bank.notifyScan()
        eq(#of(ns, "bank_keeper"), 0, "my own list: nothing")
        IsGuildLeader = nil
    end)

    ---------------------------------------------------------------------------
    -- 100 events in a row
    ---------------------------------------------------------------------------

    test("GF-014-04 100 orders in a row: merged into the notices, one chat line, time printed", function()
        local ns = login()
        local N = ns.Notify
        wow.clearPrinted()
        local clock = os.clock()
        local t = ns.Share.serverNow()
        local list = {}
        for i = 1, 100 do
            list[#list + 1] = w(ns, "gB." .. i)
            orders(ns, B, list, t + i)
        end
        settle()
        local ms = (os.clock() - clock) * 1000
        local n = #of(ns, "order_new")
        eq(n, N.BURST + 1, string.format("%d notices and one 另有 N 則 (%d)", N.BURST, n))
        local more = N.find("order_new", N.MORE_KEY)
        ok(more and more.more == 100 - N.BURST and more.text:find("另有 90 則", 1, true), "the rest merged: " .. tostring(more and more.text))
        eq(more.target.page, "orders", "it opens the orders page")
        ok(ns.Orders.notifyStats.scans <= 5, "scans: " .. ns.Orders.notifyStats.scans .. " (coalesced per frame)")
        eq(ns.Orders.notifyStats.events, 100, "every event marked once")
        wow.advance(N.ALERT_GAP + 5)
        local lines = 0
        for _, p in ipairs(wow.printed()) do if tostring(p):find("業務通知", 1, true) then lines = lines + 1 end end
        ok(lines <= 1, "at most one chat line (" .. lines .. ")")
        ok(ms < 2000, string.format("time: %.1f ms", ms))
        T.realPrint(string.format("     GF-014-04 100 orders in a row: %.1f ms, %d scans, %d notices, %d chat line(s)",
            ms, ns.Orders.notifyStats.scans, n, lines))
        -- A second burst of the same: nothing new.
        local again = ns.Orders.notifyScan()
        eq(again, 0, "replayed: nothing")
    end)
    ---------------------------------------------------------------------------
    -- The cost every ledger change pays: one scan with nothing new
    ---------------------------------------------------------------------------

    -- 25 more members (authors 0000-000010NN), each with n / 25 orders (half to
    -- me by name) and n / 25 adventure tickets (I signed up for every third).
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
        local t = ns.Share.serverNow()
        local per = n / 25
        local mine = {}
        for k, a in ipairs(authors) do
            local ws, ts = {}, {}
            for j = 1, per do
                ws[#ws + 1] = w(ns, "g" .. k .. "." .. j, { cf = (j % 2 == 0) and A or "*" })
                local id = "a" .. k .. "." .. j
                ts[#ts + 1] = { id = id, src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
                    ts = ns.Adventure.encodeTimes({ { id = 1, s = t + 2 * H, d = 2 * H }, { id = 2, s = t + 26 * H, d = 2 * H } }),
                    rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t }
                if j % 3 == 0 then mine[#mine + 1] = { id = id, ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "d", rb = "" } end
            end
            orders(ns, a, ws, t)
            advOffer(ns, a, "T", ts, t)
        end
        advOffer(ns, A, "A", mine, t + 1)
        settle()
        return ns, #mine
    end
    local function perScan(fn, rounds)
        fn() -- what is new goes now; the rounds below find nothing new
        local clock = os.clock()
        local pushed = 0
        for _ = 1, rounds do pushed = pushed + fn() end
        return (os.clock() - clock) * 1000 / rounds, pushed
    end

    test("GF-014-04 one scan with nothing new: Orders / Adventure at 100 and 300 records (printed)", function()
        for _, n in ipairs({ 100, 300 }) do
            local ns, signed = bigGuild(n)
            local nOrders, nTickets = 0, 0
            for _ in pairs(ns.Orders.all()) do nOrders = nOrders + 1 end
            for _ in pairs(ns.Adventure.all()) do nTickets = nTickets + 1 end
            eq(nOrders, n, n .. " orders in the ledger")
            eq(nTickets, n, n .. " tickets in the ledger")
            local oMs, oPushed = perScan(ns.Orders.notifyScan, 20)
            local aMs, aPushed = perScan(ns.Adventure.notifyScan, 20)
            eq(oPushed + aPushed, 0, "nothing new: nothing pushed")
            T.realPrint(string.format("     GF-014-04 idle scan, %d records: Orders.notifyScan %.2f ms, Adv.notifyScan %.2f ms (I signed up for %d)",
                n, oMs, aMs, signed))
            ok(oMs < 5, string.format("Orders.notifyScan at %d: %.2f ms < 5 ms", n, oMs))
            ok(aMs < 5, string.format("Adv.notifyScan at %d: %.2f ms < 5 ms", n, aMs))
        end
    end)
end
