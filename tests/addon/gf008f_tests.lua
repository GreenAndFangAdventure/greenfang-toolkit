-- GF-008-F (owner 2026-11-28: 「冒險指南的字太小了，請放大，或設計成有按鈕可以縮放字
-- 的大小／標記顏色的說明文字就用對應顏色／文字中提到座標或地名，要可以點，點開直接開
-- 地圖標示該地點／睡袋任務是否可偵測目前角色的進度，並提示目前實際進度」):
-- bigger text with A－ / A＋ (saved, not per character), the legend in its
-- colours, places as map links, the step the quest log says. Fake world map,
-- C_Map and C_QuestLog; offline only.

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
    -- done / onQuest: { [questID] = true }
    local function fakeQuests(done, on)
        local q = { done = done or {}, on = on or {} }
        _G.C_QuestLog = {
            IsQuestFlaggedCompleted = function(id) return q.done[id] == true end,
            IsOnQuest = function(id) return q.on[id] == true end,
        }
        return q
    end
    local function clearAll()
        _G.WorldMapFrame, _G.OpenWorldMap, _G.hooksecurefunc, _G.C_Map, _G.UiMapPoint, _G.C_QuestLog = nil, nil, nil, nil, nil, nil
    end
    local function login(map, quests, saved)
        wow.reset()
        clearAll()
        local ns = wow.login(ADDON_DIR, saved)
        ns.SleepingBagMap.resetSession()
        ns.SleepingBagMap.current = nil
        ns.SleepingBag.resetSession()
        local calls, wm
        if map then calls, wm = fakeMap(map ~= true and map or nil) end
        local q = quests and fakeQuests(quests.done, quests.on) or nil
        ns.Framework.open("sleepingbag")
        ns.SleepingBag.refresh()
        return ns, calls, wm, q
    end
    local function leftX(f) return f._points[#f._points][4] end

    test("GF-008-F text: bigger by default, A－ / A＋ in four sizes, saved for every character, scrolls", function()
        local ns = login(true)
        local SB, Th = ns.SleepingBag, ns.Theme
        eq(table.concat(Th.READ_SIZES, ","), "18,20,22,24", "four sizes, none under the old 16")
        eq(SB.textSize(), 20, "default 20 (was 16)")
        eq(SB.bodyText._font, "GreenFangToolkitRead20", "the page's font object")
        eq(_G.GreenFangToolkitRead20._fontSize, 20, "made at that size")
        eq(SB.sizer.minus._text, "A－", "A－")
        eq(SB.sizer.plus._text, "A＋", "A＋")
        ok(SB.sizer.minus._enabled and SB.sizer.plus._enabled, "both lit in the middle")
        SB.sizer.plus._scripts.OnClick(SB.sizer.plus)
        SB.sizer.plus._scripts.OnClick(SB.sizer.plus)
        eq(SB.textSize(), 24, "A＋ twice")
        eq(SB.bodyText._font, "GreenFangToolkitRead24", "redrawn bigger")
        eq(SB.sizer.plus._enabled, false, "A＋ dim at the largest")
        eq(SB.sizer.bigger(), false, "no size past the largest")
        ok(SB.scrollBar.scrollable, "big text in the page scrolls")
        SB.scrollBar.scrollBy(3)
        eq(SB.scroll:GetVerticalScroll(), 3 * 28, "the bar moves the text by lines")
        for _ = 1, 4 do SB.sizer.smaller() end
        eq(SB.textSize(), 18, "A－ down to the smallest")
        eq(SB.sizer.minus._enabled, false, "A－ dim at the smallest")
        local saved = wow.logout()
        eq(saved.GreenFangToolkitDB.settings.modules.sleepingbag.textSize, 18, "saved: settings.modules.sleepingbag.textSize")
        local alt = wow.defaultPlayer()
        alt.guid = "Player-0000-0000000F"
        wow.reset({ player = alt })
        ns = wow.login(ADDON_DIR, saved)
        ns.Framework.open("sleepingbag")
        eq(ns.SleepingBag.textSize(), 18, "another character: the same size")
        ns.Framework.moduleSettings("sleepingbag").textSize = 17
        eq(ns.SleepingBag.textSize(), 20, "a size not in the list: the default")
        clearAll()
    end)

    test("GF-008-F the buttons keep their places: A－ / A＋ between 看地圖 and 重設進度, the hint row under them", function()
        local ns = login(true)
        local SB = ns.SleepingBag
        local mapRight = leftX(SB.mapButton) + 100
        local minusX, plusX = leftX(SB.sizer.minus), leftX(SB.sizer.plus)
        ok(minusX >= mapRight, "A－ right of 看地圖")
        ok(plusX >= minusX + ns.Widgets.SIZER_W, "A＋ right of A－")
        ok(plusX + ns.Widgets.SIZER_W <= 880, "A＋ left of 重設進度")
        local hintY = SB.hintLine._points[1][5]
        ok(hintY < -64 - ns.BUTTON_H, "the hint under the button row")
        ok(SB.jumpButton._points[1][5] < -64 - ns.BUTTON_H + 1, "跳到 under the button row")
        ok(SB.scroll._points[1][5] < SB.jumpButton._points[1][5] - ns.BUTTON_H, "the text under 跳到")
        clearAll()
    end)

    test("GF-008-F the colour legend: each line in its own colour, from the pins' colour table", function()
        local ns = login(true)
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        eq(M.LEGEND, "標記顏色｜綠色：接任務｜金色：交任務並接下一個｜藍色：路線點（推車、飛艇塔、飛行點）｜灰色：大約位置",
            "the plain legend unchanged")
        local text = SB.richText(20)
        for _, style in ipairs({ M.KINDS.start, M.KINDS.turnin, M.KINDS.route, M.APPROX }) do
            local line = M.square(style.color, 16) .. " " .. M.hex(style.color) .. style.word .. "："
            ok(text:find(line, 1, true), style.word .. ": square and text in its colour")
        end
        ok(text:find("|cff4dff4d綠色：接任務|r", 1, true), "green is 0.30, 1.00, 0.30")
        -- One table: change the pins' colour, the legend follows.
        local was = M.KINDS.start.color
        M.KINDS.start.color = { 1, 0, 0 }
        ok(SB.richText(20):find("|cffff0000綠色", 1, true), "the legend reads the pins' colour")
        M.KINDS.start.color = was
        ok(SB.bodyText._text:find("|cff", 1, true), "the page draws the coloured text")
        clearAll()
    end)

    test("GF-008-F places with coordinates are links; places without are plain text", function()
        local ns = login(true)
        local SB = ns.SleepingBag
        local text = SB.richText(20)
        local L = function(s, p, t) return SB.link(s, p, t) end
        ok(text:find("【第 1／5 步】" .. L(1, 1, "貧瘠之地"), 1, true), "the zone in the header")
        ok(text:find("位置：" .. L(1, 1, "貧瘠之地（46, 74）") .. "（多來源一致）", 1, true), "the coordinates")
        ok(text:find(L(1, 1, "燒黑的瞭望塔"), 1, true), "a place in the text")
        local linked = {}
        for shown in text:gmatch("|Hgfsb:%d+:%d+|h(.-)|h") do linked[#linked + 1] = shown end
        local all = table.concat(linked, "／")
        eq(#linked, 3, "three links on step 1: " .. all)
        ok(text:find("陶拉祖營地", 1, true) and not all:find("陶拉祖營地", 1, true), "陶拉祖營地 has no point: plain")
        SB.nextStep()
        text = SB.richText(20)
        ok(text:find(L(2, 2, "荊棘谷（32, 29）"), 1, true), "a point on another map")
        ok(text:find(L(2, 2, "格羅姆高營地"), 1, true) and text:find(L(2, 1, "亞歷斯頓農場"), 1, true), "both places in the text")
        -- Every word of every point is in its step's text, and only points with coordinates have words.
        for _, st in ipairs(SB.route().steps) do
            for _, p in ipairs(st.points) do
                for _, w in ipairs(p.words or {}) do
                    ok(st.action:find(w, 1, true), st.id .. ": " .. w .. " is in the text")
                    ok(p.x and p.y, st.id .. ": " .. w .. " has coordinates")
                end
            end
        end
        eq(select(2, SB.parseLink("gfsb:3:2")), 2, "the link's point")
        clearAll()
    end)

    test("GF-008-F a click opens the map on that point; a hint on the mouse; combat says why", function()
        local ns, calls, wm = login(true)
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        local frame = SB.scrollChild
        SB.nextStep()
        frame._scripts.OnHyperlinkEnter(frame, "gfsb:2:2", ns.SleepingBagMap.hex(SB.LINK_COLOR) .. "格羅姆高營地|r")
        eq(GameTooltip._lines[1].text, "格羅姆高營地", "the place")
        eq(GameTooltip._lines[2].text, "點一下在地圖上標出", "the hint")
        frame._scripts.OnHyperlinkLeave(frame)
        frame._scripts.OnHyperlinkClick(frame, "gfsb:2:2", "格羅姆高營地", "LeftButton")
        eq(calls.open[#calls.open], 1434, "the jungle map opened")
        eq(wm.mapID, 1434, "on Grom'gol")
        ok(M.pin(2)._shown and not M.pin(1)._shown, "Grom'gol's pin")
        frame._scripts.OnHyperlinkClick(frame, "gfsb:2:1", "亞歷斯頓農場", "LeftButton")
        eq(wm.mapID, 1436, "Westfall")
        ok(M.pin(1)._shown, "the Westfall pin")
        eq(SB.openLink("gfsb:1:1"), false, "a link of another step does nothing")
        eq(SB.openLink("gfsb:2:9"), false, "no such point")
        wow.setCombat(true)
        wow.clearPrinted()
        local n = #calls.open
        local r, why = SB.openLink("gfsb:2:1")
        eq(r, false, "not in combat")
        eq(why, "combat", "why")
        eq(#calls.open, n, "no map opened")
        ok(table.concat(wow.printed(), "\n"):find("戰鬥中不能打開地圖", 1, true), "one line says why")
        wow.setCombat(false)
        clearAll()
    end)

    test("GF-008-F the waypoint fallback goes to the clicked point", function()
        local ns, calls = login({ noCanvas = true, waypoint = true })
        local SB = ns.SleepingBag
        SB.nextStep()
        eq(SB.openLink("gfsb:2:2"), "waypoint", "a waypoint")
        eq(calls.waypoints[#calls.waypoints].uiMapID, 1434, "on Grom'gol")
        ok(math.abs(calls.waypoints[#calls.waypoints].x - 0.32) < 1e-9, "its x")
        clearAll()
    end)

    test("GF-008-F the quest log: no API, no record, the step it says, 跳到 pressed by the player", function()
        local ns = login(true)
        local SB = ns.SleepingBag
        ok(SB.hintLine._text:find("無法自動判斷", 1, true), "no C_QuestLog: cannot tell")
        ok(not SB.jumpButton._shown, "no 跳到")
        local q = fakeQuests()
        SB.refresh()
        ok(SB.hintLine._text:find("還沒有這條任務", 1, true), "no record of the chain")
        ok(not SB.jumpButton._shown, "no 跳到 without a record")
        q.on[79007] = true
        SB.refresh()
        eq(SB.detect().step, 2, "the first quest taken: step 2")
        eq(SB.state().step, 1, "the page does not move by itself")
        ok(SB.jumpButton._shown, "跳到 offered")
        eq(SB.jumpButton._text, "跳到第 2 步", "its text")
        q.on[79007], q.done[79007], q.done[79192] = nil, true, true
        SB.refresh()
        eq(SB.detect().step, 3, "Westfall done, the litter turned in: step 3")
        q.on[79974], q.done[79980] = true, true
        SB.refresh()
        eq(SB.detect().step, 4, "the mound done: step 4")
        ok(SB.hintLine._text:find("實際大概在第 4 步（目前顯示第 1 步）", 1, true), "the line")
        SB.jumpButton._scripts.OnClick(SB.jumpButton)
        eq(SB.state().step, 4, "pressed: step 4")
        ok(not SB.jumpButton._shown, "same step: no 跳到")
        ok(SB.hintLine._text:find("和目前顯示的一樣", 1, true), "says it matches")
        q.done[79974], q.done[79975], q.done[79976] = true, true, true
        SB.refresh()
        eq(SB.jumpButton._text, "跳到完成", "the chain done")
        SB.jumpButton._scripts.OnClick(SB.jumpButton)
        ok(SB.isFinished(), "finished")
        clearAll()
    end)

    test("GF-008-F a quest turned in redraws the open page (no polling); a closed page stays", function()
        local ns = login(true, { done = {}, on = {} })
        local SB = ns.SleepingBag
        ok(SB.hintLine._text:find("還沒有這條任務", 1, true), "nothing yet")
        wow.fire("QUEST_TURNED_IN", 79007, 0, 0)
        eq(SB.detect().step, 3, "turned in, before the flag is set: counted")
        ok(SB.hintLine._text:find("第 3 步", 1, true), "the open page redrawn")
        ns.Framework.toggle()
        local before = SB.hintLine._text
        _G.C_QuestLog.IsOnQuest = function(id) return id == 79974 end
        wow.fire("QUEST_ACCEPTED", 5, 79974)
        eq(SB.hintLine._text, before, "closed: not redrawn")
        clearAll()
    end)

    test("GF-008-F /gftk probe sleepingbag prints the chain's flags; nothing per frame, no timer", function()
        local ns = login(true, { done = { [79007] = true }, on = { [79192] = true } })
        wow.clearPrinted()
        ns.Probe.command("sleepingbag")
        local out = table.concat(wow.printed(), "\n")
        ok(out:find("睡袋任務 1：79007｜已完成 true｜在任務記錄 false", 1, true), "79007")
        ok(out:find("睡袋任務 2：79192｜已完成 false｜在任務記錄 true", 1, true), "79192")
        ok(out:find("79976", 1, true), "to the last")
        ok(out:find("任務進度：", 1, true), "and the guide's line")
        for _, f in ipairs({ "SleepingBag.lua", "SleepingBagMap.lua" }) do
            local src = assert(io.open(ADDON_DIR .. "/" .. f, "rb")):read("*a")
            ok(not src:find("OnUpdate", 1, true) and not src:find("C_Timer", 1, true), f .. ": no OnUpdate, no timer")
        end
        clearAll()
    end)
end
