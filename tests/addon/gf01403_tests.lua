-- GF-014-03 (GPT review of 0.16.3, items 3 and the adventure half of 4):
-- worker-ticket matching only on slots I can still join, the notice names
-- that slot, a notice held back in combat is checked again, a zone picked
-- whole is told apart from one that comes from my quests, quest-only matches
-- off by default, the two chat switches; the bell's jump, the long worker
-- detail and ESC together; the small windows on a 768-high screen (1280x720
-- or 1920x1080 at UI scale 1.0) and at 0.64; drafts kept; the whole slot
-- length. Offline only (MANUAL §GF-014-03). Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B, C = "0000-0000000B", "0000-0000000C"
    local H = 3600

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local r = ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    -- A ticket (again: one second later, so the ledger takes it as newer).
    local function ticket(ns, a, over)
        wow.advance(1)
        local t = ns.Share.serverNow()
        local e = { id = "a" .. a:sub(-3) .. ".1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t }
        for k, v in pairs(over or {}) do e[k] = v end
        offer(ns, a, "T", { e })
        return e.id
    end
    local function myWorker(ns, over)
        local o = { dungeons = { "smg" }, quests = {}, main = "t", alt = "h", slots = { { now = true } } }
        for k, v in pairs(over or {}) do o[k] = v end
        ok(ns.Adventure.setWorker(o), "my worker ticket")
    end
    local function notices(ns)
        local out = {}
        for _, e in ipairs(ns.Notify.list()) do if e.module == "adventure" then out[#out + 1] = e end end
        return out
    end
    local function printed(pattern)
        local n = 0
        for _, l in ipairs(wow.state.printed) do if tostring(l):find(pattern, 1, true) then n = n + 1 end end
        return n
    end

    ---------------------------------------------------------------------------
    -- 3. Matching
    ---------------------------------------------------------------------------

    test("GF-014-03 only slots I can still join: an ended slot does not match; the notice names the joinable one", function()
        local ns = login()
        local M, U = ns.WorkerMatch, ns.AdventureUI
        myWorker(ns) -- 現在 (no length): now +-30 minutes
        local t = ns.Share.serverNow()
        -- Slot 1 ended 10 minutes ago (it still touches my 現在 window); slot 2 starts in 10 minutes.
        local ended = { id = 1, s = t - 2 * H, d = 2 * H - 600 }
        local ahead = { id = 2, s = t + 600, d = H }
        local id = ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ ended, ahead }) })
        local list = M.scan()
        eq(#list, 1, "it fits through slot 2")
        eq(list[1].slot.id, 2, "the slot I can join")
        eq(#list[1].slots, 1, "only that one counts")
        local e = notices(ns)[1]
        ok(e and e.text:find(U.clock(ahead.s), 1, true), "the notice names slot 2: " .. tostring(e and e.text))
        ok(not e.text:find(U.clock(ended.s), 1, true), "not the ended one")
        -- Only the ended slot: no match (the window around 現在 is not enough).
        ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ ended }) })
        eq(#M.scan(), 0, "an ended slot alone does not match")
        eq(#notices(ns), 0, "its notice went")
        -- Finalized on a slot that does not overlap mine: no match either.
        local later = { id = 3, s = t + 6 * H, d = H }
        ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ ahead, later }), fx = 3 })
        eq(#M.scan(), 0, "finalized elsewhere")
        ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ ahead, later }), fx = 2 })
        eq(#M.scan(), 1, "finalized on the slot I can join")
        eq(notices(ns)[1].key, "match|" .. id, "the same key")
    end)

    test("GF-014-03 a seat for my role in the slot; the ttl ends with the last joinable slot", function()
        local ns = login()
        local M = ns.WorkerMatch
        local t = ns.Share.serverNow()
        myWorker(ns, { alt = "" , slots = { { s = t + 60, d = 8 * H } } })
        local s1 = { id = 1, s = t + 600, d = H }
        local s2 = { id = 2, s = t + 3 * H, d = 2 * H }
        ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ s1, s2 }) })
        local c = M.scan()[1]
        ok(c, "matched")
        eq(c.slot.id, 1, "the earliest joinable slot")
        eq(#c.slots, 2, "both joinable")
        ok(math.abs(notices(ns)[1].expires - (s2.s + s2.d)) <= 2, "kept until slot 2 ends")
        -- No seat for my role (坦 0): nothing, whatever the slot.
        ticket(ns, B, { tm = "t", ts = ns.Adventure.encodeTimes({ s1, s2 }), rt = 0 })
        eq(#M.scan(), 0, "no seat for my main role, no support role")
        eq(M.seatIn({ seats = { t = 1 }, capacity = { t = 1 }, members = { { a = C, role = "t", slots = { 1 } } } }, { id = 1 }, "t"), false,
            "a slot whose members fill the role is full")
        eq(M.seatIn({ seats = { t = 1 }, capacity = { t = 1 }, members = { { a = C, role = "t", slots = { 2 } } } }, { id = 1 }, "t"), true,
            "a member of another slot does not fill this one")
    end)

    test("GF-014-03 a zone I picked whole is a place; a zone that only comes from my quests is not (off by default)", function()
        local ns = login()
        local M = ns.WorkerMatch
        C_QuestLog = { GetNumQuestLogEntries = function() return 2, 0 end, GetInfo = function(i)
            return ({ { isHeader = true, title = "測試荒野" }, { questID = 850, title = "測試任務：草原之心", level = 30 } })[i] end }
        local zoneTicket = { ds = "", qs = "", zn = "測試荒野", sz = 5 }
        -- My worker ticket names quest 850 (its zone 測試荒野 comes with it), no dungeon.
        myWorker(ns, { dungeons = {}, quests = { 850 } })
        local w = ns.Adventure.workers()[ns.Share.selfAuthor()]
        ok(w.zones["測試荒野"] and not w.wholeZones["測試荒野"], "the zone came from the quest")
        ticket(ns, B, zoneTicket)
        eq(M.get("quests"), false, "quest-only off by default")
        eq(#M.scan(), 0, "a zone from my quests alone: no notice by default")
        M.set("quests", true)
        local list = M.candidates()
        eq(#list, 1, "counts with 只有共同任務也算")
        eq(list[1].basis, "quest", "it rests on the quests")
        eq(#notices(ns), 1, "notified once switched on")
        M.set("quests", false)
        eq(#notices(ns), 0, "gone when switched off")
        -- The same zone picked whole (全區): a place, notified by default.
        myWorker(ns, { dungeons = {}, quests = {}, zones = { "測試荒野" } })
        list = M.scan()
        eq(#list, 1, "a whole zone matches")
        eq(list[1].basis, "place", "it is a place")
        eq(#notices(ns), 1, "notified by default")
        C_QuestLog = nil
    end)

    test("GF-014-03 shared quests still rank first when the place matches too", function()
        local ns = login()
        local M = ns.WorkerMatch
        myWorker(ns, { quests = { 850 } })
        local t = ns.Share.serverNow()
        local plainId = ticket(ns, B)
        offer(ns, C, "T", { { id = "accc.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "850", tm = "n",
            ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        local list = M.scan()
        eq(#list, 2, "both (the dungeon matches)")
        eq(list[1].view.id, "accc.1", "the one with a shared quest first")
        eq(list[1].basis, "place", "still a place match")
        eq(list[2].view.id, plainId, "then the plain one")
        eq(#notices(ns), 2, "both notified with the switch off")
    end)

    test("GF-014-03 combat: a held-back notice is checked again; gone if it no longer fits, else the newest text", function()
        local ns = login()
        local M = ns.WorkerMatch
        myWorker(ns)
        wow.advance(5)
        wow.enterCombat()
        ticket(ns, B)
        wow.advance(M.DEBOUNCE + 1)
        eq(ns.Notify.queued(), 1, "waiting in combat")
        -- The leader cancels while I am still in combat; combat ends before the next scan.
        ticket(ns, B, { st = "x", sa = ns.Share.serverNow() })
        wow.leaveCombat()
        wow.advance(0.5)
        eq(#notices(ns), 0, "checked again: not shown")
        eq(M.stats.dropped, 1, "dropped by the recheck")
        -- Again, this time the ticket changes (a later slot) but still fits: the newest text.
        ns.Notify.clear("adventure"); ns.Notify.memory("adventure").sent = {}
        local t = ns.Share.serverNow()
        wow.enterCombat()
        ticket(ns, C)
        wow.advance(M.DEBOUNCE + 1)
        eq(ns.Notify.queued(), 1, "waiting")
        local later = { id = 1, s = t + 900, d = H }
        ticket(ns, C, { tm = "t", ts = ns.Adventure.encodeTimes({ later }), ed = t + 1 })
        wow.leaveCombat()
        wow.advance(0.5)
        local e = notices(ns)[1]
        ok(e, "shown after combat")
        ok(e.text:find(ns.AdventureUI.clock(later.s), 1, true), "with the newest slot: " .. tostring(e and e.text))
    end)

    test("GF-014-03 chat: 聊天框提示 alone gives the count line; 配對時聊天框一行 gives the match instead; both off when 聊天框提示 is off", function()
        local ns = login()
        local M, N = ns.WorkerMatch, ns.Notify
        myWorker(ns)
        local function fresh() N.clear("adventure"); N.memory("adventure").sent = {}; wow.state.printed = {} end
        -- Default: GF-014's count line, no match line.
        fresh(); wow.advance(N.ALERT_GAP + 1)
        ticket(ns, B); M.scan()
        wow.advance(N.ALERT_GAP + 1)
        eq(printed("業務通知：有 1 則新提示"), 1, "the count line")
        eq(printed("職工單配對："), 0, "no match line")
        -- 配對時聊天框一行: the match line, and no count line for it.
        M.set("chat", true)
        fresh(); wow.advance(N.ALERT_GAP + 1)
        M.scan()
        wow.advance(N.ALERT_GAP + 1)
        eq(printed("職工單配對："), 1, "the match line")
        eq(printed("業務通知：有"), 0, "instead of the count line")
        -- A quiet merge (read, within GF-014's throttle) prints nothing.
        N.markRead(notices(ns)[1]); wow.state.printed = {}
        wow.advance(M.CHAT_GAP + 1)
        ticket(ns, B, { ed = ns.Share.serverNow() }); M.scan()
        wow.advance(N.ALERT_GAP + 1)
        eq(printed("職工單配對：") + printed("業務通知：有"), 0, "a quiet merge says nothing")
        -- 聊天框提示 off: no line at all, whichever.
        N.setChat(false)
        fresh(); wow.advance(N.ALERT_GAP + 1)
        M.scan()
        wow.advance(N.ALERT_GAP + 1)
        eq(#notices(ns), 1, "the notice is still there")
        eq(printed("職工單配對：") + printed("業務通知："), 0, "no chat line at all")
    end)

    ---------------------------------------------------------------------------
    -- 4. The bell's jump, the long worker detail, ESC, the screen
    ---------------------------------------------------------------------------

    test("GF-014-03 the whole slot length: 1 小時 30 分, 45 分, 2 小時 (not rounded)", function()
        local ns = login()
        local U = ns.AdventureUI
        eq(U.lengthText(5400), "1 小時 30 分", "90 minutes")
        eq(U.lengthText(2700), "45 分", "45 minutes")
        eq(U.lengthText(7200), "2 小時", "2 hours")
        local t = ns.Share.serverNow()
        myWorker(ns, { slots = { { s = t + H, d = 5400 } } })
        local w = ns.Adventure.workers()[ns.Share.selfAuthor()]
        local found
        for _, l in ipairs(U.workerTooltipLines(w, ns.Share.selfAuthor())) do
            if l.text:find("預計", 1, true) then found = l.text end
        end
        ok(found and found:find("預計 1 小時 30 分", 1, true), "the tooltip: " .. tostring(found))
        local src = assert(io.open(ADDON_DIR .. "/AdventureUI.lua", "rb")):read("*a")
        ok(not src:find("math.floor(sl.d / 3600 + 0.5)", 1, true), "no rounded hours left")
    end)

    -- UIParent at a resolution and UI scale: 768 / scale high (the game's rule).
    local SCREENS = {
        { name = "1280x720 / 1920x1080 at 1.0", w = 1365, h = 768 },
        { name = "1280x720 / 1920x1080 at 0.64", w = 2133, h = 1200 },
        { name = "1024x768 at 1.0 (narrow)", w = 1024, h = 768 },
    }
    local function screen(s)
        UIParent.GetWidth = function() return s.w end
        UIParent.GetHeight = function() return s.h end
    end
    -- On the screen whole: the size it was given, after its scale, inside the
    -- margins; a window centred on UIParent inside the screen; clamped.
    local function onScreen(ns, f, what, s)
        local fit = f.gfFit
        ok(fit and fit.clamped, what .. ": clamped (" .. s.name .. ")")
        if not (fit and fit.w and fit.h) then return end
        local m = 2 * ns.AdventureUI.SCREEN_MARGIN
        local sw, sh = fit.w * fit.scale, fit.h * fit.scale
        ok(sw <= s.w - m + 0.5 and sh <= s.h - m + 0.5,
            string.format("%s: %dx%d at %.2f fits %dx%d (%s)", what, fit.w, fit.h, fit.scale, s.w, s.h, s.name))
        local p = f._points and f._points[#f._points]
        if p and p[1] == "CENTER" and p[2] == UIParent then
            local cx, cy = s.w / 2 + (p[4] or 0) * fit.scale, s.h / 2 + (p[5] or 0) * fit.scale
            ok(cx - sw / 2 >= 0 and cx + sw / 2 <= s.w and cy - sh / 2 >= 0 and cy + sh / 2 <= s.h,
                what .. ": inside the screen (" .. s.name .. ")")
        end
    end
    local function manySlots(t, n)
        local out = {}
        for i = 1, n do out[i] = { s = t + i * 2 * H, d = H } end
        return out
    end

    test("GF-014-03 every small window fits a 768-high screen and 0.64 scale (ticket, worker, detail, chooser, grid, calendar, rules)", function()
        for _, s in ipairs(SCREENS) do
            local ns = login()
            local U, Adv = ns.AdventureUI, ns.Adventure
            screen(s)
            ns.Framework.open("adventure")
            local t = ns.Share.serverNow()
            -- The ticket form with 10 slots and the slot editor open.
            U.openTicket()
            local d = U.draft()
            d.slots = {}
            for i, sl in ipairs(manySlots(t, U.MAX_SLOTS)) do d.slots[i] = U.draftSlot(sl) end
            local tf = _G[U.TICKET_NAME]
            U.openSlotEditor(tf, 1)
            U.drawTicket()
            onScreen(ns, tf, "ticket form", s)
            -- The slot chooser with 10 slots.
            local v = { slots = {}, slotCounts = {} }
            for i, sl in ipairs(manySlots(t, U.MAX_SLOTS)) do sl.id = i; v.slots[i] = sl end
            local ch = U.slotChooser(tf, { title = "時段", slots = v.slots, counts = v.slotCounts, selected = {}, multi = true, onDone = function() end })
            onScreen(ns, ch, "slot chooser", s)
            ch:Hide()
            -- The dungeon grid.
            local g = U.pickDestination(tf)
            if g then onScreen(ns, g, "dungeon grid", s); g:Hide() end
            tf:Hide()
            -- The worker form with 10 slots.
            U.openWorker()
            local wd = U.workerDraft()
            wd.slots = {}
            for i, sl in ipairs(manySlots(t, U.MAX_SLOTS)) do wd.slots[i] = U.draftSlot(sl) end
            U.drawWorker()
            onScreen(ns, _G[U.WORKER_NAME], "worker form", s)
            _G[U.WORKER_NAME]:Hide()
            -- The long worker detail: 60 lines, one very long.
            local lines = {}
            local C0 = ns.Theme.C.text
            for i = 1, 60 do lines[i] = { text = "測試任務第 " .. i .. " 條", color = C0 } end
            lines[3] = { text = string.rep("很長的任務名稱", 20), color = C0 }
            local det = U.openWorkerDetail(lines)
            onScreen(ns, det, "worker detail", s)
            ok(det.contentWidth >= math.min(det.widest, s.w - 2 * U.SCREEN_MARGIN - 80), "the widest line fits or scrolls (" .. s.name .. ")")
            det:Hide()
            -- The calendar and the rules card.
            onScreen(ns, U.openCalendar(), "calendar", s)
            U.calendar():Hide()
            local r = U.openRules(U.rulesButton)
            ok(r.gfFit and r.gfFit.clamped, "rules: clamped (" .. s.name .. ")")
            r:Hide()
            ok(Adv, "adventure loaded")
        end
    end)

    test("GF-014-03 the bell's jump closes the detail and the forms (drafts kept); ESC closes the top one first", function()
        local ns = login()
        local U, N = ns.AdventureUI, ns.Notify
        myWorker(ns)
        local id = ticket(ns, B)
        ns.WorkerMatch.scan()
        ns.Framework.open("adventure")
        -- A draft in the ticket form, the long detail on top.
        U.openTicket()
        U.draft().note = "測試備註"
        local tf = _G[U.TICKET_NAME]
        local det = U.openWorkerDetail({ { text = "測試", color = ns.Theme.C.text } })
        ok(tf:IsShown() and det:IsShown(), "both open")
        -- ESC: the detail first, then the form.
        eq(ns.escape(), det, "ESC: the detail first")
        ok(tf:IsShown(), "the form stays")
        U.openWorkerDetail({ { text = "測試", color = ns.Theme.C.text } })
        -- The bell's jump: the row, nothing left on top of it.
        eq(N.open(notices(ns)[1]), "focused", "the jump")
        eq(U.focusId, id, "focused on the ticket")
        ok(not det:IsShown(), "the detail closed")
        ok(not tf:IsShown(), "the form closed")
        -- The draft comes back with the form.
        U.openTicket()
        eq(U.draft().note, "測試備註", "draft kept")
        -- Saving drops it; ESC keeps it.
        ns.escape()
        ok(U.keptDraft("ticket"), "ESC keeps it")
        U.openTicket()
        eq(U.draft().note, "測試備註", "back again")
        U.dropDraft("ticket"); tf:Hide(); U.dropDraft("ticket")
        U.openTicket()
        eq(U.draft().note, "", "a fresh one once dropped")
        tf:Hide()
        -- Too old: a fresh one.
        U.openTicket(); U.draft().note = "舊的"; tf:Hide()
        wow.advance(U.DRAFT_KEEP + 5)
        U.openTicket()
        eq(U.draft().note, "", "after 30 minutes: fresh")
        tf:Hide()
    end)

    test("GF-014-03 the page goes (another page, the main window closed): its small windows go too", function()
        local ns = login()
        local U, F = ns.AdventureUI, ns.Framework
        F.open("adventure")
        local p = F.panel("adventure")
        U.openWorker()
        local wf = _G[U.WORKER_NAME]
        U.workerDraft().main = "h"
        local det = U.openWorkerDetail({ { text = "測試", color = ns.Theme.C.text } })
        ok(wf:IsShown() and det:IsShown(), "open")
        -- The main window closes: the game hides the page with it (OnHide on the page).
        F.toggle("adventure")
        if p:IsShown() then p:Hide() elseif p._scripts.OnHide then p._scripts.OnHide(p) end
        ok(not wf:IsShown(), "the worker form went")
        ok(not det:IsShown(), "the detail went")
        F.open("adventure")
        U.openWorker()
        eq(U.workerDraft().main, "h", "the worker draft came back")
        -- 登記 drops it.
        U.saveWorker()
        ok(not U.keptDraft("worker"), "saved: nothing kept")
        -- Another page: the same.
        U.openWorkerDetail({ { text = "測試", color = ns.Theme.C.text } })
        local cal = U.openCalendar() -- a popup of its own (it closes the other forms, as before)
        ok(det:IsShown() and cal:IsShown(), "the detail and the calendar")
        local other
        for _, b in ipairs(F.navButtons() or {}) do if b.moduleId and b.moduleId ~= "adventure" then other = b.moduleId; break end end
        if other then
            F.open(other)
            ok(not det:IsShown(), "another page: the detail went")
            ok(not cal:IsShown(), "another page: the calendar went")
        end
    end)
end
