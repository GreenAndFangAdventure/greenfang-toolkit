-- GF-009-12: /gftk catalogscan — owner only, off unless typed, not in /gftk's
-- help. Asks this client about the ItemIDs the catalog export has no name for
-- (SupplyCatalog.scanIDs) and keeps the client's answers in
-- GreenFangToolkitDB.devCatalogScan, so that scripts/build_item_catalog.py
-- --scan can merge them into the next catalog. Members never run it; releases
-- ship only the merged catalog.
--
-- Kept per item: zhTW name, classID, subclassID, bindType, quality, item level,
-- icon. Nothing about characters, no GUIDs.
-- Throttle as GF-009-11: one request every 0.25 s (4 per second), at most 8
-- waiting, paused in combat and inside instances; 30 s without an answer is a
-- timeout (2 retries, then counted as no answer). Resumes after login.
--
--   /gftk catalogscan          progress
--   /gftk catalogscan start    start or continue
--   /gftk catalogscan stop     stop (progress is kept)
--   /gftk catalogscan reset    forget the results
local _, ns = ...
local S = {}
ns.CatalogScan = S

S.TICK = 0.25
S.INFLIGHT = 8
S.TIMEOUT = 30
S.RETRIES = 2
S.START_DELAY = 60
S.PAUSED_RETRY = 5

local ids             -- the scan list, decoded once
local inflight = {}   -- [id] = { t = asked at, tries }
local retry = {}      -- ids to ask again (head index below; no table.remove)
local retryHead = 1
local looping = false
local stats = { asked = 0, answered = 0, timeouts = 0, paused = 0 }

local function list()
    if not ids then ids = ns.SupplyCatalog and ns.SupplyCatalog.scanIDs() or {} end
    return ids
end

function S.db(create)
    if type(ns.db) ~= "table" then return nil end
    local d = ns.db.devCatalogScan
    if type(d) ~= "table" and create then
        d = { v = 1, locale = ns.call(GetLocale), build = ns.SupplyCatalog and ns.SupplyCatalog.build() or nil,
            pos = 0, got = {}, none = {}, running = false }
        ns.db.devCatalogScan = d
    end
    return type(d) == "table" and d or nil
end

function S.inflightCount()
    local n = 0
    for _ in pairs(inflight) do n = n + 1 end
    return n
end

function S.paused()
    if ns.inCombat() then return "combat" end
    if type(IsInInstance) == "function" and ns.call(IsInInstance) then return "instance" end
    return nil
end

-- The client's answer for one item, or nil while it does not know it.
local function record(id)
    if type(GetItemInfo) ~= "function" then return nil end
    local okCall, name, _, quality, itemLevel, _, _, _, _, _, icon, _, classID, subclassID, bindType = pcall(GetItemInfo, id)
    if not okCall or type(name) ~= "string" or name == "" then return nil end
    return { name, tonumber(classID) or -1, tonumber(subclassID) or 0, tonumber(bindType) or 0,
        tonumber(quality) or 0, tonumber(itemLevel) or 0, tonumber(icon) or 0 }
end

local function ask(id)
    if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
        ns.call(C_Item.RequestLoadItemDataByID, id)
        return true
    end
    if type(GetItemInfo) == "function" then ns.call(GetItemInfo, id); return true end
    return false
end

local function nextID(d)
    if retry[retryHead] then
        local id = retry[retryHead]
        retry[retryHead] = nil
        retryHead = retryHead + 1
        return id
    end
    local l = list()
    while d.pos < #l do
        d.pos = d.pos + 1
        local id = l[d.pos]
        if d.got[id] == nil and d.none[id] == nil and not inflight[id] then return id end
    end
    return nil
end

function S.done(d)
    d = d or S.db()
    return d ~= nil and d.pos >= #list() and retry[retryHead] == nil and next(inflight) == nil
end

-- One tick: timeouts, then at most one request.
function S.step()
    local d = S.db()
    if not d or not d.running then return "stopped" end
    local why = S.paused()
    if why then stats.paused = stats.paused + 1; return why end
    local t = ns.now()
    for id, f in pairs(inflight) do
        if t - f.t > S.TIMEOUT then
            inflight[id] = nil
            stats.timeouts = stats.timeouts + 1
            if f.tries < S.RETRIES then
                retry[#retry + 1] = id
                S.tries = S.tries or {}
                S.tries[id] = f.tries + 1
            else
                d.none[id] = 1
            end
        end
    end
    if S.inflightCount() >= S.INFLIGHT then return "waiting" end
    local id = nextID(d)
    if not id then
        if S.done(d) then
            d.running, d.finished = false, ns.now()
            ns.say(S.statusText())
            return "finished"
        end
        return "waiting"
    end
    local r = record(id)
    if r then d.got[id] = r; return "known" end
    inflight[id] = { t = t, tries = S.tries and S.tries[id] or 0 }
    if not ask(id) then inflight[id] = nil; d.running = false; return "no-api" end
    stats.asked = stats.asked + 1
    return "asked"
end

-- GET_ITEM_INFO_RECEIVED (itemID, success).
function S.received(id, success)
    id = tonumber(id)
    if not id or not inflight[id] then return false end
    inflight[id] = nil
    local d = S.db()
    if not d then return false end
    stats.answered = stats.answered + 1
    local r = success ~= false and record(id) or nil
    if r then d.got[id] = r else d.none[id] = 1 end
    return true
end

local function loop()
    local result = S.step()
    if result == "stopped" or result == "finished" or result == "no-api" then looping = false; return end
    ns.after((result == "combat" or result == "instance") and S.PAUSED_RETRY or S.TICK, loop)
end
local function kick()
    if looping then return end
    looping = true
    ns.after(S.TICK, loop)
end
function S.looping() return looping end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function S.statusText()
    local d = S.db()
    local total = #list()
    if not d then return string.format("物品掃描：尚未開始（%d 個）", total) end
    local state = d.running and (S.paused() and "暫停中" or "執行中") or (S.done(d) and "完成" or "已停止")
    local left = math.max(0, total - d.pos) + S.inflightCount()
    return string.format("物品掃描：%s，%d／%d（有名稱 %d，沒有回應 %d），約剩 %d 分鐘", state, d.pos, total,
        count(d.got), count(d.none), math.ceil(left * S.TICK / 60))
end

function S.start()
    local d = S.db(true)
    if not d then return false end
    if S.done(d) and d.finished then ns.say(S.statusText()); return false end
    d.running = true
    kick()
    return true
end
function S.stop()
    local d = S.db()
    if d then d.running = false end
    return true
end
function S.reset()
    if type(ns.db) == "table" then ns.db.devCatalogScan = nil end
    inflight, retry, retryHead, S.tries = {}, {}, 1, nil
    return true
end

function S.command(rest)
    local sub = ns.str(rest):lower():match("^(%S*)")
    if sub == "start" then S.start()
    elseif sub == "stop" then S.stop()
    elseif sub == "reset" then S.reset() end
    ns.say(S.statusText())
end

function S.resetSession()
    ids, inflight, retry, retryHead, looping, S.tries = nil, {}, {}, 1, false, nil
    stats = { asked = 0, answered = 0, timeouts = 0, paused = 0 }
end
function S.stats() return stats end

if type(CreateFrame) == "function" then
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
    local resumed = false
    ev:SetScript("OnEvent", function(_, event, a, b)
        if event == "GET_ITEM_INFO_RECEIVED" then
            S.received(a, b)
        elseif not resumed then
            resumed = true
            local d = S.db()
            if d and d.running then ns.after(S.START_DELAY, kick) end
        end
    end)
end
