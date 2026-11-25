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
L.STATUS_TEXT = { active = "刊登中", closed = "已結束", cancelled = "已取消", expired = "已過期" }

local stats = { rejected = 0, created = 0, updated = 0, ended = 0 }
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

---------------------------------------------------------------------------
-- Wire value of group L
---------------------------------------------------------------------------

local b36, unb36 = ns.Share.b36, ns.Share.unb36

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

-- { name, link, icon, classID, bindType } or nil, "loading" / "unknown".
function L.itemInfo(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then return nil, "unknown" end
    local getInfo = (type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function") and C_Item.GetItemInfo or GetItemInfo
    if type(getInfo) ~= "function" then return nil, "unknown" end
    local okCall, name, link, _, _, _, _, _, _, _, icon, _, classID, _, bindType = pcall(getInfo, itemID)
    if not okCall then return nil, "unknown" end
    if type(name) ~= "string" or name == "" then
        if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then ns.call(C_Item.RequestLoadItemDataByID, itemID) end
        return nil, "loading"
    end
    return { itemID = itemID, name = name, link = type(link) == "string" and link or nil,
        icon = icon or Supply.itemIcon(itemID), classID = tonumber(classID), bindType = tonumber(bindType) }
end

-- nil when it may be listed, else why not (text for the form).
function L.itemProblem(itemID, fromBag)
    local info, why = L.itemInfo(itemID)
    if not info then return why == "loading" and "物品資料載入中，請稍後再試" or "無法辨識這個物品" end
    if info.bindType == 1 or info.bindType == 4 then return "這個物品拾取綁定，不能交易" end
    if fromBag and fromBag.isBound then return "這個物品已綁定，不能交易" end
    return nil
end

-- Unbound items in this character's bags, one entry per ItemID (the 背包
-- picker; nothing is sent anywhere).
function L.bagItems()
    local C = type(C_Container) == "table" and C_Container or nil
    if not C or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then return nil end
    local seen, out = {}, {}
    for bag = 0, Supply.BAGS do
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
        local problem = L.itemProblem(itemID, f.bagInfo)
        if problem then return nil, problem end
    end
    local qty = tonumber(f.quantity)
    if not qty or qty ~= math.floor(qty) or qty < 1 or qty > L.QTY_MAX then return nil, "數量請填 1～" .. L.QTY_MAX end
    local days = tonumber(f.days) or L.DEFAULT_DAYS
    if not validDays(days) then return nil, "有效期請選 3、7、14 或 30 天" end
    local note, why = L.cleanNote(f.note)
    if not note then return nil, why == "too-long" and ("備註最多 " .. L.NOTE_MAX .. " 字") or "備註有問題" end
    local cat = byKey[f.category] and f.category or "other"
    return { direction = f.direction, itemID = itemID, quantity = qty, days = days, note = note, category = cat }
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
        note = c.note, days = c.days, createdAt = t, updatedAt = t, expiresAt = t + c.days * 86400, rev = 1, status = "active" }
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
    local c, why = L.check(f, true)
    if not c then return nil, why end
    local t = now()
    l.quantity, l.category, l.note, l.days = c.quantity, c.category, c.note, c.days
    l.expiresAt, l.updatedAt, l.rev = t + c.days * 86400, t, (l.rev or 1) + 1
    stats.updated = stats.updated + 1
    L.publish()
    return l
end

function L.renew(id, days)
    local m = mine()
    local l = m and m.list[id]
    if not l then return nil, "找不到這筆刊登" end
    return L.update(id, { quantity = l.quantity, category = l.category, note = l.note, days = days or l.days })
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
            for _, l in ipairs(Share.decoded(a, L.GROUP) or {}) do
                if l.expiresAt > t and l.createdAt <= t + Share.FUTURE then
                    local e = ns.copy(l)
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
    sweeping = false
end

-- Started with the automatic collection (after the share login).
local startSupply = Supply.start
function Supply.start()
    startSupply()
    ns.after(1, L.start)
end
