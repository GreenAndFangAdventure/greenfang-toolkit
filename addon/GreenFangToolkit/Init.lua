-- Init: events, timers and slash commands. Loaded last.

local _, ns = ...
local Sync, Roster, UI, Comm, Share = ns.Sync, ns.Roster, ns.UI, ns.Comm, ns.Share

local scanQueued, selfQueued, loginSelfRecorded = false, false, false
local loginAt = 0
-- How long the login character.self waits for guild info before giving up
-- (a guildless character, or info that never came; nothing is written then).
local GUILD_WAIT = 30
-- PLAYER_GUILD_UPDATE this long after login with no guild = really left.
local LEAVE_SETTLE = 30

local function collectSoon(delay)
    if scanQueued then return end
    scanQueued = true
    ns.after(delay or 0.8, function()
        scanQueued = false
        local ok, count = Roster.collect()
        if ok then
            UI.afterAutoScan(count)
            -- Guild confirmed and roster loaded: share own data (D-011).
            Comm.broadcast(false)
            -- D-014 sharing: once per session, a while after login.
            if not ns.shareStarted and ns.now() - loginAt >= Share.LOGIN_DELAY then
                ns.shareStarted = Share.login()
            end
        end
    end)
end

-- The first character.self of a session is always written (one per login);
-- later ones only when level, race, class, guild or professions changed.
-- final = true at the end of the guild wait and at logout: stop waiting for
-- guild info (the session's guild is used whenever there is one). Only
-- TARGET_GUILD characters are ever written (Sync.recordSelf).
local function recordSelfNow(final)
    local allowNoGuild = final or loginSelfRecorded or (ns.now() - loginAt >= GUILD_WAIT)
    local entry, reason = Sync.recordSelf(not loginSelfRecorded, { allowNoGuild = allowNoGuild })
    if entry or reason == "unchanged" then loginSelfRecorded = true end
    return entry, reason
end

local function selfSoon(delay)
    if selfQueued then return end
    selfQueued = true
    ns.after(delay or 2, function()
        selfQueued = false
        recordSelfNow()
    end)
end

local function help()
    ns.say("/gftk 或 /綠皮：開啟工具箱")
    local ids = {}
    for _, def in ipairs(ns.Framework.availableModules()) do ids[#ids + 1] = def.id end
    ns.say("/gftk <" .. table.concat(ids, "｜") .. ">：直接開啟該頁")
    ns.say("/gftk sync：查看同步狀態（開啟「同步與診斷」視窗）")
end

local function handleSlash(msg)
    local text = ns.str(msg):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = text:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "" or cmd == "show" then
        ns.Framework.toggle()
    elseif cmd == "sync" then
        Sync.command(rest)
    elseif ns.Framework.get(cmd) then
        ns.Framework.open(cmd)
    else
        help()
    end
end
ns.handleSlash = handleSlash

-- /gf is gone (D-014): GuildForge registers it too.
SLASH_GREENFANGTOOLKIT1 = "/gftk"
SLASH_GREENFANGTOOLKIT2 = "/綠皮"
SlashCmdList.GREENFANGTOOLKIT = handleSlash

local events = CreateFrame("Frame")
ns.eventFrame = events
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "GUILD_ROSTER_UPDATE",
    "INITIAL_CLUBS_LOADED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "PLAYER_GUILD_UPDATE", "CHAT_MSG_ADDON", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 ~= ns.ADDON then return end
        ns.initDB()
        ns.migrateLegacy()
        Sync.purgeForeign()
        Comm.register()
        Share.register()
        UI.loadSettings()
        return
    end
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        -- GFGuildRoster may load after us; every addon is loaded by now.
        if ns.migrateLegacy() then UI.loadSettings() end
        ns.Framework.createMinimapButton()
        ns.after(3, Sync.showNoticeOnce)
        ns.after(2, Roster.request)
        loginAt = ns.now()
        ns.after(Share.LOGIN_DELAY + 1, function() collectSoon(0) end)
        collectSoon(5)
        selfSoon(5)
        ns.after(GUILD_WAIT + 1, function()
            if not loginSelfRecorded then recordSelfNow(true) end
        end)
    elseif event == "PLAYER_LOGOUT" then
        -- Last chance before the client writes SavedVariables.
        -- D-015: always written as true (GF Sync skips the file otherwise).
        if ns.db.sync then ns.db.sync.enabled = true end
        if not ns.inCombat() then
            recordSelfNow(not loginSelfRecorded)
            -- Phase 4 (GF-001-D14): relayed data and recipe names for the site.
            Sync.recordShares()
            Sync.recordRecipeNames()
        end
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == Share.PREFIX then Share.onMessage(arg1, arg2, arg3, arg4)
        else Comm.onMessage(arg1, arg2, arg3, arg4) end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Share.ownChanged(true)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        ns.Recipes.scanSoon()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.onCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.onCombatEnd()
        -- Put the profession buttons back (they were hidden for combat).
        if ns.Character and ns.Framework.isModuleShown("character") then ns.Character.refresh() end
        if ns.Framework.isModuleShown("roster") then UI.placeOwnButtons() end
        if Roster.queuedAfterCombat then Roster.queuedAfterCombat = false; collectSoon(0.8) end
        if Sync.pendingSelf then selfSoon(1) end
    elseif event == "GUILD_ROSTER_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        collectSoon(0.8)
    elseif event == "PLAYER_GUILD_UPDATE" then
        ns.after(2, function()
            -- Joined, left or rank changed. Only drop the remembered guild once
            -- login has settled; early in login "no guild" is just not loaded.
            local guid = ns.Data.player().guid
            if not ns.isInGuild() and ns.now() - loginAt >= LEAVE_SETTLE then Sync.forgetGuild(guid) end
            recordSelfNow()
            if ns.Framework.isModuleShown("roster") then UI.refresh(true) end
        end)
    elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" then
        selfSoon(2)
        ns.after(3, function() Comm.broadcast(false) end)
        Share.ownChanged()
        if ns.Character and ns.Framework.isModuleShown("character") then
            ns.after(1, ns.Character.refresh)
        end
    end
end)
