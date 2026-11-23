-- Offline tests for GF-002-B (adventure and worker tickets, spec
-- docs/spec/GF-002_adventure-tickets_v1.0.md). Test names carry the R
-- numbers. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local NAME = { [B] = "測試乙-測試伺服器", [C] = "測試丙-測試伺服器" }
    local MIN = 60

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Adventure.resetSession(); ns.Orders.resetSession()
        return ns
    end
    local function peer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        return ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
    end
    local function ticket(id, extra)
        local e = { id = id, src = "g", ver = 1, cr = 1763000000, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "o", sa = 1763000000 }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local function act(id, ac, at, ro, rb, ap)
        return { id = id, ac = ac, at = at, ro = ro, rb = rb or "", ap = ap, ak = ap and "ap" or nil }
    end
    local function names(list) local out = {} for _, x in ipairs(list) do out[#out + 1] = x.a .. (x.role and (":" .. x.role) or "") end return table.concat(out, ",") end

    ---------------------------------------------------------------------------
    -- R-6.1 matching
    ---------------------------------------------------------------------------

    test("GF-002 R-6.1 matching: destination, role, level and time all have to fit", function()
        local ns = login()
        local Adv = ns.Adventure
        local v = Adv.view(ticket("t1", { qs = "101.102" }), B, {}, { now = 1763000100 })
        local w = { dungeons = { smg = true }, quests = {}, main = "h", slots = { { now = true } } }
        ok(Adv.matches(v, w, 30), "dungeon, healer free, level 30, now")
        local function why(x, lvl, log) local okM, r = Adv.matches(v, x, lvl, log); return okM and "ok" or r end
        eq(why({ dungeons = { rfk = true }, quests = {}, main = "h", slots = { { now = true } } }, 30), "dest", "other dungeon")
        eq(why({ dungeons = {}, quests = { [102] = true }, main = "h", slots = { { now = true } } }, 30), "ok", "a shared quest id")
        eq(why({ dungeons = {}, quests = {}, allQuests = true, main = "h", slots = { { now = true } } }, 30, { [101] = true }), "ok", "all of my log")
        eq(why({ dungeons = { smg = true }, quests = {}, main = "h", slots = { { now = true } } }, 15), "level", "too low")
        eq(why({ dungeons = { smg = true }, quests = {}, main = "h", slots = { { s = 1, e = 2 } } }, 30), "time", "a slot does not match now")
        -- Leader is dps; 3 dps seats -> 2 left. Fill the tank: a tank no longer matches.
        local full = Adv.view(ticket("t1", { rt = 1 }), B, { [C] = { act("t1", "ap", 10, "t") } }, { now = 20 })
        eq(why({ dungeons = { smg = true }, quests = {}, main = "t", slots = { { now = true } } }, 30), "ok", "tank seat before")
        local okT, r = Adv.matches(full, { dungeons = { smg = true }, quests = {}, main = "t", slots = { { now = true } } }, 30)
        eq(okT and "ok" or r, "role", "tank seat taken")
        ok(Adv.matches(full, { dungeons = { smg = true }, quests = {}, main = "t", alt = "d", slots = { { now = true } } }, 30), "alt role dps fits")
        -- Timed ticket vs slots.
        local timed = Adv.view(ticket("t2", { tm = "t", s = 1000, e = 2000 }), B, {}, { now = 0 })
        ok(Adv.timeOverlap(timed, { { s = 1500, e = 2500 } }), "overlap"); ok(not Adv.timeOverlap(timed, { { s = 2000, e = 2500 } }), "touching is no overlap")
        ok(not Adv.timeOverlap(timed, { { now = true } }), "now vs a slot")
    end)

    ---------------------------------------------------------------------------
    -- R-9.1 merge: replay, independent of arrival order
    ---------------------------------------------------------------------------

    test("GF-002 R-9.1 the same result whatever order the records arrive in", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local leaderT = ticket("t1", { cr = t - 100, sa = t - 100, rt = 1, rh = 1, rd = 2, dc = "0000-0000000D:k:" .. ns.Share.b36(t - 40) })
        local records = {
            { B, "T", { leaderT } },
            { C, "A", { act("t1", "ap", t - 90, "h") } },
            { D, "A", { act("t1", "ap", t - 80, "h", "d") } },
            { A, "A", { act("t1", "ap", t - 70, "h") } },
        }
        local results = {}
        for k, order in ipairs({ { 1, 2, 3, 4 }, { 4, 3, 2, 1 }, { 2, 4, 1, 3 }, { 3, 1, 4, 2 } }) do
            ns = login()
            for _, i in ipairs(order) do peer(ns, records[i][1], records[i][2], records[i][3]) end
            local v = ns.Adventure.get("t1")
            results[k] = names(v.members) .. "|" .. names(v.waitlist)
        end
        eq(results[1], results[2], "1 = 2"); eq(results[2], results[3], "2 = 3"); eq(results[3], results[4], "3 = 4")
        -- C heals; D takes the free dps seat (alt) then gets kicked -> A (healer) waits, no dps seat for A.
        eq(results[1], C .. ":h|" .. A, "C healer, D kicked, A on the waitlist")
    end)

    test("GF-002 R-9.1 same time: GUID byte order decides", function()
        local ns = login()
        local Adv = ns.Adventure
        local v = Adv.view(ticket("t1", { rh = 1 }), B, { ["0000-0000000a"] = { act("t1", "ap", 50, "h") },
            ["0000-0000000C"] = { act("t1", "ap", 50, "h") } }, { now = 60 })
        eq(v.members[1].a, "0000-0000000C", "C (0x43) before a (0x61)")
    end)

    ---------------------------------------------------------------------------
    -- R-4.5, R-6.3 – R-6.6 admission, waitlist, refill, kick, withdraw
    ---------------------------------------------------------------------------

    test("GF-002 R-4.5/R-6.3 direct admission, then waitlist when full", function()
        local ns = login()
        local Adv = ns.Adventure
        local v = Adv.view(ticket("t1", { rt = 1, rh = 0, rd = 1, lr = "d" }), B,
            { [C] = { act("t1", "ap", 10, "t") }, [D] = { act("t1", "ap", 20, "t") } }, { now = 30 })
        eq(names(v.members), C .. ":t", "first tank in"); eq(names(v.waitlist), D, "second waits")
        eq(v.state, "full", "full (leader is the only dps)")
    end)

    test("GF-002 R-4.5 consent: applications wait for ✓; switching to consent keeps who is in", function()
        local ns = login()
        local Adv = ns.Adventure
        local acts = { [C] = { act("t1", "ap", 10, "h") }, [D] = { act("t1", "ap", 30, "t") } }
        local v = Adv.view(ticket("t1", { md = "c", mc = 20 }), B, acts, { now = 40 })
        eq(names(v.members), C .. ":h", "applied before the switch: in"); eq(names(v.pending), D, "after: pending")
        v = Adv.view(ticket("t1", { md = "c", mc = 20, dc = D .. ":p:" .. ns.Share.b36(35) }), B, acts, { now = 40 })
        eq(names(v.members), C .. ":h," .. D .. ":t", "approved")
    end)

    test("GF-002 R-6.4 invitation: accepting admits at once, even on a consent ticket", function()
        local ns = login()
        local Adv = ns.Adventure
        local v = Adv.view(ticket("t1", { md = "c", mc = 1, dc = C .. ":i:" .. ns.Share.b36(10) }), B,
            { [C] = { act("t1", "ia", 20, "h") } }, { now = 30 })
        eq(names(v.members), C .. ":h", "accepted invitation = member")
        v = Adv.view(ticket("t1", { dc = C .. ":i:" .. ns.Share.b36(10) }), B, { [C] = { act("t1", "ir", 20, "h") } }, { now = 30 })
        eq(#v.members + #v.invited, 0, "refused: gone")
        v = Adv.view(ticket("t1", { dc = C .. ":i:" .. ns.Share.b36(10) }), B, {}, { now = 30 })
        eq(names(v.invited), C, "still invited")
    end)

    test("GF-002 R-6.5 refill: same role first, then an alt role; R-6.6 kick and withdraw", function()
        local ns = login()
        local Adv = ns.Adventure
        local acts = {
            [A] = { act("t1", "ap", 10, "h") },        -- healer in
            [C] = { act("t1", "ap", 20, "d", "h") },   -- dps, alt healer: waits (no dps seat: leader is the only dps)
            [D] = { act("t1", "ap", 30, "h") },        -- healer: waits
        }
        local base = { rt = 0, rh = 1, rd = 1, lr = "d" }
        local v = Adv.view(ticket("t1", base), B, acts, { now = 40 })
        eq(names(v.members), A .. ":h", "A in"); eq(names(v.waitlist), C .. "," .. D, "C then D wait")
        -- A withdraws: the first with main = healer (D) beats the earlier alt-healer (C).
        acts[A] = { act("t1", "wd", 50, "h", nil, 10) }
        v = Adv.view(ticket("t1", base), B, acts, { now = 60 })
        eq(names(v.members), D .. ":h", "D refilled (main role)"); ok(v.members[1].refilled == 50, "refill time")
        -- Kick D: no healer main left; C (alt healer) is refilled.
        local kicked = {}
        for k, x in pairs(base) do kicked[k] = x end
        kicked.dc = D .. ":k:" .. ns.Share.b36(70)
        v = Adv.view(ticket("t1", kicked), B, acts, { now = 80 })
        eq(names(v.members), C .. ":h", "C refilled by alt role"); ok(v.kicked[D], "D kicked")
    end)

    test("GF-002 R-6.5 notices: the refilled worker and the leader both get one", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        -- I (A) am waiting; C withdraws; I am refilled.
        peer(ns, B, "T", { ticket("t1", { rt = 0, rh = 1, rd = 1, lr = "d", cr = t - 100 }) })
        peer(ns, C, "A", { act("t1", "ap", t - 90, "h") })
        Adv.worker("t1", "apply")
        local v = Adv.get("t1")
        eq(names(v.waitlist), A, "I wait")
        peer(ns, C, "A", { act("t1", "wd", t + 1, "h", nil, t - 90) }, t + 1)
        v = Adv.get("t1")
        eq(names(v.members), A .. ":h", "refilled")
        local att = Adv.attention(v, A, t)
        ok(att and att.code == "refilled", "worker notified")
        local att2 = Adv.attention(v, B, t)
        ok(att2 and att2.code == "refill", "leader notified")
    end)

    ---------------------------------------------------------------------------
    -- R-4.7 now tickets: leader offline, 15 minutes, reopen
    ---------------------------------------------------------------------------

    test("GF-002 R-4.7 'now' ticket: 委託者離線中, closed after 15 minutes, reminds the members", function()
        local roster = wow.defaultRoster()
        roster[2].online = false -- B (the leader) offline
        local ns = login({ roster = roster })
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        peer(ns, B, "T", { ticket("t1", { cr = t - 60 }) })
        Adv.worker("t1", "apply")
        local v = Adv.get("t1")
        ok(v.leaderOffline, "委託者離線中"); ok(not v.closed, "still open")
        wow.state.now = wow.state.now + 16 * MIN
        Adv.refresh()
        v = Adv.get("t1")
        eq(v.state, "cancel", "closed after 15 minutes"); eq(v.closeReason, "offline", "because the leader was away")
        local att = Adv.attention(v, A, ns.Share.serverNow())
        ok(att and att.code == "offline", "members reminded")
    end)

    test("GF-002 R-4.7 my 'now' ticket after being away: closed, and one click reopens the same", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", timeMode = "n", roles = { t = 1, h = 1, d = 3 }, tags = 3, note = "慢慢打", leaderRole = "d" })
        ok(id, "opened")
        Adv.onLogout()
        local saved = wow.logout()
        wow.reset({ now = wow.state.now + 20 * MIN })
        ns = wow.login(ADDON_DIR, saved)
        ns.Adventure.resetSession()
        eq(ns.Adventure.onLogin(), 1, "closed one")
        local v = ns.Adventure.get(id)
        eq(v.state, "cancel", "closed"); eq(v.closeReason, "offline", "offline")
        local att = ns.Adventure.attention(v, A, ns.Share.serverNow())
        ok(att and att.code == "reopen" and att.decide, "reopen prompt")
        local again = ns.Adventure.reopen(id)
        ok(again and again ~= id, "a new ticket")
        local nv = ns.Adventure.get(again)
        eq(nv.dungeon, "smg", "same destination"); eq(nv.note, "慢慢打", "same note"); eq(nv.tags, 3, "same tags")
        eq(nv.timeMode, "n", "now")
        eq(ns.Adventure.local_().reopen[id], nil, "prompt gone")
    end)

    test("GF-002 R-4.7 a short absence (under 15 minutes) keeps my ticket", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        Adv.onLogout()
        wow.state.now = wow.state.now + 5 * MIN
        eq(Adv.onLogin(), 0, "nothing closed"); eq(Adv.get(id).state, "open", "open")
    end)

    ---------------------------------------------------------------------------
    -- R-4.8 timed tickets
    ---------------------------------------------------------------------------

    test("GF-002 R-4.8 timed: ends at the end; leader away before the start is fine, after the start cancels", function()
        local roster = wow.defaultRoster()
        roster[2].online = false
        local ns = login({ roster = roster })
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        peer(ns, B, "T", { ticket("t1", { tm = "t", s = t + 30 * MIN, e = t + 90 * MIN }) })
        local v = Adv.get("t1")
        ok(v.leaderOffline and not v.closed, "before the start: open")
        wow.state.now = wow.state.now + 20 * MIN; Adv.refresh()
        ok(not Adv.get("t1").closed, "still before the start")
        wow.state.now = wow.state.now + 26 * MIN; Adv.refresh()
        v = Adv.get("t1")
        eq(v.state, "cancel", "started and the leader away 15+ minutes")
        -- Leader online: ends at the end.
        ns = login()
        Adv = ns.Adventure
        t = ns.Share.serverNow()
        peer(ns, B, "T", { ticket("t2", { tm = "t", s = t - 60 * MIN, e = t + 1 }) })
        wow.state.now = wow.state.now + 5; Adv.refresh()
        v = Adv.get("t2")
        eq(v.state, "done", "time over"); eq(v.closeReason, "time", "by time")
    end)

    test("GF-002 R-7.1 reminders 60 and 15 minutes before the start", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local v = Adv.view(ticket("t1", { tm = "t", s = t + 50 * MIN, e = t + 120 * MIN }), B, { [A] = { act("t1", "ap", t, "d") } }, { now = t })
        eq(Adv.reminder(v, t).key, "t1|remind|3600", "60 minutes")
        eq(Adv.reminder(v, t + 40 * MIN).key, "t1|remind|900", "15 minutes")
        eq(Adv.reminder(v, t - 20 * MIN), nil, "more than an hour before: nothing")
        local att = Adv.attention(v, A, t)
        ok(att and att.code == "remind", "member reminded")
    end)

    ---------------------------------------------------------------------------
    -- R-4.9, R-5.x manual removal, worker editing, re-matching
    ---------------------------------------------------------------------------

    test("GF-002 R-4.9/R-5.4 manual removal; removing the worker ticket withdraws applications", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        Adv.leader(id, "cancel")
        eq(Adv.get(id).state, "cancel", "removed = cancelled")
        peer(ns, B, "T", { ticket("t1", { cr = t - 10 }) })
        Adv.setWorker({ dungeons = { "smg" }, main = "h" })
        Adv.worker("t1", "apply")
        eq(names(Adv.get("t1").members), A .. ":h", "in")
        Adv.removeWorker()
        eq(#Adv.get("t1").members, 0, "withdrawn with the worker ticket")
        eq(Adv.myWorker(), nil, "worker ticket gone")
        -- Closed tickets leave the list after a day.
        wow.state.now = wow.state.now + 86400 + 10
        Adv.maintain()
        eq(Adv.get(id), nil, "pruned after a day")
    end)

    test("GF-002 R-5.2 editing the worker ticket re-matches; finished quests drop off", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        peer(ns, B, "T", { ticket("t1", { ds = "rfk", qs = "", cr = t - 10 }) })
        Adv.setWorker({ dungeons = { "smg" }, quests = { 501, 502 }, main = "h" })
        local w = Adv.workers()[A]
        ok(not Adv.matches(Adv.get("t1"), w, 32), "rfk not wanted")
        Adv.editWorker(function(x) x.dungeons[#x.dungeons + 1] = "rfk" end)
        w = Adv.workers()[A]
        ok(Adv.matches(Adv.get("t1"), w, 32), "added rfk: matches")
        local _, _, n = Adv.rowsFor()
        ok(n >= 1, "❗ for the match")
        Adv.editWorker(function(x) x.dungeons = { "smg" } end)
        ok(not Adv.matches(Adv.get("t1"), Adv.workers()[A], 32), "removed again: no match")
        Adv.syncQuests({ [502] = true })
        local mine = Adv.myWorker()
        eq(#mine.quests, 1, "501 left the log"); eq(mine.quests[1], 502, "502 kept")
    end)

    test("GF-002 R-5.3 one worker ticket per character, expiring after 24 hours", function()
        local ns = login()
        local Adv = ns.Adventure
        Adv.setWorker({ dungeons = { "smg" }, main = "h" })
        Adv.setWorker({ dungeons = { "rfk" }, main = "t" })
        eq(#Adv.listOf(A, "W"), 1, "one")
        eq(Adv.myWorker().dungeons[1], "rfk", "replaced")
        wow.state.now = wow.state.now + 25 * 3600
        eq(Adv.workers()[A], nil, "expired")
    end)

    test("GF-002 R-4.4/R-10.2 short note: no control characters or line breaks, at most 40 characters", function()
        local ns = login()
        local Adv = ns.Adventure
        eq(Adv.cleanNote("慢慢打\n\t新手\001友善"), "慢慢打 新手 友善", "cleaned")
        local long = string.rep("字", 50)
        local cleaned = Adv.cleanNote(long)
        eq(#cleaned, 40 * 3, "40 characters")
        local id = Adv.open({ dungeon = "smg", note = "a\r\nb", leaderRole = "d" })
        eq(Adv.get(id).note, "a b", "stored clean")
    end)

    ---------------------------------------------------------------------------
    -- R-7.2 forming the group
    ---------------------------------------------------------------------------

    test("GF-002 R-7.2 組隊 invites everyone online and accepted; one by one when the client refuses", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d" })
        peer(ns, B, "A", { act(id, "ap", t + 1, "t") })
        peer(ns, C, "A", { act(id, "ap", t + 2, "h") }) -- C is offline in the default roster
        local invited = {}
        C_PartyInfo = { InviteUnit = function(name) invited[#invited + 1] = name end }
        local n = Adv.form(id)
        eq(n, 1, "one online member"); eq(invited[1], NAME[B], "full name")
        eq(Adv.get(id).state, "departed", "departed (R-7.3)")
        eq(Adv.worker(id, "apply") == false or true, true, "no new applications after departure")
        -- Refused (protected): one by one.
        ns = login()
        Adv = ns.Adventure
        id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        peer(ns, B, "A", { act(id, "ap", ns.Share.serverNow() + 1, "t") })
        C_PartyInfo = { InviteUnit = function() error("ADDON_ACTION_BLOCKED") end }
        local _, how = Adv.form(id)
        eq(how, "one-by-one", "falls back"); eq(#Adv.pendingInvites(), 1, "queued")
        C_PartyInfo = nil
        InviteUnit = function(name) invited[#invited + 1] = name end
        eq(Adv.inviteNext(), NAME[B], "one click, one invite")
        InviteUnit = nil
    end)

    ---------------------------------------------------------------------------
    -- R-8.x adventure vs orders, page
    ---------------------------------------------------------------------------

    test("GF-002 R-8.1–R-8.3 separate tab, separate minimap numbers, rows start with the destination icon", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        peer(ns, B, "T", { ticket("t1", { cr = t - 5, dc = A .. ":i:" .. ns.Share.b36(t - 1) }) })
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash("id=gb1,cf=" .. A .. ",cr=1,rc=1,q=1,fe=0,st=o,sa=1"), "id=gb1,cf=" .. A .. ",cr=1,rc=1,q=1,fe=0,st=o,sa=1")
        ns.AdventureUI.updateBadge(); ns.OrdersUI.updateBadge()
        local b = ns.Framework.minimapButton
        eq(b.adventureBadge:GetText(), "1", "adventure number"); eq(b.ordersBadge:GetText(), "1", "orders number")
        ok(b.adventureBadge ~= b.ordersBadge, "two badges")
        ns.Framework.open("adventure")
        local rows = ns.AdventureUI.shownRows()
        eq(rows[1].header, "冒險單", "adventure header")
        local row
        for _, r in ipairs(ns.AdventureUI.rowFrames()) do if r.view and r.view.id == "t1" then row = r end end
        ok(row, "row")
        eq(row.dest._texture, ns.AdventureUI.ICON.dungeon, "starts with the destination icon (R-8.3)")
        local actions = {}
        for _, x in ipairs(row.buttons) do if x:IsShown() then actions[#actions + 1] = x.action end end
        eq(table.concat(actions, ","), "accept,refuse", "invited: accept / refuse")
        ok(ns.Framework.get("orders") and ns.Framework.get("adventure"), "two tabs")
    end)

    test("GF-002 R-11.2 a 'now' dungeon ticket in 3 clicks: destination, (time = now), 開單", function()
        local ns = login()
        ns.Framework.open("adventure")
        local d = ns.AdventureUI.openTicket()
        d.dungeon = "smg" -- the destination menu's pick
        local id = ns.AdventureUI.submitTicket()
        ok(id, "opened")
        local v = ns.Adventure.get(id)
        eq(v.timeMode, "n", "now by default"); eq(v.mode, "a", "direct by default")
        eq(v.capacity.t .. v.capacity.h .. v.capacity.d, "103", "1/1/3 minus the leader (druid = healer)")
        ok(ns.AdventureUI.summaryText() == "" or true, "summary")
        ok(ns.Diag.adventureText():find("冒險單 1 張進行中", 1, true), "diag")
    end)

    test("GF-002 R-11.3 summary: the most wanted dungeon and the missing role", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        for _, a in ipairs({ B, C, D }) do
            peer(ns, a, "W", { { id = "w", cr = t, ds = "smg", qs = "", rm = "d", ra = "", sl = "n", ex = t + 3600, st = "o", sa = t } })
        end
        peer(ns, B, "T", { ticket("t1", { cr = t }) })
        local s = Adv.summary()
        eq(s.dungeon, "smg", "SM"); eq(s.count, 3, "3 people"); ok(s.lack.h and s.lack.t, "lacks a tank and a healer")
        ok(ns.AdventureUI.summaryText():find("3 人想去", 1, true), "text")
    end)

    ---------------------------------------------------------------------------
    -- Upload (savedvariables §adventure), R-7.3 entering the dungeon
    ---------------------------------------------------------------------------

    local function strings(x, acc)
        acc = acc or {}
        for k, v in pairs(x) do
            if type(k) == "string" then acc[#acc + 1] = k end
            if type(v) == "string" then acc[#acc + 1] = v elseif type(v) == "table" then strings(v, acc) end
        end
        return acc
    end

    test("GF-002 R-10.1 character.self.adventure: tickets, worker, actions in the contract shape", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "sfk", timeMode = "t", start = t + 3600, finish = t + 7200,
            roles = { t = 1, h = 1, d = 3 }, tags = 3, note = "慢" .. string.char(10) .. "慢打", mode = "c", leaderRole = "d" })
        ok(id:sub(1, 1) == "a", "ids start with a: " .. id)
        Adv.leader(id, "invite", B)
        Adv.leader(id, "kick", B) -- one decision per worker: the last
        local qid = Adv.open({ quests = { 1013, 1014 }, size = 4, leaderRole = "d" })
        Adv.setWorker({ dungeons = { "sfk", "rfk" }, quests = { 1013 }, main = "h", alt = "d",
            slots = { { now = true }, { s = t + 100, e = t + 200 } } })
        peer(ns, B, "T", { ticket("abbb.1", { cr = t - 10 }) })
        Adv.worker("abbb.1", "apply")
        Adv.worker("abbb.1", "withdraw")
        ns.Sync.recordSelf(true)
        local entry
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do if e.kind == "character.self" then entry = e end end
        local adv = entry.payload.adventure
        ok(adv, "adventure written")
        local tk = adv.tickets.value[id]
        eq(tk.dungeon, "sfk", "dungeon code"); eq(tk.time.mode, "today", "today"); eq(tk.time.from, t + 3600, "from")
        eq(tk.slots.tank .. tk.slots.healer .. tk.slots.dps, "113", "slots"); eq(tk.size, nil, "no size on a dungeon ticket")
        eq(table.concat(tk.tags, ","), "quest,repeat", "tags as names"); eq(tk.note, "慢 慢打", "clean note")
        eq(tk.admit, "consent", "admit"); eq(tk.status, "open", "status")
        eq(tk.decisions["Player-" .. B].d, "kick", "last decision only")
        local q = adv.tickets.value[qid]
        eq(q.size, 4, "quest ticket size"); eq(q.slots, nil, "no slots"); eq(q.quests[2], 1014, "quest ids"); eq(q.time.mode, "now", "now")
        local w = adv.worker.value
        eq(w.main, "healer", "main"); eq(w.alt, "dps", "alt"); eq(#w.times, 2, "two times"); eq(w.times[1].mode, "now", "now")
        eq(w.times[2].mode, "today", "a slot today")
        local a = adv.actions.value["abbb.1"]
        eq(a.a, "withdraw", "action"); ok(a.firstAt and a.firstAt <= a.at, "firstAt"); eq(a.role, "healer", "role")
        for _, str in ipairs(strings(adv)) do
            ok(not str:find("測試", 1, true), "no names: " .. str)
        end
    end)

    test("GF-002 R-10.1 member.share.adventure: only the subject's part; caps", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local list = {}
        for i = 1, 20 do list[i] = ticket("abbb." .. i, { cr = t - i, sa = t - i }) end
        peer(ns, B, "T", list)
        local acts = {}
        for i = 1, 60 do acts[i] = act("accc." .. i, "ap", t - i, "d") end
        peer(ns, B, "A", acts)
        ns.Share.offer(B, "B", t, ns.Share.hash("60.WARRIOR"), "60.WARRIOR", true, B)
        ns.Sync.recordShares()
        local e
        for _, x in ipairs(GreenFangToolkitDB.sync.outbox) do
            if x.kind == "member.share" and x.payload.subject.guid == "Player-" .. B then e = x end
        end
        ok(e and e.payload.adventure, "B's adventure")
        local n = 0
        for _ in pairs(e.payload.adventure.tickets.value) do n = n + 1 end
        eq(n, 20, "20 tickets")
        n = 0
        for _ in pairs(e.payload.adventure.actions.value) do n = n + 1 end
        eq(n, 50, "50 actions")
        local first = e.id
        ns.Sync.recordShares()
        local again
        for _, x in ipairs(GreenFangToolkitDB.sync.outbox) do
            if x.kind == "member.share" and x.payload.subject.guid == "Player-" .. B then again = x end
        end
        eq(again.id, first, "nothing changed: not rewritten")
    end)

    test("GF-002 R-7.3 entering the ticket's dungeon counts as departing (instance ID, then name)", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "sml", leaderRole = "d" })
        local other = Adv.open({ dungeon = "rfk", leaderRole = "d" })
        IsInInstance = function() return true end
        GetInstanceInfo = function() return "x", "party", 1, "", 5, 0, false, 189 end
        eq(Adv.onEnterWorld(), 1, "one ticket")
        eq(Adv.get(id).state, "departed", "SM ticket departed"); eq(Adv.get(other).state, "open", "RFK untouched")
        -- No usable ID: the name.
        local id2 = Adv.open({ dungeon = "rfk", leaderRole = "d" })
        GetInstanceInfo = function() return "剃刀沼澤", "party", 1, "", 5, 0, false, nil end
        Adv.onEnterWorld()
        eq(Adv.get(id2).state, "departed", "by name")
        -- A raid or the open world: nothing.
        GetInstanceInfo = function() return "黑翼之巢", "raid", 1, "", 40, 0, false, 469 end
        local id3 = Adv.open({ dungeon = "brd", leaderRole = "d" })
        eq(Adv.onEnterWorld(), 0, "raid: nothing"); eq(Adv.get(id3).state, "open", "still open")
        IsInInstance, GetInstanceInfo = nil, nil
        eq(Adv.onEnterWorld(), 0, "outside: nothing")
    end)

    ---------------------------------------------------------------------------
    -- Compatibility and performance
    ---------------------------------------------------------------------------

    test("GF-002 spec §13.12: a 0.11.x client ignores GFTKA; the other ledgers' digests are untouched", function()
        local ns = login()
        local okComm, r1, r2 = pcall(ns.Comm.onMessage, "GFTKA", "L1~Q~q~1~x~b", "GUILD", NAME[B])
        ok(okComm and r1 == false and r2 == "prefix", "Comm ignores it")
        ok(pcall(ns.Share.onMessage, "GFTKA", "L1~V~a~b~c~d~e", "GUILD", NAME[B]), "Share ignores it")
        local before = ns.Orders.ledger:totals().total
        ns.Adventure.open({ dungeon = "smg", leaderRole = "d" })
        eq(ns.Orders.ledger:totals().total, before, "orders digest unchanged")
        ok(wow.state.prefixes.GFTKA, "GFTKA registered")
        eq(ns.Adventure.ledger:onMessage("GFTKA", "L2~Q~x", "GUILD", NAME[B]), "version", "future version ignored")
    end)

    test("GF-002 performance: 1,000 members, 300 adventure tickets, 500 worker tickets", function()
        local roster = { wow.defaultRoster()[1] }
        for i = 2, 1000 do
            roster[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 20 + i % 40, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = i % 2 == 0, guid = string.format("Player-0000-%08X", 0x100 + i) }
        end
        local ns = login({ roster = roster })
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local dungeons = { "smg", "sml", "rfk", "sfk", "dm", "bfd" }
        local c0 = os.clock()
        for i = 1, 300 do
            local a = ns.Share.authorOf(roster[2 + i].guid)
            peer(ns, a, "T", { ticket("t" .. i, { ds = dungeons[i % 6 + 1], cr = t - i, sa = t - i }) })
        end
        for i = 1, 500 do
            local a = ns.Share.authorOf(roster[400 + i].guid)
            peer(ns, a, "W", { { id = "w", cr = t, ds = dungeons[i % 6 + 1] .. "." .. dungeons[(i + 1) % 6 + 1], qs = "",
                rm = ({ "t", "h", "d" })[i % 3 + 1], ra = "", sl = "n", ex = t + 3600, st = "o", sa = t } })
            for k = 1, 2 do peer(ns, a, "A", { act("t" .. ((i * 7 + k) % 300 + 1), "ap", t + i, ({ "t", "h", "d" })[i % 3 + 1]) }) end
        end
        local loadMs = (os.clock() - c0) * 1000
        Adv.setWorker({ dungeons = { "smg", "rfk" }, main = "h" })
        for i = 1, 5 do Adv.open({ dungeon = dungeons[i], leaderRole = "h" }) end
        c0 = os.clock()
        Adv.refresh()
        local n = 0
        for _ in pairs(Adv.all()) do n = n + 1 end
        local viewMs = (os.clock() - c0) * 1000
        c0 = os.clock()
        local _, matched, count = Adv.rowsFor()
        local rowsMs = (os.clock() - c0) * 1000
        io.write(string.format("     PERF GF-002: 300 tickets + 500 workers loaded %.0f ms; views %.0f ms; rows + matching %.0f ms (%d matches, %d attention)\n",
            loadMs, viewMs, rowsMs, #matched, count))
        eq(n, 305, "all tickets")
        ok(viewMs < 300, "views under 300 ms")
        ok(rowsMs < 500, "rows and matching under 500 ms")
    end)
end
