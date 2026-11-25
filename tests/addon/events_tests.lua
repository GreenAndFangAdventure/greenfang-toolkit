-- GF-013 (docs/spec/GFTK_Master_Spec_v2.0.md §9.1, §12.2): the background
-- event record. Dedup (one 成行 per adventure and character, step back /
-- reopen / resend / repeated match never count twice), revocation and
-- restore with versions, the paths (leader / worker_match / direct_signup),
-- personal evidence, 候補 / 取消 / 測試 / 團本, the bounded queue (confirm,
-- resend, capacity) and that the 30-day / 50-record log is left alone.
-- Made-up data only (the mock's 測試甲 is me, author A).

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local H, MIN = 3600, 60

    local lastAt = {}
    local function login(opts)
        for k in pairs(lastAt) do lastAt[k] = nil end
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
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
    -- Someone else's ticket (one 現在 slot): fields override the defaults.
    local function ticket(ns, leader, id, t, extra)
        local e = { id = id, src = "g", ver = 1, cr = t, ds = "smg", qs = "",
            ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = t } }), tm = "n",
            rt = 1, rh = 1, rd = 3, md = "a", lr = "d", st = "o", sa = t }
        for k, v in pairs(extra or {}) do e[k] = v end
        offer(ns, leader, "T", { e }, t)
        return e
    end
    -- Change my own A record (what checkAuto writes: dt / fp) without the game.
    local function setMine(ns, id, fields)
        local list = ns.Adventure.listOf(A, "A")
        for _, e in ipairs(list) do if e.id == id then for k, v in pairs(fields) do e[k] = v end end end
        ns.Adventure.ledger:put("A", ns.Adventure.encodeList(list))
        ns.Adventure.refresh()
    end
    local function events(ns, adv, ty)
        local out = {}
        local s = ns.Events.state(false)
        for _, ev in pairs(s and s.events or {}) do
            if (not adv or ev.adventureID == adv) and (not ty or ev.eventType == ty) then out[#out + 1] = ev end
        end
        return out
    end
    local function one(ns, adv, ty)
        local list = events(ns, adv, ty)
        eq(#list, 1, "one " .. ty)
        return list[1]
    end
    local function count(ns) local s = ns.Events.state(false); return s and s.n or 0 end

    ---------------------------------------------------------------------------
    -- Leader: created -> finalized -> formed -> done; step back revokes, again restores
    ---------------------------------------------------------------------------

    test("GF-013 §9.1 leader events: created, finalized, formed, done; a step back revokes, done again restores the same event", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        eq(ns.db.events, nil, "nothing written before the first event")
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        local cr = one(ns, id, "adventure_created")
        eq(cr.participationPath, "leader", "leader path"); eq(cr.activityType, "dungeon", "dungeon"); eq(cr.destinationID, "smg", "destination")
        eq(cr.originGUID, "Player-" .. A, "origin = me"); eq(cr.participantGUID, "Player-" .. A, "participant = me")
        eq(cr.schemaVersion, 1, "schemaVersion"); eq(cr.revision, 1, "revision 1"); eq(cr.status, "active", "active")
        apply(ns, B, id, t + 1, "t")
        Adv.maintain()
        eq(Adv.get(id).state, "formed", "full -> 成團")
        one(ns, id, "adventure_finalized"); one(ns, id, "adventure_formed")
        eq(#events(ns, id, "adventure_done"), 0, "not done yet")
        ok(Adv.leader(id, "done"), "完成")
        local done = one(ns, id, "adventure_done")
        local mine = one(ns, id, "participant_done")
        eq(done.evidence, "leader_done", "evidence: the leader's 完成"); eq(mine.participationPath, "leader", "my 成行 as leader")
        local doneID, n = done.eventID, count(ns)
        eq(E.summary().leader.done, 1, "one 成行"); eq(E.summary().participations, 1, "one participation")
        -- R-17.7 step back: 成行 -> 成團; the done events are revoked (a new revision), nothing new.
        ok(Adv.leader(id, "back"), "back")
        eq(Adv.get(id).state, "formed", "成團 again")
        eq(done.status, "revoked", "revoked"); eq(done.revision, 2, "revision 2"); eq(done.change, "revocation", "a revocation")
        eq(mine.status, "revoked", "my participation revoked too")
        eq(E.summary().leader.done, 0, "not counted while stepped back"); eq(E.summary().participations, 0, "no participation")
        eq(count(ns), n, "no new event")
        ok(Adv.leader(id, "done"), "完成 again")
        eq(one(ns, id, "adventure_done").eventID, doneID, "the same event")
        eq(done.status, "active", "restored"); eq(done.revision, 3, "revision 3"); eq(done.change, "restore", "a restore")
        eq(done.observedAt, mine.observedAt, "observedAt kept from the first time")
        eq(E.summary().leader.done, 1, "still one 成行"); eq(E.summary().participations, 1, "still one participation")
        -- Observing again (every minute) changes nothing.
        local before = done.revision
        for _ = 1, 3 do Adv.maintain() end
        eq(done.revision, before, "no new revision"); eq(count(ns), n, "no new event")
        -- One queue entry per event (its latest revision): a resend never duplicates.
        local pending = E.pending()
        local seen = {}
        for _, p in ipairs(pending) do ok(not seen[p.eventID], "one entry per event"); seen[p.eventID] = true end
        local qd
        for _, p in ipairs(pending) do if p.eventID == doneID then qd = p end end
        eq(qd.revision, 3, "the queue holds revision 3")
        -- Back to 已定案 / 招募中 revokes 成團 (and 定案 on a multi-slot ticket).
        local id2 = Adv.open({ dungeon = "sfk", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d",
            slots = { { s = t + 26 * H, d = 2 * H }, { s = t + 50 * H } } })
        Adv.leader(id2, "finalize", 1)
        eq(one(ns, id2, "adventure_finalized").status, "active", "定案")
        Adv.leader(id2, "back")
        eq(one(ns, id2, "adventure_finalized").status, "revoked", "定案 stepped back")
        Adv.leader(id2, "finalize", 2)
        local fin = one(ns, id2, "adventure_finalized")
        eq(fin.status, "active", "定案 again: the same event"); eq(fin.revision, 3, "revision 3")
    end)

    test("GF-013 §9.1 cancel / expired / unfinished are their own events; none of them counts as 成行", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local c = Adv.open({ dungeon = "smg", leaderRole = "d" })
        apply(ns, B, c, t + 1, "t")
        Adv.leader(c, "cancel")
        one(ns, c, "adventure_cancelled")
        eq(#events(ns, c, "adventure_done"), 0, "取消 is not 成行")
        local x = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { s = t + 60 } } })
        wow.state.now = wow.state.now + 31 * MIN + 60; Adv.refresh()
        Adv.maintain()
        eq(one(ns, x, "adventure_expired").evidence, "time", "過期 by time")
        local u = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d", slots = { { s = ns.Share.serverNow() + H, d = 2 * H } } })
        apply(ns, B, u, ns.Share.serverNow() + 2, "t")
        wow.state.now = wow.state.now + 28 * H; Adv.refresh()
        Adv.maintain()
        eq(Adv.get(u).state, "unfinished", "成團未成行")
        one(ns, u, "adventure_unfinished")
        eq(one(ns, u, "adventure_formed").status, "active", "it did form")
        eq(#events(ns, u, "participant_done"), 0, "未成行 is not 成行")
        local sm = E.summary()
        eq(sm.leader.cancelled .. "/" .. sm.leader.expired .. "/" .. sm.leader.unfinished .. "/" .. sm.leader.done, "1/1/1/0", "counts")
        eq(sm.participations, 0, "no participation")
        ok(E.diagText():find("取消 1", 1, true), "diagnostics: " .. E.diagText())
    end)

    ---------------------------------------------------------------------------
    -- Direct signup and worker match: paths, evidence, 候補, dedup across paths
    ---------------------------------------------------------------------------

    test("GF-013 §9.1 direct signup: applied, admitted, 成行 only with my own evidence; 候補 never counts", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        ticket(ns, B, "b1", t)
        ok(Adv.worker("b1", "apply"), "I apply")
        eq(one(ns, "b1", "signup_applied").participationPath, "direct_signup", "applied directly")
        local adm = one(ns, "b1", "participant_admitted")
        eq(adm.participationPath, "direct_signup", "admitted directly"); eq(adm.role, "h", "my role (druid: heal)")
        -- The leader writes 完成; I have no evidence of my own: not counted (unknown is not 成行).
        ticket(ns, B, "b1", t, { st = "c", sa = t + 30 * MIN })
        eq(Adv.get("b1").state, "done", "成行 for the ticket")
        Adv.maintain()
        eq(#events(ns, "b1", "participant_done"), 0, "no evidence: no 成行 for me")
        eq(E.queueStats().noEvidence, 1, "counted once as 無證據")
        Adv.maintain()
        eq(E.queueStats().noEvidence, 1, "still once")
        -- My own detection inside the window: now it counts.
        setMine(ns, "b1", { dt = t + 20 * MIN })
        Adv.maintain()
        local d = one(ns, "b1", "participant_done")
        eq(d.evidence, "self_detected", "my own detection"); eq(d.participationPath, "direct_signup", "direct")
        eq(E.summary().direct.done, 1, "直接報名成行 1"); eq(E.summary().worker.completed, 0, "not a worker order")
        -- 候補: a full ticket, I wait; it is done (even with my detection): nothing.
        ticket(ns, C, "c1", t, { rt = 0, rh = 1, rd = 0 })
        apply(ns, D, "c1", t + 1, "h")
        wow.state.now = wow.state.now + MIN
        ok(Adv.worker("c1", "apply"), "I apply to a full ticket")
        eq(#Adv.get("c1").waitlist, 1, "I am on the waitlist")
        eq(#events(ns, "c1", "participant_admitted"), 0, "候補 is not admitted")
        setMine(ns, "c1", { dt = t + 5 * MIN })
        ticket(ns, C, "c1", t, { rt = 0, rh = 1, rd = 0, st = "c", sa = t + 10 * MIN })
        Adv.maintain()
        eq(#events(ns, "c1", "participant_done"), 0, "候補 never 成行")
        eq(E.summary().participations, 1, "only b1")
    end)

    test("GF-013 §9.1 worker match: created once, matched once per order and ticket, admitted and 接單完成 by worker_match", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        ok(Adv.setWorker({ dungeons = { "smg" }, main = "h" }), "my worker ticket")
        local created = one(ns, nil, "worker_order_created")
        local order = created.workerOrderID
        ok(order and order:match("^w"), "a worker order id: " .. tostring(order))
        Adv.editWorker(function(w) w.dungeons = { "smg", "sfk" } end)
        eq(#events(ns, nil, "worker_order_created"), 1, "an edit is the same order")
        -- The leader invites me (from the match list).
        local dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 1 } })
        ticket(ns, B, "b2", t, { dc = dc })
        Adv.maintain()
        local m = one(ns, "b2", "worker_order_matched")
        eq(m.workerOrderID, order, "matched on my order")
        wow.state.now = wow.state.now + MIN
        ok(Adv.worker("b2", "accept"), "I accept")
        local adm = one(ns, "b2", "participant_admitted")
        eq(adm.participationPath, "worker_match", "admitted by the match"); eq(adm.workerOrderID, order, "with my order")
        -- Kicked, invited again, accepted again: still one match, one admission.
        local kAt = ns.Share.serverNow() + 1
        ticket(ns, B, "b2", t, { dc = Adv.encodeDecisions({ { a = A, k = "k", t = kAt } }) })
        wow.state.now = wow.state.now + MIN
        Adv.maintain()
        eq(#Adv.get("b2").members, 0, "kicked")
        local iAt = ns.Share.serverNow() + 1
        local dc2 = Adv.encodeDecisions({ { a = A, k = "i", t = iAt } })
        ticket(ns, B, "b2", t, { dc = dc2 })
        wow.state.now = wow.state.now + MIN
        ok(Adv.worker("b2", "accept"), "accepted again")
        eq(#Adv.get("b2").members, 1, "in again")
        Adv.maintain()
        eq(#events(ns, "b2", "worker_order_matched"), 1, "the same order and ticket: one match")
        eq(#events(ns, "b2", "participant_admitted"), 1, "one admission")
        -- 成行 with my party evidence (fp after 定案).
        local v = Adv.get("b2")
        setMine(ns, "b2", { fp = (v.finalAt or t) + 60 })
        ticket(ns, B, "b2", t, { dc = dc2, st = "c", sa = ns.Share.serverNow() + 60 })
        Adv.maintain()
        local d = one(ns, "b2", "participant_done")
        eq(d.participationPath, "worker_match", "接單完成"); eq(d.evidence, "self_party", "party evidence"); eq(d.workerOrderID, order, "the order")
        local sm = E.summary()
        eq(sm.worker.created .. "/" .. sm.worker.matched .. "/" .. sm.worker.admitted .. "/" .. sm.worker.completed, "1/1/1/1", "worker counts")
        eq(sm.leader.done, 0, "開單 counted apart: I led nothing"); eq(sm.direct.done, 0, "not direct")
        eq(sm.participations, 1, "one participation")
        -- Removing the worker ticket ends the order; a new one is a new order.
        Adv.removeWorker()
        Adv.setWorker({ dungeons = { "smg" }, main = "h" })
        eq(#events(ns, nil, "worker_order_created"), 2, "a new worker ticket: a new order")
    end)

    test("GF-013 §9.1 the same adventure, two paths (applied, then invited): one 成行 in the total", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        Adv.setWorker({ dungeons = { "smg" }, main = "h" })
        ticket(ns, B, "b3", t)
        Adv.worker("b3", "apply")
        Adv.worker("b3", "withdraw")
        ticket(ns, B, "b3", t, { dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 10 } }) })
        wow.state.now = wow.state.now + MIN
        Adv.worker("b3", "accept")
        setMine(ns, "b3", { dt = t + 15 * MIN })
        ticket(ns, B, "b3", t, { dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 10 } }), st = "c", sa = t + 20 * MIN })
        Adv.maintain(); Adv.maintain()
        eq(#events(ns, "b3", "participant_done"), 1, "one 成行 event for this adventure")
        eq(E.summary().participations, 1, "one in the total")
        -- A step back by the leader revokes it; the same 成行 again does not count twice.
        ticket(ns, B, "b3", t, { dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 10 } }), st = "o", sa = t + 25 * MIN, bk = t + 25 * MIN, ff = t + 25 * MIN })
        Adv.maintain()
        eq(one(ns, "b3", "participant_done").status, "revoked", "stepped back: revoked")
        eq(E.summary().participations, 0, "not counted")
        setMine(ns, "b3", { dt = t + 30 * MIN })
        ticket(ns, B, "b3", t, { dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 10 } }), st = "c", sa = t + 35 * MIN, bk = t + 25 * MIN })
        Adv.maintain()
        eq(#events(ns, "b3", "participant_done"), 1, "still one event")
        eq(one(ns, "b3", "participant_done").revision, 3, "restored as revision 3")
        eq(E.summary().participations, 1, "one")
    end)

    ---------------------------------------------------------------------------
    -- 團本, test builds, reopen
    ---------------------------------------------------------------------------

    test("GF-013 §9.1 raids: only created / applied, never finalized, formed or done", function()
        local ns = login()
        local Adv, Data = ns.Adventure, ns.AdventureData
        ok(Data.add({ id = "mc", name = "熔火之心", short = "熔火", min = 58, max = 60, category = "raid", instance = 409 }), "a raid line")
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "mc", roles = { t = 1, h = 0, d = 0 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.maintain()
        ok(Adv.get(id).final, "the ticket is finalized")
        eq(one(ns, id, "adventure_created").activityType, "raid", "a raid")
        eq(#events(ns, id), 1, "only 建立 for a raid I lead")
        ticket(ns, B, "r1", t, { ds = "mc" })
        Adv.worker("r1", "apply")
        setMine(ns, "r1", { dt = t + 60 })
        ticket(ns, B, "r1", t, { ds = "mc", st = "c", sa = t + 120 })
        Adv.maintain()
        one(ns, "r1", "signup_applied")
        eq(#events(ns, "r1"), 1, "only 報名 for someone else's raid")
        Data.remove("mc")
    end)

    test("GF-013 §9.1 test builds: events are marked test and never queued", function()
        local ns = login()
        local real = ns.VERSION
        ns.VERSION = "0.16.0-dev"
        local id = ns.Adventure.open({ dungeon = "smg", leaderRole = "d" })
        ns.VERSION = real
        local ev = one(ns, id, "adventure_created")
        eq(ev.test, true, "marked test")
        eq(#ns.Events.pending(), 0, "not queued")
        eq(ns.Events.summary().test, 1, "counted as test only")
        eq(ns.Events.summary().leader.created, 0, "not in the counts")
    end)

    test("GF-013 §9.1 重開: the new ticket is its own adventure, its 建立 points at the old one", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local old = Adv.open({ dungeon = "smg", leaderRole = "d" })
        Adv.leader(old, "cancel")
        local new = Adv.reopen(old)
        ok(new and new ~= old, "a new ticket")
        eq(one(ns, new, "adventure_created").reopenOf, old, "points at the old one")
        -- The UI's 重開 (open, then forget the old one).
        local old2 = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { s = t + 60 } } })
        wow.state.now = wow.state.now + H; Adv.refresh(); Adv.maintain()
        local new2 = Adv.open({ dungeon = "sfk", leaderRole = "d" })
        Adv.forget(old2)
        eq(one(ns, new2, "adventure_created").reopenOf, old2, "the UI path too")
        eq(E.summary().reopened, 2, "two reopened"); eq(E.summary().leader.created, 4, "four tickets created")
    end)

    ---------------------------------------------------------------------------
    -- Queue: confirm, resend, capacity; history truncation; privacy; no public page
    ---------------------------------------------------------------------------

    test("GF-013 §9.1 queue: resend after a while, confirm by revision, delete, capacity warning without losing anything", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.maintain()
        local list = E.pending()
        eq(#list, 3, "created, finalized, formed")
        local ids = {}
        for _, p in ipairs(list) do ids[#ids + 1] = p.eventID end
        eq(E.markSent(ids), 3, "sent")
        eq(#E.pending(), 0, "nothing due right after")
        eq(E.queueStats().sent, 3, "sent, not confirmed")
        wow.state.now = wow.state.now + E.RESEND_AFTER
        eq(#E.pending(), 3, "due again: resend")
        local formed = one(ns, id, "adventure_formed")
        ok(E.confirm(formed.eventID, 1), "confirmed")
        eq(E.queueStats().queued, 2, "two left")
        -- A newer revision waits for its own receipt.
        local fin = one(ns, id, "adventure_finalized")
        E.revoke(id .. "|adventure_finalized", "test")
        eq(E.confirm(fin.eventID, 1), false, "an old receipt does not clear revision 2")
        ok(E.confirm(fin.eventID, 2), "revision 2 confirmed")
        ok(E.forget(one(ns, id, "adventure_created").eventID), "deleted here")
        eq(E.queueStats().queued, 0, "queue empty")
        -- Capacity: new events are refused (counted), nothing unconfirmed is dropped.
        local MAX, WARN = E.MAX_EVENTS, E.WARN_AT
        E.MAX_EVENTS, E.WARN_AT = 4, 3
        local a = Adv.open({ dungeon = "sfk", leaderRole = "d" })
        local b = Adv.open({ dungeon = "rfk", leaderRole = "d" })
        local c = Adv.open({ dungeon = "gnr", leaderRole = "d" })
        eq(count(ns), 4, "store full (2 old + 2 new)")
        eq(#events(ns, c), 0, "the third was refused")
        local q = E.queueStats()
        ok(q.warn, "warning"); eq(q.overflow, 1, "one refused")
        ok(E.diagText():find("容量已滿", 1, true), "the diagnostics say so")
        eq(#events(ns, a) + #events(ns, b), 2, "the queued ones are all still there")
        -- Confirmed and old enough: pruned, which frees room.
        for _, p in ipairs(E.pending()) do E.confirm(p.eventID, p.revision) end
        wow.state.now = wow.state.now + (E.KEEP_CONFIRMED_DAYS + 1) * 86400
        local d = Adv.open({ dungeon = "dm", leaderRole = "d" })
        eq(#events(ns, d), 1, "room again after pruning confirmed ones")
        E.MAX_EVENTS, E.WARN_AT = MAX, WARN
    end)

    test("GF-013 §9.1 the 30-day / 50-record log is untouched; clearing it loses no queued event", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.leader(id, "done")
        eq(#Adv.myLog(), 1, "logged as before")
        eq(Adv.myLog()[1].id, id, "the same log record"); eq(Adv.myLog()[1].st, "done", "done")
        local before = E.queueStats().queued
        ok(before >= 4, "queued: " .. before)
        -- Fill the log past 50 / 30 days: the log prunes as before, the events stay.
        local log = Adv.myLog()
        for i = 1, 60 do log[#log + 1] = { id = "x" .. i, at = t - i * H, st = "done", mb = A .. ":d" } end
        log[#log + 1] = { id = "old", at = t - 31 * 86400, st = "done", mb = A .. ":d" }
        Adv.maintain()
        eq(#Adv.myLog(), Adv.LOG_MAX, "50 kept")
        Adv.clearEnded()
        eq(#Adv.myLog(), 0, "log cleared")
        eq(E.queueStats().queued, before, "every queued event is still there")
        eq(one(ns, id, "participant_done").status, "active", "my 成行 is still recorded")
    end)

    test("GF-013 §9.1/§11 privacy: no names in events or export, nothing in the GF Sync outbox, no page", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        Adv.setWorker({ dungeons = { "smg" }, main = "h" })
        local id = Adv.open({ quests = { 101 }, leaderRole = "d" })
        ticket(ns, B, "b9", t, { nt = "測試乙的隊" })
        Adv.worker("b9", "apply")
        Adv.maintain()
        ok(count(ns) >= 4, "some events")
        local allowed = {}
        for _, k in ipairs(E.FIELDS) do allowed[k] = true end
        for _, ev in ipairs(E.pending()) do
            for k, v in pairs(ev) do
                ok(allowed[k], "only contract fields: " .. k)
                ok(not tostring(v):find("測試", 1, true), "no names: " .. k .. "=" .. tostring(v))
            end
        end
        eq(one(ns, id, "adventure_created").destinationID, "q:101", "a quest ticket by its quest IDs")
        local json = E.exportJSON()
        ok(json:sub(1, 1) == "[" and json:find('"eventType":"adventure_created"', 1, true), "JSON export")
        ok(not json:find("測試", 1, true), "no names in the export")
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox or {}) do
            ok(not tostring(e.kind):find("event", 1, true), "no event in the GF Sync outbox: " .. tostring(e.kind))
        end
        -- No public page: Events draws nothing; only the diagnostics section reads it.
        local f = assert(io.open(ADDON_DIR .. "/Events.lua", "rb"))
        local src = f:read("*a"); f:close()
        ok(not src:find("CreateFrame", 1, true) and not src:find("Framework.register", 1, true), "no frame, no page")
        local d = assert(io.open(ADDON_DIR .. "/Diag.lua", "rb"))
        ok(d:read("*a"):find("ns.Events.diagText", 1, true), "the diagnostics section"); d:close()
        ok(E.diagText():find("尚未接 GF Sync", 1, true), "says it is not uploaded")
    end)

    ---------------------------------------------------------------------------
    -- GF-016 (GPT review): personal 成行 needs my own evidence; the group's
    -- 60% signal alone is unknown (not counted), for members and for the leader.
    ---------------------------------------------------------------------------

    test("GF-016 §9.1 member: the ticket is done by another member's detection (60%); without my own proof I am unknown", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        ticket(ns, B, "g1", t, { rt = 0, rh = 1, rd = 2 })
        ok(Adv.worker("g1", "apply"), "I apply")
        offer(ns, C, "A", { { id = "g1", ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "d", rb = "" } }, t + 1)
        one(ns, "g1", "participant_admitted")
        local v = Adv.get("g1")
        ok(v.final and v.slot, "one slot: finalized")
        -- C saw it done inside the window (with enough people): the ticket is 成行 (auto).
        offer(ns, C, "A", { { id = "g1", ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "d", rb = "", dt = t + 10 * MIN } }, t + 2)
        v = Adv.get("g1")
        eq(v.state, "done", "成行 for the ticket"); eq(v.auto, true, "from the group's detection")
        Adv.maintain()
        eq(#events(ns, "g1", "participant_done"), 0, "no own proof: no 成行 for me (unknown)")
        eq(E.queueStats().noEvidence, 1, "counted once as 無證據")
        eq(E.summary().participations, 0, "nothing counted")
        -- My own detection later: counted (once).
        setMine(ns, "g1", { dt = t + 12 * MIN })
        Adv.maintain()
        eq(one(ns, "g1", "participant_done").evidence, "self_detected", "my own detection counts")
        eq(E.summary().participations, 1, "one")
    end)

    test("GF-016 §9.1 leader: a member's auto 成行 while I was away is not my 成行; my own detection or party is", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.maintain()
        local v = Adv.get(id)
        ok(v.final and v.slot, "finalized")
        -- B detects it done in the window; I (the leader) saw nothing myself.
        offer(ns, B, "A", { { id = id, ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "t", rb = "", dt = t + 5 * MIN } }, t + 2)
        eq(Adv.get(id).state, "done", "成行 (auto)")
        Adv.maintain() -- copies the 成行 into my part (R-16.24)
        eq(one(ns, id, "adventure_done").evidence, "auto", "the ticket's 成行 is recorded")
        eq(#events(ns, id, "participant_done"), 0, "but not my own 成行: no proof of mine")
        eq(E.summary().leader.done, 1, "開單成行 1 (a fact of the ticket)"); eq(E.summary().participations, 0, "my participations 0")
        -- With my party seen together after 定案 (fp on my ticket): counted.
        local list = Adv.listOf(A, "T")
        for _, e in ipairs(list) do if e.id == id then e.fp = (v.finalAt or t) + 60 end end
        Adv.ledger:put("T", Adv.encodeList(list)); Adv.refresh()
        Adv.maintain()
        eq(one(ns, id, "participant_done").evidence, "self_party", "my party evidence")
        -- My own detection (Adventure.leader "auto"): self_detected at once.
        local id2 = Adv.open({ dungeon = "sfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, C, id2, t + 3, "t")
        Adv.maintain()
        ok(Adv.leader(id2, "auto"), "I saw it done here")
        eq(one(ns, id2, "participant_done").evidence, "self_detected", "seen by me")
        -- 完成 pressed by me is my own act: leader_done (unchanged).
        local id3 = Adv.open({ dungeon = "dm", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, D, id3, t + 4, "t")
        Adv.maintain()
        ok(Adv.leader(id3, "done"), "完成")
        eq(one(ns, id3, "participant_done").evidence, "leader_done", "my 完成")
    end)

    test("GF-016 §9.1 a 0.16.0 leader 成行 taken from the group's signal is revoked with a new revision", function()
        local ns = login()
        local Adv, E = ns.Adventure, ns.Events
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.maintain()
        -- What 0.16.0 wrote: my participant_done with evidence "auto".
        local k = id .. "|participant_done|" .. A
        local ev = E.ensure(k, { adventureID = id, eventType = "participant_done", participationPath = "leader",
            role = "d", evidence = "auto", activityType = "dungeon", destinationID = "smg" }, t)
        eq(ev.revision, 1, "old record")
        offer(ns, B, "A", { { id = id, ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "t", rb = "", dt = t + 5 * MIN } }, t + 2)
        Adv.maintain()
        eq(ev.status, "revoked", "revoked"); eq(ev.revokedReason, "no_self_evidence", "why"); eq(ev.revision, 2, "a new revision")
        eq(E.summary().participations, 0, "not counted")
    end)

    test("GF-016 §9.1 共同冒險: activity, destination and this time's role on every event, also the match", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        ok(Adv.setWorker({ dungeons = { "smg" }, main = "h" }), "my worker ticket")
        ticket(ns, B, "g4", t, { dc = Adv.encodeDecisions({ { a = A, k = "i", t = t + 1 } }) })
        Adv.maintain()
        local m = one(ns, "g4", "worker_order_matched")
        eq(m.role, "h", "the match carries the role my worker ticket offers")
        eq(m.activityType, "dungeon", "activity"); eq(m.destinationID, "smg", "destination")
        wow.state.now = wow.state.now + MIN
        ok(Adv.worker("g4", "accept"), "I accept")
        local adm = one(ns, "g4", "participant_admitted")
        ok(adm.role ~= nil, "admitted with a role")
        for _, f in ipairs(ns.Events.FIELDS) do ok(f ~= "companions" and f ~= "memberGUIDs", "no co-member GUIDs in the export: " .. f) end
    end)
end
