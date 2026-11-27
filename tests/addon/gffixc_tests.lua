-- GF-FIX-C (review GF-REVIEW-01 high-2, high-3, batch C): the roster scan
-- keeps the snapshot when nothing changed (Roster.version), the recipe index
-- keys on it, the searches redraw at most 0.15 s after a key, and the login
-- steps no longer rescan the roster. Owner rule: what changed shows as fast
-- as before. Made-up names and GUIDs only; offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function roster(n)
        local list = wow.defaultRoster()
        for i = #list + 1, n do
            list[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60,
                class = "戰士", classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0,
                guid = string.format("Player-0000-%08X", 0x100 + i),
                club = { race = 2, profession1ID = 164, profession2ID = 186 } }
        end
        return list
    end

    local function login(n)
        wow.reset({ roster = roster(n or 4) })
        local ns = wow.login(ADDON_DIR)
        wow.advance(130) -- every login step has run
        return ns
    end

    local function memberNamed(ns, name)
        for _, m in ipairs(ns.Roster.current().members) do if m.name == name then return m end end
    end

    local function count(tbl, key)
        local n = { calls = 0 }
        local orig = tbl[key]
        tbl[key] = function(...) n.calls = n.calls + 1; return orig(...) end
        return n, function() tbl[key] = orig end
    end

    test("GF-FIX-C roster unchanged: same snapshot, same version, no outbox write, no redraw", function()
        local ns = login(1000)
        local R = ns.Roster
        local snap, version, rebuilds, writes = R.current(), R.version, R.rebuilds, R.outboxWrites
        ok(version > 0, "a scan went through")
        local notified, restore = count(ns.UI, "afterAutoScan")
        local recorded, restore2 = count(ns.Sync, "recordRoster")
        local before = wow.state.rosterInfoCalls
        for _ = 1, 5 do wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(1) end
        restore(); restore2()
        eq(wow.state.rosterInfoCalls - before, 5 * 1000, "every event still reads every row (nothing delayed)")
        ok(R.current() == snap, "same snapshot object")
        eq(R.version, version, "Roster.version unchanged")
        eq(R.rebuilds, rebuilds, "no rebuild")
        eq(R.outboxWrites, writes, "nothing written to the outbox")
        eq(recorded.calls, 0, "Sync.recordRoster not called")
        eq(notified.calls, 0, "the roster page is not told")
        local ok1, n, s, changed = R.collect()
        ok(ok1 and n == 1000 and s == snap, "collect: ok, count, the same snapshot")
        eq(changed, false, "collect says unchanged")
        ok(s.capturedAt == ns.now(), "the time of the scan still moves")
    end)

    test("GF-FIX-C one member changes: reflected by the very next scan, other members kept", function()
        local ns = login(1000)
        local R = ns.Roster
        local snap, version = R.current(), R.version
        local other = memberNamed(ns, "成員0600-測試伺服器")
        local writes = R.outboxWrites
        local notified, restore = count(ns.UI, "afterAutoScan")
        -- 上線: the same 0.8 s merge as before, no minimum gap.
        local m = wow.state.roster[500]
        m.online = not m.online
        wow.fire("GUILD_ROSTER_UPDATE")
        wow.advance(0.8)
        ok(R.current() ~= snap, "a new snapshot")
        eq(R.version, version + 1, "Roster.version + 1")
        eq(memberNamed(ns, m.name).online, m.online, "the change is in the snapshot")
        ok(memberNamed(ns, "成員0600-測試伺服器") == other, "unchanged members keep their table")
        eq(notified.calls, 1, "the roster page is told at once")
        eq(R.outboxWrites, writes, "online is not uploaded: outbox not rewritten")
        -- 升級 then 換區, one after the other: each shows at the next scan.
        m.level = 61
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        eq(memberNamed(ns, m.name).level, 61, "level up shown")
        eq(R.outboxWrites, writes + 1, "level is uploaded: roster.snapshot written")
        eq(R.version, version + 2, "version + 1 again")
        m.zone = "幽暗城"
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        eq(memberNamed(ns, m.name).zone, "幽暗城", "zone change shown")
        -- 有人入會 / 離會.
        table.insert(wow.state.roster, { name = "新人-測試伺服器", rank = "新進", level = 5, class = "法師",
            classToken = "MAGE", zone = "杜洛塔", online = true, guid = "Player-0000-0FFFFFFF" })
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        eq(R.current().total, 1001, "new member shown")
        table.remove(wow.state.roster)
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        eq(R.current().total, 1000, "member who left gone")
        restore()
        eq(notified.calls, 5, "every change redrew the page")
    end)

    test("GF-FIX-C login steps: subsystems start as before without rescanning the roster", function()
        wow.reset({ roster = roster(4) })
        local ns = wow.login(ADDON_DIR)
        wow.advance(130)
        ok(ns.shareStarted and ns.ordersStarted and ns.adventureStarted and ns.pricesStarted, "all four started")
        eq(ns.Roster.scans, 1, "one roster scan (the login one), not one per login step")
        -- No good scan yet (e.g. in combat at the time): the step scans, as before.
        wow.reset({ roster = roster(4) })
        ns = wow.loadAddon(ADDON_DIR)
        wow.fire("PLAYER_LOGIN")
        wow.enterCombat()
        wow.advance(10)
        eq(ns.Roster.scans, 0, "no scan in combat")
        wow.leaveCombat()
        wow.advance(1)
        ok(ns.Roster.scans >= 1, "scanned after combat")
        wow.advance(125)
        ok(ns.shareStarted and ns.ordersStarted and ns.adventureStarted and ns.pricesStarted, "all four started")
    end)

    test("GF-FIX-C logout: roster.snapshot carries the time of the last scan", function()
        local ns = login(4)
        wow.advance(600)
        ns.Roster.collect() -- unchanged: no write now
        local at = ns.Roster.current().capturedAt
        wow.logout()
        local found
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do
            if e.kind == "roster.snapshot" then found = e end
        end
        ok(found, "roster.snapshot in the outbox")
        eq(found.capturedAt, at, "time of the last scan")
        eq(#found.payload.members, 4, "every member")
    end)

    test("GF-FIX-C recipe index: kept while nothing changed, rebuilt at once on a real change", function()
        local ns = login(1000)
        local R = ns.Recipes
        local idx = R.index()
        local builds = R.builds
        for _ = 1, 3 do wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(1) end
        ok(R.index() == idx, "same index after scans that found nothing new")
        eq(R.builds, builds, "no rebuild")
        local m = wow.state.roster[700]
        m.online = not m.online
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        local idx2 = R.index()
        ok(idx2 ~= idx, "rebuilt after the roster changed")
        eq(R.builds, builds + 1, "one rebuild")
        ok(R.index() == idx2, "and kept again")
        -- Shared data (Share.version) still rebuilds it at once.
        ns.Share.ownRecord("R165", ns.Share.encodeValue("R165", { 2149, 2152 }))
        local idx3 = R.index()
        ok(idx3 ~= idx2, "rebuilt after Share changed")
        ok(idx3[165] and idx3[165].recipes[2149], "the new recipe is in it")
        -- openOrder with known crafters builds nothing.
        local b = R.builds
        ns.OrdersUI.openOrder({ recipe = 2149, skill = 165 })
        ns.OrdersUI.openOrder({ recipe = 2149, skill = 165 })
        eq(R.builds, b, "openOrder: no rebuild while nothing changed")
    end)

    test("GF-FIX-C searches: first key at once, a burst of keys one more redraw at most 0.15 s later", function()
        local ns = login(4)
        local UI = ns.OrdersUI
        eq(UI.PICKER_DELAY <= 0.15, true, "picker delay")
        eq(ns.Recipes.SEARCH_DELAY <= 0.15, true, "recipe page delay")
        local f = UI.openPicker()
        local drawn = {}
        local orig = UI.drawPicker
        UI.drawPicker = function(...) drawn[#drawn + 1] = f.query; return orig(...) end
        local box = f.search
        for _, text in ipairs({ "製", "製皮", "製皮甲" }) do
            box:SetText(text)
            box._scripts.OnTextChanged(box, true)
            wow.advance(0.03)
        end
        eq(table.concat(drawn, "|"), "製", "the first key at once, the next ones wait")
        wow.advance(0.07) -- just past 0.15 s after the first key
        eq(table.concat(drawn, "|"), "製|製皮甲", "one more redraw, with the latest text")
        wow.advance(1)
        eq(#drawn, 2, "nothing more without keys")
        UI.drawPicker = orig
        -- The recipe page.
        ns.Framework.open("recipes")
        local refreshes, restore2 = count(ns.Recipes, "refresh")
        local search = ns.Recipes.searchBox
        search:SetText("a"); search._scripts.OnTextChanged(search)
        eq(refreshes.calls, 1, "the first key at once")
        search:SetText("ab"); search._scripts.OnTextChanged(search)
        search:SetText("abc"); search._scripts.OnTextChanged(search)
        eq(refreshes.calls, 1, "not on every key")
        wow.advance(0.16)
        eq(refreshes.calls, 2, "one more redraw 0.15 s after the first key")
        restore2()
    end)

    test("GF-FIX-C profession window events: first read at once, a burst makes one more", function()
        local ns = login(4)
        local R = ns.Recipes
        local reads = 0
        local origOwn, origScan = R.isOwnWindow, R.scan
        R.isOwnWindow = function() return true end
        R.scan = function() reads = reads + 1; return "same" end
        wow.fire("TRADE_SKILL_SHOW")
        eq(reads, 1, "read at once")
        for _ = 1, 6 do wow.fire("TRADE_SKILL_LIST_UPDATE") end
        eq(reads, 1, "a burst is not read event by event")
        wow.advance(R.SCAN_GAP)
        eq(reads, 2, "one more read at the end of the burst")
        wow.advance(R.SCAN_GAP)
        eq(reads, 2, "nothing more without events")
        wow.advance(6)
        R.isOwnWindow, R.scan = origOwn, origScan
    end)

    test("GF-FIX-C quest log: an empty log at login is not passed on; a removal is", function()
        local ns = login(4)
        local A = ns.Adventure
        local synced = {}
        local origLog, origSync = A.questLog, A.syncQuests
        local log = {}
        A.questLog = function() return log, next(log) ~= nil end
        A.syncQuests = function(l) synced[#synced + 1] = l end
        wow.fire("QUEST_LOG_UPDATE"); wow.advance(2)
        eq(#synced, 0, "empty log, not known to be loaded: not passed on")
        log = { [101] = { title = "測試任務" } }
        wow.fire("QUEST_LOG_UPDATE"); wow.advance(2)
        eq(#synced, 1, "a filled log is passed on")
        log = {}
        wow.fire("QUEST_LOG_UPDATE"); wow.advance(2)
        eq(#synced, 2, "once the log was seen filled, an empty one is real")
        A.questLog, A.syncQuests = origLog, origSync
        -- A fresh session: the last quest turned in, with nothing seen before.
        ns = login(4)
        A = ns.Adventure
        synced = {}
        A.questLog = function() return {}, false end
        A.syncQuests = function(l) synced[#synced + 1] = l end
        wow.fire("QUEST_TURNED_IN", 101); wow.advance(2)
        eq(#synced, 1, "a turn-in proves the log is loaded")
    end)

    test("GF-FIX-C orders page: focus mark path, scroll without moving rows, one rowsFor per refresh", function()
        local f = io.open(ADDON_DIR .. "/OrdersUI.lua", "r")
        local src = f:read("*a"); f:close()
        ok(not src:find('"Interface\\Q', 1, true), "no single-backslash texture path")
        local ns = login(4)
        local UI = ns.OrdersUI
        ns.Framework.open("orders")
        local rows, restore = count(ns.Orders, "rowsFor")
        UI.refresh()
        eq(rows.calls, 1, "one rowsFor for the page and the badge")
        restore()
        eq(UI.layoutRows(true), false, "a scroll within the same rows redraws nothing")
    end)

    test("GF-FIX-C diag and talents: one refresh when opening; the summary uses the cached read", function()
        local ns = login(4)
        local refreshes, restore = count(ns.Diag, "refresh")
        ns.Diag.open()
        ok(refreshes.calls <= 1, "opening refreshes once: " .. refreshes.calls)
        restore()
        local reads, restore2 = count(ns.Talents, "read")
        ns.Talents.own()
        ns.Talents.summaryLine(); ns.Talents.summaryLine()
        restore2()
        ok(reads.calls <= 1, "trait tree read at most once: " .. reads.calls)
    end)
end
