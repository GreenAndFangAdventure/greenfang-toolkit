-- SupplyRadar (GF-014, GF-009-09; spec v2.0 §7.3): the 綠皮調貨所 notices.
--
-- 1. New matches (module "supply"): someone published a supply for what I
--    lack, or a need for what I may have extra. Read from Supply.view (what
--    the page shows); one notice per item and direction, merged by Notify.
--    The person who needs an item hears about it only after the holder
--    published a supply (an automatic surplus of a checked rule, or a manual
--    供應 listing); the radar below never tells anyone.
-- 2. The local radar (module "radar"): this character's bags against the
--    guild needs already received and still valid (Supply.entries: others'
--    缺件 / 徵求). Bound, locked, not tradeable and unknown items do not count.
--    A hit is a notice for this player only (查看需求 / 忽略 / 刊登). Nothing is
--    sent: no record, no whisper, no listing is made by itself; 刊登 only
--    opens the form with the item filled in, the player sends it.
--
-- Work: bag events (BAG_UPDATE_DELAYED) and record changes only set a flag;
-- the check runs SupplyRadar.DEBOUNCE seconds after the last one (at most
-- MAX_WAIT after the first), never in combat (a flag, then after combat).
-- Uses only the read functions of Supply.lua / SupplyListings.lua /
-- SupplyUI.lua.

local _, ns = ...

local R = {}
ns.SupplyRadar = R
local N = ns.Notify
local Supply, L = ns.Supply, ns.SupplyListings

R.DEBOUNCE = 3
R.MAX_WAIT = 10
R.START_DELAY = 30          -- after login (after the share login and the supply start)
R.SEEN_TTL = 3 * 86400      -- a match already announced is not announced again for this long
R.IGNORE_TTL = 7 * 86400    -- 忽略 on a radar hit
R.PER_RUN = 5               -- notices of one kind in one check; the rest in one summary
R.MAX_SEEN = 2000

local stats = { checks = 0, combatSkips = 0, matches = 0, hits = 0, bagReads = 0, skippedBound = 0,
    skippedUnknown = 0, ignored = 0, ms = 0 }
R.stats = stats

R.ACTIONS = {
    { key = "view", text = "查看需求" },
    { key = "ignore", text = "忽略" },
    { key = "post", text = "刊登" },
}

local function now() return ns.now() end
local function itemText(id)
    local name = Supply.itemName and Supply.itemName(id)
    if type(name) ~= "string" or name == "" then name = "物品 " .. tostring(id) end
    return name
end

---------------------------------------------------------------------------
-- 1. New matches
---------------------------------------------------------------------------

local function forget(map, ttl, cap)
    local t, n = now(), 0
    for k, at in pairs(map) do
        if type(at) ~= "number" or t - at > ttl then map[k] = nil else n = n + 1 end
    end
    if n > cap then
        local keys = {}
        for k, at in pairs(map) do keys[#keys + 1] = { k = k, at = at } end
        table.sort(keys, function(x, y) return x.at < y.at end)
        for i = 1, n - cap do map[keys[i].k] = nil end
    end
end

R.MATCH_TEXT = {
    need = function(name, total, new) return string.format("「%s」：%d 位職工可能有（新增 %d 位）", name, total, new) end,
    offer = function(name, total, new) return string.format("「%s」：%d 位職工正在徵求，你可能有多（新增 %d 位）", name, total, new) end,
}
-- GF-UI-N: the other texts in one place, so the dev preview shows the same words.
function R.moreText(kind, extra)
    return string.format(kind == "need" and "另有 %d 項你缺的物品有新配對" or "另有 %d 項你可能有多的物品有人徵求", extra)
end
function R.radarText(name, have, wanted) return string.format("背包有「%s」x%d，%d 位職工正在徵求", name, have, wanted) end

-- GF-FIX-F (review 低-22): one check reads Supply.entries() once and gives
-- it to both parts (all = that list; nil reads it here).
function R.checkMatches(all)
    if not N.enabled("supply") then return 0 end
    all = all or Supply.entries()
    local mem = N.memory("supply")
    if type(mem.seen) ~= "table" then mem.seen = {} end
    local seen, t, pushed = mem.seen, now(), 0
    for _, kind in ipairs({ "need", "offer" }) do
        local extra = 0
        for _, it in ipairs(Supply.view(kind, all)) do
            if it.mine and #it.others > 0 then
                local new = 0
                for _, e in ipairs(it.others) do
                    local k = kind .. "|" .. it.itemID .. "|" .. tostring(e.a)
                    if not seen[k] then new = new + 1 end
                    seen[k] = t
                end
                if new > 0 then
                    stats.matches = stats.matches + 1
                    if pushed < R.PER_RUN then
                        pushed = pushed + 1
                        N.push({ module = "supply", key = kind .. ":" .. it.itemID,
                            text = R.MATCH_TEXT[kind](itemText(it.itemID), #it.others, new),
                            target = { page = "supply", tab = kind, id = it.itemID } })
                    else
                        extra = extra + 1
                    end
                end
            end
        end
        if extra > 0 then
            N.push({ module = "supply", key = kind .. ":more",
                text = R.moreText(kind, extra),
                target = { page = "supply", tab = kind } })
        end
    end
    forget(seen, R.SEEN_TTL, R.MAX_SEEN)
    return pushed
end

---------------------------------------------------------------------------
-- 2. The local radar
---------------------------------------------------------------------------

-- Guild needs received and valid: { [itemID] = { [author] = true } }, without
-- the items I already offer myself (the supply is published already).
function R.wanted(all)
    local want, mineOffer = {}, {}
    all = all or Supply.entries()
    for _, e in ipairs(all) do
        if e.own and e.direction == "offer" then mineOffer[e.itemID] = true end
    end
    for _, e in ipairs(all) do
        if not e.own and e.direction == "need" and type(e.itemID) == "number" and e.itemID > 0 and not mineOffer[e.itemID] then
            local w = want[e.itemID]
            if not w then w = {}; want[e.itemID] = w end
            w[e.a] = true
        end
    end
    return want
end

-- May this item change hands? false for bind on pickup / quest items, nil
-- when the client does not know yet (not counted either).
function R.tradeable(itemID)
    local info = L.itemInfo(itemID)
    if not info then return nil end
    if info.bindType == 1 or info.bindType == 4 then return false end
    return true
end

-- One check: returns the hits { [itemID] = { have, wanted } } (also for tests).
function R.checkBags(all)
    local mem = N.memory("radar")
    if type(mem.hit) ~= "table" then mem.hit = {} end
    if type(mem.ignored) ~= "table" then mem.ignored = {} end
    forget(mem.ignored, R.IGNORE_TTL, 500)
    local hits = {}
    if not N.enabled("radar") then
        mem.hit = {}
        return hits
    end
    local want = R.wanted(all)
    if next(want) then
        local bags = Supply.readBags(want)
        stats.bagReads = stats.bagReads + 1
        for id, c in pairs(bags or {}) do
            if c.eligible > 0 then
                local tr = R.tradeable(id)
                if tr == nil then
                    stats.skippedUnknown = stats.skippedUnknown + 1
                elseif tr == false then
                    stats.skippedBound = stats.skippedBound + 1
                elseif mem.ignored[id] then
                    stats.ignored = stats.ignored + 1
                else
                    local n = 0
                    for _ in pairs(want[id]) do n = n + 1 end
                    hits[id] = { have = c.eligible, wanted = n }
                end
            elseif c.count > 0 then
                stats.skippedBound = stats.skippedBound + 1
            end
        end
    end
    local pushed = 0
    for id, h in pairs(hits) do
        local sig = h.have .. "/" .. h.wanted
        if mem.hit[id] ~= sig then
            mem.hit[id] = sig
            stats.hits = stats.hits + 1
            if pushed < R.PER_RUN then
                pushed = pushed + 1
                N.push({ module = "radar", key = id,
                    text = R.radarText(itemText(id), h.have, h.wanted),
                    target = { page = "supply", tab = "guild", id = id }, actions = R.ACTIONS })
            end
        end
    end
    -- Gone from the bag, or nobody needs it any more: the notice goes too.
    for id in pairs(mem.hit) do
        if not hits[id] then mem.hit[id] = nil end
    end
    N.clear("radar", function(key) return not hits[tonumber(key)] end)
    return hits
end

---------------------------------------------------------------------------
-- The check (debounced; never in combat)
---------------------------------------------------------------------------

local timerOn, firstAt, lastAt = false, nil, nil

function R.checkNow()
    if ns.inCombat() then R.dirty = true; stats.combatSkips = stats.combatSkips + 1; return false end
    R.dirty = false
    stats.checks = stats.checks + 1
    local t0 = os and os.clock and os.clock() or 0
    local okE, all = pcall(Supply.entries)
    if not okE then all = nil end
    local okM, errM = pcall(R.checkMatches, all)
    local okB, errB = pcall(R.checkBags, all)
    stats.ms = math.floor(((os and os.clock and os.clock() or 0) - t0) * 1000 + 0.5)
    if not okM and Supply.note then Supply.note("雷達配對：" .. tostring(errM)) end
    if not okB and Supply.note then Supply.note("雷達背包：" .. tostring(errB)) end
    return true
end

local function fire()
    timerOn = false
    if ns.inCombat() then R.dirty = true; stats.combatSkips = stats.combatSkips + 1; return end
    local t = ns.now()
    if lastAt and t - lastAt < R.DEBOUNCE and firstAt and t - firstAt < R.MAX_WAIT then
        timerOn = true
        ns.after(R.DEBOUNCE - (t - lastAt), fire)
        return
    end
    firstAt, lastAt = nil, nil
    R.checkNow()
end

function R.markDirty()
    R.dirty = true
    if not R.started or ns.inCombat() then return end
    local t = ns.now()
    lastAt = t
    if timerOn then return end
    firstAt = t
    timerOn = true
    ns.after(R.DEBOUNCE, fire)
end

function R.start()
    if R.started then return end
    R.started = true
    R.markDirty()
end

function R.resetSession()
    for k in pairs(stats) do stats[k] = 0 end
    timerOn, firstAt, lastAt = false, nil, nil
    R.started, R.dirty = false, false
end

function R.diagText()
    return string.format("需求雷達：檢查 %d 次（上次 %d ms）、配對 %d、背包命中 %d、綁定或不可交易 %d、未知 %d、已忽略 %d、戰鬥中延後 %d",
        stats.checks, stats.ms, stats.matches, stats.hits, stats.skippedBound, stats.skippedUnknown, stats.ignored, stats.combatSkips)
end

local events = CreateFrame("Frame")
R.EVENTS = { "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }
for _, e in ipairs(R.EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not R.started then ns.after(R.START_DELAY + (ns.Share.LOGIN_DELAY or 20), R.start) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.after(0, function() if R.dirty then R.markDirty() end end)
    else
        R.markDirty()
    end
end)
-- Others' records (needs, supplies, listings) changed.
ns.Share.onUpdate(function() R.markDirty() end)

---------------------------------------------------------------------------
-- Going to the item (the page's public functions; ui work may give the page
-- a focus() of its own, which then wins) and the buttons
---------------------------------------------------------------------------

function R.focusSupply(id, target)
    local UI = ns.SupplyUI
    if not UI then return false end
    local tab = target and target.tab or "guild"
    UI.setTab(tab)
    if id == nil then return false end
    for i, d in ipairs(UI.listFor(tab)) do
        if d.itemID == id then
            UI.scroll(-(i - 1))
            UI.select(i)
            return true
        end
    end
    return false
end
N.setFocus("supply", R.focusSupply)

-- 刊登: the form, 供應, the item filled in; nothing is sent until the player saves.
function R.post(itemID)
    local UI = ns.SupplyUI
    if not (UI and ns.Framework.get("supply")) then return false end
    ns.Framework.open("supply")
    if not UI.openForm(nil) then return false end
    local f = UI.form()
    for _, b in ipairs(f and f.dirs and f.dirs.buttons or {}) do
        if b.key == "offer" then
            local click = b.GetScript and b:GetScript("OnClick")
            if click then click(b) end
        end
    end
    if UI.setFormItem then UI.setFormItem(itemID, { isBound = false }) end
    return true
end

N.register("radar", {
    onAction = function(e, key)
        local id = tonumber(e.key)
        if key == "ignore" and id then
            local mem = N.memory("radar")
            if type(mem.ignored) ~= "table" then mem.ignored = {} end
            mem.ignored[id] = now()
            if type(mem.hit) == "table" then mem.hit[id] = nil end
            return "ignored"
        elseif key == "post" and id then
            return R.post(id) and "post" or "none"
        end
        return nil
    end,
})
