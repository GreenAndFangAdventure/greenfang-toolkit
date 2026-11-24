-- 綠皮冒險工具箱 GreenFangToolkit / World of Warcraft: Forever (Interface 16001)
-- Core: namespace, small helpers, SavedVariables schema v2 and migration from
-- GFGuildRoster v0.3.1. The addon never talks to the network; GF Sync (a separate
-- Windows program) reads GreenFangToolkitDB.sync after the client saves it.
-- Contract: docs/contracts/savedvariables.md

local ADDON_NAME, ns = ...
ns = ns or {}

ns.ADDON = ADDON_NAME or "GreenFangToolkit"
-- The version lives only in GreenFangToolkit.toc ("## Version:"), so a release
-- tag, the TOC and what the addon reports can never disagree.
local function tocVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, ns.ADDON, "Version")
    if ok and type(v) == "string" and v ~= "" then return v end
end
ns.VERSION = tocVersion() or "dev"
ns.SCHEMA = "gf.toolkit"
ns.SCHEMA_VERSION = 2
ns.WORLD = "forever"
ns.DEFAULT_INTERFACE = 16001
ns.DEFAULT_MINIMAP_ANGLE = 215
ns.PREFIX = "|cff54c89a[綠皮冒險工具箱]|r "

function ns.say(s) print(ns.PREFIX .. s) end

-- Forever (16001) uses the Mainline API, where some values can be "secret"
-- (issecretvalue). A secret cannot be compared or stored, so treat it as missing.
function ns.isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
end

function ns.str(v)
    if type(v) == "string" and not ns.isSecret(v) then return v end
    return ""
end

function ns.num(v)
    if type(v) == "number" and not ns.isSecret(v) then return v end
    return nil
end

---------------------------------------------------------------------------
-- Realm of the logged-in character (GF-001-D23)
---------------------------------------------------------------------------
-- Since 2026-11-21 the site rejected every upload as invalid_realm: the
-- outbox had game.realm = "" and uploader.realm = "". The toolkit's code
-- had not changed since 0.9.2; GetRealmName() started giving "" (or a secret
-- value, which ns.str turns into ""). Order:
--   1. GetRealmName() (with spaces, what the site knows); remembered per
--      character in settings.realms (GF Sync never reads settings)
--   2. the remembered one, while GetNormalizedRealmName() agrees with it
--      (or is empty too); seeded from realms already in the SavedVariables
--   3. GetNormalizedRealmName() (no spaces)
--   4. "" = unknown: nothing is written to the outbox (Sync)
ns.realmSource = "unknown"

local function noSpace(s) return (ns.str(s):gsub("%s", "")) end

local function playerGuid() return ns.str((ns.call(UnitGUID, "player"))) end

local function realmStore()
    local s = ns.db and ns.db.settings
    if type(s) ~= "table" then return nil end
    if type(s.realms) ~= "table" then s.realms = {} end
    return s.realms
end

-- A realm already in the SavedVariables for this character (or its guild).
local function seedRealm(guid)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    for _, e in ipairs(type(db.sync) == "table" and type(db.sync.outbox) == "table" and db.sync.outbox or {}) do
        local u = type(e) == "table" and e.uploader
        if type(u) == "table" and u.guid == guid and ns.str(u.realm) ~= "" then return u.realm end
    end
    local guild = ns.str((ns.call(GetGuildInfo, "player")))
    local snaps = type(db.roster) == "table" and db.roster.snapshots
    for _, s in pairs(type(snaps) == "table" and snaps or {}) do
        if type(s) == "table" and ns.str(s.realm) ~= "" and (guild == "" or s.guild == guild) then return s.realm end
    end
    return nil
end

-- A known realm is reused for the rest of the second: the player's data is
-- read many times in a row (logout writes one entry per guild member).
local lastRealm, lastAt = nil, nil

function ns.realm()
    local now = time and time() or 0
    if lastRealm and lastAt == now then return lastRealm end
    local guid = playerGuid()
    local store = realmStore()
    local r = ns.str((ns.call(GetRealmName)))
    if r ~= "" then
        if store and guid ~= "" then store[guid] = r end
        ns.realmSource = "GetRealmName"
        lastRealm, lastAt = r, now
        return r
    end
    lastRealm = nil
    local saved = store and guid ~= "" and ns.str(store[guid]) or ""
    if saved == "" and guid ~= "" then
        saved = ns.str(seedRealm(guid))
        if saved ~= "" and store then store[guid] = saved end
    end
    local norm = ns.str((ns.call(GetNormalizedRealmName)))
    if saved ~= "" and (norm == "" or noSpace(saved) == norm) then
        ns.realmSource = "saved"
        return saved
    end
    if norm ~= "" then
        ns.realmSource = "GetNormalizedRealmName"
        return norm
    end
    ns.realmSource = "unknown"
    return ""
end

-- Call a game function that may not exist on this client. Returns its results,
-- or nothing when the function is missing or raises an error.
function ns.call(fn, ...)
    if type(fn) ~= "function" then return end
    local results = { pcall(fn, ...) }
    if not results[1] then return end
    return unpack(results, 2, table.maxn(results))
end

-- IsInGuild is not listed in the ForeverAPI dump; fall back to GetGuildInfo
-- and C_GuildInfo / IsPlayerInGuildFromGUID.
function ns.isInGuild()
    if type(IsInGuild) == "function" then
        local ok, inGuild = pcall(IsInGuild)
        if ok and type(inGuild) == "boolean" and not ns.isSecret(inGuild) then return inGuild end
    end
    if ns.str((ns.call(GetGuildInfo, "player"))) ~= "" then return true end
    local guid = ns.call(UnitGUID, "player")
    if type(guid) == "string" and type(IsPlayerInGuildFromGUID) == "function" then
        local ok, inGuild = pcall(IsPlayerInGuildFromGUID, guid)
        if ok and inGuild == true then return true end
    end
    return false
end

-- C_Timer.After, or an OnUpdate countdown when the client lacks C_Timer.
local timerFrame, timers
function ns.after(delay, fn)
    if C_Timer and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, delay, fn)
        if ok then return end
    end
    if not timerFrame then
        timers = {}
        timerFrame = CreateFrame("Frame")
        timerFrame:SetScript("OnUpdate", function(_, elapsed)
            for i = #timers, 1, -1 do
                local t = timers[i]
                t.left = t.left - (elapsed or 0)
                if t.left <= 0 then
                    table.remove(timers, i)
                    pcall(t.fn)
                end
            end
        end)
    end
    timers[#timers + 1] = { left = delay or 0, fn = fn }
end

-- Run fn once after delay, however often it is asked for meanwhile (GF-001-D11:
-- a burst of guild messages must not redraw a page once per message).
local coalesced = {}
function ns.coalesce(key, delay, fn)
    if coalesced[key] then return end
    coalesced[key] = true
    ns.after(delay, function()
        coalesced[key] = nil
        fn()
    end)
end

-- CreateFrame with a Blizzard template; if the template is missing on this
-- client, build a plain frame instead of failing to load.
-- An opaque dark background and a thin border drawn by the toolkit itself
-- (GF-001-D20). The client's BasicFrameTemplateWithInset can come out see-
-- through, so 同步與診斷 was unreadable over the roster. Also keeps the
-- template's close button inside the frame. Safe to call twice.
ns.OPAQUE_COLOR = { 0.05, 0.07, 0.06, 0.97 }
ns.BORDER_COLOR = { 0.32, 0.52, 0.42, 1 }

-- GF-UI-B (GF-UI-A §1.8): the toolkit's colours, in one place. Pages use
-- these names instead of their own numbers.
ns.COLOR = {
    gold = { 1, 0.82, 0 },            -- field names, titles, the chosen name, today
    white = { 1, 1, 1 },              -- content
    muted = { 0.72, 0.72, 0.72 },     -- not chosen, secondary professions
    disabled = { 0.5, 0.5, 0.5 },     -- cannot be used, ended, offline
    good = { 0.25, 1, 0.35 },         -- online, 成行, I signed up
    formed = { 0.3, 0.9, 0.85 },      -- 成團
    warn = { 1, 0.55, 0.15 },         -- 未成行, 待驗收 ?, test orders
    bad = { 1, 0.25, 0.25 },          -- errors, too high a level
    brand = { 0.13, 0.37, 0.30 },     -- only the column header bar and the module list
    frame = ns.OPAQUE_COLOR,          -- window background
    stripe = { 1, 1, 1, 0.04 },       -- every second list row
}
function ns.setTextColor(fs, name)
    local c = ns.COLOR[name] or ns.COLOR.white
    if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end

-- The zebra background of list row i (GF-UI-A §1.5: one look on every page).
function ns.stripe(tex, i)
    local c = ns.COLOR.stripe
    tex:SetColorTexture(c[1], c[2], c[3], (i or 1) % 2 == 0 and c[4] or 0)
end

-- GF-UI-B (GF-UI-A §1.5): the chosen list row. The quest log's title glow in
-- gold (ADD) and a 3 px gold bar on the left; never a flat yellow block.
-- Both are textures of the row itself, in its BACKGROUND layer above the
-- stripe, so the row's text stays on top. Returns { glow, bar } with
-- Show() / Hide() / IsShown().
ns.ROW_SELECT_ALPHA, ns.ROW_SELECT_BAR = 0.55, 3
function ns.rowSelect(row)
    if row.gfRowSelect then return row.gfRowSelect end
    local gold = ns.COLOR.gold
    local glow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    glow:SetAllPoints(row)
    local hasGlow = ns.GameIcons and ns.GameIcons.set(glow, "row_select")
    if hasGlow then
        if glow.SetBlendMode then glow:SetBlendMode("ADD") end
        if glow.SetVertexColor then glow:SetVertexColor(gold[1], gold[2], gold[3]) end
        glow:SetAlpha(ns.ROW_SELECT_ALPHA)
    end
    local bar = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(ns.ROW_SELECT_BAR)
    bar:SetColorTexture(gold[1], gold[2], gold[3], 1)
    local sel = { glow = glow, bar = bar, shown = false }
    function sel.Show(self)
        self.shown = true
        if hasGlow then glow:Show() else glow:Hide() end
        bar:Show()
    end
    function sel.Hide(self)
        self.shown = false
        glow:Hide(); bar:Hide()
    end
    function sel.IsShown(self) return self.shown end
    sel:Hide()
    row.gfRowSelect = sel
    return sel
end
function ns.makeOpaque(f, inset)
    if not f or f.gfOpaque then return f end
    inset = inset or 2
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    local c = ns.OPAQUE_COLOR
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    local b = ns.BORDER_COLOR
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, e in ipairs(edges) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetPoint(e[1], f, e[1], 0, 0)
        t:SetPoint(e[2], f, e[2], 0, 0)
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        t:SetColorTexture(b[1], b[2], b[3], b[4])
    end
    local close = f.CloseButton
    if type(close) == "table" and close.ClearAllPoints then
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    end
    f.gfOpaque = bg
    return f
end

-- GameTooltip just above owner, x px from its left edge (GF-001-D21: a
-- recipe tooltip anchored to the far right of a 930 px row ended up in the
-- screen corner). The client keeps GameTooltip on screen.
function ns.tooltipAbove(owner, x)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", x or 0, 2)
end

-- A popup window above the toolkit window: opaque, framed, raised on show.
-- GF-002-D: the order, fee, paste, adventure-ticket and worker windows are
-- exclusive: showing one hides the others (and any open menu).
local exclusive = {}
function ns.exclusivePopup(f)
    exclusive[#exclusive + 1] = f
    f.gfEscLevel = ns.ESC_LEVEL.popup
    if f.HookScript then
        f:HookScript("OnShow", function(self)
            for _, other in ipairs(exclusive) do
                if other ~= self and other:IsShown() then other:Hide() end
            end
            if ns.Framework and ns.Framework.closeMenu then ns.Framework.closeMenu() end
            if ns.onExclusiveShow then pcall(ns.onExclusiveShow, self) end
        end)
    end
    return f
end
function ns.exclusivePopups() return exclusive end

-- GF-002-E (owner, 0.12.2: 「目的/地」「現/在」 broke onto two lines): names
-- and field names have no fixed width and never wrap; the layout measures
-- them. labelWidth is an upper estimate at the normal font (16 px a Chinese
-- character, 8 for ASCII), used when the client cannot measure yet.
-- GF-002-F (owner: 「字還有圖都要再大」): 16 px text, 18 px titles. The
-- toolkit's own font objects copy the game's fonts and only change the size;
-- without CreateFont the game's Large fonts are used.
ns.TEXT_SIZE, ns.TITLE_SIZE = 16, 18
local function makeFont(name, base, size)
    if type(CreateFont) ~= "function" then return nil end
    local ok, f = pcall(CreateFont, name)
    if not ok or not f then return nil end
    local src = _G[base]
    if src and f.CopyFontObject then pcall(f.CopyFontObject, f, src) end
    local path, flags
    if src and src.GetFont then local p, _, fl = src:GetFont(); path, flags = p, fl end
    if path and f.SetFont then pcall(f.SetFont, f, path, size, flags or "") end
    return name
end
ns.LABEL_FONT = makeFont("GreenFangToolkitText16", "GameFontHighlight", 16) or "GameFontHighlightLarge"
ns.FIELD_FONT = makeFont("GreenFangToolkitField16", "GameFontNormal", 16) or "GameFontNormalLarge"
ns.DISABLED_FONT = makeFont("GreenFangToolkitDisabled16", "GameFontDisable", 16) or "GameFontDisableLarge"
ns.TITLE_FONT = makeFont("GreenFangToolkitTitle18", "GameFontNormal", 18) or "GameFontNormalLarge"
-- Sizes (GF-002-F): clickable icons, dungeon icons, page rows, window rows.
ns.ICON, ns.ROW_ICON, ns.DUNGEON_ICON, ns.PAGE_ROW, ns.WINDOW_ROW, ns.BUTTON_H = 32, 28, 48, 36, 52, 30
local function plainText(text)
    return (tostring(text or ""):gsub("|T.-|t", "\1\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
function ns.labelWidth(text)
    local w = 0
    for ch in plainText(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        w = w + (ch == "\1" and 10 or #ch == 1 and 9 or 17)
    end
    return w + 6
end
-- The width a FontString needs: what the client measures; the estimate
-- when it cannot measure yet (0 before the font is ready).
function ns.measure(fs)
    if not fs then return 0 end
    local w = ns.num((fs:GetStringWidth())) or 0
    if w > 0 then return w end
    return ns.labelWidth(fs:GetText())
end
-- GF-UI-B: the height a wrapped FontString takes at width w (what the
-- client measures; an estimate of 20 px a line when it cannot yet).
function ns.textHeight(fs, w)
    if not fs then return 0 end
    local h = ns.num((fs.GetStringHeight and fs:GetStringHeight()))
    if h and h > 0 then return h end
    -- GF-UI-C: every line break starts a new line too.
    local lines = 0
    for part in (tostring(fs:GetText() or "") .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(ns.labelWidth(part) / math.max(1, w or 1)))
    end
    return math.max(1, lines) * 20
end
-- A text that sizes itself to its content: no width, one line.
function ns.freeText(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    return fs
end

---------------------------------------------------------------------------
-- GF-002-E (owner: 「所有子視窗如果壓 ESC 應該都是退回或關掉」): ESC closes
-- the top window first: a menu, the dungeon grid, the popup, 同步與診斷 /
-- export, and only then the main window. The client's CloseSpecialWindows
-- hides every UISpecialFrames frame at once, so only one hidden catcher
-- frame is listed there; it is shown while any window of ours is, and when
-- the client hides it, it closes the top window and comes back if more are
-- open. ESC therefore never opens the game menu while a window is open.
---------------------------------------------------------------------------
ns.ESC_NAME = "GreenFangToolkit_Escape"
ns.ESC_LEVEL = { window = 1, panel = 2, popup = 3, grid = 4, menu = 5 }
local escFrames, escSeq, escCatcher = {}, 0, nil

local function anyOpen()
    for _, f in ipairs(escFrames) do if f:IsShown() then return true end end
    return false
end
ns.escAnyOpen = anyOpen

local function catcher()
    if escCatcher then return escCatcher end
    local c = CreateFrame("Frame", ns.ESC_NAME, UIParent)
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    c:Hide()
    c:SetScript("OnHide", function(self)
        if self.quiet then self.quiet = nil; return end
        ns.escape()
        if anyOpen() then ns.after(0, function() if anyOpen() and not self:IsShown() then self:Show() end end) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, ns.ESC_NAME) end
    escCatcher = c
    return c
end

---------------------------------------------------------------------------
-- GF-002-F (owner: 「次選單如果在其他地方按左鍵，應該也要消掉」): while a
-- menu, list or the destination picker is open, a transparent full-screen
-- button lies just under it; a click anywhere else lands on it and closes
-- them (the click does nothing else, as with the game's own drop-downs).
---------------------------------------------------------------------------
ns.BLOCKER_NAME = "GreenFangToolkit_ClickOutside"
local blocker
local function isMenu(f) return (f.gfEscLevel or 0) >= ns.ESC_LEVEL.grid end
function ns.menusOpen()
    for _, f in ipairs(escFrames) do if isMenu(f) and f:IsShown() then return true end end
    return false
end
function ns.closeMenus()
    for _, f in ipairs(escFrames) do if isMenu(f) and f:IsShown() then f:Hide() end end
end
local function updateBlocker()
    if not blocker then
        if not ns.menusOpen() then return end
        blocker = CreateFrame("Button", ns.BLOCKER_NAME, UIParent)
        blocker:SetAllPoints(UIParent)
        blocker:SetFrameStrata("TOOLTIP")
        if blocker.SetFrameLevel then blocker:SetFrameLevel(1) end
        blocker:EnableMouse(true)
        if blocker.RegisterForClicks then blocker:RegisterForClicks("AnyUp") end
        blocker:SetScript("OnClick", function() ns.closeMenus() end)
        blocker:Hide()
    end
    if ns.menusOpen() then
        if not blocker:IsShown() then blocker:Show() end
    elseif blocker:IsShown() then
        blocker:Hide()
    end
end
function ns.clickBlocker() return blocker end

function ns.escRegister(f, level)
    if not f or f.gfEscRegistered then return f end
    f.gfEscLevel = f.gfEscLevel or level or ns.ESC_LEVEL.panel
    f.gfEscRegistered = true
    escFrames[#escFrames + 1] = f
    if f.HookScript then
        f:HookScript("OnShow", function(self)
            escSeq = escSeq + 1
            self.gfEscSeq = escSeq
            local c = catcher()
            if not c:IsShown() then c:Show() end
            if isMenu(self) then updateBlocker() end
        end)
        f:HookScript("OnHide", function(self)
            if escCatcher and escCatcher:IsShown() and not anyOpen() then
                escCatcher.quiet = true
                escCatcher:Hide()
            end
            if isMenu(self) then updateBlocker() end
        end)
    end
    if f:IsShown() then
        local c = catcher(); if not c:IsShown() then c:Show() end
        if isMenu(f) then updateBlocker() end
    end
    return f
end

-- The window ESC closes next: the highest level, the last shown among equals.
function ns.escTop()
    local best
    for _, f in ipairs(escFrames) do
        if f:IsShown() then
            if not best or f.gfEscLevel > best.gfEscLevel
                or (f.gfEscLevel == best.gfEscLevel and (f.gfEscSeq or 0) > (best.gfEscSeq or 0)) then best = f end
        end
    end
    return best
end
function ns.escape()
    local f = ns.escTop()
    if f then f:Hide() end
    return f
end
function ns.escCatcher() return escCatcher end

function ns.popupWindow(name, w, h)
    local f = ns.createFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    ns.makeOpaque(f)
    if f.HookScript then f:HookScript("OnShow", function(self) if self.Raise then self:Raise() end end) end
    -- Title in the larger font (owner: 「字清楚一點」).
    if f.TitleText and f.TitleText.SetFontObject then f.TitleText:SetFontObject(ns.TITLE_FONT) end
    ns.escRegister(f, ns.ESC_LEVEL.panel)
    return f
end

function ns.createFrame(kind, name, parent, template)
    if template then
        local ok, frame = pcall(CreateFrame, kind, name, parent, template)
        if ok and frame then return frame end
    end
    local frame = CreateFrame(kind, name, parent)
    frame.gfNoTemplate = template
    if kind == "Button" and frame.SetNormalFontObject then
        pcall(frame.SetNormalFontObject, frame, "GameFontNormal")
    elseif template == "BasicFrameTemplateWithInset" then
        -- Minimal stand-in: dark background, title and a close button.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.07, 0.06, 0.92)
        frame.TitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.TitleText:SetPoint("TOP", frame, "TOP", 0, -6)
        local close = CreateFrame("Button", nil, frame)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -2)
        pcall(close.SetNormalFontObject, close, "GameFontNormal")
        close:SetText("X")
        close:SetScript("OnClick", function() frame:Hide() end)
    end
    return frame
end

function ns.shortName(value)
    local name = ns.str(value)
    return name:match("^([^-]+)") or name
end

function ns.keyName(value) return ns.str(value):lower() end

function ns.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = ns.copy(v) end
    return out
end

-- ns.combatFlag is set at PLAYER_REGEN_DISABLED, when InCombatLockdown() is
-- still false (Framework.lua, GF-001-D8).
function ns.inCombat()
    if ns.combatFlag then return true end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

function ns.now() return time() end

function ns.localTime(t)
    if not (date and t) then return "" end
    local ok, result = pcall(date, "%Y-%m-%d %H:%M:%S", t)
    return ok and type(result) == "string" and result or ""
end

function ns.utcTime(t)
    if not (date and t) then return "" end
    local ok, result = pcall(date, "!%Y-%m-%dT%H:%M:%SZ", t)
    return ok and type(result) == "string" and result or ""
end

-- Key used to keep one display snapshot per guild on this account.
-- Is this the guild the toolkit serves (ns.Config.guild)?
function ns.isTargetGuild(guild, realm)
    local target = ns.Config.guild
    if ns.str(guild) == "" or guild ~= target.name then return false end
    if target.realm ~= nil and realm ~= target.realm then return false end
    return true
end

function ns.targetGuildName() return ns.Config.guild.name end

-- Guild state of the logged-in character, straight from the client:
--   "target"  in ns.Config.guild
--   "other"   in another guild (or the right name on another realm)
--   "loading" the client says "in a guild" but has no name yet
--   "none"    not in a guild
-- Returns state, guildName.
function ns.guildState()
    local guild = ns.str((ns.call(GetGuildInfo, "player")))
    if guild == "" then
        if ns.isInGuild() then return "loading", nil end
        return "none", nil
    end
    local realm = ns.realm()
    if ns.isTargetGuild(guild, realm) then return "target", guild end
    return "other", guild
end

function ns.guildKey(realm, guild)
    return ns.str(realm) .. "|" .. ns.str(guild)
end

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

-- Fill in every field schema v2 needs without discarding anything we do not know.
function ns.initDB()
    local fresh = type(GreenFangToolkitDB) ~= "table"
    if fresh then GreenFangToolkitDB = {} end
    local db = GreenFangToolkitDB
    db.schema = ns.SCHEMA
    db.schemaVersion = ns.SCHEMA_VERSION
    db.addonVersion = ns.VERSION
    local settings = ensureTable(db, "settings")
    if settings.minimapLayoutVersion ~= 2 then
        settings.minimapAngle = ns.DEFAULT_MINIMAP_ANGLE
        settings.minimapLayoutVersion = 2
    end
    local roster = ensureTable(db, "roster")
    ensureTable(roster, "snapshots")
    local sync = ensureTable(db, "sync")
    -- D-015: no switch. Always true (GF Sync still checks it); an old false is dropped.
    sync.enabled = true
    if type(sync.noticeShown) ~= "boolean" then sync.noticeShown = false end
    -- D-015: location is always shared; the old switch is cleared.
    sync.shareLocation = nil
    ensureTable(sync, "outbox")
    ns.db = db
    return db, fresh
end

-- Fields copied from the v0.3.1 member table. Everything else is dropped.
local LEGACY_MEMBER_FIELDS = {
    "name", "race", "raceID", "raceSource", "class", "classToken", "professions",
    "professionSource", "level", "zone", "online", "guildRank", "guid",
}

-- Copy settings and the last snapshot from GFGuildRosterDB. The old table is
-- left exactly as it is. SavedVariables of an addon only exist while that addon
-- is enabled, so this is retried on every login until it has run once.
-- Existing v2 values always win over legacy ones.
function ns.migrateLegacy()
    local db = ns.db
    if not db or type(db.migration) == "table" then return false end
    local old = GFGuildRosterDB
    if type(old) ~= "table" then return false end
    local oldSettings = type(old.settings) == "table" and old.settings or {}
    local settings = db.settings
    for _, key in ipairs({ "sortKey", "sortAscending" }) do
        if settings[key] == nil and oldSettings[key] ~= nil then
            settings[key] = oldSettings[key]
        end
    end
    -- v0.3.1 already used the outer-rim layout (minimapLayoutVersion 2). Only take
    -- its angle while ours is still the untouched default.
    if oldSettings.minimapLayoutVersion == 2 and type(oldSettings.minimapAngle) == "number"
        and settings.minimapAngle == ns.DEFAULT_MINIMAP_ANGLE then
        settings.minimapAngle = oldSettings.minimapAngle
    end
    local copied = 0
    if type(old.members) == "table" and #old.members > 0 and ns.str(old.guild) ~= "" then
        local key = ns.guildKey(old.realm, old.guild)
        local current = db.roster.snapshots[key]
        local oldAt = type(old.capturedAt) == "number" and old.capturedAt or 0
        if not current or (current.capturedAt or 0) < oldAt then
            local members = {}
            for _, m in ipairs(old.members) do
                if type(m) == "table" and type(m.name) == "string" then
                    local nm = {}
                    for _, f in ipairs(LEGACY_MEMBER_FIELDS) do nm[f] = ns.copy(m[f]) end
                    members[#members + 1] = nm
                end
            end
            db.roster.snapshots[key] = {
                guild = old.guild,
                realm = ns.str(old.realm),
                capturedAt = type(old.capturedAt) == "number" and old.capturedAt or nil,
                capturedAtUTC = ns.str(old.capturedAtUTC),
                capturedAtLocal = ns.str(old.capturedAtLocal),
                total = type(old.total) == "number" and old.total or #members,
                online = type(old.online) == "number" and old.online or 0,
                members = members,
                source = "GFGuildRosterDB",
            }
            if not db.roster.lastKey then db.roster.lastKey = key end
            copied = #members
        end
    end
    db.migration = { from = "GFGuildRosterDB", fromVersion = old.version, at = ns.now(), members = copied }
    return true, copied
end

function ns.settings()
    return ns.db and ns.db.settings or {}
end
