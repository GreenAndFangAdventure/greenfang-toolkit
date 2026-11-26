-- Minimal World of Warcraft API mock for offline tests of GreenFangToolkit.
-- Plain Lua 5.1 (same dialect as the game client). Only the API surface the
-- addon touches is modelled; every other frame method is a no-op.

local wow = {}

local TOC_FILES = { "Config.lua", "Core.lua", "Theme.lua", "Data.lua", "Icons.lua", "GameIcons.lua", "Professions.lua", "Roster.lua", "Sync.lua", "Comm.lua", "Share.lua", "Profile.lua", "Ledger.lua", "Orders.lua", "Prices.lua", "Delivery.lua", "WebOrders.lua", "AdventureData.lua", "Adventure.lua",
    "Export.lua", "Framework.lua", "UI.lua", "Character.lua", "ProfileUI.lua", "Recipes.lua", "Diag.lua", "GuildAdmin.lua", "NativeLFG.lua", "OrdersUI.lua", "Widgets.lua", "AdventureUI.lua", "SleepingBagData.lua", "SleepingBag.lua", "SupplyRules.lua", "Supply.lua", "SupplyListings.lua", "SupplyUI.lua", "Probe.lua", "Init.lua" }
TOC_FILES[#TOC_FILES + 1] = "Events.lua" -- GF-013 (appended, like the TOC)
TOC_FILES[#TOC_FILES + 1] = "Notify.lua" -- GF-014 (appended, like the TOC)
TOC_FILES[#TOC_FILES + 1] = "NotifyUI.lua"
TOC_FILES[#TOC_FILES + 1] = "SupplyRadar.lua"
TOC_FILES[#TOC_FILES + 1] = "Bank.lua" -- GF-012 (appended, like the TOC)
TOC_FILES[#TOC_FILES + 1] = "BankUI.lua"
TOC_FILES[#TOC_FILES + 1] = "SupplyCatalog.lua" -- GF-009-12 (appended, like the TOC)
TOC_FILES[#TOC_FILES + 1] = "SupplyCatalogData.lua"
TOC_FILES[#TOC_FILES + 1] = "CatalogScan.lua"
TOC_FILES[#TOC_FILES + 1] = "WorkerMatch.lua" -- GF-014-02 (appended, like the TOC)
wow.TOC_FILES = TOC_FILES

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function noop() end

local state
local allObjects = {}

-- Protected frames (SecureActionButtonTemplate) cannot be changed during the
-- combat lockdown. PLAYER_REGEN_DISABLED runs just before it starts, so
-- changes are still allowed while that event is being handled.
local function guard(self, what)
    if self._protected and state and state.combat and not state.regenWindow then
        state.blocked[#state.blocked + 1] = what
        error("ADDON_ACTION_BLOCKED: " .. what .. " on a protected frame in combat", 3)
    end
end

-- Rough on-screen width of a text: 6 px per ASCII character, 11 px otherwise.
-- GF-002-E: by font when the FontString has one (the client's zhTW fonts,
-- measured from the owner's 0.12.2 screenshots: 「目的地」 did not fit 43 px
-- at GameFontNormal): Small 6/13, normal 7/15, Large 8/18 (ASCII/Chinese).
local function fontPx(font)
    if not font then return 6, 11 end
    -- GF-002-F: the toolkit's own font objects (CreateFont + SetFont) carry their size.
    local obj = type(font) == "string" and rawget(_G, font) or font
    if type(obj) == "table" and obj._fontSize then return math.floor(obj._fontSize / 2), obj._fontSize end
    font = tostring(font)
    if font:find("Small") then return 6, 13 end
    if font:find("Large") or font:find("Huge") then return 8, 18 end
    return 7, 15
end
local function textWidth(t, font)
    local a, c = fontPx(font)
    local w = 0
    t = tostring(t or ""):gsub("|T.-|t", "\1\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for ch in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        w = w + (ch == "\1" and 8 or #ch == 1 and a or c)
    end
    return w
end

-- A FontString with a fixed width (SetWidth > 0) reports at most that width,
-- as the client does for truncated text; SetWidth(0) frees it (GF-001-D18:
-- this is what cut the roster's profession names to "…"). Shared functions,
-- so every mock object does not carry its own copies.
local function fixedWidthOf(self)
    local fixed = self._fixedWidth
    if self._kind == "FontString" and type(fixed) == "number" and fixed > 0 then return fixed end
end
local function setWidth(self, w) self._fixedWidth = w end
local function setAlpha(self, a) self._alpha = a end
local function setFrameStrata(self, v) self._strata = v end
local function setColorTexture(self, r, g, b, a) self._color = { r, g, b, a } end
local function getStringWidth(self)
    local w, fixed = textWidth(self._text, self._font), fixedWidthOf(self)
    if fixed and w > fixed then return fixed end
    return w
end
-- Truncated ("…") or, with word wrap on, broken onto a second line.
local function isTruncated(self)
    local fixed = fixedWidthOf(self)
    return fixed ~= nil and textWidth(self._text, self._font) > fixed
end
wow.textWidth = textWidth

local function newObject(kind, name)
    local o = { _kind = kind, _name = name, _shown = true, _scripts = {}, _events = {}, _text = "", _attrs = {} }
    allObjects[#allObjects + 1] = o
    local methods = {}
    function methods.SetTextColor(self, r, g, b) self._color = { r, g, b } end
    function methods.SetEnabled(self, on) guard(self, "SetEnabled"); self._enabled = on and true or false end
    -- OnShow/OnHide also reach shown children, as in the client.
    local function notify(f, what)
        if f._scripts[what] then f._scripts[what](f) end
        for _, c in ipairs(f._children or {}) do if c._shown then notify(c, what) end end
    end
    function methods.Show(self)
        guard(self, "Show")
        local was = self._shown
        self._shown = true
        if not was then notify(self, "OnShow") end
    end
    function methods.Hide(self)
        guard(self, "Hide")
        local was = self._shown
        self._shown = false
        if was then notify(self, "OnHide") end
    end
    function methods.SetAttribute(self, k, v) guard(self, "SetAttribute"); self._attrs[k] = v end
    function methods.GetAttribute(self, k) return self._attrs[k] end
    function methods.RegisterForClicks(self, ...) self._clicks = { ... } end
    methods.SetWidth, methods.GetStringWidth, methods.IsTruncated = setWidth, getStringWidth, isTruncated
    methods.SetAlpha = setAlpha
    methods.SetFrameStrata, methods.SetColorTexture = setFrameStrata, setColorTexture
    function methods.SetVerticalScroll(self, v)
        self._vscroll = v
        if self._scripts.OnVerticalScroll then self._scripts.OnVerticalScroll(self, v) end
    end
    function methods.GetVerticalScroll(self) return self._vscroll or 0 end
    function methods.IsShown(self) return self._shown end
    function methods.SetScript(self, what, fn) self._scripts[what] = fn end
    function methods.GetScript(self, what) return self._scripts[what] end
    function methods.HookScript(self, what, fn)
        local old = self._scripts[what]
        self._scripts[what] = old and function(...) old(...); fn(...) end or fn
    end
    function methods.RegisterEvent(self, e) self._events[e] = true end
    function methods.UnregisterEvent(self, e) self._events[e] = nil end
    function methods.SetText(self, t) self._text = t or "" end
    function methods.GetText(self) return self._text end
    function methods.CreateFontString(self, _, _, font)
        local fs = newObject("FontString")
        fs._font, fs._parent = font, self
        return fs
    end
    function methods.SetFontObject(self, font) self._font = font end
    function methods.SetDesaturated(self, on) self._desaturated = on and true or false end
    function methods.SetVertexColor(self, r, g, b) self._vertex = { r, g, b } end
    function methods.SetHeight(self, h) if self._kind ~= "FontString" then self._h = h end end
    function methods.SetBlendMode(self, m) self._blend = m end
    function methods.SetWordWrap(self, on) self._wordWrap = on and true or false end
    function methods.CreateTexture(self, _, layer)
        local t = newObject("Texture")
        t._layer, t._parent = layer, self
        self._textures = self._textures or {}
        self._textures[#self._textures + 1] = t
        return t
    end
    function methods.SetSize(self, w, h) guard(self, "SetSize"); self._w, self._h = w, h end
    function methods.SetPoint(self, ...)
        guard(self, "SetPoint")
        self._points = self._points or {}
        self._points[#self._points + 1] = { ... }
    end
    function methods.ClearAllPoints(self) guard(self, "ClearAllPoints"); self._points = {} end
    function methods.SetTexture(self, path)
        self._texture = path
        if state.missingFiles and state.missingFiles[path] then return false end
        return true
    end
    function methods.SetTexCoord(self, ...) self._texCoord = { ... } end
    function methods.SetMinMaxValues(self, lo, hi) self._min, self._max = lo, hi end
    function methods.SetValue(self, v) self._value = v end
    function methods.GetWidth() return state and state.minimapSize or 140 end
    function methods.GetHeight() return state and state.minimapSize or 140 end
    function methods.GetCenter() return 100, 100 end
    function methods.GetEffectiveScale() return 1 end
    -- Unknown widget methods (Capitalized) are no-ops; unknown fields stay nil,
    -- as on a real frame.
    return setmetatable(o, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:find("^[A-Z]") and k ~= "TitleText" then return noop end
        return nil
    end })
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- (state is declared at the top of the file)

function wow.defaultPlayer()
    return {
        guid = "Player-0000-0000000A", name = "測試甲", realm = "測試伺服器",
        faction = "Horde", level = 32, class = "德魯伊", classToken = "DRUID",
        race = "牛頭人", raceToken = "Tauren", raceID = 6,
        guild = "綠皮與獠牙冒險事務所", guildRank = "會員",
        -- index -> { name, icon, rank, max, abilities, offset, skillLine }
        professions = {
            [1] = { "製皮", 133611, 151, 225, 0, 0, 165 },
            [2] = { "剝皮", 134366, 160, 225, 0, 0, 393 },
            [4] = { "釣魚", 136245, 75, 150, 0, 0, 356 },
            [5] = { "烹飪", 133971, 60, 150, 0, 0, 185 },
        },
        professionIndexes = { 1, 2, nil, 4, 5 },
    }
end

-- One guild member per row, in GetGuildRosterInfo order.
function wow.defaultRoster()
    return {
        { name = "測試甲-測試伺服器", rank = "會員", level = 32, class = "德魯伊", classToken = "DRUID",
          zone = "雷霆崖", online = true, guid = "Player-0000-0000000A" },
        { name = "測試乙-測試伺服器", rank = "會長", level = 60, class = "戰士", classToken = "WARRIOR",
          zone = "奧格瑪", online = true, guid = "Player-0000-0000000B",
          club = { race = 2, profession1ID = 164, profession2ID = 186 } },
        { name = "測試丙-測試伺服器", rank = "會員", level = 25, class = "法師", classToken = "MAGE",
          zone = "幽暗城", online = false, guid = "Player-0000-0000000C",
          club = { race = 5, profession1Name = "裁縫", profession2Name = "附魔" } },
        { name = "測試丁-測試伺服器", rank = "新進", level = 12, class = "獵人", classToken = "HUNTER",
          zone = "杜洛塔", online = false, guid = "Player-0000-0000000D" },
    }
end

function wow.reset(opts)
    opts = opts or {}
    state = {
        now = opts.now or 1763370000,
        timers = {},
        frames = {},
        printed = {},
        combat = false,
        inGuild = opts.inGuild ~= false,
        player = opts.player or wow.defaultPlayer(),
        roster = opts.roster or wow.defaultRoster(),
        missingRow = nil,       -- index of a row GetGuildRosterInfo pretends not to have
        noProfessionsAPI = opts.noProfessionsAPI,
        skillLines = opts.skillLines,
        rosterRequests = 0,
        noIsInGuild = opts.noIsInGuild,     -- IsInGuild missing (not in the ForeverAPI dump)
        noCTimer = opts.noCTimer,           -- C_Timer missing -> addon must use OnUpdate
        noTemplates = opts.noTemplates,     -- CreateFrame errors on Blizzard templates
        noMetadata = opts.noMetadata,       -- C_AddOns.GetAddOnMetadata / GetAddOnMetadata missing
        noClub = opts.noClub,               -- C_Club / C_CreatureInfo / GetPlayerInfoByGUID missing
        cSkillInfo = opts.cSkillInfo,       -- C_SkillInfo skill list (16001 style, table per line)
        secrets = opts.secrets or {},       -- values issecretvalue() reports as secret
        rosterOverride = opts.rosterOverride, -- function(i) returning raw GetGuildRosterInfo values
        minimapSize = opts.minimapSize,     -- Minimap:GetWidth()/GetHeight(), default 140
        missingFiles = opts.missingFiles,   -- texture paths the client does not have
        fileIDs = opts.fileIDs,             -- true: provide GetFileIDFromPath
        zone = opts.zone == nil and "雷霆崖" or opts.zone,          -- GetZoneText()
        subZone = opts.subZone == nil and "長者高地" or opts.subZone, -- GetSubZoneText()
        noZoneText = opts.noZoneText,       -- GetZoneText missing -> C_Map fallback
        classColorAPI = opts.classColorAPI, -- provide C_ClassColor.GetClassColor
        noChatInfo = opts.noChatInfo,       -- C_ChatInfo missing
        guildPerms = opts.guildPerms,       -- GF-001-Q: { invite = true, promote = true, ... }
        myRankIndex = opts.myRankIndex,     -- my rank index from GetGuildInfo (default 4)
        noGuildAdmin = opts.noGuildAdmin,   -- the guild management functions are missing
        sent = {},                          -- addon messages sent
        prefixes = {},                      -- registered addon message prefixes
        reloads = 0,                        -- C_UI.Reload calls
        blocked = {},                       -- protected calls refused (ADDON_ACTION_BLOCKED)
        casts = {},                         -- spells cast by secure buttons
        secureDepth = 0,                    -- > 0 while a secure handler runs
        noSecureTemplate = opts.noSecureTemplate, -- client without SecureActionButtonTemplate
        noSpellAPI = opts.noSpellAPI,       -- C_Spell missing
        tradeSkill = opts.tradeSkill,       -- an open profession window (GF-001-D10)
    }
    wow.state = state
    wow.installGlobals()
end

local function tickOnUpdate(seconds)
    local step = 0.1
    local elapsed = 0
    while elapsed < seconds - 1e-9 do
        state.now = state.now + step
        elapsed = elapsed + step
        for _, f in ipairs(state.frames) do
            if f._scripts.OnUpdate then f._scripts.OnUpdate(f, step) end
        end
    end
end

function wow.advance(seconds)
    if state.noCTimer then
        local start = state.now
        tickOnUpdate(seconds)
        state.now = start + seconds
        return
    end
    local target = state.now + seconds
    while true do
        table.sort(state.timers, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            return a.seq < b.seq
        end)
        local t = state.timers[1]
        if not t or t.at > target then break end
        table.remove(state.timers, 1)
        if t.at > state.now then state.now = t.at end
        t.fn()
    end
    state.now = target
end

function wow.fire(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then state.regenWindow = true end
    for _, f in ipairs(state.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
    state.regenWindow = false
end

-- Combat as the client does it: PLAYER_REGEN_DISABLED, then the lockdown.
function wow.enterCombat()
    state.combat = true
    wow.fire("PLAYER_REGEN_DISABLED")
end
function wow.leaveCombat()
    state.combat = false
    wow.fire("PLAYER_REGEN_ENABLED")
end

-- A mouse click by the player. Hidden or disabled buttons get nothing.
-- Secure buttons: PreClick (ours, insecure), then the secure action of the
-- template, then PostClick. Returns what happened.
local function secureAction(b)
    local kind = b._attrs.type
    state.secureDepth = state.secureDepth + 1
    local result = "none"
    if kind == "macro" then
        local text = b._attrs.macrotext or ""
        if text == "/reload" then C_UI.Reload(); result = "reload" else result = "macro:" .. text end
    elseif kind == "spell" and b._attrs.spell then
        state.casts[#state.casts + 1] = b._attrs.spell
        result = "spell:" .. b._attrs.spell
    end
    state.secureDepth = state.secureDepth - 1
    return result
end

function wow.click(b, mouse, down)
    if not b or b._enabled == false then return "ignored" end
    local f = b
    while f do
        if not f._shown then return "ignored" end
        f = f._parent
    end
    mouse = mouse or "LeftButton"
    if b._scripts.PreClick then b._scripts.PreClick(b, mouse, down) end
    local result = "none"
    if b._protected then
        result = secureAction(b)
    elseif b._scripts.OnClick then
        b._scripts.OnClick(b, mouse, down)
        result = "onclick"
    end
    if b._scripts.PostClick then b._scripts.PostClick(b, mouse, down) end
    return result
end

-- ESC (GF-002-E): the client's CloseSpecialWindows hides every shown frame
-- named in UISpecialFrames; when none was shown, the game menu opens.
-- Then the next frame (timers at 0) runs. Returns true when a frame took it.
function wow.pressEscape()
    local found = false
    for _, name in pairs(UISpecialFrames) do
        local f = _G[name]
        if f and f._shown then f:Hide(); found = true end
    end
    if not found then state.gameMenu = (state.gameMenu or 0) + 1 end
    wow.advance(0)
    return found
end
function wow.gameMenuCount() return state.gameMenu or 0 end

-- The game's confirm box (GF-001-Q): the one open, accept (with edit text), cancel.
function wow.popup() return state.staticPopup end
function wow.acceptPopup(text)
    local f = state.staticPopup
    if not f then return false end
    if text and f.editBox then f.editBox:SetText(text) end
    local d = StaticPopupDialogs[f.which]
    state.staticPopup = nil
    if d.OnAccept then d.OnAccept(f, f.data) end
    return true
end
function wow.cancelPopup() state.staticPopup = nil end

-- Every text currently set on any widget (font strings, buttons, edit boxes).
function wow.allObjects() return allObjects end

function wow.allTexts()
    local list = {}
    for _, o in ipairs(allObjects) do
        if type(o._text) == "string" and o._text ~= "" then list[#list + 1] = o._text end
    end
    return list
end

-- A CHAT_MSG_SYSTEM line: true when a filter hid it, else it is "shown".
function wow.systemMessage(text)
    for _, fn in ipairs(state.chatFilters and state.chatFilters.CHAT_MSG_SYSTEM or {}) do
        if fn(nil, "CHAT_MSG_SYSTEM", text) == true then return true end
    end
    state.systemShown[#state.systemShown + 1] = text
    return false
end

function wow.setCombat(on) state.combat = on and true or false end
function wow.printed() return state.printed end
function wow.clearPrinted() state.printed = {} end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------

local seq = 0
function wow.installGlobals()
    local p = state.player
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        state.printed[#state.printed + 1] = table.concat(parts, " ")
    end
    time = function() return state.now end
    GetServerTime = function() return state.now + (state.serverSkew or 0) end
    -- Local time is fixed to UTC+8 (Taiwan) so results do not depend on the machine.
    date = function(f, t)
        t = t or state.now
        if f:sub(1, 1) == "!" then return os.date(f, t) end
        return os.date("!" .. f, t + 8 * 3600)
    end
    GetLocale = function() return "zhTW" end
    GetBuildInfo = function() return "1.16.1", "99999", "Nov 1 2026", 16001 end
    UIParent = newObject("Frame", "UIParent")
    Minimap = newObject("Minimap", "Minimap")
    allObjects = {}
    GameTooltip = newObject("GameTooltip", "GameTooltip")
    GameTooltip._lines = {}
    GameTooltip.SetOwner = function(self, owner, anchor) self._owner = owner; self._anchor = anchor; self._points = {}; self._lines = {} end
    GameTooltip.GetOwner = function(self) return self._owner end
    GameTooltip.ClearLines = function(self) self._lines = {} end
    GameTooltip.AddLine = function(self, text, r, g, b)
        self._lines[#self._lines + 1] = { text = text, color = r and { r, g, b } or nil }
    end
    GameTooltip.Hide = function(self) self._owner = nil; self._shown = false; self._lines = {} end
    UISpecialFrames = {}
    -- Fonts (GF-002-F): the game's font objects, and CreateFont for the toolkit's own.
    for _, n in ipairs({ "GameFontHighlight", "GameFontNormal", "GameFontDisable" }) do
        local fo = newObject("Font", n)
        fo._fontSize = 13
        fo.GetFont = function(self) return "Fonts/ARIALN.ttf", self._fontSize, "" end
        _G[n] = fo
    end
    CreateFont = function(name)
        local fo = newObject("Font", name)
        fo.SetFont = function(self, path, size) self._fontPath, self._fontSize = path, size end
        fo.CopyFontObject = function(self, src) self._fontSize = src and src._fontSize end
        fo.GetFont = function(self) return self._fontPath, self._fontSize, "" end
        if name then _G[name] = fo end
        return fo
    end
    SlashCmdList = {}
    CreateFrame = function(kind, name, parent, template)
        if template and state.noTemplates then error("Couldn't find inherited node: " .. template) end
        local secure = template and template:find("SecureActionButtonTemplate", 1, true) ~= nil
        if secure and state.noSecureTemplate then error("Couldn't find inherited node: SecureActionButtonTemplate") end
        local f = newObject(kind, name)
        f._parent, f._template, f._protected = parent, template, secure
        if parent then parent._children = parent._children or {}; table.insert(parent._children, f) end
        if template == "BasicFrameTemplateWithInset" then f.TitleText = newObject("FontString") end
        state.frames[#state.frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    C_Timer = { After = function(delay, fn)
        seq = seq + 1
        state.timers[#state.timers + 1] = { at = state.now + delay, fn = fn, seq = seq }
    end }
    if state.noCTimer then C_Timer = nil end
    issecretvalue = function(v) return state.secrets[v] == true end
    InCombatLockdown = function() return state.combat end
    -- state.guildInfoGone simulates the client briefly reporting no guild
    -- (early login, PLAYER_LOGOUT, /reload) while the character is in one.
    -- state.guildNameLoading: IsInGuild() is true but the name is not loaded yet.
    IsInGuild = function() return state.inGuild and not state.guildInfoGone end
    if state.noIsInGuild then IsInGuild = nil end
    GetGuildInfo = function(unit)
        if unit ~= "player" or not state.inGuild or state.guildInfoGone
            or state.guildNameLoading then return nil end
        return p.guild, p.guildRank, state.myRankIndex or 4, nil
    end
    GetRealmName = function() return p.realm end
    GetZoneText = function() return state.zone end
    GetSubZoneText = function() return state.subZone end
    GetRealZoneText = nil
    C_Map = nil
    if state.noZoneText then
        GetZoneText = nil
        C_Map = {
            GetBestMapForUnit = function(unit) if unit == "player" then return 1456 end end,
            GetMapInfo = function(id) if id == 1456 then return { mapID = id, name = state.zone } end end,
        }
    end
    C_ClassColor = nil
    if state.classColorAPI then
        C_ClassColor = { GetClassColor = function(token)
            if token == "DRUID" then return { r = 0.5, g = 0.25, b = 0.125 } end
        end }
    end
    -- GF-UI-C: state.units = { target = "Player-...", party1 = ... } for the inspect checks.
    UnitGUID = function(unit)
        if unit == "player" then return p.guid end
        return state.units and state.units[unit] or nil
    end
    UnitName = function(unit) if unit == "player" then return p.name, nil end end
    UnitLevel = function(unit) if unit == "player" then return p.level end end
    UnitClass = function(unit) if unit == "player" then return p.class, p.classToken, 11 end end
    UnitRace = function(unit) if unit == "player" then return p.race, p.raceToken, p.raceID end end
    UnitFactionGroup = function(unit) if unit == "player" then return p.faction, "部落" end end
    if state.noProfessionsAPI then
        GetProfessions, GetProfessionInfo = nil, nil
    else
        GetProfessions = function()
            local i = p.professionIndexes
            return i[1], i[2], i[3], i[4], i[5]
        end
        GetProfessionInfo = function(index)
            local row = p.professions[index]
            if not row then return nil end
            return unpack(row)
        end
    end
    if state.cSkillInfo then
        C_SkillInfo = {
            GetNumSkillLines = function() return #state.cSkillInfo end,
            GetSkillLineInfo = function(i)
                local s = state.cSkillInfo[i]
                if not s then return nil end
                return { name = s.name, isHeader = s.header or false, rank = s.rank, maxRank = s.max,
                    skillID = s.skillID, tempPoints = 0, modifier = 0 }
            end,
        }
    else
        C_SkillInfo = nil
    end
    if state.skillLines then
        GetNumSkillLines = function() return #state.skillLines end
        GetSkillLineInfo = function(i)
            local s = state.skillLines[i]
            return s.name, s.header, false, s.rank, 0, 0, s.max
        end
    else
        GetNumSkillLines, GetSkillLineInfo = nil, nil
    end
    GetNumGuildMembers = function()
        local online = 0
        for _, m in ipairs(state.roster) do if m.online then online = online + 1 end end
        return #state.roster, online, online
    end
    GetGuildRosterInfo = function(i)
        state.rosterInfoCalls = (state.rosterInfoCalls or 0) + 1
        if state.rosterOverride then return state.rosterOverride(i) end
        if i == state.missingRow then return nil end
        local m = state.roster[i]
        if not m then return nil end
        local rankIndex = ({ ["會長"] = 0, ["幹部"] = 1, ["會員"] = 2, ["新進"] = 3 })[m.rank] or 2
        return m.name, m.rank, rankIndex, m.level, m.class, m.zone, m.note or "公開備註", m.officerNote or "幹部備註", m.online, 0,
            m.classToken, 0, 0, false, false, 4, m.guid
    end
    C_GuildInfo = { GuildRoster = function() state.rosterRequests = state.rosterRequests + 1 end }
    -- Guild management (GF-001-Q). state.guildPerms = { invite = true, promote = true, ... };
    -- every call is recorded in state.guildCalls; state.noGuildAdmin removes them all.
    state.guildCalls = {}
    local function perm(k) return function() return state.guildPerms ~= nil and state.guildPerms[k] == true end end
    local function call(what) return function(a, b) state.guildCalls[#state.guildCalls + 1] = what .. ":" .. tostring(a) .. (b and (":" .. tostring(b)) or "") end end
    CanGuildInvite, CanGuildPromote, CanGuildDemote, CanGuildRemove = perm("invite"), perm("promote"), perm("demote"), perm("remove")
    CanEditPublicNote, CanEditOfficerNote, CanViewOfficerNote = perm("publicNote"), perm("officerNote"), perm("viewOfficer")
    CanEditMOTD, CanEditGuildInfo = perm("motd"), perm("info")
    GuildInvite, GuildPromote, GuildDemote, GuildUninvite = call("invite"), call("promote"), call("demote"), call("uninvite")
    GuildRosterSetPublicNote = function(i, t) call("publicNote")(i, t); if state.roster[i] then state.roster[i].note = t end end
    GuildRosterSetOfficerNote = function(i, t) call("officerNote")(i, t); if state.roster[i] then state.roster[i].officerNote = t end end
    GuildSetMOTD = function(t) call("motd")(t); state.motd = t end
    GetGuildRosterMOTD = function() return state.motd or "" end
    GetGuildInfoText = function() return state.guildInfoText or "" end
    SetGuildInfoText = function(t) call("info")(t); state.guildInfoText = t end
    GuildControlGetNumRanks = function() return 4 end
    ToggleGuildFrame = call("guildFrame")
    -- GF-UI-C: inspect (state.units holds the unit tokens; state.farAway = out of range).
    InspectUnit = call("inspect")
    CanInspect = function(unit) return state.units ~= nil and state.units[unit] ~= nil end
    CheckInteractDistance = function(unit) return not state.farAway end
    GuildControlGetRankName = function(i) return ({ "會長", "幹部", "會員", "新進" })[i] or "" end
    ChatFrame_SendTell = call("tell")
    C_PartyInfo = { InviteUnit = call("group") }
    C_FriendList = { SendWho = call("who") }
    -- The game's own confirm boxes: StaticPopup_Show records the open one;
    -- wow.acceptPopup / wow.cancelPopup press its buttons.
    StaticPopupDialogs = {}
    state.staticPopup = nil
    StaticPopup_Show = function(which, text1, text2, data)
        local d = StaticPopupDialogs[which]
        if not d then return nil end
        local frame = { which = which, data = data, text = string.format(d.text, text1 or "", text2 or "") }
        if d.hasEditBox then
            frame.editBox = { _text = "", SetText = function(self, t) self._text = t or "" end,
                GetText = function(self) return self._text end, SetMaxLetters = function(self, n) self._max = n end,
                HighlightText = function() end, GetParent = function() return frame end }
        end
        frame.Hide = function() if state.staticPopup == frame then state.staticPopup = nil end end
        if d.OnShow then d.OnShow(frame, data) end
        state.staticPopup = frame
        return frame
    end
    if state.noGuildAdmin then
        CanGuildInvite, CanGuildPromote, CanGuildDemote, CanGuildRemove = nil, nil, nil, nil
        CanEditPublicNote, CanEditOfficerNote, CanViewOfficerNote, CanEditMOTD, CanEditGuildInfo = nil, nil, nil, nil, nil
        GuildInvite, GuildPromote, GuildDemote, GuildUninvite = nil, nil, nil, nil
        GuildRosterSetPublicNote, GuildRosterSetOfficerNote, GuildSetMOTD, SetGuildInfoText = nil, nil, nil, nil
        StaticPopup_Show, ToggleGuildFrame = nil, nil
    end
    C_ChatInfo = nil
    if not state.noChatInfo then
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function(prefix) state.prefixes[prefix] = true; return 0 end,
            SendAddonMessage = function(prefix, msg, chatType, target)
                if #msg > 255 then error("message too long") end
                state.sent[#state.sent + 1] = { prefix = prefix, msg = msg, chatType = chatType, target = target }
                return 0
            end,
        }
    end
    -- Chat message filters (GF-001-D12): wow.systemMessage runs them like the chat frame.
    state.chatFilters, state.systemShown = {}, {}
    ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    ChatFrame_AddMessageEventFilter = function(event, fn)
        state.chatFilters[event] = state.chatFilters[event] or {}
        table.insert(state.chatFilters[event], fn)
    end
    -- Protected on 16001 (GF-001-D8): only secure code may reload the UI.
    local function protectedReload(what)
        return function()
            if state.secureDepth == 0 then
                state.blocked[#state.blocked + 1] = what
                error("ADDON_ACTION_BLOCKED: " .. what, 2)
            end
            state.reloads = state.reloads + 1
        end
    end
    C_UI = { Reload = protectedReload("C_UI.Reload") }
    ReloadUI = protectedReload("ReloadUI")
    -- First-rank profession spell IDs -> zhTW names (test data only).
    local spellNames = { [2018] = "鍛造", [2108] = "製皮", [3908] = "裁縫", [4036] = "工程學",
        [2259] = "鍊金術", [7411] = "附魔", [2550] = "烹飪", [3273] = "急救", [2656] = "熔煉",
        [7620] = "釣魚", [2366] = "採集草藥", [8613] = "剝皮",
        [2660] = "粗製磨刀石", [2661] = "銅質鎖甲", [2662] = "銅質護腕", [3115] = "粗製砂輪",
        [2152] = "輕型護甲片", [2149] = "粗糙皮靴" }
    state.spellLookups = {}
    C_Spell = {
        GetSpellName = function(id)
            state.spellLookups[#state.spellLookups + 1] = id
            return spellNames[id] or (state.anySpellName and ("配方" .. id) or nil)
        end,
        GetSpellInfo = function(id)
            if not spellNames[id] then return nil end
            return { name = spellNames[id], spellID = id, iconID = 1, castTime = 0, minRange = 0, maxRange = 0 }
        end,
    }
    if state.noSpellAPI then C_Spell = nil end
    GetSpellInfo = nil
    C_Club = {
        GetGuildClubId = function() return 42 end,
        GetClubMembers = function()
            local ids = {}
            for i, m in ipairs(state.roster) do if m.club then ids[#ids + 1] = i end end
            return ids
        end,
        GetMemberInfo = function(_, id)
            local m = state.roster[id]
            local info = {}
            for k, v in pairs(m.club) do info[k] = v end
            info.name, info.guid = m.name, m.guid
            return info
        end,
    }
    C_CreatureInfo = { GetRaceInfo = function(id)
        local names = { [2] = "獸人", [5] = "不死族", [6] = "牛頭人", [8] = "食人妖" }
        return names[id] and { raceName = names[id] } or nil
    end }
    C_TradeSkillUI = nil
    -- An open profession window (GF-001-D10): state.tradeSkill =
    --   { skillLine = 164, recipes = { [id] = learned }, linked, guild, guildMember, ready }
    if state.tradeSkill then
        local ts = state.tradeSkill
        C_TradeSkillUI = {
            GetBaseProfessionInfo = function() return { professionID = ts.skillLine, professionName = "x" } end,
            GetAllRecipeIDs = function()
                local ids = {}
                for id in pairs(ts.recipes or {}) do ids[#ids + 1] = id end
                table.sort(ids)
                return ids
            end,
            GetRecipeInfo = function(id)
                if ts.recipes[id] == nil then return nil end
                return { recipeID = id, name = spellNames[id], learned = ts.recipes[id] }
            end,
            IsTradeSkillReady = function() return ts.ready ~= false end,
            IsTradeSkillLinked = function() return ts.linked == true end,
            IsTradeSkillGuild = function() return ts.guild == true end,
            IsTradeSkillGuildMember = function() return ts.guildMember == true end,
        }
        -- GF-001-D21: like Forever, GetAllRecipeIDs may list other
        -- professions' recipes; ts.recipeSkills = { [id] = skillLineID }.
        if ts.recipeSkills then
            C_TradeSkillUI.GetProfessionInfoByRecipeID = function(id)
                local skill = ts.recipeSkills[id]
                return skill and { professionID = skill, parentProfessionID = skill } or nil
            end
        end
    end
    GetPlayerInfoByGUID = function(guid)
        if guid == "Player-0000-0000000D" then return "獵人", "HUNTER", "食人妖", "Troll", 2, "測試丁", "" end
        return nil
    end
    GetCursorPosition = function() return 0, 0 end
    if state.fileIDs then
        GetFileIDFromPath = function(path)
            if state.missingFiles and state.missingFiles[path] then return nil end
            return 12345
        end
    else
        GetFileIDFromPath = nil
    end
    if state.noClub then
        C_Club, C_CreatureInfo, GetPlayerInfoByGUID = nil, nil, nil
    end
end

---------------------------------------------------------------------------
-- Loading the addon
---------------------------------------------------------------------------

-- Load every file of the addon in TOC order into a fresh namespace, as the
-- client does. SavedVariables are set beforehand, then ADDON_LOADED fires.
function wow.loadAddon(addonDir, saved)
    saved = saved or {}
    GreenFangToolkitDB = saved.GreenFangToolkitDB
    GFGuildRosterDB = saved.GFGuildRosterDB
    -- The client serves "## Key: value" lines of the TOC through
    -- C_AddOns.GetAddOnMetadata (GetAddOnMetadata on older clients).
    local meta = {}
    local f = io.open(addonDir .. "/GreenFangToolkit.toc", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^## ([%w%-]+):%s*(.-)%s*$")
            if k then meta[k] = v end
        end
        f:close()
    end
    local function getMeta(name, key)
        if name == "GreenFangToolkit" then return meta[key] end
    end
    if state.noMetadata then
        C_AddOns, GetAddOnMetadata = nil, nil
    else
        C_AddOns = { GetAddOnMetadata = getMeta }
        GetAddOnMetadata = getMeta
    end
    local ns = {}
    for _, file in ipairs(TOC_FILES) do
        local chunk, err = loadfile(addonDir .. "/" .. file)
        if not chunk then error(err, 0) end
        chunk("GreenFangToolkit", ns)
    end
    wow.fire("ADDON_LOADED", "GreenFangToolkit")
    return ns
end

-- Full login: load, PLAYER_LOGIN, let every startup timer run.
function wow.login(addonDir, saved)
    local ns = wow.loadAddon(addonDir, saved)
    wow.fire("PLAYER_LOGIN")
    wow.advance(10)
    return ns
end

-- What the client would write to disk: the global table after PLAYER_LOGOUT.
function wow.logout()
    wow.fire("PLAYER_LOGOUT")
    return { GreenFangToolkitDB = GreenFangToolkitDB, GFGuildRosterDB = GFGuildRosterDB }
end

---------------------------------------------------------------------------
-- SavedVariables writer in the client's on-disk style (tabs, ["key"] = value,
-- "-- [n]" after array items). Keys are sorted so the output is stable.
---------------------------------------------------------------------------

local function quote(s)
    return '"' .. s:gsub('[\\"\n\r]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r" }) .. '"'
end

local function serializeValue(v, indent, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = quote(v)
    elseif t == "number" then out[#out + 1] = (v == math.floor(v)) and string.format("%d", v) or tostring(v)
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{\n"
        local n = #v
        for i = 1, n do
            out[#out + 1] = indent .. "\t"
            serializeValue(v[i], indent .. "\t", out)
            out[#out + 1] = ", -- [" .. i .. "]\n"
        end
        local keys = {}
        for k in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and quote(k) or tostring(k)) .. "] = "
            serializeValue(v[k], indent .. "\t", out)
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    else
        out[#out + 1] = "nil"
    end
end

function wow.serializeSV(name, value)
    local out = { "\n", name, " = " }
    serializeValue(value, "", out)
    out[#out + 1] = "\n"
    return table.concat(out)
end

return wow
