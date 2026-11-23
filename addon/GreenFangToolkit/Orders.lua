-- Orders (GF-006-B, spec docs/spec/GF-006_crafting-orders_v1.0.md §4–§6):
-- crafting services, orders, closing and reminders. Synced on the GFTKO
-- ledger (Ledger.lua); every member who has the toolkit sees and relays all
-- orders (R-5.5).
--
-- Records (R-5.6): each side writes only its own half.
--   O  (author = crafter)  services: active professions (R-4.2) and fees (R-4.3)
--   W  (author = customer) the customer's open orders and the customer's actions
--   J  (author = crafter)  the crafter's actions on orders
--   M  (author = customer) reserved for web orders (R-9.3, phase 1.5); read, never written here
-- What a row shows is Orders.view(): a pure merge of W (or M) and the J
-- halves (offline tests cover it).
--
-- Value format: entries "/"-separated, fields "k=v" ","-separated, values
-- escaped with Ledger.esc. Numbers base 36. Unknown keys are kept as is.

local _, ns = ...
local str = ns.str

local Orders = {}
ns.Orders = Orders

Orders.PREFIX = "GFTKO"
Orders.ORDER_VERSION = 1
Orders.DAY = 86400
Orders.KEEP_CLOSED = 7 * 86400        -- R-6.10: closed rows move to history after 7 days
Orders.CRAFTER_CLOSE = 14 * 86400     -- R-6.5
Orders.HISTORY_MAX = 100              -- R-6.10, per character
Orders.MAX_OPEN = 30                  -- open orders per customer (keeps W small)
Orders.UNDO = 5                       -- R-6.7
Orders.STALE_DAYS = { waiting = 2, making = 3, checking = 1 } -- R-6.9 (adjustable in 同步與診斷)
Orders.ENCHANTING = 333

local function S() return ns.Share end
local function b36(n) return S().b36(n) end
local function unb36(s) return S().unb36(s) end
local esc = function(v) return ns.Ledger.esc(v) end
local unesc = function(v) return ns.Ledger.unesc(v) end
-- spec §12 item 5: a test build moves the order clock forward with
-- /gftk orders shift <days> (local only; records keep the real time).
local function now()
    local shift = ns.db and type(ns.db.orders) == "table" and ns.num(ns.db.orders.debugShift) or 0
    return S().serverNow() + shift
end
Orders.now = now

---------------------------------------------------------------------------
-- Encoding (pure)
---------------------------------------------------------------------------

-- Numeric fields (base 36 on the wire); everything else is a string.
local NUM = { ver = true, cr = true, rc = true, it = true, q = true, fe = true, fq = true, qt = true,
    sk = true, sa = true, gt = true, gv = true, ac = true, dt = true, lt = true, rt = true }

function Orders.encodeEntry(e)
    local keys = {}
    for k in pairs(e) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = e[k]
        if v ~= nil and v ~= "" then
            if NUM[k] then
                if type(v) == "number" and v >= 0 then out[#out + 1] = k .. "=" .. b36(v) end
            else
                out[#out + 1] = k .. "=" .. esc(v)
            end
        end
    end
    return table.concat(out, ",")
end

function Orders.decodeEntry(s)
    local e = {}
    for field in str(s):gmatch("[^,]+") do
        local k, v = field:match("^(%w+)=(.*)$")
        if not k then return nil end
        if NUM[k] then
            local n = unb36(v)
            if not n then return nil end
            e[k] = n
        else
            e[k] = unesc(v)
        end
    end
    return e
end

function Orders.encodeList(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = Orders.encodeEntry(e) end
    return table.concat(out, "/")
end

function Orders.decodeList(s)
    local list = {}
    if str(s) == "" then return list end
    for part in str(s):gmatch("[^/]+") do
        local e = Orders.decodeEntry(part)
        if not e or not e.id then return nil end
        list[#list + 1] = e
    end
    return list
end

-- Materials the customer gives: "itemID*count+itemID*count" <-> { [itemID] = count }.
function Orders.encodeMats(m)
    local ids = {}
    for id in pairs(m or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        if m[id] and m[id] > 0 then out[#out + 1] = tostring(id) .. "*" .. tostring(m[id]) end
    end
    return table.concat(out, "+")
end
function Orders.decodeMats(s)
    local m = {}
    for id, n in str(s):gmatch("(%d+)%*(%d+)") do m[tonumber(id)] = tonumber(n) end
    return m
end

-- Services (O): "a=164.171,f164=<fee>,r2660=<fee>" (fees base 36; 0 = free).
function Orders.encodeServices(sv)
    local active = {}
    for skill, on in pairs(sv.active or {}) do if on then active[#active + 1] = skill end end
    table.sort(active)
    local out = {}
    if #active > 0 then
        local a = {}
        for i, s in ipairs(active) do a[i] = tostring(s) end
        out[#out + 1] = "a=" .. table.concat(a, ".")
    end
    local fk = {}
    for skill in pairs(sv.fees or {}) do fk[#fk + 1] = skill end
    table.sort(fk)
    for _, skill in ipairs(fk) do out[#out + 1] = "f" .. skill .. "=" .. b36(sv.fees[skill]) end
    local rk = {}
    for id in pairs(sv.recipeFees or {}) do rk[#rk + 1] = id end
    table.sort(rk)
    -- "r<recipe>s<skill>": the upload nests recipe fees under their profession.
    for _, id in ipairs(rk) do
        local skill = sv.recipeSkill and sv.recipeSkill[id]
        out[#out + 1] = "r" .. id .. (skill and ("s" .. skill) or "") .. "=" .. b36(sv.recipeFees[id])
    end
    return table.concat(out, ",")
end
function Orders.decodeServices(s)
    local sv = { active = {}, fees = {}, recipeFees = {}, recipeSkill = {} }
    for field in str(s):gmatch("[^,]+") do
        local k, v = field:match("^(%w+)=(.*)$")
        if k == "a" then
            for id in v:gmatch("%d+") do sv.active[tonumber(id)] = true end
        elseif k and k:match("^f%d+$") and unb36(v) then
            sv.fees[tonumber(k:sub(2))] = unb36(v)
        elseif k and k:match("^r%d+$") and unb36(v) then
            sv.recipeFees[tonumber(k:sub(2))] = unb36(v)
        elseif k and k:match("^r%d+s%d+$") and unb36(v) then
            local id, skill = k:match("^r(%d+)s(%d+)$")
            sv.recipeFees[tonumber(id)] = unb36(v)
            sv.recipeSkill[tonumber(id)] = tonumber(skill)
        end
    end
    return sv
end

---------------------------------------------------------------------------
-- Ledger
---------------------------------------------------------------------------

local function validGroup(g) return g == "O" or g == "W" or g == "J" or g == "M" end
local function validAuthor(a)
    return type(a) == "string" and a ~= "" and not a:find("[~%.]") and S().memberFor(a) ~= nil
end
local function validValue(_, g, v)
    if #v > 12000 then return false end -- 64 parts of a B/D value
    if g == "O" then return true end
    local list = Orders.decodeList(v)
    if not list then return false end
    -- GF-006-C: M holds web orders only ("w" ids, src w); a game order can never be replaced by one.
    if g == "M" then
        for _, e in ipairs(list) do
            if not str(e.id):match("^w[0-9a-z.]+$") or e.src ~= "w" then return false end
        end
    end
    return true
end

local cache = { version = -1 }
Orders.ledger = ns.Ledger.new({
    id = "orders", prefix = Orders.PREFIX, burst = 6, refill = 0.5, loginDelay = 25,
    validAuthor = validAuthor, validGroup = validGroup, validValue = validValue,
    selfAuthor = function() return S().selfAuthor() end,
    changeDelay = 2,
    onChange = function() cache.version = -1; if Orders.onChanged then Orders.onChanged() end end,
    onCustom = function(...) return Orders.onCustom(...) end,
    mergeSelf = function(g, v) return Orders.mergeSelf(g, v) end,
})
local led = Orders.ledger

local svCache = {}
-- Decoded services of author a (cached by the record's hash). Callers that
-- change the result must copy it first (setActive/setFee do).
function Orders.services(a)
    local rec = a and led:get(a, "O")
    if not rec then return { active = {}, fees = {}, recipeFees = {}, recipeSkill = {} } end
    local c = svCache[a]
    if c and c.h == rec.h then return c.sv end
    local sv = Orders.decodeServices(rec.v)
    svCache[a] = { h = rec.h, sv = sv }
    return sv
end

local function listOf(a, g)
    local rec = a and led:get(a, g)
    return rec and Orders.decodeList(rec.v) or {}
end
Orders.listOf = listOf

-- Review 3-3: another computer of mine wrote an older copy (by time) of my
-- W or J that we did not have. Merge it: every id from both, the entry with
-- the later state time (sa) wins; then write it as ours again.
function Orders.mergeSelf(g, v)
    if g ~= "W" and g ~= "J" then return false end
    local incoming = Orders.decodeList(v)
    if not incoming then return false end
    local me = S().selfAuthor()
    local mine = listOf(me, g)
    local byId = {}
    for _, e in ipairs(mine) do byId[e.id] = e end
    local changed = false
    for _, e in ipairs(incoming) do
        local m = byId[e.id]
        if not m or (e.sa or 0) > (m.sa or 0) then
            if m then for i, x in ipairs(mine) do if x.id == e.id then mine[i] = e end end
            else mine[#mine + 1] = e end
            byId[e.id] = e
            changed = true
        end
    end
    if changed then led:put(g, Orders.encodeList(mine)) end
    return changed
end

---------------------------------------------------------------------------
-- Services and fees (R-4.2 – R-4.5)
---------------------------------------------------------------------------

-- { [skill] = { [guid] = true } } of every crafter taking orders, rebuilt when
-- the ledger changes (the recipe page asks for every crafter of every row).
local activeCache = { version = -1 }
function Orders.activeSets()
    if activeCache.version == led.version then return activeCache.sets end
    local sets = {}
    for _, a in ipairs(led:authors()) do
        if led:get(a, "O") then
            for skill in pairs(Orders.services(a).active) do
                sets[skill] = sets[skill] or {}
                sets[skill][S().guidOf(a)] = true
            end
        end
    end
    activeCache = { version = led.version, sets = sets }
    return sets
end

function Orders.isActive(guid, skill)
    if not guid then return false end
    local set = Orders.activeSets()[tonumber(skill) or -1]
    return set ~= nil and set[guid] == true
end

function Orders.isActiveAny(guid)
    if not guid then return false end
    for _, set in pairs(Orders.activeSets()) do if set[guid] then return true end end
    return false
end

-- R-4.3/R-4.4: recipe fee, else profession fee, else nil (not filled in).
-- 0 is free and is final (no fallback).
function Orders.feeOf(sv, skill, recipe)
    if recipe and sv.recipeFees[recipe] ~= nil then return sv.recipeFees[recipe] end
    if skill and sv.fees[skill] ~= nil then return sv.fees[skill] end
    return nil
end
function Orders.feeFor(guid, skill, recipe)
    local a = guid and S().authorOf(guid)
    if not a then return nil end
    return Orders.feeOf(Orders.services(a), skill, recipe)
end

-- Guild order (R-4.3): the lowest filled-in fee among the crafters; nil when nobody filled one in.
function Orders.lowestFee(crafters, skill, recipe)
    local best
    for _, m in ipairs(crafters or {}) do
        local f = Orders.feeFor(m.guid, skill, recipe)
        if f ~= nil and (best == nil or f < best) then best = f end
    end
    return best
end

local function myServices() return ns.copy(Orders.services(S().selfAuthor())) end

function Orders.setActive(skill, on)
    local sv = myServices()
    sv.active[skill] = on and true or nil
    return led:put("O", Orders.encodeServices(sv))
end

-- fee nil = not filled in (the key is removed), 0 = free.
function Orders.setFee(skill, fee)
    local sv = myServices()
    sv.fees[skill] = fee
    return led:put("O", Orders.encodeServices(sv))
end
function Orders.setRecipeFee(recipe, fee, skill)
    local sv = myServices()
    sv.recipeFees[recipe] = fee
    sv.recipeSkill = sv.recipeSkill or {}
    sv.recipeSkill[recipe] = fee ~= nil and (skill or sv.recipeSkill[recipe]) or nil
    return led:put("O", Orders.encodeServices(sv))
end

-- R-4.2 sort for a list of crafters: active and online, active, online, others.
function Orders.sortCrafters(list, skill)
    local set = Orders.activeSets()[tonumber(skill) or -1]
    if not set then return list end -- nobody active: the list keeps its order (online first)
    local function rank(m)
        local active = m.guid ~= nil and set[m.guid] == true
        if active and m.online then return 0 end
        if active then return 1 end
        if m.online then return 2 end
        return 3
    end
    local ranked = {}
    for i, m in ipairs(list or {}) do ranked[i] = { m = m, r = rank(m), i = i } end
    table.sort(ranked, function(x, y)
        if x.r ~= y.r then return x.r < y.r end
        return x.i < y.i
    end)
    for i, x in ipairs(ranked) do list[i] = x.m end
    return list
end

---------------------------------------------------------------------------
-- Merge (pure, R-5.6): one order's state from its halves
---------------------------------------------------------------------------

-- w: the customer's entry (from W, or from M for a web order without a W
-- entry yet); jobs: { [crafter author] = J entry for this order }; cust: the
-- customer's author. Returns the view (see the fields below).
-- v1.4a tie rule: GUID strings compared byte by byte (never locale order).
function Orders.guidLess(x, y)
    local n = math.min(#x, #y)
    for i = 1, n do
        local a, b = x:byte(i), y:byte(i)
        if a ~= b then return a < b end
    end
    return #x < #y
end
local function authorLess(x, y) return Orders.guidLess(S().guidOf(x), S().guidOf(y)) end

function Orders.view(w, jobs, cust, web)
    local v = {
        id = w.id, customer = cust, src = w.src or "g", created = w.cr or 0, recipe = w.rc, item = w.it,
        skill = w.sk, qty = math.max(1, w.q or 1), mats = Orders.decodeMats(w.m), fee = w.fe or 0,
        feeQuoted = w.fq, quote = w.qt, guild = w.cf == "*" or w.cf == nil, ext = w.ex,
        got = w.gt or 0, gave = 0, state = "waiting", since = w.cr or 0,
    }
    jobs = jobs or {}
    -- Who has it?
    local crafter, job
    if not v.guild then
        crafter = w.cf
        job = jobs[crafter]
    else
        -- v1.4a: the lock wins; the locked crafter dropping it (statusAt >= lockedAt)
        -- puts it back to 等接單. Only crafters who accept after that drop can
        -- take it (review 3-1: it is never handed to someone who was too late).
        local lockedJob = w.lk and jobs[w.lk]
        local dropped = lockedJob and lockedJob.st == "b" and (lockedJob.sa or 0) >= (w.lt or 0)
        if w.lk and lockedJob and not dropped then
            crafter, job = w.lk, lockedJob
        else
            local after = dropped and (lockedJob.sa or 0) or nil
            local best
            for a, j in pairs(jobs) do
                if (j.st == "a" or j.st == "d" or j.st == "m" or j.st == "c") and j.ac and (not after or j.ac > after) then
                    if not best or j.ac < best.ac or (j.ac == best.ac and authorLess(a, best.a)) then best = { a = a, ac = j.ac } end
                end
            end
            if best then crafter, job = best.a, jobs[best.a] end
        end
    end
    v.crafter = crafter
    v.declined = {}
    for a, j in pairs(jobs) do
        if j.st == "n" or j.st == "b" then v.declined[a] = true end
        if j.st == "b" and (j.sa or 0) > (v.droppedAt or 0) then v.droppedAt = j.sa end
    end
    if job then v.gave = job.gv or 0 end
    v.progress = math.max(v.got, v.gave)
    v.paid = (w.pd == "1") or (job and job.pd == "1") or false

    -- returnedAt (rt); 0.11.0 wrote only st = "r" with its time in sa.
    local returnedAt = w.rt or (w.st == "r" and w.sa) or 0
    -- Closes: the earliest one wins (R-6.6).
    local closes = {}
    if w.st == "x" then closes[#closes + 1] = { close = "cancel", by = "customer", how = "manual", at = w.sa or 0 } end
    if w.st == "d" then closes[#closes + 1] = { close = "deal", by = "customer", how = w.ch or "manual", at = w.sa or 0 } end
    -- GF-006-C: cancelled on the website (the M copy of a web order).
    if web and web.st == "x" then closes[#closes + 1] = { close = "cancel", by = "web", how = "manual", at = web.sa or 0 } end
    if job and not v.guild and (job.st == "n" or job.st == "b") then
        closes[#closes + 1] = { close = "cancel", by = "crafter", how = "manual", at = job.sa or 0 }
    end
    -- v1.4a: valid only when closedAt - deliveredAt >= 14 days and the last
    -- return (returnedAt) is not after the delivery.
    if job and job.st == "c" and job.dt and (job.sa or 0) - job.dt >= Orders.CRAFTER_CLOSE
        and not (returnedAt > job.dt) then
        closes[#closes + 1] = { close = "deal", by = "crafter", how = "timeout", at = job.sa or 0 }
    end
    if #closes > 0 then
        -- v1.4a: the earliest closedAt; the same second -> the customer's.
        local rank = { customer = 0, web = 1, crafter = 2 }
        table.sort(closes, function(x, y)
            if x.at ~= y.at then return x.at < y.at end
            return rank[x.by] < rank[y.by]
        end)
        local c = closes[1]
        v.state = c.close
        v.close, v.closedBy, v.closeHow, v.closedAt = c.close, c.by, c.how, c.at
        v.since = c.at
        return v
    end
    if not crafter or not job then
        v.state, v.since = "waiting", w.cr or 0
        if w.st == "p" then v.uncertain = true end
        return v
    end
    local delivered = (job.st == "d" or job.st == "m" or job.st == "c") and job.dt
    if delivered and not (returnedAt > job.dt) then
        v.state, v.since = "checking", job.dt
        v.deliveredHow = job.st == "m" and "mail" or (job.ch or "manual")
    elseif w.st == "p" then
        v.state, v.since, v.uncertain = "checking", w.sa or 0, true
    elseif returnedAt > 0 and (w.st == "r" or returnedAt > (job.dt or 0)) then
        v.state, v.since, v.returned = "making", returnedAt, true
    else
        v.state, v.since = "making", job.ac or job.sa or 0
    end
    return v
end

-- Every order known: { [id] = view }. Cached until the ledger changes.
function Orders.all()
    if cache.version == led.version and cache.views then return cache.views end
    local jobsBy = {}
    for _, a in ipairs(led:authors()) do
        for _, j in ipairs(listOf(a, "J")) do
            jobsBy[j.id] = jobsBy[j.id] or {}
            jobsBy[j.id][a] = j
        end
    end
    local views = {}
    for _, a in ipairs(led:authors()) do
        -- GF-006-C: M = the website's copy of a web order. The customer's own
        -- W entry (once they pressed a button on it) carries their actions;
        -- a cancel on the website still closes it (earliest close wins).
        local web = {}
        for _, m in ipairs(listOf(a, "M")) do web[m.id] = m end
        local seen = {}
        for _, w in ipairs(listOf(a, "W")) do
            seen[w.id] = true
            views[w.id] = Orders.view(w, jobsBy[w.id], a, web[w.id])
        end
        for id, m in pairs(web) do
            if not seen[id] then
                local base = ns.copy(m)
                if base.st == "x" then base.st, base.sa = "o", base.cr end
                views[id] = Orders.view(base, jobsBy[id], a, m)
            end
        end
    end
    cache.version, cache.views = led.version, views
    return views
end

function Orders.get(id) return Orders.all()[id] end

-- Open orders between me and author other (both directions), oldest first.
function Orders.between(me, other)
    local list = {}
    for _, v in pairs(Orders.all()) do
        if v.state ~= "deal" and v.state ~= "cancel" then
            if (v.customer == me and v.crafter == other) or (v.customer == other and v.crafter == me) then
                list[#list + 1] = v
            end
        end
    end
    table.sort(list, function(x, y)
        if x.created ~= y.created then return x.created < y.created end
        return x.id < y.id
    end)
    return list
end

---------------------------------------------------------------------------
-- Writing my half
---------------------------------------------------------------------------

local function myList(g)
    local list = listOf(S().selfAuthor(), g)
    return list
end

-- Review 1-2: a write can fail (12,000 bytes). Make room by moving the
-- oldest closed rows to history first; if it still does not fit, report it.
Orders.MAX_VALUE = 12000
local function isClosedEntry(g, e, views)
    if g == "W" then return e.st == "x" or e.st == "d" end
    local v = views[e.id]
    return v ~= nil and (v.state == "deal" or v.state == "cancel")
end
local function saveList(g, list)
    local v = Orders.encodeList(list)
    if #v > Orders.MAX_VALUE then
        local views = Orders.all()
        local closed = {}
        for i, e in ipairs(list) do if isClosedEntry(g, e, views) then closed[#closed + 1] = { i = i, at = e.sa or 0 } end end
        table.sort(closed, function(x, y) if x.at ~= y.at then return x.at < y.at end return x.i < y.i end)
        local drop = {}
        local k = 0
        while #v > Orders.MAX_VALUE and k < #closed do
            k = k + 1
            drop[closed[k].i] = true
            local kept = {}
            for i, e in ipairs(list) do if not drop[i] then kept[#kept + 1] = e end end
            v = Orders.encodeList(kept)
        end
        if #v > Orders.MAX_VALUE then return "full" end
        for i in pairs(drop) do
            local view = views[list[i].id]
            if view then Orders.toHistory(view) end
        end
    end
    local r = led:put(g, v)
    if r == "stored" or r == "same" then return r end
    return r
end
local function saved(r) return r == "stored" or r == "same" end

local function findIn(list, id)
    for i, e in ipairs(list) do if e.id == id then return e, i end end
    return nil
end

local seq = 0
-- Contract (savedvariables §crafting): only [0-9a-z.], at most 64 characters.
-- The customer's part is a hash of their author id; time + sequence make it unique.
function Orders.newId()
    -- GF-006-B2: the sequence no longer wraps at 36 (two orders in the same
    -- second could get the same id); an id already in my W is never reused.
    local mine = {}
    for _, e in ipairs(listOf(S().selfAuthor(), "W")) do mine[e.id] = true end
    local id
    repeat
        seq = seq + 1
        id = "g" .. S().hash(S().selfAuthor()) .. "." .. b36(S().serverNow()) .. b36(seq)
    until not mine[id]
    return id
end

-- R-5.2: o = { recipe, item, skill, qty, crafter (author or "*"), mats = { [itemID] = n },
-- fee (copper), feeQuoted (nil/0/n), quote }. Returns the id or nil, reason.
function Orders.place(o)
    local me = S().selfAuthor()
    if not me then return nil, "no-author" end
    local list = myList("W")
    -- Review 7-6: declined or dropped orders are not "open".
    local open = 0
    local views = Orders.all()
    for _, e in ipairs(list) do
        local v = views[e.id]
        if e.st ~= "x" and e.st ~= "d" and not (v and (v.state == "deal" or v.state == "cancel")) then open = open + 1 end
    end
    if open >= Orders.MAX_OPEN then return nil, "too-many" end
    if not o.recipe then return nil, "no-recipe" end
    local t = now()
    local e = {
        id = Orders.newId(), src = "g", ver = Orders.ORDER_VERSION, cr = t, rc = o.recipe, it = o.item,
        sk = o.skill, q = math.max(1, math.floor(o.qty or 1)), cf = o.crafter or "*",
        m = Orders.encodeMats(o.mats), fe = math.max(0, math.floor(o.fee or 0)), fq = o.feeQuoted,
        qt = o.quote, st = "o", sa = t,
    }
    list[#list + 1] = e
    local r = saveList("W", list)
    if not saved(r) then return nil, r == "full" and "full" or r end
    return e.id
end

-- Customer actions: "cancel" (x), "deal" (d, how), "return" (r), "unsure" (p),
-- "got" (n more received), "paid", "lock" (crafter).
function Orders.customer(id, action, arg)
    local list = myList("W")
    local e = findIn(list, id)
    if not e then
        -- GF-006-C: my web order (M) gets its W entry when I first act on it.
        local m = findIn(listOf(S().selfAuthor(), "M"), id)
        if not m or m.st == "x" then return false, "unknown" end
        e = ns.copy(m)
        list[#list + 1] = e
    end
    if e.st == "x" or e.st == "d" then return false, "closed" end
    local t = now()
    if action == "cancel" then e.st, e.sa = "x", t
    elseif action == "deal" then e.st, e.sa, e.ch = "d", t, arg or "manual"
    elseif action == "return" then e.st, e.sa, e.rt = "r", t, t
    elseif action == "unsure" then e.st, e.sa = "p", t
    elseif action == "got" then e.gt = (e.gt or 0) + (arg or 0)
    elseif action == "paid" then e.pd = "1"
    elseif action == "lock" then e.lk, e.lt = arg, t
    else return false, "action" end
    saveList("W", list)
    return true
end

-- Crafter actions on order v (a view): "accept", "decline", "release",
-- "delivered" (how), "mailed", "gave" (n), "close" (R-6.5), "paid".
function Orders.crafter(v, action, arg)
    -- Review 3-4 / R-6.6: nothing changes after the order closed.
    local current = Orders.get(v.id)
    if current and (current.state == "deal" or current.state == "cancel") then return false, "closed" end
    local list = myList("J")
    local e = findIn(list, v.id)
    local t = now()
    if action ~= "gave" and action ~= "paid" then Orders.local_().unsure[v.id] = nil end
    if not e then
        e = { id = v.id, cu = v.customer }
        list[#list + 1] = e
    end
    if action == "accept" then e.st, e.ac, e.sa = "a", t, t
    elseif action == "decline" then e.st, e.sa = "n", t
    elseif action == "release" then e.st, e.sa = "b", t
    elseif action == "delivered" then e.st, e.sa, e.dt, e.ch = "d", t, t, arg or "manual"
    elseif action == "mailed" then e.st, e.sa, e.dt, e.ch = "m", t, t, "mail"
    elseif action == "gave" then e.gv = math.max(0, (e.gv or 0) + (arg or 0)); if e.st == nil then e.st, e.ac, e.sa = "a", t, t end
    elseif action == "undeliver" then e.st, e.sa = "a", t; e.dt = nil
    elseif action == "close" then
        if not (e.dt and t - e.dt >= Orders.CRAFTER_CLOSE) then return false, "too-early" end
        e.st, e.sa = "c", t
    elseif action == "paid" then e.pd = "1"
    else return false, "action" end
    local r = saveList("J", list)
    if not saved(r) then return false, r == "full" and "full" or r end
    return true
end

-- What the viewer may press (R-6.2). me: my author.
function Orders.buttons(v, me)
    local out = {}
    local function add(b) out[#out + 1] = b end
    if v.state == "deal" or v.state == "cancel" then return out end
    local isCustomer, isCrafter = v.customer == me, v.crafter == me
    if v.state == "waiting" then
        if isCustomer then add("cancel")
        elseif not v.guild and isCrafter then add("accept"); add("decline")
        elseif v.guild and not (v.declined and v.declined[me]) then add("accept") end
    elseif v.state == "making" then
        if isCustomer then add("deal"); add("cancel") end
        if isCrafter then add("deliver"); add("release") end
    elseif v.state == "checking" then
        if isCustomer then add("deal"); add("return"); add("cancel") end
        if isCrafter then
            add("release")
            if v.deliveredHow and now() - (v.since or 0) >= Orders.CRAFTER_CLOSE then add("close") end
        end
    end
    return out
end

-- Press a button (from the orders page). Returns true on success.
function Orders.press(v, button)
    local me = S().selfAuthor()
    if button == "cancel" then return Orders.customer(v.id, "cancel")
    elseif button == "deal" then return Orders.customer(v.id, "deal", "manual")
    elseif button == "return" then return Orders.customer(v.id, "return")
    elseif button == "accept" then return Orders.crafter(v, "accept")
    elseif button == "decline" then return Orders.crafter(v, "decline")
    elseif button == "release" then return Orders.crafter(v, "release")
    elseif button == "deliver" then return Orders.crafter(v, "delivered", "manual")
    elseif button == "close" then return Orders.crafter(v, "close")
    end
    return false, me and "button" or "no-author"
end

---------------------------------------------------------------------------
-- Guild orders: lock the winner (R-5.3), prune closed rows (R-6.10)
---------------------------------------------------------------------------

function Orders.maintain()
    local me = S().selfAuthor()
    if not me then return end
    local t = now()
    local views = Orders.all()
    -- Customer: lock guild orders to the earliest crafter.
    local list = myList("W")
    local dirty = false
    local keep = {}
    for _, e in ipairs(list) do
        local v = views[e.id]
        if v and v.guild and v.crafter and e.lk ~= v.crafter and v.state ~= "waiting" then
            e.lk, e.lt = v.crafter, t
            dirty = true
        end
        if v and (v.state == "deal" or v.state == "cancel") and t - (v.closedAt or t) >= Orders.KEEP_CLOSED then
            Orders.toHistory(v)
            dirty = true
        else
            keep[#keep + 1] = e
        end
    end
    if dirty then saveList("W", keep) end
    -- Crafter: drop jobs of closed orders after 7 days, and of orders gone for 30 days.
    local jobs = myList("J")
    local kept, changedJ = {}, false
    for _, j in ipairs(jobs) do
        local v = views[j.id]
        local old = v and (v.state == "deal" or v.state == "cancel") and t - (v.closedAt or t) >= Orders.KEEP_CLOSED
        local gone = not v and t - (j.sa or t) >= 30 * Orders.DAY
        -- Review 7-6: a guild order someone else got is not my history.
        if old and v.crafter == me then Orders.toHistory(v) end
        if old or gone then changedJ = true else kept[#kept + 1] = j end
    end
    if changedJ then saveList("J", kept) end
    -- Review 1-7: forget reminders of orders that are gone; unsure marks after 10 minutes.
    local o = Orders.local_()
    views = Orders.all()
    for key in pairs(o.seen) do
        local id = key:match("^(.-)|")
        if not (id and views[id]) then o.seen[key] = nil end
    end
    for id, at in pairs(o.unsure) do
        if not views[id] or ns.now() - (at or 0) > 600 then o.unsure[id] = nil end
    end
    -- Review 1-8: records of members no longer on the roster (every client drops them alike).
    if ns.Roster.current() then
        for _, a in ipairs(led:authors()) do
            if not S().memberFor(a) then
                for _, g in ipairs({ "O", "W", "J", "M" }) do led:drop(a, g) end
            end
        end
    end
end

-- Local data: GreenFangToolkitDB.orders (history, seen, trades, unsure).
function Orders.local_()
    local db = ns.db
    if type(db.orders) ~= "table" then db.orders = {} end
    local o = db.orders
    for _, k in ipairs({ "history", "seen", "trades", "unsure", "reagents" }) do
        if type(o[k]) ~= "table" then o[k] = {} end
    end
    return o
end

function Orders.toHistory(v)
    local o = Orders.local_()
    local key = ns.Data.player().guid or "?"
    o.history[key] = o.history[key] or {}
    local h = o.history[key]
    for _, x in ipairs(h) do if x.id == v.id then return end end
    table.insert(h, 1, { id = v.id, recipe = v.recipe, item = v.item, skill = v.skill, qty = v.qty,
        customer = v.customer, crafter = v.crafter, close = v.close, closedBy = v.closedBy,
        closeHow = v.closeHow, closedAt = v.closedAt, fee = v.fee, mats = Orders.encodeMats(v.mats) })
    while #h > Orders.HISTORY_MAX do table.remove(h) end
end

---------------------------------------------------------------------------
-- Reminders (R-6.8, R-6.9)
---------------------------------------------------------------------------

-- /gftk orders days <waiting> <making> <checking> (R-6.9: adjustable).
function Orders.setStaleDays(a, b, c)
    local s = ns.settings()
    if type(s.modules) ~= "table" then s.modules = {} end
    if type(s.modules.orders) ~= "table" then s.modules.orders = {} end
    local function d(x) x = tonumber(x); return x and x >= 1 and x <= 30 and math.floor(x) or nil end
    if not (d(a) and d(b) and d(c)) then return false end
    s.modules.orders.stale = { waiting = d(a), making = d(b), checking = d(c) }
    return true
end

function Orders.staleDays()
    local s = ns.settings().modules
    local mine = type(s) == "table" and type(s.orders) == "table" and s.orders.stale or nil
    local out = {}
    for k, d in pairs(Orders.STALE_DAYS) do out[k] = (type(mine) == "table" and ns.num(mine[k])) or d end
    return out
end

-- Does the viewer know this recipe (guild orders they could take)?
function Orders.canMake(v, guid)
    if not (v.recipe and v.skill) then return false end
    local r = ns.Recipes and ns.Recipes.of(guid, v.skill)
    if not r then return false end
    for _, id in ipairs(r.ids) do if id == v.recipe then return true end end
    return false
end

-- Attention for one order: nil, or { key, decide = true/false, code }.
-- seen: { [key] = true } from Orders.local_().seen.
function Orders.attention(v, me, myGuid, t, days)
    days = days or Orders.staleDays()
    local isCustomer, isCrafter = v.customer == me, v.crafter == me
    local function stale(kind)
        local d = (days[kind] or 1) * Orders.DAY
        local age = t - (v.since or t)
        if age < d then return nil end
        return math.floor(age / d)
    end
    if v.state == "deal" or v.state == "cancel" then
        local other = (isCustomer and v.closedBy == "crafter") or (isCrafter and v.closedBy == "customer")
        if other then return { key = v.id .. "|closed", decide = false, code = v.state } end
        return nil
    end
    if v.state == "waiting" then
        if isCustomer then
            -- Review 7-6 / R-6.9: a crafter dropped my guild order (it is open again).
            if v.guild and v.droppedAt then
                return { key = v.id .. "|dropped|" .. v.droppedAt, decide = false, code = "dropped" }
            end
            local n = stale("waiting")
            if n then return { key = v.id .. "|stale|" .. n, decide = false, code = "stale", red = true } end
            return nil
        end
        if not v.guild and v.crafter == nil then return nil end
        if not v.guild and v.crafter == me then return { key = v.id .. "|new", decide = true, code = "new" } end
        if v.guild and not (v.declined and v.declined[me]) and Orders.canMake(v, myGuid) then
            return { key = v.id .. "|new", decide = false, code = "new" }
        end
        return nil
    end
    -- Review 7-4: a trade cut off after both accepted: the crafter decides too.
    if isCrafter and (v.state == "making" or v.state == "checking") then
        local at = Orders.local_().unsure[v.id]
        if at and ns.now() - at <= 600 then return { key = v.id .. "|unsure", decide = true, code = "unsure" } end
    end
    if v.state == "making" then
        if isCrafter and v.returned then return { key = v.id .. "|returned|" .. (v.since or 0), decide = false, code = "returned" } end
        if isCrafter or isCustomer then
            local n = stale("making")
            if n then return { key = v.id .. "|stale|" .. n, decide = false, code = "stale", red = true } end
        end
        return nil
    end
    if v.state == "checking" then
        if isCustomer then
            local n = stale("checking")
            return { key = v.id .. "|check|" .. (n or 0), decide = true, code = v.uncertain and "unsure" or "check", red = n ~= nil }
        end
        if isCrafter and now() - (v.since or t) >= Orders.CRAFTER_CLOSE then
            return { key = v.id .. "|close", decide = true, code = "close" }
        end
    end
    return nil
end

-- Rows the viewer sees, with attention; and the minimap count (unseen).
function Orders.rowsFor(me, myGuid)
    local t = now()
    local seen = Orders.local_().seen
    local days = Orders.staleDays()
    local received, placed = {}, {}
    for _, v in pairs(Orders.all()) do
        local att = Orders.attention(v, me, myGuid, t, days)
        if att and not att.decide and seen[att.key] then att = nil end
        local row = { view = v, attention = att }
        if v.customer == me then
            placed[#placed + 1] = row
        elseif v.crafter == me or (v.state == "waiting" and ((not v.guild and v.crafter == me)
            or (v.guild and Orders.canMake(v, myGuid) and not (v.declined and v.declined[me])))) then
            received[#received + 1] = row
        end
    end
    local function order(x, y)
        local ax, ay = x.attention and 0 or 1, y.attention and 0 or 1
        if ax ~= ay then return ax < ay end
        local cx = (x.view.state == "deal" or x.view.state == "cancel") and 1 or 0
        local cy = (y.view.state == "deal" or y.view.state == "cancel") and 1 or 0
        if cx ~= cy then return cx < cy end
        if x.view.created ~= y.view.created then return x.view.created > y.view.created end
        return x.view.id < y.view.id
    end
    table.sort(received, order)
    table.sort(placed, order)
    return received, placed
end

function Orders.attentionCount()
    local me = S().selfAuthor()
    if not me then return 0 end
    local received, placed = Orders.rowsFor(me, ns.Data.player().guid)
    local n = 0
    for _, list in ipairs({ received, placed }) do
        for _, row in ipairs(list) do if row.attention then n = n + 1 end end
    end
    return n
end

-- Opening the page: "notify" reminders count as seen (R-6.8).
function Orders.markSeen()
    local me = S().selfAuthor()
    if not me then return end
    local seen = Orders.local_().seen
    local received, placed = Orders.rowsFor(me, ns.Data.player().guid)
    for _, list in ipairs({ received, placed }) do
        for _, row in ipairs(list) do
            if row.attention and not row.attention.decide then seen[row.attention.key] = true end
        end
    end
end

---------------------------------------------------------------------------
-- Upload (savedvariables §crafting, upload-api v1.4 §3.10): the halves one
-- author wrote. character.self gets the uploader's own, member.share the
-- subject's. No names, no free text (no note, no ext from the game).
---------------------------------------------------------------------------

Orders.UPLOAD_ORDERS = 100
Orders.UPLOAD_SKILLS = 12
Orders.UPLOAD_RECIPES = 500
local CST = { o = "open", p = "review", r = "returned", d = "deal", x = "cancel" }
local SRC = { g = true, w = true, d = true }
local JST = { a = "accept", n = "decline", b = "drop", d = "delivered", m = "delivered", c = "delivered" }
local HOW = { trade = true, mail = true, manual = true }

local function validId(id) return type(id) == "string" and #id <= 64 and id:match("^[0-9a-z.]+$") ~= nil end
Orders.validUploadId = validId
local function guidOf(a) return a and S().guidOf(a) or nil end
local function num(n) return type(n) == "number" and n >= 0 and math.floor(n) or nil end

function Orders.wHalf(e, a, t)
    local h = {
        recordedAt = t, src = SRC[e.src] and e.src or "g", ver = e.ver or 1, created = num(e.cr),
        customer = guidOf(a), crafter = (e.cf == nil or e.cf == "*") and "*" or guidOf(e.cf),
        lock = e.lk and guidOf(e.lk) or nil, lockedAt = e.lk and num(e.lt) or nil,
        returnedAt = num(e.rt),
        recipe = num(e.rc), item = num(e.it),
        qty = math.max(1, num(e.q) or 1), fee = num(e.fe) or 0, feeQuoted = num(e.fq), quote = num(e.qt),
        cst = CST[e.st or "o"] or "open", got = num(e.gt) or 0,
    }
    for id, n in pairs(Orders.decodeMats(e.m)) do
        h.mats = h.mats or {}
        h.mats[tostring(id)] = n
    end
    if e.st == "d" then
        h.close, h.closedBy, h.closedAt = "deal", "customer", num(e.sa)
        h.closeHow = HOW[e.ch] and e.ch or "manual"
    elseif e.st == "x" then
        h.close, h.closedBy, h.closeHow, h.closedAt = "cancel", "customer", "manual", num(e.sa)
    end
    return h
end

function Orders.jHalf(e, t, view)
    local h = { recordedAt = t, jst = JST[e.st or "a"] or "accept", gave = num(e.gv) or 0,
        acceptedAt = num(e.ac), deliveredAt = num(e.dt), statusAt = num(e.sa) }
    if h.deliveredAt then
        h.deliveredHow = e.st == "m" and "mail" or (HOW[e.ch] and e.ch or "manual")
    end
    local directed = view ~= nil and not view.guild
    if e.st == "c" then
        h.close, h.closedBy, h.closeHow, h.closedAt = "deal", "crafter", "timeout", num(e.sa)
    elseif directed and (e.st == "n" or e.st == "b") then
        h.close, h.closedBy, h.closeHow, h.closedAt = "cancel", "crafter", "manual", num(e.sa)
    end
    return h
end

-- crafting = { services?, orders? } for author a, or nil when there is nothing.
function Orders.craftingFor(a)
    if not a then return nil end
    local out = {}
    local o = led:get(a, "O")
    if o then
        local sv = Orders.decodeServices(o.v)
        local value, skills = {}, 0
        local function slot(skill)
            local k = tostring(skill)
            if not value[k] then
                if skills >= Orders.UPLOAD_SKILLS then return nil end
                skills = skills + 1
                value[k] = { active = sv.active[skill] == true }
            end
            return value[k]
        end
        -- Over the caps the smallest IDs are kept (the same result every time).
        local ids = {}
        for id in pairs(sv.recipeFees) do ids[#ids + 1] = id end
        table.sort(ids)
        local skillOf = {}
        local list, seen = {}, {}
        local function addSkill(skill) if skill and not seen[skill] then seen[skill] = true; list[#list + 1] = skill end end
        for skill in pairs(sv.active) do addSkill(skill) end
        for skill in pairs(sv.fees) do addSkill(skill) end
        for _, id in ipairs(ids) do
            skillOf[id] = sv.recipeSkill[id] or (ns.Recipes and ns.Recipes.skillOfRecipe(id))
            addSkill(skillOf[id])
        end
        table.sort(list)
        for _, skill in ipairs(list) do
            local v = slot(skill)
            if v and sv.fees[skill] ~= nil then v.fee = sv.fees[skill] end
        end
        local perSkill = {}
        for _, id in ipairs(ids) do
            local skill = skillOf[id]
            local v = skill and value[tostring(skill)]
            if v and (perSkill[skill] or 0) < Orders.UPLOAD_RECIPES then
                v.recipes = v.recipes or {}
                v.recipes[tostring(id)] = sv.recipeFees[id]
                perSkill[skill] = (perSkill[skill] or 0) + 1
            end
        end
        if next(value) then out.services = { recordedAt = o.t, value = value } end
    end
    local orders, count, entries = {}, 0, {}
    local wrec, jrec = led:get(a, "W"), led:get(a, "J")
    for _, e in ipairs(wrec and Orders.decodeList(wrec.v) or {}) do
        if validId(e.id) then
            local closed = e.st == "d" or e.st == "x"
            entries[#entries + 1] = { id = e.id, w = e, closed = closed, at = closed and (e.sa or 0) or (e.cr or 0) }
        end
    end
    local views = Orders.all()
    for _, e in ipairs(jrec and Orders.decodeList(jrec.v) or {}) do
        -- Review 5-4: a job whose order is not known any more is not uploaded.
        if validId(e.id) and views[e.id] then
            local v = views[e.id]
            local closed = v ~= nil and (v.state == "deal" or v.state == "cancel")
            entries[#entries + 1] = { id = e.id, j = e, view = v, closed = closed,
                at = closed and (v.closedAt or e.sa or 0) or ((v and v.created) or e.ac or e.sa or 0) }
        end
    end
    -- Over the cap (100 per author): oldest closed (closedAt) first, then oldest open (created).
    table.sort(entries, function(x, y)
        if x.closed ~= y.closed then return not x.closed end
        if x.at ~= y.at then return x.at > y.at end
        return x.id < y.id
    end)
    for _, it in ipairs(entries) do
        local slotted = orders[it.id]
        if not slotted and count < Orders.UPLOAD_ORDERS then
            slotted = {}
            orders[it.id] = slotted
            count = count + 1
        end
        if slotted then
            if it.w then slotted.w = Orders.wHalf(it.w, a, wrec.t) end
            if it.j then slotted.j = Orders.jHalf(it.j, jrec.t, it.view) end
        end
    end
    if count > 0 then out.orders = orders end
    if not out.services and not out.orders then return nil end
    return out
end

-- { cO = { t, h }, cW = ..., cJ = ... } of author a: member.share change detection.
function Orders.uploadState(a)
    local out = {}
    for _, g in ipairs({ "O", "W", "J" }) do
        local r = a and led:get(a, g)
        if r then out["c" .. g] = { t = r.t, h = r.h } end
    end
    return out
end

---------------------------------------------------------------------------
-- Reagent lists over GFTKO (R-8.5): R~recipe asks, S~recipe~output~yield~list answers.
---------------------------------------------------------------------------

local asked, answering = {}, {}
function Orders.askReagents(recipe)
    if not recipe or asked[recipe] then return false end
    asked[recipe] = ns.now()
    return led:enqueue(led:msg("R", b36(recipe)), nil, true)
end

function Orders.onCustom(kind, fields, _, channel)
    if kind == "R" and channel == "GUILD" then
        local recipe = unb36(fields[1])
        local r = recipe and ns.Prices and ns.Prices.cachedReagents(recipe)
        if not r then return "no-reagents" end
        answering[recipe] = true
        ns.after(S().rand(1, 5), function()
            if not answering[recipe] then return end
            answering[recipe] = nil
            led:enqueue(led:msg("S", b36(recipe), ns.Prices.encodeReagents(r)), nil, true)
        end)
        return "ok"
    elseif kind == "S" and channel == "GUILD" then
        local recipe = unb36(fields[1])
        if not recipe then return "malformed" end
        answering[recipe] = nil -- someone answered
        local r = ns.Prices and ns.Prices.decodeReagents(fields[2])
        if r and asked[recipe] and not ns.Prices.cachedReagents(recipe) then ns.Prices.storeReagents(recipe, r, "guild") end
        return "ok"
    end
    return "unknown-type"
end

function Orders.resetSession()
    asked, answering, cache, svCache, activeCache = {}, {}, { version = -1 }, {}, { version = -1 }
    led:resetSession()
end
