-- Bank (GF-012 phase 1, spec v2.0 §8, owner 2026-11-25 in v2.0-task-map §4):
-- the personal guild stock 個體黑庫, phase 1 only:
--   * who is guild master (Bank.authority: IsGuildLeader / GetGuildInfo rank
--     and the live roster must agree; anything unknown refuses to manage),
--   * the custodian list 保管人名單: published by the guild master as one
--     GFTKS record group K (author = the guild master), each custodian is a
--     StorageSource per kind (bags / bank) with its authorityEpoch,
--   * checking a received list (author must be the current guild master,
--     the list's own leader field must match, its epoch must not be below the
--     highest one seen: an old packet never brings a revoked custodian back),
--   * a custodian's own 公產 scope (which bags / bank tabs count): a setting
--     on that custodian's computer only. NOTHING is scanned in phase 1.
-- Not here: stock, requests, approvals, reservations, hand-outs (phase 2).
-- Privacy: this file never calls a bag, bank or item function; nobody's bags
-- are read (offline test checks the source and counts calls).
-- Design: private repo docs/research/GF-012-A_personal-bank.md.
-- API evidence: IsGuildLeader is a general WoW guess for 16001 (not checked in
-- game); GetGuildInfo rank index and the GetGuildRosterInfo order are checked
-- (GF-001-B, GF-001-Q); BagIndex 0-5 / 6-14 from the Forever API docs (GF-PROBE).

local _, ns = ...
local str = ns.str

local Bank = {}
ns.Bank = Bank

Bank.GROUP = "K"
Bank.FORMAT = "1"
Bank.MAX_ACTIVE = 10
Bank.MAX_REVOKED = 10
Bank.ROSTER_CACHE = 5      -- seconds the live roster read is kept (memory only)
-- GF-FIX-F (review 低-21): a wire value longer than this is refused before
-- it is parsed (20 entries of about 40 bytes fit with room to spare).
Bank.MAX_VALUE = 2048
Bank.RETRY = 60            -- a republish refused as "future" is tried again after this
Bank.KINDS = { b = true, k = true, bk = true }
Bank.KIND_NAME = { bags = "背包", bank = "銀行" }
Bank.KIND_LETTER = { bags = "b", bank = "k" }
-- Enum.BagIndex (GF-PROBE §3, Forever API docs; not checked in game).
Bank.SCOPE = {
    bags = { { 0, "行囊" }, { 1, "背包1" }, { 2, "背包2" }, { 3, "背包3" }, { 4, "背包4" }, { 5, "材料袋" } },
    bank = {},
}
for i = 1, 9 do Bank.SCOPE.bank[i] = { 5 + i, "分頁" .. i } end
-- The account bank (15-23) is left out on purpose (owner decision, design §4).

Bank.STATE_NAME = {
    ok = "有效", none = "尚無名單", expired = "非目前會長的名單，不採信", unknown = "權限未知",
    forged = "名單作者不符", old = "舊版名單", invalid = "名單格式錯誤",
}
-- GF-012-FIX: why authority is unknown / what the last 指定 did, for 同步與診斷.
Bank.WHY_NAME = { guild = "不在目標公會", roster = "名冊未載入或找不到會長", self = "讀不到自己的角色",
    api = "遊戲沒回答是否為會長", conflict = "遊戲與名冊對會長不一致" }
Bank.APPOINT_NAME = { ok = "成功", same = "沒有變更", full = "已達上限", invalid = "格式不對",
    ["not-found"] = "找不到這位職工", ["no-authority"] = "沒有會長權限", roster = "公會名冊尚未載入" }
Bank.ROLE_NAME = { leader = "會長", custodian = "保管人", member = "職工", unknown = "權限未知" }

local stats = { published = 0, refused = 0, healed = 0, rejectedOld = 0, rejectedForged = 0 }
Bank.stats = stats

local function S() return ns.Share end

---------------------------------------------------------------------------
-- Saved data: GreenFangToolkitDB.bank
---------------------------------------------------------------------------

local function root()
    local db = ns.db
    if not db then return nil end
    if type(db.bank) ~= "table" then db.bank = { v = 1 } end
    local b = db.bank
    if type(b.guilds) ~= "table" then b.guilds = {} end
    if type(b.scope) ~= "table" then b.scope = {} end
    return b
end

local function guildData()
    local b = root()
    if not b or ns.guildState() ~= "target" then return nil end
    local guild = str((ns.call(GetGuildInfo, "player")))
    if guild == "" then return nil end
    local key = ns.guildKey(ns.realm(), guild)
    local g = b.guilds[key]
    if type(g) ~= "table" then g = {}; b.guilds[key] = g end
    if type(g.seen) ~= "table" then g.seen = {} end
    return g
end
Bank.guildData = guildData

---------------------------------------------------------------------------
-- Who is guild master
---------------------------------------------------------------------------

local cache = { at = -1 }
local currentMemo = {}
function Bank.invalidate() cache.at = -1; currentMemo = {} end

-- The guild master's author id from the live roster, or nil when it cannot be
-- told (roster not loaded, not exactly one rank 0 among the rows read, no GUID).
-- GF-012-FIX (owner 2026-11-27 「無法正常指定成員」): a row the client does
-- not return (an empty name, as Roster.collect already skips) used to make
-- the guild master unknown for the whole guild; it is now skipped and counted
-- (Bank.rosterSkipped). The guild master's own row missing is still unknown.
Bank.rosterSkipped = 0
function Bank.rosterLeader()
    local now = ns.now()
    if cache.at >= 0 and now - cache.at < Bank.ROSTER_CACHE then return cache.a, cache.name end
    local a, name
    local total = ns.num(ns.call(GetNumGuildMembers)) or 0
    if total > 0 and type(GetGuildRosterInfo) == "function" then
        local found, skipped = 0, 0
        for i = 1, total do
            local r = { pcall(GetGuildRosterInfo, i) }
            local n = r[1] and str(r[2]) or ""
            if n == "" then skipped = skipped + 1
            elseif ns.num(r[4]) == 0 then
                found = found + 1
                local guid = str(r[18])
                a = guid:match("^Player%-") and S().authorOf(guid) or nil
                name = n
            end
        end
        if found ~= 1 or not a then a, name = nil, nil end
        Bank.rosterSkipped = skipped
    end
    cache.at, cache.a, cache.name = now, a, name
    return a, name
end

-- "leader" / "member" / "unknown", the guild master's author id, and why.
-- Leader only when two sources agree: IsGuildLeader() (or, without it, my
-- rank index from GetGuildInfo) and the live roster. Anything else unknown.
function Bank.authority()
    if ns.guildState() ~= "target" then return "unknown", nil, "guild" end
    local leaderA = Bank.rosterLeader()
    if not leaderA then return "unknown", nil, "roster" end
    local me = S().selfAuthor()
    if not me then return "unknown", leaderA, "self" end
    local rosterSays = leaderA == me
    local apiSays
    if type(IsGuildLeader) == "function" then
        local ok, v = pcall(IsGuildLeader)
        if ok and (v == true or v == 1) then apiSays = true
        elseif ok and (v == false or v == 0) then apiSays = false end
    end
    -- GF-012-FIX: IsGuildLeader missing, erroring or with no answer (nil):
    -- my rank index from GetGuildInfo; it still has to agree with the roster.
    if apiSays == nil then
        local _, _, idx = ns.call(GetGuildInfo, "player")
        idx = ns.num(idx)
        if idx then apiSays = idx == 0 end
    end
    if apiSays == nil then return "unknown", leaderA, "api" end
    if apiSays ~= rosterSays then return "unknown", leaderA, "conflict" end
    return apiSays and "leader" or "member", leaderA, nil
end

function Bank.canManage() return (Bank.authority()) == "leader" end

---------------------------------------------------------------------------
-- The wire value: 1;<epoch>;<leaderA>;<a>,<kinds>,<1|0>,<epoch>/...
---------------------------------------------------------------------------

local function validA(a) return type(a) == "string" and a ~= "" and a:find("^[%w%-]+$") ~= nil end

function Bank.encode(d)
    if type(d) ~= "table" or type(d.epoch) ~= "number" or not validA(d.leader) then return nil end
    local parts = {}
    for _, e in ipairs(d.entries or {}) do
        if not validA(e.a) or not Bank.KINDS[e.kinds] or type(e.epoch) ~= "number" then return nil end
        parts[#parts + 1] = e.a .. "," .. e.kinds .. "," .. (e.enabled and "1" or "0") .. "," .. S().b36(e.epoch)
    end
    return Bank.FORMAT .. ";" .. S().b36(d.epoch) .. ";" .. d.leader .. ";" .. table.concat(parts, "/")
end

-- nil for anything malformed (Share then neither stores nor relays it).
function Bank.decode(_, v)
    if type(v) ~= "string" or #v > Bank.MAX_VALUE then return nil end
    local ep, leader, body = v:match("^1;([0-9a-z]+);([%w%-]+);(.*)$")
    local epoch = ep and S().unb36(ep)
    if not epoch or epoch < S().EPOCH or epoch > S().serverNow() + S().FUTURE then return nil end
    local d = { epoch = epoch, leader = leader, entries = {} }
    local seenA, active, revoked = {}, 0, 0
    local most, n = Bank.MAX_ACTIVE + Bank.MAX_REVOKED, 0
    if body ~= "" then
        for item in (body .. "/"):gmatch("([^/]*)/") do
            n = n + 1
            if n > most then return nil end -- GF-FIX-F: stop at the first entry too many
            local a, kinds, on, eep = item:match("^([%w%-]+),(%a+),([01]),([0-9a-z]+)$")
            local e = eep and S().unb36(eep)
            if not a or not Bank.KINDS[kinds] or not e or e > epoch or seenA[a] then return nil end
            seenA[a] = true
            local enabled = on == "1"
            if enabled then active = active + 1 else revoked = revoked + 1 end
            d.entries[#d.entries + 1] = { a = a, kinds = kinds, enabled = enabled, epoch = e }
        end
    end
    if active > Bank.MAX_ACTIVE or revoked > Bank.MAX_REVOKED then return nil end
    return d
end

---------------------------------------------------------------------------
-- The list now in force (checked every read; nothing in Share is changed)
---------------------------------------------------------------------------

-- Returns { state, leader, leaderName, list, direct, at }; state is a key of
-- Bank.STATE_NAME. Only state "ok" has a list.
-- GF-FIX-F (review 低-18): kept until a record changes (Share.version) or
-- the roster is read again; one page draw asks for it several times.
function Bank.current()
    local out = { state = "unknown" }
    if ns.guildState() ~= "target" or not S().store() then return out end
    local leaderA, leaderName = Bank.rosterLeader()
    if not leaderA then return out end
    local key = tostring(S().version) .. "|" .. tostring(cache.at) .. "|" .. leaderA
    if currentMemo.key == key then return currentMemo.out end
    currentMemo = { key = key, out = out }
    out.leader, out.leaderName = leaderA, leaderName
    local rec = S().get(leaderA, Bank.GROUP)
    if not rec then
        out.state = "none"
        for a, groups in pairs(S().store().rec) do
            if a ~= leaderA and groups[Bank.GROUP] then out.state = "expired"; break end
        end
        return out
    end
    local d = S().decoded(leaderA, Bank.GROUP)
    if not d then out.state = "invalid"; return out end
    if d.leader ~= leaderA then out.state = "forged"; return out end
    local g = guildData()
    local seen = g and g.seen[leaderA] or 0
    if d.epoch < seen then out.state = "old"; return out end
    if g and d.epoch > seen then g.seen[leaderA] = d.epoch end
    out.state, out.list, out.direct, out.at = "ok", d, rec.fromAuthor == true, rec.t
    return out
end

-- My own entry on the list in force (enabled or not), or nil.
local function entryFor(list, a)
    for _, e in ipairs(list and list.entries or {}) do if e.a == a then return e end end
    return nil
end
Bank.entryFor = entryFor

function Bank.isCustodian(a)
    local cur = Bank.current()
    local e = cur.state == "ok" and entryFor(cur.list, a) or nil
    return e ~= nil and e.enabled, e
end

-- StorageSource objects of the list in force (spec §8.1): one per custodian
-- and kind; revoked ones with enabled = false.
function Bank.sources()
    local cur = Bank.current()
    local out = {}
    if cur.state ~= "ok" then return out, cur end
    for _, e in ipairs(cur.list.entries) do
        for _, kind in ipairs({ "bags", "bank" }) do
            if e.kinds:find(Bank.KIND_LETTER[kind], 1, true) then
                out[#out + 1] = { sourceID = e.a .. "." .. Bank.KIND_LETTER[kind], kind = kind,
                    custodianGUID = S().guidOf(e.a), enabled = e.enabled, authorityEpoch = e.epoch }
            end
        end
    end
    return out, cur
end

-- My role on the page: leader / custodian / member / unknown.
function Bank.myRole()
    local auth = Bank.authority()
    if auth == "leader" then return "leader" end
    local me = S().selfAuthor()
    if me and (Bank.isCustodian(me)) then return "custodian" end
    if auth == "unknown" then return "unknown" end
    return "member"
end

---------------------------------------------------------------------------
-- The guild master's own list (the original on this computer)
---------------------------------------------------------------------------

local function ownList()
    local g = guildData()
    return g and g.own or nil
end

-- The original as a wire table (entries sorted by author id).
local function ownTable(own)
    local me = S().selfAuthor()
    if not own or not me then return nil end
    local list = { epoch = own.epoch, leader = me, entries = {} }
    for a, e in pairs(own.entries or {}) do
        list.entries[#list.entries + 1] = { a = a, kinds = e.kinds, enabled = e.enabled == true, epoch = e.epoch }
    end
    table.sort(list.entries, function(x, y) return x.a < y.a end)
    return list
end

-- My list's wire value while I am the guild master; else nil (Share codec own()).
function Bank.ownValue()
    if Bank.authority() ~= "leader" then return nil end
    local own = ownList()
    return own and Bank.encode(ownTable(own)) or nil
end

local function nextEpoch(own, floor)
    local g = guildData()
    local me = S().selfAuthor()
    local e = math.max(math.floor(S().serverNow()), (own and own.epoch or 0) + 1,
        ((g and me and g.seen[me]) or 0) + 1, floor or 0)
    return e
end

local retrying = false
local function publish()
    local v = Bank.ownValue()
    if not v then return "no-authority" end
    local r = S().ownRecord(Bank.GROUP, v)
    if r == "stored" or r == "same" then
        stats.published = stats.published + 1
        local g, me = guildData(), S().selfAuthor()
        local own = ownList()
        if g and me and own then g.seen[me] = math.max(g.seen[me] or 0, own.epoch) end
    elseif r == "future" and not retrying then
        -- A forged copy under my name carries a time up to 10 minutes ahead.
        retrying = true
        ns.after(Bank.RETRY, function() retrying = false; publish() end)
    end
    if Bank.onChanged then Bank.onChanged() end
    return r
end
Bank.publish = publish

-- Trim revoked entries to Bank.MAX_REVOKED (oldest first).
local function trim(own)
    local revoked = {}
    for a, e in pairs(own.entries) do if not e.enabled then revoked[#revoked + 1] = { a = a, epoch = e.epoch } end end
    table.sort(revoked, function(x, y) if x.epoch ~= y.epoch then return x.epoch > y.epoch end return x.a < y.a end)
    for i = Bank.MAX_REVOKED + 1, #revoked do own.entries[revoked[i].a] = nil end
end

local function change(fn)
    if not Bank.canManage() then stats.refused = stats.refused + 1; return "no-authority" end
    local g = guildData()
    if not g then return "no-authority" end
    g.own = g.own or { epoch = 0, entries = {} }
    if type(g.own.entries) ~= "table" then g.own.entries = {} end
    local epoch = nextEpoch(g.own)
    local r = fn(g.own, epoch)
    if r ~= "ok" then return r end
    g.own.epoch = epoch
    trim(g.own)
    publish()
    return "ok"
end

-- GF-012-FIX: whoever it is given as, the answer is a member of the current
-- guild roster with a GUID, or nil (an author id, a name or a table with a
-- GUID that is not in the roster is not anybody's custodian).
local function memberA(who)
    if type(who) == "table" and who.guid then
        local a = S().authorOf(who.guid)
        local m = a and S().memberFor(a)
        if m then return a, m end
        return nil
    end
    who = str(who)
    if who == "" then return nil end
    if validA(who) and S().memberFor(who) then return who, S().memberFor(who) end
    local m = ns.Comm.memberFor(who)
    if not m and not who:find("%-") then m = ns.Comm.memberFor(who .. "-" .. ns.realm()) end
    local a = m and m.guid and S().authorOf(m.guid)
    if a and S().memberFor(a) then return a, m end
    -- GF-012-FIX (owner 0.16.9: 會長指定自己 →「找不到」): Comm.memberFor
    -- always adds "-Realm" to the name, but the roster may give a same-realm
    -- name (my own row at least) without it. Compare the short names too,
    -- only when exactly one roster member matches.
    local k, ks = Bank.queryKeys(who)
    local hit
    for _, r in ipairs(Bank.candidates("")) do
        if Bank.rowMatches(r, k, ks, true) then
            if hit and hit.a ~= r.a then return nil end
            hit = r
        end
    end
    if hit then return hit.a, S().memberFor(hit.a) end
    return nil
end
Bank.memberA = memberA

local function activeCount(own)
    local n = 0
    for _, e in pairs(own.entries) do if e.enabled then n = n + 1 end end
    return n
end

-- Appoint a custodian (a name, a roster member or an author id). kinds: "b",
-- "k" or "bk" (default both). Returns "ok" or why not.
-- GF-012-FIX: the last result (and, when refused for authority, why) is kept
-- for 同步與診斷 (no name, no GUID).
Bank.lastAppoint = nil
local appoint
function Bank.appoint(who, kinds)
    local r = appoint(who, kinds)
    local _, _, why = Bank.authority()
    Bank.lastAppoint = { r = r, why = r == "no-authority" and why or nil }
    return r
end
appoint = function(who, kinds)
    kinds = kinds or "bk"
    if not Bank.KINDS[kinds] then return "invalid" end
    if not Bank.canManage() then stats.refused = stats.refused + 1; return "no-authority" end
    if not (ns.Roster and ns.Roster.current()) then return "roster" end
    local a = memberA(who)
    if not a then return "not-found" end
    return change(function(own, epoch)
        local e = own.entries[a]
        if e and e.enabled and e.kinds == kinds then return "same" end
        if not (e and e.enabled) and activeCount(own) >= Bank.MAX_ACTIVE then return "full" end
        own.entries[a] = { kinds = kinds, enabled = true, epoch = epoch, at = ns.now() }
        return "ok"
    end)
end

-- GF-012-FIX (owner: 成員一定是公會內的人，可以用選的): the picker's rows,
-- from the roster snapshot (no game call): { a, name, short, rank, rankIndex,
-- classToken, online, custodian }, online first, then rank, then name.
-- The sorted base list is kept per snapshot; a search only filters it.
-- One rule for typed names (資料層 appoint, the page's box, the picker's search):
-- k = the whole text; ks = the name without "-Realm" when that realm is mine
-- (or none was typed), else "". A roster name without realm matches ks.
function Bank.queryKeys(q)
    q = str(q)
    local k = ns.keyName(q)
    local ks = ns.keyName(ns.shortName(q))
    local realm = q:match("%-(.+)$")
    if realm then
        local mine = ns.keyName(ns.realm())
        local r = ns.keyName(realm)
        if r ~= mine and r ~= (mine:gsub("%s", "")) then ks = "" end
    end
    return k, ks
end

-- exact: the whole name (or its short name) equals; else a search (contains).
function Bank.rowMatches(r, k, ks, exact)
    local rs = r.shortKey
    local noRealm = r.key == rs
    if exact then
        return r.key == k or rs == k or (ks ~= "" and noRealm and rs == ks)
    end
    return k == "" or r.key:find(k, 1, true) ~= nil or (ks ~= "" and noRealm and rs:find(ks, 1, true) ~= nil)
end

local base = { snap = false }
function Bank.candidates(query)
    local snap = ns.Roster and ns.Roster.current()
    if not snap then return {} end
    if base.snap ~= snap then
        local rows = {}
        for _, m in ipairs(snap.members) do
            local a = m.guid and S().authorOf(m.guid)
            if a then
                rows[#rows + 1] = { a = a, name = m.name, short = ns.shortName(m.name), key = ns.keyName(m.name),
                    shortKey = ns.keyName(ns.shortName(m.name)),
                    rank = str(m.guildRank), rankIndex = ns.num(m.rankIndex) or 99, classToken = m.classToken,
                    online = m.online == true }
            end
        end
        table.sort(rows, function(x, y)
            if x.online ~= y.online then return x.online end
            if x.rankIndex ~= y.rankIndex then return x.rankIndex < y.rankIndex end
            return x.key < y.key
        end)
        base = { snap = snap, rows = rows }
    end
    local k, ks = Bank.queryKeys(query)
    local cur = Bank.current()
    local on = {}
    for _, e in ipairs(cur.state == "ok" and cur.list.entries or {}) do if e.enabled then on[e.a] = true end end
    local out = {}
    for _, r in ipairs(base.rows) do
        if Bank.rowMatches(r, k, ks, false) then
            r.custodian = on[r.a] == true
            out[#out + 1] = r
        end
    end
    return out
end

function Bank.revoke(a)
    if not Bank.canManage() then stats.refused = stats.refused + 1; return "no-authority" end
    return change(function(own, epoch)
        local e = own.entries[a]
        if not e or not e.enabled then return "not-found" end
        e.enabled, e.epoch, e.at = false, epoch, ns.now()
        return "ok"
    end)
end

-- Turn one kind (bags / bank) of a custodian on or off; the last kind cannot
-- be turned off (that is 撤銷).
function Bank.setKind(a, kind, on)
    local letter = Bank.KIND_LETTER[kind]
    if not letter then return "invalid" end
    if not Bank.canManage() then stats.refused = stats.refused + 1; return "no-authority" end
    return change(function(own, epoch)
        local e = own.entries[a]
        if not e or not e.enabled then return "not-found" end
        local has = { b = e.kinds:find("b", 1, true) ~= nil, k = e.kinds:find("k", 1, true) ~= nil }
        has[letter] = on and true or false
        local kinds = (has.b and "b" or "") .. (has.k and "k" or "")
        if kinds == "" then return "last-kind" end
        if kinds == e.kinds then return "same" end
        e.kinds, e.epoch, e.at = kinds, epoch, ns.now()
        return "ok"
    end)
end

-- No longer guild master (known, not unknown): keep the original aside, stop
-- publishing it. A new guild master starts from an empty list (design §3.4).
function Bank.checkStepDown()
    local g = guildData()
    if not g or not g.own then return false end
    if Bank.authority() ~= "member" then return false end
    g.previous, g.own = g.own, nil
    if Bank.onChanged then Bank.onChanged() end
    return true
end

-- Somebody sent a list under my name that is not my original (design §5.1):
-- publish the original again, newer than theirs.
function Bank.heal()
    local me = S().selfAuthor()
    local own = ownList()
    if not me or not own or Bank.authority() ~= "leader" then return false end
    local rec = S().get(me, Bank.GROUP)
    local mine = Bank.ownValue()
    if not mine or (rec and rec.h == S().hash(mine)) then return false end
    local theirs = rec and S().decodeValue(Bank.GROUP, rec.v)
    own.epoch = nextEpoch(own, theirs and (theirs.epoch + 1) or 0)
    stats.healed = stats.healed + 1
    publish()
    return true
end

---------------------------------------------------------------------------
-- A custodian's own 公產 scope (this computer only; nothing is scanned)
---------------------------------------------------------------------------

function Bank.scope()
    local b = root()
    local guid = ns.Data.player().guid
    if not b or not guid then return nil end
    local s = b.scope[guid]
    if type(s) ~= "table" then s = { bags = {}, bank = {} }; b.scope[guid] = s end
    if type(s.bags) ~= "table" then s.bags = {} end
    if type(s.bank) ~= "table" then s.bank = {} end
    return s
end

local function scopeAllowed(kind, index)
    for _, it in ipairs(Bank.SCOPE[kind] or {}) do if it[1] == index then return true end end
    return false
end

-- May I set kind now? (an enabled custodian whose list entry has that kind)
function Bank.scopeEditable(kind)
    local me = S().selfAuthor()
    if not me or not Bank.SCOPE[kind] then return false end
    local on, e = Bank.isCustodian(me)
    return on == true and e.kinds:find(Bank.KIND_LETTER[kind], 1, true) ~= nil
end

function Bank.setScope(kind, index, on)
    if not scopeAllowed(kind, index) then return "invalid" end
    if not Bank.scopeEditable(kind) then return "not-custodian" end
    local s = Bank.scope()
    if not s then return "invalid" end
    s[kind][index] = on and true or nil
    if Bank.onChanged then Bank.onChanged() end
    return "ok"
end

-- What counts (only where the list allows the kind): { bags = { 0, 1 }, bank = { 6 } }.
function Bank.scopeInForce()
    local out = { bags = {}, bank = {} }
    local s = Bank.scope()
    if not s then return out end
    for _, kind in ipairs({ "bags", "bank" }) do
        if Bank.scopeEditable(kind) then
            for _, it in ipairs(Bank.SCOPE[kind]) do if s[kind][it[1]] then out[kind][#out[kind] + 1] = it[1] end end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------

function Bank.diagText()
    local auth, _, why = Bank.authority()
    local cur = Bank.current()
    local active = 0
    for _, e in ipairs(cur.list and cur.list.entries or {}) do if e.enabled then active = active + 1 end end
    local last = ""
    local la = Bank.lastAppoint
    if la then
        last = "｜上次指定：" .. (Bank.APPOINT_NAME[la.r] or tostring(la.r))
            .. (la.why and ("（" .. (Bank.WHY_NAME[la.why] or la.why) .. "）") or "")
    end
    return string.format("身分：%s%s｜名單：%s%s｜有效保管人 %d 位｜發布 %d、拒絕管理 %d、自我修正 %d%s%s｜庫存：尚未開放（第一階段不掃描）",
        Bank.ROLE_NAME[Bank.myRole()] or "?", (auth == "unknown" and why) and ("（" .. (Bank.WHY_NAME[why] or why) .. "）") or "",
        Bank.STATE_NAME[cur.state] or cur.state, cur.state == "ok" and (cur.direct and "，直接收到" or "，經轉送") or "",
        active, stats.published, stats.refused, stats.healed,
        Bank.rosterSkipped > 0 and string.format("｜名冊讀不到 %d 列", Bank.rosterSkipped) or "", last)
end

---------------------------------------------------------------------------
-- The share group. local = true: GF Sync does not upload it. No tomb: an X
-- for K is refused by Share, so nobody can delete the master's list.
---------------------------------------------------------------------------

ns.Share.registerGroup({
    name = "CUSTODY",
    ["local"] = true,
    match = function(g) return g == Bank.GROUP end,
    encode = function(_, d) return Bank.encode(d) end,
    decode = Bank.decode,
    ownGroups = { Bank.GROUP },
    own = function() return Bank.ownValue() end,
})

-- GF-FIX-F (review 低-18): Share tells us about every record of everybody;
-- the page is drawn again only when someone's K record changed (its value,
-- time or whether it came from the author), or for a change with no author.
local kSig = {}
function Bank.kChanged(a)
    if a == nil then return true end
    local rec = S().get(a, Bank.GROUP)
    local sig = rec and (tostring(rec.h or rec.v) .. "|" .. tostring(rec.t) .. "|" .. tostring(rec.fromAuthor == true)) or false
    local old = kSig[a]
    if old == nil then old = false end
    kSig[a] = sig
    return old ~= sig
end
function Bank.resetSignatures() kSig = {} end
ns.Share.onUpdate(function(a)
    if a == S().selfAuthor() then Bank.heal() end
    if Bank.kChanged(a) then
        if Bank.onChanged then Bank.onChanged() end
        Bank.notifySoon() -- GF-014-04
    end
end)

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    Bank.invalidate()
    Bank.checkStepDown()
    if Bank.onChanged then Bank.onChanged() end
    if Bank.notifyPending then Bank.notifySoon() end -- GF-014-04: the roster came after the list
end)

---------------------------------------------------------------------------
-- GF-014-04: 業務通知 bank_keeper: the guild master named me a custodian (or
-- changed my kinds), or took it back. Only from the list in force (Bank.current:
-- the current master's, checked); one event per list epoch, announced once
-- ever (Notify.once): a relay or the replay after /reload says nothing again.
-- The master's own list never notifies the master. In combat the check waits
-- for the end of combat. Memory: Notify.memory("bank_keeper").last =
-- "<kinds>" / "off" / nil (what I was on the last list I saw).
---------------------------------------------------------------------------

Bank.KINDS_TEXT = { b = "背包", k = "銀行", bk = "背包與銀行" }
Bank.notifyStats = { scans = 0, pushed = 0, waited = 0 }

function Bank.notifyScan()
    local N = ns.Notify
    if not N then return nil end
    if ns.inCombat() then Bank.notifyStats.waited = Bank.notifyStats.waited + 1; Bank.notifyPending = true; return nil end
    Bank.notifyPending = false
    local me = S().selfAuthor()
    if not me or ns.guildState() ~= "target" then return nil end
    local cur = Bank.current()
    if cur.state ~= "ok" then
        -- Unknown (roster not read yet): look again when the roster comes.
        if cur.state == "unknown" then Bank.notifyPending = true end
        return nil
    end
    Bank.notifyStats.scans = Bank.notifyStats.scans + 1
    if cur.leader == me then return nil end -- my own list
    local mem = N.memory("bank_keeper")
    local e = entryFor(cur.list, me)
    local is = e and (e.enabled and e.kinds or "off") or nil
    local was = mem.last
    mem.last = is
    if is == was or (is == nil and was == "off") then return nil end
    local text
    if is and is ~= "off" then
        text = string.format("會長指定你為臨時黑箱保管人（%s）", Bank.KINDS_TEXT[is] or is)
        if was and was ~= "off" then text = string.format("會長把你的保管範圍改成%s", Bank.KINDS_TEXT[is] or is) end
    elseif was and was ~= "off" then
        text = "會長撤銷了你的臨時黑箱保管人資格"
    else
        return nil
    end
    local epoch = cur.list.epoch
    if not N.once("bank_keeper", "k|" .. tostring(epoch) .. "|" .. tostring(is), epoch) then return nil end
    if not N.fresh("bank_keeper", epoch) then return nil end
    local r = N.push({ module = "bank_keeper", key = "keeper", text = text, target = { page = "bank" }, overflow = true })
    if r == "stored" or r == "merged" or r == "quiet" then Bank.notifyStats.pushed = Bank.notifyStats.pushed + 1 end
    return r
end
function Bank.notifySoon() ns.coalesce("bank-notify", 0, Bank.notifyScan) end
if ns.Notify and ns.Notify.onAfterCombat then
    ns.Notify.onAfterCombat(function() if Bank.notifyPending then Bank.notifyScan() end end)
end
