-- GF-008-E (owner 2026-11-28: 步驟太多太囉嗦、要多參考資料（部落解法）、改用上一步／
-- 下一步按鈕、沒有對應地點的步驟要併進有地點的步驟): five steps, each with a
-- place; 上一步 / 下一步 / 第 N／M 步, one step on the page; the step is
-- remembered; the pins and the waypoint follow the step. Fake world map and
-- C_Map; offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local NAMES = { [1413] = "貧瘠之地", [1434] = "荊棘谷", [1436] = "西部荒野", [1442] = "石爪山脈", [1432] = "洛克莫丹",
        [1417] = "阿拉希高地", [1424] = "希爾斯布萊德丘陵", [1414] = "卡林多", [1415] = "東部王國" }
    local function fakeMap(opts)
        opts = opts or {}
        local calls = { open = {}, waypoints = {}, cleared = 0 }
        local wm = CreateFrame("Frame", "WorldMapFrame", UIParent)
        wm:Hide()
        local canvas = CreateFrame("Frame", nil, wm)
        if not opts.noCanvas then
            wm.GetCanvas = function() return canvas end
            wm.SetMapID = function(self, id) self.mapID = id end
            wm.GetMapID = function(self) return self.mapID end
        end
        _G.WorldMapFrame = (not opts.noCanvas) and wm or nil
        _G.OpenWorldMap = function(id) calls.open[#calls.open + 1] = id; wm:Show(); if wm.SetMapID then wm:SetMapID(id) end end
        _G.hooksecurefunc = function(t, name, post)
            local orig = t[name]
            t[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
        end
        _G.C_Map = {
            GetMapInfo = function(id) return NAMES[id] and { mapID = id, name = NAMES[id] } or nil end,
            GetMapChildrenInfo = function() return {} end,
        }
        if opts.waypoint then
            C_Map.SetUserWaypoint = function(p) calls.waypoints[#calls.waypoints + 1] = p end
            C_Map.ClearUserWaypoint = function() calls.cleared = calls.cleared + 1 end
            _G.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }
        end
        return calls, wm, canvas
    end
    local function clearMap()
        _G.WorldMapFrame, _G.OpenWorldMap, _G.hooksecurefunc, _G.C_Map, _G.UiMapPoint = nil, nil, nil, nil, nil
    end
    local function login(map, opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.SleepingBagMap.resetSession()
        ns.SleepingBagMap.current = nil
        local calls, wm, canvas
        if map then calls, wm, canvas = fakeMap(map ~= true and map or nil) else clearMap() end
        ns.Framework.open("sleepingbag")
        ns.SleepingBag.refresh()
        return ns, calls, wm, canvas
    end

    -- The run.lua glyph rule (GF-000-D): ASCII, CJK, CJK punctuation, full-width forms, ▲▼.
    local function codepoints(s)
        local cps, i = {}, 1
        while i <= #s do
            local b = s:byte(i)
            local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
            local cp = len == 1 and b or (b % (2 ^ (7 - len)))
            for k = 2, len do cp = cp * 64 + (s:byte(i + k - 1) or 0x80) % 64 end
            cps[#cps + 1] = cp
            i = i + len
        end
        return cps
    end
    local function glyphOK(cp)
        return cp < 0x80 or (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
            or (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFFEF) or cp == 0x25B2 or cp == 0x25BC
    end
    local function badGlyphs(t)
        local bad = {}
        for _, cp in ipairs(codepoints(t)) do if not glyphOK(cp) then bad[#bad + 1] = string.format("U+%04X", cp) end end
        return table.concat(bad, " ")
    end

    test("GF-008-E data: five steps, every step has a place on its own map (no step without one)", function()
        local ns = login()
        local route = ns.SleepingBagRoutes.Horde
        eq(#route.steps, 5, "five steps")
        local ids = {}
        for _, st in ipairs(route.steps) do ids[#ids + 1] = st.id end
        eq(table.concat(ids, ","), "barrens,westfall,stonetalon,loch-modan,thoradin-wall", "the order")
        for _, r in pairs(ns.SleepingBagRoutes) do
            if type(r) == "table" and r.steps then
                eq(#ns.SleepingBagCheck(r), 0, "no problems: " .. table.concat(ns.SleepingBagCheck(r), "；"))
            end
        end
        for i, st in ipairs(route.steps) do
            ok(st.x and st.y, "step " .. i .. ": x / y on its own map")
            eq(st.noPin, nil, "step " .. i .. ": no step without a place")
            ok(not st.action:find("\n") and #st.action < 240, "step " .. i .. ": one line to do")
            ok(not st.tip or (not st.tip:find("\n") and #st.tip < 160), "step " .. i .. ": at most one short reminder")
            eq(st.verified, false, "step " .. i .. ": 待實地驗證")
        end
        -- The check catches a step without a place (a travel step on its own).
        local bad = ns.SleepingBagCheck({ steps = {
            { id = "a", mapID = 1, action = "x", points = { { x = 1, y = 1 } } },
            { id = "b", mapID = 2, action = "坐飛艇" },
            { id = "c", mapID = 3, action = "x", points = { { x = 1, y = 1, mapID = 4 } } },
        } })
        eq(table.concat(bad, "；"), "第 2 步沒有地點；第 3 步沒有地點", "travel-only and other-map-only steps are caught")
    end)

    test("GF-008-E the page: one step, 第 N／M 步, 上一步 dim on the first, 完成 on the last", function()
        local ns = login(true)
        local SB = ns.SleepingBag
        local text = SB.pageText()
        ok(text:find("【第 1／5 步】貧瘠之地", 1, true), "the step's header")
        ok(text:find("位置：貧瘠之地（46, 74）", 1, true), "its place")
        ok(text:find("要做的事：", 1, true) and text:find("提醒：", 1, true), "what to do, one reminder")
        ok(not text:find("【全部步驟】", 1, true), "no list of every step")
        ok(not text:find("西部荒野（37, 50）", 1, true), "other steps not shown")
        for _, gone in ipairs({ "前往方式：", "守衛與危險：", "沒有飛行點時：", "目標：" }) do ok(not text:find(gone, 1, true), "no " .. gone) end
        eq(SB.stepLabel._text, "第 1／5 步", "the label")
        eq(SB.backButton._text, "上一步", "上一步")
        eq(SB.backButton._enabled, false, "dim on the first step")
        eq(SB.nextButton._text, "下一步", "下一步")
        ok(SB.nextButton._enabled ~= false, "lit")
        SB.nextStep()
        eq(SB.stepLabel._text, "第 2／5 步", "step 2")
        ok(SB.backButton._enabled ~= false, "上一步 lit")
        ok(SB.pageText():find("【第 2／5 步】西部荒野", 1, true), "step 2 shown")
        for _ = 1, 3 do SB.nextStep() end
        eq(SB.stepLabel._text, "第 5／5 步", "the last step")
        eq(SB.nextButton._text, "完成", "下一步 says 完成")
        ok(SB.nextButton._enabled ~= false, "and is lit")
        SB.nextStep()
        ok(SB.isFinished(), "finished")
        eq(SB.stepLabel._text, "全部完成（共 5 步）", "finished label")
        eq(SB.nextButton._enabled, false, "完成 dim when finished")
        ok(SB.backButton._enabled ~= false, "上一步 goes back to step 5")
        ok(SB.pageText():find("已完成全部 5 步", 1, true), "the reward page")
        eq(SB.nextStep(), false, "nothing after finished")
        SB.back()
        eq(SB.stepLabel._text, "第 5／5 步", "back on step 5")
        for _ = 1, 4 do SB.back() end
        eq(SB.back(), false, "no step before 1")
        eq(SB.backButton._enabled, false, "dim again")
        clearMap()
    end)

    test("GF-008-E the step is remembered: reopen the window, relog; another character has its own", function()
        local ns = login()
        local SB = ns.SleepingBag
        SB.nextStep(); SB.nextStep()
        ns.Framework.open("roster")
        ns.Framework.open("sleepingbag")
        eq(SB.stepLabel._text, "第 3／5 步", "reopened: same step")
        local saved = wow.logout()
        local rec = saved.GreenFangToolkitDB.settings.modules.sleepingbag.characters[wow.defaultPlayer().guid]
        eq(rec.step, 3, "saved: step")
        eq(rec.layout, 2, "saved: layout")
        wow.reset({ now = 1763380000 })
        ns = wow.login(ADDON_DIR, saved)
        ns.Framework.open("sleepingbag")
        eq(ns.SleepingBag.state().step, 3, "relog: same step")
        eq(ns.SleepingBag.stepLabel._text, "第 3／5 步", "relog: the label")
        saved = wow.logout()
        local alt = wow.defaultPlayer()
        alt.guid = "Player-0000-0000000F"
        wow.reset({ now = 1763390000, player = alt })
        ns = wow.login(ADDON_DIR, saved)
        eq(ns.SleepingBag.state().step, 1, "alt: its own step")
    end)

    test("GF-008-E a step saved by the nine-step layout moves to the step with the same place", function()
        local want = { [1] = 1, [3] = 2, [4] = 3, [6] = 3, [7] = 4, [8] = 4, [9] = 5, [10] = 6 }
        for old, new in pairs(want) do
            wow.reset()
            local ns = wow.login(ADDON_DIR)
            local s = ns.Framework.charState("sleepingbag")
            s.step, s.layout = old, nil
            eq(ns.SleepingBag.state().step, new, "old step " .. old)
            eq(s.layout, 2, "moved once")
            s.step = 2
            eq(ns.SleepingBag.state().step, 2, "not moved again")
        end
    end)

    test("GF-008-E the pins follow the step; nothing of the old step stays", function()
        local ns, _, wm = login(true)
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        eq(SB.showMap(), "canvas", "step 1 pinned")
        ok(M.pin(1)._shown, "step 1's pin")
        SB.nextStep() -- Westfall; the map still shows the Barrens
        eq(M.current.step.id, "westfall", "the pins moved to step 2")
        ok(not M.pin(1)._shown, "no Barrens pin left")
        wm:SetMapID(1436)
        ok(M.pin(1)._shown, "the Westfall pin")
        eq(M.pin(1).at.point.label, "燒毀推車旁的殘骸", "the turn-in")
        wm:SetMapID(1434)
        ok(M.pin(2)._shown and not M.pin(1)._shown, "Grom'gol on the jungle map")
        SB.nextStep() -- Stonetalon: three points
        wm:SetMapID(1442)
        ok(M.pin(1)._shown and M.pin(2)._shown and M.pin(3)._shown, "three Stonetalon pins")
        SB.nextStep() -- Loch Modan: one point
        wm:SetMapID(1432)
        ok(M.pin(1)._shown and not M.pin(2)._shown and not M.pin(3)._shown, "one pin, the others gone")
        wm:SetMapID(1442)
        ok(not M.pin(1)._shown and not M.pin(2)._shown and not M.pin(3)._shown, "nothing left on Stonetalon")
        SB.back()
        ok(M.pin(1)._shown and M.pin(3)._shown, "back: Stonetalon's pins again")
        for _ = 1, 3 do SB.nextStep() end -- finished
        eq(M.current, nil, "finished: nothing pinned")
        for _, p in ipairs(M.pins()) do ok(not p._shown, "no pin left") end
        clearMap()
    end)

    test("GF-008-E nothing drawn before 看地圖; the waypoint follows the step and is cleared", function()
        local ns, calls = login({ noCanvas = true, waypoint = true })
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        SB.nextStep()
        eq(#calls.waypoints, 0, "no waypoint before 看地圖")
        eq(M.current, nil, "nothing before 看地圖")
        eq(SB.showMap(), "waypoint", "a waypoint")
        eq(calls.waypoints[1].uiMapID, 1436, "Westfall")
        SB.nextStep()
        eq(#calls.waypoints, 2, "replaced on 下一步")
        eq(calls.waypoints[2].uiMapID, 1442, "Stonetalon")
        ok(math.abs(calls.waypoints[2].x - 0.406) < 1e-9, "the camp")
        SB.back()
        eq(calls.waypoints[3].uiMapID, 1436, "上一步: Westfall again")
        SB.reset()
        eq(calls.waypoints[4].uiMapID, 1413, "reset: the Barrens")
        for _ = 1, 5 do SB.nextStep() end
        ok(calls.cleared >= 1, "finished: our waypoint is cleared")
        clearMap()
    end)

    test("GF-008-E no OnUpdate, no timer, no new event; texts use only glyphs the game font has", function()
        for _, f in ipairs({ "SleepingBag.lua", "SleepingBagMap.lua", "SleepingBagData.lua" }) do
            local src = assert(io.open(ADDON_DIR .. "/" .. f, "rb")):read("*a")
            ok(not src:find("OnUpdate", 1, true), f .. ": no OnUpdate")
            ok(not src:find("C_Timer", 1, true), f .. ": no timer")
            local n = 0
            for _ in src:gmatch("RegisterEvent%(") do n = n + 1 end
            -- GF-008-F: SleepingBag.lua listens to QUEST_TURNED_IN / QUEST_ACCEPTED (the 任務進度 line).
            eq(n, (f == "SleepingBagMap.lua" or f == "SleepingBag.lua") and 2 or 0, f .. ": events (combat; GF-008-F the two quest ones)")
        end
        local ns = login(true)
        local SB = ns.SleepingBag
        local route = SB.route()
        for i = 1, #route.steps + 1 do
            for _, t in ipairs({ SB.pageText(), SB.stepLabel._text, SB.nextButton._text, SB.backButton._text }) do
                eq(badGlyphs(t), "", "step " .. i .. ": " .. t:sub(1, 40))
            end
            SB.nextStep()
        end
        for _, st in ipairs(route.steps) do
            for _, k in ipairs({ "action", "tip", "zone", "landmark", "rpgHint", "object" }) do
                if st[k] then eq(badGlyphs(st[k]), "", st.id .. "." .. k) end
            end
            for _, p in ipairs(st.points) do eq(badGlyphs(p.label .. (p.approx or "")), "", st.id .. " point") end
        end
        clearMap()
    end)
end
