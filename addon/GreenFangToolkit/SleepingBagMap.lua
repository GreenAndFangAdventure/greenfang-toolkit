-- SleepingBagMap (GF-008-B, owner 2026-11-26: 「能否給地圖然後有標記位置呢?」):
-- 看地圖 on the sleeping-bag page opens Blizzard's world map on the step's
-- zone and draws one pin there (docs/research/GF-008-B_map.md).
--
--   canvas    (chosen) a small frame on WorldMapFrame:GetCanvas() at x / y,
--             shown only while the map shows that zone. Blizzard's own art
--             (the quest "!" icon), nothing bundled, no library.
--   waypoint  (fallback, only when there is no canvas) C_Map.SetUserWaypoint
--             with UiMapPoint, then the map. It replaces the player's own
--             waypoint, so it is never used when the canvas works.
--   none      no 看地圖 button at all.
--
-- The zone comes from the step's mapID (classic uiMapIDs) checked against
-- C_Map.GetMapInfo's name; when the name differs, the zones under the world
-- map are searched by name (zhTW or English). Steps without x / y get no pin
-- and no button. Every position is 待實地驗證. Nothing is saved or sent.

local _, ns = ...
local str = ns.str

local M = {}
ns.SleepingBagMap = M

M.WORLD_MAP_ID = 947           -- Azeroth (classic)
M.CONTINENTS = { 1414, 1415 }  -- Kalimdor, Eastern Kingdoms (classic)
M.ZONE_TYPE = 3                -- Enum.UIMapType.Zone
M.PIN_SIZE = 32
M.PIN_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"

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
    return name ~= "" and (name == step.zone or name == step.zoneEN)
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
            local list = call(cm.GetMapChildrenInfo, root, M.ZONE_TYPE, true)
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

function M.canShow(step)
    return step ~= nil and step.x ~= nil and step.y ~= nil and M.method() ~= nil and M.mapFor(step) ~= nil
end

---------------------------------------------------------------------------
-- The pin on the world map canvas
---------------------------------------------------------------------------

local pin
M.current = nil -- { mapID, x, y, step, index } of the pin

local function placePin()
    local wm = rawget(_G, "WorldMapFrame")
    local cur = M.current
    if not (pin and wm and cur) then if pin then pin:Hide() end return end
    local shown = call(wm.GetMapID, wm)
    if shown ~= cur.mapID or not (wm.IsShown and wm:IsShown()) then pin:Hide(); return end
    local canvas = call(wm.GetCanvas, wm)
    if not canvas then pin:Hide(); return end
    local w, h = ns.num((canvas:GetWidth())) or 0, ns.num((canvas:GetHeight())) or 0
    if w <= 0 or h <= 0 then pin:Hide(); return end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", cur.x / 100 * w, -cur.y / 100 * h)
    pin.px, pin.py = cur.x / 100 * w, -cur.y / 100 * h
    pin:Show()
end
M.placePin = placePin

local hooked = false
local function makePin()
    local wm = rawget(_G, "WorldMapFrame")
    local canvas = wm and call(wm.GetCanvas, wm)
    if not canvas then return nil end
    if not pin then
        pin = CreateFrame("Frame", "GreenFangToolkit_SleepingBagPin", canvas)
        pin:SetSize(M.PIN_SIZE, M.PIN_SIZE)
        if pin.SetFrameStrata then pin:SetFrameStrata("HIGH") end
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints(pin)
        pin.icon:SetTexture(M.PIN_TEXTURE)
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            local cur = M.current
            if not (cur and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("睡袋 第 " .. cur.index .. " 步", 1, 0.82, 0)
            GameTooltip:AddLine(str(cur.step.landmark), 1, 1, 1)
            GameTooltip:AddLine("待實地驗證", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        pin:Hide()
    end
    if not hooked then
        hooked = true
        if wm.HookScript then
            wm:HookScript("OnShow", placePin)
            wm:HookScript("OnHide", function() if pin then pin:Hide() end end)
        end
        -- The map changes zone (the player clicks around): the pin follows.
        if type(hooksecurefunc) == "function" then
            if type(wm.OnMapChanged) == "function" then pcall(hooksecurefunc, wm, "OnMapChanged", placePin) end
            pcall(hooksecurefunc, wm, "SetMapID", placePin)
        end
    end
    return pin
end
function M.pin() return pin end

-- The page's step changed: the pin moves with it (or goes).
-- (The pin only exists after 看地圖; on another step it moves there, or goes.)
function M.update(step, index)
    if M.current and M.current.step ~= step then
        M.current = (step and M.canShow(step))
            and { mapID = M.mapFor(step), x = step.x, y = step.y, step = step, index = index or 1 } or nil
    end
    placePin()
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

-- 看地圖: returns "canvas" / "waypoint", or false and why ("combat", "none").
function M.show(step, index)
    if ns.inCombat() then return false, "combat" end
    if not M.canShow(step) then return false, "none" end
    local mapID = M.mapFor(step)
    local how = M.method()
    M.current = { mapID = mapID, x = step.x, y = step.y, step = step, index = index or 1 }
    if how == "canvas" then
        makePin()
        openMap(mapID)
        placePin()
        return "canvas"
    end
    local point = call(UiMapPoint.CreateFromCoordinates, mapID, step.x / 100, step.y / 100)
    if not point then return false, "none" end
    call(C_Map.SetUserWaypoint, point)
    if type(rawget(_G, "C_SuperTrack")) == "table" and fn(C_SuperTrack, "SetSuperTrackedUserWaypoint") then
        call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    openMap(mapID)
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
