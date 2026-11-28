-- Ledger (GF-006-B, spec R-5.5, R-5.6, R-8.6): a small replicated record
-- store on its own addon message prefix. Orders (GFTKO) and shared prices
-- (GFTKP) each use one. Same rules as Share.lua (D-014): a record is keyed by
-- (author, group), carries t (the author's server time) and h (a hash of the
-- value); newest t wins, anyone may relay, the author and t never change.
--
-- Why a separate prefix and not new Share groups (design GF-006-A §4c, §6f):
-- 0.10.0 computes its catalog digests over every record of an author, so new
-- groups inside GFTKS would make old and new clients disagree forever. A
-- client that never registered the prefix never gets these messages, and
-- Comm/Share drop any other prefix, so 0.10.0 cannot fail on them.
--
-- Wire ("L1~<type>~...", <= 250 bytes, numbers base 36):
--   Q~qid~count~total~b<buckets>    GUILD   what do you hold? (after login)
--   K~to~qid                        GUILD   "I answer <to>'s Q" (one replier)
--   C~qid~part~parts~a.d~...        WHISPER catalog: digest per author (differing buckets)
--   A~a~a~...                       WHISPER please send these authors' indexes
--   I~a~g.t.h~...                   WHISPER index of one author
--   G~a.g.t~...                     WHISPER please send these records
--   V~a~g~t~h~value                 GUILD (own change) or WHISPER (reply)
--   B~a~g~t~h~parts / D~a~g~t~part~chunk   a longer value
--   other types go to cfg.onCustom (orders: reagent lists, R-8.5)
-- Values never contain "~" (each user escapes its own values).

local _, ns = ...
local str = ns.str

local Ledger = {}
ns.Ledger = Ledger

Ledger.VERSION = "L1"
Ledger.MAX_BYTES = 250
Ledger.FUTURE = 600
Ledger.EPOCH = 1700000000
-- Review 1-1: a long value can take minutes at 0.5 messages a second, so the
-- timeout runs from the LAST part received, not from the first.
Ledger.PART_TIMEOUT = 60
Ledger.TARGET_FRESH = 120 -- only whisper someone heard from this recently (as Share)
Ledger.BUCKETS = 64
Ledger.list = {}

local function S() return ns.Share end
local function b36(n) return S().b36(n) end
local function unb36(s) return S().unb36(s) end
local function hash(s) return S().hash(s) end

local function hashNum(s)
    local h = #s % 16777213
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 16777213 end
    return h
end
local function fixed3(s)
    if s == "" then return "000" end
    local v = b36(hashNum(s) % 46656)
    return string.rep("0", 3 - #v) .. v
end
Ledger.hashNum = hashNum

-- GF-FIX-A: Sync.guildKey reuses the last key while the guild is unchanged.
local function guildKey() return ns.Sync.guildKey() end

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
    if #out == 0 then out[1] = "" end
    return out
end
Ledger.splitBytes = splitBytes

local L = {}
L.__index = L

-- cfg: id, prefix, burst, refill (messages/second), maxPerSession,
-- yieldToShare, loginDelay, validAuthor(a), validGroup(g),
-- validValue(a, g, v), onChange(a, g), selfAuthor(), onCustom(kind, fields,
-- senderM, channel, sender), maxRecords, evict(store) .
function Ledger.new(cfg)
    local l = setmetatable({ cfg = cfg }, L)
    l.stats = { sent = 0, received = 0, throttled = 0, dropped = 0, queuedMax = 0, capped = 0 }
    l:resetSession()
    Ledger.list[#Ledger.list + 1] = l
    return l
end

function L:resetSession()
    self.queue, self.partials, self.pending, self.digests = {}, {}, {}, {}
    self.lastHeard = {}
    self.allowance, self.lastTick, self.draining = self.cfg.burst or 4, nil, false
    self.sentThisSession, self.qid, self.version, self.totalsCache = 0, nil, 0, nil
    self.coalesced = {}
    for k in pairs(self.stats or {}) do self.stats[k] = 0 end
end

---------------------------------------------------------------------------
-- Storage: GreenFangToolkitDB.ledger[<id>][<realm|guild>].rec[a][g] = { t, h, v }
---------------------------------------------------------------------------

-- GF-FIX-H: a damaged save (an author's records or one record that is not a
-- table, a field of the wrong type) is checked once per rec table, the first
-- time it is read: the broken entries are dropped, everything else stays.
-- What is stored afterwards went through offer() and is always well formed.
local checked = setmetatable({}, { __mode = "k" })
local function scrub(self, rec)
    checked[rec] = true
    local dropped = false
    for a, groups in pairs(rec) do
        if type(a) ~= "string" or type(groups) ~= "table" then
            rec[a] = nil; dropped = true
        else
            local here = false
            for g, r in pairs(groups) do
                if type(g) ~= "string" or type(r) ~= "table" or type(r.t) ~= "number"
                    or type(r.h) ~= "string" or type(r.v) ~= "string" then
                    groups[g] = nil; here = true
                end
            end
            if here then
                dropped = true
                if next(groups) == nil then rec[a] = nil end -- as drop() does
            end
        end
    end
    if dropped then self.digests, self.totalsCache = {}, nil end
end

-- readOnly: do not create empty tables (reading must not grow the save file).
function L:store(readOnly)
    local db = ns.db
    if not db then return nil end
    local key = guildKey()
    if not key then return nil end
    local g
    if readOnly then
        local mine = type(db.ledger) == "table" and db.ledger[self.cfg.id]
        g = type(mine) == "table" and mine[key]
        if type(g) ~= "table" or type(g.rec) ~= "table" then return nil end
    else
        if type(db.ledger) ~= "table" then db.ledger = {} end
        local mine = db.ledger[self.cfg.id]
        if type(mine) ~= "table" then mine = {}; db.ledger[self.cfg.id] = mine end
        g = mine[key]
        if type(g) ~= "table" then g = {}; mine[key] = g end
        if type(g.rec) ~= "table" then g.rec = {} end
    end
    if not checked[g.rec] then scrub(self, g.rec) end
    return g
end

function L:get(a, g)
    local s = self:store(true)
    return s and s.rec[a] and s.rec[a][g] or nil
end

function L:records(a)
    local s = self:store(true)
    return s and s.rec[a] or {}
end

function L:authors()
    local s = self:store(true)
    local list = {}
    for a in pairs(s and s.rec or {}) do list[#list + 1] = a end
    table.sort(list)
    return list
end

function L:count()
    local s = self:store(true)
    local n = 0
    for _, groups in pairs(s and s.rec or {}) do for _ in pairs(groups) do n = n + 1 end end
    return n
end

local function changed(self, a, g)
    self.digests[a] = nil
    self.totalsCache = nil
    self.version = self.version + 1
    if self.cfg.onChange then pcall(self.cfg.onChange, a, g) end
end

-- Remove one record (pruning). No message: others prune by the same rules.
function L:drop(a, g)
    local s = self:store()
    if not (s and s.rec[a] and s.rec[a][g]) then return end
    s.rec[a][g] = nil
    if next(s.rec[a]) == nil then s.rec[a] = nil end
    changed(self, a, g)
end

-- Offer one record: "new", "confirm", "same", "older", "future", "invalid".
function L:offer(a, g, t, h, v)
    local cfg = self.cfg
    if type(a) ~= "string" or type(g) ~= "string" or type(t) ~= "number" or type(h) ~= "string" then
        return "invalid"
    end
    if (cfg.validAuthor and not cfg.validAuthor(a)) or (cfg.validGroup and not cfg.validGroup(g)) then
        return "invalid"
    end
    if t < Ledger.EPOCH then return "invalid" end
    if t > S().serverNow() + Ledger.FUTURE then return "future" end
    local s = self:store()
    if not s then return "invalid" end
    local rec = s.rec[a] and s.rec[a][g]
    if rec then
        if t < rec.t then
            -- Review 3-3: an older copy of OUR record that differs came from another
            -- computer of ours: let the owner merge it (never silently lost).
            if cfg.mergeSelf and h ~= rec.h and type(v) == "string" and hash(v) == h
                and cfg.selfAuthor and a == cfg.selfAuthor() then
                ns.after(0, function() pcall(cfg.mergeSelf, g, v) end)
            end
            return "older"
        end
        if t == rec.t and h == rec.h then return "same" end
        if t == rec.t and h < rec.h then return "older" end -- same time: larger hash wins (deterministic)
        if h == rec.h then rec.t = t; changed(self, a, g); return "confirm" end
    end
    if type(v) ~= "string" or hash(v) ~= h then return "invalid" end
    if cfg.validValue and not cfg.validValue(a, g, v) then return "invalid" end
    if not rec and cfg.maxRecords and self:count() >= cfg.maxRecords then
        if not (cfg.evict and cfg.evict(self, s)) then return "invalid" end
    end
    s.rec[a] = s.rec[a] or {}
    s.rec[a][g] = { t = t, h = h, v = v }
    changed(self, a, g)
    return "new"
end

-- Store one of our own records and send it on GUILD (coalesced per group).
-- Returns "stored", "same" or an offer result.
function L:put(g, v, author, noSend)
    local a = author or self.cfg.selfAuthor()
    if not a then return "invalid" end
    v = str(v)
    local h = hash(v)
    local rec = self:get(a, g)
    if rec and rec.h == h then return "same" end
    local t = S().serverNow()
    if rec and t <= rec.t then t = rec.t + 1 end
    local r = self:offer(a, g, t, h, v)
    if r ~= "new" then return r end
    if not noSend then self:sendSoon(a, g) end
    return "stored"
end

---------------------------------------------------------------------------
-- Digests
---------------------------------------------------------------------------

function L:digest(a)
    local d = self.digests[a]
    if d then return d end
    local items = {}
    for g, rec in pairs(self:records(a)) do items[#items + 1] = g .. "." .. b36(rec.t) .. "." .. rec.h end
    table.sort(items)
    d = hash(table.concat(items, "~"))
    self.digests[a] = d
    return d
end

function L:bucketOf(a) return hashNum(a) % Ledger.BUCKETS end

function L:totals()
    if self.totalsCache then return self.totalsCache end
    local per, all = {}, {}
    local n = 0
    for _, a in ipairs(self:authors()) do
        local b = self:bucketOf(a)
        per[b] = per[b] or {}
        local d = a .. "." .. self:digest(a)
        per[b][#per[b] + 1] = d
        all[#all + 1] = d
        n = n + 1
    end
    local buckets = {}
    for b = 0, Ledger.BUCKETS - 1 do buckets[#buckets + 1] = fixed3(table.concat(per[b] or {}, "~")) end
    self.totalsCache = { count = n, total = hash(table.concat(all, "~")), buckets = table.concat(buckets) }
    return self.totalsCache
end

function L:differingBuckets(theirs)
    if type(theirs) ~= "string" or #theirs ~= Ledger.BUCKETS * 3 then return nil end
    local mine = self:totals().buckets
    local set = {}
    for b = 0, Ledger.BUCKETS - 1 do
        local i = b * 3 + 1
        if mine:sub(i, i + 2) ~= theirs:sub(i, i + 2) then set[b] = true end
    end
    return set
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function canSend()
    local Share = S()
    if Share.canSend then return Share.canSend() end
    return C_ChatInfo ~= nil and type(C_ChatInfo.SendAddonMessage) == "function" and not ns.inCombat()
end

function L:msg(...) return Ledger.VERSION .. "~" .. table.concat({ ... }, "~") end

-- to = sender name for WHISPER; nil for GUILD. own = an own change or a
-- request (never dropped by the session cap).
function L:enqueue(m, to, own)
    if #m > Ledger.MAX_BYTES then return false end
    local cfg = self.cfg
    if not own and cfg.maxPerSession and self.sentThisSession + #self.queue >= cfg.maxPerSession then
        self.stats.capped = self.stats.capped + 1
        return false
    end
    if #self.queue >= (cfg.maxQueue or 400) then self.stats.dropped = self.stats.dropped + 1; return false end
    self.queue[#self.queue + 1] = { msg = m, to = to, at = ns.now() }
    if #self.queue > self.stats.queuedMax then self.stats.queuedMax = #self.queue end
    self:schedule(0)
    return true
end

function L:schedule(delay)
    if self.draining then return end
    self.draining = true
    ns.after(delay or 0.5, function() self.draining = false; self:drain() end)
end

function L:drain()
    local cfg = self.cfg
    local now = ns.now()
    local burst, refill = cfg.burst or 4, cfg.refill or 0.5
    if self.lastTick then self.allowance = math.min(burst, self.allowance + (now - self.lastTick) * refill) end
    self.lastTick = now
    for i = #self.queue, 1, -1 do
        local item = self.queue[i]
        -- Review 1-3: whisper only someone heard from just now (as Share does).
        local unwanted = item.to and now - (self.lastHeard[ns.keyName(item.to)] or 0) > Ledger.TARGET_FRESH
        if now - item.at > (cfg.stale or 600) or unwanted then
            table.remove(self.queue, i); self.stats.dropped = self.stats.dropped + 1
        end
    end
    if #self.queue == 0 then return end
    local Share = S()
    local yield = cfg.yieldToShare and Share.queued and Share.queued() > 0
    if canSend() and not yield then
        while #self.queue > 0 and self.allowance >= 1 do
            local item = table.remove(self.queue, 1)
            local r
            if item.to then
                r = ns.call(C_ChatInfo.SendAddonMessage, cfg.prefix, item.msg, "WHISPER", item.to)
            else
                r = ns.call(C_ChatInfo.SendAddonMessage, cfg.prefix, item.msg, "GUILD")
            end
            ns.Comm.noteSend(cfg.prefix, r) -- GF-001-D15
            -- Review 1-4: same throttle codes as Share (false, 3, 8, the Enum values).
            local throttled = Share.isThrottled and Share.isThrottled(r) or (r == 3 or r == 8)
            if throttled then
                table.insert(self.queue, 1, item)
                self.allowance = 0
                self.stats.throttled = self.stats.throttled + 1
                break
            end
            self.allowance = self.allowance - 1
            self.stats.sent = self.stats.sent + 1
            self.sentThisSession = self.sentThisSession + 1
            -- Review 1-3: Share hides "No player named X" for names we just whispered.
            if item.to and Share.noteWhisper then Share.noteWhisper(item.to) end
        end
    end
    if #self.queue > 0 then self:schedule(1 / math.max(refill, 0.05)) end
end

function L:queued() return #self.queue end

-- Pack items into as few messages as fit: header ~ item ~ item ...
function L:packed(header, items, to, own)
    local chunk
    for _, it in ipairs(items) do
        if chunk and #chunk + 1 + #it <= Ledger.MAX_BYTES then
            chunk = chunk .. "~" .. it
        else
            if chunk then self:enqueue(chunk, to, own) end
            chunk = header .. "~" .. it
        end
    end
    if chunk then self:enqueue(chunk, to, own) end
end

-- One record as V (or B + D parts).
function L:sendRecord(a, g, to, own)
    local rec = self:get(a, g)
    if not rec then return false end
    local single = self:msg("V", a, g, b36(rec.t), rec.h, rec.v)
    if #single <= Ledger.MAX_BYTES then return self:enqueue(single, to, own) end
    local head = self:msg("D", a, g, b36(rec.t), "zz", "")
    local parts = splitBytes(rec.v, Ledger.MAX_BYTES - #head)
    if #parts > 64 then return false end
    self:enqueue(self:msg("B", a, g, b36(rec.t), rec.h, b36(#parts)), to, own)
    for i, p in ipairs(parts) do self:enqueue(self:msg("D", a, g, b36(rec.t), b36(i), p), to, own) end
    return true
end

-- Own change: wait a moment (several clicks become one message).
function L:sendSoon(a, g)
    local key = a .. "|" .. g
    if self.coalesced[key] then return end
    self.coalesced[key] = true
    ns.after(self.cfg.changeDelay or 2, function()
        self.coalesced[key] = nil
        self:sendRecord(a, g, nil, true)
    end)
end

local function later(self, key, minD, maxD, fn)
    if self.pending[key] then return end
    self.pending[key] = true
    ns.after(S().rand(minD, maxD), function()
        local state = self.pending[key]
        self.pending[key] = nil
        if state ~= "cancel" then fn() end
    end)
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------

function L:announce()
    if ns.guildState() ~= "target" or not ns.Roster.current() then return false end
    local t = self:totals()
    self.qid = b36(math.floor(S().rand(0, 1679615)))
    self:enqueue(self:msg("Q", self.qid, b36(t.count), t.total, "b" .. t.buckets), nil, true)
    return true
end
L.login = L.announce

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

function L:sendCatalog(q, to, buckets)
    local items = {}
    for _, a in ipairs(self:authors()) do
        if not buckets or buckets[self:bucketOf(a)] then items[#items + 1] = a .. "." .. self:digest(a) end
    end
    if #items == 0 then return end
    local groups, chunk = {}, {}
    local size = 0
    for _, it in ipairs(items) do
        if size + #it + 1 > Ledger.MAX_BYTES - 30 and #chunk > 0 then
            groups[#groups + 1] = chunk; chunk = {}; size = 0
        end
        chunk[#chunk + 1] = it
        size = size + #it + 1
    end
    if #chunk > 0 then groups[#groups + 1] = chunk end
    self:enqueue(self:msg("K", to.a, q), nil, true)
    for i, list in ipairs(groups) do
        self:enqueue(self:msg("C", q, b36(i), b36(#groups), unpack(list)), to.name)
    end
end

function L:indexItems(a)
    local items = {}
    for g, rec in pairs(self:records(a)) do items[#items + 1] = g .. "." .. b36(rec.t) .. "." .. rec.h end
    table.sort(items)
    return items
end

local function onValue(self, a, g, t, h, v, channel, senderName)
    local r = self:offer(a, g, t, h, v)
    if r == "new" or r == "confirm" then self.stats.received = self.stats.received + 1 end
    if r == "older" and senderName then self:sendRecord(a, g, senderName) end
    return r
end

-- Returns a result string (tests and diagnostics).
function L:onMessage(prefix, text, channel, sender)
    local cfg = self.cfg
    if prefix ~= cfg.prefix then return "prefix" end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return "channel" end
    if ns.guildState() ~= "target" then return "other-guild" end
    local senderM = ns.Comm.memberFor(sender)
    local senderA = senderM and S().authorOf(senderM.guid)
    if not senderA then return "not-in-roster" end
    if senderA == S().selfAuthor() then return "self" end
    self.lastHeard[ns.keyName(sender)] = ns.now()
    -- Forget long values that stopped arriving (review 1-9).
    for key, p in pairs(self.partials) do
        if ns.now() - p.at > Ledger.PART_TIMEOUT then self.partials[key] = nil end
    end
    local fields = {}
    for f in (str(text) .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = f end
    if fields[1] ~= Ledger.VERSION then return "version" end
    local kind = table.remove(fields, 2)
    table.remove(fields, 1)
    local to = { a = senderA, name = sender }
    if kind == "Q" then
        if channel ~= "GUILD" then return "channel" end
        local q, count, total = fields[1], unb36(fields[2]), fields[3]
        if not q or not count then return "malformed" end
        local mine = self:totals()
        if mine.count == 0 or (mine.count == count and mine.total == total) then return "same" end
        local theirs = fields[4] and fields[4]:match("^b([0-9a-z]+)$")
        local buckets = theirs and self:differingBuckets(theirs) or nil
        later(self, "catalog|" .. senderA .. "|" .. q, 2, 8, function() self:sendCatalog(q, to, buckets) end)
        -- They may hold what we lack: ask back with our own Q later.
        return "ok"
    elseif kind == "K" then
        local toA, q = fields[1], fields[2]
        if toA and q then
            local head = "catalog|" .. toA .. "|"
            for key in pairs(self.pending) do
                if key:sub(1, #head) == head then self.pending[key] = "cancel" end
            end
        end
        return "claim"
    elseif kind == "C" then
        if channel ~= "WHISPER" then return "channel" end
        local want = {}
        for i = 4, #fields do
            local a, d = fields[i]:match("^([^%.]+)%.([0-9a-z]+)$")
            if a and (not cfg.validAuthor or cfg.validAuthor(a)) and self:digest(a) ~= d then want[#want + 1] = a end
        end
        for i = 1, #want, 12 do
            local chunk = {}
            for j = i, math.min(#want, i + 11) do chunk[#chunk + 1] = want[j] end
            self:enqueue(self:msg("A", unpack(chunk)), sender, true)
        end
        return "ok"
    elseif kind == "A" then
        if channel ~= "WHISPER" then return "channel" end
        for _, a in ipairs(fields) do
            local items = self:indexItems(a)
            if #items > 0 then self:packed(self:msg("I", a), items, sender) end
        end
        return "ok"
    elseif kind == "I" then
        if channel ~= "WHISPER" then return "channel" end
        local a = fields[1]
        if not a or (cfg.validAuthor and not cfg.validAuthor(a)) then return "malformed" end
        local asks = {}
        for i = 2, #fields do
            local g, t, h = fields[i]:match("^(.+)%.([0-9a-z]+)%.([0-9a-z]+)$")
            t = t and unb36(t)
            if g and t then
                local rec = self:get(a, g)
                if not rec or rec.t < t or (rec.t == t and rec.h < h) then
                    asks[#asks + 1] = a .. "." .. g .. "." .. b36(t)
                elseif rec.t > t then
                    self:sendRecord(a, g, sender)
                end
            end
        end
        if cfg.priority then
            table.sort(asks, function(x, y)
                local px, py = cfg.priority(x) and 0 or 1, cfg.priority(y) and 0 or 1
                if px ~= py then return px < py end
                return x < y
            end)
        end
        if #asks > 0 then self:packed(self:msg("G"), asks, sender, true) end
        return "ok"
    elseif kind == "G" then
        if channel ~= "WHISPER" then return "channel" end
        for _, it in ipairs(fields) do
            local a, g, t = it:match("^([^%.]+)%.(.+)%.([0-9a-z]+)$")
            t = t and unb36(t)
            local rec = a and self:get(a, g)
            if rec and t and rec.t >= t then self:sendRecord(a, g, sender) end
        end
        return "ok"
    elseif kind == "V" then
        local a, g, t, h = fields[1], fields[2], unb36(fields[3]), fields[4]
        if not (a and g and t and h) then return "malformed" end
        return onValue(self, a, g, t, h, table.concat(fields, "~", 5), channel, channel == "WHISPER" and sender or nil)
    elseif kind == "B" then
        local a, g, t, h, n = fields[1], fields[2], unb36(fields[3]), fields[4], unb36(fields[5])
        if not (a and g and t and h and n) or n < 1 or n > 64 then return "malformed" end
        self.partials[sender .. "|" .. a .. "|" .. g .. "|" .. fields[3]] =
            { h = h, n = n, parts = {}, at = ns.now(), channel = channel }
        return "partial"
    elseif kind == "D" then
        local a, g, tRaw, part = fields[1], fields[2], fields[3], unb36(fields[4])
        local key = sender .. "|" .. str(a) .. "|" .. str(g) .. "|" .. str(tRaw)
        local p = self.partials[key]
        if not p or not part or part < 1 or part > p.n then return "malformed" end
        if ns.now() - p.at > Ledger.PART_TIMEOUT then self.partials[key] = nil; return "timeout" end
        p.at = ns.now() -- review 1-1: from the last part received
        p.parts[part] = table.concat(fields, "~", 5)
        for i = 1, p.n do if not p.parts[i] then return "partial" end end
        self.partials[key] = nil
        return onValue(self, a, g, unb36(tRaw), p.h, table.concat(p.parts), p.channel,
            p.channel == "WHISPER" and sender or nil)
    elseif cfg.onCustom then
        return cfg.onCustom(kind, fields, senderM, channel, sender) or "custom"
    end
    return "unknown-type"
end

-- Review 1-3: a whispered member went offline: drop what is still queued for them.
function L:dropTarget(name)
    local key = ns.keyName(name)
    for i = #self.queue, 1, -1 do
        local item = self.queue[i]
        if item.to and ns.keyName(item.to) == key then
            table.remove(self.queue, i); self.stats.dropped = self.stats.dropped + 1
        end
    end
    self.lastHeard[key] = nil
end

function L:register()
    ns.Comm.registerPrefix(self.cfg.prefix) -- GF-001-D15: the result shows in 同步與診斷
end

-- Route CHAT_MSG_ADDON: true when one of the ledgers took the prefix.
function Ledger.dispatch(prefix, text, channel, sender)
    for _, l in ipairs(Ledger.list) do
        if prefix == l.cfg.prefix then return true, l:onMessage(prefix, text, channel, sender) end
    end
    return false
end

-- Escaping for values: "~" and the separators users pick never appear raw.
local SPECIAL = { [37] = true, [126] = true, [44] = true, [47] = true, [61] = true, [59] = true,
    [124] = true, [58] = true, [42] = true, [43] = true }
function Ledger.esc(v)
    return (str(v):gsub(".", function(c)
        local b = c:byte()
        if b < 32 or b == 127 or SPECIAL[b] then return string.format("%%%02X", b) end
        return c
    end))
end
function Ledger.unesc(v)
    return (str(v):gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end))
end
