-- SupplyListings (GF-009-08, v2.0 §7.2): manual listings, 徵求 (need) or
-- 供應 (offer). Not an order system: no price, no deal tracking, no automatic
-- whisper or trade. Its own record group, separate from COLLECTION, and its
-- own switch (Supply.setManual).
--
-- GFTKS group "L" (Share.lua record layer): one whole snapshot per author of
-- their active listings, "," separated, each
--   <id>.<n|o>.<category>.<itemID>.<qty>.<createdAt>.<expiresAt>.<rev>.<note>
-- numbers in base 36, the note %XX-escaped. Only the author writes their
-- record (the record is keyed by the author; relays keep author and time).
-- A cancelled, closed or expired listing is simply missing from the next
-- snapshot, and an older snapshot can never replace a newer one, so an old
-- packet cannot bring a listing back (the newer snapshot is its tombstone).
-- Receivers also drop every listing past its expiresAt by themselves.
-- Nothing here goes to GF Sync or the site (group registered as local).

local _, ns = ...
local str = ns.str

local L = {}
ns.SupplyListings = L
local Supply = ns.Supply

L.GROUP = "L"
L.DAYS = { 3, 7, 14, 30 }
L.DEFAULT_DAYS = 14
L.NOTE_MAX = 40          -- characters
L.QTY_MAX = 999
L.MAX_ACTIVE = 10        -- active listings per character
L.KEEP_ENDED = 7 * 86400 -- ended listings stay in 我的刊登 this long
L.MAX_KEPT = 50
L.SLACK = 3600           -- a received expiresAt may be this much past createdAt + 30 days
L.SWEEP_EVERY = 300

-- Categories (v2.0 §7.2): key, wire code, name.
L.CATEGORIES = {
    { key = "recipe", code = "r", text = "圖紙" },
    { key = "material", code = "m", text = "材料" },
    { key = "gear", code = "g", text = "裝備" },
    { key = "consumable", code = "c", text = "消耗品" },
    { key = "quest", code = "q", text = "任務" },
    { key = "other", code = "o", text = "其他" },
}
local byCode, byKey = {}, {}
for _, c in ipairs(L.CATEGORIES) do byCode[c.code] = c; byKey[c.key] = c end
function L.categoryText(key) return byKey[key] and byKey[key].text or "其他" end
L.DIRECTION_TEXT = { need = "徵求", offer = "供應" }

-- GF-009-14 B: 交易條件 of a manual listing (gftks.md §3.2 group M, claude-pm
-- 2026-11-27). 供應: the asking price; 徵求: what the player will pay. Per
-- item, in copper, at most the client's money cap. A listing without terms
-- (older AddOns, or no M record yet) reads 未標示.
L.TERMS_GROUP = "M"
L.PRICE_MAX = 2147483647
L.TERMS = {
    { key = "negotiable", code = "n", text = "面議" },
    { key = "free", code = "f", text = "免費" },
    { key = "price", code = "p", text = "訂價" },
    { key = "swap", code = "x", text = "交換" },
}
L.DEFAULT_TERMS = "negotiable"
L.UNMARKED = "未標示"
local termsByKey, termsByCode = {}, {}
for _, t in ipairs(L.TERMS) do termsByKey[t.key] = t; termsByCode[t.code] = t end
L.termsByKey = termsByKey
-- 「1金 20銀 5銅」 (zero parts left out; 0 = 「0銅」).
function L.priceText(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "金" end
    if s > 0 then out[#out + 1] = s .. "銀" end
    if c > 0 or #out == 0 then out[#out + 1] = c .. "銅" end
    return table.concat(out, " ")
end
-- The terms as text: long 「每個 1金 20銀」 / short 「1金20銀」; 面議, 免費, 交換; 未標示.
function L.termsText(terms, price, short)
    local t = terms and termsByKey[terms]
    if not t then return L.UNMARKED end
    if t.key ~= "price" then return t.text end
    local p = L.priceText(price)
    if short then return (p:gsub(" ", "")) end
    return "每個 " .. p
end
L.STATUS_TEXT = { active = "刊登中", closed = "已結束", cancelled = "已取消", expired = "已過期" }

local stats = { rejected = 0, created = 0, updated = 0, ended = 0, deleted = 0 }
-- GF-009-13: item data requests this session (RequestLoadItemDataByID, or a
-- GetItemInfo the client did not have), and those made while 全部 searched by
-- name (should stay 0; shown in 同步與診斷 for the Forever check).
local requests = { all = 0, nameSearch = 0 }
local inNameSearch = false
function L.requestStats() return requests end
L.stats = stats

---------------------------------------------------------------------------
-- Text helpers (pure)
---------------------------------------------------------------------------

-- Characters of a UTF-8 string (bytes that do not continue a character).
function L.chars(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- A note as stored: control bytes become spaces, trimmed, at most NOTE_MAX
-- characters (cut at a character boundary). Returns the note, or nil and
-- "too-long".
function L.cleanNote(s)
    s = str(s):gsub("[%z\1-\31\127]", " ")
    s = s:gsub("|", "/") -- no chat escape codes inside a note
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if L.chars(s) > L.NOTE_MAX then return nil, "too-long" end
    return s
end

local SPECIAL = { [37] = true, [46] = true, [44] = true, [47] = true, [126] = true, [124] = true, [59] = true, [61] = true }
local function esc(v)
    return (str(v):gsub(".", function(c)
        local b = c:byte()
        if b < 32 or b == 127 or SPECIAL[b] then return string.format("%%%02X", b) end
        return c
    end))
end
local function unesc(v) return (v:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)) end

-- ItemID from a chat item link or "item:123" text; nil otherwise (no guessing).
function L.itemFromText(text)
    text = str(text)
    local id = text:match("|Hitem:(%d+)") or text:match("^%s*item:(%d+)")
    id = tonumber(id)
    if id and id > 0 then return id end
    return nil
end

-- GF-UI-I: what the player put into the form's item box: a chat item link,
-- "item:123", or an ItemID typed as digits (only in that box; itemFromText
-- above stays strict for everything else). Returns itemID, "link" / "id",
-- or nil, "empty" / "bad".
L.ITEM_ID_MAX = 10000000
function L.parseItemInput(text)
    text = str(text):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "empty" end
    local id = L.itemFromText(text)
    if id then return id, "link" end
    local n = tonumber(text:match("^#?(%d+)$"))
    if n and n > 0 and n <= L.ITEM_ID_MAX then return n, "id" end
    return nil, "bad"
end

---------------------------------------------------------------------------
-- Wire value of group L
---------------------------------------------------------------------------

local b36, unb36 = ns.Share.b36, ns.Share.unb36

-- GF-009-14 B: group M, the author's terms for their active listings:
-- 「1,<id>.<n|f|p|x>.<price>,…」 (version 1; ids and prices base 36; price only
-- for p). An unknown letter leaves that listing 未標示; a bad price or shape
-- rejects the record (not stored, not relayed).
function L.encodeTerms(list)
    local out = { "1" }
    table.sort(list, function(x, y) return x.id < y.id end)
    for _, l in ipairs(list) do
        local t = l.terms and termsByKey[l.terms]
        if t then
            out[#out + 1] = b36(l.id) .. "." .. t.code .. "." .. (t.key == "price" and b36(l.price) or "")
        end
    end
    return table.concat(out, ",")
end
function L.decodeTerms(_, v)
    if type(v) ~= "string" or #v > 400 then stats.rejected = stats.rejected + 1; return nil end
    local parts = {}
    for x in (v .. ","):gmatch("([^,]*),") do parts[#parts + 1] = x end
    local function bad() stats.rejected = stats.rejected + 1; return nil end
    if parts[1] ~= "1" then return bad() end
    local map, n = {}, 0
    for i = 2, #parts do
        local f = {}
        for x in (parts[i] .. "."):gmatch("([^.]*)%.") do f[#f + 1] = x end
        if #f ~= 3 then return bad() end
        local id = unb36(f[1])
        if not id or id < 1 or map[id] then return bad() end
        local t, price = termsByCode[f[2]], nil
        if t and t.key == "price" then
            price = unb36(f[3])
            if not price or price < 1 or price > L.PRICE_MAX then return bad() end
        elseif t and f[3] ~= "" then
            return bad()
        end
        map[id] = { terms = t and t.key or nil, price = price }
        n = n + 1
        if n > L.MAX_ACTIVE then return bad() end
    end
    return map
end

function L.encode(list)
    local out = {}
    table.sort(list, function(x, y) return x.id < y.id end)
    for _, l in ipairs(list) do
        out[#out + 1] = table.concat({ b36(l.id), l.direction == "need" and "n" or "o", byKey[l.category] and byKey[l.category].code or "o",
            b36(l.itemID), b36(l.quantity), b36(l.createdAt), b36(l.expiresAt), b36(l.rev or 1), esc(l.note or "") }, ".")
    end
    return table.concat(out, ",")
end

-- Value -> list of listings, or nil (the whole record is rejected).
function L.decode(_, v)
    if type(v) ~= "string" or #v > 2400 then stats.rejected = stats.rejected + 1; return nil end
    local list, ids, pairsSeen = {}, {}, {}
    if v == "" then return list end
    local function bad() stats.rejected = stats.rejected + 1; return nil end
    for item in (v .. ","):gmatch("([^,]*),") do
        local f = {}
        for x in (item .. "."):gmatch("([^.]*)%.") do f[#f + 1] = x end
        if #f ~= 9 then return bad() end
        local id, dir, cat = unb36(f[1]), f[2], byCode[f[3]]
        local itemID, qty, created, expires, rev = unb36(f[4]), unb36(f[5]), unb36(f[6]), unb36(f[7]), unb36(f[8])
        if not (id and cat and itemID and qty and created and expires and rev) then return bad() end
        if dir ~= "n" and dir ~= "o" then return bad() end
        if itemID <= 0 or itemID > 10000000 or qty < 1 or qty > L.QTY_MAX or id < 1 or ids[id] then return bad() end
        if created < ns.Share.EPOCH or expires <= created or expires > created + 30 * 86400 + L.SLACK then return bad() end
        local note = unesc(f[9])
        if note:find("[%z\1-\31\127|]") or L.chars(note) > L.NOTE_MAX then return bad() end
        local direction = dir == "n" and "need" or "offer"
        local pairKey = itemID .. direction
        if pairsSeen[pairKey] then return bad() end
        ids[id], pairsSeen[pairKey] = true, true
        list[#list + 1] = { id = id, direction = direction, category = cat.key, itemID = itemID, quantity = qty,
            createdAt = created, expiresAt = expires, rev = rev, note = note }
        if #list > L.MAX_ACTIVE then return bad() end
    end
    return list
end

ns.Share.registerGroup({
    name = "LISTING",
    ["local"] = true,
    match = function(g) return g == L.GROUP end,
    encode = function(_, d) return L.encode(d) end,
    decode = L.decode,
})
ns.Share.registerGroup({
    name = "TERMS", -- GF-009-14 B
    ["local"] = true,
    match = function(g) return g == L.TERMS_GROUP end,
    encode = function(_, d) return L.encodeTerms(d) end,
    decode = L.decodeTerms,
})

---------------------------------------------------------------------------
-- This character's listings (GreenFangToolkitDB.supply.listings[guid])
---------------------------------------------------------------------------

local function mine()
    local s = Supply.db()
    local guid = ns.Data.player().guid
    if not s or not guid then return nil end
    local m = s.listings[guid]
    if type(m) ~= "table" then m = { nextID = 1, list = {} }; s.listings[guid] = m end
    if type(m.list) ~= "table" then m.list = {} end
    m.nextID = tonumber(m.nextID) or 1
    return m
end
L.mine = mine

local function now() return math.floor(ns.Share.serverNow()) end

-- Own listings, newest first (all statuses kept for 我的刊登).
function L.own()
    local m = mine()
    local out = {}
    for _, l in pairs(m and m.list or {}) do out[#out + 1] = l end
    table.sort(out, function(x, y)
        if (x.status == "active") ~= (y.status == "active") then return x.status == "active" end
        if (x.updatedAt or 0) ~= (y.updatedAt or 0) then return (x.updatedAt or 0) > (y.updatedAt or 0) end
        return x.id > y.id
    end)
    return out
end

function L.ownActive()
    local out = {}
    for _, l in ipairs(L.own()) do if l.status == "active" then out[#out + 1] = l end end
    return out
end

-- Active ones past their time become 已過期; old ended ones are forgotten.
function L.sweep()
    local m = mine()
    if not m then return false end
    local t, changed = now(), false
    local ended = {}
    for id, l in pairs(m.list) do
        if l.status == "active" and l.expiresAt <= t then
            l.status, l.updatedAt, changed = "expired", t, true
        end
        if l.status ~= "active" then
            if t - (l.updatedAt or 0) > L.KEEP_ENDED then m.list[id] = nil else ended[#ended + 1] = l end
        end
    end
    if #ended > L.MAX_KEPT then
        table.sort(ended, function(x, y) return (x.updatedAt or 0) < (y.updatedAt or 0) end)
        for i = 1, #ended - L.MAX_KEPT do m.list[ended[i].id] = nil end
    end
    return changed
end

-- Store our snapshot (sent after Share.CHANGE_DELAY when it changed).
function L.publish()
    local Share = ns.Share
    local a = Share.selfAuthor()
    if not a or not Share.store() then return "no-store" end
    L.sweep()
    local list = {}
    if Supply.manualOn() then
        for _, l in ipairs(L.ownActive()) do list[#list + 1] = l end
    end
    -- GF-009-14 B: the terms (group M) go out with every listing change.
    local copy = {}
    for i, l in ipairs(list) do copy[i] = l end
    local vm = L.encodeTerms(copy)
    local recm = Share.get(a, L.TERMS_GROUP)
    if (recm and recm.v ~= vm) or (not recm and #list > 0) then Share.ownRecord(L.TERMS_GROUP, vm) end
    local v = L.encode(list)
    local rec = Share.get(a, L.GROUP)
    if not rec and v == "" then return "none" end
    if rec and rec.v == v then return "same" end
    local r = Share.ownRecord(L.GROUP, v)
    Supply.invalidate()
    if Supply.onChanged then Supply.onChanged() end
    return r
end

function L.afterCombat() end

---------------------------------------------------------------------------
-- Items: what may be listed (v2.0 §7.2: a reliable ItemID, tradeable)
---------------------------------------------------------------------------

-- classID -> category key (Enum.ItemClass numbers).
L.CLASS_CATEGORY = { [9] = "recipe", [7] = "material", [5] = "material", [2] = "gear", [4] = "gear",
    [0] = "consumable", [12] = "quest" }

-- { name, link, icon, classID, subclassID, typeName, subTypeName, bindType }
-- or nil, "loading" / "unknown". noRequest: an item not in the client's cache
-- is not asked from the server (GF-UI-H: the item finder reads many IDs).
-- GF-FIX-F (review 中-17): a missing item (the server said so) is not read
-- or asked again; the client's data is always read fresh (never kept here).
function L.itemInfo(itemID, noRequest)
    if type(itemID) ~= "number" or itemID <= 0 then return nil, "unknown" end
    local Wd = ns.Widgets
    if L.failed[itemID] then return nil, "missing" end
    local getInfo = ns.itemInfoFn() -- GF-009-13 fix: C_Item first (Forever has no global)
    if type(getInfo) ~= "function" then return nil, "unknown" end
    local okCall, name, link, _, _, _, typeName, subTypeName, _, _, icon, _, classID, subclassID, bindType = pcall(getInfo, itemID)
    if not okCall then return nil, "unknown" end
    if type(name) ~= "string" or name == "" then
        -- A GetItemInfo miss asks the server too: counted when it is a new
        -- request (GF-FIX-F: one per item until answered, Widgets.requestItem).
        if not Wd.itemRequested(itemID) then
            requests.all = requests.all + 1
            if inNameSearch then requests.nameSearch = requests.nameSearch + 1 end
        end
        Wd.requestItem(itemID, noRequest)
        return nil, "loading"
    end
    -- GF-009-13: the game's name wins over the catalog's (noted, never asked).
    local Cat = ns.SupplyCatalog
    if Cat and Cat.loaded() then Cat.noteName(itemID, name) end
    local info = { itemID = itemID, name = name, link = type(link) == "string" and link or nil,
        icon = icon or Supply.itemIcon(itemID), classID = tonumber(classID), subclassID = tonumber(subclassID),
        typeName = type(typeName) == "string" and typeName ~= "" and typeName or nil,
        subTypeName = type(subTypeName) == "string" and subTypeName ~= "" and subTypeName or nil,
        bindType = tonumber(bindType) }
    return info
end

-- GF-009-12: the client's data only when it already has the item
-- (GetItemInfo on an unknown item asks the server, so the catalog search never
-- calls it for those). Without C_Item.IsItemDataCachedByID: nil.
function L.cachedInfo(itemID)
    if type(C_Item) ~= "table" or type(C_Item.IsItemDataCachedByID) ~= "function" then return nil end
    local okCall, yes = pcall(C_Item.IsItemDataCachedByID, itemID)
    if not okCall or not yes then return nil end
    return (L.itemInfo(itemID, true))
end

-- GF-UI-I: the form's preview of an ItemID: "ready" (name, type), "loading"
-- (asked the server; GET_ITEM_INFO_RECEIVED redraws), "missing" (the client
-- says no such item) or "blocked" (cannot be traded).
-- GF-009-13: "timeout" (no answer within LOAD_WAIT seconds) is not "missing":
-- missing is only DoesItemExistByID = false or a GET_ITEM_INFO_RECEIVED with
-- success = false. The one path for links, IDs, drops and finder picks
-- (SupplyUI setFormItem).
L.LOAD_WAIT = 5
-- [itemID] = true: the server said no such item (GF-FIX-F: the same table
-- as Widgets.failedItems, so nothing asks for it again).
L.failed = ns.Widgets.failedItems
function L.itemAnswer(itemID, success)
    itemID = tonumber(itemID)
    if not itemID then return end
    if success == false then L.failed[itemID] = true else L.failed[itemID] = nil end
end
function L.itemExists(itemID)
    if type(C_Item) == "table" and type(C_Item.DoesItemExistByID) == "function" then
        local okCall, yes = pcall(C_Item.DoesItemExistByID, itemID)
        if okCall and yes == false then return false end
    end
    return true
end
function L.preview(itemID, waited)
    local info, why = L.itemInfo(itemID)
    if info then
        return { itemID = itemID, state = L.tradeable(info) and "ready" or "blocked", info = info, name = info.name,
            typeText = L.typeText(info) }
    end
    if why == "loading" and L.itemExists(itemID) and not L.failed[itemID] then
        return { itemID = itemID, state = waited and "timeout" or "loading" }
    end
    return { itemID = itemID, state = "missing" }
end

-- GF-UI-H: 拾取綁定 (1) and quest items (4) can never be traded: never listed,
-- in either direction, and never offered by the item finder.
L.NO_TRADE_BIND = { [1] = true, [4] = true }
function L.tradeable(info) return info ~= nil and not L.NO_TRADE_BIND[info.bindType or 0] end

-- GF-009-13: the item in this character's bags: "bound" when every stack of
-- it is bound, "free" when one is not, nil when there is none.
-- GF-FIX-F (review 低-19): the bags the picker and the bound check read:
-- 0-4 and the reagent bag (Enum.BagIndex.ReagentBag) when the client has
-- one. The automatic collection still reads 0-4 only (Supply.readBags; a
-- PM decision).
function L.bagIndexes()
    local list = {}
    for bag = 0, Supply.BAGS do list[#list + 1] = bag end
    local reagent = type(Enum) == "table" and type(Enum.BagIndex) == "table" and tonumber(Enum.BagIndex.ReagentBag) or nil
    if reagent and reagent > Supply.BAGS then list[#list + 1] = reagent end
    return list
end
function L.bagBound(itemID)
    local C = type(C_Container) == "table" and C_Container or nil
    if not C or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then return nil end
    local bound = false
    for _, bag in ipairs(L.bagIndexes()) do
        local n = tonumber((ns.call(C.GetContainerNumSlots, bag))) or 0
        for slot = 1, n do
            local info = ns.call(C.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and tonumber(info.itemID) == itemID then
                if info.isBound then bound = true else return "free" end
            end
        end
    end
    return bound and "bound" or nil
end
L.BOUND_OFFER = "背包裡的這個物品已綁定，不能供應"

-- nil when it may be listed, else why not (text for the form). The same for
-- 徵求 and 供應, except that 供應 also looks at the stacks in the bags
-- (GF-009-13: all of them bound: refused; none in the bags: allowed, it may
-- still be made or fetched).
function L.itemProblem(itemID, fromBag, direction)
    local info, why = L.itemInfo(itemID)
    if not info then return why == "loading" and "物品資料載入中，請稍後再試" or "無法辨識這個物品" end
    if not L.tradeable(info) then return "這個物品拾取綁定，不能交易" end
    if fromBag and fromBag.isBound then return "這個物品已綁定，不能交易" end
    if direction == "offer" and L.bagBound(itemID) == "bound" then return L.BOUND_OFFER end
    return nil
end

---------------------------------------------------------------------------
-- GF-UI-H: the item type, from the game's classID / subclassID (never chosen
-- by the player). Names: the client's own (GetItemInfo's type texts, else
-- GetItemClassInfo / GetItemSubClassInfo), else these.
---------------------------------------------------------------------------

L.CLASS_NAME = { [0] = "消耗品", [1] = "容器", [2] = "武器", [3] = "寶石", [4] = "護甲", [5] = "材料",
    [6] = "彈藥", [7] = "商品", [9] = "配方", [11] = "箭袋", [12] = "任務", [13] = "鑰匙", [15] = "雜項" }

local function clientClassName(classID)
    local fnc = (type(C_Item) == "table" and type(C_Item.GetItemClassInfo) == "function") and C_Item.GetItemClassInfo or GetItemClassInfo
    if type(fnc) ~= "function" then return nil end
    local okCall, name = pcall(fnc, classID)
    return okCall and type(name) == "string" and name ~= "" and name or nil
end
local function clientSubName(classID, subclassID)
    local fnc = (type(C_Item) == "table" and type(C_Item.GetItemSubClassInfo) == "function") and C_Item.GetItemSubClassInfo or GetItemSubClassInfo
    if type(fnc) ~= "function" then return nil end
    local okCall, name = pcall(fnc, classID, subclassID)
    return okCall and type(name) == "string" and name ~= "" and name or nil
end

function L.className(classID, info)
    if classID == nil then return "其他" end
    return (info and info.typeName) or clientClassName(classID) or L.CLASS_NAME[classID] or "其他"
end
function L.subclassName(classID, subclassID, info)
    if classID == nil or subclassID == nil then return nil end
    return (info and info.subTypeName) or clientSubName(classID, subclassID)
end

-- The listing category (wire code) from the item class; unknown classes keep
-- what the caller gave (old callers), else 其他.
function L.categoryFor(info, fallback)
    local cat = info and info.classID and L.CLASS_CATEGORY[info.classID]
    if cat then return cat end
    return byKey[fallback] and fallback or "other"
end

-- 「配方｜裁縫」: the type line shown in the form and the finder.
function L.typeText(info)
    if not info then return "" end
    local c = L.className(info.classID, info)
    local s = L.subclassName(info.classID, info.subclassID, info)
    if s and s ~= c then return c .. "｜" .. s end
    return c
end

-- Unbound items in this character's bags, one entry per ItemID (the 背包
-- picker; nothing is sent anywhere).
function L.bagItems()
    local C = type(C_Container) == "table" and C_Container or nil
    if not C or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then return nil end
    local seen, out = {}, {}
    for _, bag in ipairs(L.bagIndexes()) do
        local n = tonumber((ns.call(C.GetContainerNumSlots, bag))) or 0
        for slot = 1, n do
            local info = ns.call(C.GetContainerItemInfo, bag, slot)
            local id = type(info) == "table" and tonumber(info.itemID) or nil
            if id and info.isBound == false then
                local e = seen[id]
                if not e then
                    e = { itemID = id, count = 0, icon = info.iconFileID, link = info.hyperlink }
                    seen[id] = e
                    out[#out + 1] = e
                end
                e.count = e.count + (tonumber(info.stackCount) or 1)
            end
        end
    end
    table.sort(out, function(x, y) return x.itemID < y.itemID end)
    return out
end
-- GF-FIX-F (中-18): the finder's copy of bagItems(), read again only after
-- the bags changed (BAG_UPDATE_DELAYED, Supply.bagVersion) or when the
-- finder opens (L.forgetBags).
local bagMemo = {}
function L.forgetBags() bagMemo = {} end
function L.bagSnapshot()
    if bagMemo.v == Supply.bagVersion and bagMemo.list then return bagMemo.list end
    local list = L.bagItems()
    bagMemo = { v = Supply.bagVersion, list = list }
    return list
end

---------------------------------------------------------------------------
-- GF-UI-H: the item finder (自己背包沒有的物品也能刊登). Only what the client
-- already knows; no item database is shipped:
--   背包 unbound bag items; 刊登 my listings and the guild's received ones;
--   集料 the collection rules' items; 配方 the cached recipe reagents and
--   products; 行情 items in the price store (AH scans, merchants).
-- An item not in the client's cache is asked for only from the small sources
-- (it appears once the client has it); the price store never asks.
-- Untradeable items (拾取綁定, quest items, bound bag stacks) never appear.
---------------------------------------------------------------------------

L.CATALOG_MAX = 3000 -- IDs looked at per opening (the price store can be big)

local function addID(set, order, id, ask)
    id = tonumber(id)
    if not id or id <= 0 or id > 10000000 then return end
    if set[id] == nil then
        if #order >= L.CATALOG_MAX then return end
        set[id] = ask and true or false
        order[#order + 1] = id
    elseif ask then
        set[id] = true
    end
end

-- GF-FIX-F (中-18): a price store reagent text is decoded once (the same
-- text always gives the same list); a changed or new entry is a new text.
local reagentMemo, reagentMemoN = {}, 0
L.REAGENT_KEEP = 20000
local function reagentsOf(P, s)
    local r = reagentMemo[s]
    if r == nil then
        r = P.decodeReagents(s) or false
        if reagentMemoN >= L.REAGENT_KEEP then reagentMemo, reagentMemoN = {}, 0 end
        reagentMemo[s], reagentMemoN = r, reagentMemoN + 1
    end
    return r or nil
end
function L.forgetReagents() reagentMemo, reagentMemoN = {}, 0 end

-- { [itemID] = askServer } and the order they were found in.
function L.catalogIDs()
    local set, order = {}, {}
    for _, l in ipairs(L.own()) do addID(set, order, l.itemID, true) end
    local okAll, all = pcall(L.activeAll)
    for _, l in ipairs(okAll and all or {}) do addID(set, order, l.itemID, true) end
    for _, r in ipairs(ns.SupplyRules and ns.SupplyRules.list or {}) do
        for _, id in ipairs(r.order or {}) do addID(set, order, id, true) end
    end
    local P = ns.Prices
    local okDB, p = pcall(function() return P and P.db() end)
    if okDB and type(p) == "table" then
        for _, s in pairs(type(p.reagents) == "table" and p.reagents or {}) do
            local r = reagentsOf(P, s)
            if r then
                addID(set, order, r.output, true)
                for _, x in ipairs(r.list) do addID(set, order, x.id, true) end
            end
        end
        for id in pairs(type(p.vendor) == "table" and p.vendor or {}) do addID(set, order, id, false) end
        for _, items in pairs(type(p.ah) == "table" and p.ah or {}) do
            if type(items) == "table" then for id in pairs(items) do addID(set, order, id, false) end end
        end
    end
    return set, order
end

-- GF-009-12: a catalog row's info is made when read (rows on screen only).
-- GF-FIX-F (低-22): made once per row (rawset), not on every read.
local CAT_ROW = { __index = function(t, k)
    if k == "info" then
        local info = ns.SupplyCatalog.info(rawget(t, "ci"))
        rawset(t, "info", info)
        return info
    end
end }
-- classID, subclassID of a finder row without making a catalog row's info.
function L.rowKind(e)
    local ci = rawget(e, "ci")
    if ci and rawget(e, "info") == nil then return ns.SupplyCatalog.kindOf(ci) end
    return e.info.classID, e.info.subclassID
end
-- Sort key: type, subtype, name, ItemID (catalog rows: the catalog's own).
local function rowKey(e)
    local ci = rawget(e, "ci")
    if ci then
        local Cat = ns.SupplyCatalog
        local c, s = Cat.kindOf(ci)
        return c, s, Cat.nameOf(ci), e.itemID
    end
    local info = e.info
    return info.classID or 99, info.subclassID or 99, info.name, e.itemID
end
local function rowLess(x, y)
    local cx, sx, nx, ix = rowKey(x)
    local cy, sy, ny, iy = rowKey(y)
    if cx ~= cy then return cx < cy end
    if sx ~= sy then return sx < sy end
    if nx ~= ny then return nx < ny end
    return ix < iy
end

-- Lower case, for the name search (ASCII only; CJK has no case).
local function fold(s) return str(s):lower() end

-- The finder's list: { itemID, info, count, bag } sorted by type, then name.
-- opts.source "bag" (default) or "all"; opts.text a name part, an ItemID or
-- an item link; opts.class / opts.subclass the filters (nil = 全部).
function L.catalog(opts)
    opts = opts or {}
    local text0 = str(opts.text):gsub("^%s+", ""):gsub("%s+$", "")
    inNameSearch = opts.source == "all" and not (L.itemFromText(text0) or text0:match("^%d+$"))
    local okList, out = pcall(L.catalogList, opts)
    inNameSearch = false
    if not okList then error(out, 0) end
    return out
end
function L.catalogList(opts)
    local bag = {}
    local bagList = L.bagSnapshot() or {} -- GF-FIX-F (中-18): one bag read, kept until the bags change
    for _, b in ipairs(bagList) do bag[b.itemID] = b end
    local set, order
    if opts.source == "all" then
        set, order = L.catalogIDs()
    else
        set, order = {}, {}
    end
    for _, b in ipairs(bagList) do addID(set, order, b.itemID, true) end
    local text = str(opts.text):gsub("^%s+", ""):gsub("%s+$", "")
    local exact = L.itemFromText(text) or (text:match("^%d+$") and tonumber(text)) or nil
    if exact then addID(set, order, exact, true) end
    local needle = (exact or text == "") and nil or fold(text)
    local out, done = {}, {}
    -- GF-009-12: 全部 also searches the whole item catalog (no CATALOG_MAX;
    -- the finder pages). A row uses the client's data when the client already
    -- has it (the game wins), else the catalog's name, class and icon; the
    -- client is asked only when one item is previewed or chosen. Catalog rows
    -- are small ({ itemID, ci }); their info table is made when it is read
    -- (only the rows on screen), and they come in catalog order already.
    local Cat = ns.SupplyCatalog
    local catOn = opts.source == "all" and Cat ~= nil and Cat.load()
    local function classOK(c, s)
        return (opts.class == nil or c == opts.class) and (opts.subclass == nil or s == opts.subclass)
    end
    local catRows = {}
    if catOn then
        -- GF-009-13: the game's names of what is in the bags (already in the
        -- client) are searched too.
        for id in pairs(bag) do L.cachedInfo(id) end
        local hits
        if exact then
            hits = {}
            local i = Cat.index(exact)
            if i then hits[1] = i end
        else
            hits = Cat.search(needle and text or nil)
        end
        for _, i in ipairs(hits) do
            local id = Cat.idOf(i)
            local client = L.cachedInfo(id)
            local okRow
            if client then okRow = L.tradeable(client) and classOK(client.classID, client.subclassID)
            else okRow = classOK(Cat.kindOf(i)) end
            if okRow then
                local row = { itemID = id, ci = i } -- two fields: the smallest table
                if client then row.info = client else setmetatable(row, CAT_ROW) end
                local b = bag[id]
                if b then row.count, row.bag = b.count, true end
                catRows[#catRows + 1] = row
            end
            done[id] = true
        end
    end
    for _, id in ipairs(order) do
        -- A catalog item the search did not pick is not looked up again.
        local skip = done[id] or (catOn and Cat.index(id) ~= nil)
        local info
        if not skip then
            if opts.source == "all" and not bag[id] and id ~= exact then
                -- GF-009-13: 全部 never asks the server about an item it does
                -- not have (only one typed or linked ItemID is asked for).
                info = L.cachedInfo(id)
            else
                info = L.itemInfo(id, not set[id])
            end
        end
        if info and L.tradeable(info) then
            local okText = (exact and id == exact) or (not exact and (not needle or fold(info.name):find(needle, 1, true) ~= nil))
            if okText and classOK(info.classID, info.subclassID) then
                local b = bag[id]
                out[#out + 1] = { itemID = id, info = info, count = b and b.count or nil, bag = b ~= nil }
            end
        end
    end
    table.sort(out, rowLess)
    if #catRows == 0 then return out end
    -- Merge the (few) other rows into the catalog rows.
    local merged, a, b = {}, 1, 1
    while a <= #catRows or b <= #out do
        if b > #out or (a <= #catRows and not rowLess(out[b], catRows[a])) then
            merged[#merged + 1] = catRows[a]; a = a + 1
        else
            merged[#merged + 1] = out[b]; b = b + 1
        end
    end
    return merged
end

-- The filters' choices for a list from L.catalog (without the class / subclass
-- filter): { { value = classID, text } } and, for one class, its subclasses.
function L.catalogClasses(list)
    local seen, out = {}, {}
    for _, e in ipairs(list) do
        local c = L.rowKind(e)
        if c ~= nil and not seen[c] then
            seen[c] = true
            out[#out + 1] = { value = c, text = L.className(c, e.info) }
        end
    end
    table.sort(out, function(a, b) return a.value < b.value end)
    return out
end
function L.catalogSubclasses(list, classID)
    local seen, out = {}, {}
    if classID == nil then return out end
    for _, e in ipairs(list) do
        local c, s = L.rowKind(e)
        if c == classID and s ~= nil and not seen[s] then
            seen[s] = true
            out[#out + 1] = { value = s, text = L.subclassName(classID, s, e.info) or L.className(classID, e.info) }
        end
    end
    table.sort(out, function(a, b) return a.value < b.value end)
    return out
end

---------------------------------------------------------------------------
-- Create / edit / end (only this character's own listings exist here)
---------------------------------------------------------------------------

local function validDays(d)
    for _, x in ipairs(L.DAYS) do if x == d then return true end end
    return false
end

-- Check the form's fields. Returns the clean fields, or nil and the reason.
function L.check(f, editing)
    if not Supply.manualOn() then return nil, "手動刊登已關閉" end
    if f.direction ~= "need" and f.direction ~= "offer" then return nil, "請選擇徵求或供應" end
    local itemID = tonumber(f.itemID)
    if not itemID then return nil, "請放入物品（物品連結或從背包選）" end
    if not editing then
        local problem = L.itemProblem(itemID, f.bagInfo, f.direction)
        if problem then return nil, problem end
    end
    local qty = tonumber(f.quantity)
    if not qty or qty ~= math.floor(qty) or qty < 1 or qty > L.QTY_MAX then return nil, "數量請填 1～" .. L.QTY_MAX end
    local days = tonumber(f.days) or L.DEFAULT_DAYS
    if not validDays(days) then return nil, "有效期請選 3、7、14 或 30 天" end
    local note, why = L.cleanNote(f.note)
    if not note then return nil, why == "too-long" and ("備註最多 " .. L.NOTE_MAX .. " 字") or "備註有問題" end
    -- GF-009-14 B: 交易條件 (a new listing: 面議; an old one edited without
    -- choosing keeps 未標示).
    local terms = f.terms
    if terms == nil and not editing then terms = L.DEFAULT_TERMS end
    if terms ~= nil and not termsByKey[terms] then return nil, "請選擇交易條件" end
    local price
    if terms == "price" then
        price = tonumber(f.price)
        if not price or price ~= math.floor(price) or price < 1 then return nil, "訂價請填每個的價格" end
        if price > L.PRICE_MAX then return nil, "每個最多 " .. L.priceText(L.PRICE_MAX) end
    end
    -- GF-UI-H: the category follows the item's class (never the player's pick).
    local cat = L.categoryFor((L.itemInfo(itemID, true)), f.category)
    return { direction = f.direction, itemID = itemID, quantity = qty, days = days, note = note, category = cat,
        terms = terms, price = price }
end

-- The active listing of the same item and direction, if any (no silent sums).
function L.duplicateOf(itemID, direction, exceptID)
    for _, l in ipairs(L.ownActive()) do
        if l.itemID == itemID and l.direction == direction and l.id ~= exceptID then return l end
    end
    return nil
end

function L.create(f)
    local m = mine()
    if not m then return nil, "角色資料尚未載入" end
    local c, why = L.check(f)
    if not c then return nil, why end
    local dup = L.duplicateOf(c.itemID, c.direction)
    if dup then return nil, "已經有同一物品的" .. L.DIRECTION_TEXT[c.direction] .. "，請修改原本的刊登", dup end
    if #L.ownActive() >= L.MAX_ACTIVE then return nil, "刊登中最多 " .. L.MAX_ACTIVE .. " 筆" end
    local t = now()
    local id = m.nextID
    m.nextID = id + 1
    local l = { id = id, itemID = c.itemID, direction = c.direction, category = c.category, quantity = c.quantity,
        note = c.note, days = c.days, createdAt = t, updatedAt = t, expiresAt = t + c.days * 86400, rev = 1, status = "active",
        terms = c.terms, price = c.price }
    m.list[id] = l
    stats.created = stats.created + 1
    L.publish()
    return l
end

-- Change quantity, category, note; a new period starts from now (續期).
function L.update(id, f)
    local m = mine()
    local l = m and m.list[id]
    if not l then return nil, "找不到這筆刊登" end
    if l.status ~= "active" then return nil, "這筆刊登已結束" end
    f.direction, f.itemID = l.direction, l.itemID
    f.days = f.days or l.days
    if f.terms == nil then f.terms, f.price = l.terms, f.price or l.price end
    local c, why = L.check(f, true)
    if not c then return nil, why end
    local t = now()
    l.quantity, l.category, l.note, l.days = c.quantity, c.category, c.note, c.days
    l.terms, l.price = c.terms, c.price
    l.expiresAt, l.updatedAt, l.rev = t + c.days * 86400, t, (l.rev or 1) + 1
    stats.updated = stats.updated + 1
    L.publish()
    return l
end

function L.renew(id, days)
    local m = mine()
    local l = m and m.list[id]
    if not l then return nil, "找不到這筆刊登" end
    return L.update(id, { quantity = l.quantity, category = l.category, note = l.note, days = days or l.days,
        terms = l.terms, price = l.price })
end

-- status: "closed" (結束) or "cancelled" (取消).
function L.finish(id, status)
    local m = mine()
    local l = m and m.list[id]
    if not l or l.status ~= "active" then return false end
    l.status, l.updatedAt = status == "cancelled" and "cancelled" or "closed", now()
    stats.ended = stats.ended + 1
    L.publish()
    return true
end

-- GF-UI-H: 刪除 an ended listing of mine (已結束／已取消／已過期). It is
-- already missing from my published snapshot (that newer snapshot is its
-- tombstone), so removing the local copy cannot bring it back; its id is
-- never handed out again (nextID only grows). An active one is not deleted:
-- 結束 it first.
function L.remove(id)
    local m = mine()
    local l = m and m.list[id]
    if not l then return false, "找不到這筆刊登" end
    if l.status == "active" then return false, "刊登中的請先結束" end
    m.list[id] = nil
    stats.deleted = (stats.deleted or 0) + 1
    L.publish()
    return true
end

-- GF-UI-H: a received listing of an item the client knows as untradeable
-- (拾取綁定, quest item) is not shown on the page (Supply.view). Unknown items
-- stay (their data may still be loading). The radar keeps its own checks.
function L.shownOnPage(e)
    if not e or e.own or not e.manual or e.auto then return true end
    -- GF-FIX-F (中-17): only what the client already has; GetItemInfo on an
    -- unknown item would ask the server on every redraw.
    local info
    if type(C_Item) == "table" and type(C_Item.IsItemDataCachedByID) == "function" then
        info = L.cachedInfo(e.itemID)
    else
        info = L.itemInfo(e.itemID, true)
    end
    return info == nil or L.tradeable(info)
end

---------------------------------------------------------------------------
-- Everybody's active listings (read side)
---------------------------------------------------------------------------

-- { a, member, own, id, itemID, direction, category, quantity, note,
-- createdAt, expiresAt, fresh } for listings not past their time, from
-- members on the current roster; ours from our own list.
function L.activeAll()
    local Share = ns.Share
    local out = {}
    local selfA = Share.selfAuthor()
    local t = now()
    for _, l in ipairs(L.ownActive()) do
        if l.expiresAt > t then
            local e = ns.copy(l)
            e.a, e.own, e.fresh, e.seenT = selfA or "self", true, Supply.freshness(l.updatedAt, math.huge), l.updatedAt
            out[#out + 1] = e
        end
    end
    local s = Share.store()
    for a, groups in pairs(s and s.rec or {}) do
        local rec = groups[L.GROUP]
        local m = rec and a ~= selfA and Share.memberFor(a)
        if m then
            local terms = Share.decoded(a, L.TERMS_GROUP) or {} -- GF-009-14 B
            for _, l in ipairs(Share.decoded(a, L.GROUP) or {}) do
                if l.expiresAt > t and l.createdAt <= t + Share.FUTURE then
                    local e = ns.copy(l)
                    local x = terms[l.id]
                    e.terms, e.price = x and x.terms or nil, x and x.price or nil
                    -- the snapshot time is the author's last change of their listings
                    e.a, e.member, e.fresh, e.seenT = a, m, Supply.freshness(rec.t, math.huge), rec.t
                    out[#out + 1] = e
                end
            end
        end
    end
    return out
end

function L.diagText()
    local own = #L.ownActive()
    local others = 0
    for _, e in ipairs(L.activeAll()) do if not e.own then others = others + 1 end end
    return string.format("手動刊登：我的刊登中 %d 筆、公會有效 %d 筆｜這次登入新增 %d、修改 %d、結束 %d、拒收 %d 則",
        own, others, stats.created, stats.updated, stats.ended, stats.rejected)
end

-- Expire our own listings now and then (the record follows).
local sweeping = false
local function sweepLoop()
    if L.sweep() then L.publish() end
    ns.after(L.SWEEP_EVERY, sweepLoop)
end
function L.start()
    if sweeping then return end
    sweeping = true
    L.publish()
    ns.after(L.SWEEP_EVERY, sweepLoop)
end

function L.resetSession()
    for k in pairs(stats) do stats[k] = 0 end
    requests.all, requests.nameSearch = 0, 0
    sweeping = false
    L.forgetBags(); L.forgetReagents()
end

-- Started with the automatic collection (after the share login).
local startSupply = Supply.start
function Supply.start()
    startSupply()
    ns.after(1, L.start)
end
