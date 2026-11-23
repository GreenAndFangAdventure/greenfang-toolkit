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
-- GF-002-E (owner: 「請調整大一點」): wider and taller, so the names fit on the rows.
F.PANEL_WIDTH, F.PANEL_HEIGHT = 1100, 640

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
    ns.makeOpaque(f) -- GF-001-D20: never see-through
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    ns.escRegister(f, ns.ESC_LEVEL.window) -- GF-002-E: ESC closes the windows above it first
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
        -- GF-001-D19: the name only; how to move or reset it is common
        -- minimap-button behaviour, and sync status is in 「同步與診斷」.
        GameTooltip:AddLine("綠皮冒險工具箱")
        -- GF-002-B (R-8.2): adventure and order numbers on two lines.
        for _, fn in ipairs(F.tooltipLines or {}) do pcall(fn, GameTooltip) end
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

---------------------------------------------------------------------------
-- Small filter widgets (GF-001-D19): plain frames and buttons only, so they
-- work without UIDropDownMenu or the newer menu system.
---------------------------------------------------------------------------

local openMenu

local function closeMenu()
    if openMenu then openMenu:Hide() end
    openMenu = nil
end
F.closeMenu = closeMenu

-- A button that shows the chosen option; a click opens a list below it.
-- options() returns { { value = v, text = "..." }, ... }; the first one is
-- "all" (value nil). onChoose(value) is called after a pick. options() is
-- only called when the list opens (it may walk the whole roster); the
-- button text comes from that list, or label(value) when given.
function ns.choiceButton(parent, w, x, y, options, onChoose, allText, label)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.options, b.value = options, nil
    local menu = CreateFrame("Frame", nil, b)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    if menu.SetFrameLevel then menu:SetFrameLevel(100) end
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    ns.makeOpaque(menu, 0)
    menu:EnableMouse(true)
    menu:Hide()
    menu.items = {}
    b.menu = menu
    ns.escRegister(menu, ns.ESC_LEVEL.menu)
    function b.textFor(value)
        if value == nil and allText then return allText end
        for _, o in ipairs(b.lastOptions or {}) do
            if o.value == value then return o.text end
        end
        if label then
            local text = label(value)
            if text then return text end
        end
        local list = b.options()
        for _, o in ipairs(list) do
            if o.value == value then return o.text end
        end
        return list[1].text
    end
    function b.choose(value)
        b.value = value
        b:SetText(b.textFor(value) .. " ▼")
        closeMenu()
        onChoose(value)
    end
    function b.refreshText() b:SetText(b.textFor(b.value) .. " ▼") end
    b:SetScript("OnClick", function()
        if menu:IsShown() then closeMenu(); return end
        closeMenu()
        local list = b.options()
        b.lastOptions = list
        for i, o in ipairs(list) do
            local item = menu.items[i]
            if not item then
                item = CreateFrame("Button", nil, menu)
                item:SetSize(w + 20, 22)
                item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 22)
                pcall(item.SetNormalFontObject, item, "GameFontHighlight")
                item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                menu.items[i] = item
            end
            item:SetText(o.text)
            local value = o.value
            item:SetScript("OnClick", function() b.choose(value) end)
            item:Show()
        end
        for i = #list + 1, #menu.items do menu.items[i]:Hide() end
        menu:SetSize(w + 28, #list * 22 + 8)
        menu:Show()
        openMenu = menu
    end)
    b:HookScript("OnHide", function() if openMenu == menu then closeMenu() end end)
    b.refreshText()
    return b
end

-- A check box with a label on its right; onChange(checked).
function ns.checkBox(parent, text, x, y, onChange)
    local c = ns.createFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c.label = ns.freeText(parent:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    c.label:SetPoint("LEFT", c, "RIGHT", 0, 0)
    c.label:SetText(text)
    c.checked = false
    function c.set(on)
        c.checked = on and true or false
        if c.SetChecked then c:SetChecked(c.checked) end
    end
    c:SetScript("OnClick", function()
        c.set(not c.checked)
        onChange(c.checked)
    end)
    return c
end

-- A small menu at the cursor (GF-001-D20: right-click on a recipe).
-- items = { { text = "...", fn = function() end }, ... }. Opaque, above the
-- toolkit window; a pick or Esc closes it.
F.MENU_NAME = "GreenFangToolkit_Menu"
local popup

function ns.showMenu(owner, items)
    closeMenu()
    if type(items) ~= "table" or #items == 0 then return nil end
    if not popup then
        popup = CreateFrame("Frame", F.MENU_NAME, UIParent)
        -- GF-002-D: above every window (a toplevel window raised over level 100 hid half of it).
        popup:SetFrameStrata("TOOLTIP")
        if popup.SetFrameLevel then popup:SetFrameLevel(100) end
        if popup.SetClampedToScreen then popup:SetClampedToScreen(true) end
        ns.makeOpaque(popup, 0)
        popup:EnableMouse(true)
        popup.items = {}
        ns.escRegister(popup, ns.ESC_LEVEL.menu)
    end
    -- GF-002-E: the larger font; as wide as the longest item.
    local w = 180
    for _, item in ipairs(items) do w = math.max(w, ns.labelWidth(item.text) + 24) end
    for i, item in ipairs(items) do
        local b = popup.items[i]
        if not b then
            b = CreateFrame("Button", nil, popup)
            b:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (i - 1) * 22)
            pcall(b.SetNormalFontObject, b, "GameFontHighlight")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            popup.items[i] = b
        end
        b:SetSize(w - 8, 22)
        b:SetText(item.text)
        local fn = item.fn
        b:SetScript("OnClick", function() closeMenu(); fn() end)
        b:Show()
    end
    for i = #items + 1, #popup.items do popup.items[i]:Hide() end
    popup:SetSize(w, #items * 22 + 8)
    popup:ClearAllPoints()
    local x, y = nil, nil
    if type(GetCursorPosition) == "function" then
        local cx, cy = GetCursorPosition()
        local scale = ns.num((UIParent:GetEffectiveScale())) or 1
        if ns.num(cx) and ns.num(cy) and scale > 0 then x, y = cx / scale, cy / scale end
    end
    if x and y then
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        popup:SetPoint("TOPLEFT", owner or UIParent, "BOTTOMLEFT", 0, 0)
    end
    popup.owner = owner
    popup:Show()
    openMenu = popup
    return popup
end

-- A button with a list of check boxes (GF-001-D22: the recipe page's 專業 and
-- 會做的人). options() returns { { value, text, icon? } }; 全選 and 全不選
-- come first. b.selected is a set { [value] = true }, or nil = everything.
-- summary(selected, options) gives the button text; onChange() after a click.
F.CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

function ns.multiChoiceButton(parent, w, x, y, options, onChange, summary)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.options, b.selected = options, nil
    local menu = CreateFrame("Frame", nil, b)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    if menu.SetFrameLevel then menu:SetFrameLevel(100) end
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    ns.makeOpaque(menu, 0)
    menu:EnableMouse(true)
    menu:Hide()
    menu.items = {}
    b.menu = menu
    ns.escRegister(menu, ns.ESC_LEVEL.menu)
    local ROW, WIDTH = 22, math.max(w + 40, 190)

    function b.isOn(value) return b.selected == nil or b.selected[value] == true end
    function b.count()
        local n = 0
        for _, o in ipairs(b.options()) do if b.isOn(o.value) then n = n + 1 end end
        return n
    end
    function b.refreshText() b:SetText(summary(b) .. " ▼") end
    local function changed()
        -- Everything ticked is the same as "everything" (nil), so options
        -- added later (a new profession) are included.
        if b.selected and b.count() == #b.options() then b.selected = nil end
        b.refreshText()
        if menu:IsShown() then b.drawItems() end
        onChange()
    end
    function b.selectAll() b.selected = nil; changed() end
    function b.selectNone() b.selected = {}; changed() end
    function b.toggle(value)
        if b.selected == nil then
            b.selected = {}
            for _, o in ipairs(b.options()) do b.selected[o.value] = true end
        end
        b.selected[value] = (not b.selected[value]) or nil
        changed()
    end
    function b.setOnly(value) b.selected = { [value] = true }; changed() end

    local function item(i)
        local it = menu.items[i]
        if it then return it end
        it = CreateFrame("Button", nil, menu)
        it:SetSize(WIDTH - 8, ROW)
        it:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * ROW)
        it:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        it.check = it:CreateTexture(nil, "ARTWORK")
        it.check:SetSize(16, 16)
        it.check:SetPoint("LEFT", it, "LEFT", 2, 0)
        it.icon = it:CreateTexture(nil, "ARTWORK")
        it.icon:SetSize(16, 16)
        it.icon:SetPoint("LEFT", it, "LEFT", 22, 0)
        it.label = it:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        it.label:SetJustifyH("LEFT")
        menu.items[i] = it
        return it
    end

    function b.drawItems()
        local list = b.options()
        local entries = { { text = "全選", fn = b.selectAll }, { text = "全不選", fn = b.selectNone } }
        for _, o in ipairs(list) do
            local value = o.value
            entries[#entries + 1] = { text = o.text, icon = o.icon, on = b.isOn(value), fn = function() b.toggle(value) end }
        end
        for i, e in ipairs(entries) do
            local it = item(i)
            it.value = list[i - 2] and list[i - 2].value or nil
            it.label:SetText(e.text)
            it.label:ClearAllPoints()
            local hasIcon = e.icon and ns.Icons.set(it.icon, e.icon)
            if hasIcon then it.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); it.icon:Show() else it.icon:Hide() end
            it.label:SetPoint("LEFT", it, "LEFT", hasIcon and 42 or (e.on ~= nil and 22 or 6), 0)
            if e.on and ns.Icons.set(it.check, F.CHECK_TEXTURE) then it.check:Show() else it.check:Hide() end
            it.isOption = e.on ~= nil
            it.checked = e.on == true
            it:SetScript("OnClick", e.fn) -- the list stays open: tick several
            it:Show()
        end
        for i = #entries + 1, #menu.items do menu.items[i]:Hide() end
        menu:SetSize(WIDTH, #entries * ROW + 8)
    end

    b:SetScript("OnClick", function()
        if menu:IsShown() then closeMenu(); return end
        closeMenu()
        b.drawItems()
        menu:Show()
        openMenu = menu
    end)
    b:HookScript("OnHide", function() if openMenu == menu then closeMenu() end end)
    b.refreshText()
    return b
end
