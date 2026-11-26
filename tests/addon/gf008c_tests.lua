-- GF-008-C (owner, 0.16.5 in Forever: 「睡袋的每一步都應該要有地圖處，不要用
-- 驚嘆號或問號，會與實際任務搞混，換個標誌」): every step opens a map (a step
-- without x / y opens it without a pin and says why), and the pin is the raid
-- target star, not a quest mark. Fake world map and C_Map; offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local NAMES = { [1413] = "貧瘠之地", [1434] = "荊棘谷", [1436] = "西部荒野", [1442] = "石爪山脈", [1432] = "洛克莫丹",
        [1417] = "阿拉希高地", [1414] = "卡林多", [1415] = "東部王國" }
    local function fakeMap()
        local calls = { open = {} }
        local wm = CreateFrame("Frame", "WorldMapFrame", UIParent)
        wm:Hide()
        local canvas = CreateFrame("Frame", nil, wm)
        wm.GetCanvas = function() return canvas end
        wm.SetMapID = function(self, id) self.mapID = id end
        wm.GetMapID = function(self) return self.mapID end
        _G.WorldMapFrame = wm
        _G.OpenWorldMap = function(id) calls.open[#calls.open + 1] = id; wm:Show(); wm:SetMapID(id) end
        _G.hooksecurefunc = function(t, name, post)
            local orig = t[name]
            t[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
        end
        _G.C_Map = {
            GetMapInfo = function(id) return NAMES[id] and { mapID = id, name = NAMES[id] } or nil end,
            GetMapChildrenInfo = function() return {} end,
        }
        return calls, wm, canvas
    end
    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.SleepingBagMap.resetSession()
        ns.SleepingBagMap.current = nil
        local calls, wm, canvas = fakeMap()
        ns.Framework.open("sleepingbag")
        ns.SleepingBag.refresh()
        return ns, calls, wm, canvas
    end

    test("GF-008-C every step has a map; the one the owner can check", function()
        local ns = login()
        local M = ns.SleepingBagMap
        local want = { 1413, 1434, 1436, 1414, 1442, 1442, 1415, 1432, 1417 }
        for i, st in ipairs(ns.SleepingBagRoutes.Horde.steps) do
            eq(M.mapFor(st), want[i], "step " .. i .. " " .. st.id .. ": its map")
            ok(M.canShow(st), "step " .. i .. ": 看地圖")
            ok((st.x and st.y) or st.noPin, "step " .. i .. ": a pin, or why not")
            eq(st.verified, false, "step " .. i .. ": 待實地驗證")
        end
    end)

    test("GF-008-C a step without x / y: its map opens without a pin, and the page says why", function()
        local ns, calls, wm = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        eq(SB.showMap(), "canvas", "step 1 pinned")
        local pin = M.pin()
        ok(pin._shown, "the pin")
        SB.complete(); SB.complete(); SB.complete() -- step 4: back to Kalimdor
        local step = SB.currentStep()
        eq(step.id, "to-kalimdor", "step 4")
        ok(SB.mapButton._shown ~= false, "看地圖 shown")
        wm:Hide() -- closed since step 1: 看地圖 opens it again
        eq(SB.showMap(), "map", "the map only")
        eq(calls.open[#calls.open], 1414, "opened on 卡林多")
        eq(wm:GetMapID(), 1414, "the map shows it")
        ok(not pin._shown, "no pin")
        eq(M.current, nil, "nothing pinned")
        ok(SB.pageText():find("卡林多（地圖不標位置：" .. step.noPin .. "）", 1, true), "the reason on the page")
        -- Step 7 (to Loch Modan): Eastern Kingdoms, no pin.
        SB.complete(); SB.complete(); SB.complete()
        eq(SB.currentStep().id, "to-loch-modan", "step 7")
        eq(SB.showMap(), "map", "the map only")
        eq(wm:GetMapID(), 1415, "東部王國")
    end)

    test("GF-008-C approximate pins say so: 格羅姆高營地, 烈日石居, the wall on the Arathi map", function()
        local ns, _, wm = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        SB.complete() -- step 2
        eq(SB.showMap(), "canvas", "pinned")
        ok(SB.pageText():find("荊棘谷（32, 29）（大約：格羅姆高營地的飛艇塔）", 1, true), "the page says approximate")
        local pin = M.pin()
        GameTooltip._lines = nil
        local said = {}
        local add = GameTooltip.AddLine
        GameTooltip.AddLine = function(self, t, ...) said[#said + 1] = t; return add(self, t, ...) end
        pin._scripts.OnEnter(pin)
        GameTooltip.AddLine = add
        local found = false
        for _, t in ipairs(said) do if tostring(t):find("大約：格羅姆高營地", 1, true) then found = true end end
        ok(found, "the tooltip says approximate")
        for _ = 1, 7 do SB.complete() end
        eq(SB.currentStep().id, "thoradin-wall", "the last step")
        eq(SB.showMap(), "canvas", "pinned")
        eq(wm:GetMapID(), 1417, "on 阿拉希高地")
        ok(SB.pageText():find("阿拉希高地（20, 30）（大約：索拉丁之牆北段）", 1, true), "the wall's text")
    end)

    test("GF-008-C the pin is the raid target star (no quest ! or ?); the star sheet when the file is missing", function()
        local ns = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        for _, bad in ipairs({ "Quest", "Gossip", "Exclamation", "Question", "TurnIn" }) do
            ok(not M.PIN_TEXTURE:find(bad), "not a quest mark: " .. bad)
            ok(not M.PIN_SHEET.file:find(bad), "sheet not a quest mark: " .. bad)
        end
        eq(M.PIN_TEXTURE, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", "the star")
        SB.showMap()
        eq(M.pin().icon._texture, M.PIN_TEXTURE, "drawn with it")
        -- A client without the single file: the same star from the sheet.
        ns = login({ missingFiles = { ["Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"] = true } })
        SB, M = ns.SleepingBag, ns.SleepingBagMap
        SB.showMap()
        eq(M.pin().icon._texture, M.PIN_SHEET.file, "the sheet")
        eq(table.concat(M.pin().icon._texCoord or {}, ","), "0,0.25,0,0.25", "its star")
        local src = assert(io.open(ADDON_DIR .. "/SleepingBagMap.lua", "rb")):read("*a")
        ok(not src:find("AvailableQuestIcon", 1, true) and not src:find("ActiveQuestIcon", 1, true), "no quest icon left")
    end)
end
