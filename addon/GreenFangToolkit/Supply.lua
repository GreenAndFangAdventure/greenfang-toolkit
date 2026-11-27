-- Supply (GF-009-03/04/06, v2.0 §7, 附錄 A §4～§9): the automatic collection
-- snapshot of this character, the COLLECTION record group on GFTKS, and the
-- one query the 綠皮調貨所 page reads (automatic snapshots + manual listings,
-- SupplyListings.lua).
--
-- COLLECTION on GFTKS (Share.lua record layer): group "C<num>" per collection
-- rule, one whole snapshot per author: "<rulesVersion>/<missing>/<surplus>",
-- each list "<itemID>.<qty>" in base 36, "," separated, positive numbers
-- only. A newer snapshot replaces the whole old one (items not listed are 0);
-- an empty snapshot ("1//") clears what others hold. The record's t is the
-- author's server time when they scanned; relays never change it (Share.lua),
-- so freshness always counts from the author. Same-second versions: the
-- author's own record time only moves forward (Share.ownRecord), so the newer
-- version always has the larger t; no extra sequence number is needed.
-- Nothing here goes to GF Sync or the site (group registered as local).
--
-- Work: in combat only a dirty flag; out of combat one full scan 3 seconds
-- after the last bag / quest event (at most 10 seconds after the first). A
-- snapshot goes out only when its value changed (Share.ownRecord sends it
-- after Share.CHANGE_DELAY, which also merges quick changes); an unchanged
-- one only moves its time forward now and then.

local _, ns = ...
local str = ns.str

local Supply = {}
ns.Supply = Supply
local Rules = ns.SupplyRules

Supply.SCHEMA = 1
Supply.DEBOUNCE = 3
Supply.MAX_WAIT = 10
Supply.LOGIN_JITTER = { 5, 30 }      -- seconds after the share login (附錄 A §5)
Supply.CONFIRM_EVERY = 30 * 60      -- an unchanged snapshot: move its time at most this often
Supply.RESEND_EVERY = 6 * 3600      -- ... and send it again this often (the others' copy stays fresh)
Supply.SURPLUS_TTL = 12 * 3600       -- 附錄 A §6.3
Supply.MISSING_TTL = 72 * 3600
Supply.RECENT = 3600                -- 近期 (else 稍早, until the TTL)
Supply.MAX_QTY = 200                -- per item in a snapshot
Supply.MAX_VALUE = 600              -- bytes of one snapshot value
Supply.MAX_FOREIGN_ITEMS = 64       -- items in a snapshot of a rules version we do not know
Supply.BAGS = 4                     -- bag 0 (backpack) .. 4

Supply.rand = function(a, b) return a + math.random() * (b - a) end -- tests replace it

local stats = { scans = 0, dirty = 0, combatSkips = 0, published = 0, confirmed = 0, resent = 0,
    rejected = 0, unsupported = 0, errors = {} }
Supply.stats = stats

local function note(err)
    local list = stats.errors
    for _, e in ipairs(list) do if e == err then return end end
    list[#list + 1] = err
    while #list > 5 do table.remove(list, 1) end
end
Supply.note = note

---------------------------------------------------------------------------
-- Saved state: GreenFangToolkitDB.supply (附錄 A §8). A schema we do not
-- know clears this table only.
---------------------------------------------------------------------------

function Supply.db()
    local db = ns.db
    if not db then return nil end
    if type(db.supply) ~= "table" or db.supply.v ~= Supply.SCHEMA then db.supply = { v = Supply.SCHEMA } end
    local s = db.supply
    if type(s.listings) ~= "table" then s.listings = {} end
    if type(s.sentAt) ~= "table" then s.sentAt = {} end
    return s
end

-- Automatic collection on? Default: only when a rule is checked in game; an
-- experimental rule needs the player's own 試用 (s.auto == true).
function Supply.autoOn()
    local s = Supply.db()
    if s and s.auto ~= nil then return s.auto == true end
    return #Rules.active(false) > 0
end
function Supply.manualOn()
    local s = Supply.db()
    return not (s and s.manual == false)
end
function Supply.activeRules()
    if not Supply.autoOn() then return {} end
    local s = Supply.db()
    return Rules.active(s and s.auto == true)
end
function Supply.isActive(rule)
    for _, r in ipairs(Supply.activeRules()) do if r == rule then return true end end
    return false
end

---------------------------------------------------------------------------
-- Reading the game (capability detection; 附錄 A §4.1)
---------------------------------------------------------------------------

-- fn(...) -> ok, value (ok false when the call raised an error)
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    local okCall, v = pcall(fn, ...)
    if not okCall then return false end
    if ns.isSecret and ns.isSecret(v) then return false end
    return true, v
end

-- A function questID -> "done" / "active" / "idle" / nil (unknown), or nil
-- when this client lacks the quest functions.
function Supply.questReader()
    local Q = type(C_QuestLog) == "table" and C_QuestLog or nil
    if not Q then return nil end
    local flagged = Q.IsQuestFlaggedCompleted
    local onQuest = Q.IsOnQuest
    local logIndex = Q.GetLogIndexForQuestID
    if type(flagged) ~= "function" or (type(onQuest) ~= "function" and type(logIndex) ~= "function") then return nil end
    return function(questID)
        if type(questID) ~= "number" then return nil end
        local okDone, done = try(flagged, questID)
        if not okDone or type(done) ~= "boolean" then return nil end
        if done then return "done" end
        if type(onQuest) == "function" then
            local okOn, on = try(onQuest, questID)
            if okOn and type(on) == "boolean" then return on and "active" or "idle" end
            return nil
        end
        local okIdx, idx = try(logIndex, questID)
        if not okIdx then return nil end
        if idx == nil then return "idle" end
        if type(idx) ~= "number" then return nil end
        return idx > 0 and "active" or "idle"
    end
end

-- Counts of the wanted ItemIDs in this character's bags (never the bank):
-- { [itemID] = { count = n, eligible = n } }; eligible leaves out bound or
-- locked items and items whose state is unknown. nil when the bags cannot
-- be read.
function Supply.readBags(wanted)
    local C = type(C_Container) == "table" and C_Container or nil
    if not C or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then
        return nil, "no-bag-api"
    end
    local out = {}
    for bag = 0, Supply.BAGS do
        local okN, n = try(C.GetContainerNumSlots, bag)
        if not okN then return nil, "bag-error" end
        n = tonumber(n) or 0
        for slot = 1, n do
            local okI, info = try(C.GetContainerItemInfo, bag, slot)
            if not okI then return nil, "bag-error" end
            local id = type(info) == "table" and tonumber(info.itemID) or nil
            if id and wanted[id] then
                local c = out[id] or { count = 0, eligible = 0 }
                local k = tonumber(info.stackCount) or 1
                c.count = c.count + k
                if info.isBound == false and not info.isLocked then c.eligible = c.eligible + k end
                out[id] = c
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The calculation (pure; 附錄 A §3.2, §4.2, §4.3)
---------------------------------------------------------------------------

-- rule, questState(questID) -> "done"/"active"/"idle"/nil, bags as above.
-- Returns { missing = { [itemID] = n }, surplus = { [itemID] = n },
-- unknown = { [itemID] = true } }. A chapter whose state is unknown adds
-- nothing (no guessed need, no guessed surplus).
function Supply.compute(rule, questState, bags)
    local snap = { missing = {}, surplus = {}, unknown = {} }
    local parentDone = rule.parentQuestID and questState(rule.parentQuestID) == "done"
    for _, ch in ipairs(rule.chapters) do
        local st = parentDone and "done" or questState(ch.questID)
        for _, it in ipairs(ch.items) do
            local id = it.itemID
            if st == nil then
                snap.unknown[id] = true
            else
                local need, reserve = 0, 0
                if st == "active" then need, reserve = it.need, it.need
                elseif st == "idle" then reserve = rule.reserveWhenIdle or 1 end
                local b = bags[id] or { count = 0, eligible = 0 }
                local missing = math.max(0, need - (b.count or 0))
                if missing > 0 then snap.missing[id] = math.min(missing, Supply.MAX_QTY) end
                if rule.candidateTradeable then
                    local extra = math.max(0, (b.eligible or 0) - reserve)
                    if extra > 0 then snap.surplus[id] = math.min(extra, Supply.MAX_QTY) end
                end
            end
        end
    end
    return snap
end

---------------------------------------------------------------------------
-- Wire value of a COLLECTION snapshot
---------------------------------------------------------------------------

local b36, unb36 = ns.Share.b36, ns.Share.unb36

local function encodeList(map)
    local ids = {}
    for id, q in pairs(map or {}) do if q > 0 then ids[#ids + 1] = id end end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = b36(id) .. "." .. b36(math.floor(map[id])) end
    return table.concat(out, ",")
end

function Supply.encode(rule, snap)
    return tostring(rule.rulesVersion) .. "/" .. encodeList(snap and snap.missing) .. "/" .. encodeList(snap and snap.surplus)
end
function Supply.emptyValue(rule) return tostring(rule.rulesVersion) .. "//" end

local function decodeList(s, limit)
    local map, n = {}, 0
    if s == "" then return map, 0 end
    for item in (s .. ","):gmatch("([^,]*),") do
        local id, q = item:match("^([0-9a-z]+)%.([0-9a-z]+)$")
        id, q = id and unb36(id), q and unb36(q)
        if not id or not q or id <= 0 or q <= 0 or q > Supply.MAX_QTY or map[id] then return nil end
        map[id] = q
        n = n + 1
        if n > limit then return nil end
    end
    return map, n
end

-- Value -> { num, rulesVersion, missing, surplus, empty } or nil (rejected).
-- A rules version newer than ours is kept (it replaces the author's old
-- snapshot) but marked unsupported: never matched with our item rules.
function Supply.decode(g, v)
    local num = Rules.numOfGroup(g)
    local rule = num and Rules.byNum(num)
    if not rule or type(v) ~= "string" or #v > Supply.MAX_VALUE then stats.rejected = stats.rejected + 1; return nil end
    local rv, m, s = v:match("^(%d+)/([^/]*)/([^/]*)$")
    rv = tonumber(rv)
    if not rv or rv < 1 then stats.rejected = stats.rejected + 1; return nil end
    if rv ~= rule.rulesVersion then
        local mm = decodeList(m, Supply.MAX_FOREIGN_ITEMS)
        local ss = mm and decodeList(s, Supply.MAX_FOREIGN_ITEMS)
        if not ss then stats.rejected = stats.rejected + 1; return nil end
        stats.unsupported = stats.unsupported + 1
        return { num = num, rulesVersion = rv, unsupported = true, missing = {}, surplus = {}, empty = true }
    end
    local limit = #rule.order
    local missing = decodeList(m, limit)
    local surplus = missing and decodeList(s, limit)
    if not surplus then stats.rejected = stats.rejected + 1; return nil end
    for id in pairs(missing) do
        if not rule.items[id] or surplus[id] then stats.rejected = stats.rejected + 1; return nil end
    end
    for id in pairs(surplus) do
        if not rule.items[id] then stats.rejected = stats.rejected + 1; return nil end
    end
    return { num = num, rulesVersion = rv, missing = missing, surplus = surplus,
        empty = next(missing) == nil and next(surplus) == nil }
end

ns.Share.registerGroup({
    name = "COLLECTION",
    ["local"] = true,
    match = function(g)
        local n = Rules.numOfGroup(g)
        return n ~= nil and Rules.byNum(n) ~= nil
    end,
    encode = function(g, d)
        local rule = Rules.byNum(Rules.numOfGroup(g) or -1)
        return rule and Supply.encode(rule, d) or nil
    end,
    decode = Supply.decode,
})

---------------------------------------------------------------------------
-- This character's snapshot: scan and publish
---------------------------------------------------------------------------

local last = { scanAt = nil, questOK = nil, bagOK = nil, missing = 0, surplus = 0, snaps = {} }
Supply.last = last

-- Store (and later send) our snapshot of rule when it changed; when it did
-- not, only move its time now and then. Returns what happened.
local function publish(rule, value)
    local Share = ns.Share
    local a = Share.selfAuthor()
    if not a or not Share.store() then return "no-store" end
    local g = Rules.groupOf(rule)
    local rec = Share.get(a, g)
    local now = Share.serverNow()
    if rec and rec.v == value then
        if now - rec.t < Supply.CONFIRM_EVERY then return "same" end
        Share.ownRecord(g, value)
        stats.confirmed = stats.confirmed + 1
        local sent = Supply.db().sentAt
        if now - (sent[a .. "|" .. g] or 0) >= Supply.RESEND_EVERY then
            sent[a .. "|" .. g] = now
            if Share.sendRecord(a, g, true) then stats.resent = stats.resent + 1 end
        end
        return "confirm"
    end
    -- Nothing published yet and nothing to say: no record at all.
    if not rec and value == Supply.emptyValue(rule) then return "none" end
    local r = Share.ownRecord(g, value)
    if r == "stored" then
        stats.published = stats.published + 1
        Supply.db().sentAt[a .. "|" .. g] = now
    end
    return r
end
Supply.publish = publish

-- One full scan (out of combat). Rules that are not active publish an empty
-- snapshot once, so the others drop what they held.
function Supply.scanNow()
    if ns.inCombat() then stats.combatSkips = stats.combatSkips + 1; return "combat" end
    Supply.dirty = false
    stats.scans = stats.scans + 1
    -- GF-FIX-F (review 低-22): the page hears about a scan only when it
    -- changed something it shows (a snapshot stored, the counts, a read
    -- that failed or came back, the first scan).
    local before = table.concat({ tostring(last.scanAt ~= nil), tostring(last.questOK), tostring(last.bagOK),
        tostring(last.missing), tostring(last.surplus) }, "|")
    local stored = false
    last.scanAt = ns.Share.serverNow()
    local active = Supply.activeRules()
    local activeSet = {}
    for _, r in ipairs(active) do activeSet[r] = true end
    -- Inactive rules: clear an old snapshot.
    for _, rule in ipairs(Rules.list) do
        if rule.usable and not activeSet[rule] then
            local a = ns.Share.selfAuthor()
            local rec = a and ns.Share.get(a, Rules.groupOf(rule))
            if rec and rec.v ~= Supply.emptyValue(rule) and publish(rule, Supply.emptyValue(rule)) == "stored" then stored = true end
            last.snaps[rule.collectionID] = nil
        end
    end
    if #active == 0 then last.missing, last.surplus = 0, 0; return "off" end
    local questState = Supply.questReader()
    last.questOK = questState ~= nil
    if not questState then note("任務資料讀不到：自動集料暫停"); return "no-quest-api" end
    local wanted = {}
    for _, rule in ipairs(active) do for id in pairs(rule.items) do wanted[id] = true end end
    local bags, why = Supply.readBags(wanted)
    last.bagOK = bags ~= nil
    if not bags then note("背包讀不到：自動集料暫停（" .. tostring(why) .. "）"); return why end
    local missing, surplus = 0, 0
    for _, rule in ipairs(active) do
        local snap = Supply.compute(rule, questState, bags)
        last.snaps[rule.collectionID] = snap
        for _ in pairs(snap.missing) do missing = missing + 1 end
        for _ in pairs(snap.surplus) do surplus = surplus + 1 end
        if next(snap.unknown) then note("有任務狀態不明的章節：那些物品不列入供需") end
        if publish(rule, Supply.encode(rule, snap)) == "stored" then stored = true end
    end
    last.missing, last.surplus = missing, surplus
    local after = table.concat({ "true", tostring(last.questOK), tostring(last.bagOK),
        tostring(last.missing), tostring(last.surplus) }, "|")
    if (stored or after ~= before) and Supply.onChanged then Supply.onChanged() end
    return "ok"
end

-- Bag / quest events: only a flag in combat; out of combat a scan after
-- Supply.DEBOUNCE quiet seconds (at most Supply.MAX_WAIT after the first).
local timerOn, firstAt, lastAt = false, nil, nil
local function fire()
    timerOn = false
    if ns.inCombat() then stats.combatSkips = stats.combatSkips + 1; return end
    local now = ns.now()
    if lastAt and now - lastAt < Supply.DEBOUNCE and firstAt and now - firstAt < Supply.MAX_WAIT then
        timerOn = true
        ns.after(Supply.DEBOUNCE - (now - lastAt), fire)
        return
    end
    firstAt, lastAt = nil, nil
    Supply.scanNow()
end

function Supply.markDirty()
    Supply.dirty = true
    stats.dirty = stats.dirty + 1
    if not Supply.started or ns.inCombat() then return end
    local now = ns.now()
    lastAt = now
    if timerOn then return end
    firstAt = now
    timerOn = true
    ns.after(Supply.DEBOUNCE, fire)
end

function Supply.start()
    if Supply.started then return end
    Supply.started = true
    Supply.dirty = true
    ns.after(Supply.rand(Supply.LOGIN_JITTER[1], Supply.LOGIN_JITTER[2]), function()
        if Supply.dirty then Supply.markDirty() end
    end)
end

-- Switches (the page and the diagnostics); turning one off publishes an
-- empty snapshot / listing record, so the others clear what they hold.
function Supply.setAuto(on)
    local s = Supply.db()
    if not s then return end
    s.auto = on and true or false
    if Supply.started then Supply.scanNow() end
    if Supply.onChanged then Supply.onChanged() end
end
function Supply.setManual(on)
    local s = Supply.db()
    if not s then return end
    s.manual = on and true or false
    if ns.SupplyListings then ns.SupplyListings.publish() end
    if Supply.onChanged then Supply.onChanged() end
end

local events = CreateFrame("Frame")
-- GF-FIX-F (review 中-16): the item data events (GET_ITEM_INFO_RECEIVED,
-- ITEM_DATA_LOAD_RESULT) are no longer ours: Widgets.lua passes on only the
-- answers to the toolkit's own requests (W.onItemAnswer, below).
Supply.EVENTS = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_REGEN_ENABLED" }
for _, e in ipairs(Supply.EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- After the share login (Init.lua) so the guild and roster are known.
        if not Supply.started then
            ns.after(ns.Share.LOGIN_DELAY, function() Supply.start() end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Next frame: Init.lua clears the toolkit's combat flag after us.
        ns.after(0, function()
            if Supply.dirty then Supply.markDirty() end
            if ns.SupplyListings then ns.SupplyListings.afterCombat() end
        end)
    else
        -- GF-FIX-F (中-18): the finder's bag list is read again after a change.
        if event == "BAG_UPDATE_DELAYED" then Supply.bagVersion = Supply.bagVersion + 1 end
        Supply.markDirty()
    end
end)
Supply.bagVersion = 0

-- GF-009-13: (itemID, success): success = false is "no such item". Only the
-- answers to our own requests come here, at once (GF-FIX-F, 中-16).
ns.Widgets.onItemAnswer(function(itemID, success)
    if ns.SupplyListings and ns.SupplyListings.itemAnswer then ns.SupplyListings.itemAnswer(itemID, success) end
    if Supply.onItemInfo then Supply.onItemInfo(itemID, success) end
end)

---------------------------------------------------------------------------
-- Everybody's snapshots (read side; 附錄 A §6.3, §7.4)
---------------------------------------------------------------------------

function Supply.freshness(t, ttl)
    local age = ns.Share.serverNow() - (t or 0)
    if age < -ns.Share.FUTURE or age >= ttl then return "expired" end
    if age < Supply.RECENT then return "recent" end
    return "earlier"
end
Supply.FRESH_TEXT = { recent = "近期", earlier = "稍早", expired = "過期", unknown = "未知" }

-- Snapshots of active rules from guild members (and ourselves). Each:
-- { a, member, own, rule, t, missing, surplus, missingFresh, surplusFresh }.
-- Members not on the current roster, unsupported rules versions and expired
-- halves are left out.
local snapCache = {}
function Supply.snapshots()
    local Share = ns.Share
    local key = tostring(Share.version) .. "|" .. tostring(Supply.autoOn()) .. "|" .. math.floor(Share.serverNow() / 60)
    if snapCache.key == key then return snapCache.list end
    local list, counts = {}, { valid = 0, expired = 0, unsupported = 0 }
    local s = Share.store()
    local selfA = Share.selfAuthor()
    local active = Supply.activeRules()
    for a, groups in pairs(s and s.rec or {}) do
        local m = Share.memberFor(a)
        for _, rule in ipairs(active) do
            local rec = groups[Rules.groupOf(rule)]
            if rec and (m or a == selfA) then
                local d = Share.decoded(a, Rules.groupOf(rule))
                if d and d.unsupported then
                    counts.unsupported = counts.unsupported + 1
                elseif d and not d.empty then
                    local mf = Supply.freshness(rec.t, Supply.MISSING_TTL)
                    local sf = Supply.freshness(rec.t, Supply.SURPLUS_TTL)
                    if mf == "expired" and sf == "expired" then
                        counts.expired = counts.expired + 1
                    else
                        counts.valid = counts.valid + 1
                        list[#list + 1] = { a = a, member = m, own = a == selfA, rule = rule, t = rec.t,
                            missing = mf ~= "expired" and d.missing or {}, surplus = sf ~= "expired" and d.surplus or {},
                            missingFresh = mf, surplusFresh = sf }
                    end
                end
            end
        end
    end
    snapCache = { key = key, list = list, counts = counts }
    return list, counts
end
function Supply.snapshotCounts()
    Supply.snapshots()
    return snapCache.counts or { valid = 0, expired = 0, unsupported = 0 }
end
function Supply.invalidate() snapCache = {} end

---------------------------------------------------------------------------
-- The one query (v2.0 §7.2): automatic and manual entries of the same
-- person, item and direction are one entry with both sources, never added
-- up. direction: "need" (缺件／徵求) or "offer" (可能有多／供應).
---------------------------------------------------------------------------

-- Returns a list of entries { key, a, member, own, itemID, direction, qty,
-- auto = n or nil, manual = listing or nil, manuals = { listings } or nil,
-- t, fresh, rule }. One entry per person, item and direction: a provider is
-- counted once and qty is the largest single source (an automatic bag
-- candidate and a manual promise of the same things are not two supplies).
-- GF-016: every manual listing is kept in manuals (an old client may send
-- two of the same item and direction); manual is the largest of them.
function Supply.entries()
    local byKey, list = {}, {}
    local function add(a, member, own, itemID, direction, qty, t, fresh, src, payload, rule)
        local key = a .. "|" .. itemID .. "|" .. direction
        local e = byKey[key]
        if not e then
            e = { key = key, a = a, member = member, own = own, itemID = itemID, direction = direction, qty = 0, t = 0 }
            byKey[key] = e
            list[#list + 1] = e
        end
        if src == "auto" then
            e.auto = math.max(e.auto or 0, qty); e.rule = e.rule or rule
        else
            e.manuals = e.manuals or {}
            e.manuals[#e.manuals + 1] = payload
            if not e.manual or (payload.quantity or 0) > (e.manual.quantity or 0) then e.manual = payload end
        end
        e.qty = math.max(e.qty, qty) -- one gap / one supply, never two
        if t > e.t then e.t, e.fresh = t, fresh end
    end
    for _, sn in ipairs(Supply.snapshots()) do
        for id, q in pairs(sn.missing) do add(sn.a, sn.member, sn.own, id, "need", q, sn.t, sn.missingFresh, "auto", nil, sn.rule) end
        for id, q in pairs(sn.surplus) do add(sn.a, sn.member, sn.own, id, "offer", q, sn.t, sn.surplusFresh, "auto", nil, sn.rule) end
    end
    if ns.SupplyListings and Supply.manualOn() then
        for _, l in ipairs(ns.SupplyListings.activeAll()) do
            add(l.a, l.member, l.own, l.itemID, l.direction, l.quantity, l.seenT or l.createdAt, l.fresh, "manual", l)
        end
    end
    return list
end

local function online(e) return e.member and e.member.online == true end
local function better(x, y)
    local ox, oy = online(x), online(y)
    if ox ~= oy then return ox end
    if x.t ~= y.t then return x.t > y.t end
    if x.qty ~= y.qty then return x.qty > y.qty end
    return x.a < y.a
end
Supply.better = better

-- The page's three lists. Each item: { itemID, qty (mine) or nil, mine =
-- entry or nil, others = { entries }, rule, label }.
--   mine "need":  what I lack, others = who may have it
--   mine "offer": what I may have extra, others = who needs it
--   guild:        everybody else's needs and offers, by item
-- GF-FIX-F: entries = a Supply.entries() list read once by the caller (the radar).
function Supply.view(kind, entries)
    local all = {}
    -- GF-UI-H: others' manual listings of untradeable items are left out here.
    local Lst = ns.SupplyListings
    for _, e in ipairs(entries or Supply.entries()) do
        if not (Lst and Lst.shownOnPage) or Lst.shownOnPage(e) then all[#all + 1] = e end
    end
    local items, order = {}, {}
    local function itemFor(id)
        local it = items[id]
        if not it then it = { itemID = id, others = {}, needs = {}, offers = {} }; items[id] = it; order[#order + 1] = it end
        return it
    end
    if kind == "need" or kind == "offer" then
        local other = kind == "need" and "offer" or "need"
        for _, e in ipairs(all) do
            if e.own and e.direction == kind then
                local it = itemFor(e.itemID)
                it.mine, it.qty, it.rule = e, e.qty, e.rule
            end
        end
        for _, e in ipairs(all) do
            if not e.own and e.direction == other and items[e.itemID] then
                local list = items[e.itemID].others
                list[#list + 1] = e
            end
        end
    else
        for _, e in ipairs(all) do
            if not e.own then
                local it = itemFor(e.itemID)
                local list = e.direction == "need" and it.needs or it.offers
                list[#list + 1] = e
                it.others[#it.others + 1] = e
                it.rule = it.rule or e.rule
            end
        end
    end
    for _, it in ipairs(order) do
        table.sort(it.others, better)
        table.sort(it.needs, better)
        table.sort(it.offers, better)
        local onlineN = 0
        for _, e in ipairs(it.others) do if online(e) then onlineN = onlineN + 1 end end
        it.onlineCount = onlineN
    end
    -- Items with an online match first, then any match, then the newest.
    table.sort(order, function(x, y)
        if (x.onlineCount > 0) ~= (y.onlineCount > 0) then return x.onlineCount > 0 end
        if (#x.others > 0) ~= (#y.others > 0) then return #x.others > 0 end
        local tx = x.others[1] and x.others[1].t or (x.mine and x.mine.t or 0)
        local ty = y.others[1] and y.others[1].t or (y.mine and y.mine.t or 0)
        if tx ~= ty then return tx > ty end
        return x.itemID < y.itemID
    end)
    return order
end

---------------------------------------------------------------------------
-- Items (names, icons, links) and contact
---------------------------------------------------------------------------

-- GF-009-13 fix: C_Item.GetItemInfo first (Forever answers it; the global
-- GetItemInfo gave nothing in the owner's probe).
function Supply.getItemInfo(itemID) return ns.itemInfo(itemID) end

function Supply.itemName(itemID)
    if ns.Widgets.itemFailed(itemID) then return nil end -- GF-FIX-F: never read or asked again
    local name
    if type(C_Item) == "table" and type(C_Item.GetItemNameByID) == "function" then name = ns.call(C_Item.GetItemNameByID, itemID) end
    if type(name) ~= "string" or name == "" then name = Supply.getItemInfo(itemID) end
    if type(name) == "string" and name ~= "" then return name end
    -- GF-FIX-F (中-17): one request per item until it is answered; none for a missing one.
    ns.Widgets.requestItem(itemID)
    return nil
end
-- What a row shows: the client's name, else the rule's label, else 載入中.
function Supply.itemLabel(itemID)
    local name = Supply.itemName(itemID)
    if name then return name, true end
    if ns.Widgets.itemFailed(itemID) then return ns.Widgets.TEXT.itemMissing, false end -- GF-FIX-F
    for _, r in ipairs(Rules.list) do
        local it = r.items and r.items[itemID]
        if it and it.label then return r.title .. " " .. it.label, false end
    end
    return "物品資料載入中", false
end
function Supply.itemIcon(itemID)
    local icon
    if type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then icon = ns.call(C_Item.GetItemIconByID, itemID) end
    if not icon and type(GetItemIcon) == "function" then icon = ns.call(GetItemIcon, itemID) end
    return icon
end
function Supply.itemLink(itemID)
    local _, link = Supply.getItemInfo(itemID)
    if type(link) == "string" and link:find("|Hitem:", 1, true) then return link end
    return nil
end

-- The neutral text a contact button puts into the whisper box (附錄 A §7.5).
function Supply.contactText(e)
    local what = Supply.itemLink(e.itemID) or Supply.itemName(e.itemID) or "這個物品"
    if e.direction == "offer" then
        return "你好，我在綠皮調貨所看到你可能有多的" .. what .. "，請問方便談談交換方式嗎？"
    end
    return "你好，我在綠皮調貨所看到你在找" .. what .. "，我可能有，方便談談交換方式嗎？"
end

-- Whisper target: the roster's full name (Name-Realm), never cut by hand.
function Supply.contactName(e)
    local m = e and e.member
    local name = m and str(m.name) or ""
    if name == "" then return nil end
    return name
end

local function chatUtil(modern, legacy)
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil[modern]) == "function" then return ChatFrameUtil[modern] end
    if type(_G[legacy]) == "function" then return _G[legacy] end
    return nil
end
function Supply.canContact(e)
    if not Supply.contactName(e) or e.own then return false end
    return chatUtil("SendTellWithMessage", "ChatFrame_SendTellWithMessage") ~= nil
        or chatUtil("OpenChat", "ChatFrame_OpenChat") ~= nil
end
-- Opens the whisper box with the text in it; the player presses Enter.
function Supply.contact(e)
    local name = Supply.contactName(e)
    if not name or e.own then return false end
    local text = Supply.contactText(e)
    local withText = chatUtil("SendTellWithMessage", "ChatFrame_SendTellWithMessage")
    if withText and pcall(withText, name, text) then return true end
    local open = chatUtil("OpenChat", "ChatFrame_OpenChat")
    if open and pcall(open, "/w " .. name .. " " .. text) then return true end
    note("無法開啟密語框")
    return false
end

---------------------------------------------------------------------------
-- Diagnostics (the 同步與診斷 window only; 附錄 A §9)
---------------------------------------------------------------------------

function Supply.diagText()
    local parts = {}
    local exp, enabled = {}, {}
    for _, r in ipairs(Rules.list) do
        if r.usable then
            local list = r.state == "enabled" and enabled or exp
            list[#list + 1] = r.title .. " v" .. r.rulesVersion
        end
    end
    parts[#parts + 1] = string.format("規則庫 v%d｜已驗證：%s｜實驗：%s", Rules.LIBRARY_VERSION,
        #enabled > 0 and table.concat(enabled, "、") or "無", #exp > 0 and table.concat(exp, "、") or "無")
    parts[#parts + 1] = "自動集料：" .. (Supply.autoOn() and "開" or "關") .. "｜手動刊登：" .. (Supply.manualOn() and "開" or "關")
    local function yn(v) if v == nil then return "未讀" end return v and "成功" or "失敗" end
    parts[#parts + 1] = string.format("任務讀取 %s｜背包讀取 %s｜最後掃描 %s｜缺口 %d 種、可能多 %d 種",
        yn(last.questOK), yn(last.bagOK), last.scanAt and ns.localTime(last.scanAt) or "尚未", last.missing or 0, last.surplus or 0)
    local c = Supply.snapshotCounts()
    parts[#parts + 1] = string.format("收到的快照：有效 %d、過期 %d、規則版本不同 %d｜拒收的資料 %d 則",
        c.valid, c.expired, c.unsupported, stats.rejected)
    parts[#parts + 1] = string.format("這次登入：掃描 %d、標記待掃 %d、戰鬥中略過 %d、更新快照 %d、確認 %d、重送 %d",
        stats.scans, stats.dirty, stats.combatSkips, stats.published, stats.confirmed, stats.resent)
    if ns.SupplyListings then parts[#parts + 1] = ns.SupplyListings.diagText() end
    for _, p in ipairs(Rules.problems or {}) do parts[#parts + 1] = p end
    if #stats.errors > 0 then parts[#parts + 1] = "最近的狀況：" .. table.concat(stats.errors, "；") end
    return table.concat(parts, "｜")
end

function Supply.resetSession()
    for k in pairs(stats) do if type(stats[k]) == "number" then stats[k] = 0 end end
    stats.errors = {}
    last.scanAt, last.questOK, last.bagOK, last.missing, last.surplus, last.snaps = nil, nil, nil, 0, 0, {}
    timerOn, firstAt, lastAt = false, nil, nil
    Supply.started, Supply.dirty = false, false
    snapCache = {}
end
