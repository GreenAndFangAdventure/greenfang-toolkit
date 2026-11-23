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
function ns.popupWindow(name, w, h)
    local f = ns.createFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    ns.makeOpaque(f)
    if f.HookScript then f:HookScript("OnShow", function(self) if self.Raise then self:Raise() end end) end
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
