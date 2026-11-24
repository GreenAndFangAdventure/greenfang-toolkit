-- GF-002-H (0.13.0, spec docs/spec/GF-002_adventure-tickets_v1.0.md §16):
-- 1-5 slots on adventure and worker tickets, signups per slot, the leader's
-- 定案, 成團 / 成行 / 成團未成行, the completion log, the adventure calendar.
-- Test names carry the R numbers. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local H, MIN = 3600, 60

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local r = ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    -- Someone signs up for ticket id at time t as role, for the slots ("12"; nil = a 0.12.x signup).
    local function apply(ns, author, id, t, role, sx)
        return offer(ns, author, "A", { { id = id, ac = "ap", at = t, ap = t, ak = "ap", ro = role, rb = "", sx = sx, su = sx and t or nil } }, t)
    end
    local function names(list)
        local out = {}
        for _, x in ipairs(list) do out[#out + 1] = x.a end
        return table.concat(out, ",")
    end
    local function mine(ns) return ns.Adventure.listOf(A, "T") end
    local function threeSlots(ns, extra)
        local t = ns.Share.serverNow()
        local o = { dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d",
            slots = { { s = t + 26 * H, d = 2 * H }, { s = t + 50 * H }, { s = t + 74 * H, d = 3 * H } } }
        for k, v in pairs(extra or {}) do o[k] = v end
        return ns.Adventure.open(o), t
    end

    ---------------------------------------------------------------------------
    -- R-16.1 - R-16.4: slots
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.1/R-16.2 1-5 slots: a start each, the length optional, 現在 with or without one", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { now = true }, { s = t + 3 * H, d = 2 * H },
            { s = t + 30 * H }, { s = t + 54 * H, d = H }, { s = t + 78 * H }, { s = t + 100 * H } } })
        ok(id, "opened")
        local v = Adv.get(id)
        eq(#v.slots, 5, "at most 5 slots (the 6th is dropped)")
        eq(v.slots[1].now and v.slots[1].d, nil, "現在 without a length")
        eq(v.slots[2].d, 2 * H, "a length"); eq(v.slots[3].d, nil, "no length")
        local ids = {}
        for _, sl in ipairs(v.slots) do ids[#ids + 1] = sl.id end
        eq(table.concat(ids, ","), "1,2,3,4,5", "numbered 1-5")
        -- 現在 with a length.
        local id2 = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { now = true, d = 3 * H } } })
        local v2 = Adv.get(id2)
        eq(v2.timeMode, "n", "now"); eq(v2.finish - v2.slots[1].s, 3 * H, "ends 3 hours after it opened")
        -- Bad: no start; too far.
        eq(select(2, Adv.open({ dungeon = "smg", slots = { { d = H } } })), "bad-time", "a start is required")
        eq(select(2, Adv.open({ dungeon = "smg", slots = { { s = t + 20 * 86400 } } })), "too-far", "at most 14 days ahead")
        eq(select(2, Adv.open({ dungeon = "smg", slots = {} })), "bad-time", "at least one slot")
    end)

    test("GF-002-H 0.12.x peers: tm / s / e keep the main slot; a ticket without slots reads as one", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns)
        local e = mine(ns)[1]
        eq(e.tm, "f", "the first slot is another day"); eq(e.s, t + 26 * H, "s = the first slot"); eq(e.e, t + 28 * H, "e = its end")
        ok(e.ts and e.ts:find("^1%-"), "ts: " .. tostring(e.ts))
        for k in pairs(e) do ok(k:match("^%w+$"), "plain key " .. k) end
        -- Only "a:i:t" in dc (the 0.12.x parser), the slots in iv.
        Adv.leader(id, "invite", B, { 2, 3 })
        e = mine(ns)[1]
        ok(e.dc:match("^0000%-0000000B:i:[0-9a-z]+$"), "dc unchanged: " .. e.dc)
        eq(Adv.decodePairs(e.iv)[B], "23", "the invited slots")
        -- Finalizing moves tm / s / e to that slot.
        Adv.leader(id, "finalize", 3)
        e = mine(ns)[1]
        eq(e.s, t + 74 * H, "s = the finalized slot"); eq(e.e, t + 77 * H, "its end")
        -- A 0.12.x ticket (no ts): one slot from tm / s / e; its signups (no sx) count for it.
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "t", s = t + H, e = t + 3 * H,
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        apply(ns, C, "abbb.1", t + 10, "h")
        local v = Adv.get("abbb.1")
        eq(#v.slots, 1, "one slot"); eq(v.slots[1].d, 2 * H, "2 hours"); eq(names(v.members), C, "the 0.12.x signup is in")
        eq(v.final, 1, "one slot: finalized by its first member (R-16.8)")
        -- A 0.12.x worker ticket (sl only).
        offer(ns, D, "W", { { id = "w", cr = t, ds = "smg", qs = "", rm = "h", ra = "", sl = "n_" .. ns.Share.b36(t + H) .. "-" .. ns.Share.b36(t + 2 * H),
            ex = t + 86400, st = "o", sa = t } })
        local w = Adv.workers()[D]
        eq(#w.slots, 2, "two slots"); ok(w.slots[1].now, "now"); eq(w.slots[2].d, H, "an hour")
    end)

    test("GF-002-H R-16.4 editing keeps the slot ids; a removed slot takes its signups; a new id does not inherit old ones", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns)
        apply(ns, B, id, t + 10, "t", "2")
        apply(ns, C, id, t + 20, "h", "23")
        local v = Adv.get(id)
        eq(v.slotCounts[2].total, 2, "slot 2: two signups"); eq(v.slotCounts[3].h, 1, "slot 3: the healer")
        -- Remove slot 2.
        local draft = {}
        for _, sl in ipairs(v.slots) do if sl.id ~= 2 then draft[#draft + 1] = { id = sl.id, s = sl.s, d = sl.d } end end
        wow.advance(60)
        ok(Adv.editTicket(id, { dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = draft }), "edited")
        v = Adv.get(id)
        local ids = {}
        for _, sl in ipairs(v.slots) do ids[#ids + 1] = sl.id end
        eq(table.concat(ids, ","), "1,3", "ids 1 and 3 stay")
        eq(names(v.members), C, "B signed only slot 2: gone; C keeps slot 3")
        eq(table.concat(v.members[1].slots, ","), "3", "C: slot 3")
        -- Add a slot: it takes the free id 2, but B's old slot-2 signup does not count for it.
        draft[#draft + 1] = { s = t + 98 * H }
        wow.advance(60)
        Adv.editTicket(id, { dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = draft })
        v = Adv.get(id)
        local new
        for _, sl in ipairs(v.slots) do if sl.s == t + 98 * H then new = sl end end
        eq(new.id, 2, "the free id"); ok(new.a, "added at")
        eq(names(v.members), C, "B is not back")
        -- B picks the new slot 2 now: counts.
        wow.advance(60)
        apply(ns, B, id, ns.Share.serverNow(), "t", "2")
        eq(Adv.get(id).slotCounts[2].t, 1, "a new choice counts")
        -- Removing the finalized slot unfinalizes.
        Adv.leader(id, "finalize", 3)
        eq(Adv.get(id).final, 3, "finalized 3")
        local keep = {}
        for _, sl in ipairs(Adv.get(id).slots) do if sl.id ~= 3 then keep[#keep + 1] = { id = sl.id, s = sl.s, d = sl.d } end end
        Adv.editTicket(id, { dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = keep })
        eq(Adv.get(id).final, nil, "no longer finalized")
    end)

    ---------------------------------------------------------------------------
    -- R-16.5 - R-16.7: signups and matching per slot
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.6 matching: any overlapping slot; without a length the start +-30 minutes", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns)
        local v = Adv.get(id)
        local function w(slots) return { dungeons = { smg = true }, quests = {}, main = "h", slots = slots } end
        ok(Adv.matches(v, w({ { s = t + 27 * H, d = H } }), 30), "inside slot 1")
        eq(table.concat(Adv.overlapSlots(v, { { s = t + 27 * H, d = H } }), ","), "1", "slot 1")
        ok(Adv.matches(v, w({ { s = t + 50 * H + 20 * MIN } }), 30), "slot 2 has no length: 20 minutes after its start still fits")
        local okM, why = Adv.matches(v, w({ { s = t + 50 * H + 31 * MIN, d = H } }), 30)
        eq(okM and "ok" or why, "time", "31 minutes after a start without a length: no")
        ok(not Adv.matches(v, w({ { now = true } }), 30), "now vs future slots")
        eq(table.concat(Adv.overlapSlots(v, { { s = t + 27 * H, d = H }, { s = t + 75 * H } }), ","), "1,3", "two slots")
        -- Once finalized, only that slot.
        Adv.leader(id, "finalize", 3)
        v = Adv.get(id)
        ok(not Adv.matches(v, w({ { s = t + 27 * H, d = H } }), 30), "slot 1 no longer counts")
        ok(Adv.matches(v, w({ { s = t + 75 * H } }), 30), "slot 3 does")
    end)

    test("GF-002-H R-16.5/R-16.7 signups name their slots; per-slot role counts; changing slots keeps my place", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "f", s = t + 26 * H, e = t + 28 * H,
            ts = Adv.encodeTimes({ { id = 1, s = t + 26 * H, d = 2 * H }, { id = 2, s = t + 50 * H } }),
            rt = 1, rh = 1, rd = 1, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        apply(ns, C, "abbb.1", t + 1, "h", "1")
        ok(Adv.worker("abbb.1", "apply", { 1, 2 }), "I apply for slots 1 and 2")
        local v = Adv.get("abbb.1")
        eq(v.slotCounts[1].h, 2, "slot 1: two healers (C and me)"); eq(v.slotCounts[2].h, 1, "slot 2: me (a druid: healer)")
        local me
        for _, m in ipairs(v.members) do if m.a == A then me = m end end
        ok(me, "in"); eq(table.concat(me.slots, ","), "1,2", "slots 1 and 2")
        local at = me.at
        wow.advance(30)
        Adv.worker("abbb.1", "apply", { 2 })
        v = Adv.get("abbb.1")
        for _, m in ipairs(v.members) do if m.a == A then me = m end end
        eq(table.concat(me.slots, ","), "2", "slot 2 only"); eq(me.at, at, "dropping a slot keeps my place")
        local e = Adv.listOf(A, "A")[1]
        eq(e.sx, "2", "sx"); ok(e.su > e.ap, "su = when the choice changed")
        wow.advance(30)
        Adv.worker("abbb.1", "apply", { 1, 2 })
        for _, m in ipairs(Adv.get("abbb.1").members) do if m.a == A then me = m end end
        ok(me.at > at, "adding a slot counts from now")
        -- Invited for slot 2: accepting takes the invited slots.
        offer(ns, B, "T", { { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "f", s = t + 26 * H, e = t + 28 * H,
            ts = Adv.encodeTimes({ { id = 1, s = t + 26 * H }, { id = 2, s = t + 50 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "c", mc = t, st = "o", sa = t,
            dc = A .. ":i:" .. ns.Share.b36(t + 5), iv = A .. ":2" } })
        local inv = Adv.get("abbb.2").invited[1]
        eq(inv.a, A, "invited"); eq(table.concat(inv.slots, ","), "2", "for slot 2")
        Adv.worker("abbb.2", "accept")
        local m = Adv.get("abbb.2").members[1]
        eq(m and m.a, A, "accepted: in at once"); eq(table.concat(m.slots, ","), "2", "the invited slot")
    end)

    ---------------------------------------------------------------------------
    -- R-16.8 - R-16.10: 定案
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.8/R-16.9 定案: who did not pick the slot waits, after those who did; notified", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns, { roles = { t = 1, h = 1, d = 1 }, leaderRole = "t" }) -- seats: 1 healer, 1 dps
        apply(ns, B, id, t + 1, "h", "1")   -- slot 1 only
        apply(ns, C, id, t + 2, "h", "12")  -- both
        apply(ns, D, id, t + 3, "d", "2")   -- slot 2 only
        local v = Adv.get(id)
        eq(names(v.members), B .. "," .. D, "before 定案: first come (B healer, D dps)")
        eq(names(v.waitlist), C, "C waits for the healer seat")
        eq(v.final, nil, "several slots: not finalized by itself")
        wow.advance(60)
        local ok1 = Adv.leader(id, "finalize", 2)
        ok(ok1, "finalized slot 2")
        v = Adv.get(id)
        eq(v.final, 2, "slot 2"); ok(v.finalAt, "when")
        eq(names(v.members), C .. "," .. D, "C (both) and D (slot 2) take the seats")
        eq(names(v.waitlist), B, "B kept as standby")
        ok(v.waitlist[1].late, "after everyone who picked slot 2")
        -- B is told; so are the members.
        local attB = Adv.attention(v, B, t + 10)
        eq(attB and attB.code, "final-wait", "B: finalized, now waiting")
        eq((Adv.attention(v, C, t + 10) or {}).code, "final", "C: finalized")
        -- A late standby is never refilled: D withdraws -> the dps seat stays open.
        apply(ns, D, id, t + 3, "d", "2")
        offer(ns, D, "A", { { id = id, ac = "wd", at = t + 20, ap = t + 3, ak = "ap", ro = "d", rb = "", sx = "2", su = t + 3 } }, t + 20)
        v = Adv.get(id)
        eq(names(v.members), C, "D left"); eq(names(v.waitlist), B, "B still waits (did not pick slot 2)")
        -- B adds slot 2: in (refill is for those who picked it; B's new choice takes the free seat).
        -- (a client adding a slot signs up again: Adv.worker; the new time is its place)
        offer(ns, B, "A", { { id = id, ac = "ap", at = t + 100, ap = t + 100, ak = "ap", ro = "h", rb = "", sx = "12", su = t + 100 } }, t + 100)
        v = Adv.get(id)
        eq(names(v.waitlist), B, "the healer seat is C's; B waits, no longer late")
        ok(not v.waitlist[1].late, "not late")
    end)

    test("GF-002-H R-16.8/R-16.10 one slot: finalized by the first member; reminders only for the finalized slot", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = t + 50 * MIN, d = 2 * H } } })
        local v = Adv.get(id)
        eq(v.final, nil, "nobody yet")
        apply(ns, B, id, t + 1, "t")
        v = Adv.get(id)
        eq(v.final, 1, "finalized by the first member")
        eq(Adv.reminder(v, t + 60).key, id .. "|remind|3600", "the 60-minute reminder")
        -- Several slots, not finalized: no reminder; finalized: only that slot's.
        local id2 = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { s = t + 50 * MIN }, { s = t + 5 * H } } })
        apply(ns, B, id2, t + 1, "t", "12")
        eq(Adv.reminder(Adv.get(id2), t + 60), nil, "not finalized: no reminder")
        Adv.leader(id2, "finalize", 2)
        eq(Adv.reminder(Adv.get(id2), t + 60), nil, "slot 2 is 5 hours away")
        eq(Adv.reminder(Adv.get(id2), t + 4 * H + 10 * MIN).key, id2 .. "|remind|3600", "an hour before slot 2")
        -- 組隊 needs the finalized slot.
        local id3 = Adv.open({ dungeon = "rfk", leaderRole = "d", slots = { { now = true }, { s = t + 5 * H } } })
        eq(select(2, Adv.form(id3)), "not-final", "several slots: 定案 first")
    end)

    ---------------------------------------------------------------------------
    -- R-16.15 - R-16.17: 成團, 成行, 成團未成行
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.15/R-16.16 成團 by 組隊 or full; 成行 only by 完成; 完成 needs 成團", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 2 }, leaderRole = "d" })
        eq(select(2, Adv.leader(id, "done")), "not-formed", "open: no 完成")
        apply(ns, B, id, t + 1, "t")
        local v = Adv.get(id)
        eq(v.state, "open", "finalized, not full, no 組隊")
        wow.advance(60)
        C_PartyInfo = { InviteUnit = function() end }
        Adv.form(id)
        C_PartyInfo = nil
        v = Adv.get(id)
        eq(v.state, "formed", "組隊 -> 成團"); ok(v.formedAt, "formedAt")
        ok(Adv.leader(id, "done"), "完成")
        v = Adv.get(id)
        eq(v.state, "done", "成行"); ok(v.closed, "closed")
        local e = mine(ns)[1]
        eq(e.st, "c", "st c"); ok(e.mb:find(B .. ":t", 1, true) and e.mb:find(A .. ":d", 1, true), "members with roles: " .. e.mb)
        -- Full counts as 成團 too (one slot, finalized by the first member).
        local id2 = Adv.open({ dungeon = "sfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id2, t + 2, "t")
        eq(Adv.get(id2).state, "formed", "full -> 成團 without 組隊")
        eq(Adv.get(id2).formedAt, t + 2, "formed when it filled")
    end)

    test("GF-002-H R-16.17 成團 without 完成: 24 hours after the slot it ends as 成團未成行 (and is logged)", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d", slots = { { s = t + H, d = 2 * H } } })
        apply(ns, B, id, t + 2, "t")
        eq(Adv.get(id).state, "formed", "full")
        wow.state.now = wow.state.now + 3 * H + 23 * H; Adv.refresh()
        eq(Adv.get(id).state, "formed", "23 hours after the slot: still 成團")
        ok(not Adv.get(id).closed, "open")
        wow.state.now = wow.state.now + 2 * H; Adv.refresh()
        eq(Adv.get(id).state, "unfinished", "24 hours after: 成團未成行")
        Adv.maintain()
        local e = mine(ns)[1]
        eq(e.st .. ":" .. e.rs, "x:unfinished", "written")
        local log = Adv.myLog()
        eq(#log, 1, "logged"); eq(log[1].st, "unfinished", "as 成團未成行"); eq(log[1].dn, nil, "no doneAt")
        -- An open ticket (not formed) after its slot: ended by time, no log.
        local id2 = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { s = ns.Share.serverNow() + 60 } } })
        wow.state.now = wow.state.now + 31 * MIN + 60; Adv.refresh()
        eq(Adv.get(id2).state, "ended", "no length: ended 30 minutes after its start")
        Adv.maintain()
        eq(#Adv.myLog(), 1, "not logged")
        -- The leader away does not cancel a formed ticket at login (it waits for 完成).
        local id3 = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id3, ns.Share.serverNow(), "t")
        Adv.onLogout()
        wow.state.now = wow.state.now + 30 * MIN; Adv.refresh()
        eq(Adv.onLogin(), 0, "nothing closed")
        eq(Adv.get(id3).state, "formed", "still 成團")
    end)

    ---------------------------------------------------------------------------
    -- R-16.18 - R-16.21: the completion log and the upload
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.18/R-16.19 completion log: GUID + role, no names; 30 days or 50 records", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 1 }, leaderRole = "d", slots = { { now = true }, { s = t + 5 * H } } })
        apply(ns, B, id, t + 1, "t", "1")
        apply(ns, C, id, t + 2, "h", "12")
        wow.advance(60)
        Adv.leader(id, "finalize", 1)
        Adv.form(id)
        wow.advance(60)
        Adv.leader(id, "done")
        local r = Adv.myLog()[1]
        eq(r.id, id, "ticket id"); eq(r.ds, "smg", "destination"); eq(r.st, "done", "成行")
        ok(r.fs and r.fm and r.dn and r.dn >= r.fm, "slot start, formedAt, doneAt")
        ns.Sync.recordSelf(true)
        local entry
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do if e.kind == "character.self" then entry = e end end
        local up = entry.payload.adventure.log.value[id]
        ok(up, "uploaded"); eq(up.dungeon, "smg", "dungeon"); eq(up.status, "done", "status")
        eq(#up.members, 3, "leader + 2")
        local roles = {}
        for _, m in ipairs(up.members) do roles[m.guid] = m.role; ok(m.guid:match("^Player%-"), "a GUID") end
        eq(roles["Player-" .. B], "tank", "B tank"); eq(roles["Player-" .. C], "healer", "C healer"); eq(roles["Player-" .. A], "dps", "me dps")
        local function strings(x, acc)
            acc = acc or {}
            for k, v in pairs(x) do
                if type(k) == "string" then acc[#acc + 1] = k end
                if type(v) == "string" then acc[#acc + 1] = v elseif type(v) == "table" then strings(v, acc) end
            end
            return acc
        end
        for _, s in ipairs(strings(entry.payload.adventure)) do ok(not s:find("測試", 1, true), "no names: " .. s) end
        -- Pruning: 50 records, 30 days.
        local list = {}
        for i = 1, 60 do list[i] = { id = "a" .. i, at = t - i * 3600, st = "done", mb = A .. ":d" } end
        list[61] = { id = "old", at = t - 31 * 86400, st = "done", mb = A .. ":d" }
        local kept = Adv.pruneLog(list, t)
        eq(#kept, 50, "50 newest"); eq(kept[1].id, "a1", "newest first")
        for _, x in ipairs(kept) do ok(x.id ~= "old", "older than 30 days dropped") end
    end)

    test("GF-002-H R-16.21 upload: slots, finalized slot, phase, signup and invite slots; others' log from the ledger", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns)
        Adv.leader(id, "invite", D, { 1, 3 })
        apply(ns, B, id, t + 1, "t", "13")
        Adv.leader(id, "finalize", 3)
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "f", s = t + 26 * H, e = t + 28 * H,
            ts = Adv.encodeTimes({ { id = 1, s = t + 26 * H }, { id = 2, s = t + 50 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        Adv.worker("abbb.1", "apply", { 2 })
        ns.Sync.recordSelf(true)
        local entry
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do if e.kind == "character.self" then entry = e end end
        local adv = entry.payload.adventure
        local tk = adv.tickets.value[id]
        eq(#tk.times, 3, "three slots"); eq(tk.times[1].id, 1, "ids"); eq(tk.times[1].mode, "at", "at a time")
        eq(tk.times[1].length, 2 * H, "length"); eq(tk.times[2].length, nil, "no length"); eq(tk.times[2].to, tk.times[2].from + 1800, "to = from + 30 min")
        eq(tk.final, 3, "finalized slot"); ok(tk.finalAt, "finalAt"); eq(tk.phase, "open", "phase")
        eq(tk.time.from, t + 74 * H, "time = the finalized slot (0.12.x readers)")
        eq(table.concat(tk.decisions["Player-" .. D].slots, ","), "1,3", "invited for 1 and 3")
        eq(table.concat(adv.actions.value["abbb.1"].slots, ","), "2", "my signup: slot 2")
        -- Another leader's 成行 ticket, still in the ledger: its log goes up with member.share.
        offer(ns, B, "T", { { id = "abbb.9", src = "g", ver = 1, cr = t - 100, ds = "rfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "t", tg = 0, md = "a", st = "c", sa = t - 10, fx = 1, fm = t - 50, mb = B .. ":t;" .. C .. ":h" } }, t + 5)
        local up = Adv.uploadFor(B)
        local r = up.log and up.log.value["abbb.9"]
        ok(r, "from the ledger"); eq(r.status, "done", "成行"); eq(r.formedAt, t - 50, "formedAt"); eq(r.doneAt, t - 10, "doneAt")
        eq(#r.members, 2, "members")
    end)

    ---------------------------------------------------------------------------
    -- UI: slot chips, the chooser, the row buttons
    ---------------------------------------------------------------------------

    test("GF-002-H R-16.3 the ticket window: one chip per slot, ＋時段 up to 5, 移除 in the picker; saved with ids", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openTicket()
        d.dungeon = "smg"
        local f = _G[U.TICKET_NAME]
        eq(#d.slots, 1, "one slot (現在)")
        for i = 2, 5 do
            local pk = (function() wow.click(f.addSlot); return U.picker() end)()
            ok(pk:IsShown() and pk.title:GetText() == "時段 " .. i, "adding opens its picker: 時段 " .. i)
            ok(pk.remove:IsShown(), "移除 with more than one slot")
            pk:Hide()
        end
        eq(#d.slots, 5, "five"); eq(f.addSlot:IsShown(), false, "no ＋時段 at 5")
        ok(f.slotChips[5]:IsShown(), "five chips")
        ok(f.rowY[3] < -48 - 2 * 52, "the rows below moved down (two lines of chips)")
        -- Remove slot 3 in its picker.
        local pk = U.pickStart(f.slotChips[3], 3)
        wow.click(pk.remove)
        eq(#d.slots, 4, "four"); ok(f.addSlot:IsShown(), "＋時段 again")
        local id = U.submitTicket()
        local v = ns.Adventure.get(id)
        eq(#v.slots, 4, "saved four"); ok(v.slots[1].now, "現在 first")
        -- Editing keeps the ids.
        local d2 = U.openTicket(v)
        local ids = {}
        for _, sl in ipairs(d2.slots) do ids[#ids + 1] = sl.id end
        eq(table.concat(ids, ","), "1,2,3,4", "draft ids")
        table.remove(d2.slots, 2)
        U.submitTicket()
        ids = {}
        for _, sl in ipairs(ns.Adventure.get(id).slots) do ids[#ids + 1] = sl.id end
        eq(table.concat(ids, ","), "1,3,4", "the ids stay")
    end)

    test("GF-002-H R-16.5/R-16.8 the row: 申請 picks slots, 時段 changes them; the leader 定案 -> 組隊 -> 完成 (glows inside)", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "f", s = t + 26 * H, e = t + 28 * H,
            ts = Adv.encodeTimes({ { id = 1, s = t + 26 * H, d = 2 * H }, { id = 2, s = t + 50 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        Adv.setWorker({ dungeons = { "smg" }, main = "h", slots = { { s = t + 50 * H, d = H } } })
        local v = Adv.get("abbb.1")
        eq(table.concat(U.buttonsFor(v), ","), "apply", "apply")
        eq(U.press(v, "apply", UIParent), "slots", "the chooser")
        local ch = U.chooser()
        ok(ch:IsShown(), "shown"); eq(ch.title:GetText(), "申請", "titled")
        ok(not ch.rows[1].selected and ch.rows[2].selected, "slot 2 ticked (my worker ticket fits it)")
        wow.click(ch.rows[1])
        wow.click(ch.go)
        ok(not ch:IsShown(), "closed")
        v = Adv.get("abbb.1")
        local me
        for _, m in ipairs(v.members) do if m.a == A then me = m end end
        eq(table.concat(me.slots, ","), "1,2", "both")
        eq(table.concat(U.buttonsFor(v), ","), "slots,withdraw", "change my slots, withdraw")
        U.press(v, "slots", UIParent)
        ok(ch.rows[1].selected and ch.rows[2].selected, "my slots ticked")
        wow.click(ch.rows[2]); wow.click(ch.go)
        for _, m in ipairs(Adv.get("abbb.1").members) do if m.a == A then me = m end end
        eq(table.concat(me.slots, ","), "1", "slot 1 only")
        -- The leader's buttons.
        local id = threeSlots(ns)
        apply(ns, B, id, t + 1, "t", "2")
        v = Adv.get(id)
        eq(table.concat(U.buttonsFor(v), ","), "edit,finalize,remove", "not finalized: 定案")
        U.press(v, "finalize", UIParent)
        ok(ch.rows[2].selected and not ch.rows[1].selected, "the slot with the most signups is suggested")
        ok(plain(ch.rows[2].count._text):find("1", 1, true), "its role count")
        wow.click(ch.rows[3]); ok(ch.rows[3].selected and not ch.rows[2].selected, "one slot only")
        wow.click(ch.rows[2]); wow.click(ch.go)
        v = Adv.get(id)
        eq(v.final, 2, "finalized 2")
        eq(table.concat(U.buttonsFor(v), ","), "edit,form,remove", "then 組隊")
        C_PartyInfo = { InviteUnit = function() end }
        U.press(v, "form")
        C_PartyInfo = nil
        v = Adv.get(id)
        eq(table.concat(U.buttonsFor(v), ","), "done,remove", "成團: 完成")
        -- 完成 glows inside the destination.
        ns.Framework.open("adventure")
        IsInInstance = function() return true end
        GetInstanceInfo = function() return "x", "party", 1, "", 5, 0, false, 189 end -- 血色修道院
        Adv.onEnterWorld()
        U.refresh()
        local glow
        for _, r in ipairs(U.rowFrames()) do
            if r:IsShown() and r.view and r.view.id == id then
                for _, b in ipairs(r.buttons) do if b:IsShown() and b.action == "done" then glow = b.glowing and b.sel:IsShown() end end
                ok(plain(r.detail:GetText()):find("成團", 1, true), "成團 on line 2")
            end
        end
        ok(glow, "完成 glows")
        eq(Adv.get(id).state, "formed", "still not 成行")
        IsInInstance, GetInstanceInfo = nil, nil
    end)

    ---------------------------------------------------------------------------
    -- R-16.12 - R-16.14: the adventure calendar
    ---------------------------------------------------------------------------

    -- Local midnight-based day offsets in the mock (UTC+8): a start on day k at 20:00.
    local function dayAt(ns, k, hh)
        return ns.AdventureUI.dayStart(k) + (hh or 20) * H
    end

    test("GF-002-H R-16.12/R-16.13 calendar: a week a page to 14 days, icons a day, frames for mine / signed / finalized", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local t = ns.Share.serverNow()
        local mineId = Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = dayAt(ns, 1) }, { s = dayAt(ns, 3) } } })
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "rfk", qs = "", tm = "f",
            ts = Adv.encodeTimes({ { id = 1, s = dayAt(ns, 1, 21) }, { id = 2, s = dayAt(ns, 9) } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "sfk", qs = "", tm = "f",
            ts = Adv.encodeTimes({ { id = 1, s = dayAt(ns, 1, 19) }, { id = 2, s = dayAt(ns, 14) } }), fx = 2, fa = t,
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        Adv.worker("abbb.1", "apply", { 1 })
        local day1 = U.calendarItems(1)
        eq(#day1, 2, "day 1: mine and B's rfk (sfk is finalized on day 14)")
        local kinds = {}
        for _, it in ipairs(day1) do kinds[it.view.id] = (it.mine and "mine" or it.signed and "signed" or "other") end
        eq(kinds[mineId], "mine", "mine"); eq(kinds["abbb.1"], "signed", "my signup")
        eq(#U.calendarItems(9), 1, "rfk slot 2 on day 9"); ok(not U.calendarItems(9)[1].signed, "not my slot")
        local d14 = U.calendarItems(14)
        eq(#d14, 1, "day 14"); ok(d14[1].final, "finalized")
        -- The window.
        ns.Framework.open("adventure")
        ok(plain(U.calendarButton:GetText()) == " 行事曆" or plain(U.calendarButton:GetText()):find("行事曆", 1, true), "行事曆 button")
        wow.click(U.calendarButton)
        local f = U.calendar()
        ok(f:IsShown(), "opened")
        eq(f.prev:IsShown(), false, "the first page: no back")
        local cell = f.cells[2] -- day 1
        local shownIcons, glowMine, glowSigned = 0, false, false
        for _, ic in ipairs(cell.icons) do
            if ic:IsShown() then
                shownIcons = shownIcons + 1
                if ic.kind == "mine" then glowMine = ic.glow:IsShown() and ic.glow._vertex and ic.glow._vertex[1] == 1 or ic.glow:IsShown() end
                if ic.kind == "signed" then glowSigned = ic.glow:IsShown() end
            end
        end
        eq(shownIcons, 2, "two icons on day 1"); ok(glowMine and glowSigned, "framed: mine and signed")
        wow.click(cell)
        eq(f.day, 1, "day 1 chosen")
        local rows = 0
        for _, r in ipairs(f.list) do if r:IsShown() then rows = rows + 1 end end
        eq(rows, 2, "its tickets listed")
        -- Pages: 0-6, 7-13, 14.
        wow.click(f.next); wow.click(f.next)
        eq(f.page, 2, "the third page"); eq(f.next:IsShown(), false, "no further than 14 days")
        local c14 = f.cells[1]
        local fin = false
        for _, ic in ipairs(c14.icons) do if ic:IsShown() and ic.final then fin = ic.shine:IsShown() end end
        ok(fin, "the finalized slot shines")
        ok(not f.cells[2].enabled, "day 15 is out of range")
        -- ESC closes it.
        wow.pressEscape()
        ok(not f:IsShown(), "ESC closes")
    end)
    ---------------------------------------------------------------------------
    -- v1.1a R-16.22 - R-16.25: automatic 成行
    ---------------------------------------------------------------------------

    -- My party: these authors (party1..4).
    local function party(list)
        UnitGUID = function(u)
            if u == "player" then return "Player-" .. A end
            local i = tonumber(tostring(u):match("^party(%d)$"))
            return i and list[i] and ("Player-" .. list[i]) or nil
        end
    end
    local function inside(instanceID)
        IsInInstance = function() return instanceID ~= nil end
        GetInstanceInfo = function() return "x", "party", 1, "", 5, 0, false, instanceID end
    end
    local function restore()
        IsInInstance, GetInstanceInfo = nil, nil
        UnitGUID = function(u) if u == "player" then return "Player-" .. A end end
    end

    test("GF-002-H R-16.22 needed: 60% of the set size rounded up, at least 2 (the leader counts)", function()
        local ns = login()
        local Adv = ns.Adventure
        eq(Adv.autoNeeded({ roles = { t = 1, h = 1, d = 3 } }), 3, "5 -> 3")
        eq(Adv.autoNeeded({ roles = { t = 1, h = 0, d = 2 } }), 2, "3 -> 2")
        eq(Adv.autoNeeded({ size = 4 }), 3, "4 -> 3")
        eq(Adv.autoNeeded({ size = 2 }), 2, "2 -> 2")
        local from, to = Adv.autoWindow({ s = 10000 })
        eq(from, 10000 - 3600, "60 minutes before"); eq(to, 10000 + 4 * 3600, "no length: 4 hours")
        eq(select(2, Adv.autoWindow({ s = 10000, d = 7200 })), 17200, "with a length: its end")
    end)

    test("GF-002-H R-16.22 dungeon: inside with 3 of 5 accepted in the party -> 成團 and 成行 at once (no 組隊)", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "sml", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t"); apply(ns, C, id, t + 2, "h")
        wow.advance(60)
        party({ B }); inside(189)
        Adv.onEnterWorld()
        eq(Adv.get(id).state, "open", "only 2 accepted in the party: not yet")
        party({ B, C, D }) -- D is not accepted: does not count
        Adv.checkAuto()
        local v = Adv.get(id)
        eq(v.state, "done", "成行"); ok(v.auto, "automatic"); ok(v.formedAt, "成團 too")
        local e = mine(ns)[1]
        eq(e.st, "c", "written as 成行"); ok(e.dt, "detected at"); ok(e.mb:find(C .. ":h", 1, true), "members")
        eq(Adv.myLog()[1].st, "done", "logged")
        -- Outside the window: a slot two days away.
        local id2 = Adv.open({ dungeon = "sml", roles = { t = 1, h = 1, d = 1 }, leaderRole = "d", slots = { { s = ns.Share.serverNow() + 2 * 86400 } } })
        apply(ns, B, id2, ns.Share.serverNow(), "t"); apply(ns, C, id2, ns.Share.serverNow(), "h")
        Adv.checkAuto()
        eq(Adv.get(id2).state, "formed", "full (成團), but not in its window: no 成行")
        -- Another dungeon: nothing.
        local id3 = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 1, d = 1 }, leaderRole = "d" })
        apply(ns, B, id3, ns.Share.serverNow(), "t"); apply(ns, C, id3, ns.Share.serverNow(), "h")
        Adv.checkAuto()
        ok(Adv.get(id3).state ~= "done", "SM is not RFK")
        restore()
    end)

    test("GF-002-H R-16.24 the leader away: an accepted member's own record makes it 成行; the log goes up with member.share", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "sml", qs = "", tm = "n", rt = 1, rh = 0, rd = 2,
            lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        apply(ns, C, "abbb.1", t + 1, "d")
        wow.advance(5)
        ok(Adv.worker("abbb.1", "apply"), "I am in")
        wow.advance(60)
        party({ C }); inside(189) -- the leader B is not in the party
        eq(Adv.checkAuto(), 1, "one record written")
        local e = Adv.listOf(A, "A")[1]
        ok(e.dt, "dt on my own signup only"); eq(#Adv.listOf(A, "T"), 0, "nothing in anyone else's part")
        local v = Adv.get("abbb.1")
        eq(v.state, "done", "成行 from my record"); ok(v.auto, "auto")
        eq((Adv.attention(v, C, ns.Share.serverNow()) or {}).code, "done", "the others hear of it")
        local up = Adv.uploadFor(B)
        local r = up.log and up.log.value["abbb.1"]
        ok(r, "B's log record, derived"); eq(r and r.status, "done", "成行"); ok(r and r.auto, "auto"); eq(r and #r.members, 3, "B, C and me")
        -- A record from someone who is not accepted does not count.
        offer(ns, B, "T", { { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "sml", qs = "", tm = "n", rt = 1, rh = 0, rd = 2,
            lr = "t", tg = 0, md = "a", st = "o", sa = t, dc = D .. ":k:" .. ns.Share.b36(t + 2) } })
        offer(ns, D, "A", { { id = "abbb.2", ac = "ap", at = t + 1, ap = t + 1, ak = "ap", ro = "d", rb = "", dt = t + 70 } }, t + 70)
        eq(Adv.get("abbb.2").state, "open", "kicked D's record: ignored")
        restore()
    end)

    test("GF-002-H R-16.23 quest ticket: a quest of the ticket turned in with enough accepted in the party", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ quests = { 1013, 1014 }, size = 4, leaderRole = "d" })
        apply(ns, B, id, t + 1, "d"); apply(ns, C, id, t + 2, "d")
        wow.advance(60)
        party({ B, C })
        eq(Adv.checkAuto(2000), 0, "another quest: nothing")
        eq(Adv.checkAuto(), 0, "no quest turned in: nothing")
        eq(Adv.checkAuto(1014), 1, "1014 turned in, 3 of 4 accepted here")
        eq(Adv.get(id).state, "done", "成行")
        restore()
    end)

    ---------------------------------------------------------------------------
    -- v1.1a R-16.26 - R-16.29: quests easy to see
    ---------------------------------------------------------------------------

    local function questLog(rows)
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
    end
    local ROWS = {
        { isHeader = true, title = "貧瘠之地" },
        { questID = 850, title = "測試任務：草原之心", level = 16 },
        { questID = 851, title = "測試任務：綠洲", level = 22 },
        { isHeader = true, title = "剃刀沼澤" },
        { questID = 1101, title = "測試任務：沼澤之王", level = 34 },
    }

    test("GF-002-H R-16.27 quest picker: by zone, full names, colored levels; a dungeon quest brings its dungeon; up to 5", function()
        local ns = login()
        local U = ns.AdventureUI
        questLog(ROWS)
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "", qs = "851", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        local d = U.openTicket()
        local f = _G[U.TICKET_NAME]
        wow.click(f.pickQuest)
        local qp = U.questPickerFrame()
        ok(qp:IsShown(), "open")
        local heads = {}
        for _, h in ipairs(qp.heads) do if h:IsShown() then heads[#heads + 1] = h:GetText() end end
        eq(table.concat(heads, ","), "貧瘠之地,剃刀沼澤", "zone headers in log order")
        local rows = {}
        for _, r in ipairs(qp.rows) do if r:IsShown() then rows[r.questId] = r end end
        eq(rows[850].name:GetText(), "測試任務：草原之心", "the full name")
        ok(rows[850].level:GetText():find("16", 1, true) and rows[850].level:GetText():find("^|cff"), "a colored level")
        ok(rows[851].wanted and not rows[850].wanted, "❗ on the quest B's ticket wants")
        eq(U.questDungeon({ zone = "剃刀沼澤" }), "rfk", "a dungeon quest: its dungeon (its art on the row)")
        wow.click(rows[1101])
        eq(d.dungeon, "rfk", "brings its dungeon"); eq(#d.quests, 1, "and the quest")
        wow.click(rows[850]); wow.click(rows[851])
        wow.click(rows[1101])
        eq(d.dungeon, nil, "no dungeon quest left: no dungeon")
        local id = U.submitTicket()
        local e
        for _, x in ipairs(ns.Adventure.listOf(A, "T")) do if x.id == id then e = x end end
        ok(e.qn and e.qn:find("850:測試任務：草原之心", 1, true), "names travel in-game: " .. tostring(e and e.qn))
        local text = plain(U.destText(ns.Adventure.get(id)))
        eq(text, "測試任務：草原之心 16 +1", "the first quest, its level, +1")
        ns.Sync.recordSelf(true)
        local entry
        for _, x in ipairs(GreenFangToolkitDB.sync.outbox) do if x.kind == "character.self" then entry = x end end
        local tk = entry.payload.adventure.tickets.value[id]
        eq(table.concat(tk.quests, ","), "850,851", "the upload: quest IDs only")
        for k, v in pairs(tk) do ok(type(v) ~= "string" or not v:find("測試任務", 1, true), "no quest names uploaded: " .. k) end
        C_QuestLog = nil
        -- Someone without the quests in their log still sees the names (qn).
        offer(ns, B, "T", { { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "", qs = "1101.850", qn = "1101:測試任務：沼澤之王;850:測試任務：草原之心",
            ql = "1101:34;850:16", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        eq(plain(U.destText(ns.Adventure.get("abbb.2"))), "測試任務：沼澤之王 34 +1", "from the ticket's names")
        local tip = U.ticketTooltip(ns.Adventure.get("abbb.2"))
        eq(#tip, 2, "the tooltip lists all"); ok(plain(tip[2]):find("草原之心", 1, true), "the second")
        -- At most 5.
        questLog({ { questID = 1, title = "q1", level = 10 }, { questID = 2, title = "q2", level = 10 }, { questID = 3, title = "q3", level = 10 },
            { questID = 4, title = "q4", level = 10 }, { questID = 5, title = "q5", level = 10 }, { questID = 6, title = "q6", level = 10 } })
        d = U.openTicket()
        U.pickQuests(f.pickQuest)
        for _, r in ipairs(qp.rows) do if r:IsShown() then wow.click(r) end end
        eq(#d.quests, 5, "at most 5")
        C_QuestLog = nil
    end)

    test("GF-002-H R-16.29 worker quests by name (+N); 日誌全部 with its count", function()
        local ns = login()
        local U = ns.AdventureUI
        questLog(ROWS)
        U.openWorker()
        local wf = _G[U.WORKER_NAME]
        U.pickWorkerQuests(wf.quests)
        local qp = U.questPickerFrame()
        ok(qp.all:IsShown(), "日誌全部 at the top"); eq(qp.all.label._text, "日誌全部 3", "with the count")
        local rows = {}
        for _, r in ipairs(qp.rows) do if r:IsShown() then rows[r.questId] = r end end
        wow.click(rows[850]); wow.click(rows[851]); wow.click(rows[1101])
        ok(plain(wf.quests:GetText()):find("測試任務：草原之心 16、測試任務：綠洲 22 +1", 1, true), "names on the button: " .. plain(wf.quests:GetText()))
        U.saveWorker()
        local w = ns.Adventure.myWorker()
        eq(plain(U.workerDest(w)), "測試任務：草原之心 16、測試任務：綠洲 22 +1", "the row: names, not 任務 3")
        U.openWorker()
        U.pickWorkerQuests(wf.quests)
        wow.click(qp.all)
        ok(plain(wf.quests:GetText()):find("日誌全部 3", 1, true), "日誌全部 3")
        U.saveWorker()
        eq(plain(U.workerDest(ns.Adventure.myWorker())), "日誌全部 3", "shared with the count")
        C_QuestLog = nil
    end)
end
