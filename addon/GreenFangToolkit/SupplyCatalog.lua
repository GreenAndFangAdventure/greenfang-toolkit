-- GF-009-12: the 找物品 item catalog. The data lives in a separate
-- LoadOnDemand AddOn (GreenFangToolkit_Catalog, built by
-- scripts/build_item_catalog.py): ItemID, zhTW name, item class and the native
-- icon number of every tradeable item. It is loaded the first time 找物品 →
-- 全部 opens, never at login, and is never copied into SavedVariables.
-- The catalog only finds items; the preview and whether an item may be listed
-- still come from the game client (SupplyListings.lua).
local _, ns = ...
local Cat = {}
ns.SupplyCatalog = Cat

Cat.ADDON = "GreenFangToolkit_Catalog"
Cat.GLOBAL = "GreenFangToolkit_CatalogData"
Cat.SCHEMA = 1

local data            -- the loaded table, or nil
local status = "idle" -- idle / ok / missing / bad / no-loader
local reason
local stats = { loads = 0, searches = 0, lastMs = nil, loadMs = nil, memKB = nil }

local function clock()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return os.clock() * 1000
end
local function memKB()
    if type(collectgarbage) ~= "function" then return nil end
    local okCall, kb = pcall(collectgarbage, "count")
    return okCall and tonumber(kb) or nil
end

local function valid(t)
    return type(t) == "table" and t.v == Cat.SCHEMA and type(t.id) == "table" and type(t.name) == "table"
        and type(t.kind) == "table" and type(t.icon) == "table" and #t.id == #t.name
end

-- Load once (on demand). Returns true when the catalog can be searched.
function Cat.load()
    if data then return true end
    if status ~= "idle" then return false end -- tried this session (a new AddOn needs a restart)
    local value = _G[Cat.GLOBAL]
    if value == nil then
        local load = (type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" and C_AddOns.LoadAddOn)
            or (type(LoadAddOn) == "function" and LoadAddOn) or nil
        if not load then status = "no-loader"; return false end
        local before, t0 = memKB(), clock()
        local okCall, loaded, why = pcall(load, Cat.ADDON)
        stats.loads = stats.loads + 1
        if not okCall or not loaded then
            status, reason = "missing", okCall and ns.str(why) ~= "" and ns.str(why) or nil
            return false
        end
        value = _G[Cat.GLOBAL]
        stats.loadMs = clock() - t0
        local after = memKB()
        stats.memKB = before and after and math.max(0, after - before) or nil
    end
    if not valid(value) then status = "bad"; return false end
    data, status, reason = value, "ok", nil
    return true
end
function Cat.loaded() return data ~= nil end
function Cat.status() return status, reason end
function Cat.count() return data and #data.id or 0 end
function Cat.build() return data and data.build or nil end

-- The record at index i as the finder's info table (catalog = true: not yet
-- confirmed by the client).
local byID
function Cat.info(i)
    if not data or not data.id[i] then return nil end
    local kind = tonumber(data.kind[i]) or 0
    local icon = tonumber(data.icon[i]) or 0
    return { itemID = data.id[i], name = data.name[i], classID = math.floor(kind / 100), subclassID = kind % 100,
        icon = icon > 0 and icon or nil, catalog = true }
end
function Cat.find(itemID)
    if not data then return nil end
    if not byID then
        byID = {}
        for i, id in ipairs(data.id) do byID[id] = i end
    end
    local i = byID[itemID]
    return i and Cat.info(i) or nil
end

-- Indexes whose name contains needle (plain text; nil or "" = all), in
-- catalog order (class, subclass, name). No limit: the finder pages.
function Cat.search(needle)
    if not data then return {} end
    local t0 = clock()
    local out, names = {}, data.name
    if needle == nil or needle == "" then
        for i = 1, #names do out[i] = i end
    else
        local find = string.find
        for i = 1, #names do
            if find(names[i], needle, 1, true) then out[#out + 1] = i end
        end
    end
    stats.searches = stats.searches + 1
    stats.lastMs = clock() - t0
    return out
end

function Cat.stats() return stats end

function Cat.resetSession()
    data, status, reason, byID = nil, "idle", nil, nil
    stats = { loads = 0, searches = 0, lastMs = nil, loadMs = nil, memKB = nil }
end

local STATUS_TEXT = { idle = "尚未載入", ok = "已載入", missing = "沒有安裝", bad = "格式不符", ["no-loader"] = "無法載入" }
function Cat.diagText()
    local lines = { "目錄：" .. (STATUS_TEXT[status] or status) .. (reason and ("（" .. reason .. "）") or "") }
    if data then
        lines[#lines + 1] = string.format("版本 %s，%d 筆", ns.str(data.build), #data.id)
    end
    if stats.loadMs then lines[#lines + 1] = string.format("載入 %.0f 毫秒，約 %s KB", stats.loadMs, stats.memKB and string.format("%.0f", stats.memKB) or "?") end
    if stats.lastMs then lines[#lines + 1] = string.format("搜尋 %d 次，上次 %.1f 毫秒", stats.searches, stats.lastMs) end
    return table.concat(lines, "\n")
end

-- GF-009-11's offline prototype (never released) kept an item cache in
-- GreenFangToolkitDB.supplyItems. The catalog replaces it: a test build's
-- cache is dropped once at login. Listings and drafts live elsewhere and are
-- not touched.
function Cat.dropOldCache()
    if type(ns.db) == "table" and ns.db.supplyItems ~= nil then
        ns.db.supplyItems = nil
        return true
    end
    return false
end
if type(CreateFrame) == "function" then
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() Cat.dropOldCache() end)
end
