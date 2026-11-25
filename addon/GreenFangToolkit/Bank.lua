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
Bank.ROLE_NAME = { leader = "會長", custodian = "保管人", member = "成員", unknown = "權限未知" }

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
function Bank.invalidate() cache.at = -1 end

-- The guild master's author id from the live roster, or nil when it cannot be
-- told (roster not loaded, a row missing, not exactly one rank 0, no GUID).
function Bank.rosterLeader()
    local now = ns.now()
    if cache.at >= 0 and now - cache.at < Bank.ROSTER_CACHE then return cache.a, cache.name end
    local a, name
    local total = ns.num(ns.call(GetNumGuildMembers)) or 0
    if total > 0 and type(GetGuildRosterInfo) == "function" then
        local found, bad = 0, false
        for i = 1, total do
            local r = { pcall(GetGuildRosterInfo, i) }
            local n = r[1] and str(r[2]) or ""
            if n == "" then bad = true; break end
            if ns.num(r[4]) == 0 then
                found = found + 1
                local guid = str(r[18])
                a = guid:match("^Player%-") and S().authorOf(guid) or nil
                name = n
                if not a then bad = true end
            end
        end
        if bad or found ~= 1 then a, name = nil, nil end
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
        elseif ok and v == false then apiSays = false end
    else
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
    if type(v) ~= "string" then return nil end
    local ep, leader, body = v:match("^1;([0-9a-z]+);([%w%-]+);(.*)$")
    local epoch = ep and S().unb36(ep)
    if not epoch or epoch < S().EPOCH or epoch > S().serverNow() + S().FUTURE then return nil end
    local d = { epoch = epoch, leader = leader, entries = {} }
    local seenA, active, revoked = {}, 0, 0
    if body ~= "" then
        for item in (body .. "/"):gmatch("([^/]*)/") do
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
function Bank.current()
    local out = { state = "unknown" }
    if ns.guildState() ~= "target" or not S().store() then return out end
    local leaderA, leaderName = Bank.rosterLeader()
    if not leaderA then return out end
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

local function memberA(who)
    if type(who) == "table" and who.guid then return S().authorOf(who.guid), who end
    who = str(who)
    if who == "" then return nil end
    if validA(who) and S().memberFor(who) then return who, S().memberFor(who) end
    local m = ns.Comm.memberFor(who)
    if not m and not who:find("%-") then m = ns.Comm.memberFor(who .. "-" .. ns.realm()) end
    if m and m.guid then return S().authorOf(m.guid), m end
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
function Bank.appoint(who, kinds)
    kinds = kinds or "bk"
    if not Bank.KINDS[kinds] then return "invalid" end
    if not Bank.canManage() then stats.refused = stats.refused + 1; return "no-authority" end
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
    return string.format("身分：%s%s｜名單：%s%s｜有效保管人 %d 位｜發布 %d、拒絕管理 %d、自我修正 %d｜庫存：尚未開放（第一階段不掃描）",
        Bank.ROLE_NAME[Bank.myRole()] or "?", (auth == "unknown" and why) and ("（" .. why .. "）") or "",
        Bank.STATE_NAME[cur.state] or cur.state, cur.state == "ok" and (cur.direct and "，直接收到" or "，經轉送") or "",
        active, stats.published, stats.refused, stats.healed)
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

ns.Share.onUpdate(function(a)
    if a == S().selfAuthor() then Bank.heal() end
    if Bank.onChanged then Bank.onChanged() end
end)

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    Bank.invalidate()
    Bank.checkStepDown()
    if Bank.onChanged then Bank.onChanged() end
end)
