-- Framework (GF-000-A): module registry, the single unified window (module list
-- on the left, module content on the right) and the single minimap entry.
--
-- A module is a table passed to ns.Framework.register:
--   id        unique string ("roster", "sleepingbag", ...)
--   title     shown in the module list and the window title
--   order     sort order in the list (smaller first)
--   available optional function() -> boolean; false hides the entry
--             (not released yet, no permission, wrong faction, ...)
--   create    function(panel) builds the module's widgets into panel, once
--   show      optional function(panel) called every time the module is shown
--   hide      optional function(panel)
-- Module settings live in GreenFangToolkitDB.settings.modules[id] (GF Sync ignores
-- settings). Per-character state lives in .characters[<GUID>] inside that table.

local _, ns = ...

---------------------------------------------------------------------------
-- Combat state (GF-001-D8). InCombatLockdown() is still false while
-- PLAYER_REGEN_DISABLED runs, so that event sets this flag first.
-- GF-001-D9 (D-012): the 「同步到網站」 button and its /reload dialog are
-- gone; uploading happens only after logout.
---------------------------------------------------------------------------

ns.combatFlag = false

-- PLAYER_REGEN_DISABLED: last moment before the lockdown. Hide every
-- protected frame of ours so none can be clicked (or changed) in combat.
function ns.onCombatStart()
    ns.combatFlag = true
    if ns.Professions then ns.Professions.hideAll() end
end

function ns.onCombatEnd()
    ns.combatFlag = false
end

local str = ns.str

local F = {}
ns.Framework = F

F.WINDOW_NAME = "GreenFangToolkit_MainWindow"
F.NAV_WIDTH = 160
F.PANEL_WIDTH, F.PANEL_HEIGHT = 1000, 610

local modules, byId = {}, {}
local window, navButtons, panels, currentId = nil, {}, {}, nil
local minimapButton

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

function F.register(def)
    assert(type(def) == "table" and type(def.id) == "string", "module needs an id")
    if byId[def.id] then return byId[def.id] end
    def.order = def.order or 100
    def.title = def.title or def.id
    byId[def.id] = def
    modules[#modules + 1] = def
    table.sort(modules, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return def
end

function F.get(id) return byId[id] end

local function isAvailable(def)
    if type(def.available) ~= "function" then return true end
    local ok, result = pcall(def.available)
    return ok and result == true
end

-- Modules the current character may see, in list order.
function F.availableModules()
    local list = {}
    for _, def in ipairs(modules) do
        if isAvailable(def) then list[#list + 1] = def end
    end
    return list
end

---------------------------------------------------------------------------
-- Settings helpers
---------------------------------------------------------------------------

function F.moduleSettings(id)
    local settings = ns.settings()
    if type(settings.modules) ~= "table" then settings.modules = {} end
    if type(settings.modules[id]) ~= "table" then settings.modules[id] = {} end
    return settings.modules[id]
end

-- Stable key for the logged-in character: its GUID, else Name-Realm.
function F.charKey()
    local p = ns.Data.player()
    if p.guid then return p.guid end
    if p.name ~= "" then return p.name .. "-" .. p.realm end
    return nil
end

function F.charState(id)
    local key = F.charKey()
    if not key then return {} end
    local ms = F.moduleSettings(id)
    if type(ms.characters) ~= "table" then ms.characters = {} end
    if type(ms.characters[key]) ~= "table" then ms.characters[key] = {} end
    return ms.characters[key]
end

---------------------------------------------------------------------------
-- Unified window
---------------------------------------------------------------------------

local function createWindow()
    if window then return window end
    local f = ns.createFrame("Frame", F.WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(F.NAV_WIDTH + F.PANEL_WIDTH + 10, F.PANEL_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if UISpecialFrames then table.insert(UISpecialFrames, F.WINDOW_NAME) end
    local nav = CreateFrame("Frame", nil, f)
    nav:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
    nav:SetSize(F.NAV_WIDTH - 14, F.PANEL_HEIGHT - 44)
    local bg = nav:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.37, 0.30, 0.25)
    f.nav = nav
    f:Hide()
    window = f
    return f
end

local function setTitle(def)
    if window and window.TitleText then
        window.TitleText:SetText("綠皮冒險工具箱｜" .. (def and def.title or ""))
    end
end

local function panelFor(def)
    if panels[def.id] then return panels[def.id] end
    local p = CreateFrame("Frame", nil, window)
    p:SetPoint("TOPLEFT", window, "TOPLEFT", F.NAV_WIDTH, 0)
    p:SetSize(F.PANEL_WIDTH, F.PANEL_HEIGHT)
    p:Hide()
    panels[def.id] = p
    if type(def.create) == "function" then
        local ok, err = pcall(def.create, p)
        if not ok then ns.say("模組「" .. def.title .. "」載入失敗：" .. tostring(err)) end
    end
    return p
end

-- Rebuild the module list: availability can change (joining a guild, level...).
local function rebuildNav()
    for _, b in ipairs(navButtons) do b:Hide() end
    local list = F.availableModules()
    for i, def in ipairs(list) do
        local b = navButtons[i]
        if not b then
            b = ns.createFrame("Button", nil, window.nav, "UIPanelButtonTemplate")
            b:SetSize(F.NAV_WIDTH - 24, 26)
            b:SetPoint("TOPLEFT", window.nav, "TOPLEFT", 5, -6 - (i - 1) * 30)
            navButtons[i] = b
        end
        b:SetText(def.title)
        b:SetScript("OnClick", function() F.select(def.id) end)
        if b.SetEnabled then b:SetEnabled(def.id ~= currentId) end
        b.moduleId = def.id
        b:Show()
    end
    return list
end

-- Show module id (or the remembered/first available one) inside the window.
function F.select(id)
    createWindow()
    local def = id and byId[id]
    if not (def and isAvailable(def)) then
        local remembered = byId[str(ns.settings().lastModule)]
        if remembered and isAvailable(remembered) then
            def = remembered
        else
            def = F.availableModules()[1]
        end
    end
    if currentId and panels[currentId] and (not def or currentId ~= def.id) then
        local old = byId[currentId]
        panels[currentId]:Hide()
        if old and type(old.hide) == "function" then pcall(old.hide, panels[currentId]) end
    end
    if not def then currentId = nil; rebuildNav(); setTitle(nil); return nil end
    currentId = def.id
    ns.settings().lastModule = def.id
    local p = panelFor(def)
    p:Show()
    setTitle(def)
    rebuildNav()
    if type(def.show) == "function" then
        local ok, err = pcall(def.show, p)
        if not ok then ns.say("模組「" .. def.title .. "」顯示失敗：" .. tostring(err)) end
    end
    return def
end

function F.open(id)
    local def = F.select(id)
    window:Show()
    return def
end

function F.toggle(id)
    if window and window:IsShown() and (id == nil or id == currentId) then
        window:Hide()
        return nil
    end
    return F.open(id)
end

function F.isShown() return window ~= nil and window:IsShown() end
function F.current() return currentId end
function F.isModuleShown(id) return F.isShown() and currentId == id end
function F.panel(id) return panels[id] end
function F.navButtons() return navButtons end

---------------------------------------------------------------------------
-- Minimap button: the single entry point, sitting on the minimap rim.
-- Layout follows the common minimap-button convention (the same sizes and
-- anchors LibDBIcon uses, without depending on that library):
--   button 31x31; MiniMap-TrackingBorder 53x53 anchored TOPLEFT (the round
--   part of that texture covers the button's top-left 31x31 area); background
--   and icon anchored TOPLEFT so they sit centred in that round part.
---------------------------------------------------------------------------

F.MINIMAP_BUTTON_SIZE = 31
F.MINIMAP_RIM_OFFSET = 10      -- button centre this far outside the minimap edge
F.MINIMAP_BORDER = { texture = "Interface\\Minimap\\MiniMap-TrackingBorder", size = 53, x = 0, y = 0 }
F.MINIMAP_BACKGROUND = { texture = "Interface\\Minimap\\UI-Minimap-Background", size = 20, x = 7, y = -5 }
F.MINIMAP_ICON_LAYOUT = { size = 17, x = 7, y = -6 }
F.MINIMAP_ICON = "Interface\\Icons\\INV_Misc_Bag_10"          -- 冒險背包 (owner's choice)
F.MINIMAP_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Bag_08"

-- Radius from the minimap centre to the button centre: on the rim, not
-- floating outside it. Uses the real minimap size (16001 may differ from 140).
function F.minimapOrbitRadius()
    local diameter = 0
    if Minimap and Minimap.GetWidth and Minimap.GetHeight then
        diameter = math.max(ns.num((ns.call(Minimap.GetWidth, Minimap))) or 0,
            ns.num((ns.call(Minimap.GetHeight, Minimap))) or 0)
    end
    if diameter < 80 then diameter = 140 end
    return diameter / 2 + F.MINIMAP_RIM_OFFSET
end
local minimapOrbitRadius = F.minimapOrbitRadius

-- The chosen icon, or the fallback when the client does not have that file.
-- GetFileIDFromPath (Mainline) returns nil for a missing file; without it we
-- cannot tell, so the chosen icon is used and the fallback is applied only if
-- SetTexture reports failure.
function F.minimapIconPath()
    if type(GetFileIDFromPath) == "function" then
        local ok, id = pcall(GetFileIDFromPath, F.MINIMAP_ICON)
        if ok and id == nil then return F.MINIMAP_ICON_FALLBACK end
    end
    return F.MINIMAP_ICON
end

local function placeTexture(tex, spec, b)
    tex:SetSize(spec.size, spec.size)
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", spec.x, spec.y)
end

local function minimapPosition()
    if not minimapButton or not Minimap then return end
    local angle = tonumber(ns.settings().minimapAngle) or ns.DEFAULT_MINIMAP_ANGLE
    minimapButton:ClearAllPoints()
    local radius = minimapOrbitRadius()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(math.rad(angle)) * radius, math.sin(math.rad(angle)) * radius)
end

function F.resetMinimap()
    ns.settings().minimapAngle = ns.DEFAULT_MINIMAP_ANGLE
    minimapPosition()
end

local atan2 = math.atan2 or math.atan
local function moveMinimapButton()
    if not (Minimap and minimapButton and GetCursorPosition) then return end
    local mx, my = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and my and cursorX and cursorY and scale and scale > 0) then return end
    ns.settings().minimapAngle = math.deg(atan2(cursorY / scale - my, cursorX / scale - mx))
    minimapPosition()
end

function F.createMinimapButton()
    if minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "GreenFangToolkit_MinimapButton", Minimap)
    b:SetSize(F.MINIMAP_BUTTON_SIZE, F.MINIMAP_BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(F.MINIMAP_BACKGROUND.texture)
    placeTexture(background, F.MINIMAP_BACKGROUND, b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    local path = F.minimapIconPath()
    if icon:SetTexture(path) == false and path ~= F.MINIMAP_ICON_FALLBACK then
        path = F.MINIMAP_ICON_FALLBACK
        icon:SetTexture(path)
    end
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- trim the square icon frame
    placeTexture(icon, F.MINIMAP_ICON_LAYOUT, b)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture(F.MINIMAP_BORDER.texture)
    placeTexture(border, F.MINIMAP_BORDER, b)
    b.icon, b.border, b.background, b.iconPath = icon, border, background, path
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(self, mouseButton)
        if self.didDrag then self.didDrag = false; return end
        if mouseButton == "RightButton" then
            F.resetMinimap()
            ns.say("小地圖按鈕位置已重置。")
        else
            F.toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self.didDrag = true
        self:SetScript("OnUpdate", moveMinimapButton)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        moveMinimapButton()
        ns.after(0.15, function() self.didDrag = false end)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("綠皮冒險工具箱")
        GameTooltip:AddLine("點擊：開啟工具箱", 1, 1, 1)
        GameTooltip:AddLine("拖曳：沿小地圖外圈調整位置", 0.7, 0.9, 0.7)
        GameTooltip:AddLine("右鍵：恢復預設位置", 0.7, 0.9, 0.7)
        local c = ns.Sync.statusColor()
        GameTooltip:AddLine(ns.Sync.shortStatus(), c[1], c[2], c[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton = b
    F.minimapButton = b
    -- Keep an open tooltip current when sync or the outbox changes.
    ns.Sync.onChange(function()
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == b then
            GameTooltip:ClearLines()
            b:GetScript("OnEnter")(b)
        end
    end)
    minimapPosition()
    if Minimap.HookScript then
        Minimap:HookScript("OnSizeChanged", minimapPosition)
    end
end
