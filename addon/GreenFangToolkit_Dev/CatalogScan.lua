-- GF-009-13: the owner's item name scan, as a separate dev-only AddOn
-- (GreenFangToolkit_Dev). It is not in the guild release: build_release.py
-- packs only the main TOC's files and .pkgmeta ignores this folder. Members
-- never see /gftkdev.
--
-- Asks this game client about ItemIDs the catalog export has no name for
-- (CatalogScanData.lua) and keeps the client's answers in its own
-- SavedVariables, GreenFangToolkitDevDB, for
-- scripts/build_item_catalog.py --scan.
--
--   /gftkdev catalogscan             progress
--   /gftkdev catalogscan sample      about 20 IDs: success, invalid ID, timeout
--   /gftkdev catalogscan report      the sample's result per ID
--   /gftkdev catalogscan full        the whole list (paused: FULL_ENABLED)
--   /gftkdev catalogscan stop        stop (progress is kept)
--   /gftkdev catalogscan reset       forget all results
--
-- Kept per item: zhTW name, classID, subclassID, bindType, quality, item
-- level, icon. Nothing about characters, no GUIDs.
-- Before it starts or resumes, the game's locale and build must be the ones
-- the list was made from (and the ones a saved run was made with).
-- Throttle: one request every 0.25 s (4 per second), at most 8 waiting,
-- paused in combat and inside instances. 30 s without an answer is a timeout:
-- 2 retries, then the ID counts as timed out. Waiting and retry IDs are saved
-- (pending) and asked again after the next login.
-- Counts (saved with the run): requests sent, GET_ITEM_INFO_RECEIVED events
-- (all, and those for our IDs), success, failed, invalid, timeouts, retries.
-- GF-009-13 fix (Forever 0.16.4 sample: 0 successes, 39 events, none ours):
-- C_Item.RequestLoadItemDataByID answers with ITEM_DATA_LOAD_RESULT, not
-- GET_ITEM_INFO_RECEIVED. Both are listened to and counted apart (loads);
-- waiting IDs are also polled (IsItemDataCachedByID, then GetItemInfo) every
-- tick; a retry asks through GetItemInfo
-- (the other path), so a client where one path is silent still gets there.
local _, D = ...
local S = {}
D.CatalogScan = S

S.SCHEMA = 2
S.TICK = 0.25
S.INFLIGHT = 8
S.TIMEOUT = 30
S.RETRIES = 2
S.START_DELAY = 60
S.PAUSED_RETRY = 5
-- GF-009-13 (claude-pm): the full scan is paused until the sample is checked
-- in Forever. Only the sample runs.
S.FULL_ENABLED = false
S.MODES = { sample = "catalogSample", full = "catalogScan" }

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local lists = {}       -- [mode] = sorted ItemIDs, decoded once
local inflight = {}    -- [id] = { t = asked at, tries }
-- Retry queue: head / tail positions (the length operator breaks once the
-- head has moved; no table.remove).
local retry, retryHead, retryTail = {}, 1, 0
local function push(id) retryTail = retryTail + 1; retry[retryTail] = id end
local restored = {}    -- [mode] = pending IDs put back in the retry queue
local looping = false
local active           -- the running mode this session

local function now()
    if type(GetTime) == "function" then return GetTime() end
    return time()
end
local function after(delay, fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(delay, fn) end
end
function S.say(text) print("|cff7fbf3fGF Dev|r " .. tostring(text)) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, table.maxn(res)) -- holes (the 16th value is nil on Forever)
end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

function S.unpack(s)
    local out, last = {}, 0
    if type(s) ~= "string" then return out end
    for gap in s:gmatch("[^,]+") do
        last = last + (tonumber(gap, 36) or 0)
        out[#out + 1] = last
    end
    return out
end
S.B36 = B36

function S.list(mode)
    if not lists[mode] then
        local data = D.scanData
        lists[mode] = S.unpack(type(data) == "table" and (mode == "sample" and data.sample or data.scan) or nil)
    end
    return lists[mode]
end

---------------------------------------------------------------------------
-- Saved runs
---------------------------------------------------------------------------

function S.clientBuild()
    local version, build = call(GetBuildInfo)
    if version == nil or build == nil then return nil end
    return tostring(version) .. "." .. tostring(build)
end
function S.clientLocale() return call(GetLocale) end

local function newRun(mode)
    return { v = S.SCHEMA, mode = mode, locale = S.clientLocale(), build = S.clientBuild(),
        list = D.scanData and D.scanData.build or nil, pos = 0, got = {}, invalid = {}, timeout = {}, pending = {},
        running = false, counts = { requests = 0, events = 0, ours = 0, success = 0, failed = 0, invalid = 0,
            timeouts = 0, retries = 0, known = 0, paused = 0 } }
end
function S.db(mode, create)
    local key = S.MODES[mode]
    if not key then return nil end
    if type(GreenFangToolkitDevDB) ~= "table" then
        if not create then return nil end
        GreenFangToolkitDevDB = {}
    end
    local d = GreenFangToolkitDevDB[key]
    if (type(d) ~= "table" or d.v ~= S.SCHEMA) and create then
        d = newRun(mode)
        GreenFangToolkitDevDB[key] = d
    end
    return type(d) == "table" and d.v == S.SCHEMA and d or nil
end

-- nil when this client may scan (and continue d), else why not.
function S.check(d)
    local data = D.scanData
    if type(data) ~= "table" or type(data.build) ~= "string" then return "沒有掃描清單" end
    local loc, build = S.clientLocale(), S.clientBuild()
    if loc ~= data.locale then
        return string.format("遊戲語系是 %s，掃描清單是 %s 的，不能掃描", tostring(loc), tostring(data.locale))
    end
    if build ~= data.build then
        return string.format("遊戲版本是 %s，掃描清單是 %s 的，要先重建清單", tostring(build), data.build)
    end
    if d and (d.build ~= build or d.locale ~= loc or d.list ~= data.build) then
        return string.format("存檔裡的掃描是 %s／%s 的結果，請先 /gftkdev catalogscan reset",
            tostring(d.build), tostring(d.locale))
    end
    return nil
end

---------------------------------------------------------------------------
-- The worker
---------------------------------------------------------------------------

function S.inflightCount() return count(inflight) end

function S.paused()
    if call(InCombatLockdown) then return "combat" end
    if call(IsInInstance) then return "instance" end
    return nil
end

local function cached(id)
    if type(C_Item) == "table" and type(C_Item.IsItemDataCachedByID) == "function" then
        return call(C_Item.IsItemDataCachedByID, id) and true or false
    end
    return nil -- unknown: GetItemInfo itself asks
end
local function exists(id)
    if type(C_Item) == "table" and type(C_Item.DoesItemExistByID) == "function" then
        return call(C_Item.DoesItemExistByID, id) ~= false
    end
    return true
end

-- GF-009-13 fix (Forever field probe): the client answers C_Item.GetItemInfo
-- (the classic 18 values) while the global GetItemInfo gives nothing, so the
-- scan saw no item at all, not even cached cloth. C_Item first, as
-- SupplyListings does.
function S.infoFn()
    if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then return C_Item.GetItemInfo end
    if type(GetItemInfo) == "function" then return GetItemInfo end
    return nil
end

-- The client's answer for one item, or nil while it does not know it.
local function record(id)
    local name, _, quality, itemLevel, _, _, _, _, _, icon, _, classID, subclassID, bindType = call(S.infoFn(), id)
    if type(name) ~= "string" or name == "" then return nil end
    return { name, tonumber(classID) or -1, tonumber(subclassID) or 0, tonumber(bindType) or 0,
        tonumber(quality) or 0, tonumber(itemLevel) or 0, tonumber(icon) or 0 }
end

local function ask(id)
    if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
        call(C_Item.RequestLoadItemDataByID, id)
        return true
    end
    return false
end

local function resolved(d, id) return d.got[id] ~= nil or d.invalid[id] ~= nil or d.timeout[id] ~= nil end

-- After a login, IDs that were waiting or due for a retry are asked again
-- first (their tries are kept).
local function restore(mode, d)
    if restored[mode] then return end
    restored[mode] = true
    local ids = {}
    for id in pairs(d.pending) do
        if not inflight[id] and not resolved(d, id) then ids[#ids + 1] = id else d.pending[id] = nil end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do push(id) end
end

local function nextID(d)
    while retry[retryHead] do
        local id = retry[retryHead]
        retry[retryHead] = nil
        retryHead = retryHead + 1
        if not resolved(d, id) and not inflight[id] then return id end
    end
    local l = S.list(d.mode)
    while d.pos < #l do
        d.pos = d.pos + 1
        local id = l[d.pos]
        if not resolved(d, id) and not inflight[id] and d.pending[id] == nil then return id end
    end
    return nil
end

function S.done(d)
    return d ~= nil and d.pos >= #S.list(d.mode) and retry[retryHead] == nil and next(inflight) == nil
        and next(d.pending) == nil
end

function S.active() return active and S.db(active) or nil end

local function bump(c, key) c[key] = (c[key] or 0) + 1 end

-- A waiting ID the client now has: done, whatever event (if any) said so.
local function settle(d, id, how)
    local r = record(id)
    if not r then return false end
    inflight[id], d.pending[id] = nil, nil
    d.got[id] = r
    bump(d.counts, "success")
    bump(d.counts, how)
    return true
end

-- One tick: answers found by polling, timeouts, then at most one request.
function S.step()
    local d = S.active()
    if not d or not d.running then return "stopped" end
    local c = d.counts
    local why = S.paused()
    if why then c.paused = c.paused + 1; return why end
    local t = now()
    for id in pairs(inflight) do
        if cached(id) then settle(d, id, "polled") end
    end
    for id, f in pairs(inflight) do
        if t - f.t >= S.TIMEOUT then
            inflight[id] = nil
            c.timeouts = c.timeouts + 1
            if f.tries < S.RETRIES then
                c.retries = c.retries + 1
                d.pending[id] = f.tries + 1
                push(id)
            else
                d.pending[id] = nil
                d.timeout[id] = f.tries + 1
            end
        end
    end
    if S.inflightCount() >= S.INFLIGHT then return "waiting" end
    local id = nextID(d)
    if not id then
        if S.done(d) then
            d.running, d.finished = false, time()
            active = nil
            S.say(S.statusText())
            return "finished"
        end
        return "waiting"
    end
    if not exists(id) then
        d.invalid[id] = "exist"
        d.pending[id] = nil
        c.invalid = c.invalid + 1
        return "invalid"
    end
    if cached(id) ~= false then
        -- Cached (or no way to tell: GetItemInfo asks the server itself).
        local r = record(id)
        if r then
            d.got[id], d.pending[id] = r, nil
            c.known = c.known + 1
            return "known"
        end
        if cached(id) == nil then
            local tries = d.pending[id] or 0
            inflight[id], d.pending[id] = { t = t, tries = tries }, tries
            c.requests = c.requests + 1
            return "asked"
        end
    end
    local tries = d.pending[id] or 0
    inflight[id], d.pending[id] = { t = t, tries = tries }, tries
    -- A retry asks through GetItemInfo (it queues the server itself and is
    -- answered by GET_ITEM_INFO_RECEIVED); the first try through
    -- RequestLoadItemDataByID (ITEM_DATA_LOAD_RESULT).
    if tries > 0 and S.infoFn() then
        if settle(d, id, "known") then return "known" end
        bump(c, "viaInfo")
    elseif ask(id) then
        bump(c, "viaLoad")
    else
        inflight[id] = nil
        d.running, active = false, nil
        return "no-api"
    end
    c.requests = c.requests + 1
    return "asked"
end

-- GET_ITEM_INFO_RECEIVED and ITEM_DATA_LOAD_RESULT (itemID, success): every
-- event is counted (events / loads).
function S.received(id, success, event)
    local d = S.active()
    if d then bump(d.counts, event == "ITEM_DATA_LOAD_RESULT" and "loads" or "events") end
    id = tonumber(id)
    if not d or not id or not inflight[id] then return false end
    local c = d.counts
    c.ours = c.ours + 1
    inflight[id] = nil
    d.pending[id] = nil
    local r = success ~= false and record(id) or nil
    if r then
        d.got[id] = r
        c.success = c.success + 1
    else
        d.invalid[id] = "answer"
        c.failed = c.failed + 1
    end
    return true
end

local function loop()
    local result = S.step()
    if result == "stopped" or result == "finished" or result == "no-api" then looping = false; return end
    after((result == "combat" or result == "instance") and S.PAUSED_RETRY or S.TICK, loop)
end
local function kick()
    if looping then return end
    looping = true
    after(S.TICK, loop)
end
function S.looping() return looping end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

local LABEL = { sample = "樣本", full = "全量" }
function S.statusText(mode)
    mode = mode or active or (S.db("sample") and "sample") or (S.db("full") and "full") or "sample"
    local d = S.db(mode)
    local total = #S.list(mode)
    local head = "物品掃描（" .. LABEL[mode] .. "）："
    if not d then return string.format("%s尚未開始（%d 個）", head, total) end
    local state = d.running and (S.paused() and "暫停中" or "執行中") or (S.done(d) and "完成" or "已停止")
    local waiting = count(d.pending)
    local left = math.max(0, total - d.pos) + waiting
    local c = d.counts
    return string.format("%s%s，%d／%d（成功 %d，無效 %d，逾時 %d，等待 %d）；請求 %d 次（載入 %d、GetItemInfo %d），事件 %d 次＋載入事件 %d 次（我們的 %d），輪詢找到 %d、已快取 %d、逾時 %d 次，約剩 %d 分鐘",
        head, state, d.pos, total, count(d.got), count(d.invalid), count(d.timeout), waiting,
        c.requests, c.viaLoad or 0, c.viaInfo or 0, c.events, c.loads or 0, c.ours, c.polled or 0, c.known or 0,
        c.timeouts or 0, math.ceil(left * S.TICK / 60))
end

-- The sample's result, one line per ID.
function S.report()
    local d = S.db("sample")
    local out = {}
    for _, id in ipairs(S.list("sample")) do
        local line
        if not d then line = "尚未開始"
        elseif d.got[id] then
            local r = d.got[id]
            line = string.format("成功 %s（類 %d-%d，綁定 %d，品質 %d，等級 %d，圖示 %d）", r[1], r[2], r[3], r[4], r[5], r[6], r[7])
        elseif d.invalid[id] then line = d.invalid[id] == "exist" and "無效（遊戲說沒有這個物品）" or "無效（伺服器回答失敗）"
        elseif d.timeout[id] then line = string.format("逾時（問了 %d 次）", d.timeout[id])
        elseif d.pending[id] then line = "等待中"
        else line = "還沒問" end
        out[#out + 1] = string.format("%d：%s", id, line)
    end
    return out
end

function S.start(mode)
    if mode == "full" and not S.FULL_ENABLED then
        S.say("全量掃描暫停中：先跑 /gftkdev catalogscan sample")
        return false
    end
    if active and active ~= mode then S.say("另一個掃描在跑：先 stop"); return false end
    local d = S.db(mode)
    local problem = S.check(d)
    if problem then S.say(problem); return false end
    d = S.db(mode, true)
    if S.done(d) and d.finished then S.say(S.statusText(mode)); return false end
    restore(mode, d)
    d.running = true
    active = mode
    kick()
    return true
end
function S.stop()
    for mode in pairs(S.MODES) do
        local d = S.db(mode)
        if d then d.running = false end
    end
    active = nil
    return true
end
function S.reset()
    if type(GreenFangToolkitDevDB) == "table" then
        for _, key in pairs(S.MODES) do GreenFangToolkitDevDB[key] = nil end
    end
    inflight, retry, retryHead, retryTail, restored, active = {}, {}, 1, 0, {}, nil
    return true
end

function S.command(rest)
    local sub = tostring(rest or ""):lower():match("^%s*(%S*)")
    if sub == "sample" then S.start("sample")
    elseif sub == "full" then S.start("full")
    elseif sub == "stop" then S.stop()
    elseif sub == "reset" then S.reset()
    elseif sub == "report" then
        for _, line in ipairs(S.report()) do S.say(line) end
    end
    S.say(S.statusText())
end

-- After a login: a run that was on resumes a minute later (same checks).
function S.resume()
    for mode in pairs(S.MODES) do
        local d = S.db(mode)
        if d and d.running and not active then
            local problem = S.check(d)
            if problem or (mode == "full" and not S.FULL_ENABLED) then
                d.running = false
                S.say(problem or "全量掃描暫停中")
            else
                restore(mode, d)
                active = mode
                after(S.START_DELAY, function() if active == mode and d.running then kick() end end)
            end
        end
    end
end

function S.resetSession()
    lists, inflight, retry, retryHead, retryTail, restored, looping, active = {}, {}, {}, 1, 0, {}, false, nil
end

SLASH_GFTKDEV1 = "/gftkdev"
if type(SlashCmdList) == "table" then
    SlashCmdList.GFTKDEV = function(msg)
        local cmd, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
        if cmd:lower() == "catalogscan" then S.command(rest)
        else S.say("/gftkdev catalogscan [sample｜report｜stop｜reset]") end
    end
end

if type(CreateFrame) == "function" then
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
    pcall(ev.RegisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
    local resumed = false
    ev:SetScript("OnEvent", function(_, event, a, b)
        if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            S.received(a, b, event)
        elseif not resumed then
            resumed = true
            S.resume()
        end
    end)
end
