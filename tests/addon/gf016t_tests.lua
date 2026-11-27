-- GF-016-T: the adventure upload for upload-api v1.6 (§3 item 11, §4a, §8).
--   T1 log records carry at        T2 log records carry by (leader / seen)
--   T3 a step back keeps a revoked record (at = the step back)
--   T4 reopenOf on 重開 is a new event revision (correction)
--   T5 deleteTicket sends adventure.removed (owner); clearEnded sends nothing (owner 2026-11-27)
--   T6 one revision per ticket, shared by tickets and log, +1 only on a real change
--   T7 a member's event destination is checked here (quest ids, dungeon code, zone)
-- Old saves (no rv / by) load and upload without made-up fields.
-- Offline only; made-up names only. Run alone: run_lupa.py --only gf016t

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local H, DAY = 3600, 86400

    local lastAt = {}
    local function login(saved)
        for k in pairs(lastAt) do lastAt[k] = nil end
        wow.reset()
        local ns = wow.login(ADDON_DIR, saved)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local k = a .. g
        local at = math.max(t or ns.Share.serverNow(), (lastAt[k] or 0) + 1)
        lastAt[k] = at
        local r = ns.Adventure.ledger:offer(a, g, at, ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    local function apply(ns, author, id, t, role)
        return offer(ns, author, "A", { { id = id, ac = "ap", at = t, ap = t, ak = "ap", ro = role, rb = "" } }, t)
    end
    local function mine(ns, id)
        for _, e in ipairs(ns.Adventure.listOf(A, "T")) do if e.id == id then return e end end
    end
    -- My 成團 ticket: B takes the tank seat of a two-seat dungeon ticket.
    local function formed(ns)
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, ns.Share.serverNow(), "t")
        ok(Adv.get(id).formed, "formed")
        return id
    end
    local function upMine(ns) return ns.Adventure.uploadFor(A) end

    ---------------------------------------------------------------------------
    -- T1 / T2 / T6
    ---------------------------------------------------------------------------

    test("gf016t T1/T2/T6 成行: the log record has at, by = leader and the ticket's revision", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = formed(ns)
        local rvFormed = mine(ns, id).rv
        ok(rvFormed and rvFormed >= 1, "a new ticket has a revision")
        wow.advance(30)
        local t = ns.Share.serverNow()
        ok(Adv.leader(id, "done"), "done")
        eq(mine(ns, id).rv, rvFormed + 1, "成行: one more")
        local up = upMine(ns)
        local r, tk = up.log.value[id], up.tickets.value[id]
        eq(r.status, "done", "done"); eq(r.at, t, "at (T1)"); eq(r.by, "leader", "by (T2)")
        eq(r.revision, rvFormed + 1, "revision (T6)"); eq(tk.revision, r.revision, "one sequence with the ticket")
        eq(r.doneAt, t, "doneAt unchanged")
    end)

    test("gf016t T6 nothing changed: no new revision; an edit is one", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        eq(mine(ns, id).rv, 1, "starts at 1")
        Adv.leader(id, "mode", "a") -- already auto: the same record
        eq(mine(ns, id).rv, 1, "same contents: still 1")
        Adv.maintain()
        eq(mine(ns, id).rv, 1, "upkeep with nothing to do: still 1")
        Adv.leader(id, "mode", "c")
        eq(mine(ns, id).rv, 2, "a change: 2")
        Adv.leader(id, "mode", "c")
        eq(mine(ns, id).rv, 2, "again the same: 2")
    end)

    ---------------------------------------------------------------------------
    -- T3 and the same-second step back
    ---------------------------------------------------------------------------

    test("gf016t T3 退回: the record stays as revoked at the step back, with a higher revision", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = formed(ns)
        Adv.leader(id, "done")
        local rvDone = mine(ns, id).rv
        wow.advance(60)
        local tb = ns.Share.serverNow()
        ok(Adv.leader(id, "back"), "back")
        eq(#Adv.myLog(), 1, "kept"); eq(Adv.logCount(), 0, "not counted as 成行")
        local up = upMine(ns)
        local r = up.log.value[id]
        eq(r.status, "revoked", "revoked"); eq(r.at, tb, "at = the step back"); eq(r.by, "leader", "by")
        eq(r.doneAt, nil, "no doneAt"); eq(r.auto, nil, "no auto")
        eq(r.revision, rvDone + 1, "next revision"); eq(up.tickets.value[id].revision, r.revision, "same as the ticket")
        eq(up.tickets.value[id].status, "open", "ticket open again")
        ok(#r.members >= 2, "the members of the revoked one")
        -- Ages out with the log: 30 days.
        wow.state.now = wow.state.now + 31 * DAY
        eq(#Adv.pruneLog(Adv.myLog()), 0, "gone after 30 days")
    end)

    test("gf016t T3/T6 the same second: 成行, 退回, 成行 again order by revision", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = formed(ns)
        local t = ns.Share.serverNow()
        Adv.leader(id, "done")
        local r1 = upMine(ns).log.value[id]
        Adv.leader(id, "back")
        local r2 = upMine(ns).log.value[id]
        Adv.leader(id, "done")
        local up = upMine(ns)
        local r3 = up.log.value[id]
        eq(ns.Share.serverNow(), t, "all in one second")
        eq(r1.status, "done"); eq(r2.status, "revoked"); eq(r3.status, "done")
        eq(r1.at, r2.at, "same at"); eq(r2.at, r3.at, "same at")
        ok(r1.revision < r2.revision and r2.revision < r3.revision, "revisions order them: "
            .. r1.revision .. "<" .. r2.revision .. "<" .. r3.revision)
        eq(up.tickets.value[id].revision, r3.revision, "the ticket is at the last one")
        eq(Adv.logCount(), 1, "one 成行")
    end)

    test("gf016t T3 another leader's ticket stepped back (bk): revoked from its entry, its revision", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.7", src = "g", ver = 1, cr = t - 300, ds = "rfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "t", tg = 0, md = "a", st = "o", sa = t - 20, bk = t - 20, ff = t - 20, fx = 1, fm = t - 200,
            mb = B .. ":t;" .. C .. ":h", rv = 4 } }, t)
        local up = Adv.uploadFor(B)
        local r = up.log.value["abbb.7"]
        eq(r.status, "revoked", "revoked"); eq(r.at, t - 20, "at = bk"); eq(r.revision, 4, "its revision"); eq(r.by, "leader", "by")
        eq(up.tickets.value["abbb.7"].revision, 4, "ticket revision")
    end)

    ---------------------------------------------------------------------------
    -- Old saves
    ---------------------------------------------------------------------------

    test("gf016t old data: no rv / by stays without them; at stays as written; nothing made up", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        -- An old (0.16.12) ticket of B, done, no rv.
        offer(ns, B, "T", { { id = "abbb.9", src = "g", ver = 1, cr = t - 100, ds = "rfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "t", tg = 0, md = "a", st = "c", sa = t - 10, fx = 1, fm = t - 50, mb = B .. ":t;" .. C .. ":h" } }, t)
        local up = Adv.uploadFor(B)
        eq(up.tickets.value["abbb.9"].revision, nil, "no revision on an old ticket")
        local r = up.log.value["abbb.9"]
        eq(r.revision, nil, "no revision in its log"); eq(r.at, t - 10, "at = its status time"); eq(r.status, "done", "done")
        -- My log as 0.16.12 wrote it: no by, no rv.
        Adv.local_().log[A] = { { id = "aaaa.1", ds = "rfk", fs = t - 900, fm = t - 800, dn = t - 700, at = t - 700, st = "done",
            mb = A .. ":d;" .. B .. ":t" } }
        local mup = upMine(ns)
        local m = mup.log.value["aaaa.1"]
        eq(m.at, t - 700, "at"); eq(m.by, nil, "no by made up"); eq(m.revision, nil, "no revision made up")
        eq(mup.removed, nil, "no removed without deletes")
        eq(Adv.logCount(), 1, "counted")
    end)

    test("gf016t old data: a ticket saved without rv gets 1 on its first change, not before", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        -- As 0.16.12 left it: no rv.
        local list = Adv.listOf(A, "T")
        for _, e in ipairs(list) do e.rv = nil end
        Adv.ledger:put("T", Adv.encodeList(list)); Adv.refresh()
        eq(mine(ns, id).rv, nil, "no rv")
        Adv.maintain()
        eq(mine(ns, id).rv, nil, "nothing changed: still none")
        Adv.leader(id, "mode", "c")
        eq(mine(ns, id).rv, 1, "first change: 1")
    end)

    test("gf016t old save file: a 0.16.12 adventure table loads and uploads", function()
        wow.reset()
        local t0 = wow.state.now
        local saved = { GreenFangToolkitDB = { addonVersion = "0.16.12", adventure = { log = { [A] = { { id = "aaaa.2", ds = "wc",
            fm = t0 - 300, dn = t0 - 200, at = t0 - 200, st = "done", mb = A .. ":d" } } }, seen = {}, reopen = {}, deleted = {} } } }
        local ns = login(saved)
        local up = ns.Adventure.uploadFor(A)
        local r = up and up.log and up.log.value["aaaa.2"]
        ok(r, "uploaded"); eq(r.by, nil, "no by"); eq(r.revision, nil, "no revision"); eq(r.at, t0 - 200, "at")
        eq(up.removed, nil, "no removed")
        eq(GreenFangToolkitDB.adventure.removed, nil, "no new empty table in the save")
    end)

    ---------------------------------------------------------------------------
    -- Two computers (mergeSelf)
    ---------------------------------------------------------------------------

    test("gf016t T6 another computer of mine: the higher revision wins; same revision, different: next one", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local e = mine(ns, id)
        local t = ns.Share.serverNow()
        -- Higher revision with an earlier sa: taken.
        local other = {}
        for k, v in pairs(e) do other[k] = v end
        other.rv, other.sa, other.nt = 5, (e.sa or t) - 50, "from B pc"
        ok(Adv.mergeSelf("T", Adv.encodeList({ other })), "merged")
        eq(mine(ns, id).rv, 5, "rv 5"); eq(mine(ns, id).nt, "from B pc", "its contents")
        -- Lower revision with a later sa: ignored.
        local older = {}
        for k, v in pairs(other) do older[k] = v end
        older.rv, older.sa, older.nt = 4, t + 100, "stale"
        eq(Adv.mergeSelf("T", Adv.encodeList({ older })), false, "nothing taken")
        eq(mine(ns, id).nt, "from B pc", "kept")
        -- Same revision, different contents: the later sa wins and moves to 6.
        local same = {}
        for k, v in pairs(other) do same[k] = v end
        same.sa, same.nt = (other.sa or t) + 10, "later"
        ok(Adv.mergeSelf("T", Adv.encodeList({ same })), "merged")
        eq(mine(ns, id).rv, 6, "next revision"); eq(mine(ns, id).nt, "later", "the later one")
    end)

    ---------------------------------------------------------------------------
    -- T4
    ---------------------------------------------------------------------------

    test("gf016t T4 重開: reopenOf is a correction, revision 2, queued again", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local old = Adv.open({ dungeon = "smg", leaderRole = "d" })
        Adv.leader(old, "cancel")
        local new = Adv.reopen(old)
        local ev = E.get(table.concat({ new, "adventure_created" }, "|"))
        ok(ev, "created event")
        eq(ev.reopenOf, old, "reopenOf"); eq(ev.revision, 2, "revision 2"); eq(ev.change, "correction", "correction")
        ok(ev.revisedAt, "revisedAt"); eq(ev.status, "active", "active")
        local s = E.state(false)
        eq(s.queue[ev.eventID].rev, 2, "queued at revision 2")
        -- Once only: a second call changes nothing.
        E.onReopen(old, new)
        eq(ev.revision, 2, "still 2")
    end)

    ---------------------------------------------------------------------------
    -- T7
    ---------------------------------------------------------------------------

    test("gf016t T7 a forwarded destination is checked: quest ids, count, dungeon code, zone", function()
        local ns = login()
        local E = ns.Events
        local a, d = E.destination({ quests = { "12", "abc", "0", "-3", "10000000", "5", "1.5", "6", "7", "8", "9" } })
        eq(a, "quest"); eq(d, "q:12.5.6.7.8", "whole numbers 1-9,999,999, at most 5")
        a, d = E.destination({ quests = { "x", "0" } })
        eq(a, "other", "none left: other"); eq(d, nil)
        a, d = E.destination({ dungeon = "BAD!" })
        eq(a, "other", "bad code: other"); eq(d, nil)
        a, d = E.destination({ dungeon = "abcdefghijklm" })
        eq(a, "other", "13 characters: other")
        a, d = E.destination({ dungeon = "rfk" })
        eq(a, "dungeon"); eq(d, "rfk", "a good code")
        a, d = E.destination({ zone = "  西部\1荒野  " })
        eq(a, "zone"); eq(d, "z:西部 荒野", "control characters out")
        a, d = E.destination({ zone = string.rep("界", 60) })
        eq(d, "z:" .. string.rep("界", 40), "40 characters")
    end)

    ---------------------------------------------------------------------------
    -- T5
    ---------------------------------------------------------------------------

    test("gf016t T5 刪除: adventure.removed (owner), kept 30 days; 清除已結束: none, earlier ones stay", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local t = ns.Share.serverNow()
        ok(Adv.deleteTicket(id), "deleted")
        local up = upMine(ns)
        ok(up and up.removed, "removed sent")
        eq(up.removed.value[id].why, "owner", "owner"); eq(up.removed.value[id].at, t, "at")
        -- 清除已結束: only this computer; no removed for the ended ticket or its log record.
        local id2 = formed(ns)
        Adv.leader(id2, "done")
        local n, logN = Adv.clearEnded()
        ok(n >= 1 and logN >= 1, "cleared here")
        up = upMine(ns)
        eq(up.removed.value[id2], nil, "清除已結束 sends no removed")
        eq(up.removed.value[id].why, "owner", "the 刪除 one stays")
        local count = 0
        for _ in pairs(up.removed.value) do count = count + 1 end
        eq(count, 1, "only the 刪除 one")
        -- Not in another leader's upload.
        eq((Adv.uploadFor(B) or {}).removed, nil, "only mine")
        wow.state.now = wow.state.now + 31 * DAY
        up = upMine(ns)
        eq(up and up.removed, nil, "gone after 30 days")
    end)

    test("gf016t T5 清除已結束 alone: nothing sent, no removed table in the save", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = formed(ns)
        Adv.leader(id, "done")
        Adv.clearEnded()
        eq((upMine(ns) or {}).removed, nil, "no removed")
        eq(GreenFangToolkitDB.adventure.removed, nil, "no table")
    end)

    ---------------------------------------------------------------------------
    -- The upload still goes (GF Sync 0.1.0 passes character.self as written)
    ---------------------------------------------------------------------------

    test("gf016t character.self carries the new fields", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = formed(ns)
        Adv.leader(id, "done")
        ns.Sync.recordSelf(true)
        local entry
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do if e.kind == "character.self" then entry = e end end
        ok(entry, "character.self written")
        local r = entry.payload.adventure.log.value[id]
        ok(r.at and r.by == "leader" and r.revision, "at / by / revision")
    end)
end
