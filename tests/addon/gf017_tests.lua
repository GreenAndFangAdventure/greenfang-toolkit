-- GF-017: the game's guild bank, gold only (owner 2026-11-28): the balance
-- and the gold log, read only while I have the guild bank open, merged into
-- this computer's log (no line counted twice), shared with the guild (Share
-- group GB, local), and the 公會銀行 view on the 臨時黑箱 page.
-- Offline only (made-up names, GUIDs and amounts); nothing checked in game.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, X = "0000-0000000A", "0000-0000000B", "0000-000000FF"
    local PEER_B = "測試乙-測試伺服器"
    local H, D = 3600, 86400

    -- The fake guild bank. G.lines: { kind, name, amount, y, m, d, h } in the game's order.
    local G
    local NAMES = { "GetGuildBankMoney", "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction",
        "QueryGuildBankLog", "MAX_GUILDBANK_TABS" }
    local saved
    local function installBank(opts)
        opts = opts or {}
        saved = {}
        for _, n in ipairs(NAMES) do saved[n] = _G[n] end
        G = { money = opts.money or 1234567, lines = opts.lines or {}, calls = {}, queries = {} }
        local function count(n) G.calls[n] = (G.calls[n] or 0) + 1 end
        GetGuildBankMoney = function() count("money"); return G.money end
        GetNumGuildBankMoneyTransactions = function() count("num"); return G.num or #G.lines end
        GetGuildBankMoneyTransaction = function(i)
            count("line")
            local l = G.lines[i]
            if not l then return nil end
            return l[1], l[2], l[3], l[4], l[5], l[6], l[7]
        end
        QueryGuildBankLog = function(tab) G.queries[#G.queries + 1] = tab end
        MAX_GUILDBANK_TABS = 8
        if opts.noApi then
            GetGuildBankMoney, GetNumGuildBankMoneyTransactions, GetGuildBankMoneyTransaction, QueryGuildBankLog = nil, nil, nil, nil
        end
    end
    local function removeBank()
        if saved then for _, n in ipairs(NAMES) do _G[n] = saved[n] end end
        saved = nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeBank(); if not okRun then error(err, 0) end end end

    local function now(ns) return math.floor(ns.Share.serverNow()) end
    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = opts.roster, inGuild = opts.inGuild })
        if opts.guild then wow.state.player.guild = opts.guild end
        installBank(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        wow.advance(40)
        wow.state.sent = {}
        return ns
    end
    local function open() wow.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10); wow.advance(1.5) end
    local function close() wow.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10) end
    local function moneyEvent() wow.fire("GUILDBANK_UPDATE_MONEY"); wow.advance(0.5) end
    local function logEvent() wow.fire("GUILDBANKLOG_UPDATE"); wow.advance(0.5) end
    local function visit() open(); moneyEvent(); logEvent(); close() end
    local function offer(ns, a, v, t)
        return ns.Share.offer(a, "GB", t or now(ns), ns.Share.hash(v), v, true, a)
    end
    local function find(list, k, name, amount)
        local n = 0
        for _, e in ipairs(list) do if e.k == k and e.n == name and e.a == amount then n = n + 1 end end
        return n
    end

    ---------------------------------------------------------------------------
    -- 1. Times
    ---------------------------------------------------------------------------

    test("GF-017 relative time -> approximate server time with its precision", function()
        local ns = login()
        local GB = ns.GuildBank
        local t0 = 1763370000
        local t, p = GB.whenOf(t0, 0, 0, 3, 5)
        eq(t, t0 - (3 * 24 + 5) * H - H / 2, "3 days 5 hours ago, the middle of that hour")
        eq(p, H / 2, "half an hour either way")
        local t2, p2 = GB.whenOf(t0, 0, 2, 1, 0)
        eq(t2, t0 - (2 * 30 + 1) * D - H / 2, "a month counts 30 days")
        eq(p2, H / 2 + 4 * D, "2 days of slack per month")
        local t3 = GB.whenOf(t0, nil, nil, nil, nil)
        eq(t3, t0 - H / 2, "all zero / nil: within the last hour")
        eq(GB.whenOf(t0, 0, 0, -1, 0), nil, "negative refused")
        eq(GB.precisionText(H / 2), "準到小時", "hour precision")
        eq(GB.precisionText(4 * D), "大約", "coarse")
        eq(GB.agoText(t0 - 30 * 60, t0), "不到 1 小時前", "under an hour")
        eq(GB.agoText(t0 - 5 * H, t0), "約 5 小時前", "hours")
        eq(GB.agoText(t0 - 3 * D - H, t0), "約 3 天前", "days")
    end)

    ---------------------------------------------------------------------------
    -- 2. Merging
    ---------------------------------------------------------------------------

    local function line(k, n, a, t, p) return { k = k, n = n, a = a, t = t, p = p or H / 2 } end

    test("GF-017 merge: the same read twice adds nothing; a later read with shifted times matches", function()
        local ns = login()
        local GB = ns.GuildBank
        local t0 = 1763370000
        local log = {}
        local first = {}
        for i = 1, 5 do
            local t, p = GB.whenOf(t0, 0, 0, i, 2)
            first[#first + 1] = line("d", "甲" .. i, 10000 * i, t, p)
        end
        eq((GB.merge(log, first, t0)), 5, "five new")
        eq((GB.merge(log, first, t0)), 0, "again: nothing new")
        -- Seen again 7 hours later: the game now says 7 more hours ago; two new lines on top.
        local later = t0 + 7 * H
        local second = {}
        for i = 1, 5 do
            local t, p = GB.whenOf(later, 0, 0, i, 9)
            second[#second + 1] = line("d", "甲" .. i, 10000 * i, t, p)
        end
        local tn, pn = GB.whenOf(later, 0, 0, 0, 1)
        second[#second + 1] = line("w", "乙", 500, tn, pn)
        second[#second + 1] = line("r", "丙", 777, tn, pn)
        local added, matched = GB.merge(log, second, later)
        eq(added, 2, "only the two new lines")
        eq(matched, 5, "the old five matched")
        eq(#log, 7, "seven in all")
        eq(log[1].k == "w" or log[1].k == "r", true, "newest first")
    end)

    test("GF-017 merge: two equal lines in one hour count twice, once each (one to one)", function()
        local ns = login()
        local GB = ns.GuildBank
        local t0 = 1763370000
        local log = {}
        local t, p = GB.whenOf(t0, 0, 0, 0, 3)
        GB.merge(log, { line("d", "甲", 5000, t, p), line("d", "甲", 5000, t, p) }, t0)
        eq(#log, 2, "both kept")
        GB.merge(log, { line("d", "甲", 5000, t, p) }, t0)
        eq(#log, 2, "a read with one of them adds nothing")
        GB.merge(log, { line("d", "甲", 5000, t, p), line("d", "甲", 5000, t, p), line("d", "甲", 5000, t, p) }, t0)
        eq(#log, 3, "a third one in the same hour is new")
        -- Same name and amount far apart: different lines.
        local tf = GB.whenOf(t0, 0, 0, 10, 0)
        GB.merge(log, { line("d", "甲", 5000, tf, p) }, t0)
        eq(#log, 4, "ten days earlier is another line")
        -- Another kind or amount is never the same line.
        GB.merge(log, { line("w", "甲", 5000, t, p), line("d", "甲", 5001, t, p) }, t0)
        eq(#log, 6, "kind and amount count")
    end)

    test("GF-017 merge narrows the time window; keeps 200 lines or 90 days", function()
        local ns = login()
        local GB = ns.GuildBank
        local t0 = 1763370000
        local log = { line("d", "甲", 100, t0 - 10 * H, 4 * D) }
        GB.merge(log, { line("d", "甲", 100, t0 - 11 * H, H / 2) }, t0)
        eq(#log, 1, "matched")
        ok(log[1].p <= H / 2, "window narrowed to the exact read: " .. log[1].p)
        -- 300 lines, one per 16 hours (200 days): the newest 200 plus none older than 90 days beyond them.
        local many = {}
        for i = 1, 300 do many[#many + 1] = line("d", "乙", i, t0 - i * 16 * H) end
        local big = {}
        GB.merge(big, many, t0)
        eq(#big, 200, "200 lines kept (the 90 days hold only 135)")
        ok(big[1].t > big[200].t, "newest first")
        -- 400 lines within 60 days: all inside 90 days, all kept.
        local dense, many2 = {}, {}
        for i = 1, 400 do many2[#many2 + 1] = line("w", "丙", i, t0 - i * 3 * H) end
        GB.merge(dense, many2, t0)
        eq(#dense, 400, "everything of the last 90 days")
    end)

    ---------------------------------------------------------------------------
    -- 3. Reading the open bank (events, combat, missing API)
    ---------------------------------------------------------------------------

    local LINES = {
        { "deposit", "測試甲", 50000, 0, 0, 0, 2 },
        { "withdraw", "測試乙", 20000, 0, 0, 1, 0 },
        { "repair", "測試丙", 3456, 0, 0, 2, 5 },
        { "depositSummary", "", 1200, 0, 0, 3, 0 },
        { "buyTab", "測試乙", 0, 0, 0, 20, 0 },
    }

    test("GF-017 reads only while the guild bank is open; events only registered while open", done(function()
        local ns = login({ lines = LINES })
        local GB = ns.GuildBank
        local f = GB.events
        eq(f._events.GUILDBANK_UPDATE_MONEY, nil, "money event not registered while closed")
        eq(f._events.GUILDBANKLOG_UPDATE, nil, "log event not registered while closed")
        ok(f._events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW, "the open event is")
        wow.fire("GUILDBANK_UPDATE_MONEY"); wow.fire("GUILDBANKLOG_UPDATE"); wow.advance(2)
        eq(G.calls.money, nil, "closed: nothing read")
        wow.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8); wow.advance(2)
        eq(G.calls.money, nil, "the personal bank (8) is not the guild bank")
        open()
        ok(f._events.GUILDBANK_UPDATE_MONEY and f._events.GUILDBANKLOG_UPDATE, "registered while open")
        eq(#G.queries, 1, "the log asked for once")
        eq(G.queries[1], 9, "MAX_GUILDBANK_TABS + 1")
        logEvent()
        local g = GB.guildData()
        eq(#g.log, 5, "five lines")
        eq(find(g.log, "s", "", 1200), 1, "the summary line without a name")
        eq(find(g.log, "b", "測試乙", 0), 1, "a free tab (0 copper) kept")
        eq(g.money, 1234567, "the balance read on opening")
        moneyEvent()
        eq(#G.queries, 1, "still one request")
        close()
        eq(f._events.GUILDBANK_UPDATE_MONEY, nil, "unregistered on close")
        local reads = G.calls.money
        wow.fire("GUILDBANK_UPDATE_MONEY"); wow.advance(2)
        eq(G.calls.money, reads, "closed again: nothing read")
        -- Another visit 5 hours later: the same lines, 5 hours older.
        wow.advance(5 * H)
        for _, l in ipairs(LINES) do l[7] = l[7] + 5 end
        G.lines[#G.lines + 1] = { "deposit", "測試丁", 999, 0, 0, 0, 0 }
        visit()
        for _, l in ipairs(LINES) do l[7] = l[7] - 5 end
        table.remove(G.lines)
        eq(#g.log, 6, "only the new line added")
        eq(#G.queries, 2, "one request per visit")
        -- The old GUILDBANKFRAME_* events work too.
        wow.fire("GUILDBANKFRAME_OPENED"); wow.advance(1.5)
        eq(GB.open, true, "opened")
        wow.fire("GUILDBANKFRAME_CLOSED")
        eq(GB.open, false, "closed")
    end))

    test("GF-017 a 0 balance right after opening waits for the money event", done(function()
        local ns = login({ money = 0 })
        local GB = ns.GuildBank
        open()
        eq(GB.guildData().money, nil, "0 before the money event is not taken")
        eq(GB.status().state, "never", "still nobody saw it")
        moneyEvent()
        eq(GB.guildData().money, 0, "0 after the money event is real")
        close()
    end))

    test("GF-017 nothing is read in combat; it is read after combat while still open", done(function()
        local ns = login({ lines = LINES })
        local GB = ns.GuildBank
        wow.enterCombat()
        open()
        logEvent(); moneyEvent()
        eq(G.calls.money, nil, "no money read in combat")
        eq(G.calls.num, nil, "no log read in combat")
        eq(#G.queries, 0, "no request in combat")
        wow.leaveCombat(); wow.advance(1)
        ok((G.calls.money or 0) > 0, "read after combat")
        eq(#G.queries, 1, "asked after combat")
        logEvent()
        eq(#GB.guildData().log, 5, "log read")
        close()
        -- Combat while closed: nothing at all.
        local before = G.calls.money
        wow.enterCombat(); wow.leaveCombat(); wow.advance(1)
        eq(G.calls.money, before, "closed: the end of combat reads nothing")
        ok(not GB.events._events.PLAYER_REGEN_ENABLED, "the end-of-combat event only while open")
    end))

    test("GF-017 missing API, errors and unread values: no error, said plainly", done(function()
        local ns = login({ noApi = true })
        local GB = ns.GuildBank
        open(); moneyEvent(); logEvent(); close()
        eq(GB.status().state, "noapi", "no money function")
        ok(GB.TEXT.noapi:find("讀不到", 1, true), "said as 讀不到")
        ok(GB.diagText():find("讀不到存款函式", 1, true), "diag says so")
        -- The functions error / return nil.
        removeBank()
        local ns2 = login()
        GetGuildBankMoney = function() error("boom") end
        GetNumGuildBankMoneyTransactions = function() return nil end
        open(); moneyEvent(); logEvent(); close()
        eq(ns2.GuildBank.status().state, "unread", "money unread is not 0")
        eq(ns2.GuildBank.guildData().money, nil, "nothing stored")
        eq(ns2.GuildBank.guildData().logRead, "?", "log unread")
        -- The log is empty (no permission or nothing yet).
        removeBank()
        local ns3 = login({ lines = {} })
        visit()
        eq(ns3.GuildBank.guildData().logRead, "0", "the game gave none")
        eq(ns3.GuildBank.status().state, "ok", "the balance is still there")
    end))

    ---------------------------------------------------------------------------
    -- 4. Sharing
    ---------------------------------------------------------------------------

    test("GF-017 my read is shared as group GB (local); sizes measured", done(function()
        local ns = login({ lines = LINES })
        local GB = ns.GuildBank
        visit()
        local rec = ns.Share.get(A, "GB")
        ok(rec, "my record")
        ok(ns.Share.isLocalGroup("GB"), "local: GF Sync does not upload it")
        local d = ns.Share.decoded(A, "GB")
        eq(d.money, 1234567, "balance")
        eq(d.logRead, "1", "log read")
        eq(#d.log, 5, "five lines")
        wow.advance(40)
        local sent = 0
        for _, m in ipairs(wow.state.sent) do if m.msg:find("~GB~", 1, true) then sent = sent + 1 end end
        ok(sent >= 1, "went out: " .. sent)
        -- Worst case: MAX_WIRE entries with 48-byte names and huge numbers.
        local big = {}
        local name = string.rep("測", 16) -- 48 bytes
        for i = 1, GB.MAX_WIRE + 5 do big[#big + 1] = { k = "w", n = name, a = 99999999999, t = now(ns) - i * D, p = 400 * D - 1 } end
        local v = GB.encode({ money = 99999999999, logRead = "1", log = big })
        ok(#v <= GB.MAX_VALUE, "worst value within the limit: " .. #v)
        local wd = GB.decode("GB", v)
        ok(wd, "decodes")
        ok(#wd.log <= GB.MAX_WIRE, "at most MAX_WIRE entries: " .. #wd.log)
        -- Usual: 20 lines with 18-byte names.
        local usual = {}
        for i = 1, 20 do usual[#usual + 1] = { k = "d", n = "測試名字六-測", a = 12345 * i, t = now(ns) - i * H, p = H / 2 } end
        local uv = GB.encode({ money = 5000000, logRead = "1", log = usual })
        local per = ns.Share.MAX_BYTES - #("S1~D~" .. A .. "~GB~" .. ns.Share.b36(now(ns)) .. "~zz~")
        local msgs = 1 + math.ceil(#uv / per)
        ok(msgs <= 6, string.format("usual value %d bytes, %d messages", #uv, msgs))
        T.realPrint(string.format("     GF-017 sizes: worst %d bytes (limit %d), usual %d bytes = %d messages", #v, GB.MAX_VALUE, #uv, msgs))
    end))

    test("GF-017 received records: malformed refused, not stored", done(function()
        local ns = login()
        local GB = ns.GuildBank
        local t = now(ns)
        local b36 = ns.Share.b36
        local bad = {
            "2;1;1;",                                                -- format
            "1;zz;x;",                                               -- log flag
            "1;-1;1;",                                               -- money
            "1;1;1;q," .. b36(t) .. ",1,1,甲",                       -- kind
            "1;1;1;d," .. b36(t + 3600) .. ",1,1,甲",                -- future
            "1;1;1;d," .. b36(1000) .. ",1,1,甲",                    -- before the epoch
            "1;1;1;d," .. b36(t) .. ",1,1,|cffff0000甲",             -- escape in a name
            "1;1;1;d," .. b36(t) .. ",1,1",                          -- missing field
            "1;1;1;" .. string.rep("d," .. b36(t) .. ",1,1,甲/", 30), -- too many
            "1;1;1;" .. string.rep("x", GB.MAX_VALUE),               -- too long
        }
        for i, v in ipairs(bad) do
            eq(GB.decode("GB", v), nil, "bad value " .. i)
            eq(offer(ns, B, v), "invalid", "not stored " .. i)
        end
        eq(ns.Share.get(B, "GB"), nil, "nothing kept")
        ok(GB.decode("GB", "1;1;?;"), "an empty log is fine")
    end))

    test("GF-017 only roster members are shown and merged; the newest seen time wins", done(function()
        local ns = login({ lines = LINES })
        local GB = ns.GuildBank
        local t = now(ns)
        local b36 = ns.Share.b36
        local theirs = "1;" .. b36(7654321) .. ";1;d," .. b36(t - 2 * H) .. "," .. b36(1800) .. "," .. b36(4444) .. ",測試乙"
        -- A stranger (not in the roster).
        eq(offer(ns, X, theirs, t - 60), "new", "stored (relayed for whoever knows them)")
        eq(GB.status().state, "never", "a stranger's record is not shown")
        eq(#GB.guildData().log, 0, "nor merged")
        -- A guild member.
        offer(ns, B, theirs, t - 120)
        wow.advance(1)
        local st = GB.status()
        eq(st.state, "ok", "shown")
        eq(st.best.money, 7654321, "their balance")
        eq(st.best.by, "測試乙", "seen by them")
        eq(find(GB.guildData().log, "d", "測試乙", 4444), 1, "their line merged into mine")
        -- My own visit, newer: mine wins.
        wow.advance(60)
        visit()
        st = GB.status()
        eq(st.best.money, 1234567, "my newer read wins")
        eq(st.best.own, true, "mine")
        -- Their newer one later wins again.
        wow.advance(600)
        local newer = "1;" .. b36(8000000) .. ";?;"
        offer(ns, B, newer, now(ns))
        st = GB.status()
        eq(st.best.money, 8000000, "the newest seen time wins")
        -- Merging the same record twice changes nothing.
        local n = #GB.guildData().log
        GB.resetMerged(); GB.absorb(B)
        eq(#GB.guildData().log, n, "absorbing again adds nothing")
    end))

    ---------------------------------------------------------------------------
    -- 5. Totals and filters
    ---------------------------------------------------------------------------

    test("GF-017 totals over 7 and 30 days; too short a log says so", function()
        local ns = login()
        local GB = ns.GuildBank
        local t0 = 1763370000
        local log = {
            line("d", "甲", 10000, t0 - 1 * D), line("s", "", 500, t0 - 2 * D), line("w", "乙", 3000, t0 - 3 * D),
            line("r", "丙", 700, t0 - 6 * D), line("d", "甲", 20000, t0 - 10 * D), line("b", "乙", 100000, t0 - 40 * D),
        }
        local s7 = GB.summary(log, 7, t0)
        eq(s7.income, 10500, "7 days in"); eq(s7.spend, 3700, "7 days out"); eq(s7.net, 6800, "7 days net")
        eq(s7.covered, nil, "40 days of log cover 7")
        local s30 = GB.summary(log, 30, t0)
        eq(s30.income, 30500, "30 days in"); eq(s30.spend, 3700, "30 days out")
        local short = GB.summary({ line("d", "甲", 1, t0 - 4 * D) }, 7, t0)
        eq(short.covered, 4, "only 4 days")
        local none = GB.summary({}, 7, t0)
        eq(none.any, false, "no log")
    end)

    test("GF-017 rows: 全部 / 存入 / 支出 and the name search", done(function()
        local ns = login({ lines = LINES })
        local GB = ns.GuildBank
        visit()
        eq(#GB.rows("all", ""), 5, "all")
        eq(#GB.rows("in", ""), 2, "deposits (deposit + summary)")
        eq(#GB.rows("out", ""), 3, "spending (withdraw, repair, tab)")
        eq(#GB.rows("all", "測試乙"), 2, "by name")
        eq(#GB.rows("out", " 乙 "), 2, "part of a name, trimmed")
        eq(#GB.rows("in", "測試丙"), 0, "none")
    end))

    ---------------------------------------------------------------------------
    -- 6. The view
    ---------------------------------------------------------------------------

    local function fakeView(ns)
        local views = {}
        ns.BankUI.addView = function(v) views[#views + 1] = v end
        ns.GuildBankUI.register()
        local parent = CreateFrame("Frame", nil, UIParent)
        return views, parent
    end

    test("GF-017 view: joins the page once; build once, draw many times without new frames", done(function()
        local ns = login({ lines = LINES })
        local views, parent = fakeView(ns)
        eq(#views, 1, "registered once")
        eq(views[1].key, "guildbank"); eq(views[1].text, "公會銀行"); eq(views[1].order, 30)
        eq(ns.GuildBankUI.register(), false, "not twice")
        views[1].build(parent)
        local frames = #wow.state.frames
        local objects = #wow.allObjects()
        views[1].build(parent)
        eq(#wow.state.frames, frames, "a second build makes nothing")
        for _ = 1, 5 do views[1].draw() end
        visit()
        for _ = 1, 5 do views[1].draw() end
        ns.GuildBankUI.setKind("out"); ns.GuildBankUI.scroll(-1); ns.GuildBankUI.setSearch("乙")
        eq(#wow.state.frames, frames, "drawing makes no frame")
        eq(#wow.allObjects(), objects, "nor any texture or text")
    end))

    test("GF-017 view: nobody yet, the balance, who saw it, totals, the rows", done(function()
        local ns = login({ lines = LINES })
        local views, parent = fakeView(ns)
        local UI = ns.GuildBankUI
        views[1].build(parent)
        views[1].draw()
        eq(UI.c.money:GetText(), "還沒有人打開過公會銀行", "never: no 0")
        ok(not UI.c.money:GetText():find("0", 1, true), "no zero shown")
        visit()
        views[1].draw()
        local m = UI.c.money:GetText()
        ok(m:find("UI%-GoldIcon") and m:find("UI%-SilverIcon") and m:find("UI%-CopperIcon"), "coin icons: " .. m)
        ok(m:find("123|r", 1, true) or m:find("123", 1, true), "123 gold")
        ok(UI.c.seen:GetText():find("由 測試甲 在", 1, true), "who saw it: " .. UI.c.seen:GetText())
        ok(UI.c.sum7:GetText():find("最近 7 天", 1, true), "7 days")
        ok(UI.c.sum30:GetText():find("只有最近 20 天的紀錄", 1, true), "short log noted: " .. UI.c.sum30:GetText())
        local rows = UI.shown()
        eq(#rows, 5, "five rows")
        local foundOut, foundIn = false, false
        for _, r in ipairs(rows) do
            if r.kind:find("支出", 1, true) and r.amount:find("^%-") and r.amount:find("ff4040", 1, true) then foundOut = true end
            if r.kind:find("存入", 1, true) and r.amount:find("^%+") and r.amount:find("40ff59", 1, true) then foundIn = true end
        end
        ok(foundOut, "spending in red with -")
        ok(foundIn, "deposits in green with +")
    end))

    test("GF-017 view: many rows reuse, the wheel, 還有 N 筆, search waits at most 0.15 s", done(function()
        local lines = {}
        for i = 1, 60 do lines[i] = { i % 2 == 0 and "deposit" or "withdraw", "角色" .. (i % 10), 100 * i, 0, 0, i % 25, i % 24 } end
        local ns = login({ lines = lines })
        local views, parent = fakeView(ns)
        local UI = ns.GuildBankUI
        views[1].build(parent)
        visit()
        views[1].draw()
        local n = UI.c.nRows
        ok(n >= 8, "rows that fit: " .. n)
        eq(#UI.shown(), n, "every row in use")
        ok(UI.c.more:GetText():find(string.format("還有 %d 筆", 60 - n), 1, true), "more: " .. UI.c.more:GetText())
        UI.scroll(-3)
        ok(UI.c.more:GetText():find(string.format("還有 %d 筆", 60 - n - 3), 1, true), "scrolled 3")
        UI.scroll(-1000)
        eq(UI.c.more:GetText(), "", "at the end")
        -- Search: typing waits, then filters.
        UI.c.search:SetText("角色3")
        UI.c.search._scripts.OnTextChanged(UI.c.search, true)
        ok(#UI.shown() == n, "not yet")
        wow.advance(0.15)
        for _, r in ipairs(UI.shown()) do eq(r.name, "角色3", "filtered row") end
        ok(#UI.shown() > 0 and #UI.shown() < n, "filtered")
        UI.setKind("in")
        for _, r in ipairs(UI.shown()) do ok(r.kind:find("存入", 1, true), "only deposits") end
    end))

    test("GF-017 view: no guild, another guild, missing API each say one sentence", done(function()
        local ns = login({ inGuild = false })
        local views, parent = fakeView(ns)
        views[1].build(parent); views[1].draw()
        eq(ns.GuildBankUI.c.note:GetText(), "你還沒有加入公會", "no guild")
        ok(not ns.GuildBankUI.c.money:IsShown(), "nothing else")
        removeBank()
        local ns2 = login({ guild = "別的公會" })
        local v2, p2 = fakeView(ns2)
        v2[1].build(p2); v2[1].draw()
        eq(ns2.GuildBankUI.c.note:GetText(), ns2.GuildBank.TEXT.other, "another guild")
        removeBank()
        local ns3 = login({ noApi = true })
        local v3, p3 = fakeView(ns3)
        v3[1].build(p3); v3[1].draw()
        eq(ns3.GuildBankUI.c.money:GetText(), ns3.GuildBank.TEXT.noapi, "no API")
        removeBank()
        local ns4 = login({ lines = {} })
        local v4, p4 = fakeView(ns4)
        v4[1].build(p4); visit(); v4[1].draw()
        eq(ns4.GuildBankUI.c.empty:GetText(), ns4.GuildBank.TEXT.logEmpty, "no log given")
    end))

    test("GF-017 the page redraws on a data change only while shown", done(function()
        local ns = login({ lines = LINES })
        local views, parent = fakeView(ns)
        local UI = ns.GuildBankUI
        views[1].build(parent); views[1].draw()
        local d = UI.c.draws
        parent:Hide()
        visit(); wow.advance(1)
        eq(UI.c.draws, d, "hidden: no draw")
        parent:Show()
        wow.advance(5 * H); visit(); wow.advance(1)
        ok(UI.c.draws > d, "shown: drawn")
    end))

    ---------------------------------------------------------------------------
    -- 7. Safety, diag, probe
    ---------------------------------------------------------------------------

    test("GF-017 the source never calls anything that moves gold or changes the bank", function()
        local forbidden = { "DepositGuildBankMoney", "WithdrawGuildBankMoney", "PickupGuildBankMoney", "SetGuildBankWithdrawGoldLimit",
            "BuyGuildBankTab", "RepairAllItems", "SetGuildBankTabPermissions", "SetGuildBankTabItemWithdraw", "SetGuildBankTabInfo",
            "SetGuildBankText", "AutoStoreGuildBankItem", "PickupGuildBankItem", "SplitGuildBankItem", "SetCurrentGuildBankTab",
            "QueryGuildBankTab", "DropCursorMoney", "PickupPlayerMoney", "CloseGuildBankFrame", "ShowGuildBankFrame",
            "GuildBankFrame_LoadUI", "SetGuildBankTabWithdraw", "GuildControlSetRankFlag", "SendMail" }
        for _, file in ipairs({ "GuildBank.lua", "GuildBankUI.lua" }) do
            local f = assert(io.open(ADDON_DIR .. "/" .. file, "r"))
            local src = f:read("*a")
            f:close()
            for _, name in ipairs(forbidden) do ok(not src:find(name, 1, true), file .. " does not name " .. name) end
            ok(not src:find("OnUpdate\"", 1, true) and not src:find("\"OnUpdate", 1, true), file .. " has no OnUpdate")
        end
        local list = table.concat(wow.TOC_FILES, ",")
        ok(list:find("BankStock.lua,GuildBank.lua,GuildBankUI.lua", 1, true), "after BankStock.lua in the TOC")
    end)

    test("GF-017 diag line and probe fields", done(function()
        local ns = login({ lines = LINES })
        visit()
        ok(ns.GuildBank.diagText():find("存款 1234567 銅", 1, true), "diag: " .. ns.GuildBank.diagText())
        ok(ns.GuildBank.diagText():find("本機收支 5 筆", 1, true), "diag log")
        local apis = table.concat(ns.Probe.APIS, ",")
        ok(apis:find("GetNumGuildBankMoneyTransactions", 1, true) and apis:find("GetGuildBankMoneyTransaction", 1, true), "probe names")
        ok(table.concat(ns.Probe.EVENTS, ","):find("GUILDBANK_UPDATE_WITHDRAWMONEY", 1, true), "probe event")
        -- /gftk probe bank with the guild bank open.
        C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(t) return t == 10 end }
        local r = ns.Probe.run("bank")
        C_PlayerInteractionManager = nil
        local b = r.bank
        eq(b.numGuildBankMoneyTransactions, "number:5", "count and type")
        ok(tostring(b.guildBankMoneyTransaction1):find("^ok:string,string,number"), "line types: " .. tostring(b.guildBankMoneyTransaction1))
        eq(b.guildBankMoneyKind1, "deposit", "a known kind name")
        eq(b.maxGuildBankTabs, "8", "the constant")
        ok(not ns.Probe.text():find("測試甲", 1, true), "no names in the probe text")
    end))
end
