-- Init: events, timers and slash commands. Loaded last.

local _, ns = ...
local Sync, Roster, UI, Comm, Share = ns.Sync, ns.Roster, ns.UI, ns.Comm, ns.Share
local Orders, Prices, Delivery, Ledger = ns.Orders, ns.Prices, ns.Delivery, ns.Ledger

-- GF-006-B: order and price ledgers start a while after the D-014 sharing.
local ORDERS_DELAY, PRICES_DELAY, MAINTAIN_EVERY = 30, 120, 60
local ADVENTURE_DELAY = 35 -- GF-002-B

local scanQueued, selfQueued, loginSelfRecorded = false, false, false
local loginAt = 0
-- How long the login character.self waits for guild info before giving up
-- (a guildless character, or info that never came; nothing is written then).
local GUILD_WAIT = 30
-- PLAYER_GUILD_UPDATE this long after login with no guild = really left.
local LEAVE_SETTLE = 30

local recordSelfNow -- defined below

local function collectSoon(delay)
    if scanQueued then return end
    scanQueued = true
    ns.after(delay or 0.8, function()
        scanQueued = false
        local ok, count = Roster.collect()
        if ok then
            UI.afterAutoScan(count)
            -- GF-001-D24: the roster gives the full name; write the login entry now.
            if not loginSelfRecorded then recordSelfNow() end
            -- Guild confirmed and roster loaded: share own data (D-011).
            Comm.broadcast(false)
            -- D-014 sharing: once per session, a while after login.
            if not ns.shareStarted and ns.now() - loginAt >= Share.LOGIN_DELAY then
                ns.shareStarted = Share.login()
            end
            -- GF-006-B: orders (GFTKO) and shared prices (GFTKP), later and slower.
            if not ns.ordersStarted and ns.now() - loginAt >= ORDERS_DELAY then
                ns.ordersStarted = Orders.ledger:announce()
                -- GF-006-C (R-9.4): web orders GF Sync left in GreenFangToolkit_Inbox.
                if ns.ordersStarted then pcall(ns.WebOrders.readInbox) end
                Delivery.checkPending()
            end
            -- GF-002-B: adventure tickets (GFTKA); my tickets that should have closed while I was away.
            if not ns.adventureStarted and ns.now() - loginAt >= ADVENTURE_DELAY then
                ns.adventureStarted = ns.Adventure.ledger:announce()
                if ns.adventureStarted then pcall(ns.Adventure.onLogin) end
            end
            if not ns.pricesStarted and ns.now() - loginAt >= PRICES_DELAY then
                ns.pricesStarted = Prices.login()
            end
        end
    end)
end

-- The first character.self of a session is always written (one per login);
-- later ones only when level, race, class, guild or professions changed.
-- final = true at the end of the guild wait and at logout: stop waiting for
-- guild info (the session's guild is used whenever there is one). Only
-- TARGET_GUILD characters are ever written (Sync.recordSelf).
function recordSelfNow(final)
    local allowNoGuild = final or loginSelfRecorded or (ns.now() - loginAt >= GUILD_WAIT)
    local entry, reason = Sync.recordSelf(not loginSelfRecorded,
        { allowNoGuild = allowNoGuild, waitFullName = not allowNoGuild })
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

-- Test builds ("dev" or a version with a suffix such as 0.11.0-beta1) only.
function ns.isTestBuild() return ns.VERSION == "dev" or ns.VERSION:find("-", 1, true) ~= nil end

local function handleSlash(msg)
    local text = ns.str(msg):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = text:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "" or cmd == "show" then
        ns.Framework.toggle()
    elseif cmd == "sync" then
        Sync.command(rest)
    elseif cmd == "orders" and rest:match("^days") then
        -- GF-006-B (R-6.9): reminder days, shown in 同步與診斷.
        local a, b, c = rest:match("^days%s+(%d+)%s+(%d+)%s+(%d+)")
        if Orders.setStaleDays(a, b, c) then ns.Diag.open() else help() end
    elseif cmd == "orders" and rest:match("^shift") and ns.isTestBuild() then
        -- Test builds only (spec §12 item 5).
        local days = tonumber(rest:match("^shift%s+(%-?%d+)")) or 0
        Orders.local_().debugShift = days * 86400
        ns.Diag.open()
    elseif cmd == "prices" and rest:match("^fake") and ns.isTestBuild() then
        local id, copper = rest:match("^fake%s+(%d+)%s+(%d+)")
        Prices.fake(id, copper)
        ns.Diag.open()
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
        -- GF-006-B: new prefixes; 0.10.0 never registers them (spec §12 item 10).
        Orders.ledger:register()
        ns.Adventure.ledger:register()
        Prices.ledger:register()
        Delivery.install()
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
        ns.after(ORDERS_DELAY + 1, function() collectSoon(0) end)
        ns.after(ADVENTURE_DELAY + 1, function() collectSoon(0) end)
        ns.after(PRICES_DELAY + 1, function() collectSoon(0) end)
        -- GF-006-B: lock guild orders, move closed rows to history, badge.
        local function maintain()
            if ns.guildState() == "target" then
                pcall(Orders.maintain)
                if ns.adventureStarted then pcall(ns.Adventure.maintain) end
                if ns.AdventureUI then pcall(ns.AdventureUI.updateBadge) end
                if ns.OrdersUI then pcall(ns.OrdersUI.updateBadge) end
            end
            ns.after(MAINTAIN_EVERY, maintain)
        end
        -- Review 3-3: after the first catalog round, not before.
        ns.after(ORDERS_DELAY + 30, maintain)
        collectSoon(5)
        selfSoon(5)
        ns.after(GUILD_WAIT + 1, function()
            if not loginSelfRecorded then recordSelfNow(true) end
        end)
    elseif event == "PLAYER_LOGOUT" then
        -- Last chance before the client writes SavedVariables.
        -- D-015: always written as true (GF Sync skips the file otherwise).
        if ns.db.sync then ns.db.sync.enabled = true end
        -- GF-002-B (R-4.7): when I left, for my "now" tickets.
        if ns.Adventure then pcall(ns.Adventure.onLogout) end
        if not ns.inCombat() then
            recordSelfNow(not loginSelfRecorded)
            -- Phase 4 (GF-001-D14): relayed data and recipe names for the site.
            Sync.recordShares()
            Sync.recordRecipeNames()
        end
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == Share.PREFIX then Share.onMessage(arg1, arg2, arg3, arg4)
        elseif not Ledger.dispatch(arg1, arg2, arg3, arg4) then Comm.onMessage(arg1, arg2, arg3, arg4) end
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
            -- GF-001-D24: guild info arrived; the scan gives the full name.
            if not loginSelfRecorded and ns.isInGuild() then collectSoon(0.8) end
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

---------------------------------------------------------------------------
-- GF-006-B: trade, mail, merchant and auction house events. Registered one
-- by one under pcall: an event the client does not know (16001 not
-- verified) is skipped and listed in 同步與診斷 (R-7.5).
---------------------------------------------------------------------------

local orderEvents = CreateFrame("Frame")
ns.orderEventFrame = orderEvents
ns.missingEvents = {}
for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED",
    "TRADE_TARGET_ITEM_CHANGED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
    "BAG_UPDATE_DELAYED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_INBOX_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "QUEST_LOG_UPDATE", "QUEST_REMOVED",
    "QUEST_TURNED_IN" }) do
    local ok = pcall(orderEvents.RegisterEvent, orderEvents, e)
    if not ok then ns.missingEvents[#ns.missingEvents + 1] = e end
end

orderEvents:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not ns.db or ns.guildState() ~= "target" then return end
    if event == "TRADE_SHOW" then Delivery.onTradeShow()
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then Delivery.snapshot()
    elseif event == "TRADE_ACCEPT_UPDATE" then Delivery.onAccept(arg1, arg2)
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then Delivery.onInfoMessage(arg1, arg2)
    elseif event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then
        Delivery.onTradeClosed()
        if ns.OrdersUI then ns.OrdersUI.tradeHidden() end
    elseif event == "BAG_UPDATE_DELAYED" then Delivery.onBagsSettled()
    elseif event == "MAIL_SEND_SUCCESS" then Delivery.onMailSent()
    elseif event == "MAIL_FAILED" then Delivery.onMailFailed()
    elseif event == "MAIL_INBOX_UPDATE" then Delivery.onInboxUpdate()
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then Prices.readMerchant()
    elseif event == "AUCTION_HOUSE_SHOW" then Prices.onAuctionShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then Prices.onAuctionClosed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then Prices.onReplicate()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        Prices.onBrowseResults()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        Prices.onSearchResult(arg1)
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        -- GF-002-B (R-5.2): quests that left my log come off my worker ticket.
        ns.coalesce("adventure-quests", 2, function()
            local log = ns.Adventure.questLog()
            if log then pcall(ns.Adventure.syncQuests, log) end
        end)
    end
end)
