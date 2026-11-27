-- GF-012-FIX (owner 2026-11-27: 臨時黑箱「無法正常指定成員」，成員要用選的):
-- the guild master's authority survives a roster row the client does not
-- return, IsGuildLeader() with no answer falls back to the rank index, only
-- a member of the guild roster can be appointed, the member picker (search,
-- online and offline, rank, class color, 已是保管人) and the diagnostics line.
-- Offline only; made-up names and GUIDs.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, C = "0000-0000000A", "0000-0000000C"

    local function roster(n)
        local r = wow.defaultRoster()
        r[1].rank, r[2].rank = "會長", "會員" -- I (A) am guild master
        for i = 5, n or 4 do
            r[i] = { name = "假員" .. i .. "-測試伺服器", rank = "會員", level = 10, class = "戰士", classToken = "WARRIOR",
                zone = "杜洛塔", online = i % 3 == 0, guid = string.format("Player-0000-%08X", 0x1000 + i) }
        end
        return r
    end
    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = roster(opts.n), myRankIndex = opts.myRankIndex })
        if opts.leader == nil then IsGuildLeader = function() return true end
        elseif opts.leader == "nil" then IsGuildLeader = function() return nil end
        else IsGuildLeader = nil end
        local ns = wow.loadAddon(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Supply then ns.Supply.rand = function(a) return a end end
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        wow.advance(40)
        ns.Bank.invalidate()
        return ns
    end
    local function done(fn) return function() local okRun, err = pcall(fn); IsGuildLeader = nil; if not okRun then error(err, 0) end end end

    test("GF-012-FIX a roster row the client does not return does not make the guild master unknown", done(function()
        local ns = login()
        eq((ns.Bank.authority()), "leader", "all rows")
        wow.state.missingRow = 4; ns.Bank.invalidate()
        eq((ns.Bank.authority()), "leader", "one member row missing")
        eq(ns.Bank.appoint("測試丙"), "ok", "appointed")
        wow.state.missingRow = 1; ns.Bank.invalidate()
        local auth, _, why = ns.Bank.authority()
        eq(auth, "unknown", "the guild master's own row missing"); eq(why, "roster", "why")
    end))

    test("GF-012-FIX IsGuildLeader() with no answer falls back to the rank index", done(function()
        local ns = login({ leader = "nil", myRankIndex = 0 })
        eq((ns.Bank.authority()), "leader", "rank 0 and the roster agree")
        ns = login({ leader = "nil" }) -- rank index 4: conflicts with the roster
        local auth, _, why = ns.Bank.authority()
        eq(auth, "unknown", "still refused"); eq(why, "conflict", "why")
    end))

    test("GF-012-FIX only a member of the guild roster can be appointed", done(function()
        local ns = login()
        eq(ns.Bank.appoint({ guid = "Player-0000-0000FFFF", name = "外人-別的伺服器" }), "not-found", "not in the roster")
        eq(ns.Bank.appoint("0000-0000FFFF"), "not-found", "author id not in the roster")
        eq(ns.Share.get(A, "K"), nil, "nothing published")
        eq(ns.Bank.appoint({ guid = "Player-" .. C }), "ok", "a roster member by GUID")
        local d = ns.Bank.diagText()
        ok(d:find("上次指定：找不到這位職工", 1, true) == nil, "the last result is ok now")
        eq(ns.Bank.appoint("外人"), "not-found", "unknown name")
        d = ns.Bank.diagText()
        ok(d:find("上次指定：找不到這位職工", 1, true), "diagnostics tell why: " .. d)
        ok(not d:find("0000-", 1, true) and not d:find("Player-", 1, true), "no GUID in diagnostics")
    end))

    test("GF-012-FIX candidates: online and offline, rank, class, search, 已是保管人", done(function()
        local ns = login()
        local rows = ns.Bank.candidates("")
        eq(#rows, 4, "everybody in the roster")
        eq(rows[1].online, true, "online first")
        local offline = 0
        for _, r in ipairs(rows) do if not r.online then offline = offline + 1 end; ok(r.rank ~= "" and r.classToken ~= "", "rank and class: " .. tostring(r.short) .. "/" .. tostring(r.rank) .. "/" .. tostring(r.classToken)) end
        eq(offline, 2, "offline members listed")
        rows = ns.Bank.candidates("丙")
        eq(#rows, 1, "search"); eq(rows[1].a, C, "C"); eq(rows[1].custodian, false, "not yet")
        eq(ns.Bank.appoint({ guid = "Player-" .. C }), "ok", "appointed")
        eq(ns.Bank.candidates("丙")[1].custodian, true, "marked")
        eq(#ns.Bank.candidates("沒有"), 0, "no match")
    end))

    test("GF-012-FIX the page: 選擇職工 opens the picker, a click appoints, rows are reused", done(function()
        local ns = login()
        local UI = ns.BankUI
        ns.Framework.open(UI.ID)
        -- The box only searches the roster: a name that is not a member opens the picker, appoints nobody.
        UI.controls.name:SetText("外人")
        wow.click(UI.controls.appoint)
        eq(ns.Share.get(A, "K"), nil, "nobody appointed from typed text")
        ok(UI.picker and UI.picker:IsShown() and UI.picker.search:GetText() == "外人", "picker opened with the text: " .. tostring(UI.picker) .. tostring(UI.picker and UI.picker:IsShown()) .. tostring(UI.picker and UI.picker.search:GetText()) .. tostring(UI.controls.result:GetText()))
        UI.picker:Hide(); UI.controls.name:SetText("")
        ok(UI.controls.appoint and not UI.controls.appoint.disabled, "選擇職工 enabled for the guild master")
        wow.click(UI.controls.appoint)
        local f = UI.picker
        ok(f and f:IsShown(), "picker shown")
        local shown = 0
        for _, b in ipairs(f.rows) do if b:IsShown() then shown = shown + 1 end end
        eq(shown, 4, "four members")
        eq(#f.rows, UI.PICKER_ROWS, "one frame per visible row")
        local target
        for _, b in ipairs(f.rows) do if b.data and b.data.a == C then target = b end end
        ok(target, "C listed"); wow.click(target)
        ok((ns.Bank.isCustodian(C)), "appointed by click")
        ok(not f:IsShown(), "picker closed")
        wow.click(UI.controls.appoint)
        for _, b in ipairs(f.rows) do if b.data and b.data.a == C then ok(b.mark:GetText():find("已是保管人", 1, true), "marked") end end
    end))

    test("GF-012-FIX a custodian who left the guild shows 已不在公會", done(function()
        local ns = login()
        eq(ns.Bank.appoint({ guid = "Player-" .. C }), "ok", "appointed")
        local UI = ns.BankUI
        ns.Framework.open(UI.ID)
        table.remove(wow.state.roster, 3)
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
        ns.Bank.invalidate(); UI.refresh()
        eq(UI.controls.rows[1].name:GetText(), "已不在公會", "left")
    end))

    test("GF-012-FIX the guild master appoints himself (full name, short name, roster name without realm)", done(function()
        local ns = login()
        eq(ns.Bank.appoint("測試甲"), "ok", "my short name")
        ok((ns.Bank.isCustodian(A)), "I am custodian")
        ns = login()
        eq(ns.Bank.appoint("測試甲-測試伺服器"), "ok", "my full name")
        -- The client gives same-realm names without "-Realm" (seen for my own row).
        wow.reset({ roster = roster(), myRankIndex = 0 })
        for _, m in ipairs(wow.state.roster) do m.name = m.name:gsub("%-.*$", "") end
        IsGuildLeader = function() return true end
        ns = wow.loadAddon(ADDON_DIR)
        wow.fire("PLAYER_LOGIN"); wow.fire("PLAYER_ENTERING_WORLD"); wow.advance(30); wow.advance(40)
        ns.Bank.invalidate()
        eq(ns.Bank.appoint("測試甲"), "ok", "roster name without realm, typed short")
        eq(ns.Bank.appoint("測試丙-測試伺服器"), "ok", "roster name without realm, typed full")
        eq(ns.Bank.appoint("測試丁-別的伺服器"), "not-found", "same name on another realm is not him")
        local mine
        for _, r in ipairs(ns.Bank.candidates("甲")) do if r.a == A then mine = r end end
        ok(mine and mine.custodian, "I am in the picker, marked")
    end))

    test("GF-012-FIX the page: a typed 名字-伺服器 finds a roster name without realm", done(function()
        wow.reset({ roster = roster(), myRankIndex = 0 })
        for _, m in ipairs(wow.state.roster) do m.name = m.name:gsub("%-.*$", "") end
        IsGuildLeader = function() return true end
        local ns = wow.loadAddon(ADDON_DIR)
        wow.fire("PLAYER_LOGIN"); wow.fire("PLAYER_ENTERING_WORLD"); wow.advance(30); wow.advance(40)
        ns.Bank.invalidate()
        local UI = ns.BankUI
        ns.Framework.open(UI.ID)
        UI.controls.name:SetText("測試丙-測試伺服器")
        wow.click(UI.controls.appoint)
        ok((ns.Bank.isCustodian(C)), "appointed from the page")
        UI.controls.name:SetText("測試甲")
        wow.click(UI.controls.appoint)
        ok((ns.Bank.isCustodian(A)), "myself from the page")
        eq(#ns.Bank.candidates("測試丁-測試伺服器"), 1, "picker search finds him")
        eq(#ns.Bank.candidates("測試丁-別的伺服器"), 0, "not on another realm")
        UI.controls.name:SetText("測試丁-別的伺服器")
        wow.click(UI.controls.appoint)
        eq((ns.Bank.isCustodian("0000-0000000D")), false, "another realm: nobody appointed")
    end))

    test("GF-012-FIX roster snapshot not loaded: says so instead of 找不到", done(function()
        local ns = login()
        ns.db.roster.snapshots = {}
        eq(ns.Bank.appoint("測試甲"), "roster", "not loaded")
        ok(ns.Bank.diagText():find("上次指定：公會名冊尚未載入", 1, true), "diagnostics")
    end))

    test("GF-012-FIX 1000 members: open the picker and type one letter", done(function()
        local ns = login({ n = 1000 })
        local UI = ns.BankUI
        ns.Framework.open(UI.ID)
        local calls0 = wow.state.rosterInfoCalls or 0
        local t0 = os.clock()
        UI.openPicker()
        local tOpen = os.clock() - t0
        UI.picker.search:SetText("9")
        t0 = os.clock()
        for _ = 1, 100 do UI.picker.query = "9"; UI.drawPicker() end
        local tType = (os.clock() - t0) / 100
        eq((wow.state.rosterInfoCalls or 0) - calls0, 0, "no game roster call from the picker")
        local shown = 0
        for _, b in ipairs(UI.picker.rows) do if b:IsShown() then shown = shown + 1 end end
        eq(shown, UI.PICKER_ROWS, "only the visible rows")
        T.realPrint(string.format("     GF-012-FIX 1000 人：開啟（首次建表）%.2f ms，打一個字後重畫平均 %.3f ms", tOpen * 1000, tType * 1000))
        ok(tOpen < 0.05 and tType < 0.05, "fast enough")
    end))
end
