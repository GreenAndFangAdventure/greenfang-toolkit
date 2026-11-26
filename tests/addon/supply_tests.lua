-- GF-009 (v2.0 §7, 附錄 A §11): 綠皮調貨所 — automatic collection (rules,
-- the own snapshot, the COLLECTION group), manual listings and the page.
-- Offline only: the quest, bag and item functions are a small fake game
-- below; nothing here was checked in the Forever client. Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_SELF, A_B, A_C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local PEER_B, PEER_C = "測試乙-測試伺服器", "測試丙-測試伺服器"
    local function page(n) return 2724 + n end

    -- A fake game: quests[id] = "done" / "active" / "idle" / "unknown";
    -- bag = { { itemID, count, bound, locked } } (bag 0); items[id] = { name, bindType, classID }.
    local G
    local function installGame(opts)
        opts = opts or {}
        G = { quests = opts.quests or {}, bag = opts.bag or {}, items = opts.items or {}, bagError = false }
        for n = 1, 27 do
            if not G.items[page(n)] then G.items[page(n)] = { name = "荊棘谷的青山第" .. n .. "頁", classID = 15, bindType = 0 } end
        end
        if not opts.noQuestAPI then
            C_QuestLog = {
                IsQuestFlaggedCompleted = function(id)
                    local s = G.quests[id]
                    if s == "unknown" then return nil end
                    return s == "done"
                end,
                IsOnQuest = function(id) return G.quests[id] == "active" end,
            }
        else
            C_QuestLog = nil
        end
        if not opts.noBagAPI then
            C_Container = {
                GetContainerNumSlots = function(bag) if G.bagError then error("boom") end return bag == 0 and 20 or 0 end,
                GetContainerItemInfo = function(bag, slot)
                    local it = bag == 0 and G.bag[slot]
                    if not it then return nil end
                    return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = it[4] == true, iconFileID = 134939 }
                end,
            }
        else
            C_Container = nil
        end
        GetItemInfo = function(id)
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939,
                0, it.classID or 15, 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and (G.items[id].icon or 134939) or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function() end,
        }
        state_whispers = {}
        ChatFrame_SendTellWithMessage = function(name, text) state_whispers[#state_whispers + 1] = { name = name, text = text } end
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil
    end

    -- Logged in, past the share login and the supply start; deterministic delays.
    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        if opts.auto ~= false then ns.Supply.setAuto(true) end
        wow.advance(40)
        wow.state.sent = {}
        return ns
    end
    local function rule(ns) return ns.SupplyRules.byID("green_hills_pages") end
    local function own(ns) return ns.Share.get(A_SELF, "C1") end
    local function ownSnap(ns) local r = own(ns); return r and ns.Share.decodeValue("C1", r.v) end
    local function sent(kind, group)
        local out = {}
        for _, m in ipairs(wow.state.sent) do
            if m.prefix == "GFTKS" and m.msg:find("^S1~" .. kind .. "~") and (not group or m.msg:find("~" .. group .. "~", 1, true)) then
                out[#out + 1] = m
            end
        end
        return out
    end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function cval(ns, missing, surplus)
        return ns.Supply.encode(rule(ns), { missing = missing or {}, surplus = surplus or {} })
    end
    local function T0() return math.floor(wow.state.now) end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    ---------------------------------------------------------------------------
    -- Rules (GF-009-02)
    ---------------------------------------------------------------------------

    test("GF-009-02 rules: 15 pages from data, ItemID 2724 + page, experimental, chapters defined", done(function()
        local ns = login({ auto = false })
        local r = rule(ns)
        eq(r.state, "experimental", "not checked in game yet")
        eq(#r.order, 15, "15 pages")
        local want = { 1, 4, 6, 8, 10, 11, 14, 16, 18, 20, 21, 24, 25, 26, 27 }
        for i, p in ipairs(want) do eq(r.order[i], 2724 + p, "page " .. p) end
        eq(#r.chapters, 4, "four chapters"); eq(r.chapters[1].questID, 339, "chapter I quest"); eq(r.parentQuestID, 338, "parent")
        ok(r.usable, "usable")
        eq(ns.Supply.autoOn(), false, "experimental only after the player's 試用")
        eq(#ns.Supply.activeRules(), 0, "nothing active by default")
    end))

    test("GF-009-02 two rules with the same ItemID: the second one is turned off, diagnostics say so", done(function()
        local ns = login({ auto = false })
        local list = {
            { collectionID = "a", num = 7, rulesVersion = 1, state = "enabled", title = "甲", chapters = { { questID = 1, pages = { 1, 2 } } },
              itemIDFor = function(p) return 100 + p end },
            { collectionID = "b", num = 8, rulesVersion = 1, state = "enabled", title = "乙", chapters = { { questID = 2, pages = { 2, 3 } } },
              itemIDFor = function(p) return 100 + p end },
        }
        local problems = ns.SupplyRules.validate(list)
        ok(list[1].usable and not list[2].usable, "second one off")
        ok(#problems == 1 and problems[1]:find("相同物品", 1, true), "diagnostics: " .. tostring(problems[1]))
        ns.SupplyRules.validate() -- back to the real library
    end))

    ---------------------------------------------------------------------------
    -- Calculation (附錄 A §11.1)
    ---------------------------------------------------------------------------

    local function calc(ns, quests, bag)
        local bags = {}
        for _, b in ipairs(bag) do
            local c = bags[b[1]] or { count = 0, eligible = 0 }
            c.count = c.count + b[2]
            if not b[3] then c.eligible = c.eligible + b[2] end
            bags[b[1]] = c
        end
        return ns.Supply.compute(rule(ns), function(id)
            local s = quests[id]
            if s == "unknown" then return nil end
            return s or "idle"
        end, bags)
    end

    test("GF-009 §11.1 chapter in progress, 0/1/3 of a page: missing 1/0/0, surplus 0/0/2", done(function()
        local ns = login({ auto = false })
        local q = { [339] = "active" }
        for i, n in ipairs({ 0, 1, 3 }) do
            local s = calc(ns, q, n > 0 and { { page(1), n } } or {})
            eq(s.missing[page(1)] or 0, ({ 1, 0, 0 })[i], "missing with " .. n)
            eq(s.surplus[page(1)] or 0, ({ 0, 0, 2 })[i], "surplus with " .. n)
        end
    end))

    test("GF-009 §11.1 no collection quest, 1/2 of a page: no need; the first is kept, the second may be offered", done(function()
        local ns = login({ auto = false })
        local s1 = calc(ns, {}, { { page(4), 1 } })
        ok(next(s1.missing) == nil, "no need published")
        eq(s1.surplus[page(4)], nil, "the first one is kept")
        local s2 = calc(ns, {}, { { page(4), 2 } })
        ok(next(s2.missing) == nil, "still no need")
        eq(s2.surplus[page(4)], 1, "the second one may be offered")
    end))

    test("GF-009 §11.1 chapter I handed in (pages gone): its four pages are not missing", done(function()
        local ns = login({ auto = false })
        local s = calc(ns, { [339] = "done" }, {})
        for _, p in ipairs({ 1, 4, 6, 8 }) do eq(s.missing[page(p)], nil, "page " .. p) end
        ok(next(s.missing) == nil and next(s.surplus) == nil, "nothing at all")
    end))

    test("GF-009 §11.1 chapter I done, chapter II in progress: only chapter II pages, once each", done(function()
        local ns = login({ auto = false })
        local s = calc(ns, { [339] = "done", [340] = "active" }, { { page(1), 1 } })
        local n = 0
        for id, q in pairs(s.missing) do n = n + 1; eq(q, 1, "one each"); ok(rule(ns).items[id].chapter == 2, "chapter II only") end
        eq(n, 4, "four pages of chapter II")
        eq(s.surplus[page(1)], 1, "a leftover chapter I page may be offered (that chapter needs none)")
    end))

    test("GF-009 §11.1 the whole quest done: no need; leftover tradeable pages may be offered", done(function()
        local ns = login({ auto = false })
        local s = calc(ns, { [338] = "done", [342] = "active" }, { { page(25), 1 }, { page(26), 2 } })
        ok(next(s.missing) == nil, "no need")
        eq(s.surplus[page(25)], 1, "leftover"); eq(s.surplus[page(26)], 2, "both leftovers")
    end))

    test("GF-009 §11.1 unknown quest state, bound pages: no made-up need or supply", done(function()
        local ns = login({ auto = false })
        local s = calc(ns, { [339] = "unknown", [340] = "active" }, { { page(1), 3 }, { page(10), 2, true } })
        eq(s.missing[page(1)], nil, "unknown chapter: no need"); eq(s.surplus[page(1)], nil, "unknown chapter: no supply")
        ok(s.unknown[page(1)], "marked unknown")
        eq(s.missing[page(10)], nil, "a bound page still counts for the own need")
        eq(s.surplus[page(10)], nil, "bound pages are never offered")
    end))

    test("GF-009 §11.1 no quest API / bag API errors / nil: nothing published, safely off", done(function()
        local ns = login({ noQuestAPI = true })
        eq(ns.Supply.scanNow(), "no-quest-api", "quest API missing")
        eq(own(ns), nil, "no snapshot")
        ok(ns.Supply.diagText():find("任務讀取 失敗", 1, true), "diagnostics: " .. ns.Supply.diagText())
        removeGame()
        ns = login({ quests = { [339] = "active" } })
        local before = own(ns).v
        G.bag = { { page(1), 1 } }
        G.bagError = true
        eq(ns.Supply.scanNow(), "bag-error", "bag error")
        eq(own(ns).v, before, "the last good snapshot stays; nothing wrong published")
        G.bagError = false
        eq(ns.Supply.scanNow(), "ok", "fine again")
        eq(ownSnap(ns).missing[page(1)], nil, "now updated")
        removeGame()
        ns = login({ noBagAPI = true, quests = { [339] = "active" } })
        eq(ns.Supply.scanNow(), "no-bag-api", "no bag API")
        eq(own(ns), nil, "nothing")
    end))

    test("GF-009 §11.1 quest taken, abandoned, page picked up twice, bag sorted: snapshot follows; a pure move sends nothing", done(function()
        local ns = login()
        eq(own(ns), nil, "nothing to say before the quest")
        G.quests[339] = "active"
        wow.fire("QUEST_ACCEPTED"); wow.advance(4)
        eq(ownSnap(ns).missing[page(1)], 1, "missing after taking the quest")
        wow.advance(35)
        local first = #sent("V", "C1")
        ok(first >= 1, "sent after the change delay")
        G.bag = { { page(1), 1 }, { page(1), 1 } }
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(4)
        eq(ownSnap(ns).missing[page(1)], nil, "no longer missing")
        eq(ownSnap(ns).surplus[page(1)], 1, "the duplicate may be offered")
        wow.advance(35)
        wow.state.sent = {}
        G.bag = { nil, nil, { page(1), 1 }, { page(1), 1 } } -- moved slots, same counts
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(40)
        eq(#sent("V", "C1"), 0, "a bag move sends nothing")
        G.quests[339] = "idle" -- abandoned
        wow.fire("QUEST_REMOVED"); wow.advance(4)
        local s = ownSnap(ns)
        ok(next(s.missing) == nil, "abandoned: no need")
        eq(s.surplus[page(1)], 1, "not on the quest: one kept, one may be offered")
        G.bag = {} -- handed over / mailed
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(4)
        ok(ownSnap(ns).empty, "empty snapshot")
        wow.advance(35)
        ok(#sent("V", "C1") >= 1, "the empty snapshot is sent so the others clear it")
    end))

    test("GF-009-06 events debounce: many bag events, one scan 3 s after the last (at most 10 s)", done(function()
        local ns = login({ quests = { [339] = "active" } })
        local before = ns.Supply.stats.scans
        for _ = 1, 5 do wow.fire("BAG_UPDATE_DELAYED"); wow.advance(1) end
        eq(ns.Supply.stats.scans, before, "no scan while events keep coming")
        wow.advance(3)
        eq(ns.Supply.stats.scans, before + 1, "one scan")
        for _ = 1, 30 do wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.5) end
        ok(ns.Supply.stats.scans >= before + 2, "a steady stream still scans within the maximum wait")
        ok(ns.Supply.stats.scans <= before + 4, "but not on every event: " .. ns.Supply.stats.scans - before)
    end))

    ---------------------------------------------------------------------------
    -- COLLECTION over GFTKS (附錄 A §11.2)
    ---------------------------------------------------------------------------

    test("GF-009 §11.2 B's offer reaches us and matches; a relay keeps the author and time", done(function()
        local ns = login({ quests = { [339] = "active" } })
        wow.fire("QUEST_ACCEPTED"); wow.advance(4)
        local t = T0() - 600
        local v = cval(ns, nil, { [page(1)] = 2 })
        from(ns, PEER_C, vMsg(ns, A_B, "C1", t, v)) -- C relays B's snapshot
        local rec = ns.Share.get(A_B, "C1")
        ok(rec and rec.t == t and not rec.fromAuthor, "B is the author, B's time")
        local items = ns.Supply.view("need")
        eq(#items, 4, "my four missing pages")
        local it
        for _, x in ipairs(items) do if x.itemID == page(1) then it = x end end
        eq(#it.others, 1, "B may have page 1"); eq(it.others[1].a, A_B, "B"); eq(it.others[1].qty, 2, "2")
        eq(items[1].itemID, page(1), "the item with a match first")
        wow.state.sent = {}
        ns.Share.sendRecord(A_B, "C1", true)
        wow.advance(2)
        local out = sent("V", "C1")
        ok(#out == 1 and out[1].msg:find("S1~V~" .. A_B .. "~C1~" .. ns.Share.b36(t) .. "~", 1, true) == 1, "relayed as B's, B's time")
    end))

    test("GF-009 §11.2 the same packet three times changes nothing after the first", done(function()
        local ns = login()
        local msg = vMsg(ns, A_B, "C1", T0() - 60, cval(ns, nil, { [page(4)] = 1 }))
        from(ns, PEER_B, msg)
        local v = ns.Share.version
        from(ns, PEER_B, msg); from(ns, PEER_B, msg)
        eq(ns.Share.version, v, "no change, no redraw")
        wow.advance(30)
        eq(#sent("V", "C1"), 0, "nothing relayed back")
    end))

    test("GF-009 §11.2 two versions in the same second: the newer wins (own time only moves forward)", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        local t1 = own(ns).t
        G.bag = { { page(1), 1 } }
        ns.Supply.scanNow()
        local t2 = own(ns).t
        ok(t2 > t1, "the second version has a larger time: " .. t1 .. " " .. t2)
        -- Received: a newer time replaces, an older one does not.
        local t = T0() - 100
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(4)] = 1 })))
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t + 1, cval(ns, nil, { [page(4)] = 3 })))
        eq(ns.Share.decoded(A_B, "C1").surplus[page(4)], 3, "newer wins")
        from(ns, PEER_C, vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(4)] = 1 })))
        eq(ns.Share.decoded(A_B, "C1").surplus[page(4)], 3, "older did not replace it")
    end))

    test("GF-009 §11.2 B gives everything away: the empty snapshot clears it; an old packet does not bring it back", done(function()
        local ns = login({ quests = { [339] = "active" } })
        wow.fire("QUEST_ACCEPTED"); wow.advance(4)
        local t = T0() - 300
        local old = vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(1)] = 2 }))
        from(ns, PEER_B, old)
        eq(#ns.Supply.view("need")[1].others, 1, "matched")
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t + 60, ns.Supply.emptyValue(rule(ns))))
        for _, it in ipairs(ns.Supply.view("need")) do eq(#it.others, 0, "cleared") end
        from(ns, PEER_C, old) -- relayed again later
        for _, it in ipairs(ns.Supply.view("need")) do eq(#it.others, 0, "not back") end
    end))

    test("GF-009 §11.2 a 10 hour old offer relayed now is still 10 hours old (surplus 12 h, missing 72 h)", done(function()
        local ns = login({ quests = { [339] = "active" } })
        wow.fire("QUEST_ACCEPTED"); wow.advance(4)
        local t = T0() - 10 * 3600
        from(ns, PEER_C, vMsg(ns, A_B, "C1", t, cval(ns, { [page(10)] = 1 }, { [page(1)] = 2 })))
        local it = ns.Supply.view("need")[1]
        eq(it.others[1].fresh, "earlier", "稍早, not 近期")
        eq(ns.Share.get(A_B, "C1").t, t, "time not refreshed by the relay")
        wow.advance(3 * 3600)
        ns.Supply.invalidate()
        for _, x in ipairs(ns.Supply.view("need")) do eq(#x.others, 0, "offer past 12 hours") end
        local g = ns.Supply.view("guild")
        eq(#g, 1, "B's need (72 hours) is still there"); eq(g[1].itemID, page(10), "page 10"); eq(#g[1].needs, 1, "one need")
    end))

    test("GF-009 §11.2 bad ItemID, quantity, rules version, group or GUID are refused; other data unharmed", done(function()
        local ns = login()
        local t = T0() - 60
        local good = vMsg(ns, A_B, "B", t, ns.Share.encodeValue("B", { level = 40, classToken = "WARRIOR" }))
        from(ns, PEER_B, good)
        local bad = {
            "1//" .. ns.Share.b36(99999) .. ".1",            -- not one of the pages
            "1//" .. ns.Share.b36(page(1)) .. ".0",          -- zero
            "1//" .. ns.Share.b36(page(1)) .. ".zz",         -- too many
            "1/" .. ns.Share.b36(page(1)) .. ".1/" .. ns.Share.b36(page(1)) .. ".1", -- missing and surplus at once
            "x//", "1/", "1//a.1.2",
        }
        for i, v in ipairs(bad) do
            from(ns, PEER_B, vMsg(ns, A_B, "C1", t + i, v))
            eq(ns.Share.get(A_B, "C1"), nil, "refused: " .. v)
        end
        ok(ns.Supply.stats.rejected >= #bad, "counted for diagnostics")
        from(ns, PEER_B, vMsg(ns, A_B, "C9", t, "1//"))
        eq(ns.Share.get(A_B, "C9"), nil, "unknown collection ignored (as an old client ignores C1)")
        from(ns, PEER_B, vMsg(ns, "nobody", "C1", t, "1//"))
        eq(ns.Share.get("nobody", "C1"), nil, "author not on the roster")
        -- A newer rules version: kept (replaces the old one) but never matched.
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t + 20, "2//" .. ns.Share.b36(page(1)) .. ".1"))
        ok(ns.Share.decoded(A_B, "C1").unsupported, "unsupported version")
        eq(#ns.Supply.view("guild"), 0, "not shown")
        eq(ns.Share.decoded(A_B, "B").level, 40, "the level record is untouched")
    end))

    test("GF-009 §11.2 combat: no scan, nothing sent; after combat one merged update", done(function()
        local ns = login({ quests = { [339] = "active" } })
        wow.advance(60)
        wow.state.sent = {}
        local scans = ns.Supply.stats.scans
        wow.enterCombat()
        G.bag = { { page(1), 3 } }
        for _ = 1, 10 do wow.fire("BAG_UPDATE_DELAYED"); wow.advance(2) end
        wow.advance(60)
        eq(ns.Supply.stats.scans, scans, "no scan in combat")
        eq(#wow.state.sent, 0, "nothing sent in combat")
        ok(ns.Supply.dirty, "only marked dirty")
        wow.leaveCombat()
        wow.advance(4)
        eq(ns.Supply.stats.scans, scans + 1, "one scan after combat")
        wow.advance(35)
        eq(#sent("V", "C1"), 1, "one merged update")
    end))

    test("GF-009 §11.2 turning automatic collection off sends an empty snapshot once", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow(); wow.advance(35)
        ok(not ownSnap(ns).empty, "published")
        ns.Supply.setAuto(false)
        ok(ownSnap(ns).empty, "cleared")
        wow.advance(35)
        local out = sent("V", "C1")
        ok(#out >= 1 and out[#out].msg:find("~1//$"), "the empty snapshot went out")
        wow.state.sent = {}
        ns.Supply.scanNow(); wow.advance(35)
        eq(#sent("V", "C1"), 0, "only once")
    end))

    test("GF-009 §11.2 100 / 300 / 1000 members: the guild view builds from the cache in bounded time", done(function()
        for _, n in ipairs({ 100, 300, 1000 }) do
            local roster = wow.defaultRoster()
            for i = 1, n do
                roster[#roster + 1] = { name = "合成" .. i .. "-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
                    zone = "奧格瑪", online = i % 3 == 0, guid = string.format("Player-0000-%08X", 4096 + i) }
            end
            local ns = login({ roster = roster })
            local S = ns.Share
            local t = T0() - 120
            for i = 1, n do
                local a = string.format("0000-%08X", 4096 + i)
                local p = ({ 1, 4, 6, 8 })[1 + (i % 4)]
                local v = i % 2 == 0 and cval(ns, nil, { [page(p)] = 1 }) or cval(ns, { [page(10)] = 1 }, nil)
                S.offer(a, "C1", t, S.hash(v), v, true, a)
            end
            local c0 = os.clock()
            local g = ns.Supply.view("guild")
            local ms = (os.clock() - c0) * 1000
            ok(#g >= 2, "items listed")
            local people = 0
            for _, it in ipairs(g) do people = people + #it.others end
            eq(people, n, n .. " members in the view")
            ok(ms < 2000, n .. " members in " .. ms .. " ms")
            T.realPrint(string.format("     PERF GF-009: %d snapshots, guild view %.0f ms", n, ms))
            removeGame()
        end
    end))

    test("GF-009 COLLECTION and listings never reach GF Sync's outbox", done(function()
        local ns = login()
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "B", t, ns.Share.encodeValue("B", { level = 40, classToken = "WARRIOR" })))
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(1)] = 2 })))
        ok(ns.Share.isLocalGroup("C1") and ns.Share.isLocalGroup("L"), "registered as local")
        local saved = wow.logout()
        local text = wow.serializeSV("GreenFangToolkitDB", saved.GreenFangToolkitDB.sync or {})
        ok(not text:find('"C1"', 1, true) and not text:find("荊棘谷", 1, true), "no supply data in the outbox")
    end))

    ---------------------------------------------------------------------------
    -- Manual listings (GF-009-08, v2.0 §7.2)
    ---------------------------------------------------------------------------

    local SCROLL, BOP = 9001, 9002
    local function itemsWith()
        return { [SCROLL] = { name = "配方：測試藥水", classID = 9, bindType = 0 },
            [BOP] = { name = "測試護符", classID = 4, bindType = 1 } }
    end
    local function lform(over)
        local f = { direction = "need", itemID = SCROLL, quantity = 1, days = 14, note = "", category = "recipe" }
        for k, v in pairs(over or {}) do f[k] = v end
        return f
    end

    test("GF-009-08 a listing: fields checked, 14 days by default, note at most 40 characters", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local Lst = ns.SupplyListings
        local l = Lst.create(lform({ days = nil }))
        ok(l, "created")
        eq(l.expiresAt - l.createdAt, 14 * 86400, "14 days by default")
        local _, why = Lst.create(lform({ direction = "offer", quantity = 0 })); ok(why:find("數量"), why)
        _, why = Lst.create(lform({ direction = "offer", days = 60 })); ok(why:find("有效期"), why)
        _, why = Lst.create(lform({ direction = "offer", note = string.rep("字", 41) })); ok(why:find("40"), why)
        _, why = Lst.create(lform({ direction = "offer", itemID = BOP })); ok(why:find("綁定"), why)
        _, why = Lst.create(lform({ direction = "offer", itemID = 123456 })); ok(why:find("載入中") or why:find("辨識"), why)
        _, why = Lst.create(lform({ direction = "offer", itemID = false })); ok(why:find("物品"), why)
        local l2 = Lst.create(lform({ direction = "offer", note = "換\1一瓶" .. string.rep("字", 30) }))
        ok(l2 and not l2.note:find("\1", 1, true), "control bytes removed")
        eq(Lst.itemFromText("|cff|Hitem:9001::::|h[x]|h|r"), SCROLL, "ItemID from a link")
        eq(Lst.itemFromText("9001"), nil, "no guessed ItemID from plain text")
    end))

    test("GF-009-08 the same item and direction twice: refused with the existing one to edit (no silent sum)", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local Lst = ns.SupplyListings
        local l = Lst.create(lform({ quantity = 2 }))
        local again, why, dup = Lst.create(lform({ quantity = 3 }))
        ok(not again and why:find("修改", 1, true), why)
        eq(dup.id, l.id, "the existing listing")
        eq(Lst.ownActive()[1].quantity, 2, "not added up")
        ok(Lst.create(lform({ direction = "offer" })), "the other direction is a different listing")
    end))

    test("GF-009-08 two members: B lists, we see it; B edits, renews and cancels; old packets do not bring it back; it expires", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local Lst = ns.SupplyListings
        local t = T0() - 60
        local item = { id = 1, direction = "offer", category = "recipe", itemID = SCROLL, quantity = 1, createdAt = t, expiresAt = t + 3 * 86400, rev = 1, note = "換材料" }
        local v1 = Lst.encode({ item })
        local m1 = vMsg(ns, A_B, "L", t, v1)
        from(ns, PEER_B, m1)
        local g = ns.Supply.view("guild")
        eq(#g, 1, "listed"); eq(g[1].offers[1].manual.note, "換材料", "note kept")
        item.quantity, item.rev = 2, 2
        from(ns, PEER_B, vMsg(ns, A_B, "L", t + 30, Lst.encode({ item })))
        eq(ns.Supply.view("guild")[1].offers[1].qty, 2, "edit seen")
        from(ns, PEER_B, vMsg(ns, A_B, "L", t + 50, "")) -- cancelled
        eq(#ns.Supply.view("guild"), 0, "cancel seen")
        from(ns, PEER_C, m1)
        eq(#ns.Supply.view("guild"), 0, "an old relayed packet does not bring it back")
        -- A new one that expires on its own.
        from(ns, PEER_B, vMsg(ns, A_B, "L", t + 55, v1))
        eq(#ns.Supply.view("guild"), 1, "newer listing")
        wow.advance(3 * 86400)
        ns.Supply.invalidate()
        eq(#ns.Supply.view("guild"), 0, "past its time: gone even without a new packet")
    end))

    test("GF-009-08 only the author: our edits touch our own list; another's listing id is not ours to change", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local Lst = ns.SupplyListings
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, Lst.encode({ { id = 5, direction = "offer", category = "recipe", itemID = SCROLL, quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        local okEdit, why = Lst.update(5, { quantity = 9 })
        ok(not okEdit and why:find("找不到"), "B's listing cannot be edited here: " .. tostring(why))
        ok(not Lst.finish(5), "nor ended")
        local l = Lst.create(lform())
        wow.advance(40)
        wow.state.sent = {}
        ok(Lst.update(l.id, { quantity = 4, note = "急", category = "recipe" }), "own edit")
        eq(Lst.ownActive()[1].rev, 2, "revision")
        wow.advance(40)
        local out = sent("V", "L")
        ok(#out == 1 and out[1].msg:find("S1~V~" .. A_SELF .. "~L~", 1, true) == 1, "our record went out once")
        ok(Lst.renew(l.id, 30), "renew")
        eq(Lst.ownActive()[1].expiresAt - math.floor(ns.Share.serverNow()), 30 * 86400, "a new period from now")
        ok(Lst.finish(l.id, "closed"), "ended")
        eq(#Lst.ownActive(), 0, "no longer active")
        eq(Lst.own()[1].status, "closed", "kept in 我的刊登 as 已結束")
        eq(ns.Share.get(A_SELF, "L").v, "", "the record is empty now (the others drop it)")
    end))

    test("GF-009-08 own listing expires: marked 已過期, the record drops it", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local Lst = ns.SupplyListings
        Lst.create(lform({ days = 3 }))
        wow.advance(3 * 86400 + 400)
        eq(Lst.own()[1].status, "expired", "已過期")
        eq(ns.Share.get(A_SELF, "L").v, "", "not shared any more")
    end))

    test("GF-009-08 automatic gap and manual need of the same page: one entry, both sources, not added up", done(function()
        local ns = login({ quests = { [339] = "active" }, items = itemsWith() })
        ns.Supply.scanNow()
        ok(ns.SupplyListings.create(lform({ itemID = page(1), quantity = 1, category = "quest" })), "manual need of page 1")
        local found
        for _, it in ipairs(ns.Supply.view("need")) do if it.itemID == page(1) then found = it end end
        ok(found, "listed")
        eq(found.qty, 1, "one gap, not two")
        ok(found.mine.auto and found.mine.manual, "both sources kept")
        eq(ns.SupplyUI.sourceText(found.mine), "自動＋手動", "both shown")
        -- B: automatic surplus 1 and a manual offer 2 of the same page: max, not 3.
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(1)] = 1 })))
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, ns.SupplyListings.encode({ { id = 1, direction = "offer", category = "quest", itemID = page(1), quantity = 2, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        for _, it in ipairs(ns.Supply.view("need")) do
            if it.itemID == page(1) then eq(#it.others, 1, "B once"); eq(it.others[1].qty, 2, "max of the two") end
        end
    end))

    test("GF-009-08 manual listings and the automatic snapshot can each be turned off", done(function()
        local ns = login({ quests = { [339] = "active" }, items = itemsWith() })
        ns.Supply.scanNow()
        ns.SupplyListings.create(lform())
        ns.Supply.setManual(false)
        eq(ns.Share.get(A_SELF, "L").v, "", "listing record emptied")
        ok(not ownSnap(ns).empty, "automatic snapshot untouched")
        local _, why = ns.SupplyListings.create(lform({ direction = "offer" }))
        ok(why:find("關閉"), why)
        ns.Supply.setManual(true)
        ok(ns.Share.get(A_SELF, "L").v ~= "", "back on: shared again")
        ns.Supply.setAuto(false)
        ok(ownSnap(ns).empty, "automatic off")
        ok(ns.Share.get(A_SELF, "L").v ~= "", "listing untouched")
    end))

    test("GF-009-08 bad listing records are refused whole; old clients ignore group L", done(function()
        local ns = login({ auto = false, items = itemsWith() })
        local t = T0() - 60
        local bads = {
            "1.o.r." .. ns.Share.b36(SCROLL) .. ".1." .. ns.Share.b36(t) .. "." .. ns.Share.b36(t + 40 * 86400) .. ".1.", -- 40 days
            "1.x.r." .. ns.Share.b36(SCROLL) .. ".1." .. ns.Share.b36(t) .. "." .. ns.Share.b36(t + 86400) .. ".1.",
            "1.o.r." .. ns.Share.b36(SCROLL) .. ".0." .. ns.Share.b36(t) .. "." .. ns.Share.b36(t + 86400) .. ".1.",
            "1.o.r." .. ns.Share.b36(SCROLL) .. ".1." .. ns.Share.b36(t) .. "." .. ns.Share.b36(t + 86400) .. ".1." .. string.rep("a", 41),
        }
        for i, v in ipairs(bads) do
            from(ns, PEER_B, vMsg(ns, A_B, "L", t + i, v))
            eq(ns.Share.get(A_B, "L"), nil, "refused " .. i)
        end
        -- What an old client does with a group it does not know: offer says invalid.
        eq(ns.Share.offer(A_B, "Q7", t, ns.Share.hash("x"), "x", true, A_B), "invalid", "unknown group")
    end))

    ---------------------------------------------------------------------------
    -- The page (附錄 A §7, §11.3)
    ---------------------------------------------------------------------------

    local function texts(f, acc)
        acc = acc or {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and o._text ~= "" then acc[#acc + 1] = o._text end
        end
        return acc
    end

    test("GF-009 page: item icon + name + quantity on every row, the game's icons, no ItemID, no bad glyphs", done(function()
        local ns = login({ quests = { [339] = "active" }, bag = { { page(1), 3 } } })
        G.items[page(4)].icon = nil
        G.items[page(6)] = nil -- not in the cache yet
        ns.Supply.scanNow()
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        eq(UI.state.tab, "need", "我缺的 first")
        local rows = 0
        for _, it in ipairs(UI.state.items) do
            rows = rows + 1
            ok(it.qty:find("^缺 %d+$"), "quantity: " .. it.qty)
        end
        eq(rows, 3, "pages 4, 6, 8 missing")
        local sawLoading = false
        for _, txt in ipairs(texts()) do
            ok(not txt:find("—") and not txt:find("…") and not txt:find("●") and not txt:find("→"), "glyph in " .. txt)
            ok(not txt:find(tostring(page(4)), 1, true), "no ItemID shown: " .. txt)
            if txt == "物品資料載入中" or txt:find("第6頁", 1, true) then sawLoading = true end
        end
        ok(sawLoading, "an item not in the cache shows the rule's label or 載入中")
        UI.setTab("offer")
        eq(#UI.state.items, 1, "page 1: may have 2 extra")
        eq(UI.state.items[1].qty, "可能多 2", "可能多 2")
        ok(UI.state.items[1].match == "暫無需要者", "no match yet")
        UI.setTab("guild")
        ok(#UI.state.items == 0, "empty guild view")
        local seenEmpty = false
        for _, txt in ipairs(texts()) do if txt == "目前沒有可配對的公會物資" then seenEmpty = true end end
        ok(seenEmpty, "clear empty state")
    end))

    test("GF-009 page: 聯絡 only fills the whisper box with neutral words; the full name; not for ourselves", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Supply.scanNow()
        from(ns, PEER_B, vMsg(ns, A_B, "C1", T0() - 60, cval(ns, nil, { [page(1)] = 2 })))
        ns.Framework.open("supply")
        local e = ns.Supply.view("need")[1].others[1]
        ok(ns.Supply.canContact(e), "can contact")
        ok(ns.Supply.contact(e), "opened")
        eq(#state_whispers, 1, "one whisper box")
        eq(state_whispers[1].name, PEER_B, "full name from the roster")
        local text = state_whispers[1].text
        ok(text:find("可能有多的", 1, true) and text:find("交換方式", 1, true), text)
        ok(not text:find("免費", 1, true) and not text:find("賣", 1, true), "neutral: " .. text)
        eq(#sent("V") + #sent("I"), #sent("V") + #sent("I"), "")
        for _, m in ipairs(wow.state.sent) do ok(m.chatType ~= "WHISPER" or m.prefix == "GFTKS", "no chat whisper sent") end
        local mine = { own = true, member = { name = "測試甲-測試伺服器" }, itemID = page(1), direction = "need" }
        ok(not ns.Supply.canContact(mine) and not ns.Supply.contact(mine), "not ourselves")
    end))

    test("GF-009 page: the form lists by link, ESC and X close it, a click outside does not; the picker (GF-009-14: a window) too", done(function()
        local ns = login({ auto = false, items = itemsWith(), bag = { { SCROLL, 1 }, { BOP, 1, true } } })
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        ok(UI.openForm(), "form open")
        local f = UI.form()
        ok(f:IsShown(), "shown")
        UI.formFromText("|cff|Hitem:" .. SCROLL .. "::::|h[配方]|h|r")
        eq(UI.formState.itemID, SCROLL, "item from the link")
        eq(UI.formState.category, "recipe", "圖紙 suggested from the item class")
        local p = UI.openPicker()
        ok(p:IsShown(), "picker")
        local shownRows = 0
        for _, b in ipairs(p.rows) do if b:IsShown() then shownRows = shownRows + 1 end end
        eq(shownRows, 1, "only the unbound item")
        -- GF-009-14 (was: a click outside closed it): the picker is a window in
        -- DIALOG (the IME candidates above it), so no click-outside layer.
        local blocker = ns.clickBlocker()
        ok(not (blocker and blocker:IsShown()), "no click-outside layer over the picker")
        wow.pressEscape()
        ok(not p:IsShown(), "ESC closes the picker")
        ok(f:IsShown(), "the form stays (it holds typed text)")
        f.qty:SetText("2")
        local l = UI.submitForm()
        ok(l and l.quantity == 2 and l.category == "recipe", "listed")
        ok(not f:IsShown(), "closed after listing")
        eq(UI.state.tab, "mine", "我的刊登 shows it")
        eq(UI.state.items[1].qty, "徵求 2", "徵求 2")
        UI.openForm(l)
        ok(f:IsShown(), "edit form")
        wow.pressEscape()
        ok(not f:IsShown(), "ESC closes it")
        UI.openForm()
        f.CloseButton._scripts.OnClick(f.CloseButton)
        ok(not f:IsShown(), "X closes it")
    end))

    test("GF-009 page: refresh waits out combat; the page and diagnostics never print account or GUID", done(function()
        local ns = login({ quests = { [339] = "active" } })
        ns.Framework.open("supply")
        wow.enterCombat()
        ns.SupplyUI.refresh()
        ok(ns.SupplyUI.pending, "waits for the end of combat")
        wow.leaveCombat(); wow.advance(1)
        ok(not ns.SupplyUI.pending, "refreshed after combat")
        local d = ns.Supply.diagText()
        ok(not d:find("Player-", 1, true) and not d:find(A_SELF, 1, true), "no GUID in diagnostics: " .. d)
        ok(d:find("規則庫", 1, true) and d:find("實驗", 1, true), "rules library and experimental rule listed")
        ns.Diag.open()
        local found = false
        for _, txt in ipairs(texts()) do if txt:find("物資供需", 1, true) then found = true end end
        ok(found, "a section in 同步與診斷")
    end))

    test("GF-009 schema: an unknown supply schema clears only the supply table", done(function()
        local saved = { GreenFangToolkitDB = { supply = { v = 99, junk = true }, settings = { lastModule = "roster" } } }
        local ns = login({ saved = saved, auto = false })
        eq(ns.db.supply.v, 1, "supply reset")
        eq(ns.db.supply.junk, nil, "old data gone")
        eq(ns.settings().lastModule ~= nil, true, "other settings kept")
    end))

    -- GF-016 (GPT review, v2.0 §7.2 last paragraph): one character, one item,
    -- an automatic bag candidate and a manual offer: both source details kept,
    -- one provider, the quantity is the larger one (never the sum).
    test("GF-016 §7.2 same character, same item: auto candidate + manual offer = one provider, both sources, max not sum", done(function()
        local ns = login({ quests = { [339] = "active" }, items = itemsWith() })
        ns.Supply.scanNow()
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t, cval(ns, nil, { [page(1)] = 2 })))
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, ns.SupplyListings.encode({ { id = 1, direction = "offer", category = "quest",
            itemID = page(1), quantity = 3, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        local function need()
            for _, it in ipairs(ns.Supply.view("need")) do if it.itemID == page(1) then return it end end
        end
        local it = need()
        ok(it, "my gap of page 1")
        eq(#it.others, 1, "可能提供者: B once")
        local b = it.others[1]
        eq(b.a, A_B, "B"); eq(b.qty, 3, "the larger of 2 and 3, not 5")
        eq(b.auto, 2, "the automatic detail kept (2)")
        ok(b.manual and b.manual.quantity == 3, "the manual detail kept (3)")
        eq(#b.manuals, 1, "one manual listing")
        eq(ns.SupplyUI.sourceText(b), "自動＋手動", "both sources named")
        -- The same in the guild view: one offer of B for page 1.
        local g
        for _, x in ipairs(ns.Supply.view("guild")) do if x.itemID == page(1) then g = x end end
        eq(#g.offers, 1, "guild view: B once"); eq(g.offers[1].qty, 3, "guild view: 3")
        -- C offers it by hand only: two providers now, B still once.
        from(ns, PEER_C, vMsg(ns, A_C, "L", t, ns.SupplyListings.encode({ { id = 1, direction = "offer", category = "quest",
            itemID = page(1), quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        it = need()
        eq(#it.others, 2, "B and C")
        local byA = {}
        for _, e in ipairs(it.others) do byA[e.a] = (byA[e.a] or 0) + 1 end
        eq(byA[A_B], 1, "B counted once"); eq(byA[A_C], 1, "C once")
        -- B's automatic candidate goes away (gave it away): the manual one stays alone.
        from(ns, PEER_B, vMsg(ns, A_B, "C1", t + 30, cval(ns, nil, {})))
        it = need()
        for _, e in ipairs(it.others) do
            if e.a == A_B then eq(e.auto, nil, "no automatic part"); eq(e.qty, 3, "the manual 3") end
        end
        -- My own side: automatic gap 1 and a manual need of 1: one gap of 1 (not 2), both sources.
        ok(ns.SupplyListings.create(lform({ itemID = page(1), quantity = 1, category = "quest" })), "manual need")
        it = need()
        eq(it.qty, 1, "one gap"); ok(it.mine.auto and it.mine.manual, "both sources on mine")
    end))
end
