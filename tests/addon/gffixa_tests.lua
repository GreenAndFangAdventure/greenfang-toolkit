-- GF-FIX-A: the communication core's caches and guards (review GF-REVIEW-01
-- 高-1, 高-5 / 中-13 decode side, 中-1, 中-2, 中-3, 低-1~3, 5, 6) and the
-- location sharing switch (D-019). Offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function bigRoster(n)
        local list = wow.defaultRoster()
        for i = #list + 1, n do
            list[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60,
                class = "戰士", classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0,
                guid = string.format("Player-0000-%08X", 0x100 + i) }
        end
        return list
    end

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        wow.advance(2)
        return ns
    end

    -- Count calls of the game functions Data.player() / guildKey() read.
    local API = { "UnitGUID", "UnitName", "GetGuildInfo", "IsInGuild", "UnitLevel", "UnitClass",
        "UnitRace", "UnitFactionGroup", "GetRealmName", "GetNormalizedRealmName", "IsPlayerInGuildFromGUID" }
    local function counting()
        local n, saved = { calls = 0 }, {}
        for _, name in ipairs(API) do
            local fn = _G[name]
            if type(fn) == "function" then
                saved[name] = fn
                _G[name] = function(...) n.calls = n.calls + 1; return fn(...) end
            end
        end
        return n, function() for name, fn in pairs(saved) do _G[name] = fn end end
    end
    local function measure(label, fn)
        local n, restore = counting()
        collectgarbage("collect")
        collectgarbage("stop")
        local kb0, t0 = collectgarbage("count"), os.clock()
        fn()
        local ms, kb = (os.clock() - t0) * 1000, collectgarbage("count") - kb0
        collectgarbage("restart")
        restore()
        T.realPrint(string.format("     GFFIXA %s: %d game API calls, %.1f ms, %.0f KB allocated", label, n.calls, ms, kb))
        return n.calls, ms, kb
    end

    test("GF-FIX-A measure: 1000 members, sort by roles and 1000 Share.store()", function()
        local ns = login({ roster = bigRoster(1000) })
        local members = {}
        for i, m in ipairs(ns.Roster.current().members) do members[i] = m end
        eq(#members, 1000, "1000 members")
        local sortCalls = measure("sort 1000 by roles", function() ns.UI.sortMembers(members, "roles", true) end)
        local storeCalls = measure("1000 x Share.store()", function()
            for _ = 1, 1000 do ns.Share.store() end
        end)
        local ledgerCalls = measure("1000 x Ledger:get()", function()
            for _ = 1, 1000 do ns.Adventure.ledger:get("0000-0000000B", "T") end
        end)
        GF_FIXA_MEASURE = { sort = sortCalls, store = storeCalls, ledger = ledgerCalls }
        -- After GF-FIX-A: one game call per store() (the live guild name), no garbage.
        ok(storeCalls <= 1000, "Share.store() reads at most one game value: " .. storeCalls)
        ok(ledgerCalls <= 1000, "Ledger:get() reads at most one game value: " .. ledgerCalls)
    end)

    ---------------------------------------------------------------------------
    -- 高-1: caches that can never be stale
    ---------------------------------------------------------------------------

    test("GF-FIX-A ns.call: results, nils in the middle, errors and missing functions", function()
        local ns = login()
        local a, b, c = ns.call(function() return 1, nil, 3 end)
        eq(a, 1, "first"); eq(b, nil, "middle nil"); eq(c, 3, "third")
        eq(select("#", ns.call(function() error("boom") end)), 0, "an error gives nothing")
        eq(select("#", ns.call(nil)), 0, "no function gives nothing")
        eq(ns.call(function(x, y) return x + y end, 2, 5), 7, "arguments passed")
        eq(ns.selfGUID(), "Player-0000-0000000A", "selfGUID")
    end)

    test("GF-FIX-A Data.player / guildKey / selfAuthor follow the game at once (no event needed)", function()
        local ns = login()
        local key = ns.Sync.guildKey()
        eq(key, "測試伺服器|綠皮與獠牙冒險事務所", "guild key")
        local p = ns.Data.player()
        p.guild, p.level = "changed by a caller", 1
        eq(ns.Data.player().level, 32, "a caller's change never leaks into the next call")
        wow.state.player.level = 40
        eq(ns.Data.player().level, 40, "level read live")
        wow.state.player.guildRank = "幹部"
        eq(ns.Data.player().guildRank, "幹部", "rank read live")
        -- The client briefly reports no guild (logout, /reload): the session's guild, as before.
        wow.state.guildInfoGone = true
        eq(ns.Sync.guildKey(), key, "session guild kept while the client reports none")
        wow.state.guildInfoGone = false
        wow.state.player.guild = "別的公會"
        eq(ns.Sync.guildKey(), "測試伺服器|別的公會", "another guild: a new key on the next call")
        wow.state.player.guild = "綠皮與獠牙冒險事務所"
        eq(ns.Sync.guildKey(), key, "back")
        eq(ns.Share.selfAuthor(), "0000-0000000A", "author")
        wow.state.player.guid = "Player-0000-000000FF"
        eq(ns.Share.selfAuthor(), "0000-000000FF", "a new GUID gives a new author at once")
        eq(ns.Data.player().guid, "Player-0000-000000FF", "and a new player table")
    end)

    ---------------------------------------------------------------------------
    -- 中-3: text from others
    ---------------------------------------------------------------------------

    test("GF-FIX-A cleanText and the Z / B decoders drop escapes, control characters, huge names", function()
        local ns = login()
        eq(ns.cleanText("|TInterface\\Icons\\X:999|t奧格瑪|cffff0000紅|r"), "TInterface\\Icons\\X:999t奧格瑪cffff0000紅r", "no |")
        eq(ns.cleanText("a\nb\0c"), "abc", "no control characters")
        local long = string.rep("奧", 40) -- 120 bytes
        local cut = ns.cleanText(long, 64)
        eq(#cut, 63, "cut at a character boundary")
        eq(cut, string.rep("奧", 21), "whole characters only")
        local S = ns.Share
        local z = S.decodeValue("Z", "|TInterface\\Icons\\Spell_Fire:4000|t/" .. long)
        ok(not z.zone:find("|", 1, true), "zone without |")
        ok(#z.subZone <= 64, "subzone at most 64 bytes")
        eq(S.decodeValue("Z", "|/x"), nil, "a zone that is only escapes is no zone")
        eq(S.decodeValue("B", "60.|cffWARRIOR").classToken, nil, "bad class token dropped")
        eq(S.decodeValue("B", "60.WARRIOR").classToken, "WARRIOR", "good class token kept")
        local d = ns.Comm.decodeBody("L=40;T=1763370000;Z=|Hitem:1|h奧格瑪|h")
        if d and d.location then ok(not d.location.zone:find("|", 1, true), "0.8.x zone cleaned") end
    end)

    ---------------------------------------------------------------------------
    -- 中-1: GUILD queue
    ---------------------------------------------------------------------------

    local PEER, THIRD = "測試乙-測試伺服器", "測試丙-測試伺服器"
    local A_SELF, A_PEER, A_THIRD = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local function shareLogin(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        wow.advance(25)
        return ns
    end
    local function sent(kind)
        local list = {}
        for _, s in ipairs(wow.state.sent) do
            if s.prefix == "GFTKS" and (not kind or s.msg:sub(1, #kind + 4) == "S1~" .. kind .. "~") then
                list[#list + 1] = s
            end
        end
        return list
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function vMsg(ns, a, g, t, value)
        local v = ns.Share.encodeValue(g, value)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end

    test("GF-FIX-A queue: a catalog reply still queued is dropped when someone else answers first", function()
        local ns = shareLogin()
        local S = ns.Share
        wow.state.sent = {}
        eq(from(ns, PEER, "S1~Q~qq1~0~xx~w2"), "ok", "Q taken")
        ns.combatFlag = true -- nothing can go out
        wow.advance(3)
        local queued = S.queued()
        ok(queued > 0, "our catalog reply is queued")
        from(ns, THIRD, "S1~C~qq1~1~1~" .. A_PEER .. ".zz.1")
        eq(S.queued(), queued - 1, "dropped once someone else's C for the same request came")
        eq(S.stats.cancelled, 1, "counted")
        ns.combatFlag = false
        wow.advance(5)
        eq(#sent("C"), 0, "our C never went out")
    end)

    test("GF-FIX-A queue: replies to others expire after CONTROL_STALE; own requests stay; busy leaves Q to others", function()
        local ns = shareLogin()
        local S = ns.Share
        ns.combatFlag = true
        S.sendIndex(A_SELF, "index|" .. A_SELF)
        local before = S.queued()
        ok(before > 0, "index queued")
        wow.advance(S.CONTROL_STALE + 5)
        eq(S.queued(), 0, "the stale index is gone")
        ns.combatFlag = false
        local busy = S.BUSY_CONTROL
        S.BUSY_CONTROL = 0
        eq(from(ns, PEER, "S1~Q~qq2~0~xx~w2"), "busy", "busy: Q left to the others")
        S.BUSY_CONTROL = busy
        local cap = S.MAX_GUILD_CONTROL
        S.MAX_GUILD_CONTROL = 0
        eq(S.enqueue("S1~I~x~1~w2~B.1.a", "index", nil, "index|x"), false, "over the cap: a reply index is not queued")
        eq(S.enqueue("S1~I~x~1~w2~B.1.a", "index"), true, "my own index always is")
        eq(S.enqueue("S1~Q~x~0~a~w2", "ask"), true, "our own request always is")
        S.MAX_GUILD_CONTROL = cap
    end)

    test("GF-FIX-A K: a claim is only kept for known members and groups", function()
        local ns = shareLogin()
        eq(from(ns, PEER, "S1~K~nobody~" .. A_PEER .. ".B"), "malformed", "unknown requester")
        eq(from(ns, PEER, "S1~K~" .. A_THIRD .. "~" .. A_PEER .. ".B~nobody.B~" .. A_PEER .. ".junk"), "claim", "known parts kept")
    end)

    ---------------------------------------------------------------------------
    -- 中-2: forged records and self-repair
    ---------------------------------------------------------------------------

    test("GF-FIX-A a record more than two minutes ahead is refused", function()
        local ns = shareLogin()
        eq(from(ns, PEER, vMsg(ns, A_PEER, "B", wow.state.now + 300, { level = 61 })), "future", "300 s ahead")
        eq(from(ns, PEER, vMsg(ns, A_PEER, "B", wow.state.now + 60, { level = 61 })), "new", "60 s ahead is fine")
    end)

    test("GF-FIX-A someone else's newer value for me is not stored; mine goes out again after it", function()
        local ns = shareLogin()
        local S = ns.Share
        local mine = S.get(A_SELF, "B")
        ok(mine, "my B")
        wow.state.sent = {}
        local forgedT = wow.state.now + 100
        eq(from(ns, PEER, vMsg(ns, A_SELF, "B", forgedT, { level = 1, classToken = "MAGE" })), "healed", "refused")
        eq(S.get(A_SELF, "B").h, mine.h, "my own value kept")
        wow.advance(S.HEAL_DELAY + 1)
        local out = sent("V")
        local found
        for _, m in ipairs(out) do
            local a, g, t = m.msg:match("^S1~V~([^~]+)~([^~]+)~([^~]+)~")
            if a == A_SELF and g == "B" then found = S.unb36(t) end
        end
        ok(found and found > forgedT, "my B re-published with a t after the forgery")
        eq(S.stats.healed, 1, "counted")
        -- The same value, or an older one, is the normal path.
        eq(from(ns, PEER, "S1~V~" .. A_SELF .. "~B~" .. S.b36(S.get(A_SELF, "B").t) .. "~" .. mine.h .. "~" .. mine.v), "same", "same value")
    end)

    test("GF-FIX-A someone else's withdrawal of my location is not applied while I share it", function()
        local ns = shareLogin()
        local S = ns.Share
        ok(S.get(A_SELF, "Z"), "my Z")
        wow.state.sent = {}
        eq(from(ns, PEER, "S1~X~" .. A_SELF .. "~Z~" .. S.b36(wow.state.now + 50)), "healed", "refused")
        ok(S.get(A_SELF, "Z"), "still there")
        wow.advance(S.HEAL_DELAY + 1)
        ok(#sent("V") >= 1, "my Z went out again")
    end)

    test("GF-FIX-A observeOwn: a changed value goes after a later record already held", function()
        local ns = shareLogin()
        local S = ns.Share
        local s = S.store()
        local ahead = S.serverNow() + 100
        s.rec[A_SELF].B = { t = ahead, h = "zzzz", v = "1.MAGE", fromAuthor = true }
        S.observeOwn()
        eq(S.get(A_SELF, "B").t, ahead + 1, "after the record held")
        ok(S.get(A_SELF, "B").h ~= "zzzz", "my value")
    end)

    ---------------------------------------------------------------------------
    -- 低-1, 低-3, 低-5
    ---------------------------------------------------------------------------

    test("GF-FIX-A a failing listener does not stop the message handling", function()
        local ns = shareLogin()
        ns.Share.onUpdate(function() error("page bug") end)
        eq(from(ns, PEER, vMsg(ns, A_PEER, "B", wow.state.now, { level = 59 })), "new", "handled")
        eq(ns.Share.decoded(A_PEER, "B").level, 59, "stored")
    end)

    test("GF-FIX-A forget also drops the roster window's copy; 0.8.x time never after the realm's", function()
        local ns = shareLogin()
        local S = ns.Share
        ns.db.peers = ns.db.peers or {}
        ns.db.peers["someone-x"] = { guid = S.guidOf("0000-0000ABCD"), name = "someone-x" }
        S.forget(S.store(), "0000-0000ABCD")
        eq(ns.db.peers["someone-x"], nil, "peer dropped")
        local member = ns.Comm.memberFor(THIRD)
        S.fromV1(member, { capturedAt = S.serverNow() + 90, level = 30 })
        eq(S.get(A_THIRD, "B").t, S.serverNow(), "clamped to the realm's clock")
    end)

    ---------------------------------------------------------------------------
    -- 高-5 / 中-13 (decode side)
    ---------------------------------------------------------------------------

    test("GF-FIX-A adventure: a ticket with a huge head count is refused; no loop past its limit", function()
        local ns = login()
        local A = ns.Adventure
        eq(A.decodeEntry("id=x1,ds=rfc,rt=zzzzzz"), nil, "rt = 2 billion refused")
        eq(A.decodeEntry("id=x1,sz=15"), nil, "sz 41 refused") -- 15 base 36 = 41
        ok(A.decodeEntry("id=x1,sz=14"), "sz 40 kept")
        eq(A.decodeEntry("id=x1,s=zzzzzzzzz"), nil, "a time past 2100 refused")
        local bad = "id=x1,ds=rfc,rt=zzzzzz"
        eq(A.decodeList(bad), nil, "the list is invalid")
        eq(A.ledger.cfg.validValue(A_PEER, "T", bad), false, "the record is refused")
        -- The largest accepted ticket: every seat loop stays small.
        local t = A.decodeEntry("id=x1,ds=rfc,rt=14,rh=14,rd=14")
        local cap = A.capacity(t)
        local seats = (cap.t or 0) + (cap.h or 0) + (cap.d or 0)
        ok(seats <= 120, "at most 120 seats: " .. seats)
        local list = ns.AdventureUI and ns.AdventureUI.slotList and ns.AdventureUI.slotList({ capacity = cap, seats = {} })
        if list then ok(#list <= 120, "slot list bounded") end
        local q = A.decodeEntry("id=x2,sz=14")
        ok(A.capacity(q).any <= 39, "quest ticket bounded")
        -- Slots: past 2100 or a length over 7 days is dropped.
        local slots = A.decodeTimes("1-" .. ns.Share.b36(1763370000) .. "-" .. ns.Share.b36(3600) .. "-_2-zzzzzzzzz--_3-"
            .. ns.Share.b36(1763370000) .. "-" .. ns.Share.b36(8 * 86400) .. "-")
        eq(#slots, 1, "only the sane slot")
        eq(slots[1].id, 1, "slot 1")
    end)

    ---------------------------------------------------------------------------
    -- D-019: location sharing switch
    ---------------------------------------------------------------------------

    local function selfEntry()
        for _, e in ipairs(GreenFangToolkitDB.sync.outbox) do
            if e.kind == "character.self" then return e end
        end
    end

    test("GF-FIX-A D-019 location switch: on by default, off withdraws, on shares again", function()
        local ns = shareLogin()
        local S, Sync = ns.Share, ns.Sync
        eq(Sync.shareLocation(), true, "on by default")
        eq(GreenFangToolkitDB.settings.shareLocation, nil, "nothing saved for the default")
        eq(GreenFangToolkitDB.sync.shareLocation, nil, "the old D-015 field stays unused")
        Sync.recordSelf(true)
        ok(selfEntry().payload.location, "location uploaded")
        wow.state.sent = {}
        ok(Sync.setShareLocation(false), "turned off")
        wow.advance(1)
        eq(GreenFangToolkitDB.settings.shareLocation, false, "saved")
        eq(S.get(A_SELF, "Z"), nil, "my Z withdrawn")
        ok(S.store().tomb[A_SELF].Z, "tombstone kept")
        local x = sent("X")
        eq(#x, 1, "one withdrawal on GUILD")
        ok(x[1].msg:find("~" .. A_SELF .. "~Z~", 1, true), "for my Z")
        eq(x[1].chatType, "GUILD", "on GUILD")
        eq(selfEntry().payload.location, nil, "outbox written without the location")
        eq(ns.Comm.ownData().location, nil, "the 0.8.x broadcast leaves it out")
        S.observeOwn()
        eq(S.get(A_SELF, "Z"), nil, "observing does not share it again")
        -- An old copy relayed back while off: not stored, my withdrawal goes out again.
        wow.state.sent = {}
        eq(from(ns, PEER, vMsg(ns, A_SELF, "Z", S.serverNow() + 30, { zone = "奧格瑪" })), "healed", "relayed copy refused")
        eq(S.get(A_SELF, "Z"), nil, "still withdrawn")
        wow.advance(S.HEAL_DELAY + 1)
        eq(#sent("X"), 1, "withdrawal sent again")
        -- Someone else's withdrawal is fine while off.
        eq(from(ns, PEER, "S1~X~" .. A_SELF .. "~Z~" .. S.b36(S.serverNow() + 40)), "tomb", "accepted when off")
        eq(Sync.setShareLocation(false), false, "already off")
        wow.advance(2)
        wow.state.sent = {}
        ok(Sync.setShareLocation(true), "on again")
        wow.advance(1)
        eq(GreenFangToolkitDB.settings.shareLocation, nil, "default again")
        ok(S.get(A_SELF, "Z"), "my Z back")
        local z
        for _, m in ipairs(sent("V")) do if m.msg:find("~" .. A_SELF .. "~Z~", 1, true) then z = m end end
        ok(z, "shared again at once")
        ok(selfEntry().payload.location, "uploaded again")
    end)

    test("GF-FIX-A D-019: the switch in the 事務設定 window (同步與診斷)", function()
        local ns = shareLogin()
        ns.Diag.toggle()
        local c = ns.Diag.locationCheck
        ok(c, "check box")
        eq(c.label._text, "分享位置", "label")
        eq(c.checked, true, "ticked by default")
        local x = c._points and c._points[1] and c._points[1][4] or 0
        T.realPrint(string.format("     GFFIXA location check at x=%d, right edge %d of %d", x, x + 28 + ns.labelWidth("分享位置"), ns.Diag.WIDTH))
        ok(x + 28 + ns.labelWidth("分享位置") <= ns.Diag.WIDTH - 12, "inside the window")
        local state = ns.Diag.window() and ns.Diag.window().state
        if state and state._text then
            ok(20 + ns.labelWidth(state._text) < x, "clear of the status line: " .. state._text)
        end
        wow.click(c)
        eq(ns.Sync.shareLocation(), false, "click: off")
        eq(c.checked, false, "unticked")
        wow.click(c)
        eq(ns.Sync.shareLocation(), true, "click: on again")
    end)

    test("GF-FIX-A D-019: /gftk location on|off", function()
        local ns = shareLogin()
        SlashCmdList.GREENFANGTOOLKIT("location off")
        eq(ns.Sync.shareLocation(), false, "off")
        eq(ns.Share.get(A_SELF, "Z"), nil, "withdrawn")
        SlashCmdList.GREENFANGTOOLKIT("  LOCATION on")
        eq(ns.Sync.shareLocation(), true, "on")
        SlashCmdList.GREENFANGTOOLKIT("location")
        eq(ns.Sync.shareLocation(), true, "no argument: only the state")
        SlashCmdList.GREENFANGTOOLKIT("locationx off")
        eq(ns.Sync.shareLocation(), true, "another word is not this command")
    end)

    test("GF-FIX-A D-019: an old save with the switch off keeps it after a reload", function()
        wow.reset()
        local ns = wow.login(ADDON_DIR, { GreenFangToolkitDB = { schema = "gf.toolkit", schemaVersion = 2,
            settings = { shareLocation = false }, sync = { enabled = true, noticeShown = true, noticeVersion = 3, outbox = {} } } })
        eq(ns.Sync.shareLocation(), false, "still off")
        ns.Share.rand = function(a) return a end
        wow.advance(25)
        eq(ns.Share.get(A_SELF, "Z"), nil, "no Z shared at login")
    end)
end
