-- Share (GF-001-D10, D-014): automatic in-game sharing and relaying of guild
-- members' data. Design: docs/research/share-design-d014.md.
--
-- Every piece of data is a record keyed by (author, group):
--   B  level and class            P  profession skill points
--   Z  location (only while the author shares it)
--   R<skillLineID>  learned recipe IDs of one profession (phase 2 reads them)
-- A record carries t, the author's GetServerTime() when they observed the
-- value, and h, a hash of the value. Anyone may relay a record; the original
-- author and t never change. Newest t wins; same h with a newer t only moves
-- t forward (a confirmation, no data needed). Tombstones (h = "x") exist only
-- for "R<id>": a profession was given up (D-015: no privacy withdrawals).
--
-- Wire (prefix GFTKS, GUILD only, <= 250 bytes): "S1~<type>~..."
--   I~a~n~g.t.h~...          index of one author's records (n items in all)
--   Q~qid~count~digest~b<buckets>  who holds what? (asked after login)
--   C~qid~part~parts~[k<buckets>~]a.d.m~  catalog: one digest per author
--                            (one replier); with k only the listed buckets
--   A~a~a~...                please send these authors' indexes
--   G~a.g.t~...              please send these records
--   V~a~g~t~h~value          a value that fits in one message
--   B~a~g~t~h~parts / D~a~g~t~part~chunk   a longer value
--   X~a~R<id>~t              a profession was given up
--   K~to~a.g~a.g~...         "I am answering <to> with these records" (D12)
--
-- GF-001-D12 (EVAL-1000-members §3.2): GUILD carries only short messages
-- (I/Q/C summaries, A/G requests, K claims and the author's own changes).
-- Data sent to answer somebody (V/B/D/X replies to G, and pushes of newer
-- copies after their I or V) goes by WHISPER to that member only, if they
-- marked their requests with the field "w2" (0.9.2+). Older clients get
-- GUILD replies as before. A short GUILD claim K goes out right before the
-- whisper, so other holders drop the same reply (design: whisper-replies.md).
-- Numbers are base 36. a is the author's GUID without "Player-".
--
-- D-015: installing the toolkit means sharing; there is no switch. The old
-- GFTK messages (Comm.lua) are still sent and read; received ones become
-- B/P/Z records here.

local _, ns = ...
local str = ns.str
local unpack = unpack or table.unpack

local Share = {}
ns.Share = Share

Share.PREFIX = "GFTKS"
Share.VERSION = "S1"
Share.MAX_BYTES = 250
Share.FUTURE = 600                -- seconds a t may be ahead of our server time
Share.EPOCH = 1700000000          -- 2023-11; anything older is a broken clock
Share.ALLOWANCE = 8               -- messages we may send in a burst
Share.REFILL = 0.9                -- messages per second
Share.STALE = 300                 -- queued data older than this is dropped
Share.RESEND = 60                 -- a record goes out at most once a minute
Share.PART_TIMEOUT = 60
Share.TOMB_KEEP = 60 * 86400
Share.GONE_KEEP = 14 * 86400      -- author missing from the roster this long
Share.LOGIN_DELAY = 20
Share.ZONE_EVERY = 300
Share.CHANGE_DELAY = 30
-- Per-login catch-up and storage scale with the roster (GF-001-D14,
-- EVAL-1000 §3.1 and §3.4); these are the minimums.
Share.MAX_INDEX_ASKS = 60         -- or 0.6 per roster member
Share.MAX_RECORD_ASKS = 120       -- or 2 per roster member
Share.MAX_RECORDS = 2000          -- or 10 per roster member
Share.ASK_EVERY = 10              -- seconds between rounds of requests
Share.ASK_A_PER_ROUND = 2         -- A messages (15 authors each) per round
Share.ASK_G_PER_ROUND = 6         -- G messages (8 records each) per round
Share.MARK = "w2"                 -- "send my data by WHISPER" (requests and indexes, D12)
Share.CAPABLE_KEEP = 600          -- a w2 mark is trusted this long
Share.TARGET_FRESH = 120          -- only whisper someone heard from this recently
Share.MAX_QUEUE = 300             -- queued replies beyond this are dropped
Share.MAX_PER_TARGET = 60         -- queued whispers per member
Share.GONE_HIDE = 30              -- seconds a "player not found" may follow our whisper
-- Catalog buckets (GF-001-D14, EVAL-1000 §3.3): authors are split into 64
-- buckets by a hash of their id. A 0.10 Q carries every bucket's digest
-- (3 characters each, 192 in all); a 0.10 replier answers only the buckets
-- that differ. 1,000 members: about 16 authors, 3 messages per bucket.
Share.BUCKETS = 64
Share.BUCKET_WIDTH = 3

Share.rand = function(a, b) return a + math.random() * (b - a) end -- tests replace it

local stats = { sent = 0, received = 0, throttled = 0, dropped = 0, relayed = 0, whispered = 0, evicted = 0 }
Share.stats = stats

---------------------------------------------------------------------------
-- Encoding (pure)
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function Share.b36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        out[#out + 1] = DIGITS:sub(d + 1, d + 1)
        n = (n - d) / 36
    end
    return string.reverse(table.concat(out))
end

function Share.unb36(s)
    if type(s) ~= "string" or s == "" or s:find("[^0-9a-z]") then return nil end
    return tonumber(s, 36)
end

-- 24-bit polynomial hash of a string, base 36. Same everywhere.
local function hashNum(s)
    local h = #s % 16777213
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 16777213 end
    return h
end
function Share.hash(s) return Share.b36(hashNum(s)) end

-- Bucket (0 .. BUCKETS-1) of an author id.
function Share.bucketOf(a) return hashNum(a) % Share.BUCKETS end

-- Fixed-width hash for a bucket digest ("0000" for an empty bucket).
local function fixed(s)
    if s == "" then return string.rep("0", Share.BUCKET_WIDTH) end
    local v = Share.b36(hashNum(s) % (36 ^ Share.BUCKET_WIDTH))
    return string.rep("0", Share.BUCKET_WIDTH - #v) .. v
end

-- A set of buckets <-> a string of 2-character base-36 bucket numbers (a
-- 64-bit mask would not fit a Lua number exactly).
local function two(b) local v = Share.b36(b); return #v < 2 and ("0" .. v) or v end
function Share.maskOf(set)
    local list = {}
    for b in pairs(set) do list[#list + 1] = b end
    table.sort(list)
    for i, b in ipairs(list) do list[i] = two(b) end
    return table.concat(list)
end
function Share.inMask(mask, b)
    local want = two(b)
    for i = 1, #mask - 1, 2 do if mask:sub(i, i + 1) == want then return true end end
    return false
end

-- Escape separators and control bytes. Explicit byte tests: "%c" depends on
-- the C locale and can match bytes inside UTF-8 characters.
local SPECIAL = { [37] = true, [59] = true, [61] = true, [44] = true, [47] = true, [126] = true, [124] = true, [46] = true }
local function esc(v)
    return (str(v):gsub(".", function(c)
        local b = c:byte()
        if b < 32 or b == 127 or SPECIAL[b] then return string.format("%%%02X", b) end
        return c
    end))
end
local function unesc(v)
    return (v:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end))
end

-- Sorted IDs: first as is, then differences; base 36, "." separated.
function Share.encodeIDs(ids)
    local list = {}
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        if id and id > 0 then list[#list + 1] = math.floor(id) end
    end
    table.sort(list)
    local out, prev = {}, 0
    for _, id in ipairs(list) do
        if id ~= prev then out[#out + 1] = Share.b36(id - prev); prev = id end
    end
    return table.concat(out, ".")
end

function Share.decodeIDs(s)
    local ids, prev = {}, 0
    if s == "" then return ids end
    for part in (s .. "."):gmatch("([^%.]*)%.") do
        local d = Share.unb36(part)
        if not d or d == 0 then return nil end
        prev = prev + d
        ids[#ids + 1] = prev
    end
    return ids
end

-- Value of a group <-> its wire string.
-- GF-010: groups other modules add (Share.defineGroup): { encode, decode,
-- tomb = true when the author may withdraw it }. Checked after the built-in ones.
Share.GROUPS = {}
function Share.defineGroup(g, def)
    assert(type(g) == "string" and g:match("^[A-Z][A-Za-z0-9]*$") and not g:match("^[BPZR]"), "group name")
    assert(type(def) == "table" and type(def.encode) == "function" and type(def.decode) == "function", "group codec")
    Share.GROUPS[g] = def
    return def
end

function Share.encodeValue(g, d)
    local def = Share.GROUPS[g]
    if def then return def.encode(d) end
    if g == "B" then
        if type(d.level) ~= "number" then return nil end
        return tostring(math.floor(d.level)) .. "." .. esc(d.classToken or "")
    elseif g == "P" then
        local list = {}
        for _, p in ipairs(d or {}) do
            if type(p.skillLineID) == "number" then list[#list + 1] = p end
        end
        -- Author's order (GetProfessions order) is kept; everyone relays the string as is.
        local out = {}
        for _, p in ipairs(list) do
            out[#out + 1] = string.format("%d,%d,%d", p.skillLineID, tonumber(p.rank) or 0, tonumber(p.max) or 0)
        end
        return table.concat(out, "/")
    elseif g == "Z" then
        if type(d) ~= "table" or str(d.zone) == "" then return nil end
        return esc(d.zone) .. "/" .. esc(d.subZone or "")
    elseif g:match("^R%d+$") then
        return Share.encodeIDs(d)
    end
    return nil
end

function Share.decodeValue(g, v)
    if type(v) ~= "string" then return nil end
    local def = Share.GROUPS[g]
    if def then return def.decode(v) end
    if g == "B" then
        local level, class = v:match("^(%d+)%.(.*)$")
        level = tonumber(level)
        if not level or level < 1 or level > 200 then return nil end
        class = unesc(class)
        return { level = level, classToken = class ~= "" and class or nil }
    elseif g == "P" then
        local list = {}
        if v == "" then return list end
        for item in (v .. "/"):gmatch("([^/]*)/") do
            local id, rank, max = item:match("^(%d+),(%d+),(%d+)$")
            if not id then return nil end
            list[#list + 1] = { skillLineID = tonumber(id), rank = tonumber(rank), max = tonumber(max) }
        end
        return list
    elseif g == "Z" then
        local zone, sub = v:match("^([^/]*)/([^/]*)$")
        if not zone or zone == "" then return nil end
        zone, sub = unesc(zone), unesc(sub)
        return { zone = zone, subZone = (sub ~= "" and sub ~= zone) and sub or nil }
    elseif g:match("^R%d+$") then
        return Share.decodeIDs(v)
    end
    return nil
end

local function validGroup(g)
    return g == "B" or g == "P" or g == "Z" or (type(g) == "string" and g:match("^R%d+$") ~= nil)
        or Share.GROUPS[g] ~= nil -- GF-010
end

function Share.authorOf(guid)
    guid = str(guid)
    local a = guid:match("^Player%-(.+)$") or guid
    if a == "" or a:find("[~%.]") then return nil end
    return a
end
function Share.guidOf(a) return "Player-" .. a end

---------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------

function Share.serverNow()
    local t = ns.num((ns.call(GetServerTime)))
    return t or ns.now()
end

---------------------------------------------------------------------------
-- Storage: GreenFangToolkitDB.share.guilds[<realm|guild>]
---------------------------------------------------------------------------

local function guildKey()
    -- Sync.player keeps the session's guild when the client briefly reports
    -- none (logout, /reload): the logout writes need the store (GF-001-D14).
    local p = ns.Sync.player()
    if not p.guild then return nil end
    return ns.guildKey(p.realm, p.guild)
end

-- GF-001-D23: records kept under "|<guild>" while the realm was empty,
-- merged into the realm's store g (newer wins).
local mergeChecked
function Share.mergeLost(g, old)
    for a, groups in pairs(type(old.rec) == "table" and old.rec or {}) do
        g.rec[a] = g.rec[a] or {}
        for gr, rec in pairs(groups) do
            local mine = g.rec[a][gr]
            if type(rec) == "table" and (not mine or (ns.num(rec.t) or 0) > (ns.num(mine.t) or 0)) then
                g.rec[a][gr] = rec
            end
        end
    end
    for a, groups in pairs(type(old.tomb) == "table" and old.tomb or {}) do
        g.tomb[a] = g.tomb[a] or {}
        for gr, t in pairs(groups) do
            if type(t) == "number" and t > (g.tomb[a][gr] or 0) then g.tomb[a][gr] = t end
        end
    end
    if Share.recount then Share.recount() end
end

local function store()
    local db = ns.db
    if not db then return nil end
    if type(db.share) ~= "table" then db.share = { v = 1 } end
    if type(db.share.guilds) ~= "table" then db.share.guilds = {} end
    if type(db.share.seenIDs) ~= "table" then db.share.seenIDs = {} end
    local key = guildKey()
    if not key then return nil end
    local g = db.share.guilds[key]
    if type(g) ~= "table" then g = {}; db.share.guilds[key] = g end
    -- queued/idsSent/named: what this client last wrote to the outbox (phase 4).
    for _, k in ipairs({ "rec", "tomb", "gone", "queued", "idsSent", "named" }) do
        if type(g[k]) ~= "table" then g[k] = {} end
    end
    -- GF-001-D23: while GetRealmName() gave "", 0.9.5/0.9.6 kept this guild's
    -- data under "|<guild>". Merge it in once the realm is known (newer wins).
    -- What was written to the outbox from it (queued/idsSent/named) is not
    -- merged: those members are simply written again.
    -- Checked once per store key: store() is called very often.
    if key ~= mergeChecked then
        mergeChecked = key
        local lost = "|" .. ns.str(ns.Sync.player().guild)
        if key ~= lost and type(db.share.guilds[lost]) == "table" then
            Share.mergeLost(g, db.share.guilds[lost])
            db.share.guilds[lost] = nil
        end
    end
    return g
end
Share.store = store

function Share.get(a, g)
    local s = store()
    return s and s.rec[a] and s.rec[a][g] or nil
end

function Share.records(a)
    local s = store()
    return s and s.rec[a] or nil
end

-- Newest tombstone covering group g of author a, or nil.
local function tombFor(s, a, g)
    local t = s.tomb[a]
    if not t then return nil end
    local best = t["*"]
    if t[g] and (not best or t[g] > best) then best = t[g] end
    return best
end

local function rosterSize()
    local snap = ns.Roster.current()
    return snap and (tonumber(snap.total) or #snap.members) or 0
end
function Share.maxRecords() return math.max(Share.MAX_RECORDS, rosterSize() * 10) end
function Share.maxIndexAsks() return math.max(Share.MAX_INDEX_ASKS, math.ceil(rosterSize() * 0.6)) end
function Share.maxRecordAsks() return math.max(Share.MAX_RECORD_ASKS, rosterSize() * 2) end

-- Record count, cached in memory (recounted after deletions). GF-001-D11.
local recordCount
local function countRecords(s)
    if recordCount then return recordCount end
    local n = 0
    for _, groups in pairs(s.rec) do for _ in pairs(groups) do n = n + 1 end end
    recordCount = n
    return n
end
-- After records were merged in (GF-001-D23): count again, rebuild indexes.
function Share.recount()
    recordCount = nil
    Share.version = (Share.version or 0) + 1
end

-- Digest of everything we know about author a: records and tombstones.
-- Cached per author; changed() and deletions clear it (GF-001-D14).
local digestCache = {}
function Share.digest(a)
    local c = digestCache[a]
    if c then return c.d, c.m end
    local d, m = Share.digestNow(a)
    digestCache[a] = { d = d, m = m }
    return d, m
end
function Share.digestNow(a)
    local s = store()
    local items, maxT = {}, 0
    if not s then return "0", 0 end
    for g, r in pairs(s.rec[a] or {}) do
        items[#items + 1] = g .. "." .. Share.b36(r.t) .. "." .. r.h
        if r.t > maxT then maxT = r.t end
    end
    for g, t in pairs(s.tomb[a] or {}) do
        items[#items + 1] = g .. "." .. Share.b36(t) .. ".x"
        if t > maxT then maxT = t end
    end
    if #items == 0 then return "0", 0 end
    table.sort(items)
    return Share.hash(table.concat(items, ";")), maxT
end

function Share.authors()
    local s = store()
    local set, list = {}, {}
    if not s then return list end
    for a in pairs(s.rec) do set[a] = true end
    for a in pairs(s.tomb) do set[a] = true end
    for a in pairs(set) do list[#list + 1] = a end
    table.sort(list)
    return list
end

-- Totals and bucket digests, cached until the data changes (Share.version).
local totalsCache = {}
local function totals()
    if totalsCache.version == Share.version and totalsCache.version then return totalsCache end
    local parts, buckets = {}, {}
    for b = 0, Share.BUCKETS - 1 do buckets[b] = {} end
    for _, a in ipairs(Share.authors()) do
        local item = a .. "." .. (Share.digest(a))
        parts[#parts + 1] = item
        local list = buckets[Share.bucketOf(a)]
        list[#list + 1] = item
    end
    local digests = {}
    for b = 0, Share.BUCKETS - 1 do digests[b + 1] = fixed(table.concat(buckets[b], ";")) end
    totalsCache = {
        version = Share.version,
        count = #parts,
        digest = #parts == 0 and "0" or Share.hash(table.concat(parts, ";")),
        buckets = table.concat(digests),
    }
    return totalsCache
end

function Share.totalDigest()
    local t = totals()
    return t.count, t.digest
end

-- All bucket digests in one string (BUCKETS x BUCKET_WIDTH characters).
function Share.bucketDigests() return totals().buckets end

-- Buckets whose digest differs from theirs: a set, or nil when theirs is
-- not a bucket string (then everything is answered).
function Share.differingBuckets(theirs)
    local w = Share.BUCKET_WIDTH
    if type(theirs) ~= "string" or #theirs ~= Share.BUCKETS * w or theirs:find("[^0-9a-z]") then return nil end
    local mine = Share.bucketDigests()
    local set, any = {}, false
    for b = 0, Share.BUCKETS - 1 do
        if theirs:sub(b * w + 1, b * w + w) ~= mine:sub(b * w + 1, b * w + w) then set[b] = true; any = true end
    end
    return any and set or nil
end

---------------------------------------------------------------------------
-- Roster lookups
---------------------------------------------------------------------------

-- author -> roster member, rebuilt only when the roster snapshot changes.
local indexFor, indexByA
local function rosterIndex()
    local snap = ns.Roster.current()
    if not snap then return nil end
    if indexFor == snap then return indexByA, snap end
    local byA = {}
    for _, m in ipairs(snap.members) do
        local a = m.guid and Share.authorOf(m.guid)
        if a then byA[a] = m end
    end
    indexFor, indexByA = snap, byA
    return byA, snap
end

-- Decoded value of a record, cached by hash (recipe lists are decoded often).
local decodedCache = {}
function Share.decoded(a, g)
    local rec = Share.get(a, g)
    if not rec then return nil end
    local key = a .. "|" .. g
    local c = decodedCache[key]
    if c and c.h == rec.h then return c.value end
    local value = Share.decodeValue(g, rec.v)
    decodedCache[key] = { h = rec.h, value = value }
    return value
end

function Share.memberFor(a)
    local byA = rosterIndex()
    return byA and byA[a] or nil
end

function Share.selfAuthor()
    return Share.authorOf(ns.Data.player().guid)
end

---------------------------------------------------------------------------
-- Accepting records
---------------------------------------------------------------------------

local listeners = {}
function Share.onUpdate(fn) listeners[#listeners + 1] = fn end

-- Rebuild ns.db.peers[name] (the roster window's data) from a's records.
local function updatePeer(a, direct)
    if a == Share.selfAuthor() then return end
    local m = Share.memberFor(a)
    local recs = Share.records(a)
    if not m or not ns.db then return end
    if type(ns.db.peers) ~= "table" then ns.db.peers = {} end
    local key = ns.keyName(m.name)
    if not recs or not next(recs) then ns.db.peers[key] = nil; return end
    local peer = { name = m.name, guid = m.guid, guild = ns.targetGuildName(), receivedAt = ns.now() }
    peer.realm = m.name:match("^.-%-(.+)$") or ns.realm()
    local newest = 0
    for g, r in pairs(recs) do
        if r.t > newest and (g == "B" or g == "P" or g == "Z") then newest = r.t end
    end
    local b = recs.B and Share.decoded(a, "B")
    if b then peer.level, peer.classToken = b.level, b.classToken end
    local p = recs.P and ns.copy(Share.decoded(a, "P"))
    if p then
        for _, prof in ipairs(p) do
            prof.name = ns.Data.skillName(nil, prof.skillLineID) or ("專業 " .. prof.skillLineID)
        end
        peer.professions = p
    end
    peer.location = recs.Z and ns.copy(Share.decoded(a, "Z")) or nil
    peer.reportedAt = newest > 0 and newest or nil
    if not peer.reportedAt then ns.db.peers[key] = nil; return end
    ns.db.peers[key] = peer
end

-- Bumped on every change, so pages can cache what they build (GF-001-D11).
Share.version = 0

local function changed(a, direct)
    digestCache[a] = nil
    Share.version = Share.version + 1
    updatePeer(a, direct)
    for _, fn in ipairs(listeners) do fn(a) end
end

-- Offer one record. Returns a result string:
--   "new" (stored), "confirm" (t moved forward), "same", "older", "tomb",
--   "future", "invalid".
function Share.offer(a, g, t, h, v, fromAuthor, via)
    local s = store()
    if not s then return "invalid" end
    if type(a) ~= "string" or not validGroup(g) or type(t) ~= "number" or type(h) ~= "string" then
        return "invalid"
    end
    if t > Share.serverNow() + Share.FUTURE then return "future" end
    if t < Share.EPOCH then return "invalid" end
    local tomb = tombFor(s, a, g)
    if tomb and tomb >= t then return "tomb" end
    local rec = s.rec[a] and s.rec[a][g]
    if rec then
        if t < rec.t then return "older" end
        if h == rec.h then
            if t == rec.t then rec.heardAt = ns.now(); return "same" end
            rec.t, rec.heardAt = t, ns.now()
            changed(a, fromAuthor)
            return "confirm"
        end
        if t == rec.t then
            -- Same second, different value: the author's own copy wins, else the larger hash.
            if not fromAuthor and (rec.fromAuthor or h < rec.h) then return "same" end
        end
    end
    local value = type(v) == "string" and Share.hash(v) == h and Share.decodeValue(g, v) or nil
    if value == nil then return "invalid" end
    if not rec and countRecords(s) >= Share.maxRecords() and not Share.evict(s) then return "full" end
    if not rec and recordCount then recordCount = recordCount + 1 end
    s.rec[a] = s.rec[a] or {}
    s.rec[a][g] = { t = t, h = h, v = v, heardAt = ns.now(), via = via, fromAuthor = fromAuthor or nil }
    changed(a, fromAuthor)
    return "new"
end

-- Apply a tombstone. Returns true when it was new.
function Share.applyTomb(a, g, t)
    local s = store()
    if not s or type(a) ~= "string" or type(t) ~= "number" then return false end
    -- D-015: only "a profession was given up" (R<id>); no privacy withdrawals.
    -- GF-010 (spec v2.0 §5.2, §11): a group defined with tomb = true may be withdrawn.
    if type(g) ~= "string" or not (g:match("^R%d+$") or (Share.GROUPS[g] and Share.GROUPS[g].tomb)) then return false end
    if t > Share.serverNow() + Share.FUTURE or t < Share.EPOCH then return false end
    s.tomb[a] = s.tomb[a] or {}
    local old = s.tomb[a][g]
    if old and old >= t then return false end
    s.tomb[a][g] = t
    recordCount = nil
    for rg, r in pairs(s.rec[a] or {}) do
        if (g == "*" or rg == g) and r.t <= t then s.rec[a][rg] = nil end
    end
    if s.rec[a] and not next(s.rec[a]) then s.rec[a] = nil end
    changed(a, false)
    return true
end

---------------------------------------------------------------------------
-- Own records
---------------------------------------------------------------------------

local mayShare -- defined with the sending code below

-- Observe this character now. Returns the list of groups whose value changed.
function Share.observeOwn()
    local a = Share.selfAuthor()
    local s = store()
    if not a or not s then return {} end
    local p = ns.Sync.player()
    local now = Share.serverNow()
    local out = {}
    local function put(g, v)
        if not v then return end
        local h = Share.hash(v)
        local before = s.rec[a] and s.rec[a][g]
        local tomb = tombFor(s, a, g)
        local t = now
        if tomb and tomb >= t then t = tomb + 1 end
        local r = Share.offer(a, g, t, h, v, true, a)
        if r == "new" and not (before and before.h == h) then out[#out + 1] = g end
    end
    put("B", Share.encodeValue("B", { level = p.level, classToken = p.classToken ~= "" and p.classToken or nil }))
    local profs = {}
    for _, prof in ipairs((ns.Data.ownProfessionsDetailed())) do
        profs[#profs + 1] = { skillLineID = prof.skillLineID, rank = prof.rank, max = prof.max }
    end
    put("P", Share.encodeValue("P", profs))
    if ns.Sync.shareLocation() then
        local loc = ns.Data.location()
        if loc then put("Z", Share.encodeValue("Z", loc)) end
    end
    -- GF-010: defined groups with an own() value (nil = not shared). A
    -- withdrawable group that is no longer shared gets a tombstone.
    for g, def in pairs(Share.GROUPS) do
        if type(def.own) == "function" then
            local v = def.own()
            if v then
                put(g, v)
            elseif def.tomb and s.rec[a] and s.rec[a][g] then
                Share.applyTomb(a, g, now)
                out[#out + 1] = g
            end
        end
    end
    -- A profession given up: withdraw its recipes (only when the list is known).
    if #profs > 0 then
        local have = {}
        for _, prof in ipairs(profs) do if prof.skillLineID then have[prof.skillLineID] = true end end
        for g in pairs(s.rec[a] or {}) do
            local id = tonumber(g:match("^R(%d+)$"))
            if id and not have[id] then
                Share.applyTomb(a, g, now)
                out[#out + 1] = g
            end
        end
    end
    return out
end

-- Store one of our own records (recipes, phase 2). Returns "stored" when the
-- value changed (it goes out after Share.CHANGE_DELAY), "same" when only the
-- time moved forward, or another Share.offer result.
local recipeTimers = {}
function Share.ownRecord(g, v)
    local a = Share.selfAuthor()
    if not a or not v or not store() then return "unknown" end
    local s = store()
    local before = s.rec[a] and s.rec[a][g]
    local t = Share.serverNow()
    local tomb = tombFor(s, a, g)
    if tomb and tomb >= t then t = tomb + 1 end
    if before and before.t >= t then t = before.t + 1 end
    local h = Share.hash(v)
    local r = Share.offer(a, g, t, h, v, true, a)
    if r == "confirm" then return "same" end
    if r ~= "new" then return r end
    if before and before.h == h then return "same" end
    if mayShare() and not recipeTimers[g] then
        recipeTimers[g] = true
        ns.after(Share.CHANGE_DELAY, function()
            recipeTimers[g] = nil
            Share.sendRecord(a, g, true)
        end)
    end
    return "stored"
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local queue = {}       -- { msg, at, kind, to = { a, name } or nil }
local allowance = Share.ALLOWANCE
local lastTick
local draining = false
local lastSent = {}    -- ["a|g"] = time a record went out (by anyone)
local pending = {}     -- [key] = true while a delayed reply is waiting
local capable = {}     -- [author] = time their last request carried Share.MARK
local lastHeard = {}   -- [author] = time we last heard anything from them
local claimed = {}     -- ["to|a|g"] = time someone claimed (or we sent) that reply
local gone = {}        -- [author] = time "player not found" came for them
local recentWhisper = {} -- [lower full name] = { at, a }

local function canSend()
    if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
    if ns.inCombat() then return false end
    -- GuildForge (Forever): AreOutgoingAddonChatMessagesRestricted() is true
    -- nearly all the time while messages still go out; only trust it in
    -- instances (combat is already handled above).
    if ns.call(IsInInstance) == true and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
        if ns.call(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == true then return false end
    end
    return true
end

-- GF-006-B: the order and price ledgers (Ledger.lua) use the same rules.
Share.canSend = canSend

local function throttledCode(r)
    if r == false then return true end
    if type(r) ~= "number" or r == 0 then return false end
    local codes = Enum and Enum.SendAddonMessageResult
    return r == 3 or r == 8 or (codes and (r == codes.AddonMessageThrottle or r == codes.ChannelThrottle)) or false
end

Share.isThrottled = throttledCode

-- GF-006-B2 (review 1-3): a ledger whispered name: hide its "No player named
-- X" line like ours, and drop the ledgers' queues when it comes.
function Share.noteWhisper(name)
    local m = ns.Comm.memberFor(name)
    local a = m and Share.authorOf(m.guid)
    recentWhisper[ns.keyName(name)] = { at = ns.now(), a = a, name = name }
end

local drain
local function schedule(delay)
    if draining then return end
    draining = true
    ns.after(delay or 0.5, function() draining = false; drain() end)
end

drain = function()
    local now = ns.now()
    if lastTick then allowance = math.min(Share.ALLOWANCE, allowance + (now - lastTick) * Share.REFILL) end
    lastTick = now
    for i = #queue, 1, -1 do
        local item = queue[i]
        local stale = item.kind == "data" and now - item.at > Share.STALE
        -- Whisper only someone who asked just now and is still online.
        local unwanted = item.to and (gone[item.to.a]
            or now - (lastHeard[item.to.a] or 0) > Share.TARGET_FRESH)
        if stale or unwanted then table.remove(queue, i); stats.dropped = stats.dropped + 1 end
    end
    if #queue == 0 then return end
    if canSend() then
        while #queue > 0 and allowance >= 1 do
            local item = queue[1]
            local r
            if item.to then
                r = ns.call(C_ChatInfo.SendAddonMessage, Share.PREFIX, item.msg, "WHISPER", item.to.name)
            else
                r = ns.call(C_ChatInfo.SendAddonMessage, Share.PREFIX, item.msg, "GUILD")
            end
            if throttledCode(r) then
                allowance = 0; stats.throttled = stats.throttled + 1
                break
            end
            table.remove(queue, 1)
            allowance = allowance - 1
            stats.sent = stats.sent + 1
            if item.to then
                stats.whispered = stats.whispered + 1
                recentWhisper[ns.keyName(item.to.name)] = { at = now, a = item.to.a }
            end
        end
    end
    if #queue > 0 then schedule(1) end
end

function Share.queued() return #queue end

local function queuedFor(a)
    local n = 0
    for _, item in ipairs(queue) do if item.to and item.to.a == a then n = n + 1 end end
    return n
end
Share.queuedFor = queuedFor

-- to = { a = author, name = "Name-Realm" } sends by WHISPER; nil by GUILD.
local function enqueue(msg, kind, to)
    if #msg > Share.MAX_BYTES then return false end
    -- Replies must never pile up: drop them beyond the caps (own changes,
    -- requests and summaries always go in; they are few).
    if to and (#queue >= Share.MAX_QUEUE or queuedFor(to.a) >= Share.MAX_PER_TARGET) then
        stats.dropped = stats.dropped + 1
        return false
    end
    queue[#queue + 1] = { msg = msg, at = ns.now(), kind = kind or "data", to = to }
    schedule(0)
    return true
end
Share.enqueue = enqueue

local function msg(...) return Share.VERSION .. "~" .. table.concat({ ... }, "~") end

-- Pack items into as few messages as fit: header .. item ~ item ~ ...
local function packed(header, items, kind)
    local chunk
    for _, item in ipairs(items) do
        if chunk and #chunk + 1 + #item <= Share.MAX_BYTES then
            chunk = chunk .. "~" .. item
        else
            if chunk then enqueue(chunk, kind) end
            chunk = header .. "~" .. item
        end
    end
    if chunk then enqueue(chunk, kind) end
end

-- Split s into pieces of at most n bytes without cutting a UTF-8 character.
local function splitBytes(s, n)
    local out, i = {}, 1
    while i <= #s do
        local j = math.min(#s, i + n - 1)
        while j < #s and j > i do
            local b = s:byte(j + 1)
            if b < 0x80 or b >= 0xC0 then break end
            j = j - 1
        end
        out[#out + 1] = s:sub(i, j)
        i = j + 1
    end
    return out
end

local function recordKey(a, g) return a .. "|" .. g end

mayShare = function() return ns.Sync.isEnabled() and ns.guildState() == "target" end

-- Send one record (value or tombstone) unless it went out recently. With
-- to, it goes by WHISPER to that member only (the caller sent the claim).
function Share.sendRecord(a, g, force, to)
    if not mayShare() then return false end
    local s = store()
    if not s then return false end
    local key = to and (to.a .. "|" .. recordKey(a, g)) or recordKey(a, g)
    local now = ns.now()
    if not force and lastSent[key] and now - lastSent[key] < Share.RESEND then return false end
    local rec = s.rec[a] and s.rec[a][g]
    if not rec then
        local tomb = s.tomb[a] and s.tomb[a][g]
        if not tomb then return false end
        lastSent[key] = now
        return enqueue(msg("X", a, g, Share.b36(tomb)), "data", to)
    end
    lastSent[key] = now
    local t = Share.b36(rec.t)
    local single = msg("V", a, g, t, rec.h, rec.v)
    if a ~= Share.selfAuthor() then stats.relayed = stats.relayed + 1 end
    if #single <= Share.MAX_BYTES then return enqueue(single, "data", to) end
    local head = #msg("D", a, g, t, "zz", "")
    local parts = splitBytes(rec.v, Share.MAX_BYTES - head)
    enqueue(msg("B", a, g, t, rec.h, Share.b36(#parts)), "data", to)
    for i, piece in ipairs(parts) do enqueue(msg("D", a, g, t, Share.b36(i), piece), "data", to) end
    return true
end

function Share.indexItems(a)
    local s = store()
    local items = {}
    if not s then return items end
    for g, r in pairs(s.rec[a] or {}) do items[#items + 1] = g .. "." .. Share.b36(r.t) .. "." .. r.h end
    for g, t in pairs(s.tomb[a] or {}) do items[#items + 1] = g .. "." .. Share.b36(t) .. ".x" end
    table.sort(items)
    return items
end

function Share.sendIndex(a)
    if not mayShare() then return false end
    local items = Share.indexItems(a)
    if #items == 0 then return false end
    packed(msg("I", a, Share.b36(#items), Share.MARK), items, "index")
    return true
end

-- A reply after a random delay, cancelled if someone else answers first.
local function later(key, minDelay, maxDelay, fn)
    if pending[key] then return end
    pending[key] = true
    ns.after(Share.rand(minDelay, maxDelay), function()
        if pending[key] == "cancel" then pending[key] = nil; return end
        pending[key] = nil
        fn()
    end)
end
local function cancel(key) if pending[key] then pending[key] = "cancel" end end
Share.pendingReplies = pending

-- The member to whisper a reply to, or nil (an older client: GUILD as before).
-- Their roster name is the full "Name-Realm" form the server addresses.
local function targetFor(senderA)
    local at = capable[senderA]
    if not at or ns.now() - at > Share.CAPABLE_KEEP or gone[senderA] then return nil end
    local m = Share.memberFor(senderA)
    if not m or str(m.name) == "" then return nil end
    return { a = senderA, name = m.name }
end
Share.targetFor = targetFor

-- Send records to one member: drop what someone already claimed or sent,
-- claim the rest on GUILD (one short K), then whisper them.
local function answer(to, items)
    if not mayShare() then return end
    local now = ns.now()
    local send = {}
    for _, it in ipairs(items) do
        local key = to.a .. "|" .. recordKey(it.a, it.g)
        local claimAt = claimed[key]
        local heardOnGuild = lastSent[recordKey(it.a, it.g)]
        local fresh = (claimAt and now - claimAt < Share.RESEND)
            or (heardOnGuild and now - heardOnGuild < Share.RESEND and it.a ~= Share.selfAuthor())
        if not fresh and (Share.get(it.a, it.g) or (store().tomb[it.a] or {})[it.g]) then
            send[#send + 1] = it
            claimed[key] = now
        end
    end
    if #send == 0 then return end
    local list = {}
    for _, it in ipairs(send) do list[#list + 1] = it.a .. "." .. it.g end
    packed(msg("K", to.a), list, "claim")
    for _, it in ipairs(send) do Share.sendRecord(it.a, it.g, true, to) end
end
Share.answer = answer

-- Pushes to one member are gathered for a moment and answered together.
local pushes = {} -- [to.a] = { to, items, seen }
local function pushTo(to, a, g)
    local job = pushes[to.a]
    if not job then
        job = { to = to, items = {}, seen = {} }
        pushes[to.a] = job
        later("pushto|" .. to.a, 2, 6, function()
            pushes[to.a] = nil
            answer(job.to, job.items)
        end)
    end
    local key = recordKey(a, g)
    if not job.seen[key] then
        job.seen[key] = true
        job.items[#job.items + 1] = { a = a, g = g }
    end
end

-- A newer copy goes to whoever showed an older one: by WHISPER to a 0.9.2+
-- member, else on GUILD as before (cancelled when someone else sends it).
local function push(to, a, g)
    if not mayShare() then return end
    if to then pushTo(to, a, g)
    else later("push|" .. recordKey(a, g), 2, 6, function() Share.sendRecord(a, g) end) end
end

---------------------------------------------------------------------------
-- Login and changes
---------------------------------------------------------------------------

local qid
local catalogParts = {}
local asks = { index = 0, records = 0 }
local wantIndex, wantRecords = {}, {}

-- Catch-up order (GF-001-D14, EVAL-1000 §3.4): members online now first,
-- then the most recently changed, then the rest of the roster. wants maps
-- key -> { a = author, t = newest time we know they have }.
local function byPriority(wants)
    local list = {}
    for k, w in pairs(wants) do
        local m = Share.memberFor(w.a)
        list[#list + 1] = { k = k, online = m and m.online == true or false, t = w.t or 0 }
    end
    table.sort(list, function(x, y)
        if x.online ~= y.online then return x.online end
        if x.t ~= y.t then return x.t > y.t end
        return x.k < y.k
    end)
    return list
end
Share.byPriority = byPriority

local flushPending = false
local flushSoon
-- One round of requests: a few A and G messages, most important first. What
-- is left waits Share.ASK_EVERY seconds, so a big catch-up is spread out;
-- beyond the per-login caps it waits for the next login (or the next Q/C).
local function flushWants()
    local list = {}
    local roundA = Share.ASK_A_PER_ROUND * 15
    for _, it in ipairs(byPriority(wantIndex)) do
        if asks.index >= Share.maxIndexAsks() then wantIndex[it.k] = nil
        elseif #list < roundA then
            list[#list + 1] = it.k; asks.index = asks.index + 1; wantIndex[it.k] = nil
        end
    end
    for i = 1, #list, 15 do
        local chunk = {}
        for j = i, math.min(#list, i + 14) do chunk[#chunk + 1] = list[j] end
        chunk[#chunk + 1] = Share.MARK
        enqueue(msg("A", unpack(chunk)), "ask")
    end
    local recs = {}
    local roundG = Share.ASK_G_PER_ROUND * 8
    for _, it in ipairs(byPriority(wantRecords)) do
        if asks.records >= Share.maxRecordAsks() then wantRecords[it.k] = nil
        elseif #recs < roundG then
            recs[#recs + 1] = it.k; asks.records = asks.records + 1; wantRecords[it.k] = nil
        end
    end
    for i = 1, #recs, 8 do
        local chunk = {}
        for j = i, math.min(#recs, i + 7) do chunk[#chunk + 1] = recs[j] end
        chunk[#chunk + 1] = Share.MARK
        enqueue(msg("G", unpack(chunk)), "ask")
    end
    if next(wantIndex) or next(wantRecords) then flushSoon(Share.ASK_EVERY) end
end
flushSoon = function(delay)
    if flushPending then return end
    flushPending = true
    ns.after(delay or 1, function() flushPending = false; flushWants() end)
end
function Share.waiting()
    local n = 0
    for _ in pairs(wantIndex) do n = n + 1 end
    for _ in pairs(wantRecords) do n = n + 1 end
    return n
end

function Share.login()
    if ns.guildState() ~= "target" then return false end
    if not ns.Roster.current() then return false end
    Share.prune()
    asks.index, asks.records = 0, 0
    if mayShare() then
        Share.observeOwn()
        Share.sendIndex(Share.selfAuthor())
    end
    local count, digest = Share.totalDigest()
    qid = Share.b36(math.floor(Share.rand(0, 1679615)))
    catalogParts = {}
    enqueue(msg("Q", qid, Share.b36(count), digest, "b" .. Share.bucketDigests(), Share.MARK), "ask")
    return true
end

local changeTimer = false
local lastZoneAt
function Share.ownChanged(zoneOnly)
    if not mayShare() then return end
    if zoneOnly then
        if lastZoneAt and ns.now() - lastZoneAt < Share.ZONE_EVERY then return end
        lastZoneAt = ns.now()
    end
    if changeTimer then return end
    changeTimer = true
    ns.after(zoneOnly and 1 or Share.CHANGE_DELAY, function()
        changeTimer = false
        if not mayShare() then return end
        local a = Share.selfAuthor()
        for _, g in ipairs(Share.observeOwn()) do Share.sendRecord(a, g, true) end
    end)
end

-- Drop everything about author a (records, tombstones, upload state).
function Share.forget(s, a)
    s.rec[a], s.tomb[a], s.gone[a], s.queued[a], s.idsSent[a] = nil, nil, nil, nil, nil
    digestCache[a] = nil
    Share.version = Share.version + 1
    local prefix = a .. "|"
    for k in pairs(s.named) do
        if k:sub(1, #prefix) == prefix then s.named[k] = nil end
    end
    recordCount = nil
end

-- Storage full (GF-001-D14, design §5): forget the author not on the roster
-- whose records were heard least recently. Returns false when everyone
-- stored is on the roster (then the new record is not kept).
function Share.evict(s)
    local byA = rosterIndex()
    local pick, pickAt
    for a, groups in pairs(s.rec) do
        if not (byA and byA[a]) then
            local newest = 0
            for _, r in pairs(groups) do
                if (r.heardAt or 0) > newest then newest = r.heardAt or 0 end
            end
            if not pickAt or newest < pickAt then pick, pickAt = a, newest end
        end
    end
    if not pick then return false end
    Share.forget(s, pick)
    stats.evicted = stats.evicted + 1
    countRecords(s)
    return true
end

-- Old records: authors gone from the roster for 14 days; old tombstones.
function Share.prune()
    recordCount = nil
    digestCache = {}
    Share.version = Share.version + 1
    local s = store()
    local byA = rosterIndex()
    if not s or not byA then return end
    local now = ns.now()
    for _, a in ipairs(Share.authors()) do
        if byA[a] then
            s.gone[a] = nil
        else
            s.gone[a] = s.gone[a] or now
            if now - s.gone[a] >= Share.GONE_KEEP then Share.forget(s, a) end
        end
    end
    local serverNow = Share.serverNow()
    for a, groups in pairs(s.tomb) do
        for g, t in pairs(groups) do
            if serverNow - t > Share.TOMB_KEEP then groups[g] = nil end
        end
        if not next(groups) then s.tomb[a] = nil end
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local partials = {}

-- Compare one index item with ours; queue asks or pushes.
local function compareItem(a, g, t, h, to)
    local s = store()
    if h == "x" then Share.applyTomb(a, g, t); return end
    if not validGroup(g) then return end
    local tomb = tombFor(s, a, g)
    local rec = s.rec[a] and s.rec[a][g]
    if tomb and tomb >= t then
        push(to, a, g)
        return
    end
    if not rec or rec.t < t then
        if rec and rec.h == h then
            Share.offer(a, g, t, h, nil, false, nil)
        else
            wantRecords[a .. "." .. g .. "." .. Share.b36(t)] = { a = a, t = t }
            flushSoon()
        end
    elseif rec.t > t then
        push(to, a, g)
    end
end

-- An index may span several messages: n is the total number of items.
local indexParts = {} -- ["sender|a"] = { listed = {}, count, n, at }

local function handleIndex(senderA, a, n, items, to)
    local key = senderA .. "|" .. a
    local now = ns.now()
    local acc = indexParts[key]
    if not acc or now - acc.at > Share.PART_TIMEOUT or acc.count >= acc.n then
        acc = { listed = {}, count = 0, n = n, at = now }
        indexParts[key] = acc
    end
    for _, item in ipairs(items) do
        local g, t, h = item:match("^([^%.]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
        t = t and Share.unb36(t)
        if g and t then
            if not acc.listed[g] then acc.count = acc.count + 1 end
            acc.listed[g] = true
            compareItem(a, g, t, h, to)
        end
    end
    if acc.count < acc.n then return end
    indexParts[key] = nil
    local listed = acc.listed
    -- Whole index in: anything we hold for a that they did not list, they lack.
    if mayShare() then
        for _, item in ipairs(Share.indexItems(a)) do
            local g = item:match("^([^%.]+)")
            if not listed[g] then push(to, a, g) end
        end
    end
    -- Someone answered for a; same digest as ours means our reply is not needed.
    cancel("index|" .. a)
end

local function handleCatalog(fields)
    local q, part, total = fields[1], Share.unb36(fields[2]), Share.unb36(fields[3])
    cancel("catalog|" .. str(q))
    if q ~= qid or not part or not total then return end
    catalogParts[part] = true
    local seen = catalogParts.seen or {}
    catalogParts.seen = seen
    -- A bucketed reply (0.10) lists only some buckets: k<mask>.
    local first = 4
    local mask = fields[4] and fields[4]:match("^k([0-9a-z]+)$")
    if mask and #mask % 2 == 0 then
        catalogParts.mask = mask
        first = 5
    end
    for i = first, #fields do
        local a, d, m = fields[i]:match("^([^%.]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
        m = m and Share.unb36(m)
        if a and m then
            seen[a] = true
            local mine, myMax = Share.digest(a)
            if mine ~= d then
                if myMax > m and mayShare() then
                    later("index|" .. a, 2, 6, function() Share.sendIndex(a) end)
                else
                    wantIndex[a] = { a = a, t = m }
                end
            end
        end
    end
    flushSoon()
    for i = 1, total do if not catalogParts[i] then return end end
    -- Whole catalog in: authors only we know about go out as indexes (only
    -- in the buckets the reply covered).
    local covered = catalogParts.mask
    if mayShare() then
        for _, a in ipairs(Share.authors()) do
            if not seen[a] and (not covered or Share.inMask(covered, Share.bucketOf(a))) then
                later("index|" .. a, 2, 6, function() Share.sendIndex(a) end)
            end
        end
    end
    qid = nil
end

-- buckets: set of buckets to answer, or nil for the whole catalog.
local function sendCatalog(q, buckets)
    local items = {}
    for _, a in ipairs(Share.authors()) do
        if not buckets or buckets[Share.bucketOf(a)] then
            local d, m = Share.digest(a)
            items[#items + 1] = a .. "." .. d .. "." .. Share.b36(m)
        end
    end
    local mask = buckets and ("k" .. Share.maskOf(buckets)) or nil
    -- Count parts first so each carries "part~parts" (and the mask).
    local header = #msg("C", q, "zz", "zz") + (mask and #mask + 1 or 0)
    local groups, cur, len = {}, {}, header
    for _, item in ipairs(items) do
        if #cur > 0 and len + 1 + #item > Share.MAX_BYTES then
            groups[#groups + 1] = cur; cur, len = {}, header
        end
        cur[#cur + 1] = item; len = len + 1 + #item
    end
    if #cur > 0 or (mask and #groups == 0) then groups[#groups + 1] = cur end
    for i, list in ipairs(groups) do
        if mask then
            enqueue(msg("C", q, Share.b36(i), Share.b36(#groups), mask, unpack(list)), "index")
        else
            enqueue(msg("C", q, Share.b36(i), Share.b36(#groups), unpack(list)), "index")
        end
    end
end

local function onValue(senderA, a, g, t, h, v, channel)
    local rec = Share.get(a, g)
    if channel == "GUILD" then
        -- Everyone heard it: our GUILD reply is not needed, and nobody needs a whisper of it.
        cancel("push|" .. recordKey(a, g))
        cancel("give|" .. recordKey(a, g))
        if rec and rec.t <= t then lastSent[recordKey(a, g)] = ns.now() end
    end
    local r = Share.offer(a, g, t, h, v, senderA == a, senderA)
    if r == "new" or r == "confirm" then stats.received = stats.received + 1 end
    if r == "older" then push(targetFor(senderA), a, g) end
    return r
end

local function item1(items) return items[1].a .. "." .. items[1].g .. "." .. #items end

-- Returns a result string (for tests and diagnostics).
function Share.onMessage(prefix, text, channel, sender)
    if prefix ~= Share.PREFIX then return "prefix" end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return "channel" end
    if ns.guildState() ~= "target" then return "other-guild" end
    local senderM = ns.Comm.memberFor(sender)
    if not senderM then return "not-in-roster" end
    local senderA = Share.authorOf(senderM.guid)
    if not senderA then return "not-in-roster" end
    if senderA == Share.selfAuthor() then return "self" end
    local fields = {}
    for f in (str(text) .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = f end
    if fields[1] ~= Share.VERSION then return "version" end
    local kind = fields[2]
    table.remove(fields, 1); table.remove(fields, 1)
    local byA = rosterIndex()
    local function known(a) return a and byA and byA[a] ~= nil end
    lastHeard[senderA] = ns.now()
    gone[senderA] = nil
    -- Only data comes by WHISPER (replies to our own requests).
    if channel == "WHISPER" and kind ~= "V" and kind ~= "B" and kind ~= "D" and kind ~= "X" then
        return "channel"
    end
    -- Requests from 0.9.2+ end with the mark; an index carries it right after
    -- its item count (each part of a long index starts with that header).
    -- Marked senders get their data by WHISPER.
    if kind == "I" and fields[3] == Share.MARK then
        table.remove(fields, 3)
        capable[senderA] = ns.now()
    elseif (kind == "Q" or kind == "A" or kind == "G") and fields[#fields] == Share.MARK then
        table.remove(fields)
        capable[senderA] = ns.now()
    end

    if kind == "I" then
        local a = fields[1]
        if not known(a) then return "unknown-author" end
        local n = Share.unb36(fields[2])
        if not n then return "malformed" end
        handleIndex(senderA, a, n, { unpack(fields, 3) }, targetFor(senderA))
        return "ok"
    elseif kind == "Q" then
        local q, count, digest = fields[1], Share.unb36(fields[2]), fields[3]
        if not q or not count then return "malformed" end
        if not mayShare() then return "disabled" end
        local myCount, myDigest = Share.totalDigest()
        if myCount == 0 or (myCount == count and myDigest == digest) then return "same" end
        -- 0.10 requesters send bucket digests: answer only what differs.
        local theirs = fields[4] and fields[4]:match("^b([0-9a-z]+)$")
        local buckets = theirs and Share.differingBuckets(theirs) or nil
        later("catalog|" .. q, 2, 8, function() sendCatalog(q, buckets) end)
        return "ok"
    elseif kind == "C" then
        handleCatalog(fields)
        return "ok"
    elseif kind == "A" then
        if not mayShare() then return "disabled" end
        for _, a in ipairs(fields) do
            if known(a) and #Share.indexItems(a) > 0 then
                local mine = a == Share.selfAuthor()
                later("index|" .. a, mine and 0 or 2, mine and 1 or 6, function() Share.sendIndex(a) end)
            end
        end
        return "ok"
    elseif kind == "G" then
        if not mayShare() then return "disabled" end
        local to = targetFor(senderA)
        local own, others = {}, {}
        for _, item in ipairs(fields) do
            local a, g, t = item:match("^([^%.]+)%.([^%.]+)%.([0-9a-z]+)$")
            t = t and Share.unb36(t)
            local rec = a and Share.get(a, g)
            if rec and t and rec.t >= t and known(a) then
                local mine = a == Share.selfAuthor()
                if to then
                    table.insert(mine and own or others, { a = a, g = g })
                else
                    later("give|" .. recordKey(a, g), mine and 0 or 2, mine and 1 or 6,
                        function() Share.sendRecord(a, g) end)
                end
            end
        end
        -- The author answers about themselves first; other holders wait and
        -- skip what a claim (K) already covered.
        if #own > 0 then later("own|" .. senderA .. "|" .. item1(own), 0, 1, function() answer(to, own) end) end
        if #others > 0 then later("give|" .. senderA .. "|" .. item1(others), 2, 6, function() answer(to, others) end) end
        return "ok"
    elseif kind == "K" then
        local toA = fields[1]
        if not toA then return "malformed" end
        local now = ns.now()
        for i = 2, #fields do
            local a, g = fields[i]:match("^([^%.]+)%.(.+)$")
            if a then claimed[toA .. "|" .. recordKey(a, g)] = now end
        end
        return "claim"
    elseif kind == "V" then
        local a, g, t, h, v = fields[1], fields[2], Share.unb36(fields[3]), fields[4], table.concat(fields, "~", 5)
        if not known(a) then return "unknown-author" end
        if not t then return "malformed" end
        return onValue(senderA, a, g, t, h, v, channel)
    elseif kind == "B" then
        local a, g, t, h, n = fields[1], fields[2], Share.unb36(fields[3]), fields[4], Share.unb36(fields[5])
        if not known(a) or not t or not n or n < 1 or n > 64 then return "malformed" end
        local key = senderA .. "|" .. a .. "|" .. g .. "|" .. fields[3]
        partials[key] = { h = h, n = n, parts = {}, at = ns.now(), channel = channel }
        if channel == "GUILD" then
            cancel("give|" .. recordKey(a, g))
            cancel("push|" .. recordKey(a, g))
        end
        return "partial"
    elseif kind == "D" then
        local a, g, tRaw, part = fields[1], fields[2], fields[3], Share.unb36(fields[4])
        local key = senderA .. "|" .. str(a) .. "|" .. str(g) .. "|" .. str(tRaw)
        local p = partials[key]
        if not p or not part or part < 1 or part > p.n then return "malformed" end
        local now = ns.now()
        for k, other in pairs(partials) do
            if now - other.at > Share.PART_TIMEOUT then partials[k] = nil end
        end
        if not partials[key] then return "timeout" end
        p.parts[part] = table.concat(fields, "~", 5)
        for i = 1, p.n do if not p.parts[i] then return "partial" end end
        partials[key] = nil
        return onValue(senderA, a, g, Share.unb36(tRaw), p.h, table.concat(p.parts), p.channel)
    elseif kind == "X" then
        local a, g, t = fields[1], fields[2], Share.unb36(fields[3])
        if not known(a) or not t then return "malformed" end
        if channel == "GUILD" then cancel("push|" .. recordKey(a, g)) end
        return Share.applyTomb(a, g, t) and "tomb" or "same"
    end
    return "unknown-type"
end

---------------------------------------------------------------------------
-- Old GFTK messages (Comm.lua, 0.8.x): the sender is the author.
---------------------------------------------------------------------------

-- d: decoded GFTK body. Returns true when any record was stored or confirmed.
function Share.fromV1(member, d)
    local a = member and member.guid and Share.authorOf(member.guid)
    if not a or type(d.capturedAt) ~= "number" then return false, "invalid" end
    local any, why = false, "older"
    local function try(g, v)
        if not v then return end
        local r = Share.offer(a, g, d.capturedAt, Share.hash(v), v, true, a)
        if r == "new" or r == "confirm" then any = true elseif r == "future" then why = "future" end
    end
    try("B", d.level and Share.encodeValue("B", d) or nil)
    try("P", d.professions and Share.encodeValue("P", d.professions) or nil)
    try("Z", d.location and Share.encodeValue("Z", d.location) or nil)
    return any, any and nil or why
end

---------------------------------------------------------------------------
-- A whispered member went offline (D12): the client prints "No player named
-- X is currently playing." Hide that line only for names we whispered in the
-- last Share.GONE_HIDE seconds, and drop whatever we still had queued for them.
---------------------------------------------------------------------------

local notFoundPattern
local function notFound()
    if notFoundPattern then return notFoundPattern end
    local fmt = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S
        or "No player named '%s' is currently playing."
    local i, j = fmt:find("%s", 1, true)
    if not i then return nil end
    local function lit(x) return (x:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    notFoundPattern = "^" .. lit(fmt:sub(1, i - 1)) .. "(.+)" .. lit(fmt:sub(j + 1)) .. "$"
    return notFoundPattern
end

-- The recent whisper target a name from the system line refers to, or nil.
local function whisperedTarget(name)
    local n = ns.keyName(name)
    local now = ns.now()
    for full, w in pairs(recentWhisper) do
        if now - w.at > Share.GONE_HIDE then
            recentWhisper[full] = nil
        elseif full == n or full:sub(1, #n + 1) == n .. "-" or n:sub(1, #full + 1) == full .. "-" then
            return full, w
        end
    end
    return nil
end

function Share.targetGone(a, name)
    gone[a or ""] = ns.now()
    if name and ns.Ledger then
        for _, l in ipairs(ns.Ledger.list) do l:dropTarget(name) end
    end
    for i = #queue, 1, -1 do
        if queue[i].to and queue[i].to.a == a then table.remove(queue, i); stats.dropped = stats.dropped + 1 end
    end
end

-- ChatFrame message filter: true hides the line.
function Share.systemFilter(_, _, text, ...)
    local pattern = notFound()
    local name = pattern and type(text) == "string" and text:match(pattern)
    if not name then return false, text, ... end
    local full, w = whisperedTarget(name)
    if not full then return false, text, ... end
    recentWhisper[full] = nil
    Share.targetGone(w.a, w.name or full)
    return true
end

function Share.register()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        ns.call(C_ChatInfo.RegisterAddonMessagePrefix, Share.PREFIX)
    end
    -- FA relocated.md: ChatFrame_AddMessageEventFilter is a Blizzard_Deprecated
    -- shim on Forever; ChatFrameUtil.AddMessageEventFilter is the current name.
    if not Share.filterAdded then
        local add = (type(ChatFrameUtil) == "table" and type(ChatFrameUtil.AddMessageEventFilter) == "function"
            and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
        if type(add) == "function" then
            ns.call(add, "CHAT_MSG_SYSTEM", Share.systemFilter)
            Share.filterAdded = true
        end
    end
end

-- Tests: forget session state (queue, timers' bookkeeping, partials).
function Share.resetSession()
    queue, partials, lastSent, indexParts = {}, {}, {}, {}
    capable, lastHeard, claimed, gone, recentWhisper, pushes = {}, {}, {}, {}, {}, {}
    recordCount, indexFor, indexByA, decodedCache = nil, nil, nil, {}
    digestCache, totalsCache = {}, {}
    for k in pairs(pending) do pending[k] = nil end
    allowance, lastTick, draining = Share.ALLOWANCE, nil, false
    qid, catalogParts, wantIndex, wantRecords = nil, {}, {}, {}
    changeTimer, lastZoneAt, flushPending = false, nil, false
    for k in pairs(stats) do stats[k] = 0 end
end
