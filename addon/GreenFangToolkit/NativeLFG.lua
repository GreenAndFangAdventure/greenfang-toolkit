-- NativeLFG (GF-002-G, 0.12.6): the game's own group finder (尋求組隊,
-- C_LFGList) next to the toolkit's adventure tickets. Owner: 「是否能同步內建
-- 集合時（遊戲內建的尋求組隊）的內容？如果時間是現在，無論職工單或冒險單，都
-- 可以去對應、建議現在有的地城及內容」. Research: docs/research/GF-002-G_native-lfg.md.
--
-- What it does (only what an AddOn may):
--   * reads the results of the last group finder search (the player's own,
--     or one started by a click on 「搜尋」 here) and keeps those for the
--     dungeons of the toolkit (matched by the instance map ID);
--   * suggests the dungeons people are looking for right now;
--   * lists a 「現在」 ticket in the group finder, from a click (CreateListing);
--   * applies to a found group or whispers its leader, from a click.
-- Every call is guarded: a missing function hides the feature, a failed call
-- returns false. Searching and listing are never started without a click.

local _, ns = ...
local str = ns.str

local L = {}
ns.NativeLFG = L

L.DUNGEON_CATEGORY = 2 -- 地城 in the group finder (Blizzard's category IDs)

local function api() return type(C_LFGList) == "table" and C_LFGList or nil end
function L.has(name)
    local a = api()
    return a ~= nil and type(a[name]) == "function"
end
-- Can we read results at all?
function L.available() return L.has("GetSearchResults") and L.has("GetSearchResultInfo") and L.has("GetActivityInfoTable") end
function L.canSearch() return L.available() and L.has("Search") end
function L.canList() return L.has("CreateListing") and L.has("GetActivityInfoTable") end
function L.canApply() return L.has("ApplyToGroup") end

local function call(name, ...)
    local a = api()
    if not a or type(a[name]) ~= "function" then return false end
    return pcall(a[name], ...)
end

---------------------------------------------------------------------------
-- Activities <-> the toolkit's dungeons (by the instance map ID)
---------------------------------------------------------------------------

local activityCache -- { [activityID] = dungeonID or false }
function L.reset() activityCache = nil; L.results = nil; L.searchedAt = nil end

function L.dungeonOfActivity(activityID)
    activityCache = activityCache or {}
    if activityCache[activityID] ~= nil then return activityCache[activityID] or nil end
    local ok, info = call("GetActivityInfoTable", activityID)
    local found = false
    if ok and type(info) == "table" then
        local mapID = ns.num(info.mapID)
        local name = str(info.fullName)
        for _, d in ipairs(ns.AdventureData.DUNGEONS) do
            if (mapID and d.instance == mapID) or (name ~= "" and name == d.name) then found = d.id; break end
        end
    end
    activityCache[activityID] = found
    return found or nil
end

-- The activity of a dungeon (for listing), or nil.
function L.activityFor(dungeonID)
    local d = ns.AdventureData.byId[dungeonID]
    if not d then return nil end
    local lists = {}
    for _, args in ipairs({ { L.DUNGEON_CATEGORY }, {} }) do
        local ok, ids = call("GetAvailableActivities", unpack(args))
        if ok and type(ids) == "table" then lists[#lists + 1] = ids; break end
    end
    for _, ids in ipairs(lists) do
        for _, id in ipairs(ids) do
            if L.dungeonOfActivity(id) == dungeonID then return id end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Search results (the last search, by anyone: the player or our click)
---------------------------------------------------------------------------

local ROLE_KEYS = { t = "TANK_REMAINING", h = "HEALER_REMAINING", d = "DAMAGER_REMAINING" }

-- { { id, dungeon, leader, members, need = { t, h, d }, comment, name } } for our dungeons.
function L.read()
    if not L.available() then return {} end
    local ok, total, ids = call("GetSearchResults")
    if not ok then return {} end
    if type(total) == "table" and ids == nil then ids = total end
    local out = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local okI, info = call("GetSearchResultInfo", id)
        if okI and type(info) == "table" and not info.isDelisted then
            local acts = info.activityIDs or (info.activityID and { info.activityID }) or {}
            local dungeon
            for _, a in ipairs(acts) do dungeon = dungeon or L.dungeonOfActivity(a) end
            if dungeon then
                local need = {}
                local okC, counts = call("GetSearchResultMemberCounts", id)
                if okC and type(counts) == "table" then
                    for r, k in pairs(ROLE_KEYS) do need[r] = ns.num(counts[k]) end
                end
                -- GF-FIX-D (review 中-3): other players' text: no "|" sequences, short.
                out[#out + 1] = { id = id, dungeon = dungeon, leader = ns.cleanText(info.leaderName, 64), members = ns.num(info.numMembers) or 0,
                    need = need, comment = ns.cleanText(info.comment, 160), name = ns.cleanText(info.name, 160) }
            end
        end
    end
    table.sort(out, function(a, b) if a.dungeon ~= b.dungeon then return a.dungeon < b.dungeon end return a.id < b.id end)
    return out
end

function L.refresh()
    L.results = L.read()
    L.searchedAt = ns.now()
    if L.onChanged then pcall(L.onChanged) end
    return L.results
end

-- Results for some dungeons ({ [id] = true }), or all.
function L.resultsFor(set)
    local out = {}
    for _, r in ipairs(L.results or {}) do if not set or set[r.dungeon] then out[#out + 1] = r end end
    return out
end
-- { [dungeon] = number of groups } — "people are looking for this now".
function L.counts()
    local out = {}
    for _, r in ipairs(L.results or {}) do out[r.dungeon] = (out[r.dungeon] or 0) + 1 end
    return out
end

-- From a click only: ask the game to search the dungeon category.
function L.search()
    if not L.canSearch() then return false end
    local ok = call("Search", L.DUNGEON_CATEGORY)
    return ok and true or false
end

-- From a click only: list a 「現在」 ticket (dungeon, comment) in the group finder.
function L.list(dungeonID, comment)
    if not L.canList() then return false, "no-api" end
    local act = L.activityFor(dungeonID)
    if not act then return false, "no-activity" end
    local data = { activityIDs = { act }, activityID = act, isAutoAccept = false, isPrivateGroup = false,
        questID = nil, comment = str(comment), name = "" }
    local ok, res = call("CreateListing", data)
    if ok and res ~= false then return true end
    return false, "failed"
end

-- From a click only: apply with my roles (main / alt), or nothing.
function L.apply(result, main, alt)
    if not (result and L.canApply()) then return false end
    local roles = { t = main == "t" or alt == "t", h = main == "h" or alt == "h", d = main == "d" or alt == "d" }
    local ok = call("ApplyToGroup", result.id, roles.t, roles.h, roles.d)
    return ok and true or false
end

-- 同步與診斷.
function L.diagText()
    local names = { "GetAvailableActivities", "GetActivityInfoTable", "Search", "GetSearchResults", "GetSearchResultInfo",
        "GetSearchResultMemberCounts", "CreateListing", "ApplyToGroup", "GetActiveEntryInfo" }
    local have, missing = 0, {}
    for _, n in ipairs(names) do if L.has(n) then have = have + 1 else missing[#missing + 1] = n end end
    return string.format("C_LFGList %d / %d%s｜上次結果：%s",
        have, #names, #missing > 0 and ("（沒有：" .. table.concat(missing, "、") .. "）") or "",
        L.searchedAt and (#(L.results or {}) .. " 隊") or "還沒有")
end

-- The game says a search finished (the player's or ours): read it.
-- GF-FIX-D (review 中-14): a client without these events loads on (pcall, as elsewhere).
local f = CreateFrame("Frame")
L.missingEvents = {}
for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED" }) do
    if not pcall(f.RegisterEvent, f, e) then L.missingEvents[#L.missingEvents + 1] = e end
end
f:SetScript("OnEvent", function()
    ns.coalesce("native-lfg", 1, function() L.refresh() end)
end)
L.eventFrame = f
