-- Prices (GF-006-B, spec §8): merchant prices, our own auction scan, price
-- addons, guild price sharing and the automatic estimate.
--
-- Storage (account-wide, GreenFangToolkitDB.prices):
--   vendor[itemID]  = "<price>.<t>"                 R-8.2.1 (only bought with money)
--   ah[<realm>-<type>][itemID] = "d.m.q[.n]|..."     R-8.4: one string per item,
--       newest day first, up to 14 days; d = day number, m = lowest unit
--       price that day, q = quantity seen, n = reporters (folded shared days)
--   reagents[recipe] = "<output>.<yield>.<id*n+id*n>"  R-8.5 (static data)
--   token = { id, at }                              R-8.6 random reporter code
-- <type> is the auction house type (spec §3): alliance, horde or neutral.
-- A scan whose type is unknown is not stored (better less than mixed).
--
-- Shared prices (R-8.6) travel on the GFTKP ledger: author = our random
-- token (never a GUID or name), group = "<rk>:<day>:<bucket>", value =
-- "<realm>/<type>/<id>.<min>.<qty>,...". Only the last 3 days; older days are
-- folded into ah[] (day value and reporter count only).

local _, ns = ...
local str = ns.str

local Prices = {}
ns.Prices = Prices

Prices.PREFIX = "GFTKP"
Prices.DAYS_KEPT = 14
Prices.REF_DAYS = 7
Prices.GREY_AFTER = 3            -- days: older prices are shown grey
Prices.SHARE_DAYS = 3            -- today, yesterday, the day before
Prices.MAX_ITEMS = 8000          -- per realm + auction house type (own and shared together)
Prices.FORGET_DAYS = 30
Prices.MAX_REPORTERS = 7         -- per item and day
Prices.OUTLIER = 3
Prices.MAX_PRICE = 100000000     -- 10,000 gold in copper
Prices.BUCKETS = 32
Prices.TOKEN_DAYS = 30
Prices.AUTO_SEARCH = 30          -- R-8.4: items looked up when the auction house opens
Prices.FRAME_BUDGET = 4          -- ms per frame
Prices.ITEMS_PER_FRAME = 200     -- when the client has no timer
Prices.NEUTRAL_TOWNS = { ["藏寶海灣"] = true, ["加基森"] = true, ["永望鎮"] = true,
    ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

local function S() return ns.Share end
local function b36(n) return S().b36(n) end
local function unb36(s) return S().unb36(s) end
local function fn(x) return type(x) == "function" end

function Prices.today(t) return math.floor((t or S().serverNow()) / 86400) end

function Prices.db()
    local db = ns.db
    if type(db.prices) ~= "table" then db.prices = {} end
    local p = db.prices
    for _, k in ipairs({ "vendor", "ah", "reagents", "scan" }) do
        if type(p[k]) ~= "table" then p[k] = {} end
    end
    return p
end

function Prices.realmKey(realm, kind) return str(realm) .. "-" .. str(kind) end

-- The auction house type of this character's own faction.
function Prices.homeKind()
    local f = ns.call(UnitFactionGroup, "player")
    if f == "Alliance" then return "alliance" end
    if f == "Horde" then return "horde" end
    return nil
end
function Prices.homeKey()
    local k = Prices.homeKind()
    return k and Prices.realmKey(ns.realm(), k) or nil
end

---------------------------------------------------------------------------
-- Day strings (pure)
---------------------------------------------------------------------------

function Prices.decodeDays(s)
    local list = {}
    for part in str(s):gmatch("[^|]+") do
        local d, m, q, n = part:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)%.?([0-9a-z]*)$")
        if d then list[#list + 1] = { d = unb36(d), m = unb36(m), q = unb36(q), n = n ~= "" and unb36(n) or nil } end
    end
    return list
end

function Prices.encodeDays(list)
    table.sort(list, function(a, b) return a.d > b.d end)
    local out = {}
    for i = 1, math.min(#list, Prices.DAYS_KEPT) do
        local e = list[i]
        out[i] = b36(e.d) .. "." .. b36(e.m) .. "." .. b36(e.q or 0) .. (e.n and ("." .. b36(e.n)) or "")
    end
    return table.concat(out, "|")
end

-- Merge one observation into an item's day string: same day = lowest price.
function Prices.mergeDay(s, day, m, q, n)
    local list = Prices.decodeDays(s)
    for _, e in ipairs(list) do
        if e.d == day then
            if m < e.m then e.m = m end
            if q and q > (e.q or 0) then e.q = q end
            if n and (e.n == nil or n > e.n) then e.n = n end
            return Prices.encodeDays(list)
        end
    end
    list[#list + 1] = { d = day, m = m, q = q or 0, n = n }
    return Prices.encodeDays(list)
end

function Prices.median(values)
    local n = #values
    if n == 0 then return nil end
    local s = {}
    for i, v in ipairs(values) do s[i] = v end
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return math.floor((s[n / 2] + s[n / 2 + 1]) / 2)
end

-- R-8.6: the value of one item on one day. own = our own lowest price (or
-- nil), others = { [token] = lowest price } from other reporters.
-- Others count only with at least 2 different reporters; at most 7 (the
-- ones closest to the median); values 3x away from the median are dropped;
-- with exactly two values 3x apart, neither counts.
function Prices.dayValue(own, others)
    local list = {}
    for _, v in pairs(others or {}) do list[#list + 1] = v end
    table.sort(list)
    if #list > Prices.MAX_REPORTERS then
        local m = Prices.median(list)
        -- Review 3-5: the same distance -> the smaller value (never arrival order).
        table.sort(list, function(a, b)
            local da, db = math.abs(a - m), math.abs(b - m)
            if da ~= db then return da < db end
            return a < b
        end)
        local kept = {}
        for i = 1, Prices.MAX_REPORTERS do kept[i] = list[i] end
        list = kept
    end
    local values = {}
    if own then values[#values + 1] = own end
    if #list >= 2 then for _, v in ipairs(list) do values[#values + 1] = v end end
    if #values == 0 then return nil, #list end
    if #values == 2 then
        local lo, hi = math.min(values[1], values[2]), math.max(values[1], values[2])
        if hi >= lo * Prices.OUTLIER then
            if own then return own, #list end -- our own scan always counts (spec R-8.4)
            return nil, #list
        end
    end
    local m = Prices.median(values)
    local kept = {}
    for _, v in ipairs(values) do
        if v <= m * Prices.OUTLIER and v * Prices.OUTLIER >= m then kept[#kept + 1] = v end
    end
    return Prices.median(kept), #list
end

---------------------------------------------------------------------------
-- Own store
---------------------------------------------------------------------------

function Prices.items(rk)
    local p = Prices.db()
    if type(p.ah[rk]) ~= "table" then p.ah[rk] = {} end
    return p.ah[rk]
end

local itemCount = {}
local function countItems(rk)
    if itemCount[rk] then return itemCount[rk] end
    local n = 0
    for _ in pairs(Prices.items(rk)) do n = n + 1 end
    itemCount[rk] = n
    return n
end

function Prices.priority()
    local set = {}
    if ns.Orders then
        for _, v in pairs(ns.Orders.all()) do
            if v.state ~= "deal" and v.state ~= "cancel" then
                if v.item then set[v.item] = true end
                local r = v.recipe and Prices.cachedReagents(v.recipe)
                for _, x in ipairs(r and r.list or {}) do set[x.id] = true end
            end
        end
    end
    return set
end

local function newestDay(s) return unb36(str(s):match("^([0-9a-z]+)%.")) or 0 end

-- GF-FIX-E (review M-20): eviction candidates, oldest first, built once per
-- realm + type and used until they run out (never a full scan per new item).
-- An entry whose item was refreshed or removed since is skipped.
local evictList = {}
local function candidates(rk)
    local c = evictList[rk]
    if c and c.pos <= #c then return c end
    c = { pos = 1 }
    for id, s in pairs(Prices.items(rk)) do c[#c + 1] = { id = id, d = newestDay(s) } end
    table.sort(c, function(x, y) if x.d ~= y.d then return x.d < y.d end return x.id < y.id end)
    evictList[rk] = c
    return c
end
Prices.evictBuilds = 0 -- tests: how often the candidate list was built

-- Full: forget the item not seen for longest (never one an open order uses).
local function evictOne(rk, keep)
    local items = Prices.items(rk)
    for pass = 1, 2 do
        local before = evictList[rk]
        local c = candidates(rk)
        if c ~= before then Prices.evictBuilds = Prices.evictBuilds + 1 end
        local j = c.pos
        while j <= #c do
            local e = c[j]
            local s = not e.gone and items[e.id]
            if not s or newestDay(s) ~= e.d then
                e.gone = true
                if j == c.pos then c.pos = j + 1 end
            elseif not keep[e.id] then
                items[e.id] = nil
                itemCount[rk] = (itemCount[rk] or 1) - 1
                e.gone = true
                if j == c.pos then c.pos = j + 1 end
                return true
            end
            j = j + 1
        end
        -- Only kept items left in this list: one fresh build may find newer ones.
        if c ~= before or pass == 2 then break end
        evictList[rk] = nil
    end
    return false
end

-- Store one day's lowest unit price of one item (R-8.4).
function Prices.record(rk, id, unit, qty, day, n, keep)
    if not (rk and id and unit and unit > 0 and unit <= Prices.MAX_PRICE) then return false end
    local items = Prices.items(rk)
    if not items[id] then
        if countItems(rk) >= Prices.MAX_ITEMS and not evictOne(rk, keep or {}) then return false end
        itemCount[rk] = countItems(rk) + 1
    end
    items[id] = Prices.mergeDay(items[id], day or Prices.today(), unit, qty, n)
    return true
end

-- Review 1-5: big jobs (prune, fold, publish, cap) run a little every frame.
-- Inside a job, Prices.tick() yields every TICK items; outside a job it does nothing.
Prices.TICK = 200
local jobs, jobsScheduled, ticks = {}, false, 0
local function jobClock() if type(debugprofilestop) == "function" then return debugprofilestop() end end
local function stepJobs()
    jobsScheduled = false
    local start = jobClock()
    while #jobs > 0 do
        local co = jobs[1]
        local ok, err = coroutine.resume(co)
        if not ok then Prices.jobError = tostring(err) end
        if coroutine.status(co) == "dead" then table.remove(jobs, 1) end
        if not start or jobClock() - start >= Prices.FRAME_BUDGET then break end
    end
    if #jobs > 0 then jobsScheduled = true; ns.after(0, stepJobs) end
end
function Prices.background(fn)
    jobs[#jobs + 1] = coroutine.create(fn)
    if not jobsScheduled then jobsScheduled = true; ns.after(0, stepJobs) end
end
function Prices.tick()
    ticks = ticks + 1
    if ticks % Prices.TICK == 0 and coroutine.running() then coroutine.yield() end
end
function Prices.busy() return #jobs > 0 end

-- 30 days unseen: forget (R-8.4).
function Prices.prune(today)
    today = today or Prices.today()
    local p = Prices.db()
    for rk, items in pairs(p.ah) do
        local drop = {}
        for id, s in pairs(items) do
            local d = unb36(str(s):match("^([0-9a-z]+)%.")) or 0
            if today - d > Prices.FORGET_DAYS then drop[#drop + 1] = id end
            Prices.tick()
        end
        for _, id in ipairs(drop) do items[id] = nil end
        itemCount[rk] = nil
        evictList[rk] = nil
    end
end

---------------------------------------------------------------------------
-- Shared prices (R-8.6)
---------------------------------------------------------------------------

function Prices.token()
    local p = Prices.db()
    local t = S().serverNow()
    if type(p.token) ~= "table" or type(p.token.id) ~= "string" or t - (ns.num(p.token.at) or 0) > Prices.TOKEN_DAYS * 86400 then
        local id = "t"
        for _ = 1, 6 do
            local d = math.floor(S().rand(0, 36))
            id = id .. ("0123456789abcdefghijklmnopqrstuvwxyz"):sub(d + 1, d + 1)
        end
        p.token = { id = id, at = t }
    end
    return p.token.id
end

function Prices.rkCode(rk) return S().hash(rk) end

local function groupOf(rk, day, bucket) return Prices.rkCode(rk) .. ":" .. b36(day) .. ":" .. bucket end

function Prices.encodeShare(realm, kind, items)
    local ids = {}
    for id in pairs(items) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        local e = items[id]
        out[#out + 1] = b36(id) .. "." .. b36(e.m) .. "." .. b36(e.q or 0)
    end
    return ns.Ledger.esc(realm) .. "/" .. kind .. "/" .. table.concat(out, ",")
end

-- Returns realm, kind, { [id] = { m, q } }, or nil when anything is out of range
-- (the whole record is dropped, R-8.6).
function Prices.decodeShare(v)
    local realm, kind, body = str(v):match("^([^/]*)/(%a+)/(.*)$")
    if not realm or (kind ~= "alliance" and kind ~= "horde" and kind ~= "neutral") then return nil end
    local items = {}
    for part in body:gmatch("[^,]+") do
        local id, m, q = part:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
        id, m, q = id and unb36(id), m and unb36(m), q and unb36(q)
        if not (id and m and q) or m <= 0 or m > Prices.MAX_PRICE or q < 1 then return nil end
        items[id] = { m = m, q = q }
    end
    return ns.Ledger.unesc(realm), kind, items
end

local function validGroup(g)
    local rk, d, b = str(g):match("^([0-9a-z]+):([0-9a-z]+):([0-9a-z]+)$")
    if not rk then return false end
    local day = unb36(d)
    local today = Prices.today()
    return day ~= nil and day <= today and day > today - Prices.SHARE_DAYS
end

-- GF-FIX-E (review H-6, M-21): records this client dropped to stay within its
-- limits, refused[a|g] = hash, this session only (nothing saved). The same
-- record from another member is then not stored and dropped again; a newer
-- record of that author and group has another hash and is taken at once.
local refused, capSeen = {}, {}
local function refuse(a, g, h) if a and g and h then refused[a .. "|" .. g] = h end end
Prices.refusedCount = function() local n = 0; for _ in pairs(refused) do n = n + 1 end; return n end

local function validValue(a, g, v)
    if #v > 16000 then return false end
    local h = refused[str(a) .. "|" .. str(g)]
    if h and S().hash(v) == h then return false end
    local realm, kind = Prices.decodeShare(v)
    if not realm then return false end
    return g:match("^([0-9a-z]+):") == Prices.rkCode(Prices.realmKey(realm, kind))
end

local sharedCache = { version = -1 }
Prices.ledger = ns.Ledger.new({
    id = "prices", prefix = Prices.PREFIX, burst = 1, refill = 0.5, maxPerSession = 300,
    -- Review 1-6: 7 reporters x 3 days x 33 buckets.
    yieldToShare = true, maxRecords = 700, maxQueue = 300,
    validAuthor = function(a) return type(a) == "string" and a:match("^t[0-9a-z]+$") ~= nil end,
    validGroup = validGroup, validValue = validValue,
    selfAuthor = function() return Prices.token() end,
    priority = function(g) return g:find(":p$") ~= nil or g:find(":p%.") ~= nil end,
    onChange = function()
        sharedCache.version = -1
        -- Review 1-6: shared prices count toward the 8,000 items (checked a moment later).
        ns.coalesce("price-cap", 5, function() Prices.enforceCapAll() end)
    end,
    evict = function(l, s)
        -- GF-FIX-E: never our own records; the dropped one is refused (see refused).
        local pickA, pickG, pickT
        local mine = Prices.token()
        for a, groups in pairs(s.rec) do
            if a ~= mine then
                for g, rec in pairs(groups) do
                    if not pickT or rec.t < pickT then pickA, pickG, pickT = a, g, rec.t end
                end
            end
        end
        if pickA then refuse(pickA, pickG, s.rec[pickA][pickG].h); l:drop(pickA, pickG); return true end
        return false
    end,
})
local led = Prices.ledger

-- shared[rk][id][day] = { [token] = min }, rebuilt when the ledger changes.
function Prices.shared(rk)
    if sharedCache.version ~= led.version then sharedCache = { version = led.version, byRk = {} } end
    local c = sharedCache.byRk[rk]
    if c then return c end
    c = {}
    local code = Prices.rkCode(rk)
    local mine = Prices.token()
    for _, a in ipairs(led:authors()) do
        if a ~= mine then
            for g, rec in pairs(led:records(a)) do
                local gc, d = g:match("^([0-9a-z]+):([0-9a-z]+):")
                if gc == code then
                    local day = unb36(d)
                    local _, _, items = Prices.decodeShare(rec.v)
                    for id, e in pairs(items or {}) do
                        c[id] = c[id] or {}
                        c[id][day] = c[id][day] or {}
                        local prev = c[id][day][a]
                        if not prev or e.m < prev then c[id][day][a] = e.m end
                    end
                end
            end
        end
    end
    sharedCache.byRk[rk] = c
    return c
end

-- Publish today's own prices of rk as our records (no broadcast: others
-- fetch by digest; R-8.6). Order items go into bucket "p" (asked first).
function Prices.publish(rk, today)
    Prices.background(function() Prices.publishNow(rk, today) end)
end

function Prices.publishNow(rk, today)
    today = today or Prices.today()
    local realm, kind = rk:match("^(.*)%-(%a+)$")
    if not realm then return 0 end
    local prio = Prices.priority()
    local buckets = {}
    for id, s in pairs(Prices.items(rk)) do
        local e = Prices.decodeDays(s)[1]
        if e and e.d == today and not e.n then
            local b = prio[id] and "p" or b36(id % Prices.BUCKETS)
            buckets[b] = buckets[b] or {}
            buckets[b][id] = e
        end
        Prices.tick()
    end
    local n = 0
    local token = Prices.token()
    for b, items in pairs(buckets) do
        local r = led:put(groupOf(rk, today, b), Prices.encodeShare(realm, kind, items), token, true)
        if r == "stored" then n = n + 1 end
        Prices.tick()
    end
    if n > 0 then led:announce() end
    return n
end

-- Days that left the 3-day window: keep only the day value and the number
-- of reporters (R-8.6), then drop the records.
function Prices.fold(today)
    today = today or Prices.today()
    local s = led:store()
    if not s then return 0 end
    local folded = {}
    for a, groups in pairs(s.rec) do
        for g, rec in pairs(groups) do
            local d = g:match("^[0-9a-z]+:([0-9a-z]+):")
            local day = d and unb36(d)
            if day and day <= today - Prices.SHARE_DAYS then
                local realm, kind, items = Prices.decodeShare(rec.v)
                if realm then
                    local rk = Prices.realmKey(realm, kind)
                    folded[rk] = folded[rk] or {}
                    for id, e in pairs(items) do
                        folded[rk][id] = folded[rk][id] or {}
                        folded[rk][id][day] = folded[rk][id][day] or {}
                        if a ~= Prices.token() then folded[rk][id][day][a] = e.m end
                        Prices.tick()
                    end
                end
                folded.drop = folded.drop or {}
                folded.drop[#folded.drop + 1] = { a = a, g = g }
            end
        end
    end
    local n = 0
    for rk, ids in pairs(folded) do
        if rk ~= "drop" then
            for id, days in pairs(ids) do
                for day, others in pairs(days) do
                    local count = 0
                    for _ in pairs(others) do count = count + 1 end
                    local value = Prices.dayValue(nil, others)
                    if value then Prices.record(rk, id, value, 0, day, count); n = n + 1 end
                    Prices.tick()
                end
            end
        end
    end
    for _, x in ipairs(folded.drop or {}) do led:drop(x.a, x.g) end
    return n
end

-- Review 1-6: items per realm + type, own and shared together.
function Prices.itemCount(rk)
    local seen, n = {}, 0
    for id in pairs(Prices.items(rk)) do seen[id] = true; n = n + 1 end
    for id in pairs(Prices.shared(rk)) do if not seen[id] then n = n + 1 end end
    return n
end

-- The item IDs of one stored record, without prices (stored records were
-- checked when they arrived).
local function idsOf(v)
    local body = str(v):match("^[^/]*/%a+/(.*)$")
    local ids = {}
    if body then
        for id in body:gmatch("([0-9a-z]+)%.[0-9a-z]+%.[0-9a-z]+") do ids[#ids + 1] = unb36(id) end
    end
    return ids
end

-- Drop many records with one ledger change (one version step, one cache reset).
local function dropMany(list)
    if #list == 0 then return 0 end
    if type(led.dropMany) == "function" then return led:dropMany(list) or #list end
    local s = led:store(true)
    if not s then return 0 end
    local n = 0
    for _, x in ipairs(list) do
        local groups = s.rec[x.a]
        if groups and groups[x.g] then
            groups[x.g] = nil
            if next(groups) == nil then s.rec[x.a] = nil end
            if type(led.digests) == "table" then led.digests[x.a] = nil end
            n = n + 1
        end
    end
    if n > 0 then
        led.totalsCache = nil
        led.version = (led.version or 0) + 1
        sharedCache.version = -1
    end
    return n
end

-- Over 8,000: drop shared records, oldest first, until it fits.
-- GF-FIX-E (review H-6): every record is read once (item IDs only); the
-- records to drop are worked out with per-item counts, then dropped together.
Prices.capReads = 0 -- tests: records read by the last enforceCap
function Prices.enforceCap(rk)
    local code = Prices.rkCode(rk)
    local mine = Prices.token()
    local own = Prices.items(rk)
    local recs = {}
    local s = led:store(true)
    for a, groups in pairs(s and s.rec or {}) do
        if a ~= mine then
            for g, rec in pairs(groups) do
                if g:match("^([0-9a-z]+):") == code then recs[#recs + 1] = { a = a, g = g, t = rec.t, h = rec.h, v = rec.v } end
            end
        end
    end
    Prices.capReads = 0
    if #recs == 0 then return 0 end
    -- Items per record and how many records hold each item.
    local held, total = {}, countItems(rk)
    for _, r in ipairs(recs) do
        r.ids = idsOf(r.v)
        r.v = nil
        Prices.capReads = Prices.capReads + 1
        for _, id in ipairs(r.ids) do
            local n = held[id]
            if not n then
                held[id] = 1
                if not own[id] then total = total + 1 end
            else
                held[id] = n + 1
            end
        end
        Prices.tick()
    end
    if total <= Prices.MAX_ITEMS then return 0 end
    table.sort(recs, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.a .. x.g < y.a .. y.g end)
    local drop = {}
    for _, r in ipairs(recs) do
        if total <= Prices.MAX_ITEMS then break end
        for _, id in ipairs(r.ids) do
            held[id] = held[id] - 1
            if held[id] == 0 and not own[id] then total = total - 1 end
        end
        drop[#drop + 1] = { a = r.a, g = r.g }
        refuse(r.a, r.g, r.h)
        Prices.tick()
    end
    dropMany(drop)
    return #drop
end

-- GF-FIX-E (review M-19): only the "<realm>/<type>/" prefix of each record is
-- read (once per group code), and nothing is done when the ledger has not
-- changed since the last check.
local lastCapVersion
function Prices.enforceCapAll()
    if lastCapVersion == led.version then return 0 end
    lastCapVersion = led.version
    local keys = {}
    local s = led:store(true)
    for _, groups in pairs(s and s.rec or {}) do
        for g, rec in pairs(groups) do
            local code = g:match("^([0-9a-z]+):")
            if code and capSeen[code] == nil then
                local realm, kind = str(rec.v):match("^([^/]*)/(%a+)/")
                if realm and (kind == "alliance" or kind == "horde" or kind == "neutral") then
                    capSeen[code] = Prices.realmKey(ns.Ledger.unesc(realm), kind)
                end
            end
            if code and capSeen[code] then keys[capSeen[code]] = true end
        end
    end
    local n = 0
    for rk in pairs(keys) do n = n + 1; Prices.background(function() Prices.enforceCap(rk) end) end
    return n
end

---------------------------------------------------------------------------
-- Reference price (R-8.4, R-8.6)
---------------------------------------------------------------------------

-- { price, newestDay, grey, single } or nil. single = only one other
-- reporter knows it (shown grey in the tooltip, never in totals).
function Prices.reference(rk, id, today)
    if not (rk and id) then return nil end
    today = today or Prices.today()
    local own = {}
    for _, e in ipairs(Prices.decodeDays(Prices.items(rk)[id])) do own[e.d] = e end
    local shared = Prices.shared(rk)[id] or {}
    local values, newest = {}, nil
    local single
    for day = today - Prices.REF_DAYS + 1, today do
        local o = own[day]
        local v
        if o and o.n then
            v = o.m -- a folded shared day
        else
            local others = shared[day]
            local count
            v, count = Prices.dayValue(o and o.m or nil, others)
            if not v and count == 1 then
                for _, x in pairs(others) do single = { price = x, day = day } end
            end
        end
        if v then values[#values + 1] = v; newest = day end
    end
    local price = Prices.median(values)
    if not price then
        if single then return { price = single.price, newestDay = single.day, grey = true, single = true } end
        return nil
    end
    return { price = price, newestDay = newest, grey = today - newest >= Prices.GREY_AFTER }
end

---------------------------------------------------------------------------
-- Price addons (optional; R-8.2.2). Names not verified on Forever: every call
-- is protected, and a missing addon is simply skipped.
---------------------------------------------------------------------------

function Prices.pluginPrice(id)
    local link = "item:" .. tostring(id)
    if type(Auctionator) == "table" and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table"
        and fn(Auctionator.API.v1.GetAuctionPriceByItemID) then
        local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "GreenFangToolkit", id)
        if ok and ns.num(v) and v > 0 then return v, "Auctionator" end
    end
    if type(TSM_API) == "table" and fn(TSM_API.GetCustomPriceValue) then
        local ok, v = pcall(TSM_API.GetCustomPriceValue, "DBMarket", "i:" .. tostring(id))
        if ok and ns.num(v) and v > 0 then return v, "TSM" end
    end
    if type(AucAdvanced) == "table" and type(AucAdvanced.API) == "table" and fn(AucAdvanced.API.GetMarketValue) then
        local ok, v = pcall(AucAdvanced.API.GetMarketValue, link)
        if ok and ns.num(v) and v > 0 then return v, "Auctioneer" end
    end
    return nil
end

---------------------------------------------------------------------------
-- Merchant prices (R-8.2.1)
---------------------------------------------------------------------------

function Prices.vendorPrice(id)
    local v = Prices.db().vendor[id]
    local p = v and unb36(str(v):match("^([0-9a-z]+)"))
    return p
end

function Prices.readMerchant()
    local n = fn(GetMerchantNumItems) and ns.num((ns.call(GetMerchantNumItems))) or 0
    local stored = 0
    local p = Prices.db()
    for i = 1, n do
        local id = fn(GetMerchantItemID) and ns.num((ns.call(GetMerchantItemID, i))) or nil
        local price, stack, extended
        if type(C_MerchantFrame) == "table" and fn(C_MerchantFrame.GetItemInfo) then
            local info = ns.call(C_MerchantFrame.GetItemInfo, i)
            if type(info) == "table" then
                price, stack, extended = ns.num(info.price), ns.num(info.stackCount), info.hasExtendedCost
            end
        end
        if price == nil and fn(GetMerchantItemInfo) then
            local _, _, pr, qty, _, _, _, ext = ns.call(GetMerchantItemInfo, i)
            price, stack, extended = ns.num(pr), ns.num(qty), ext
        end
        if id and price and price > 0 and not extended then
            local unit = math.floor(price / math.max(1, stack or 1) + 0.5)
            p.vendor[id] = b36(unit) .. "." .. b36(S().serverNow())
            stored = stored + 1
        end
    end
    return stored
end

---------------------------------------------------------------------------
-- Reagent lists (R-8.5)
---------------------------------------------------------------------------

function Prices.encodeReagents(r)
    local parts = {}
    for _, x in ipairs(r.list) do parts[#parts + 1] = tostring(x.id) .. "*" .. tostring(x.n) end
    return tostring(r.output or 0) .. "." .. tostring(r.yield or 1) .. "." .. table.concat(parts, "+")
end
function Prices.decodeReagents(s)
    local out, yield, body = str(s):match("^(%d+)%.(%d+)%.(.*)$")
    if not out then return nil end
    local r = { output = tonumber(out), yield = math.max(1, tonumber(yield)), list = {} }
    if r.output == 0 then r.output = nil end
    for id, n in body:gmatch("(%d+)%*(%d+)") do r.list[#r.list + 1] = { id = tonumber(id), n = tonumber(n) } end
    if #r.list == 0 or #r.list > 12 then return nil end
    return r
end

function Prices.cachedReagents(recipe)
    local s = Prices.db().reagents[recipe]
    return s and Prices.decodeReagents(s) or nil
end

function Prices.storeReagents(recipe, r, from)
    if not (recipe and r and #r.list > 0) then return false end
    Prices.db().reagents[recipe] = Prices.encodeReagents(r)
    if from then Prices.reagentSource = from end
    return true
end

-- The client's own schematic (works for own recipes; others: not verified).
function Prices.schematic(recipe)
    local T = C_TradeSkillUI
    if type(T) ~= "table" or not fn(T.GetRecipeSchematic) then return nil end
    local ok, s = pcall(T.GetRecipeSchematic, recipe, false)
    if not ok or type(s) ~= "table" then return nil end
    local r = { output = ns.num(s.outputItemID), yield = math.max(1, ns.num(s.quantityMin) or 1), list = {} }
    for _, slot in ipairs(type(s.reagentSlotSchematics) == "table" and s.reagentSlotSchematics or {}) do
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local id = first and ns.num(first.itemID)
        local n = ns.num(slot.quantityRequired)
        -- Basic reagents only (optional / finishing slots have reagentType ~= 1 on retail).
        if id and n and n > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
            r.list[#r.list + 1] = { id = id, n = n }
        end
    end
    if #r.list == 0 then return nil end
    return r
end

-- Cache → schematic → ask the guild (answer arrives later) → nil.
function Prices.reagents(recipe)
    local r = Prices.cachedReagents(recipe)
    if r then return r, "cache" end
    r = Prices.schematic(recipe)
    if r then Prices.storeReagents(recipe, r); return r, "client" end
    if ns.Orders then ns.Orders.askReagents(recipe) end
    return nil, "asked"
end

-- After reading our own profession window: remember the lists (a few per frame).
function Prices.cacheOwn(ids)
    local i = 1
    local function step()
        local done = 0
        while i <= #ids and done < 20 do
            local id = ids[i]
            if not Prices.cachedReagents(id) then
                local r = Prices.schematic(id)
                if r then Prices.storeReagents(id, r) end
            end
            i = i + 1
            done = done + 1
        end
        if i <= #ids then ns.after(0.1, step) end
    end
    step()
end

---------------------------------------------------------------------------
-- Price of one item and the estimate (R-8.1 – R-8.3)
---------------------------------------------------------------------------

-- { price, source = "vendor"|"addon"|"scan", grey } or nil.
function Prices.priceOf(id, rk)
    local v = Prices.vendorPrice(id)
    if v then return { price = v, source = "vendor" } end
    local a, name = Prices.pluginPrice(id)
    if a then return { price = a, source = "addon", addon = name } end
    local r = Prices.reference(rk or Prices.homeKey(), id)
    if r and not r.single then return { price = r.price, source = "scan", grey = r.grey } end
    return nil, r
end

-- R-8.3: the finished item's market price (addon, else our reference).
function Prices.marketOf(id, rk)
    local a = Prices.pluginPrice(id)
    if a then return { price = a, source = "addon" } end
    local r = Prices.reference(rk or Prices.homeKey(), id)
    if r and not r.single then return { price = r.price, source = "scan", grey = r.grey } end
    return nil
end

-- reagents = { output, yield, list = { { id, n } } } or nil; qty = items
-- wanted; mine = { [itemID] = true | count } materials the customer gives
-- (true = all of it; GF-006-D: a count = that many, the rest is bought);
-- priceOf(id) -> { price } or nil. Returns { mats = { { id, need, own, buy,
-- unit, total, mine, unknown } }, total, unknown = true when a price is
-- missing for a material that has to be bought, missing = { itemID... } those
-- materials, crafts }. Only the part that is not brought is charged.
function Prices.estimate(reagents, qty, mine, priceOf)
    local out = { mats = {}, total = 0, unknown = false, missing = {} }
    if not reagents then out.noList = true; return out end
    local crafts = math.ceil(math.max(1, qty or 1) / math.max(1, reagents.yield or 1))
    out.crafts = crafts
    for _, x in ipairs(reagents.list) do
        local need = x.n * crafts
        local m = mine and mine[x.id]
        local own = m == true and need or math.max(0, math.min(need, math.floor(tonumber(m) or 0)))
        local row = { id = x.id, need = need, own = own, buy = need - own, mine = own >= need }
        if row.buy > 0 then
            local p = priceOf(x.id)
            if p and p.price then
                row.unit, row.total = p.price, p.price * row.buy
                out.total = out.total + row.total
            else
                row.unknown = true
                out.unknown = true
                out.missing[#out.missing + 1] = x.id
            end
        end
        out.mats[#out.mats + 1] = row
    end
    return out
end

---------------------------------------------------------------------------
-- Auction house (R-8.4): type, one-click scan, quiet lookups on open
---------------------------------------------------------------------------

Prices.ah = { open = false }

-- spec §3: the NPC's faction, and whether we stand in one of the three
-- neutral towns. Unknown -> nil (the scan is then not stored).
function Prices.detectKind()
    local faction = ns.call(UnitFactionGroup, "npc")
    local sub, zone = str(ns.call(GetSubZoneText)), str(ns.call(GetZoneText))
    local neutralTown = Prices.NEUTRAL_TOWNS[sub] or Prices.NEUTRAL_TOWNS[zone]
    if neutralTown and (faction == nil or faction == "Neutral" or faction == "") then return "neutral" end
    if not neutralTown and faction == "Alliance" then return "alliance" end
    if not neutralTown and faction == "Horde" then return "horde" end
    return nil
end

local function clock()
    if fn(debugprofilestop) then return debugprofilestop() end
    return nil
end

-- A job that runs a little every frame (R-8.4: the game must not hang).
local worker
local function runSoon()
    if worker and not worker.scheduled then
        worker.scheduled = true
        ns.after(0, function()
            if not worker then return end
            worker.scheduled = false
            local start = clock()
            local n = 0
            while worker do
                local more = worker.step()
                n = n + 1
                if not more then
                    local w = worker
                    worker = nil
                    if w.done then w.done() end
                    return
                end
                if start then
                    if clock() - start >= Prices.FRAME_BUDGET then break end
                elseif n >= Prices.ITEMS_PER_FRAME then break end
            end
            Prices.scan.frames = (Prices.scan.frames or 0) + 1
            if ns.OrdersUI and ns.OrdersUI.scanChanged then pcall(ns.OrdersUI.scanChanged) end -- review 7-3
            runSoon()
        end)
    end
end

Prices.scan = { state = "idle" }

function Prices.scanState() return Prices.scan end

-- GF-FIX-E (review M-20): the items of one scan that fit. Items we already
-- have are always updated; new items fit into the free places plus the places
-- of older items (not used by an open order, not in this scan). When more are
-- new than that, the ones an open order uses come first, then the most offered,
-- then the smaller ID; the rest are left out, so a scan never pushes out what
-- it has just stored.
function Prices.fitScan(rk, agg, keep)
    local items = Prices.items(rk)
    local known, fresh, left = {}, {}, 0
    for id in pairs(agg) do
        if items[id] then known[#known + 1] = id else fresh[#fresh + 1] = id end
    end
    local room = Prices.MAX_ITEMS - countItems(rk)
    if #fresh > room then
        local today = Prices.today()
        for id, s in pairs(items) do
            if not keep[id] and not agg[id] and newestDay(s) < today then room = room + 1 end
        end
    end
    if #fresh > room then
        table.sort(fresh, function(x, y)
            local kx, ky = keep[x] and 0 or 1, keep[y] and 0 or 1
            if kx ~= ky then return kx < ky end
            local qx, qy = agg[x].q or 0, agg[y].q or 0
            if qx ~= qy then return qx > qy end
            return x < y
        end)
        left = #fresh - math.max(room, 0)
        for k = #fresh, math.max(room, 0) + 1, -1 do fresh[k] = nil end
    end
    for _, id in ipairs(fresh) do known[#known + 1] = id end
    return known, left
end

-- Collect results into agg[id] = { m, q }, then store them.
local function commit(rk, agg, how)
    local keep = Prices.priority()
    local ids, left = Prices.fitScan(rk, agg, keep)
    Prices.scan.leftOut = left -- not saved: shown by diagnostics only
    local i, today = 1, Prices.today()
    worker = {
        step = function()
            local id = ids[i]
            if not id then return false end
            Prices.record(rk, id, agg[id].m, agg[id].q, today, nil, keep)
            i = i + 1
            return true
        end,
        done = function()
            local p = Prices.db()
            p.scan.last = { at = S().serverNow(), how = how, items = #ids, rk = rk,
                frames = Prices.scan.frames, seconds = ns.now() - (Prices.scan.started or ns.now()) }
            Prices.scan.state = "done"
            Prices.publish(rk, today)
            if ns.OrdersUI and ns.OrdersUI.scanChanged then ns.OrdersUI.scanChanged() end
        end,
    }
    runSoon()
end

local function add(agg, id, unit, qty)
    if not (id and unit and unit > 0) then return end
    local e = agg[id]
    if not e then agg[id] = { m = unit, q = qty or 1 }
    else
        if unit < e.m then e.m = unit end
        e.q = e.q + (qty or 1)
    end
end

local AH = function() return type(C_AuctionHouse) == "table" and C_AuctionHouse or nil end

function Prices.canReplicate() local A = AH(); return A ~= nil and fn(A.ReplicateItems) and fn(A.GetNumReplicateItems) and fn(A.GetReplicateItemInfo) end
function Prices.canBrowse() local A = AH(); return A ~= nil and fn(A.SendBrowseQuery) and fn(A.GetBrowseResults) end
function Prices.canSearch() local A = AH(); return A ~= nil and fn(A.SendSearchQuery) and fn(A.MakeItemKey) end

-- R-8.4: the ⚖ button. Returns "started" or why not.
function Prices.startScan()
    if not Prices.ah.open then return "closed" end
    if ns.inCombat() then return "combat" end
    if Prices.scan.state == "running" then return "running" end
    local kind = Prices.ah.kind or Prices.detectKind()
    Prices.ah.kind = kind
    if not kind then Prices.scan.lastError = "unknown-kind"; return "unknown-kind" end
    local rk = Prices.realmKey(ns.realm(), kind)
    Prices.scan = { state = "running", rk = rk, started = ns.now(), frames = 0 }
    if Prices.canReplicate() then
        Prices.scan.how = "replicate"
        local ok = pcall(AH().ReplicateItems)
        if ok then
            -- REPLICATE_ITEM_LIST_UPDATE starts the reading; a timeout falls back to browsing.
            local s = Prices.scan
            ns.after(30, function()
                if Prices.scan == s and s.state == "running" and not s.reading then Prices.startBrowse(rk) end
            end)
            return "started"
        end
    end
    return Prices.startBrowse(rk)
end

function Prices.onReplicate()
    local s = Prices.scan
    if s.state ~= "running" or s.how ~= "replicate" or s.reading then return end
    s.reading = true
    local A = AH()
    local total = ns.num((ns.call(A.GetNumReplicateItems))) or 0
    s.total = total
    local agg, i = {}, 0
    worker = {
        step = function()
            if not Prices.ah.open or ns.inCombat() then return false end
            if i >= total then return false end
            -- 0-based index on retail.
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = ns.call(A.GetReplicateItemInfo, i)
            count, buyout, itemID = ns.num(count), ns.num(buyout), ns.num(itemID)
            if itemID and count and count > 0 and buyout and buyout > 0 then
                add(agg, itemID, math.floor(buyout / count), count)
            end
            i = i + 1
            s.done = i
            return true
        end,
        done = function()
            if i < total then s.state = "stopped"; return end
            commit(s.rk, agg, "replicate")
        end,
    }
    runSoon()
end

-- Browse by category (materials, consumables, recipes, crafted gear).
Prices.BROWSE_CLASSES = { 7, 0, 9, 2, 4 }
function Prices.startBrowse(rk)
    if not Prices.canBrowse() then
        Prices.scan.state = "unsupported"
        return "unsupported"
    end
    local s = Prices.scan
    s.how, s.rk, s.agg, s.classIndex, s.page = "browse", rk, {}, 0, 0
    Prices.nextBrowse()
    return "started"
end

function Prices.nextBrowse()
    local s = Prices.scan
    if s.state ~= "running" or s.how ~= "browse" then return end
    -- Review 7-2: GetBrowseResults is cumulative: the last list of a class replaces, never adds.
    for id, e in pairs(s.classAgg or {}) do
        local a = s.agg[id]
        if not a then s.agg[id] = { m = e.m, q = e.q } else
            if e.m < a.m then a.m = e.m end
            a.q = a.q + e.q
        end
    end
    s.classAgg = {}
    s.classIndex = s.classIndex + 1
    local class = Prices.BROWSE_CLASSES[s.classIndex]
    if not class then commit(s.rk, s.agg, "browse"); return end
    local query = { searchString = "", sorts = {}, filters = {}, itemClassFilters = { { classID = class } } }
    local ok = pcall(AH().SendBrowseQuery, query)
    if not ok then Prices.nextBrowse(); return end
    Prices.browseTimer(s)
end

-- 15 s without results for this class and page: next class.
function Prices.browseTimer(s)
    s.page = (s.page or 0) + 1
    local class, page = s.classIndex, s.page
    ns.after(15, function()
        if Prices.scan == s and s.state == "running" and s.classIndex == class and s.page == page then Prices.nextBrowse() end
    end)
end

function Prices.onBrowseResults()
    local s = Prices.scan
    if s.state ~= "running" or s.how ~= "browse" then return end
    if ns.inCombat() or not Prices.ah.open then Prices.stopScan(); return end
    local list = ns.call(AH().GetBrowseResults)
    s.classAgg = {}
    for _, r in ipairs(type(list) == "table" and list or {}) do
        local id = type(r.itemKey) == "table" and ns.num(r.itemKey.itemID)
        add(s.classAgg, id, ns.num(r.minPrice), ns.num(r.totalQuantity))
    end
    local A = AH()
    local full = fn(A.HasFullBrowseResults) and ns.call(A.HasFullBrowseResults)
    if full == false and fn(A.RequestMoreBrowseResults) then
        pcall(A.RequestMoreBrowseResults)
        Prices.browseTimer(s)
    else
        Prices.nextBrowse()
    end
end

function Prices.stopScan()
    if Prices.scan.state == "running" then Prices.scan.state = "stopped" end
    worker = nil
end

-- Quiet lookups when the auction house opens (R-8.4): open orders' items, at most 30.
local lookups = {}
function Prices.autoLookup()
    if not Prices.canSearch() or not Prices.ah.kind then return 0 end
    local ids = {}
    for id in pairs(Prices.priority()) do ids[#ids + 1] = id end
    table.sort(ids)
    local n = 0
    for i = 1, math.min(#ids, Prices.AUTO_SEARCH) do
        local id = ids[i]
        local tries = 0
        local function try()
            if not Prices.ah.open or ns.inCombat() then return end
            -- Review 7-1: respect the client's query state.
            local A = AH()
            if fn(A.IsThrottledMessageSystemReady) and ns.call(A.IsThrottledMessageSystemReady) ~= true then
                tries = tries + 1
                if tries <= 20 then ns.after(2, try) end
                return
            end
            local okKey, key = pcall(A.MakeItemKey, id)
            if okKey and key then
                lookups[id] = true
                pcall(A.SendSearchQuery, key, {}, true)
            end
        end
        ns.after(i * 1.2, try)
        n = n + 1
    end
    return n
end

function Prices.onSearchResult(itemID)
    local A = AH()
    if not (A and Prices.ah.kind) then return end
    local id = ns.num(type(itemID) == "table" and itemID.itemID or itemID)
    if not (id and lookups[id]) then return end
    lookups[id] = nil
    local unit, qty
    if fn(A.GetCommoditySearchResultInfo) then
        local r = ns.call(A.GetCommoditySearchResultInfo, id, 1)
        if type(r) == "table" then unit, qty = ns.num(r.unitPrice), ns.num(r.quantity) end
    end
    if not unit and fn(A.GetItemSearchResultInfo) and type(itemID) == "table" then
        local r = ns.call(A.GetItemSearchResultInfo, itemID, 1)
        if type(r) == "table" then unit, qty = ns.num(r.buyoutAmount), ns.num(r.quantity) end
    end
    if unit then Prices.record(Prices.realmKey(ns.realm(), Prices.ah.kind), id, unit, qty) end
end

function Prices.onAuctionShow()
    Prices.ah.open = true
    Prices.ah.kind = Prices.detectKind()
    Prices.autoLookup()
    if ns.OrdersUI and ns.OrdersUI.auctionShown then ns.OrdersUI.auctionShown() end
end

function Prices.onAuctionClosed()
    Prices.ah.open = false
    lookups = {} -- review 1-9
    Prices.stopScan()
    if ns.OrdersUI and ns.OrdersUI.auctionHidden then ns.OrdersUI.auctionHidden() end
end

-- spec §12 item 11: a test build publishes one extreme own price
-- (/gftk prices fake <itemID> <copper>); others' reference must not move.
function Prices.fake(id, copper)
    local rk = Prices.homeKey()
    id, copper = tonumber(id), tonumber(copper)
    if not (rk and id and copper and copper > 0) then return false end
    local items = Prices.items(rk)
    local today = Prices.today()
    local list = {}
    for _, e in ipairs(Prices.decodeDays(items[id])) do if e.d ~= today then list[#list + 1] = e end end
    list[#list + 1] = { d = today, m = math.min(copper, Prices.MAX_PRICE), q = 1 }
    items[id] = Prices.encodeDays(list)
    Prices.publish(rk, today)
    return true
end

function Prices.login()
    Prices.background(function()
        Prices.prune()
        Prices.fold()
        Prices.enforceCapAll()
    end)
    return led:announce()
end

function Prices.resetSession()
    worker, lookups, itemCount, sharedCache = nil, {}, {}, { version = -1 }
    evictList, refused, capSeen, lastCapVersion = {}, {}, {}, nil
    jobs, jobsScheduled = {}, false
    Prices.scan = { state = "idle" }
    Prices.ah = { open = false }
    led:resetSession()
end
