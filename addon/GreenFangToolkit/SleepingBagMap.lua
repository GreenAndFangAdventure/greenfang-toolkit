-- SleepingBagMap (GF-008-B, owner 2026-11-26: 「能否給地圖然後有標記位置呢?」):
-- 看地圖 on the sleeping-bag page opens Blizzard's world map on the step's
-- zone and draws one pin there (docs/research/GF-008-B_map.md).
--
--   canvas    (chosen) a small frame on WorldMapFrame:GetCanvas() at x / y,
--             shown only while the map shows that zone. Blizzard's own art
--             (GF-008-D: a framed, glowing sleep icon tinted by kind; no quest mark, no star), nothing
--             bundled, no library.
--   waypoint  (fallback, only when there is no canvas) C_Map.SetUserWaypoint
--             with UiMapPoint, then the map. It replaces the player's own
--             waypoint, so it is never used when the canvas works.
--   none      no 看地圖 button at all.
--
-- The zone comes from the step's mapID (classic uiMapIDs) checked against
-- C_Map.GetMapInfo's name; when the name differs, the zones under the world
-- map are searched by name (zhTW or English). GF-008-C: every step has a map;
-- a step without x / y (a long journey, a continent) opens its map without a
-- pin, and the page says why. Every position is 待實地驗證. Nothing is saved
-- or sent.
-- GF-008-D: a step may have several points (start / turn-in / route), each
-- tinted by kind (grey when approximate), and a point may sit on another map.

local _, ns = ...
local str = ns.str

local M = {}
ns.SleepingBagMap = M

M.WORLD_MAP_ID = 947           -- Azeroth (classic)
M.CONTINENTS = { 1414, 1415 }  -- Kalimdor, Eastern Kingdoms (classic)
M.ZONE_TYPE = 3                -- Enum.UIMapType.Zone
M.CONTINENT_TYPE = 2           -- Enum.UIMapType.Continent

-- The map APIs /gftk probe records (added to its list below).
M.APIS = {
    "C_Map.SetUserWaypoint", "C_Map.ClearUserWaypoint", "C_Map.HasUserWaypoint", "C_Map.GetBestMapForUnit",
    "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo", "C_Map.GetPlayerMapPosition", "C_Map.GetMapArtLayerTextures",
    "UiMapPoint.CreateFromCoordinates", "C_SuperTrack.SetSuperTrackedUserWaypoint",
    "WorldMapFrame.GetCanvas", "WorldMapFrame.SetMapID", "WorldMapFrame.GetMapID", "WorldMapFrame.AddDataProvider",
    "OpenWorldMap", "ToggleWorldMap", "ShowUIPanel", "hooksecurefunc",
}

local function fn(t, k) return type(t) == "table" and type(t[k]) == "function" end
local function call(f, ...)
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
    return nil
end

---------------------------------------------------------------------------
-- What this client offers
---------------------------------------------------------------------------

function M.support()
    local wm = rawget(_G, "WorldMapFrame")
    local cm = rawget(_G, "C_Map")
    local up = rawget(_G, "UiMapPoint")
    return {
        canvas = fn(wm, "GetCanvas") and fn(wm, "SetMapID") and fn(wm, "GetMapID")
            and (type(rawget(_G, "OpenWorldMap")) == "function" or type(rawget(_G, "ToggleWorldMap")) == "function"
                or type(rawget(_G, "ShowUIPanel")) == "function"),
        waypoint = fn(cm, "SetUserWaypoint") and fn(up, "CreateFromCoordinates"),
        info = fn(cm, "GetMapInfo"),
        children = fn(cm, "GetMapChildrenInfo"),
        best = fn(cm, "GetBestMapForUnit"),
    }
end

-- "canvas" / "waypoint" / nil
function M.method()
    local s = M.support()
    if s.canvas then return "canvas" end
    if s.waypoint then return "waypoint" end
    return nil
end

-- One line for /gftk probe and the diagnostics: 地圖：畫布 有｜路標 有｜…
function M.probeLine()
    local s = M.support()
    local function yn(v) return v and "有" or "無" end
    return string.format("地圖：畫布 %s｜路標 %s｜地圖資訊 %s｜所在地圖 %s｜做法 %s",
        yn(s.canvas), yn(s.waypoint), yn(s.info), yn(s.best),
        ({ canvas = "畫布標記", waypoint = "路標" })[M.method() or ""] or "沒有")
end

---------------------------------------------------------------------------
-- The step's zone
---------------------------------------------------------------------------

local function nameOf(id)
    local cm = rawget(_G, "C_Map")
    if not fn(cm, "GetMapInfo") then return nil end
    local info = call(cm.GetMapInfo, id)
    return type(info) == "table" and info.name or nil
end
local function sameZone(name, step)
    name = str(name)
    if name == "" then return false end
    if step.mapZone then return name == step.mapZone or name == step.mapZoneEN end -- GF-008-C
    return name == step.zone or name == step.zoneEN
end

local found = {} -- zone name -> mapID (searched once a session)
function M.mapFor(step)
    if not (step and step.zone) then return nil end
    local cm = rawget(_G, "C_Map")
    if type(cm) ~= "table" then return step.mapID end -- nothing to check with (the waypoint needs C_Map anyway)
    if step.mapID and (not fn(cm, "GetMapInfo") or sameZone(nameOf(step.mapID), step)) then return step.mapID end
    if found[step.zone] ~= nil then return found[step.zone] or nil end
    local hit = false
    if fn(cm, "GetMapChildrenInfo") then
        local roots = { M.WORLD_MAP_ID }
        for _, c in ipairs(M.CONTINENTS) do roots[#roots + 1] = c end
        for _, root in ipairs(roots) do
            -- GF-008-C: a continent step looks among the continents.
            local kind = (step.mapZone and step.noPin) and M.CONTINENT_TYPE or M.ZONE_TYPE
            local list = call(cm.GetMapChildrenInfo, root, kind, true)
            for _, info in ipairs(type(list) == "table" and list or {}) do
                if type(info) == "table" and sameZone(info.name, step) then hit = info.mapID; break end
            end
            if hit then break end
        end
    end
    found[step.zone] = hit
    return hit or nil
end
function M.resetSession() found = {} end

-- GF-008-C: every step has a map; GF-008-D: the pins are the step's points.
function M.points(step) return (step and type(step.points) == "table") and step.points or {} end
function M.hasPin(step) return step ~= nil and #M.points(step) > 0 end
function M.canOpen()
    return type(rawget(_G, "OpenWorldMap")) == "function" or type(rawget(_G, "ToggleWorldMap")) == "function"
end
function M.canShow(step)
    if not (step and M.mapFor(step) ~= nil) then return false end
    local how = M.method()
    if how == "canvas" then return true end
    -- A waypoint needs a point; a step without one still opens its map when the client can.
    if how == "waypoint" then return M.hasPin(step) or M.canOpen() end
    return false
end

-- A point on another map than the step's (the wall's bags on the Arathi map).
function M.pointMap(step, p)
    if not p.mapID or p.mapID == step.mapID then return M.mapFor(step) end
    return M.mapFor({ zone = p.zone or step.zone, zoneEN = p.zoneEN, mapID = p.mapID })
end

---------------------------------------------------------------------------
-- GF-008-D colours (owner: 「地圖座標可以用不同的顏色」): by kind, grey for an
-- approximate point. The page also says it in words (大約, 單一來源).
---------------------------------------------------------------------------

M.KINDS = {
    start = { name = "接任務", color = { 0.30, 1.00, 0.30 }, word = "綠色" },
    turnin = { name = "交任務並接下一個", color = { 1.00, 0.82, 0.00 }, word = "金色" },
    route = { name = "路線點", color = { 0.35, 0.70, 1.00 }, word = "藍色" },
}
M.APPROX = { name = "大約位置", color = { 0.75, 0.75, 0.75 }, word = "灰色" }
M.CONF = { multi = "多來源一致", single = "單一來源", approx = "大約" }
M.LEGEND = "標記顏色｜綠色：接任務｜金色：交任務並接下一個｜藍色：路線點（推車、飛艇塔、飛行點）｜灰色：大約位置"

function M.styleFor(p)
    if p.conf == "approx" then return M.APPROX end
    return M.KINDS[p.kind] or M.KINDS.turnin
end
function M.colorFor(p) return M.styleFor(p).color end

---------------------------------------------------------------------------
-- The pins on the world map canvas
--
-- GF-008-D (owner: 「要有外框，用其他符號，且要可發光」): a round frame (the
-- minimap tracking border, tinted by kind) around the sleep spell icon, with
-- a soft additive glow behind it that pulses with an AnimationGroup (Alpha,
-- BOUNCE). No per-frame script: the animation runs only while the pin is shown and
-- is stopped when the pin hides (the world map closes, another zone, another
-- step). Every file is game art, checked at run time with a fallback.
---------------------------------------------------------------------------

M.PIN_SIZE = 32
M.ICONS = { "Interface\\Icons\\Spell_Nature_Sleep", "Interface\\Icons\\INV_Misc_Bag_10" }
M.BORDERS = {
    -- The tracking button layout: 54 x 54 from the top left of a 32 frame.
    { file = "Interface\\Minimap\\MiniMap-TrackingBorder", size = 54, anchor = "TOPLEFT" },
    -- A square action-slot frame around the icon.
    { file = "Interface\\Buttons\\UI-Quickslot2", size = 52, anchor = "CENTER" },
}
M.GLOWS = { "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64", "Interface\\Buttons\\UI-ActionButton-Border" }
M.GLOW_SIZE = 64
M.GLOW_ALPHA = { 0.25, 0.95 }
M.GLOW_SECONDS = 0.8
M.PIN_TEXTURE = M.ICONS[1] -- (older name)

-- The first file of the list this client has (SetTexture returns false for a missing file).
local function setFirst(tex, list)
    for _, f in ipairs(list) do
        local path = type(f) == "table" and f.file or f
        if tex:SetTexture(path) ~= false then return f end
    end
    return nil
end
M.setFirst = setFirst

local pins = {}
M.current = nil -- { mapID, step, index, list = { { mapID, x, y, point }, ... } }

local function hidePin(p)
    if p.anim and p.anim.Stop then p.anim:Stop() end
    p:Hide()
end
local function hideAll() for _, p in ipairs(pins) do hidePin(p) end end

local function tooltip(self)
    local cur, at = M.current, self.at
    if not (cur and at and GameTooltip) then return end
    local p, style = at.point, M.styleFor(at.point)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("睡袋 第 " .. cur.index .. " 步", 1, 0.82, 0)
    GameTooltip:AddLine(str(p.label or cur.step.landmark), 1, 1, 1)
    GameTooltip:AddLine(string.format("%s（%.1f, %.1f）", style.name, p.x, p.y), unpack(style.color))
    if p.conf == "approx" then GameTooltip:AddLine("大約：" .. str(p.approx or p.label), 1, 1, 1)
    else GameTooltip:AddLine("座標：" .. (M.CONF[p.conf] or "單一來源"), 1, 1, 1) end
    GameTooltip:AddLine("待實地驗證", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function newPin(canvas, i)
    local p = CreateFrame("Frame", "GreenFangToolkit_SleepingBagPin" .. (i > 1 and i or ""), canvas)
    p:SetSize(M.PIN_SIZE, M.PIN_SIZE)
    if p.SetFrameStrata then p:SetFrameStrata("HIGH") end
    -- The glow: its own frame, so that only it pulses.
    p.glowFrame = CreateFrame("Frame", nil, p)
    p.glowFrame:SetSize(M.GLOW_SIZE, M.GLOW_SIZE)
    p.glowFrame:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.glow = p.glowFrame:CreateTexture(nil, "BACKGROUND")
    p.glow:SetAllPoints(p.glowFrame)
    p.glowFile = setFirst(p.glow, M.GLOWS)
    p.glow:SetBlendMode("ADD")
    if p.glowFrame.CreateAnimationGroup then
        local ag = p.glowFrame:CreateAnimationGroup()
        if ag then
            local a = ag:CreateAnimation("Alpha")
            if a then
                if a.SetFromAlpha then a:SetFromAlpha(M.GLOW_ALPHA[1]); a:SetToAlpha(M.GLOW_ALPHA[2]) end
                a:SetDuration(M.GLOW_SECONDS)
            end
            ag:SetLooping("BOUNCE")
            p.anim = ag
        end
    end
    -- The symbol and its round frame.
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(20, 20)
    p.icon:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.iconFile = setFirst(p.icon, M.ICONS)
    p.border = p:CreateTexture(nil, "OVERLAY")
    local b = setFirst(p.border, M.BORDERS)
    p.borderFile = b and b.file
    if b then
        p.border:SetSize(b.size, b.size)
        if b.anchor == "TOPLEFT" then p.border:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        else p.border:SetPoint("CENTER", p, "CENTER", 0, 0) end
    end
    p:EnableMouse(true)
    p:SetScript("OnEnter", tooltip)
    p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- Hidden (map closed, parent hidden): the animation stops with it.
    p:SetScript("OnHide", function(self) if self.anim and self.anim.Stop then self.anim:Stop() end end)
    p:Hide()
    return p
end

local function placePins()
    local wm = rawget(_G, "WorldMapFrame")
    local cur = M.current
    if not (wm and cur) then hideAll(); return end
    local shown = call(wm.GetMapID, wm)
    local canvas = call(wm.GetCanvas, wm)
    local open = wm.IsShown and wm:IsShown()
    local w = canvas and (ns.num((canvas:GetWidth())) or 0) or 0
    local h = canvas and (ns.num((canvas:GetHeight())) or 0) or 0
    for i, p in ipairs(pins) do
        local at = cur.list[i]
        if at and open and at.mapID == shown and w > 0 and h > 0 then
            local c = M.colorFor(at.point)
            p.at = at
            p.border:SetVertexColor(c[1], c[2], c[3])
            p.glow:SetVertexColor(c[1], c[2], c[3])
            p:ClearAllPoints()
            p.px, p.py = at.x / 100 * w, -at.y / 100 * h
            p:SetPoint("CENTER", canvas, "TOPLEFT", p.px, p.py)
            p:Show()
            if p.anim and not (p.anim.IsPlaying and p.anim:IsPlaying()) then p.anim:Play() end
        else
            hidePin(p)
        end
    end
end
M.placePin = placePins
M.placePins = placePins

local hooked = false
local function makePins(n)
    local wm = rawget(_G, "WorldMapFrame")
    local canvas = wm and call(wm.GetCanvas, wm)
    if not canvas then return nil end
    for i = #pins + 1, n do pins[i] = newPin(canvas, i) end
    if not hooked then
        hooked = true
        if wm.HookScript then
            wm:HookScript("OnShow", placePins)
            wm:HookScript("OnHide", hideAll)
        end
        -- The map changes zone (the player clicks around): the pins follow.
        if type(hooksecurefunc) == "function" then
            if type(wm.OnMapChanged) == "function" then pcall(hooksecurefunc, wm, "OnMapChanged", placePins) end
            pcall(hooksecurefunc, wm, "SetMapID", placePins)
        end
    end
    return pins
end
function M.pin(i) return pins[i or 1] end
function M.pins() return pins end

local function resolve(step, index)
    local list = {}
    for _, p in ipairs(M.points(step)) do
        local id = M.pointMap(step, p)
        if id then list[#list + 1] = { mapID = id, x = p.x, y = p.y, point = p } end
    end
    return { mapID = M.mapFor(step), step = step, index = index or 1, list = list }
end

-- GF-008-E: our waypoint (only the waypoint fallback sets one): the first
-- point on the step's own map; cleared when the guide no longer has a step.
local function firstOwn(cur)
    for _, at in ipairs(cur.list) do if at.mapID == cur.mapID then return at end end
    return cur.list[1]
end
local function setWaypoint(cur)
    local at = firstOwn(cur)
    if not at then return false end
    local point = call(UiMapPoint.CreateFromCoordinates, at.mapID, at.x / 100, at.y / 100)
    if not point then return false end
    call(C_Map.SetUserWaypoint, point)
    if type(rawget(_G, "C_SuperTrack")) == "table" and fn(C_SuperTrack, "SetSuperTrackedUserWaypoint") then
        call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return at
end
local function clearWaypoint()
    local cm = rawget(_G, "C_Map")
    if fn(cm, "ClearUserWaypoint") then call(cm.ClearUserWaypoint) end
end
M.clearWaypoint = clearWaypoint

-- The page's step changed: the pins (and our waypoint) move with it, or go.
-- GF-008-E: nothing of the old step stays; nothing is drawn before 看地圖 was
-- pressed once (M.current is nil until then).
function M.update(step, index)
    local old = M.current
    if old and (old.step ~= step or old.index ~= index) then
        if step and M.hasPin(step) and M.canShow(step) then
            M.current = resolve(step, index)
            if #pins > 0 then makePins(#M.current.list) end
            if old.waypoint then M.current.waypoint = setWaypoint(M.current) and true or nil end
        else
            M.current = nil
            if old.waypoint then clearWaypoint() end
        end
    end
    placePins()
end

local function openMap(mapID)
    local wm = rawget(_G, "WorldMapFrame")
    if not (wm and wm.IsShown and wm:IsShown()) then
        if type(rawget(_G, "OpenWorldMap")) == "function" then
            call(OpenWorldMap, mapID)
        elseif type(rawget(_G, "ToggleWorldMap")) == "function" then
            call(ToggleWorldMap)
        elseif type(rawget(_G, "ShowUIPanel")) == "function" then
            call(ShowUIPanel, wm)
        end
    end
    if wm and fn(wm, "SetMapID") then call(wm.SetMapID, wm, mapID) end
end

-- 看地圖: returns "canvas" / "waypoint" / "map" (no pin), or false and why ("combat", "none").
function M.show(step, index)
    if ns.inCombat() then return false, "combat" end
    if not M.canShow(step) then return false, "none" end
    local mapID = M.mapFor(step)
    local how = M.method()
    -- GF-008-C: no points: the map only, no pin.
    if not M.hasPin(step) then
        M.current = nil
        placePins()
        openMap(mapID)
        return "map"
    end
    local cur = resolve(step, index)
    if how == "canvas" then
        M.current = cur
        makePins(#cur.list)
        openMap(mapID)
        placePins()
        return "canvas"
    end
    -- The waypoint: the first point on the step's own map.
    local first = setWaypoint(cur)
    if not first then return false, "none" end
    cur.waypoint = true
    M.current = cur
    openMap(first.mapID)
    return "waypoint"
end

---------------------------------------------------------------------------
-- /gftk probe: the map APIs go into its list; combat relights the button
---------------------------------------------------------------------------

if ns.Probe and type(ns.Probe.APIS) == "table" then
    local have = {}
    for _, a in ipairs(ns.Probe.APIS) do have[a] = true end
    for _, a in ipairs(M.APIS) do if not have[a] then ns.Probe.APIS[#ns.Probe.APIS + 1] = a end end
    if type(ns.Probe.FRAMES) == "table" then ns.Probe.FRAMES[#ns.Probe.FRAMES + 1] = "WorldMapFrame" end
    -- The summary /gftk probe prints gets the map line too.
    local diag = ns.Probe.diagText
    if type(diag) == "function" then
        ns.Probe.diagText = function(...) return str(diag(...)) .. "｜" .. M.probeLine() end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if ns.SleepingBag and ns.SleepingBag.refresh then ns.SleepingBag.refresh() end
end)
