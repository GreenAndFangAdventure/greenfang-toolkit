-- GF-FIX-D (review GF-REVIEW-01 batch D, 0.16.6): the adventure module.
-- 高-4 quest log cache, 高-5 slotList guard, 中-3 other players' text,
-- 中-9 scrolling, 中-10 rowsFor once per change, 中-11 seen cleanup,
-- 中-12 an unknown quest log, 中-13 date() guards, 中-14 / 中-15 NativeLFG,
-- 低-23, 低-24, 低-26 (WorkerMatch), the leaderMenu icon. Offline only,
-- made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B, C, D = "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local H = 3600

    local function bigRoster(n)
        local list = wow.defaultRoster()
        for i = #list + 1, n do
            list[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 30, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = i % 2 == 0,
                guid = string.format("Player-0000-%08X", 0x100 + i) }
        end
        return list
    end
    local function author(i) return string.format("0000-%08X", 0x100 + i) end
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
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

    -- A quest log of n quests in zones of 5; counts every C_QuestLog.GetInfo call.
    local calls = { info = 0 }
    local function questLog(n)
        local rows = {}
        for i = 1, n do
            if (i - 1) % 5 == 0 then rows[#rows + 1] = { isHeader = true, title = "測試區域" .. math.floor((i - 1) / 5 + 1) } end
            rows[#rows + 1] = { questID = 3000 + i, title = "測試任務" .. i, level = 20 + i % 10 }
        end
        C_QuestLog = {
            GetNumQuestLogEntries = function() return #rows, 0 end,
            GetInfo = function(i) calls.info = calls.info + 1; return rows[i] end,
        }
        return rows
    end

    -- A busy page: 12 tickets of others (half quest tickets), 12 workers with quests,
    -- my worker ticket and 2 tickets I lead (so matching workers are listed).
    local function busyPage(ns)
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local sv = Adv.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } })
        for i = 5, 16 do
            local quest = i % 2 == 0
            offer(ns, author(i), "T", { { id = "a" .. i .. ".1", src = "g", ver = 1, cr = t, ds = quest and "" or "smg",
                qs = quest and tostring(3000 + i) or "", zn = quest and "測試區域1" or nil, tm = "n", ts = sv,
                rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        end
        for i = 17, 28 do
            offer(ns, author(i), "W", { { id = "w", cr = t, ds = "smg", qs = (3000 + i - 16) .. "." .. (3000 + i - 15),
                rm = "d", ra = "", sv = sv, ex = t + 86400, st = "o", sa = t } })
        end
        ok(Adv.setWorker({ dungeons = { "smg" }, quests = { 3001, 3002 }, main = "t", alt = "h", slots = { { now = true } } }), "my worker")
        ok(Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { now = true } } }), "mine 1")
        ok(Adv.open({ quests = { 3003 }, zone = "測試區域1", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { now = true } } }), "mine 2")
    end

    -- How many times rowsFor really computed (Adv.rowsStats when the cache has one).
    local function rowsCounter(Adv)
        local n = { calls = 0 }
        local orig = Adv.rowsFor
        Adv.rowsFor = function(...) n.calls = n.calls + 1; return orig(...) end
        return function()
            Adv.rowsFor = orig
            return Adv.rowsStats and Adv.rowsStats.computed or n.calls
        end
    end

    test("GF-FIX-D measure: C_QuestLog.GetInfo per page draw, rowsFor per ledger change", function()
        local ns = login({ roster = bigRoster(40) })
        local Adv, U = ns.Adventure, ns.AdventureUI
        questLog(25)
        busyPage(ns)
        ns.Framework.open("adventure")
        wow.advance(5)
        calls.info = 0
        U.refresh()
        local perDraw = calls.info
        -- One ledger change (someone's new ticket), then everything it sets off.
        local base = Adv.rowsStats and Adv.rowsStats.computed or 0
        local stop = rowsCounter(Adv)
        local t = ns.Share.serverNow()
        offer(ns, author(29), "T", { { id = "a29.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, now = true, s = t } }), rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        wow.advance(5)
        local perChange = stop() - base
        T.realPrint(string.format("     GFFIXD page draw: %d C_QuestLog.GetInfo calls; one ledger change: %d rowsFor computations",
            perDraw, perChange))
        GF_FIXD_MEASURE = { info = perDraw, rows = perChange }
        ok(perDraw == 0, "the log was read before the draw; the draw reads none: " .. perDraw)
        ok(perChange <= 1, "one ledger change: rowsFor worked out once: " .. perChange)
        C_QuestLog = nil
    end)

    ---------------------------------------------------------------------------
    -- 高-4: the quest log is kept, and a change shows at once
    ---------------------------------------------------------------------------

    test("GF-FIX-D 高-4 quest log: read once while unchanged; an event or a new count reads it again at once", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local rows = questLog(3)
        local reads0 = Adv.questLogStats.reads
        for _ = 1, 20 do U.questName(3001) end
        eq(Adv.questLogStats.reads - reads0, 1, "20 names, one read")
        eq(U.questName(3001), "測試任務1", "the name")
        -- The game renames it (a quest log change of the same size): the event, then at once.
        rows[2].title = "測試任務一（改）"
        wow.fire("QUEST_LOG_UPDATE")
        eq(U.questName(3001), "測試任務一（改）", "the change shows on the very next call")
        -- An objective done: the same.
        rows[2].isComplete = true
        wow.fire("QUEST_LOG_UPDATE")
        ok(Adv.questLog()[3001].complete, "complete at once")
        -- A quest more, even before any event: the count differs, read again.
        rows[#rows + 1] = { questID = 3999, title = "測試任務新", level = 30 }
        eq(U.questName(3999), "測試任務新", "a new quest at once")
        -- Every quest event marks it changed.
        for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
            local r = Adv.questLogStats.reads
            wow.fire(e, 3001); Adv.questLog()
            eq(Adv.questLogStats.reads - r, 1, e .. " reads again")
        end
        -- Another quest API (tests, a reload): read again.
        questLog(2)
        eq(U.questName(3002), "測試任務2", "the new API is read")
        C_QuestLog = nil
        eq(Adv.questLog(), nil, "no API: nil, as before")
    end)

    test("GF-FIX-D 高-4 without the quest events nothing is kept: every call reads the log", function()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        local Adv = ns.Adventure
        -- What a client without the events does: the frame's registrations fail.
        local f = Adv.questLogFrame
        ok(f, "the quest log watcher")
        wow.reset()
        local orig = CreateFrame
        CreateFrame = function(...)
            local fr = orig(...)
            fr.RegisterEvent = function(_, e) if e:match("^QUEST_") then error("unknown event " .. e) end end
            return fr
        end
        ns = wow.login(ADDON_DIR)
        CreateFrame = orig
        Adv = ns.Adventure
        questLog(3)
        local r = Adv.questLogStats.reads
        Adv.questLog(); Adv.questLog(); Adv.questLog()
        eq(Adv.questLogStats.reads - r, 3, "not watched: read every time")
        C_QuestLog = nil
    end)

    ---------------------------------------------------------------------------
    -- 中-12: an unknown log removes nothing, sends nothing
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-12 log not loaded yet: unknown, my worker ticket keeps its quests; known after a removal", function()
        local ns = login()
        local Adv = ns.Adventure
        local rows = {}
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
        ok(Adv.setWorker({ dungeons = {}, quests = { 3001, 3002 }, main = "d", slots = { { now = true } } }), "my worker")
        local set, found, known = Adv.questLog()
        eq(next(set), nil, "empty"); eq(found, false, "nothing found"); eq(known, false, "unknown")
        local before = Adv.ledger.version
        eq(Adv.syncQuests(set, known), false, "unknown: nothing removed")
        eq(Adv.syncQuests(set), false, "called without known (Init): an empty unknown set removes nothing")
        eq(#Adv.myWorker().quests, 2, "both quests kept")
        eq(Adv.ledger.version, before, "nothing written, nothing sent")
        -- Through the event path: the first QUEST_LOG_UPDATE at login, log still empty.
        wow.fire("QUEST_LOG_UPDATE"); wow.advance(3)
        eq(#Adv.myWorker().quests, 2, "the login event: kept")
        -- The log fills: known; then a quest turned in and the log is really empty.
        rows = { { questID = 3001, title = "測試任務1" } }
        wow.fire("QUEST_LOG_UPDATE"); wow.advance(3)
        local _, _, k2 = Adv.questLog()
        eq(k2, true, "known once a quest was seen")
        eq(table.concat(Adv.myWorker().quests, ","), "3001", "3002 left the log: removed")
        rows = {}
        wow.fire("QUEST_TURNED_IN", 3001); wow.advance(3)
        eq(#Adv.myWorker().quests, 0, "known empty log: the last quest goes")
        C_QuestLog = nil
    end)

    test("GF-FIX-D 中-12 a removal or turn-in proves the log is loaded (fresh session, empty log)", function()
        local ns = login()
        local Adv = ns.Adventure
        C_QuestLog = { GetNumQuestLogEntries = function() return 0, 0 end, GetInfo = function() return nil end }
        eq(Adv.questLogKnown(), false, "not known at login")
        wow.fire("QUEST_REMOVED", 3001)
        eq(Adv.questLogKnown(), true, "a removal: loaded")
        local _, _, known = Adv.questLog()
        eq(known, true, "known")
        C_QuestLog = nil
    end)

    ---------------------------------------------------------------------------
    -- 中-10 / 低-26: one change, one computation; a change is seen at once
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-10 rowsFor / workers(): shared while nothing changed, new at once after a change", function()
        local ns = login({ roster = bigRoster(30) })
        local Adv = ns.Adventure
        busyPage(ns)
        local c0, w0 = Adv.rowsStats.computed, Adv.rowsStats.workers
        local t1 = Adv.rowsFor(); Adv.rowsFor(); Adv.attentionCount()
        eq(Adv.rowsStats.computed - c0, 1, "three calls, one computation")
        Adv.workers(); Adv.workers(); ns.WorkerMatch.myWorker(); ns.WorkerMatch.candidates()
        ok(Adv.rowsStats.workers - w0 <= 1, "workers() once: " .. (Adv.rowsStats.workers - w0))
        -- A new ticket from someone: the very next call lists it (no waiting).
        local t = ns.Share.serverNow()
        offer(ns, author(29), "T", { { id = "a29.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, now = true, s = t } }), rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        local t2 = Adv.rowsFor()
        eq(#t2, #t1 + 1, "the new ticket at once")
        -- markSeen changes what needs attention: the next call sees it.
        local _, _, n1 = Adv.rowsFor()
        ok(n1 > 0, "something needs attention")
        Adv.markSeen()
        local _, _, n2 = Adv.rowsFor()
        ok(n2 < n1, "seen: fewer at once (" .. n1 .. " -> " .. n2 .. ")")
        -- A roster change (someone goes offline): new at once.
        local c1 = Adv.rowsStats.computed
        ns.Roster.version = ns.Roster.version + 1
        Adv.rowsFor()
        eq(Adv.rowsStats.computed - c1, 1, "roster changed: worked out again")
        -- The clock: the next second works it out again.
        local c2 = Adv.rowsStats.computed
        wow.advance(1)
        Adv.rowsFor()
        eq(Adv.rowsStats.computed - c2, 1, "a new second: again")
    end)

    ---------------------------------------------------------------------------
    -- 中-11: matching-worker seen keys go with their ticket
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-11 seen: 'm<ticket>|<worker>' keys of tickets gone are pruned; live ones stay", function()
        local ns = login()
        local Adv = ns.Adventure
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { now = true } } })
        local seen = Adv.local_().seen
        seen["m" .. id .. "|" .. B] = true
        seen["mazzz.gone|" .. B] = true
        seen["azzz.gone|match"] = true
        seen["w|x"] = true
        Adv.maintain()
        ok(seen["m" .. id .. "|" .. B], "a live ticket's worker key stays")
        eq(seen["mazzz.gone|" .. B], nil, "a gone ticket's worker key goes")
        eq(seen["azzz.gone|match"], nil, "a gone ticket's key goes (as before)")
        ok(seen["w|x"], "w keys untouched (as before)")
    end)

    ---------------------------------------------------------------------------
    -- 高-5 (the page's guard) and 中-13 (date)
    ---------------------------------------------------------------------------

    test("GF-FIX-D 高-5 slotList: more seats than a row shows builds no list (counted first)", function()
        local ns = login()
        local U = ns.AdventureUI
        local list, n = U.slotList({ capacity = { t = 2000000000, h = 1, d = 3 }, seats = {} })
        eq(#list, 0, "no list"); eq(n, 2000000004, "the count")
        list, n = U.slotList({ capacity = { any = 2000000000 }, seats = {} })
        eq(#list, 0, "any: no list"); eq(n, 2000000000, "the count")
        list, n = U.slotList({ capacity = { t = 1, h = 1, d = 2 }, seats = { d = 1 } })
        eq(#list, 4, "a normal ticket"); eq(n, 4, "4 seats")
        eq(U.roleText({ capacity = { t = 20, h = 10, d = 10 }, seats = {} }) ~= nil, true, "numbers per role")
    end)

    test("GF-FIX-D 中-13 date() giving nil: clock, day, dayText, dayStart never fail", function()
        local ns = login()
        local U = ns.AdventureUI
        local realDate = date
        date = function(fmt, t) if t and t > 3e10 then return nil end return realDate(fmt, t) end
        local far = 4e10
        eq(U.clock(far), "", "clock")
        eq(U.day(far), "", "day")
        eq(U.dayText(far), "", "dayText")
        ok(type(U.dayStart(0, far)) == "number", "dayStart")
        ok(type(U.slotText({ s = far, d = 3600 })) == "string", "a slot's text")
        date = function() error("time result cannot be represented") end
        eq(U.clock(1763370000), "", "an error from date(): nothing")
        date = realDate
        ok(U.clock(1763370000):match("^%d%d:%d%d$"), "back to normal")
    end)

    ---------------------------------------------------------------------------
    -- 中-3: other members' text on adventure tickets
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-3 a ticket's note, quest names and zone: no | sequences, at most 40 characters", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        local long = string.rep("長", 60)
        local e = { id = "abbb.9", src = "g", ver = 1, cr = t, ds = "", qs = "3001.3002", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, now = true, s = t } }), sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t,
            nt = "|TInterface\\Icons\\INV_Misc_QuestionMark:2000|t" .. long,
            qn = "3001:|Hquest:1|h假連結|h;3002:" .. long, zn = "|cffff0000假區域|r" .. long }
        ok(Adv.decodeList(Adv.encodeList({ e })), "the entry decodes")
        offer(ns, B, "T", { e })
        local v = Adv.get("abbb.9")
        ok(v, "the ticket")
        ok(not v.note:find("|", 1, true), "note: no |: " .. v.note)
        ok(#v.note <= 120 and select(2, v.note:gsub("[^\128-\191]", "")) <= 40, "note: at most 40 characters")
        ok(not v.questNames[3001]:find("|", 1, true), "quest name: no |")
        ok(select(2, v.questNames[3002]:gsub("[^\128-\191]", "")) <= 40, "quest name: at most 40")
        ok(not v.zone:find("|", 1, true), "zone: no |")
        ok(select(2, v.zone:gsub("[^\128-\191]", "")) <= 40, "zone: at most 40")
        local detail = U.detailText(v)
        ok(not detail:find("|T", 1, true) or not detail:find("2000", 1, true), "no foreign texture on the row")
        ok(not detail:find("|H", 1, true), "no link on the row")
        -- My own note keeps what I typed (cleanNote, unchanged).
        eq(Adv.cleanNote("慢慢打"), "慢慢打", "mine as before")
    end)

    ---------------------------------------------------------------------------
    -- 中-14 / 中-15: the group finder
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-14/中-15 group finder: events registered with pcall; results redraw the page at once", function()
        local ns = login()
        local L, U = ns.NativeLFG, ns.AdventureUI
        ok(type(L.missingEvents) == "table", "missing events listed (pcall)")
        eq(#L.missingEvents, 0, "the mock has both")
        ok(type(L.onChanged) == "function", "the page listens")
        ns.Framework.open("adventure")
        local n = 0
        local orig = U.refresh
        U.refresh = function(...) n = n + 1; return orig(...) end
        L.refresh()
        U.refresh = orig
        eq(n, 1, "the page redrawn by the results")
        -- Hidden page: nothing drawn.
        ns.Framework.toggle("adventure") -- the window closed
        ok(not ns.Framework.isModuleShown("adventure"), "page closed")
        n = 0
        U.refresh = function(...) n = n + 1; return orig(...) end
        L.refresh()
        U.refresh = orig
        eq(n, 0, "page hidden: no redraw")
    end)

    test("GF-FIX-D 中-3 group finder text: no | sequences", function()
        local ns = login()
        local L = ns.NativeLFG
        L.reset()
        local results = { { searchResultID = 1, activityID = 1, leaderName = "|cffff0000隊長|r", numMembers = 2,
            comment = "|TInterface\x:999|t來" .. string.rep("長", 80), name = "|Hx|h名|h" } }
        local api = C_LFGList
        C_LFGList = {
            GetSearchResults = function() return 1, { 1 } end,
            GetSearchResultInfo = function() return results[1] end,
            GetSearchResultMemberCounts = function() return {} end,
            GetActivityInfoTable = function() return { fullName = ns.AdventureData.byId.smg.name } end,
        }
        local list = L.read()
        C_LFGList = api
        L.reset()
        ok(list[1], "a result for 血色修道院：墓地")
        ok(not list[1].comment:find("|", 1, true), "comment: no |")
        ok(not list[1].leader:find("|", 1, true), "leader: no |")
        ok(not list[1].name:find("|", 1, true), "name: no |")
        ok(#list[1].comment <= 160, "comment short")
    end)

    ---------------------------------------------------------------------------
    -- 中-9: scrolling refills nothing inside the same rows; one party read a draw
    ---------------------------------------------------------------------------

    test("GF-FIX-D 中-9 scroll: the same first row fills nothing; another row fills; buttons keep one script", function()
        local ns = login({ roster = bigRoster(40) })
        local U = ns.AdventureUI
        busyPage(ns)
        ns.Framework.open("adventure")
        U.refresh()
        local stats = U.layoutStats()
        local f0 = stats.fills
        local sc = U.scrollFrame()
        sc:SetVerticalScroll(10); U.layoutRows(); U.layoutRows()
        eq(stats.fills, f0, "inside the first row: nothing filled again")
        local row
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view then row = r; break end end
        ok(row, "a ticket row")
        local b = row.buttons[1]
        local click, enter = b:GetScript("OnClick"), b:GetScript("OnEnter")
        sc:SetVerticalScroll(U.ROW_HEIGHT * 2); U.layoutRows()
        eq(stats.fills, f0 + 1, "two rows down: filled once")
        U.refresh()
        eq(b:GetScript("OnClick"), click, "the same OnClick after refills")
        eq(b:GetScript("OnEnter"), enter, "the same OnEnter after refills")
        -- Party read once a draw, not per row.
        local reads = 0
        local orig = ns.Adventure.partyAuthors
        ns.Adventure.partyAuthors = function(...) reads = reads + 1; return orig(...) end
        U.refresh()
        ns.Adventure.partyAuthors = orig
        eq(reads, 1, "one party read for the whole draw")
    end)

    test("GF-FIX-D 中-9 a worker row's tooltip lines are worked out when read, not on fill", function()
        local ns = login({ roster = bigRoster(40) })
        local U = ns.AdventureUI
        busyPage(ns)
        local n = 0
        local orig = U.workerTooltipLines
        U.workerTooltipLines = function(...) n = n + 1; return orig(...) end
        ns.Framework.open("adventure")
        U.refresh()
        eq(n, 0, "no tooltip lines on fill")
        local row
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.workerTip then row = r; break end end
        ok(row, "a worker row")
        ok(#row.workerTip.lines > 0, "the lines when read")
        local _ = row.workerTip.lines
        eq(n, 1, "worked out once")
        U.workerTooltipLines = orig
    end)

    ---------------------------------------------------------------------------
    -- 低-23, 低-24, the leaderMenu icon
    ---------------------------------------------------------------------------

    test("GF-FIX-D 低-23 skew asked once a second; calendar days in one pass", function()
        local ns = login()
        local U = ns.AdventureUI
        local n = 0
        local orig = GetServerTime
        GetServerTime = function() n = n + 1; return orig() end
        for _ = 1, 50 do U.skew() end
        ok(n <= 1, "50 skews, at most one GetServerTime: " .. n)
        wow.advance(1)
        U.skew()
        ok(n <= 2, "a new second: asked again")
        GetServerTime = orig
        local t = ns.Share.serverNow()
        ns.Adventure.open({ dungeon = "smg", leaderRole = "d", slots = { { s = t + 26 * H }, { s = t + 50 * H } } })
        local c = 0
        local all = ns.Adventure.all
        ns.Adventure.all = function(...) c = c + 1; return all(...) end
        local d1 = U.calendarItems(1); local d2 = U.calendarItems(2); U.calendarItems(3)
        ns.Adventure.all = all
        eq(#d1 + #d2 >= 1, true, "the ticket on its days")
        eq(c, 3, "Adv.all once per call (its own cache)")
    end)

    test("GF-FIX-D 低-24 the player's day, not the UTC day; a blocked invitation falls back to one by one", function()
        local ns = login()
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        local skew = t - ns.now()
        local d = date("*t", t - skew)
        eq(Adv.localDay(t), d.year * 1000 + d.yday, "the day on the player's clock")
        local endOfDay = t - skew - (d.hour * 3600 + d.min * 60 + d.sec) + 86399 + skew
        eq(Adv.legacyTime({ { id = 1, s = endOfDay } }, 1, t), "t", "late tonight is today")
        eq(Adv.legacyTime({ { id = 1, s = endOfDay + 2 } }, 1, t), "f", "past midnight is not")
        -- Blocked: no error, the client's event instead.
        local id = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local v = Adv.encodeList({ { id = id, ac = "ap", at = t + 1, ro = "t", rb = "" } })
        Adv.ledger:offer(B, "A", t + 1, ns.Share.hash(v), v)
        Adv.refresh()
        C_PartyInfo = { InviteUnit = function() wow.fire("ADDON_ACTION_BLOCKED", "GreenFangToolkit", "InviteUnit") end }
        local n, how = Adv.form(id)
        eq(n, 0, "nobody counted as invited"); eq(how, "one-by-one", "falls back")
        eq(#Adv.pendingInvites(), 1, "queued for 下一位")
        C_PartyInfo = nil
    end)

    test("GF-FIX-D 美術 leaderMenu 編輯 goes through tex(); a missing file draws nothing", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { now = true } } })
        local items = U.leaderMenu(Adv.get(id))
        local edit
        for _, it in ipairs(items) do if plain(it.text):find("編輯", 1, true) then edit = it end end
        ok(edit, "編輯 in the menu")
        eq(edit.text, U.tex("edit") .. " 編輯", "through tex()")
        local origHas = ns.GameIcons.has
        ns.GameIcons.has = function() return false end
        -- GF-UI-N: 編輯 is GameIcons art now: none of its files known → the last
        -- candidate (a plain note every client ships), never a green box.
        ok(U.tex("edit"):find("INV_Misc_Note_01", 1, true), "no file: the last candidate")
        eq(U.tex("not-a-key"), "", "an unknown file: no markup")
        ns.GameIcons.has = origHas
    end)
end
