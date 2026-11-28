-- GF-008-D (owner: 「睡袋任務的地圖區域標記要有外框，用其他符號，且要可發光…
-- 地圖座標可以用不同的顏色…針對部落解法做，聯盟的是另一套版本」): framed,
-- glowing pins tinted by kind, a short Horde guide with sourced coordinates,
-- the route picked by its faction field. Fake world map and C_Map; the fake
-- AnimationGroup is added to frames here (the mock has none). Offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local NAMES = { [1413] = "貧瘠之地", [1434] = "荊棘谷", [1436] = "西部荒野", [1442] = "石爪山脈", [1432] = "洛克莫丹",
        [1417] = "阿拉希高地", [1424] = "希爾斯布萊德丘陵", [1414] = "卡林多", [1415] = "東部王國" }
    local groups
    local function fakeAnim(frame)
        local g = { frame = frame, playing = false, plays = 0, stops = 0, anims = {} }
        function g.CreateAnimation(self, kind)
            local a = { kind = kind }
            function a.SetFromAlpha(_, v) a.from = v end
            function a.SetToAlpha(_, v) a.to = v end
            function a.SetDuration(_, v) a.duration = v end
            self.anims[#self.anims + 1] = a
            return a
        end
        function g.SetLooping(self, v) self.looping = v end
        function g.Play(self) self.playing = true; self.plays = self.plays + 1 end
        function g.Stop(self) self.playing = false; self.stops = self.stops + 1 end
        function g.IsPlaying(self) return self.playing end
        groups[#groups + 1] = g
        return g
    end
    local function fakeMap()
        groups = {}
        local calls = { open = {} }
        local create = _G.CreateFrame
        _G.CreateFrame = function(...)
            local f = create(...)
            rawset(f, "CreateAnimationGroup", fakeAnim)
            return f
        end
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
    local function same(c, want) return c and math.abs(c[1] - want[1]) < 1e-9 and math.abs(c[2] - want[2]) < 1e-9 and math.abs(c[3] - want[3]) < 1e-9 end

    test("GF-008-D the pin: a round frame around the sleep icon, no star, no quest mark", function()
        local ns = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        eq(SB.showMap(), "canvas", "pinned")
        local pin = M.pin()
        eq(pin.icon._texture, "Interface\\Icons\\Spell_Nature_Sleep", "the symbol")
        eq(pin.border._texture, "Interface\\Minimap\\MiniMap-TrackingBorder", "its frame")
        eq(pin.border._w, 54, "the tracking layout")
        eq(pin.glow._texture, "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64", "the glow")
        eq(pin.glow._blend, "ADD", "additive")
        for _, list in ipairs({ M.ICONS, M.GLOWS }) do
            for _, f in ipairs(list) do
                for _, bad in ipairs({ "Quest", "Gossip", "Exclamation", "Question", "RaidTarget", "TurnIn" }) do
                    ok(not f:find(bad), f .. " is not " .. bad)
                end
            end
        end
        for _, b in ipairs(M.BORDERS) do ok(not b.file:find("RaidTarget") and not b.file:find("Quest"), b.file) end
        local src = assert(io.open(ADDON_DIR .. "/SleepingBagMap.lua", "rb")):read("*a")
        ok(not src:find("UI-RaidTargetingIcon", 1, true), "the star is gone")
    end)

    test("GF-008-D files missing on the client: the fallbacks", function()
        local ns = login({ missingFiles = {
            ["Interface\\Icons\\Spell_Nature_Sleep"] = true,
            ["Interface\\Minimap\\MiniMap-TrackingBorder"] = true,
            ["Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"] = true,
        } })
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        SB.showMap()
        local pin = M.pin()
        eq(pin.iconFile, "Interface\\Icons\\INV_Misc_Bag_10", "the bag icon")
        eq(pin.borderFile, "Interface\\Buttons\\UI-Quickslot2", "the square frame")
        eq(pin.border._w, 52, "its size")
        eq(pin.glowFile, "Interface\\Buttons\\UI-ActionButton-Border", "the button glow")
    end)

    test("GF-008-D the glow: an Alpha AnimationGroup (no OnUpdate) that stops when the map closes", function()
        local ns, _, wm = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        SB.showMap()
        local pin = M.pin()
        local g = pin.anim
        ok(g, "an animation group")
        eq(g.frame, pin.glowFrame, "on the glow only")
        eq(g.looping, "BOUNCE", "back and forth")
        eq(g.anims[1].kind, "Alpha", "alpha")
        ok(g.anims[1].from < g.anims[1].to and g.anims[1].duration > 0, "from dim to bright")
        ok(g.playing, "plays while shown")
        wm:Hide()
        ok(not pin._shown and not g.playing, "map closed: hidden and stopped")
        wm:Show()
        ok(pin._shown and g.playing, "map open: plays again")
        wm:SetMapID(1436)
        ok(not pin._shown and not g.playing, "another zone: stopped")
        wm:SetMapID(1413)
        ok(g.playing, "back")
        for _, f in ipairs({ "SleepingBag.lua", "SleepingBagMap.lua", "SleepingBagData.lua" }) do
            local src = assert(io.open(ADDON_DIR .. "/" .. f, "rb")):read("*a")
            ok(not src:find("OnUpdate", 1, true), f .. ": no OnUpdate")
            ok(not src:find("C_Timer", 1, true), f .. ": no timer")
        end
        local src = assert(io.open(ADDON_DIR .. "/SleepingBagMap.lua", "rb")):read("*a")
        local n = 0
        for _ in src:gmatch("RegisterEvent%(") do n = n + 1 end
        eq(n, 2, "only the two combat events (as before)")
    end)

    test("GF-008-D colours by kind, grey when approximate; the legend on the page", function()
        local ns, _, wm = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        eq(M.colorFor({ kind = "start", conf = "multi" }), M.KINDS.start.color, "start")
        eq(M.colorFor({ kind = "turnin", conf = "single" }), M.KINDS.turnin.color, "turn-in")
        eq(M.colorFor({ kind = "route", conf = "multi" }), M.KINDS.route.color, "route")
        eq(M.colorFor({ kind = "route", conf = "approx" }), M.APPROX.color, "approximate is grey")
        local seen = {}
        for _, s in pairs(M.KINDS) do ok(not seen[s.word], "distinct " .. s.word); seen[s.word] = true end
        ok(not seen[M.APPROX.word], "grey is its own")
        SB.showMap()
        ok(same(M.pin().border._vertex, M.KINDS.start.color), "step 1: green frame")
        ok(same(M.pin().glow._vertex, M.KINDS.start.color), "and glow")
        local text = SB.pageText()
        ok(text:find(M.LEGEND, 1, true), "the legend line")
        for _, w in ipairs({ "綠色：接任務", "金色：交任務", "藍色：路線點", "灰色：大約位置" }) do ok(M.LEGEND:find(w, 1, true), w) end
        -- GF-008-E: step 2 Westfall (gold) with Grom'gol (grey, approximate) on the jungle map.
        SB.complete()
        SB.showMap()
        ok(same(M.pin(1).border._vertex, M.KINDS.turnin.color), "step 2: the cart, gold")
        wm:SetMapID(1434)
        ok(same(M.pin(2).border._vertex, M.APPROX.color), "Grom'gol: grey")
        ok(SB.pageText():find("（大約：格羅姆高營地的飛艇塔）", 1, true), "and it says 大約")
        -- Step 3: the camp and the mound (gold), the path from Sun Rock (blue, one source).
        SB.complete()
        eq(SB.currentStep().id, "stonetalon", "step 3")
        SB.showMap()
        ok(M.pin(1)._shown and M.pin(2)._shown and M.pin(3)._shown, "three pins")
        ok(same(M.pin(1).border._vertex, M.KINDS.turnin.color), "the camp: gold")
        ok(same(M.pin(3).border._vertex, M.KINDS.route.color), "the path: blue")
        ok(SB.pageText():find("石爪山脈（40, 52）（多來源一致）", 1, true), "the camp's line")
        ok(SB.pageText():find("石爪山脈（50, 52）（單一來源）", 1, true), "the path's line")
        -- Step 4: one point; the other pins go (and stop).
        SB.complete()
        SB.showMap()
        ok(M.pin(1)._shown and not M.pin(2)._shown, "one pin")
        ok(not M.pin(2).anim.playing, "the other stopped")
        wm:Hide()
    end)

    test("GF-008-D the wall: the cart on Hillsbrad, the bags on the Arathi map", function()
        local ns, calls, wm = login()
        local SB, M = ns.SleepingBag, ns.SleepingBagMap
        for _ = 1, 4 do SB.complete() end
        eq(SB.currentStep().id, "thoradin-wall", "step 5 (GF-008-E)")
        eq(SB.showMap(), "canvas", "pinned")
        eq(calls.open[#calls.open], 1424, "opens on Hillsbrad")
        ok(M.pin(1)._shown and not M.pin(2)._shown, "the cart only")
        ok(same(M.pin(1).border._vertex, M.KINDS.route.color), "blue: a route point")
        wm:SetMapID(1417)
        ok(not M.pin(1)._shown and M.pin(2)._shown, "Arathi: the bags")
        ok(same(M.pin(2).border._vertex, M.KINDS.turnin.color), "gold")
    end)

    test("GF-008-D data: every step has points or says why; each point has kind, source and confidence", function()
        local ns = login()
        local route = ns.SleepingBagRoutes.Horde
        eq(route.faction, "Horde", "a faction field")
        eq(#route.steps, 5, "five steps (GF-008-E; old saved steps are moved over)")
        local count = { multi = 0, single = 0, approx = 0 }
        for i, st in ipairs(route.steps) do
            ok((st.points and #st.points > 0) or st.noPin, "step " .. i .. ": points, or why not")
            ok(st.action and st.tip, "step " .. i .. ": action, tip (GF-008-E: travel folded into action)")
            ok(not st.action:find("\n") and #st.action < 200, "step " .. i .. ": a short action")
            eq(st.verified, false, "step " .. i .. ": 待實地驗證")
            for _, p in ipairs(st.points or {}) do
                ok(ns.SleepingBagMap.KINDS[p.kind], st.id .. ": kind " .. tostring(p.kind))
                ok(count[p.conf], st.id .. ": confidence " .. tostring(p.conf))
                ok(type(p.src) == "string" and p.src ~= "", st.id .. ": source")
                ok(p.x > 0 and p.x < 100 and p.y > 0 and p.y < 100, st.id .. ": on the map")
                if p.conf == "approx" then ok(p.approx, st.id .. ": the landmark it sits on") end
                count[p.conf] = count[p.conf] + 1
            end
        end
        eq(count.multi .. "/" .. count.single .. "/" .. count.approx, "6/2/1", "多來源一致 / 單一來源 / 大約 (GF-008-E)")
    end)

    test("GF-008-D the route by its faction field; Alliance unchanged (no entry); a later Alliance route is data only", function()
        local ns = login()
        local SB = ns.SleepingBag
        eq(SB.route("Horde"), ns.SleepingBagRoutes.Horde, "Horde")
        eq(SB.route("Alliance"), nil, "no Alliance route yet")
        local alliance = wow.defaultPlayer()
        alliance.faction = "Alliance"
        wow.reset({ player = alliance })
        ns = wow.login(ADDON_DIR)
        eq(ns.SleepingBag.route(), nil, "Alliance: none")
        ok(not ns.Framework.get("sleepingbag").available(), "the entry stays hidden")
        -- Data only: a route table with faction = "Alliance" shows up.
        ns.SleepingBagRoutes.Test = { faction = "Alliance", title = "t", reward = "r", note = "", minLevel = 14, source = "",
            steps = { { id = "a", zone = "西部荒野", landmark = "l", action = "a", travel = "t", verified = false } } }
        eq(ns.SleepingBag.route(), ns.SleepingBagRoutes.Test, "found by faction")
        ok(ns.Framework.get("sleepingbag").available(), "the entry appears")
        ns.SleepingBagRoutes.Test = nil
    end)
end
