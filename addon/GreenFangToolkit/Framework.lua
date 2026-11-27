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
-- GF-UI-E (spec v2.0 §3), optional, so every older register() still works:
--   entry     which main entry the page belongs to: "profile" 職工檔案,
--             "directory" 職工名冊, "crafting" 委託業務, "logistics" 物資調度,
--             "adventure" 冒險業務, "handbook" 冒險指南, or "settings" 事務設定
--             (the bottom button). Left out: F.DEFAULT_ENTRY[id]; a page with
--             neither gets an entry of its own after the six (named def.short or
--             def.title), so nothing that registered before disappears.
--   subTitle  the page's name on the sub-tab row (2-4 characters); else
--             F.NAMES.page[id], def.short, def.title.
--   subOrder  order among the pages of one entry (smaller first); else order.
-- An entry with no available page is hidden. The pages of one entry switch on
-- the sub-tab row at the top of the content area. All names: F.NAMES.
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
F.PANEL_WIDTH, F.PANEL_HEIGHT = 1100, 680 -- GF-002-F: 36 px rows
-- GF-UI-E: the sub-tab row above every page. The page keeps its own 680 px
-- (it is moved down, not squeezed); the window grows by this much.
F.SUBTAB_H = 40
F.SUBTAB_Y = -35 -- the row's buttons, from the window's top (under the title line)

local modules, byId = {}, {}
local window, navButtons, panels, currentId = nil, {}, {}, nil
local subTabs = {}
local lastPage = {} -- entry -> the page last open there (this session only; lastModule is saved)
local minimapButton

---------------------------------------------------------------------------
-- GF-UI-E: the six entries (spec v2.0 §3), their names and icons. Every name
-- shown in the navigation is in F.NAMES (also ns.NAMES), so a new name is one
-- line here. Other files may add their page names (F.NAMES.page[id] = "...").
---------------------------------------------------------------------------

F.ENTRIES = { "profile", "directory", "crafting", "logistics", "adventure", "handbook" }
F.SETTINGS_ENTRY = "settings"
F.NAMES = {
    entry = {
        profile = "職工檔案", directory = "職工名冊", crafting = "委託業務",
        logistics = "物資調度", adventure = "冒險業務", handbook = "冒險指南",
        settings = "事務設定",
    },
    -- Sub-tab names of the pages there are today (spec §3 建議子頁).
    page = {
        character = "角色資料", roster = "在籍職工", recipes = "工匠配方", orders = "製作委託",
        adventure = "業務大廳", sleepingbag = "睡袋指南", supply = "綠皮調貨所", -- GF-UI-K: the owner's name, now only on the tab (the title says 物資調度)
    },
    settingsTip = "同步與診斷",
}
ns.NAMES = F.NAMES

-- Pages that registered without an entry, by id (the ones of today, and the
-- ids the first-wave sessions use: GF-010 profile, GF-009 supply, GF-012 bank).
F.DEFAULT_ENTRY = {
    character = "profile", profile = "profile",
    roster = "directory",
    recipes = "crafting", orders = "crafting",
    supply = "logistics", bank = "logistics",
    adventure = "adventure",
    sleepingbag = "handbook",
}

-- The game's own icons, each with fallbacks (MANUAL §3uie).
F.ENTRY_ICON = {
    -- GF-UI-J (owner, 0.16.2): the game's own orc head (a Horde guild), then the human head.
    profile = { "Interface\\Icons\\INV_Misc_Head_Orc_01", "Interface\\Icons\\INV_Misc_Head_Human_01",
        "Interface\\Icons\\INV_Misc_Note_01" },
    -- GF-UI-F: a group of people; GF-UI-J (owner): the Horde battle standard first,
    -- then the group-finder heads, then the guild tabard; never a book (冒險指南 is the book).
    directory = { "Interface\\Icons\\INV_BannerPVP_01", "Interface\\Icons\\INV_Misc_GroupLooking", "Interface\\Icons\\INV_Shirt_GuildTabard_01",
        "Interface\\Icons\\INV_Misc_Note_02" },
    crafting = { "Interface\\Icons\\Trade_BlackSmithing", "Interface\\Icons\\INV_Hammer_20" },
    logistics = { "Interface\\Icons\\INV_Box_01", "Interface\\Icons\\INV_Misc_Bag_08" },
    adventure = { "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Sword_04" },
    handbook = { "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Misc_Book_09" },
    settings = { "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\Trade_Engineering" },
    page = { "Interface\\Icons\\INV_Misc_Note_01" }, -- an entry of its own (no entry given)
}
F.NAV_ICON = 22 -- GF-UI-G: 22 px in the module list (22-24)

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

-- GF-UI-E: the entry a page belongs to (see the top of this file).
local function knownEntry(key)
    return type(key) == "string" and F.NAMES.entry[key] ~= nil
end
function F.entryOf(def)
    if not def then return nil end
    if knownEntry(def.entry) then return def.entry end
    local d = F.DEFAULT_ENTRY[def.id]
    if knownEntry(d) then return d end
    return "page:" .. def.id
end

function F.entryName(key)
    if F.NAMES.entry[key] then return F.NAMES.entry[key] end
    local id = type(key) == "string" and key:match("^page:(.+)$")
    local def = id and byId[id]
    if def then return def.short or F.SHORT_TITLE[def.id] or def.title end
    return tostring(key or "")
end

function F.pageTitle(def)
    if not def then return "" end
    return def.subTitle or F.NAMES.page[def.id] or def.short or def.title
end

local function subOrder(def) return def.subOrder or def.order end

-- The available pages of one entry, in sub-tab order.
function F.pagesOf(key)
    local list = {}
    for _, def in ipairs(F.availableModules()) do
        if F.entryOf(def) == key then list[#list + 1] = def end
    end
    table.sort(list, function(a, b)
        if subOrder(a) ~= subOrder(b) then return subOrder(a) < subOrder(b) end
        return a.id < b.id
    end)
    return list
end

-- The entries to show, in order: { key, name, pages }. The six first (only
-- those with a page), then pages with an entry of their own (by order).
-- 事務設定 is not in this list (it sits at the bottom, F.settingsPages()).
function F.entries()
    local out, seen = {}, {}
    for _, key in ipairs(F.ENTRIES) do
        local pages = F.pagesOf(key)
        if #pages > 0 then out[#out + 1] = { key = key, name = F.entryName(key), pages = pages } end
        seen[key] = true
    end
    seen[F.SETTINGS_ENTRY] = true
    for _, def in ipairs(F.availableModules()) do
        local key = F.entryOf(def)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { key = key, name = F.entryName(key), pages = F.pagesOf(key) }
        end
    end
    return out
end
function F.settingsPages() return F.pagesOf(F.SETTINGS_ENTRY) end

-- The page an entry opens: the one last open there, else its first.
function F.entryPage(key)
    local pages = F.pagesOf(key)
    local last = lastPage[key]
    for _, def in ipairs(pages) do
        if def.id == last then return def end
    end
    return pages[1]
end
function F.currentEntry() return currentId and F.entryOf(byId[currentId]) or nil end

---------------------------------------------------------------------------
-- Settings helpers
---------------------------------------------------------------------------

function F.moduleSettings(id)
    local settings = ns.settings()
    if type(settings.modules) ~= "table" then settings.modules = {} end
    if type(settings.modules[id]) ~= "table" then settings.modules[id] = {} end
    return settings.modules[id]
end

-- Stable key for the logged-in character: its GUID, or nil (nothing is
-- stored then). GF-FIX-B (review low-11, savedvariables §5): never a name.
function F.charKey()
    local g = ns.selfGUID and ns.selfGUID()
    if type(g) == "string" and g:match("^Player%-") then return g end
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
    -- GF-UI-D: the theme's window (dark panel, 1 px line, gold title, the X).
    local f = ns.Theme.window(F.WINDOW_NAME, UIParent, F.NAV_WIDTH + F.PANEL_WIDTH + 10, F.PANEL_HEIGHT + F.SUBTAB_H)
    if ns.Theme.C.main then ns.Theme.color(f.gfOpaque, ns.Theme.C.main) end -- GF-UI-G: the main window, more opaque
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    ns.escRegister(f, ns.ESC_LEVEL.window) -- GF-002-E: ESC closes the windows above it first
    local nav = CreateFrame("Frame", nil, f)
    nav:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
    nav:SetSize(F.NAV_WIDTH - 14, F.PANEL_HEIGHT + F.SUBTAB_H - 44)
    -- GF-UI-D: the module list is a faint panel with a line on its right.
    nav.bg = ns.Theme.fill(nav, ns.Theme.C.side or ns.Theme.C.panel, "BACKGROUND") -- GF-UI-G / GF-UI-J: #292724
    nav.line = ns.Theme.vline(nav, 0, 0, 0, nil, true)
    f.nav = nav
    -- GF-UI-E: the sub-tab row over the page, with a thin line under it.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", F.NAV_WIDTH, F.SUBTAB_Y)
    bar:SetSize(F.PANEL_WIDTH, ns.BUTTON_H + 2)
    bar.line = ns.Theme.hline(f, F.SUBTAB_Y - ns.BUTTON_H - 4, F.NAV_WIDTH + 20, 20)
    f.subBar = bar
    -- GF-FIX-B (owner: 4:3): the window fits the screen (Theme.fit, when it
    -- opens); a new resolution or UI scale fits it, and the open windows, again.
    f.gfFitMain = true
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end
        ns.Theme.refit()
        if ns.Theme.fitPending then self:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end)
    f:Hide()
    window = f
    return f
end

-- GF-UI-B (GF-UI-A §2.1 item 3, §2.2 item 3): two-character names in the
-- module list; the window title keeps the full name, or what the module
-- puts there (def.windowTitle(), e.g. the roster's guild name).
F.SHORT_TITLE = { roster = "名冊", recipes = "配方", orders = "訂單", adventure = "冒險",
    sleepingbag = "睡袋", character = "角色" }
function F.shortTitle(def)
    return def and (F.SHORT_TITLE[def.id] or def.short or def.title) or ""
end
-- GF-UI-K (spec v2.0 §3): 「綠皮冒險工具箱｜<主入口名>」 on every page (the
-- sub-tab names the page); what a module adds (def.windowTitle(), the roster's
-- guild name) follows after one more ｜.
function F.windowTitle(def)
    if not def then return "綠皮冒險工具箱" end
    local text = F.entryName(F.entryOf(def))
    if type(def.windowTitle) == "function" then
        local ok, t = pcall(def.windowTitle)
        if ok and type(t) == "string" and t ~= "" then text = text .. "｜" .. t end
    end
    return "綠皮冒險工具箱｜" .. text
end
local function setTitle(def)
    if window and window.TitleText then window.TitleText:SetText(F.windowTitle(def)) end
end
F.refreshTitle = function() if currentId then setTitle(byId[currentId]) end end

local function panelFor(def)
    if panels[def.id] then return panels[def.id] end
    local p = CreateFrame("Frame", nil, window)
    p:SetPoint("TOPLEFT", window, "TOPLEFT", F.NAV_WIDTH, -F.SUBTAB_H) -- GF-UI-E: under the sub-tab row
    p:SetSize(F.PANEL_WIDTH, F.PANEL_HEIGHT)
    p:Hide()
    panels[def.id] = p
    if type(def.create) == "function" then
        local ok, err = pcall(def.create, p)
        if not ok then ns.say("模組「" .. def.title .. "」載入失敗：" .. tostring(err)) end
    end
    return p
end

-- GF-UI-E: an entry button: the game's icon (20 px) and the 4-character name.
local function setNavIcon(b, key)
    local list = F.ENTRY_ICON[key] or F.ENTRY_ICON.page
    local shown = nil
    for _, path in ipairs(list) do
        if ns.Icons.set(b.icon, path) then shown = path; break end
    end
    if shown then
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:Show()
    else
        b.icon:Hide()
    end
    b.iconPath = shown
end

local function navButton(parent)
    -- GF-UI-B: 30 px, the toolkit's 16 px font (GF-UI-A §1.3). GF-UI-D: an
    -- outlined theme button; the open entry is the chosen one (gold).
    local b = ns.Theme.button(parent, nil, F.NAV_WIDTH - 24, ns.BUTTON_H)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(F.NAV_ICON, F.NAV_ICON)
    b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
    ns.leftText(b, 8 + F.NAV_ICON + 8)
    return b
end

-- The bottom button: 事務設定. Its pages when a module registered entry =
-- "settings"; until then it opens the 同步與診斷 window (Diag.lua).
local function settingsButton()
    if window.settingsButton then return window.settingsButton end
    local b = navButton(window.nav)
    b:SetPoint("BOTTOMLEFT", window.nav, "BOTTOMLEFT", 5, 8)
    b.entryKey = F.SETTINGS_ENTRY
    b:SetText(F.NAMES.entry.settings)
    setNavIcon(b, F.SETTINGS_ENTRY)
    b:SetScript("OnClick", function()
        local def = F.entryPage(F.SETTINGS_ENTRY)
        if def then F.select(def.id)
        elseif ns.Diag then ns.Diag.toggle() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(F.NAMES.settingsTip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    window.settingsButton = b
    return b
end

-- The sub-tab row: one tab per page of the open entry; the open page is the
-- chosen one (gold) and cannot be pressed (it does not light up either).
local function rebuildSubTabs(key)
    for _, b in ipairs(subTabs) do b:Hide() end
    local pages = key and F.pagesOf(key) or {}
    -- GF-FIX-B (owner, after GF-UI-K): an entry with one page shows its one
    -- tab too, like the others (more pages will come under these entries).
    local x = 20
    for i, def in ipairs(pages) do
        local b = subTabs[i]
        if not b then
            b = ns.Theme.button(window.subBar, nil, 100, ns.BUTTON_H)
            subTabs[i] = b
        end
        local text = F.pageTitle(def)
        b:SetText(text)
        local w = math.max(96, ns.labelWidth(text) + 28)
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", window.subBar, "TOPLEFT", x, 0)
        x = x + w + 8
        b.moduleId = def.id
        local id = def.id
        b:SetScript("OnClick", function() F.select(id) end)
        if b.SetEnabled then b:SetEnabled(def.id ~= currentId) end
        ns.Theme.setSelected(b, def.id == currentId)
        b:Show()
    end
    return pages
end

-- Rebuild the entry list: availability can change (joining a guild, level...).
local function rebuildNav()
    for _, b in ipairs(navButtons) do b:Hide() end
    local list = F.entries()
    local open = F.currentEntry()
    for i, e in ipairs(list) do
        local b = navButtons[i]
        if not b then
            b = navButton(window.nav)
            b:SetPoint("TOPLEFT", window.nav, "TOPLEFT", 5, -6 - (i - 1) * (ns.BUTTON_H + 6))
            navButtons[i] = b
        end
        local chosen = e.key == open
        local def = chosen and byId[currentId] or F.entryPage(e.key)
        b:SetText(e.name)
        setNavIcon(b, e.key:find("^page:") and "page" or e.key)
        local id = def and def.id
        b:SetScript("OnClick", function() F.select(id) end)
        if b.SetEnabled then b:SetEnabled(not chosen) end
        ns.Theme.setSelected(b, chosen)
        b.entryKey = e.key
        b.moduleId = id -- the page this entry opens (the open one when chosen)
        b:Show()
    end
    local s = settingsButton()
    ns.Theme.setSelected(s, open == F.SETTINGS_ENTRY)
    rebuildSubTabs(open)
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
    lastPage[F.entryOf(def)] = def.id -- GF-UI-E: the entry reopens this page
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
function F.subTabButtons() return subTabs end -- GF-UI-E: the sub-tab row (pooled; check IsShown)
function F.settingsButton() return window and window.settingsButton or nil end

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
-- GF-UI-C (owner: the toolkit covered the profession window). Choice (a):
-- while the game's profession window (TradeSkillFrame / CraftFrame) is open
-- the toolkit window and its popups step aside, and come back when it
-- closes. (b) docking beside it does not fit: the toolkit is ~1290 px wide
-- and the profession window ~350, more than a 1920 px screen at scale 1;
-- (c) a lower strata would still cover it whenever both are on the same
-- part of the screen, and the toolkit's popups would fall under the game's
-- windows too. Only frames that were shown are brought back; if the player
-- opens the toolkit again meanwhile, nothing is restored twice.
---------------------------------------------------------------------------

F.PROFESSION_EVENTS = { TRADE_SKILL_SHOW = "show", TRADE_SKILL_CLOSE = "close", CRAFT_SHOW = "show", CRAFT_CLOSE = "close" }
local stepAside -- the frames hidden for the profession window, or nil
local professionOpen = {}

function F.professionShown(kind)
    professionOpen[kind or "trade"] = true
    if stepAside then return stepAside end
    local hidden = {}
    if window and window:IsShown() then hidden[#hidden + 1] = window end
    for _, f in ipairs(ns.exclusivePopups and ns.exclusivePopups() or {}) do
        if f:IsShown() then hidden[#hidden + 1] = f end
    end
    if ns.Diag and ns.Diag.window and ns.Diag.window() and ns.Diag.window():IsShown() then hidden[#hidden + 1] = ns.Diag.window() end
    if #hidden == 0 then return nil end
    if ns.closeMenus then ns.closeMenus() end
    for _, f in ipairs(hidden) do f:Hide() end
    stepAside = hidden
    return hidden
end

function F.professionClosed(kind)
    professionOpen[kind or "trade"] = nil
    if next(professionOpen) then return nil end -- the other one is still open
    local list = stepAside
    stepAside = nil
    if not list then return nil end
    -- The window first, then the popups above it.
    for _, f in ipairs(list) do
        if not f:IsShown() then
            -- The window: shown again through select(), so the page redraws (it
            -- may have changed while hidden, e.g. recipes read from the window).
            if f == window and currentId then F.open(currentId) else f:Show() end
        end
    end
    return list
end
function F.steppedAside() return stepAside end

do
    local ev = CreateFrame("Frame")
    for name in pairs(F.PROFESSION_EVENTS) do pcall(ev.RegisterEvent, ev, name) end
    ev:SetScript("OnEvent", function(_, event)
        local kind = event:find("^CRAFT") and "craft" or "trade"
        if F.PROFESSION_EVENTS[event] == "show" then F.professionShown(kind) else F.professionClosed(kind) end
    end)
    F.professionEventFrame = ev
end

---------------------------------------------------------------------------
-- Small filter widgets (GF-001-D19): plain frames and buttons only, so they
-- work without UIDropDownMenu or the newer menu system.
---------------------------------------------------------------------------

local openMenu

-- GF-UI-B (GF-UI-A §1.4 item 4, §1.6): a drop-down button has the game's
-- drop-down arrow on its right (a texture, never a text arrow) and its
-- text on the left.
F.DROP_ARROW = 24
function ns.dropArrow(b)
    if b.arrow then return b.arrow end
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(F.DROP_ARROW, F.DROP_ARROW)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    ns.GameIcons.set(b.arrow, "dropdown")
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", 10, 0)
        fs:SetPoint("RIGHT", b, "RIGHT", -(F.DROP_ARROW + 6), 0)
        if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
        if fs.SetWordWrap then fs:SetWordWrap(false) end
    end
    return b.arrow
end

-- GF-UI-C (owner: 「選項沒對齊」): a list item's text starts at the same x on
-- every row (the game centres button text by default).
F.ITEM_TEXT_X = 8
function ns.leftText(b, x)
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", x or F.ITEM_TEXT_X, 0)
        if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    end
    b.gfTextX = x or F.ITEM_TEXT_X
end

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
    local b = ns.Theme.button(parent, nil, w, ns.BUTTON_H) -- GF-UI-D: outlined, the arrow on the right
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.options, b.value = options, nil
    local menu = CreateFrame("Frame", nil, b)
    menu:SetFrameStrata("TOOLTIP") -- GF-002-F: above the click-outside blocker
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
    ns.dropArrow(b)
    function b.choose(value)
        b.value = value
        b:SetText(b.textFor(value))
        closeMenu()
        onChoose(value)
    end
    function b.refreshText() b:SetText(b.textFor(b.value)) end
    b:SetScript("OnClick", function()
        if menu:IsShown() then closeMenu(); return end
        closeMenu()
        local list = b.options()
        b.lastOptions = list
        for i, o in ipairs(list) do
            local item = menu.items[i]
            if not item then
                item = CreateFrame("Button", nil, menu)
                item:SetSize(w + 20, 28)
                item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 28)
                pcall(item.SetNormalFontObject, item, ns.LABEL_FONT)
                item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                ns.Theme.guardHover(item)
                menu.items[i] = item
            end
            item:SetText(o.text)
            ns.leftText(item)
            local value = o.value
            item:SetScript("OnClick", function() b.choose(value) end)
            item:Show()
        end
        for i = #list + 1, #menu.items do menu.items[i]:Hide() end
        menu:SetSize(w + 28, #list * 28 + 8)
        menu:Show()
        openMenu = menu
    end)
    b:HookScript("OnHide", function() if openMenu == menu then closeMenu() end end)
    b.refreshText()
    return b
end

-- A check box with a label on its right; onChange(checked).
function ns.checkBox(parent, text, x, y, onChange)
    local c = ns.Theme.checkBox(parent, 28) -- GF-UI-D: the theme's box and the game's check mark
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
    local w = 200
    for _, item in ipairs(items) do w = math.max(w, ns.labelWidth(item.text) + 24) end
    for i, item in ipairs(items) do
        local b = popup.items[i]
        if not b then
            b = CreateFrame("Button", nil, popup)
            b:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (i - 1) * 28)
            pcall(b.SetNormalFontObject, b, ns.LABEL_FONT)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            ns.Theme.guardHover(b) -- GF-UI-D2: the gold header line stays dark
            popup.items[i] = b
        end
        b:SetSize(w - 8, 28)
        b:SetText(item.text)
        ns.leftText(b)
        -- GF-UI-C: a header line (e.g. the member's current rank): gold, not clickable.
        b.header = item.header == true
        if b.SetDisabledFontObject then pcall(b.SetDisabledFontObject, b, ns.FIELD_FONT) end
        if b.SetEnabled then b:SetEnabled(not b.header) end
        local fn = item.fn
        if b.header then b:SetScript("OnClick", nil)
        else b:SetScript("OnClick", function() closeMenu(); fn() end) end
        b:Show()
    end
    for i = #items + 1, #popup.items do popup.items[i]:Hide() end
    popup:SetSize(w, #items * 28 + 8)
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
    local b = ns.Theme.button(parent, nil, w, ns.BUTTON_H) -- GF-UI-D: outlined, the arrow on the right
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.options, b.selected = options, nil
    local menu = CreateFrame("Frame", nil, b)
    menu:SetFrameStrata("TOOLTIP") -- GF-002-F: above the click-outside blocker
    if menu.SetFrameLevel then menu:SetFrameLevel(100) end
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    ns.makeOpaque(menu, 0)
    menu:EnableMouse(true)
    menu:Hide()
    menu.items = {}
    b.menu = menu
    ns.escRegister(menu, ns.ESC_LEVEL.menu)
    local ROW, WIDTH = 28, math.max(w + 40, 210)

    function b.isOn(value) return b.selected == nil or b.selected[value] == true end
    -- GF-FIX-B (review mid-8): while the list is open, one options() read
    -- (made when it opened) serves every tick; closed, it is read live.
    b.optionReads = 0 -- options() calls (tests)
    function b.currentOptions()
        if menu:IsShown() and b.lastOptions then return b.lastOptions end
        b.optionReads = b.optionReads + 1
        local list = b.options()
        if menu:IsShown() then b.lastOptions = list end
        return list
    end
    menu:HookScript("OnHide", function() b.lastOptions = nil end)
    function b.count()
        local n = 0
        for _, o in ipairs(b.currentOptions()) do if b.isOn(o.value) then n = n + 1 end end
        return n
    end
    ns.dropArrow(b)
    function b.refreshText() b:SetText(summary(b)) end
    local function changed()
        -- Everything ticked is the same as "everything" (nil), so options
        -- added later (a new profession) are included.
        if b.selected and b.count() == #b.currentOptions() then b.selected = nil end
        b.refreshText()
        if menu:IsShown() then b.drawItems() end
        onChange()
    end
    function b.selectAll() b.selected = nil; changed() end
    function b.selectNone() b.selected = {}; changed() end
    function b.toggle(value)
        if b.selected == nil then
            b.selected = {}
            for _, o in ipairs(b.currentOptions()) do b.selected[o.value] = true end
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
        ns.Theme.guardHover(it)
        it.check = it:CreateTexture(nil, "ARTWORK")
        it.check:SetSize(20, 20)
        it.check:SetPoint("LEFT", it, "LEFT", 2, 0)
        it.icon = it:CreateTexture(nil, "ARTWORK")
        it.icon:SetSize(22, 22)
        it.icon:SetPoint("LEFT", it, "LEFT", 26, 0)
        it.label = it:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        it.label:SetJustifyH("LEFT")
        menu.items[i] = it
        return it
    end

    function b.drawItems()
        local list = b.currentOptions()
        local entries = { { text = "全選", fn = b.selectAll }, { text = "全不選", fn = b.selectNone } }
        -- GF-UI-C: every name starts at one x (after the box, and after the icon column when any option has one).
        local anyIcon = false
        for _, o in ipairs(list) do if o.icon then anyIcon = true end end
        local textX = anyIcon and 54 or 26
        b.textX = textX
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
            it.label:SetPoint("LEFT", it, "LEFT", textX, 0)
            -- GF-UI-B (GF-UI-A §1.6): ticked and empty boxes are both drawn.
            if e.on ~= nil then ns.GameIcons.set(it.check, e.on and "check_on" or "check_off") else it.check:Hide() end
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
        b.lastOptions = nil
        menu:Show() -- shown first: the one options() read below is kept while it is open
        b.drawItems()
        openMenu = menu
    end)
    b:HookScript("OnHide", function() if openMenu == menu then closeMenu() end end)
    b.refreshText()
    return b
end
