-- GF-009-12: the 找物品 item catalog. SupplyCatalogData.lua (built by
-- scripts/build_item_catalog.py, in the main TOC) holds ItemID, zhTW name,
-- item class and the native icon number of every tradeable item as one long
-- string per item class. At login only those strings are in memory; they are
-- decoded into search tables the first time 找物品 → 全部 opens, and the
-- strings are then let go. Nothing is copied into SavedVariables.
-- The catalog only finds items; the preview and whether an item may be listed
-- still come from the game client (SupplyListings.lua).
local _, ns = ...
local Cat = {}
ns.SupplyCatalog = Cat

Cat.SCHEMA = 2

local data            -- { id, name, kind, icon } after decoding, or nil
local status = "idle" -- idle / ok / missing / bad
local stats = { decodes = 0, searches = 0, lastMs = nil, decodeMs = nil, memKB = nil }

local function clock()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return os.clock() * 1000
end
local function memKB()
    if type(collectgarbage) ~= "function" then return nil end
    local okCall, kb = pcall(collectgarbage, "count")
    return okCall and tonumber(kb) or nil
end

-- Decode once (the first 找物品 → 全部). Returns true when it can be searched.
function Cat.load()
    if data then return true end
    if status ~= "idle" then return false end
    local src = ns.SupplyCatalogData
    if type(src) ~= "table" then status = "missing"; return false end
    if src.v ~= Cat.SCHEMA or type(src.groups) ~= "table" then status = "bad"; return false end
    local before, t0 = memKB(), clock()
    local id, name, kind, icon = {}, {}, {}, {}
    local classes = {}
    for c in pairs(src.groups) do classes[#classes + 1] = c end
    table.sort(classes)
    local n = 0
    for _, c in ipairs(classes) do
        local s = src.groups[c]
        if type(s) == "string" then
            for i, sub, ic, nm in s:gmatch("(%d+)\t(%d+)\t(%d+)\t([^\n]+)") do
                n = n + 1
                id[n], kind[n], icon[n], name[n] = tonumber(i), c * 100 + tonumber(sub), tonumber(ic), nm
            end
        end
    end
    if n == 0 then status = "bad"; return false end
    data = { id = id, name = name, kind = kind, icon = icon, build = src.build, locale = src.locale }
    src.groups = nil -- the strings are no longer needed
    stats.decodes = stats.decodes + 1
    stats.decodeMs = clock() - t0
    local after = memKB()
    stats.memKB = before and after and (after - before) or nil
    status = "ok"
    return true
end
function Cat.loaded() return data ~= nil end
function Cat.status() return status end
function Cat.count() return data and #data.id or 0 end
function Cat.build() return data and data.build or (ns.SupplyCatalogData and ns.SupplyCatalogData.build) or nil end

-- The record at index i as the finder's info table (catalog = true: not yet
-- confirmed by the client).
local byID
function Cat.info(i)
    if not data or not data.id[i] then return nil end
    local k, icon = data.kind[i], data.icon[i]
    return { itemID = data.id[i], name = data.name[i], classID = math.floor(k / 100), subclassID = k % 100,
        icon = icon > 0 and icon or nil, catalog = true }
end
-- Index of an ItemID in the catalog, or nil.
function Cat.index(itemID)
    if not data then return nil end
    if not byID then
        byID = {}
        for i, v in ipairs(data.id) do byID[v] = i end
    end
    return byID[itemID]
end
function Cat.find(itemID)
    local i = Cat.index(itemID)
    return i and Cat.info(i) or nil
end
-- Fields of index i without making a table.
function Cat.idOf(i) return data and data.id[i] end
function Cat.nameOf(i) return data and data.name[i] end
function Cat.kindOf(i)
    local k = data and data.kind[i]
    if not k then return nil, nil end
    return math.floor(k / 100), k % 100
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

-- The scan list for /gftk catalogscan (CatalogScan.lua): sorted ItemIDs.
function Cat.scanIDs()
    local src = ns.SupplyCatalogData
    local s = type(src) == "table" and src.scan or nil
    local out, last = {}, 0
    if type(s) ~= "string" then return out end
    for gap in s:gmatch("[^,]+") do
        last = last + (tonumber(gap, 36) or 0)
        out[#out + 1] = last
    end
    return out
end

function Cat.stats() return stats end

function Cat.resetSession()
    data, status, byID = nil, "idle", nil
    stats = { decodes = 0, searches = 0, lastMs = nil, decodeMs = nil, memKB = nil }
end

local STATUS_TEXT = { idle = "尚未載入", ok = "已載入", missing = "沒有目錄", bad = "格式不符" }
function Cat.diagText()
    local lines = { "目錄：" .. (STATUS_TEXT[status] or status) }
    local build = Cat.build()
    if build then lines[#lines + 1] = "版本 " .. build .. (data and string.format("，%d 筆", #data.id) or "") end
    if stats.decodeMs then
        lines[#lines + 1] = string.format("解開 %.0f 毫秒，約 %s KB", stats.decodeMs,
            stats.memKB and string.format("%.0f", stats.memKB) or "?")
    end
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
