-- GF-008-B (owner 2026-11-26): the sleeping-bag guide shows normal mode only
-- (the RPG code and saved progress stay), and 看地圖 marks the step on
-- Blizzard's world map (SleepingBagMap.lua). The world map, C_Map and
-- UiMapPoint here are fakes: what Forever really offers is for /gftk probe
-- (MANUAL §GF-008-B). Offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    -- A fake classic world map: WorldMapFrame with a canvas, C_Map with names.
    local NAMES = { [1413] = "貧瘠之地", [1434] = "荊棘谷", [1436] = "西部荒野", [1442] = "石爪山脈", [1432] = "洛克莫丹", [1424] = "希爾斯布萊德丘陵" }
    local function fakeMap(opts)
        opts = opts or {}
        local calls = { open = {}, waypoints = {} }
        local wm = CreateFrame("Frame", "WorldMapFrame", UIParent)
        wm:Hide()
        local canvas = CreateFrame("Frame", nil, wm)
        if not opts.noCanvas then
            wm.GetCanvas = function() return canvas end
            wm.SetMapID = function(self, id) self.mapID = id end
            wm.GetMapID = function(self) return self.mapID end
            wm.OnMapChanged = function() end
        end
        -- (a mock frame answers any method name, so "no canvas" is no world map frame at all)
        _G.WorldMapFrame = (not opts.noCanvas) and wm or nil
        _G.OpenWorldMap = function(id) calls.open[#calls.open + 1] = id; wm:Show(); if wm.SetMapID then wm:SetMapID(id) end end
        _G.hooksecurefunc = function(t, name, post)
            local orig = t[name]
            t[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
        end
        local names = opts.names or NAMES
        _G.C_Map = {
            GetMapInfo = function(id) return names[id] and { mapID = id, name = names[id] } or nil end,
            GetMapChildrenInfo = function() return opts.children or {} end,
            GetBestMapForUnit = function() return 1413 end,
        }
        if opts.waypoint then
            C_Map.SetUserWaypoint = function(p) calls.waypoints[#calls.waypoints + 1] = p end
            _G.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }
        end
        return calls, wm, canvas
    end
    local function clearMap()
        _G.WorldMapFrame, _G.OpenWorldMap, _G.hooksecurefunc, _G.C_Map, _G.UiMapPoint = nil, nil, nil, nil, nil
    end
    -- The fakes go in after login (wow.reset puts the mock's globals back).
    local function login(map)
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        ns.SleepingBagMap.resetSession()
        ns.SleepingBagMap.current = nil
        local calls, wm, canvas
        if map then calls, wm, canvas = fakeMap(map ~= true and map or nil) else clearMap() end
        return ns, calls, wm, canvas
    end
    local function open(ns)
        ns.Framework.open("sleepingbag")
        ns.SleepingBag.refresh()
        return ns.SleepingBag.mapButton
    end

    test("GF-008-B normal mode only: no switch, every step listed; a saved rpg character keeps its mode and step", function()
        local ns = login()
        local SB = ns.SleepingBag
        open(ns)
        eq(SB.viewMode(), "normal", "normal shown")
        local text = SB.pageText()
        ok(text:find("【全部步驟】", 1, true) and text:find("貧瘠之地（46, 74）", 1, true), "the normal page")
        ok(text:find("狀態：待實地驗證", 1, true), "still 待實地驗證")
        -- The RPG text is still there for later.
        ok(not SB.pageText("rpg"):find("46, 74", 1, true), "RPG text kept (hides coordinates)")
        -- A character saved in rpg with progress.
        SB.state().mode = "rpg"; SB.complete(); SB.complete()
        local saved = wow.logout()
        wow.reset({ now = 1763380000 })
        ns = wow.login(ADDON_DIR, saved)
        SB = ns.SleepingBag
        open(ns)
        eq(SB.state().mode, "rpg", "saved mode untouched")
        eq(SB.state().step, 3, "the step kept")
        eq(SB.viewMode(), "normal", "shown as normal")
        ok(SB.pageText():find("＞ 3.", 1, true), "normal page at step 3")
        for _, f in ipairs(wow.state.frames) do
            local t = f._text or ""
            if t:find("目前：", 1, true) or t == "顯示座標與走法" then ok(f._shown == false, "hidden: " .. t) end
        end
    end)

    test("GF-008-B 看地圖: the world map on the step's zone, one pin at x / y in Blizzard art; follows the map and the step", function()
        local ns, calls, wm, canvas = login(true)
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        local b = open(ns)
        eq(b._text, "看地圖", "the button (3 characters)")
        ok(b._shown ~= false and b._enabled ~= false, "shown and lit on step 1 (x / y known)")
        eq(SB.showMap(), "canvas", "drawn on the canvas")
        eq(calls.open[1], 1413, "opened on 貧瘠之地")
        eq(wm:GetMapID(), 1413, "the map shows it")
        local pin = M.pin()
        ok(pin and pin._shown, "the pin")
        eq(pin._parent, canvas, "on the map canvas")
        eq(pin.icon._texture, M.PIN_TEXTURE, "Blizzard's icon")
        ok(M.PIN_TEXTURE:find("^Interface\\"), "a game file")
        local W, H = canvas:GetWidth(), canvas:GetHeight()
        ok(math.abs(pin.px - 0.46 * W) < 0.01 and math.abs(pin.py + 0.74 * H) < 0.01, "at 46, 74")
        -- The player looks at another zone: the pin goes; back: it is there again.
        wm:SetMapID(1436)
        ok(not pin._shown, "another zone: no pin")
        wm:SetMapID(1413)
        ok(pin._shown, "back on 貧瘠之地")
        wm:Hide(); ok(not pin._shown, "map closed: no pin")
        wm:Show(); ok(pin._shown, "map open again")
        -- Step 2 has no x / y: no button, no pin.
        SB.complete()
        ok(b._shown == false, "no button without x / y")
        ok(not pin._shown, "no pin without x / y")
        -- Step 3 (西部荒野 37, 50): the button again.
        SB.complete()
        ok(b._shown ~= false, "button on step 3")
        eq(SB.showMap(), "canvas", "drawn")
        eq(wm:GetMapID(), 1436, "西部荒野")
        ok(math.abs(pin.px - 0.37 * W) < 0.01, "at 37")
        -- Nothing saved or sent by the map.
        eq(ns.db.sleepingbagMap, nil, "no saved map data")
        clearMap()
    end)

    test("GF-008-B the zone: the mapID is checked by name, else found by name; not found = no button", function()
        local ns, calls = login({ names = { [1413] = "別的地方" }, children = { { mapID = 9001, name = "The Barrens" } } })
        local M = ns.SleepingBagMap
        local step = ns.SleepingBag.currentStep()
        eq(M.mapFor(step), 9001, "found by its English name")
        open(ns)
        eq(ns.SleepingBag.showMap(), "canvas", "shown")
        eq(calls.open[1], 9001, "on the found map")
        ns = login({ names = {}, children = {} })
        eq(ns.SleepingBagMap.mapFor(ns.SleepingBag.currentStep()), nil, "no zone")
        local b = open(ns)
        ok(b._shown == false, "no button")
        clearMap()
    end)

    test("GF-008-B no canvas: a waypoint when the client has one; nothing at all: no button", function()
        local ns, calls = login({ noCanvas = true, waypoint = true })
        local b = open(ns)
        eq(ns.SleepingBagMap.method(), "waypoint", "the fallback")
        ok(b._shown ~= false, "the button")
        eq(ns.SleepingBag.showMap(), "waypoint", "a waypoint")
        local p = calls.waypoints[1]
        ok(p and p.uiMapID == 1413 and math.abs(p.x - 0.46) < 1e-9 and math.abs(p.y - 0.74) < 1e-9, "at 1413 0.46 0.74")
        clearMap()
        ns = login()
        b = open(ns)
        eq(ns.SleepingBagMap.method(), nil, "no map API")
        ok(b._shown == false, "no button")
        local r, why = ns.SleepingBag.showMap()
        eq(r, false, "nothing"); eq(why, "none", "why")
    end)

    test("GF-008-B combat: the button is not lit and does nothing; lit again after combat", function()
        local ns = login(true)
        local b = open(ns)
        wow.enterCombat()
        eq(b._enabled, false, "not lit in combat")
        local r, why = ns.SleepingBag.showMap()
        eq(r, false, "nothing in combat"); eq(why, "combat", "why")
        wow.leaveCombat()
        eq(b._enabled, true, "lit again")
        clearMap()
    end)

    test("GF-008-B /gftk probe lists the map APIs and prints a map line", function()
        local ns = login({ waypoint = true })
        local P = ns.Probe
        local have = {}
        for _, a in ipairs(P.APIS) do have[a] = (have[a] or 0) + 1 end
        for _, a in ipairs({ "C_Map.SetUserWaypoint", "C_Map.GetBestMapForUnit", "WorldMapFrame.GetCanvas", "C_Map.GetMapInfo" }) do
            eq(have[a], 1, "probe checks " .. a)
        end
        local frames = {}
        for _, f in ipairs(P.FRAMES) do frames[f] = true end
        ok(frames.WorldMapFrame, "probe records WorldMapFrame")
        local line = ns.SleepingBagMap.probeLine()
        ok(line:find("畫布 有", 1, true) and line:find("路標 有", 1, true) and line:find("做法 畫布標記", 1, true), line)
        SlashCmdList.GREENFANGTOOLKIT("probe")
        ok(P.diagText():find("地圖：", 1, true), "the probe summary has the map line")
        -- The copy text lists what is missing: here the fake has no ClearUserWaypoint.
        ok(P.text():find("C_Map.ClearUserWaypoint", 1, true), "the copy text names a missing map API")
        clearMap()
    end)

    test("GF-008-B data: steps with x / y have a map; every step stays 待實地驗證", function()
        local ns = login()
        for _, st in ipairs(ns.SleepingBagRoutes.Horde.steps) do
            eq(st.verified, false, st.id .. " unverified")
            if st.x then ok(st.y and st.mapID, st.id .. " has y and a map") end
        end
    end)
end
