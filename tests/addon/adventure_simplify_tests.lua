-- GF-002-I (0.14.0, spec docs/spec/GF-002_adventure-tickets_v1.0.md §17):
-- the simpler states (招募中 / 已定案 / 成團 / 成行; 過期 / 未成行 / 取消),
-- 成團 by itself, step back, worker tickets that close, the state badge with
-- its ✓✗ checklist (Adventure.whyState is the only source), the 規則 card,
-- data-driven dungeons and raids, quests on worker rows, and the adventure
-- page's cheap fixes from the design review GF-UI-A. Made-up data only.

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
    -- Each author's signups add up (one A record per author), each offer newer than the last.
    local acts, lastAt = {}, {}
    local function apply(ns, author, id, t, role, sx, extra)
        if acts.ns ~= ns then acts, lastAt = { ns = ns }, {} end
        local e = { id = id, ac = "ap", at = t, ap = t, ak = "ap", ro = role, rb = "", sx = sx, su = sx and t or nil }
        for k, v in pairs(extra or {}) do e[k] = v end
        local list = acts[author] or {}
        acts[author] = list
        for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
        list[#list + 1] = e
        local at = math.max(t, (lastAt[author] or 0) + 1)
        lastAt[author] = at
        return offer(ns, author, "A", list, at)
    end
    local function names(list)
        local out = {}
        for _, x in ipairs(list) do out[#out + 1] = x.a end
        return table.concat(out, ",")
    end
    local function party(list)
        UnitGUID = function(u)
            if u == "player" then return "Player-" .. A end
            local i = tonumber(tostring(u):match("^party(%d)$"))
            return i and list[i] and ("Player-" .. list[i]) or nil
        end
    end
    local function inside(instanceID, kind)
        IsInInstance = function() return instanceID ~= nil end
        GetInstanceInfo = function() return "x", kind or "party", 1, "", 5, 0, false, instanceID end
    end
    local function restore()
        IsInInstance, GetInstanceInfo = nil, nil
        UnitGUID = function(u) if u == "player" then return "Player-" .. A end end
    end
    -- Visit every row of the page (the list only draws the rows in view): fn(row) once per data row.
    local function eachRow(U, fn)
        local sc = U.scrollFrame()
        local seen = {}
        for k = 0, #U.shownRows() do
            sc:SetVerticalScroll(k * U.ROW_HEIGHT)
            for _, r in ipairs(U.rowFrames()) do
                if r:IsShown() then
                    local key = (r.view and r.view.id) or (r.mine and "mine") or r.worker or (r.head:IsShown() and r.head:GetText()) or tostring(r)
                    if not seen[key] then seen[key] = true; fn(r) end
                end
            end
        end
        sc:SetVerticalScroll(0)
    end
    local function mineT(ns, id)
        for _, e in ipairs(ns.Adventure.listOf(A, "T")) do if e.id == id then return e end end
    end
    local function threeSlots(ns, extra)
        local t = ns.Share.serverNow()
        local o = { dungeon = "smg", roles = { t = 1, h = 1, d = 1 }, leaderRole = "d",
            slots = { { s = t + 26 * H, d = 2 * H }, { s = t + 50 * H }, { s = t + 74 * H, d = 3 * H } } }
        for k, v in pairs(extra or {}) do o[k] = v end
        return ns.Adventure.open(o), t
    end
    -- Every item of a checklist: at most 6 characters and a number, no sentence marks.
    local function checkItems(why, what)
        for _, g in ipairs(why.groups) do
            ok(g.name and g.name ~= "", what .. ": a group name")
            for _, it in ipairs(g.items) do
                ok(ns_chars(it.text) <= 6, what .. ": item ≤ 6 characters: " .. tostring(it.text))
                ok(not tostring(it.text):find("。", 1, true) and not tostring(it.text):find("，", 1, true), what .. ": no sentence")
                if it.value then ok(tostring(it.value):match("^[%d/%-h ]+$"), what .. ": a number: " .. tostring(it.value)) end
            end
        end
    end
    function ns_chars(s)
        local n = 0
        for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
        return n
    end

    ---------------------------------------------------------------------------
    -- R-17.1 - R-17.4, R-17.11 / R-17.12: every state, and whyState agrees with it
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.1/R-17.12 whyState names the same state as the view, in every case", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local cases = {}
        local function case(what, id, want)
            local v = Adv.get(id)
            eq(v.state, want, what .. ": the state")
            local why = Adv.whyState(v)
            eq(why.state, v.state, what .. ": whyState agrees")
            eq(why.name, Adv.STATE_NAME[want], what .. ": its name")
            checkItems(why, what)
            -- What made it so is ticked in the current group.
            for _, it in ipairs(why.groups[1].items) do
                if it.text == "定案" or it.text == "滿員" or it.text == "隊伍" or it.text == "自動" or it.text == "完成" then
                    eq(it.ok, true, what .. ": " .. it.text .. " ✓")
                end
            end
            cases[#cases + 1] = want
            return v, why
        end
        -- 招募中: several slots, nothing finalized; the next step is 定案 (the leader's button).
        local id1 = threeSlots(ns)
        local _, why1 = case("several slots", id1, "open")
        eq(why1.groups[2].state, "final", "next: 已定案"); eq(why1.groups[2].items[1].ok, false, "✗ 定案")
        eq(why1.action, "finalize", "→ 定案")
        -- 已定案: one slot with its first member; 成團 needs 滿員 or the party.
        local id2 = Adv.open({ dungeon = "sfk", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d" })
        apply(ns, B, id2, t + 1, "t")
        local _, why2 = case("one slot, a member", id2, "final")
        local texts = {}
        for _, it in ipairs(why2.groups[2].items) do texts[#texts + 1] = it.text .. (it.value and (" " .. it.value) or "") end
        eq(table.concat(texts, ","), "滿員 1/4,或,隊伍 1/3,時段內", "the next state's checklist")
        eq(why2.action, "form", "→ 組隊 (invites)")
        -- 成團 by full.
        local id3 = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id3, t + 1, "t")
        local v3, why3 = case("full", id3, "formed")
        eq(v3.formedBy, "full", "by 滿員")
        eq(why3.groups[2].state, "done", "next: 成行")
        eq(why3.action, "done", "→ 完成")
        -- 成團 by the party (the leader saw it).
        local id4 = Adv.open({ dungeon = "sml", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d" })
        apply(ns, B, id4, t + 1, "t"); apply(ns, C, id4, t + 2, "h")
        wow.advance(60)
        party({ B, C })
        Adv.checkAuto()
        local v4 = case("party (leader)", id4, "formed")
        eq(v4.formedBy, "party", "by the party")
        -- 成團 by the party: a member saw it (its own signup's fp), the leader not grouped.
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        apply(ns, C, "abbb.1", t + 1, "h", nil, { fp = t + 30 })
        apply(ns, D, "abbb.1", t + 2, "d")
        case("party (member)", "abbb.1", "formed")
        -- 成行 by 完成.
        Adv.leader(id3, "done")
        local _, why5 = case("完成", id3, "done")
        eq(why5.action, "back", "→ 退回")
        -- 成行 by itself (inside with enough accepted).
        inside(189)
        Adv.checkAuto()
        local v6 = case("auto", id4, "done")
        ok(v6.auto, "automatic")
        restore()
        -- 過期: open, its slots over; and already finalized, its slot over.
        local id7 = Adv.open({ dungeon = "dm", leaderRole = "d", slots = { { s = t + 60 } } })
        local id8 = Adv.open({ dungeon = "wc", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { s = t + 60, d = H } } })
        apply(ns, B, id8, t + 2, "t")
        wow.state.now = wow.state.now + 2 * H; Adv.refresh()
        local _, why7 = case("open, over", id7, "ended")
        eq(why7.action, "reopen", "→ 重開")
        case("finalized, over", id8, "ended")
        -- 未成行.
        wow.state.now = wow.state.now + 26 * H; Adv.refresh()
        case("formed, 24 hours after", "abbb.1", "unfinished")
        -- 取消 by hand and by the leader away (C is offline in the roster).
        local id9 = Adv.open({ dungeon = "stk", leaderRole = "d" })
        Adv.leader(id9, "cancel", "manual")
        case("removed", id9, "cancel")
        local now = ns.Share.serverNow()
        offer(ns, C, "T", { { id = "accc.1", src = "g", ver = 1, cr = now, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "o", sa = now } })
        Adv.all()
        wow.advance(16 * MIN); Adv.refresh()
        local vc, whyc = case("leader away", "accc.1", "cancel")
        eq(vc.closeReason, "offline", "offline"); eq(whyc.groups[1].items[1].text, "團長在線", "✗ 團長在線")
        eq(#cases, 12, "every case")
    end)

    test("GF-002-I R-17.2 one slot needs no 定案; ❗ for the leader 60 minutes before the earliest slot", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = t + 2 * H }, { s = t + 30 * H } } })
        eq(Adv.attention(Adv.get(id), A, t), nil, "two hours away: nothing")
        eq(Adv.attention(Adv.get(id), A, t + 61 * MIN).code, "finalize", "59 minutes before: ❗ 定案")
        ok(Adv.attention(Adv.get(id), A, t + 61 * MIN).decide, "until the leader decides")
        eq(Adv.whyState(Adv.get(id), { now = t + 61 * MIN }).due, true, "whyState knows")
        Adv.leader(id, "finalize", 2)
        eq(Adv.attention(Adv.get(id), A, t + 61 * MIN), nil, "finalized: gone")
        local one = Adv.open({ dungeon = "sfk", leaderRole = "d", slots = { { s = t + 30 * MIN } } })
        eq(Adv.attention(Adv.get(one), A, t), nil, "one slot: never")
    end)

    test("GF-002-I R-17.3 組隊 only invites; 成團 by itself (full, or the party in the window, only after 定案)", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns, { roles = { t = 1, h = 1, d = 2 }, slots = { { now = true }, { s = ns.Share.serverNow() + 50 * H } } })
        apply(ns, B, id, t + 1, "t", "12"); apply(ns, C, id, t + 2, "h", "12")
        wow.advance(60)
        party({ B, C })
        Adv.checkAuto()
        eq(Adv.get(id).state, "open", "not finalized: no 成團 (and nothing written)")
        eq(mineT(ns, id).fp, nil, "no fp")
        Adv.leader(id, "finalize", 2)
        Adv.checkAuto()
        eq(Adv.get(id).state, "final", "the finalized slot is 50 hours away: not in the window")
        Adv.leader(id, "back") -- back to 招募中, finalize the 現在 slot
        Adv.leader(id, "finalize", 1)
        C_PartyInfo = { InviteUnit = function() end }
        Adv.form(id)
        C_PartyInfo = nil
        local e = mineT(ns, id)
        eq(e.st, "o", "組隊 writes no state"); eq(e.fp, nil, "and no 成團")
        Adv.checkAuto()
        eq(Adv.get(id).state, "formed", "the party in the window: 成團")
        ok(mineT(ns, id).fp, "the leader's fp")
        -- A 0.13.x leader's 組隊 (st = g) still reads as 成團.
        local now = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.9", src = "g", ver = 1, cr = now, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "g", sa = now + 5 } })
        apply(ns, C, "abbb.9", now + 1, "h")
        eq(Adv.get("abbb.9").state, "formed", "0.13.x 組隊"); eq(Adv.get("abbb.9").formedBy, "group", "by 組隊")
        restore()
    end)

    ---------------------------------------------------------------------------
    -- R-17.5 過期 and 重開, R-17.7 step back
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.5 過期: grey with its badge for a day; 重開 = the same contents, a new time", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "dm", roles = { t = 1, h = 1, d = 2 }, leaderRole = "h", tags = 4, note = "慢慢來", mode = "c",
            slots = { { s = t + 60, d = H } } })
        wow.state.now = wow.state.now + 2 * H; Adv.refresh()
        Adv.maintain()
        eq(mineT(ns, id).st .. ":" .. mineT(ns, id).rs, "x:time", "closed by time")
        ns.Framework.open("adventure")
        U.setTab("ended") -- GF-002-J (R-17.23): ended tickets are on 已結束
        local row
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then row = r end end
        ok(row, "still listed")
        eq(plain(row.badge.text._text), "已過期", "the 過期 badge"); ok(row.badge.icon._desaturated, "grey")
        eq(table.concat(row.name._color, ","), "0.5,0.5,0.5", "grey name")
        eq(row.buttons[1].action, "reopen", "重開"); ok(row.buttons[1]:IsShown(), "shown")
        wow.click(row.buttons[1])
        local d = U.draft()
        ok(_G[U.TICKET_NAME]:IsShown(), "the ticket window")
        eq(d.editId, nil, "a new ticket"); eq(d.reopenOf, id, "of the old one")
        eq(d.dungeon, "dm", "same dungeon"); eq(d.note, "慢慢來", "same note"); eq(d.mode, "c", "same admission"); eq(d.tags, 4, "same tags")
        eq(d.roles.d, 2, "same roles"); ok(d.slots[1].now and #d.slots == 1, "a new time: 現在")
        local nid = U.submitTicket()
        ok(nid and nid ~= id, "opened again")
        eq(mineT(ns, id), nil, "the 過期 one left my list")
        eq(Adv.get(nid).state, "open", "招募中")
        -- Otherwise it leaves after a day.
        local id2 = Adv.open({ dungeon = "wc", leaderRole = "d", slots = { { s = ns.Share.serverNow() + 60 } } })
        wow.state.now = wow.state.now + 2 * H; Adv.refresh(); Adv.maintain()
        ok(mineT(ns, id2), "kept")
        wow.state.now = wow.state.now + 25 * H; Adv.refresh(); Adv.maintain()
        eq(mineT(ns, id2), nil, "a day later: gone")
    end)

    test("GF-002-I R-17.7 step back: 成行 -> 成團 (log out), 成團 -> 已定案, 已定案 -> 招募中 (standbys back)", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns) -- seats: 1 tank, 1 healer
        apply(ns, B, id, t + 1, "h", "1")
        apply(ns, C, id, t + 2, "h", "12")
        apply(ns, D, id, t + 3, "t", "2")
        eq(select(2, Adv.leader(id, "back")), "back", "招募中: nothing to step back")
        Adv.leader(id, "finalize", 2)
        local v = Adv.get(id)
        eq(v.state, "formed", "C and D fill slot 2: 成團"); eq(names(v.waitlist), B, "B a standby")
        ok(v.waitlist[1].late, "after the others")
        wow.advance(60)
        -- 成團 -> 已定案.
        ok(Adv.leader(id, "back"), "back")
        v = Adv.get(id)
        eq(v.state, "final", "已定案"); ok(v.formedBack, "fb"); eq(v.final, 2, "still finalized")
        -- 已定案 -> 招募中: B gets the healer seat back (the earliest signup), C waits again.
        ok(Adv.leader(id, "back"), "back again")
        v = Adv.get(id)
        eq(v.state, "open", "招募中"); eq(v.final, nil, "no 定案")
        eq(names(v.members), B .. "," .. D, "B back in"); eq(names(v.waitlist), C, "C waits"); ok(not v.waitlist[1].late, "not late")
        eq(mineT(ns, id).s, v.slots[1].s, "0.12.x time: the first slot again")
        -- 成行 -> 成團: the log record goes, and it stays 成團 (ff).
        local id2 = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id2, ns.Share.serverNow(), "t")
        Adv.leader(id2, "done")
        eq(#Adv.myLog(), 1, "logged")
        ok(Adv.leader(id2, "back"), "成行 -> 成團")
        eq(Adv.get(id2).state, "formed", "成團"); eq(#Adv.myLog(), 0, "the log record is gone")
        eq(mineT(ns, id2).st, "o", "open again in my record")
        -- One slot: 已定案 by its first member, nothing to step back to.
        local id3 = Adv.open({ dungeon = "wc", leaderRole = "d" })
        apply(ns, B, id3, ns.Share.serverNow(), "t")
        eq(Adv.get(id3).state, "final", "已定案")
        eq(select(2, Adv.leader(id3, "back")), "back", "one slot: no step back")
    end)

    test("GF-002-I R-17.7 after a step back the same party does not redo it at once; a new start does", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "sml", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t"); apply(ns, C, id, t + 2, "h")
        wow.advance(60)
        party({ B, C }); inside(189)
        Adv.checkAuto()
        eq(Adv.get(id).state, "done", "成團 and 成行 by themselves")
        wow.advance(60)
        Adv.leader(id, "back")
        eq(Adv.get(id).state, "formed", "back to 成團")
        Adv.checkAuto(); wow.advance(60); Adv.checkAuto()
        eq(Adv.get(id).state, "formed", "still inside with them: not done again")
        local why = Adv.whyState(Adv.get(id))
        local auto
        for _, it in ipairs(why.groups[2].items) do if it.text == "自動" then auto = it end end
        ok(auto and auto.ok == false, "✗ 自動 in the checklist")
        -- 成團 -> 已定案 while grouped: not formed again.
        Adv.leader(id, "back")
        Adv.checkAuto()
        eq(Adv.get(id).state, "final", "the same party: stays 已定案")
        -- They leave and come back: a new start.
        party({}); Adv.checkAuto()
        party({ B, C }); Adv.checkAuto()
        local v = Adv.get(id)
        ok(v.state == "formed" or v.state == "done", "regrouped: 成團 (or 成行) again: " .. v.state)
        restore()
    end)

    ---------------------------------------------------------------------------
    -- R-17.9 / R-17.10: worker tickets close
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.9/R-17.10 an expired worker ticket closes, its waiting signups go (the leader hears), 重開 a day", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        -- B's tickets: one I wait on (consent), one I am in.
        offer(ns, B, "T", {
            { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "c", mc = t, st = "o", sa = t },
            { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "sfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t },
        })
        ok(Adv.setWorker({ dungeons = { "smg", "sfk" }, main = "h", slots = { { s = t + 2 * H, d = H } }, hours = 24 }), "registered")
        wow.advance(5)
        Adv.worker("abbb.1", "apply"); Adv.worker("abbb.2", "apply")
        eq(#Adv.get("abbb.1").pending, 1, "pending on 1"); eq(#Adv.get("abbb.2").members, 1, "in 2")
        ok(Adv.workers()[A], "listed for others")
        -- Its only slot ends: closed.
        wow.state.now = wow.state.now + 3 * H + 60; Adv.refresh()
        Adv.maintain()
        local w = Adv.myWorker()
        ok(w and w.closed, "已結案"); eq(Adv.workers()[A], nil, "others never see it")
        eq(Adv.uploadFor(A) and Adv.uploadFor(A).worker, nil, "the site neither")
        eq(#Adv.get("abbb.1").pending, 0, "the waiting signup is withdrawn")
        eq(#Adv.get("abbb.2").members, 1, "the seat I hold stays")
        local wd
        for _, e in ipairs(Adv.listOf(A, "A")) do if e.id == "abbb.1" then wd = e end end
        eq(wd.ac .. ":" .. tostring(wd.wr), "wd:x", "withdrawn, reason expired")
        local att = Adv.attention(Adv.get("abbb.1"), B, ns.Share.serverNow())
        eq(att and att.code, "worker-gone", "the leader is told")
        -- My row: grey, 已結案, 重開 (GF-002-J: on 已結束).
        ns.Framework.open("adventure")
        U.setTab("ended")
        local row
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.mine then row = r end end
        eq(plain(row.badge.text._text), "已結案", "the badge"); eq(row.buttons[1].action, "reopen-worker", "重開")
        wow.click(row.buttons[1])
        local d = U.workerDraft()
        eq(table.concat(d.dungeons, ","), "smg,sfk", "same dungeons"); eq(d.main, "h", "same role")
        ok(#d.slots == 1 and d.slots[1].now, "new slots: 現在")
        -- Not reopened: deleted a day later.
        _G[U.WORKER_NAME]:Hide()
        wow.state.now = wow.state.now + 25 * H; Adv.refresh(); Adv.maintain()
        eq(Adv.myWorker(), nil, "gone from the save")
        -- 24 hours (ex) close it too.
        Adv.setWorker({ dungeons = { "smg" }, main = "h", slots = { { now = true } }, hours = 1 })
        wow.state.now = wow.state.now + H + 60; Adv.refresh(); Adv.maintain()
        ok(Adv.myWorker().closed, "after its hours: 已結案")
        -- Quest sync does not reopen a closed one.
        eq(Adv.syncQuests({}), false, "untouched")
    end)

    ---------------------------------------------------------------------------
    -- R-17.11 - R-17.13: the badge, the checklist, the rules card
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.11 a state badge at x = 640 on line 2 of every row; its tooltip is the ✓✗ checklist", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "sml", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, id, t + 1, "t")
        Adv.setWorker({ dungeons = { "smg" }, main = "h", slots = { { now = true } } })
        offer(ns, C, "W", { { id = "w", cr = t, ds = "sml", qs = "", rm = "d", ra = "", sv = Adv.encodeTimes({ { id = 1, now = true, s = t } }),
            ex = t + 86400, st = "o", sa = t } })
        ns.Framework.open("adventure")
        U.refresh()
        local kinds = {}
        eachRow(U, function(r)
            if not r.head:IsShown() then
                local p = r.badge._points[1]
                eq(p[4], 640, "x = 640"); eq(p[5], U.LINE2, "line 2")
                ok(r.badge:IsShown(), "shown")
                if r.view then kinds.ticket = r end
                if r.mine then kinds.mine = r end
                if r.worker then kinds.worker = { badge = plain(r.badge.text._text) } end
            end
        end)
        -- Back at the top: the frames that show the ticket and my worker ticket now.
        for _, r in ipairs(U.rowFrames()) do
            if r:IsShown() and r.view then kinds.ticket = r end
            if r:IsShown() and r.mine then kinds.mine = r end
        end
        eq(kinds.worker and kinds.worker.badge, "上架", "another worker: 上架")
        ok(kinds.ticket and kinds.mine and kinds.worker, "a ticket, my worker ticket, another worker")
        eq(plain(kinds.ticket.badge.text._text), "已成團", "成團")
        eq(plain(kinds.mine.badge.text._text), "上架", "上架")
        -- The tooltip: ReadyCheck marks, the two groups, the button to press.
        kinds.ticket.badge:GetScript("OnEnter")(kinds.ticket.badge)
        local lines = {}
        for _, l in ipairs(GameTooltip._lines) do lines[#lines + 1] = l.text end
        local text = table.concat(lines, "\n")
        ok(text:find("ReadyCheck-Ready", 1, true), "✓ marks")
        ok(text:find("ReadyCheck", 1, true) and (text:find("NotReady", 1, true) or text:find("Waiting", 1, true)), "✗ or ⏳")
        ok(plain(lines[1]):find("成團", 1, true), "the state first")
        ok(plain(text):find("成行", 1, true), "the next state")
        ok(plain(lines[#lines]):find("完成", 1, true), "→ 完成 last")
        for _, l in ipairs(lines) do ok(not l:find("。", 1, true), "no sentence: " .. plain(l)) end
        -- The 完成 button shows the same list.
        local done
        for _, b in ipairs(kinds.ticket.buttons) do if b:IsShown() and b.action == "done" then done = b end end
        ok(done, "完成")
        done:GetScript("OnEnter")(done)
        eq(#GameTooltip._lines, #lines, "the same checklist on 完成")
        -- Widths: the badge fits before the buttons; four buttons would still end inside the row.
        local W = ns.Widgets
        ok(U.COL.badge + W.BADGE_W <= U.COL.buttons, "badge before the buttons")
        ok(U.COL.detail + U.COL.detailW <= U.COL.badge, "details before the badge")
        local last = 0
        for _, b in ipairs(kinds.ticket.buttons) do
            if b:IsShown() then last = math.max(last, b.flowX + ns.OrdersUI.buttonSpan(b)) end
        end
        ok(last <= U.ROW_WIDTH, "buttons inside the row: " .. last)
    end)

    test("GF-002-I R-17.13 規則: icons, arrows, nouns of 2-4 characters and numbers; nothing overlaps; ESC / outside close", function()
        local ns = login()
        local U = ns.AdventureUI
        ns.Framework.open("adventure")
        ok(U.rulesButton:IsShown(), "the 規則 button"); ok(plain(U.rulesButton:GetText()):find("規則", 1, true), "named")
        wow.click(U.rulesButton)
        local f = U.rules()
        ok(f:IsShown(), "open")
        local arrows, icons = 0, 0
        for _, row in ipairs(U.rulesRows()) do
            for _, tok in ipairs(row) do
                if tok.arrow then arrows = arrows + 1 end
                if tok.icon then icons = icons + 1 end
                if tok.text then
                    local s = tok.text
                    ok(s:match("^[%d/h ]+$") or ns_chars(s:gsub("[%d/ ]", "")) <= 4, "a short noun or a number: " .. s)
                end
            end
        end
        ok(arrows >= 10 and icons >= 15, "mostly icons and arrows")
        local sizes = {}
        for _, n in ipairs(U.RULE_SIZES) do sizes[#sizes + 1] = n .. ">" .. ns.Adventure.autoNeeded({ size = n }) end
        eq(table.concat(sizes, " "), "3>2 4>3 5>3 10>6 20>12 40>24", "the party numbers come from autoNeeded")
        -- No two parts overlap; all inside.
        local parts = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._parent == f and o._shown and o._points and o._points[1] and o._points[1][2] == f and o._points[1][1] == "TOPLEFT" then
                local p = o._points[1]
                local w, h = o._w or 0, o._h or 0
                if o._kind == "FontString" then w, h = wow.textWidth(o._text, o._font), 16 end
                if o._kind ~= "FontString" or plain(o._text) ~= "" then
                    parts[#parts + 1] = { l = p[4], t = -p[5], r = p[4] + w, b = -p[5] + h, n = plain(o._text) ~= "" and plain(o._text) or (o._texture or "?") }
                end
            end
        end
        ok(#parts > 30, "parts measured: " .. #parts)
        for i = 1, #parts do
            local a = parts[i]
            ok(a.l >= 0 and a.t >= 0 and a.r <= f._w + 1 and a.b <= f._h + 1, "inside: " .. a.n)
            for j = i + 1, #parts do
                local b = parts[j]
                ok(not (a.l < b.r - 1 and b.l < a.r - 1 and a.t < b.b - 1 and b.t < a.b - 1), "overlap: " .. a.n .. " × " .. b.n)
            end
        end
        -- ESC closes it first; a click outside too (a menu-level frame).
        ns.escape()
        ok(not f:IsShown(), "ESC")
        wow.click(U.rulesButton)
        ok(ns.clickBlocker() and ns.clickBlocker():IsShown(), "the click-outside blocker is up")
        wow.click(ns.clickBlocker())
        ok(not f:IsShown(), "a click outside")
    end)

    ---------------------------------------------------------------------------
    -- R-17.14 - R-17.16: data-driven destinations, raids later
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.14/R-17.16 one data line adds a raid: art with a fallback, 團本 tab, 40-person roles, instance check", function()
        local ns = login()
        local Data, U, Adv = ns.AdventureData, ns.AdventureUI, ns.Adventure
        for _, d in ipairs(Data.DUNGEONS) do
            ok(d.category == "dungeon" and d.size == 5 and d.icon and d.min and d.max, "every line: " .. d.id)
            ok(ns.GameIcons.ART["dungeon_" .. d.id], "art for " .. d.id)
        end
        ok(not Data.has("raid"), "no raid yet")
        local grid = U.dungeonGrid(UIParent, function() end)
        local raidTab
        for _, b in ipairs(grid.tabs) do if b.category == "raid" then raidTab = b end end
        ok(not raidTab:IsShown(), "團本 hidden without raid data")
        grid:Hide()
        ok(Data.add({ id = "mc", short = "熔火", name = "測試團本", min = 60, max = 60, category = "raid", size = 40, instance = 409, icon = "MoltenCore" }), "added")
        ok(not Data.add({ id = "mc", name = "x", min = 1, max = 2 }), "an id once")
        local art = ns.GameIcons.ART.dungeon_mc
        eq(art[1][1], "Interface\\LFGFrame\\LFGIcon-MoltenCore", "the group finder art"); eq(#art, 3, "two fallbacks (a raid's, the key)")
        local r = Data.defaultRoles("mc")
        eq(r.t .. "/" .. r.h .. "/" .. r.d, "5/10/25", "40 people by default")
        eq(Adv.autoNeeded({ roles = r }), 24, "60% of 40")
        grid = U.dungeonGrid(UIParent, function() end)
        ok(raidTab:IsShown(), "團本 now shown")
        wow.click(raidTab)
        local shown = {}
        for _, b in ipairs(grid.buttons) do if b:IsShown() then shown[#shown + 1] = b.dungeon end end
        eq(table.concat(shown, ","), "", "my level 32: 適合我 hides it")
        wow.click(grid.filters[2]) -- 全部
        shown = {}
        for _, b in ipairs(grid.buttons) do if b:IsShown() then shown[#shown + 1] = b.dungeon end end
        eq(table.concat(shown, ","), "mc", "全部: the raid")
        grid:Hide()
        -- A 40-person ticket: the roles start at the raid's, ＋ stops at 40, the row writes numbers.
        local d = U.openTicket()
        U.setDraftDungeon(d, "mc")
        eq(d.roles.d, 25, "raid roles"); U.drawTicket()
        U.changeCount("d", 1)
        eq(d.roles.d, 25, "40 already: ＋ does nothing")
        U.changeCount("t", -1); U.changeCount("d", 1)
        eq(d.roles.d, 26, "one free seat")
        local id = U.submitTicket()
        ok(id, "opened")
        ns.Framework.open("adventure"); U.refresh()
        for _, row in ipairs(U.rowFrames()) do
            if row:IsShown() and row.view and row.view.id == id then
                ok(plain(row.roles:GetText()):find("26", 1, true), "numbers per role: " .. plain(row.roles:GetText()))
                for _, s in ipairs(row.slots) do ok(not s:IsShown(), "no seat icons for 40") end
            end
        end
        -- Inside a raid instance.
        inside(409, "raid")
        eq(table.concat(Adv.currentDungeon() or {}, ","), "mc", "the raid by its instance ID")
        restore()
        Data.remove("mc")
        ok(not Data.has("raid"), "removed")
    end)

    test("GF-002-I R-17.15 the picker: sorted by my level, 適合我 / 全部, scrolls; cells apart", function()
        local ns = login()
        local U, Data = ns.AdventureUI, ns.AdventureData
        local list = U.gridList("dungeon", "fit", 32)
        ok(#list > 0 and #list < #Data.DUNGEONS, "適合我: fewer")
        for _, d in ipairs(list) do ok(Data.fits(d.id, 32), "fits: " .. d.id) end
        local all = U.gridList("dungeon", "all", 32)
        eq(#all, #Data.DUNGEONS, "全部")
        local function dist(d) return 32 < d.min and d.min - 32 or 32 > d.max and 32 - d.max or 0 end
        for i = 2, #all do ok(dist(all[i - 1]) <= dist(all[i]), "nearest range first: " .. all[i].id) end
        eq(U.gridList("dungeon", "all", nil)[1].id, Data.DUNGEONS[1].id, "no level: the list order")
        U.openTicket()
        local grid = U.pickDestination(_G[U.TICKET_NAME].dest)
        eq(grid.filter, "fit", "適合我 first")
        -- The cells sit in the scrolled area, 3 rows visible, none overlapping.
        ok(grid.scroll._h == U.GRID_ROWS * U.GRID_CELL_H, "3 rows visible")
        wow.click(grid.filters[2])
        local cells = {}
        for _, b in ipairs(grid.buttons) do
            if b:IsShown() then
                local p = b._points[1]
                eq(p[2], grid.content, "inside the scrolled area")
                cells[#cells + 1] = { l = p[4], t = -p[5], r = p[4] + U.GRID_CELL_W - 8, b = -p[5] + U.GRID_CELL_H - 8, id = b.dungeon }
            end
        end
        eq(#cells, #Data.DUNGEONS, "all of them")
        for i = 1, #cells do
            for j = i + 1, #cells do
                local a, b = cells[i], cells[j]
                ok(not (a.l < b.r and b.l < a.r and a.t < b.b and b.t < a.b), "overlap: " .. a.id .. " × " .. b.id)
            end
        end
        ok(grid.content._h > grid.scroll._h, "more than fits: it scrolls")
        wow.click(grid.buttons[3])
        eq(U.draft().dungeon, Data.DUNGEONS[3].id, "a click picks it")
    end)

    ---------------------------------------------------------------------------
    -- R-17.17: quests on every worker row
    ---------------------------------------------------------------------------

    test("GF-002-I R-17.17 worker rows: the quest icon, the first quest and +N or 日誌全部 N; ❗ for quests I have", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        C_QuestLog = { GetNumQuestLogEntries = function() return 2, 0 end, GetInfo = function(i)
            return ({ { isHeader = true, title = "貧瘠之地" }, { questID = 850, title = "測試任務：草原之心", level = 16 } })[i] end }
        local t = ns.Share.serverNow()
        local sv = Adv.encodeTimes({ { id = 1, now = true, s = t } })
        offer(ns, B, "W", { { id = "w", cr = t, ds = "smg", qs = "850.851.852", qn = "850:測試任務：草原之心;851:測試任務：綠洲", rm = "t", ra = "",
            sv = sv, ex = t + 86400, st = "o", sa = t } })
        offer(ns, C, "W", { { id = "w", cr = t, ds = "", qs = "", qa = "1", qc = 7, rm = "d", ra = "", sv = sv, ex = t + 86400, st = "o", sa = t } })
        offer(ns, D, "W", { { id = "w", cr = t, ds = "", qs = "851", qn = "851:測試任務：綠洲", rm = "d", ra = "", sv = sv, ex = t + 86400, st = "o", sa = t } })
        -- I lead a smg ticket: B matches it; C and D are listed under 全部職工.
        Adv.open({ dungeon = "smg", leaderRole = "d" })
        ns.Framework.open("adventure")
        U.refresh()
        local rows, heads = {}, {}
        eachRow(U, function(r)
            if r.head:IsShown() then heads[#heads + 1] = plain(r.head:GetText()) end
            if r.worker then rows[r.worker] = { detail = r.detail:GetText(), name = r.name:GetText() } end
        end)
        ok(table.concat(heads, ","):find("全部職工", 1, true), "全部職工")
        local b = rows[B]
        ok(b, "B (matching)")
        local line = b.detail
        ok(line:find("INV_Misc_Note_01", 1, true), "the quest icon")
        ok(plain(line):find("測試任務：草原之心 16 +2", 1, true), "the first quest (its level from my log) +2: " .. plain(line))
        ok(line:find("AvailableQuestIcon", 1, true), "❗: 850 is in my log")
        local c = rows[C]
        ok(c and plain(c.name):find("日誌全部 7", 1, true), "日誌全部 7: " .. plain(c and c.name))
        local d = rows[D]
        ok(d and plain(d.name):find("測試任務：綠洲", 1, true), "D's quest")
        ok(not d.name:find("AvailableQuestIcon", 1, true), "not in my log: no ❗")
        C_QuestLog = nil
    end)

    ---------------------------------------------------------------------------
    -- The design review's cheap fixes on the adventure page (GF-UI-A §3 ★3 ★4 ★5 9 16)
    ---------------------------------------------------------------------------

    test("GF-002-I GF-UI-A: no sentences, 2-4 character names, inline icons ≥ 16 px, calendar frames, red fields", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local src = assert(io.open(ADDON_DIR .. "/AdventureUI.lua", "rb")):read("*a")
        for _, s in ipairs({ "這天沒有冒險單", "同時在尋求組隊上架", "尋求組隊（遊戲內建）", "搜尋尋求組隊", "邀請下一位", "（已登記）",
            "移除職工單", "任務日誌是空的", "請先選目的地", "（最多 5 個）", "（可以選好幾個）", "SetColorTexture(1, 0.82, 0.2, 0.22)" }) do
            ok(not src:find(s, 1, true), "gone: " .. s)
        end
        for size in src:gmatch("|T[^|]-:(%d+)|t") do ok(tonumber(size) >= 16, "inline icon " .. size) end
        for size in src:gmatch("tex%([^,%)]+, (%d+)%)") do ok(tonumber(size) >= 16, "tex size " .. size) end
        ok(plain(U.tex("yes")) == "" and U.tex("yes"):find(":18", 1, true), "the default inline size is 18")
        -- Names on the page and in the windows.
        ns.Framework.open("adventure")
        eq(plain(U.lfgButton:GetText()):gsub("^%s+", ""), "尋求組隊", "尋求組隊")
        eq(U.nextInvite.label._text, "下一位", "下一位")
        U.openTicket()
        local tf = _G[U.TICKET_NAME]
        eq(plain(tf.lfgCheck.label._text):gsub("^%s+", ""), "上架", "上架")
        -- A missing field turns red with a ✗ (no sentence).
        local _, why = U.submitTicket()
        eq(why, "no-destination", "nothing chosen")
        eq(table.concat(tf.fieldStrings["目的地"]._color, ","), "1,0.3,0.3", "目的地 red")
        ok(tf.fieldMark:IsShown() and tf.fieldMark._texture:find("NotReady", 1, true), "✗ next to it")
        eq(tf.result._text, "", "no text")
        U.draft().dungeon = "smg"; U.drawTicket()
        eq(table.concat(tf.fieldStrings["目的地"]._color, ","), "1,0.82,0", "fixed: gold again")
        ok(not tf.fieldMark:IsShown(), "no ✗")
        U.openWorker()
        eq(plain(_G[U.WORKER_NAME].TitleText._text), "職工單", "no brackets in the title")
        eq(_G[U.WORKER_NAME].remove.label._text, "移除", "移除")
        -- Calendar: today in gold, the chosen day highlighted and framed; arrows greyed, not hidden.
        local f = U.openCalendar()
        ok(f.cells[1].frame.shown and f.cells[1].today, "today framed")
        ok(not f.cells[2].frame.shown, "tomorrow not")
        wow.click(f.cells[3])
        ok(f.cells[3].frame.shown and f.cells[3].pick.on, "chosen: frame and highlight")
        ok(f.cells[1].frame.shown and not f.cells[1].pick.on, "today still framed")
        ok(f.prev:IsShown() and f.prev.disabled and f.prev.tex._desaturated, "back greyed out")
        eq(f.empty._text, "沒有冒險單", "no sentence")
        local glow
        for _, cell in ipairs(f.cells) do for _, ic in ipairs(cell.icons) do glow = ic.glow end end
        Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = U.dayStart(1) + 20 * H } } })
        U.drawCalendar()
        for _, ic in ipairs(f.cells[2].icons) do if ic:IsShown() then glow = ic.glow end end
        eq(glow and glow._w, 48, "glow 48")
        -- The quest picker's selection is the list-row highlight with a gold bar.
        C_QuestLog = { GetNumQuestLogEntries = function() return 2, 0 end, GetInfo = function(i)
            return ({ { isHeader = true, title = "貧瘠之地" }, { questID = 850, title = "測試任務：草原之心", level = 16 } })[i] end }
        U.openTicket()
        U.pickQuests(_G[U.TICKET_NAME].pickQuest)
        local qp = U.questPickerFrame()
        for _, z in ipairs(qp.zoneRows) do if z:IsShown() and z.zone == "貧瘠之地" then wow.click(z) end end -- GF-002-J (R-17.20): the zone first
        local r = qp.rows[1]
        wow.click(r)
        ok(r.pick.on and r.pick.hl._texture:find("UI-QuestLogTitleHighlight", 1, true) and r.pick.bar._shown, "row selection")
        C_QuestLog = nil
    end)

    test("GF-002-I 0.13.x / 0.12.x peers: only new fields, plain keys; a 0.14.0 ticket reads the same old way", function()
        local ns = login()
        local Adv = ns.Adventure
        local id, t = threeSlots(ns)
        apply(ns, B, id, t + 1, "h", "2"); apply(ns, C, id, t + 2, "t", "2")
        wow.advance(60)
        Adv.leader(id, "finalize", 2)
        wow.advance(60)
        Adv.leader(id, "back"); Adv.leader(id, "back") -- 成團 -> 已定案 -> 招募中
        local e = mineT(ns, id)
        for k in pairs(e) do ok(k:match("^%w+$"), "plain key " .. k) end
        eq(e.st, "o", "st stays one of o / g / c / x"); ok(e.fb, "the new field")
        -- An old reader decodes it (unknown fields pass through as strings).
        local list = Adv.decodeList(Adv.encodeList({ e }))
        eq(list[1].id, id, "decodes"); eq(list[1].st, "o", "same st")
        -- The worker ticket that closed keeps st = x (0.13.x and 0.12.x already hide it).
        Adv.setWorker({ dungeons = { "smg" }, main = "h", slots = { { now = true } }, hours = 1 })
        wow.state.now = wow.state.now + 2 * H; Adv.refresh(); Adv.maintain()
        eq(Adv.listOf(A, "W")[1].st, "x", "st x")
    end)

    ---------------------------------------------------------------------------
    -- v1.2a §17.6: R-17.18 / R-17.19
    ---------------------------------------------------------------------------

    -- A quest log through C_QuestLog (rows like GetInfo's), optional tag info.
    local function questLogRows(rows, tags)
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
        if tags then C_QuestLog.GetQuestTagInfo = function(id) return tags[id] end end
    end

    test("GF-002-I R-17.18 objectives complete, turned in or abandoned: off my worker ticket by itself", function()
        local ns = login()
        local Adv = ns.Adventure
        local rows = { { isHeader = true, title = "貧瘠之地" },
            { questID = 850, title = "測試任務：草原之心", level = 16 },
            { questID = 851, title = "測試任務：綠洲", level = 22 },
            { questID = 852, title = "測試任務：甲蟲", level = 20 } }
        questLogRows(rows)
        Adv.setWorker({ dungeons = { "smg" }, quests = { 850, 851, 852 }, main = "h", slots = { { now = true } } })
        eq(Adv.syncQuests(Adv.questLog()), false, "nothing done yet: unchanged")
        rows[2].isComplete = true -- 850: ready to turn in
        table.remove(rows, 4)    -- 852: abandoned (or turned in)
        ok(Adv.syncQuests(Adv.questLog()), "changed")
        eq(table.concat(Adv.myWorker().quests, ","), "851", "only 851 is left")
        -- The same on the classic GetQuestLogTitle (isComplete = 1, the 6th value) and through the event.
        C_QuestLog = nil
        GetNumQuestLogEntries = function() return 2, 0 end
        GetQuestLogTitle = function(i)
            if i == 1 then return "貧瘠之地", 0, nil, true end
            return "測試任務：綠洲", 22, 0, false, false, 1, 0, 851
        end
        ns.adventureStarted = true
        wow.fire("QUEST_LOG_UPDATE")
        wow.advance(3)
        eq(#Adv.myWorker().quests, 0, "851 complete: gone too (QUEST_LOG_UPDATE)")
        GetNumQuestLogEntries, GetQuestLogTitle = nil, nil
    end)

    test("GF-002-I R-17.19 自動: off by default, per character; group / elite quests I accept join my worker ticket (up to 5)", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local rows = { { isHeader = true, title = "貧瘠之地" },
            { questID = 900, title = "測試任務：獨行", level = 20 },
            { questID = 901, title = "測試任務：三人", level = 22, suggestedGroup = 3 },
            { questID = 902, title = "測試任務：精英", level = 24 },
            { questID = 903, title = "測試任務：地城", level = 25 } }
        questLogRows(rows, { [902] = { tagID = 0, tagName = "", isElite = true }, [903] = { tagID = 81, tagName = "地城" } })
        Adv.setWorker({ dungeons = { "smg" }, quests = {}, main = "h", slots = { { now = true } } })
        eq(Adv.autoAddOn(), false, "off by default")
        eq(Adv.onQuestAccepted(901), false, "off: nothing joins")
        -- The toggle in the worker window: 2 characters and an icon, kept per character at once.
        U.openWorker()
        local wf = _G[U.WORKER_NAME]
        eq(wf.autoAdd.label._text, "自動", "named 自動"); eq(wf.autoAdd.tip, "團體／精英任務", "the tooltip")
        ok(not wf.autoAdd.selected, "not chosen")
        wow.click(wf.autoAdd)
        ok(Adv.autoAddOn() and wf.autoAdd.selected, "on, and it glows")
        eq(Adv.local_().autoAdd[A], true, "kept for this character only")
        eq(Adv.local_().autoAdd[B], nil, "not for another")
        wf:Hide()
        -- Through the event (classic: questLogIndex, questID), after a second.
        ns.adventureStarted = true
        wow.fire("QUEST_ACCEPTED", 2, 900)
        wow.advance(2)
        eq(#Adv.myWorker().quests, 0, "a solo quest: not added")
        wow.fire("QUEST_ACCEPTED", 3, 901)
        wow.advance(2)
        eq(table.concat(Adv.myWorker().quests, ","), "901", "suggestedGroup 3: added")
        ok(Adv.onQuestAccepted(902), "isElite (C_QuestLog.GetQuestTagInfo): added")
        ok(Adv.onQuestAccepted(903), "tag ID 81 (dungeon): added")
        eq(Adv.onQuestAccepted(903), false, "once")
        -- The older GetQuestTagInfo with a tag name.
        rows[#rows + 1] = { questID = 904, title = "測試任務：團體", level = 25 }
        GetQuestTagInfo = function(id) if id == 904 then return 1, "Group" end end
        ok(Adv.onQuestAccepted(904), "GetQuestTagInfo Group: added")
        rows[#rows + 1] = { questID = 905, title = "測試任務：五", level = 25, suggestedGroup = 5 }
        rows[#rows + 1] = { questID = 906, title = "測試任務：六", level = 25, suggestedGroup = 5 }
        ok(Adv.onQuestAccepted(905), "the fifth")
        eq(Adv.onQuestAccepted(906), false, "the cap: " .. Adv.MAX_QUESTS)
        eq(#Adv.myWorker().quests, 5, "five")
        GetQuestTagInfo = nil
        -- No group information at all on the client: nothing happens, no error.
        Adv.setWorker({ dungeons = { "smg" }, quests = {}, main = "h", slots = { { now = true } } })
        questLogRows({ { questID = 950, title = "測試任務：未知", level = 20 } })
        eq(Adv.isGroupQuest(950, Adv.questLog()[950]), false, "nothing to tell: not a group quest")
        eq(Adv.onQuestAccepted(950), false, "nothing joins")
        -- Not added to a closed or a 日誌全部 worker ticket, nor without one.
        questLogRows(rows, {})
        Adv.setWorker({ dungeons = {}, allQuests = true, main = "h", slots = { { now = true } } })
        eq(Adv.onQuestAccepted(901), false, "日誌全部: already all")
        Adv.removeWorker()
        eq(Adv.onQuestAccepted(901), false, "no worker ticket")
        -- Off again.
        U.toggleAutoAdd()
        eq(Adv.autoAddOn(), false, "off")
        C_QuestLog = nil
    end)
end
