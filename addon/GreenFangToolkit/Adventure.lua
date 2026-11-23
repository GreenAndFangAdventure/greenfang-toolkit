-- Adventure (GF-002-B, spec docs/spec/GF-002_adventure-tickets_v1.0.md):
-- adventure tickets (a leader looking for people) and worker tickets (a
-- player waiting to be found), matching, applications, invitations,
-- admission, waitlist and refill. Synced on its own ledger prefix GFTKA
-- (0.11.x never registers it: nothing reaches them, nothing breaks).
--
-- Records (R-9.1): everyone writes only their own part.
--   T  (author = leader)  the leader's adventure tickets and decisions
--   W  (author = worker)  the worker's one worker ticket
--   A  (author = worker)  the worker's actions on tickets (apply, withdraw, accept/refuse an invitation)
-- Adventure.view() replays every event of a ticket in a fixed order (server
-- time, then GUID byte order, then event kind), so the result never depends
-- on the order the records arrived in (R-9.1).

local _, ns = ...
local str = ns.str

local Adv = {}
ns.Adventure = Adv

Adv.PREFIX = "GFTKA"
Adv.VERSION = 1
Adv.MAX_TICKETS = 20           -- R-9.4, per leader
Adv.OFFLINE_CLOSE = 15 * 60    -- R-4.7 / R-4.8
Adv.KEEP_CLOSED = 86400        -- R-4.9 / R-9.4
Adv.WORKER_TTL = 86400         -- R-5.3
Adv.MAX_SLOTS = 3              -- R-5.1
Adv.MAX_QUESTS = 5             -- R-4.1
Adv.NOTE_MAX = 40              -- R-4.4 / R-10.2
Adv.REMIND = { 3600, 900 }     -- R-7.1
Adv.FUTURE_DAYS = 14           -- R-4.2
Adv.ROLES = { "t", "h", "d" }
Adv.TAGS = { quest = 1, farm = 2, slow = 4, fast = 8, voice = 16 } -- R-4.4

local function S() return ns.Share end
local function b36(n) return S().b36(n) end
local function unb36(s) return S().unb36(s) end
local function now() return S().serverNow() end
local esc = function(v) return ns.Ledger.esc(v) end
local unesc = function(v) return ns.Ledger.unesc(v) end

---------------------------------------------------------------------------
-- Encoding (pure)
---------------------------------------------------------------------------

local NUM = { ver = true, cr = true, s = true, e = true, rt = true, rh = true, rd = true, sz = true, tg = true,
    sa = true, mc = true, at = true, ex = true, lv = true, ap = true }

function Adv.encodeEntry(e)
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

function Adv.decodeEntry(s)
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

function Adv.encodeList(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = Adv.encodeEntry(e) end
    return table.concat(out, "/")
end

function Adv.decodeList(s)
    local list = {}
    if str(s) == "" then return list end
    for part in str(s):gmatch("[^/]+") do
        local e = Adv.decodeEntry(part)
        if not e or not e.id then return nil end
        list[#list + 1] = e
    end
    return list
end

local function splitDots(s)
    local out = {}
    for x in str(s):gmatch("[^%.]+") do out[#out + 1] = x end
    return out
end
Adv.splitDots = splitDots

-- Slots "n" (now) or "s-e" pairs joined by "_" (base 36 server times).
function Adv.encodeSlots(slots)
    local out = {}
    for _, sl in ipairs(slots or {}) do
        if sl.now then out[#out + 1] = "n" else out[#out + 1] = b36(sl.s) .. "-" .. b36(sl.e) end
    end
    return table.concat(out, "_")
end
function Adv.decodeSlots(s)
    local out = {}
    for part in str(s):gmatch("[^_]+") do
        if part == "n" then out[#out + 1] = { now = true }
        else
            local a, b = part:match("^([0-9a-z]+)%-([0-9a-z]+)$")
            a, b = a and unb36(a), b and unb36(b)
            if a and b and b > a then out[#out + 1] = { s = a, e = b } end
        end
    end
    return out
end

-- Decisions "a:k:t;a:p:t;a:i:t" (kick, approve, invite) <-> list.
function Adv.encodeDecisions(list)
    local out = {}
    for _, d in ipairs(list or {}) do out[#out + 1] = d.a .. ":" .. d.k .. ":" .. b36(d.t) end
    return table.concat(out, ";")
end
function Adv.decodeDecisions(s)
    local out = {}
    for part in str(s):gmatch("[^;]+") do
        local a, k, t = part:match("^([^:]+):(%a):([0-9a-z]+)$")
        t = t and unb36(t)
        if a and t and (k == "k" or k == "p" or k == "i") then out[#out + 1] = { a = a, k = k, t = t } end
    end
    return out
end

-- Quest levels on a ticket (in-game only, not uploaded): "216:24;217:s" (s = scaling).
Adv.QUEST_SLACK = 3
function Adv.encodeQuestLevels(qs, log)
    if not log then return nil end
    local out = {}
    for _, q in ipairs(qs or {}) do
        local info = log[tonumber(q) or q]
        if info then
            if info.scaling then out[#out + 1] = tostring(q) .. ":s"
            elseif info.level and info.level > 0 then out[#out + 1] = tostring(q) .. ":" .. info.level end
        end
    end
    return #out > 0 and table.concat(out, ";") or nil
end
function Adv.decodeQuestLevels(s)
    if not s or s == "" then return nil end
    local out = {}
    for id, lv in tostring(s):gmatch("(%d+):([%ds]+)") do out[tonumber(id)] = lv == "s" and "s" or tonumber(lv) end
    return out
end

-- R-10.2: one short line: no control characters or line breaks, at most 40 characters.
function Adv.cleanNote(s)
    -- Explicit byte tests (as Share.lua): control bytes 0-31 and 127 become spaces.
    s = str(s):gsub(".", function(c) local b = c:byte(); if b < 32 or b == 127 then return " " end end)
    s = s:gsub("  +", " "):gsub("^ ", ""):gsub(" $", "")
    local out, n, i = {}, 0, 1
    while i <= #s and n < Adv.NOTE_MAX do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        out[#out + 1] = s:sub(i, i + len - 1)
        n = n + 1
        i = i + len
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Ledger
---------------------------------------------------------------------------

local function validAuthor(a)
    return type(a) == "string" and a ~= "" and not a:find("[~%.]") and S().memberFor(a) ~= nil
end
local function validValue(_, g, v)
    if #v > 12000 then return false end
    local list = Adv.decodeList(v)
    if not list then return false end
    if g == "W" and #list > 1 then return false end
    if g == "T" and #list > Adv.MAX_TICKETS then return false end
    return true
end

local cache = { version = -1 }
Adv.ledger = ns.Ledger.new({
    id = "adventure", prefix = Adv.PREFIX, burst = 6, refill = 0.5, loginDelay = 35,
    validAuthor = validAuthor, validGroup = function(g) return g == "T" or g == "W" or g == "A" end,
    validValue = validValue, selfAuthor = function() return S().selfAuthor() end, changeDelay = 2,
    onChange = function() cache.version = -1; if Adv.onChanged then Adv.onChanged() end end,
    mergeSelf = function(g, v) return Adv.mergeSelf(g, v) end,
})
local led = Adv.ledger

local function listOf(a, g)
    local rec = a and led:get(a, g)
    return rec and Adv.decodeList(rec.v) or {}
end
Adv.listOf = listOf

---------------------------------------------------------------------------
-- Guild roster: online and level (R-9.3); offline since when (R-4.7)
---------------------------------------------------------------------------

local offlineSince = {} -- [author] = server time we first saw them offline this session
function Adv.member(a) return S().memberFor(a) end
function Adv.isOnline(a)
    if a == S().selfAuthor() then return true end
    local m = S().memberFor(a)
    return m ~= nil and m.online == true
end
-- Update from the roster (called on every check); returns seconds offline or nil.
function Adv.offlineFor(a, t)
    t = t or now()
    if Adv.isOnline(a) then offlineSince[a] = nil; return nil end
    if not offlineSince[a] then offlineSince[a] = t end
    return t - offlineSince[a]
end
Adv.offlineSince = offlineSince

---------------------------------------------------------------------------
-- The ticket's view: replay (pure apart from the online lookup passed in)
---------------------------------------------------------------------------

local function guidLess(x, y) return ns.Orders.guidLess(S().guidOf(x), S().guidOf(y)) end
local KIND_ORDER = { apply = 1, accept = 2, approve = 3, invite = 4, refuse = 5, withdraw = 6, kick = 7 }

-- Seats still to fill: { t = n, h = n, d = n } or { any = n } for quest tickets.
function Adv.capacity(t)
    if t.ds and t.ds ~= "" then
        local cap = { t = t.rt or 1, h = t.rh or 1, d = t.rd or 3 }
        local lr = t.lr
        if lr and cap[lr] and cap[lr] > 0 then cap[lr] = cap[lr] - 1 end
        return cap
    end
    return { any = math.max(1, (t.sz or 5) - 1) }
end

-- t: the leader's ticket entry; leader: author; actions: { [worker] = { entries for this ticket } };
-- roleOf(worker) -> main, alt (from their worker ticket, else the action).
-- opts: { now, offline = seconds the leader has been offline or nil }.
function Adv.view(t, leader, actions, opts)
    opts = opts or {}
    local v = { id = t.id, leader = leader, src = t.src or "g", created = t.cr or 0, dungeon = t.ds ~= "" and t.ds or nil,
        quests = splitDots(t.qs), questLevels = Adv.decodeQuestLevels(t.ql), timeMode = t.tm or "n", start = t.s, finish = t.e, tags = t.tg or 0,
        note = t.nt, mode = t.md or "a", state = "open", members = {}, waitlist = {}, pending = {}, invited = {},
        kicked = {}, level = t.lv, leaderRole = t.lr }
    local cap = Adv.capacity(t)
    v.capacity = {}
    for k, n in pairs(cap) do v.capacity[k] = n end
    -- Events.
    local events = {}
    for _, d in ipairs(Adv.decodeDecisions(t.dc)) do
        events[#events + 1] = { t = d.t, a = d.a, kind = d.k == "k" and "kick" or d.k == "p" and "approve" or "invite" }
    end
    local roles = {}
    for a, list in pairs(actions or {}) do
        for _, e in ipairs(list) do
            local kind = ({ ap = "apply", wd = "withdraw", ia = "accept", ir = "refuse" })[e.ac]
            -- A withdrawn or refused entry keeps when it started (ap, ak), so the
            -- replay still knows the seat was taken in between (R-6.5 refill).
            if (e.ac == "wd" or e.ac == "ir") and e.ap and e.ak then
                local start = ({ ap = "apply", ia = "accept" })[e.ak]
                if start then events[#events + 1] = { t = e.ap, a = a, kind = start, main = e.ro, alt = e.rb } end
            end
            if kind and e.at then events[#events + 1] = { t = e.at, a = a, kind = kind, main = e.ro, alt = e.rb } end
        end
    end
    table.sort(events, function(x, y)
        if x.t ~= y.t then return x.t < y.t end
        if x.a ~= y.a then return guidLess(x.a, y.a) end
        return KIND_ORDER[x.kind] < KIND_ORDER[y.kind]
    end)
    local closedAt = (t.st == "x" or t.st == "c") and (t.sa or 0) or nil
    local departedAt = t.st == "g" and (t.sa or 0) or nil
    local seats = {}
    for k, n in pairs(cap) do seats[k] = n end
    local status = {} -- [a] = { s = "member"|"wait"|"pending", role, at }
    local invited = {}
    local quest = cap.any ~= nil
    local function free(role) return (seats[role] or 0) > 0 end
    local function admit(a, e)
        local main, alt = e.main or roles[a] and roles[a].main, e.alt or roles[a] and roles[a].alt
        roles[a] = { main = main, alt = alt }
        if quest then
            if free("any") then seats.any = seats.any - 1; status[a] = { s = "member", role = "any", at = e.t }
            else status[a] = { s = "wait", at = e.t } end
        elseif main and free(main) then seats[main] = seats[main] - 1; status[a] = { s = "member", role = main, at = e.t }
        elseif alt and alt ~= "" and free(alt) then seats[alt] = seats[alt] - 1; status[a] = { s = "member", role = alt, at = e.t }
        else status[a] = { s = "wait", at = e.t } end
    end
    -- R-6.5: refill the freed seat from the waitlist: the first with that main
    -- role, else the first with it as the alternative role (by join time).
    local function refill(role, at)
        local list = {}
        for a, st in pairs(status) do if st.s == "wait" then list[#list + 1] = { a = a, at = st.at } end end
        table.sort(list, function(x, y) if x.at ~= y.at then return x.at < y.at end return guidLess(x.a, y.a) end)
        local pick
        for _, w in ipairs(list) do
            local r = roles[w.a] or {}
            if quest or r.main == role then pick = w.a; break end
        end
        if not pick and not quest then
            for _, w in ipairs(list) do if (roles[w.a] or {}).alt == role then pick = w.a; break end end
        end
        if pick then
            seats[role] = seats[role] - 1
            status[pick] = { s = "member", role = role, at = status[pick].at, refilled = at }
        end
    end
    local function leave(a, at)
        local st = status[a]
        status[a] = nil
        if st and st.s == "member" then
            seats[st.role] = seats[st.role] + 1
            refill(st.role, at)
        end
    end
    for _, e in ipairs(events) do
        local open = not (closedAt and e.t > closedAt)
        local accepting = open and not (departedAt and e.t > departedAt)
        if e.kind == "apply" then
            if accepting and not status[e.a] then
                roles[e.a] = { main = e.main, alt = e.alt }
                local consent = v.mode == "c" and (not t.mc or e.t >= t.mc)
                if consent and not invited[e.a] then status[e.a] = { s = "pending", at = e.t }
                else admit(e.a, e) end
            end
        elseif e.kind == "approve" then
            if status[e.a] and status[e.a].s == "pending" then admit(e.a, { t = status[e.a].at, main = roles[e.a].main, alt = roles[e.a].alt }) end
        elseif e.kind == "invite" then
            if accepting and not status[e.a] then invited[e.a] = e.t end
        elseif e.kind == "accept" then
            if accepting and invited[e.a] and not status[e.a] then
                roles[e.a] = { main = e.main, alt = e.alt }
                invited[e.a] = nil
                admit(e.a, e)
            end
        elseif e.kind == "refuse" then
            invited[e.a] = nil
        elseif e.kind == "withdraw" then
            if status[e.a] then leave(e.a, e.t) end
        elseif e.kind == "kick" then
            invited[e.a] = nil
            if status[e.a] then leave(e.a, e.t) end
            v.kicked[e.a] = e.t
        end
    end
    for a, st in pairs(status) do
        local row = { a = a, role = st.role, at = st.at, refilled = st.refilled, online = opts.online and opts.online(a) }
        if st.s == "member" then v.members[#v.members + 1] = row
        elseif st.s == "wait" then v.waitlist[#v.waitlist + 1] = row
        else v.pending[#v.pending + 1] = row end
    end
    for a, at in pairs(invited) do v.invited[#v.invited + 1] = { a = a, at = at } end
    local function byAt(x, y) if x.at ~= y.at then return x.at < y.at end return guidLess(x.a, y.a) end
    table.sort(v.members, byAt); table.sort(v.waitlist, byAt); table.sort(v.pending, byAt); table.sort(v.invited, byAt)
    v.seats = seats
    local left = 0
    for _, n in pairs(seats) do left = left + n end
    v.left = left
    -- State (R-4.6 – R-4.8, R-7.3).
    local tnow = opts.now or now()
    if t.st == "x" then v.state, v.closedAt, v.closeReason = "cancel", t.sa, t.rs
    elseif t.st == "c" then v.state, v.closedAt = "done", t.sa
    else
        if t.st == "g" then v.state = "departed" elseif left == 0 then v.state = "full" end
        if v.timeMode ~= "n" and v.finish and tnow >= v.finish then
            v.state, v.closedAt, v.closeReason = "done", v.finish, "time"
        elseif opts.offline then
            v.leaderOffline = true
            local started = v.timeMode == "n" or (v.start and tnow >= v.start)
            if started and opts.offline >= Adv.OFFLINE_CLOSE then
                v.state, v.closedAt, v.closeReason = "cancel", tnow, "offline"
            end
        end
    end
    v.closed = v.state == "cancel" or v.state == "done"
    return v
end

-- Every ticket: { [id] = view }, cached until the ledger changes or a minute passes.
function Adv.all()
    local t = now()
    if cache.version == led.version and cache.views and t - (cache.at or 0) < 60 then return cache.views end
    local actionsBy = {}
    for _, a in ipairs(led:authors()) do
        for _, e in ipairs(listOf(a, "A")) do
            actionsBy[e.id] = actionsBy[e.id] or {}
            actionsBy[e.id][a] = actionsBy[e.id][a] or {}
            table.insert(actionsBy[e.id][a], e)
        end
    end
    local views = {}
    for _, a in ipairs(led:authors()) do
        local off = Adv.offlineFor(a, t)
        for _, e in ipairs(listOf(a, "T")) do
            views[e.id] = Adv.view(e, a, actionsBy[e.id], { now = t, offline = off, online = Adv.isOnline })
        end
    end
    cache.version, cache.views, cache.at = led.version, views, t
    return views
end
function Adv.get(id) return Adv.all()[id] end
function Adv.refresh() cache.version = -1 end

-- Worker tickets: { [author] = { entry, slots, dungeons set, quests set } }.
function Adv.workers()
    local out = {}
    local t = now()
    for _, a in ipairs(led:authors()) do
        local e = listOf(a, "W")[1]
        if e and e.st ~= "x" and (e.ex or 0) > t then
            local ds, qs = {}, {}
            for _, d in ipairs(splitDots(e.ds)) do ds[d] = true end
            for _, q in ipairs(splitDots(e.qs)) do qs[tonumber(q) or q] = true end
            out[a] = { entry = e, slots = Adv.decodeSlots(e.sl), dungeons = ds, quests = qs, allQuests = e.qa == "1",
                main = e.rm, alt = e.ra ~= "" and e.ra or nil, online = Adv.isOnline(a) }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Matching (R-6.1, pure)
---------------------------------------------------------------------------

-- Do two time sets overlap? A ticket is { now } or { s, e }; slots likewise.
function Adv.timeOverlap(ticket, slots)
    for _, sl in ipairs(slots or {}) do
        if ticket.timeMode == "n" then
            if sl.now then return true end
        elseif not sl.now and ticket.start and ticket.finish then
            if sl.s < ticket.finish and ticket.start < sl.e then return true end
        end
    end
    return false
end

-- R-6.1: destination, role, level, time. w = a worker (Adv.workers()[a]); level = the worker's level.
-- questLog: the worker's own quest set when they chose "all of my log" (nil for others: unknown, no match).
function Adv.matches(v, w, level, questLog)
    if v.closed or v.state == "departed" then return false, "closed" end
    -- Destination.
    local dest = false
    if v.dungeon and w.dungeons[v.dungeon] then dest = true end
    if not dest then
        for _, q in ipairs(v.quests) do
            local id = tonumber(q) or q
            if w.quests[id] or (w.allQuests and questLog and questLog[id]) then dest = true; break end
        end
    end
    if not dest then return false, "dest" end
    -- Role.
    if v.seats.any then
        if v.seats.any <= 0 then return false, "full" end
    else
        local need = function(r) return r and (v.seats[r] or 0) > 0 end
        if not (need(w.main) or need(w.alt)) then return false, "role" end
    end
    -- Level (R-6.1 point 3): dungeons by their range; quest tickets by the shared
    -- quests' levels (the leader's log). Scaling quests follow the character: never excluded.
    if v.dungeon and level and not ns.AdventureData.fits(v.dungeon, level) then return false, "level" end
    if not v.dungeon and level and v.questLevels then
        local anyFits, anyChecked = false, false
        for _, q in ipairs(v.quests) do
            local id = tonumber(q) or q
            local shared = w.quests[id] or (w.allQuests and questLog and questLog[id])
            if shared then
                local ql = v.questLevels[id]
                if ql == nil or ql == "s" or level >= ql - Adv.QUEST_SLACK then anyFits = true end
                anyChecked = true
            end
        end
        if anyChecked and not anyFits then return false, "level" end
    end
    if not Adv.timeOverlap(v, w.slots) then return false, "time" end
    return true
end

---------------------------------------------------------------------------
-- Writing my part
---------------------------------------------------------------------------

local function me() return S().selfAuthor() end
local function save(g, list)
    local v = Adv.encodeList(list)
    if #v > 12000 then return false, "full" end
    local r = led:put(g, v)
    if r == "stored" or r == "same" then Adv.refresh(); return true end
    return false, r
end
local function findIn(list, id)
    for i, e in ipairs(list) do if e.id == id then return e, i end end
end

local seq = 0
function Adv.newId()
    local mine = {}
    for _, e in ipairs(listOf(me(), "T")) do mine[e.id] = true end
    local id
    repeat
        seq = seq + 1
        -- Contract (savedvariables §adventure): game tickets start with "a" (x/y: website/Discord).
        id = "a" .. S().hash(me()) .. "." .. b36(now()) .. b36(seq)
    until not mine[id]
    return id
end

-- Infer my role from my class (R-5.1; remembered once changed by hand).
local CLASS_ROLES = {
    WARRIOR = { "t", "d" }, PALADIN = { "h", "t" }, PRIEST = { "h", "d" }, DRUID = { "h", "t" },
    SHAMAN = { "h", "d" }, ROGUE = { "d" }, MAGE = { "d" }, WARLOCK = { "d" }, HUNTER = { "d" },
}
function Adv.defaultRoles(classToken)
    local r = CLASS_ROLES[str(classToken)] or { "d" }
    return r[1], r[2]
end

-- R-4.1 – R-4.5. o = { dungeon, quests = { ids }, timeMode = "n"|"t"|"f", start, finish,
-- roles = { t, h, d }, size, tags, note, mode = "a"|"c", leaderRole }.
function Adv.open(o)
    local mine = listOf(me(), "T")
    local open = 0
    for _, e in ipairs(mine) do if e.st ~= "x" and e.st ~= "c" then open = open + 1 end end
    if open >= Adv.MAX_TICKETS then return nil, "too-many" end
    if not o.dungeon and not (o.quests and #o.quests > 0) then return nil, "no-destination" end
    local t = now()
    local tm = o.timeMode or "n"
    if tm ~= "n" then
        if not (o.start and o.finish and o.finish > o.start) then return nil, "bad-time" end
        if o.start > t + Adv.FUTURE_DAYS * 86400 then return nil, "too-far" end
    end
    local qs = {}
    for i, q in ipairs(o.quests or {}) do if i <= Adv.MAX_QUESTS then qs[#qs + 1] = tostring(q) end end
    local e = {
        id = Adv.newId(), src = "g", ver = Adv.VERSION, cr = t, ds = o.dungeon or "", qs = table.concat(qs, "."),
        ql = Adv.encodeQuestLevels(qs, Adv.questLog()),
        tm = tm, s = tm ~= "n" and o.start or nil, e = tm ~= "n" and o.finish or nil,
        rt = o.roles and o.roles.t, rh = o.roles and o.roles.h, rd = o.roles and o.roles.d,
        sz = (not o.dungeon) and (o.size or 5) or nil, tg = o.tags or 0, nt = Adv.cleanNote(o.note),
        md = o.mode == "c" and "c" or "a", mc = o.mode == "c" and t or nil, lr = o.leaderRole,
        st = "o", sa = t, lv = ns.num(ns.call(UnitLevel, "player")),
    }
    mine[#mine + 1] = e
    local ok, why = save("T", mine)
    if not ok then return nil, why end
    return e.id
end

-- Leader actions: "cancel", "done", "depart", "mode" (arg "a"/"c"), "kick"/"approve"/"invite" (arg author).
function Adv.leader(id, action, arg)
    local mine = listOf(me(), "T")
    local e = findIn(mine, id)
    if not e then return false, "unknown" end
    if e.st == "x" or e.st == "c" then return false, "closed" end
    local t = now()
    if action == "cancel" then e.st, e.sa, e.rs = "x", t, arg or "manual"
    elseif action == "done" then e.st, e.sa = "c", t
    elseif action == "depart" then e.st, e.sa = "g", t
    elseif action == "mode" then
        if arg == "c" and e.md ~= "c" then e.mc = t end
        if arg == "a" then e.mc = nil end
        e.md = arg == "c" and "c" or "a"
    elseif action == "kick" or action == "approve" or action == "invite" then
        local list = Adv.decodeDecisions(e.dc)
        local k = action == "kick" and "k" or action == "approve" and "p" or "i"
        local kept = {}
        -- Contract: one decision per worker (the last one); the game replays the same.
        for _, d in ipairs(list) do if d.a ~= arg then kept[#kept + 1] = d end end
        kept[#kept + 1] = { a = arg, k = k, t = t }
        e.dc = Adv.encodeDecisions(kept)
    else return false, "action" end
    return save("T", mine)
end

-- Worker actions on ticket id: "apply", "withdraw", "accept" (an invitation), "refuse".
function Adv.worker(id, action)
    local list = listOf(me(), "A")
    local e = findIn(list, id)
    local code = ({ apply = "ap", withdraw = "wd", accept = "ia", refuse = "ir" })[action]
    if not code then return false, "action" end
    local v = Adv.get(id)
    if (action == "apply" or action == "accept") and (not v or v.closed or v.state == "departed") then return false, "closed" end
    local w = listOf(me(), "W")[1]
    local main, alt
    if w then main, alt = w.rm, w.ra end
    if not main then
        local _, token = ns.call(UnitClass, "player")
        main, alt = Adv.defaultRoles(token)
    end
    if not e then e = { id = id }; list[#list + 1] = e end
    local t = now()
    if code == "ap" or code == "ia" then e.ap, e.ak = t, code
    elseif not (e.ac == "ap" or e.ac == "ia") then e.ap, e.ak = nil, nil end -- nothing to withdraw from
    e.ac, e.at, e.ro, e.rb = code, t, main, alt or ""
    return save("A", list)
end

-- R-5.1 – R-5.4: my worker ticket. o = { dungeons = {ids}, quests = {ids}, allQuests, main, alt, slots, hours }.
function Adv.setWorker(o)
    if not o then return save("W", {}) end
    local t = now()
    local slots = {}
    for i, sl in ipairs(o.slots or { { now = true } }) do if i <= Adv.MAX_SLOTS then slots[#slots + 1] = sl end end
    local qs = {}
    for _, q in ipairs(o.quests or {}) do qs[#qs + 1] = tostring(q) end
    local e = { id = "w", cr = t, ds = table.concat(o.dungeons or {}, "."), qs = table.concat(qs, "."),
        qa = o.allQuests and "1" or nil, rm = o.main or "d", ra = o.alt or "", sl = Adv.encodeSlots(slots),
        ex = t + (o.hours or 24) * 3600, st = "o", sa = t }
    return save("W", { e })
end

-- R-5.4: removing my worker ticket also withdraws my open applications.
function Adv.removeWorker()
    local acts = listOf(me(), "A")
    local t = now()
    for _, e in ipairs(acts) do if e.ac == "ap" or e.ac == "ia" then e.ap, e.ak = e.at, e.ac; e.ac, e.at = "wd", t end end
    save("A", acts)
    return save("W", {})
end

function Adv.myWorker()
    local e = listOf(me(), "W")[1]
    if not e then return nil end
    local ds, qs = {}, {}
    for _, d in ipairs(splitDots(e.ds)) do ds[#ds + 1] = d end
    for _, q in ipairs(splitDots(e.qs)) do qs[#qs + 1] = tonumber(q) or q end
    return { dungeons = ds, quests = qs, allQuests = e.qa == "1", main = e.rm, alt = e.ra ~= "" and e.ra or nil,
        slots = Adv.decodeSlots(e.sl), expires = e.ex }
end

-- R-5.2: edit one piece and keep the rest.
function Adv.editWorker(change)
    local w = Adv.myWorker() or { dungeons = {}, quests = {}, slots = { { now = true } } }
    change(w)
    w.hours = math.max(1, math.floor(((w.expires or (now() + 86400)) - now()) / 3600 + 0.5))
    return Adv.setWorker(w)
end

-- R-5.2: quests that left my log (done, abandoned) are removed from my worker ticket.
function Adv.syncQuests(logSet)
    local w = Adv.myWorker()
    if not w or w.allQuests then return false end
    local kept, changed = {}, false
    for _, q in ipairs(w.quests) do if logSet[q] then kept[#kept + 1] = q else changed = true end end
    if not changed then return false end
    return Adv.editWorker(function(x) x.quests = kept end)
end

-- Another computer of mine wrote an older copy: merge by id (later sa / at wins).
function Adv.mergeSelf(g, v)
    if g ~= "T" and g ~= "A" then return false end
    local incoming = Adv.decodeList(v)
    if not incoming then return false end
    local mine = listOf(me(), g)
    local byId = {}
    for i, e in ipairs(mine) do byId[e.id] = i end
    local changed = false
    for _, e in ipairs(incoming) do
        local i = byId[e.id]
        local tIn, tMine = e.sa or e.at or 0, i and (mine[i].sa or mine[i].at or 0) or -1
        if not i then mine[#mine + 1] = e; changed = true
        elseif tIn > tMine then mine[i] = e; changed = true end
    end
    if changed then led:put(g, Adv.encodeList(mine)) end
    return changed
end

---------------------------------------------------------------------------
-- Upkeep: my own "now" tickets after being away, timed tickets, pruning
---------------------------------------------------------------------------

function Adv.local_()
    local db = ns.db
    if type(db.adventure) ~= "table" then db.adventure = {} end
    local o = db.adventure
    for _, k in ipairs({ "seen", "reopen" }) do if type(o[k]) ~= "table" then o[k] = {} end end
    return o
end

-- PLAYER_LOGOUT: remember when I left (R-4.7, R-4.8).
-- Only when I have tickets (no empty tables in the save file otherwise).
function Adv.onLogout()
    if #listOf(me(), "T") == 0 and not (ns.db and type(ns.db.adventure) == "table") then return end
    Adv.local_().logoutAt = now()
end

-- Login: my open tickets that should have closed while I was away close now;
-- "now" tickets also leave a reopen prompt (R-4.7).
function Adv.onLogin()
    if not (ns.db and type(ns.db.adventure) == "table") then return 0 end
    local o = Adv.local_()
    local away = o.logoutAt and (now() - o.logoutAt) or 0
    o.logoutAt = nil
    if away < Adv.OFFLINE_CLOSE then return 0 end
    local mine = listOf(me(), "T")
    local n = 0
    local t = now()
    for _, e in ipairs(mine) do
        if e.st == "o" or e.st == "g" then
            local started = (e.tm or "n") == "n" or (e.s and t >= e.s)
            if started then
                e.st, e.sa, e.rs = "x", t, "offline"
                n = n + 1
                if (e.tm or "n") == "n" then o.reopen[e.id] = true end
            end
        end
    end
    if n > 0 then save("T", mine) end
    return n
end

-- R-4.7: reopen with the same contents (a new id; the old one stays closed).
function Adv.reopen(id)
    local o = Adv.local_()
    local e = findIn(listOf(me(), "T"), id)
    o.reopen[id] = nil
    if not e then return nil, "unknown" end
    local q = {}
    for _, x in ipairs(splitDots(e.qs)) do q[#q + 1] = tonumber(x) or x end
    return Adv.open({ dungeon = e.ds ~= "" and e.ds or nil, quests = q, timeMode = "n",
        roles = { t = e.rt, h = e.rh, d = e.rd }, size = e.sz, tags = e.tg, note = e.nt, mode = e.md, leaderRole = e.lr })
end
function Adv.dismissReopen(id) Adv.local_().reopen[id] = nil end

-- Every minute: finish my timed tickets whose time is over, prune old ones (R-4.8, R-4.9, R-9.4).
function Adv.maintain()
    local t = now()
    local mine = listOf(me(), "T")
    local kept, dirty = {}, false
    for _, e in ipairs(mine) do
        if (e.st == "o" or e.st == "g") and (e.tm or "n") ~= "n" and e.e and t >= e.e then e.st, e.sa = "c", e.e; dirty = true end
        if (e.st == "x" or e.st == "c") and t - (e.sa or t) >= Adv.KEEP_CLOSED then dirty = true
        else kept[#kept + 1] = e end
    end
    if dirty then save("T", kept) end
    -- My actions on tickets that are gone.
    local views = Adv.all()
    local acts, keptA, dirtyA = listOf(me(), "A"), {}, false
    for _, e in ipairs(acts) do
        if views[e.id] or t - (e.at or t) < Adv.KEEP_CLOSED then keptA[#keptA + 1] = e else dirtyA = true end
    end
    if dirtyA then save("A", keptA) end
    -- My expired worker ticket.
    local w = listOf(me(), "W")[1]
    if w and (w.ex or 0) <= t then save("W", {}) end
    -- Records of members who left.
    if ns.Roster.current() then
        for _, a in ipairs(led:authors()) do
            if not S().memberFor(a) then for _, g in ipairs({ "T", "W", "A" }) do led:drop(a, g) end end
        end
    end
    local seen = Adv.local_().seen
    for key in pairs(seen) do
        local id = key:match("^(.-)|")
        if id and id ~= "w" and not views[id] and not id:match("^m") then seen[key] = nil end
    end
end

---------------------------------------------------------------------------
-- What concerns me (R-6.2, R-6.4 – R-7.1): rows with attention, the minimap number
---------------------------------------------------------------------------

function Adv.myLevel() return ns.num(ns.call(UnitLevel, "player")) end

-- Attention for one ticket view and me; nil or { key, decide, code }.
function Adv.attention(v, my, t, myWorker, questLog)
    t = t or now()
    if v.leader == my then
        if Adv.local_().reopen[v.id] then return { key = v.id .. "|reopen", decide = true, code = "reopen" } end
        if v.closed then return nil end
        if #v.pending > 0 then return { key = v.id .. "|pending|" .. #v.pending, decide = true, code = "pending" } end
        for _, m in ipairs(v.members) do
            if m.refilled then return { key = v.id .. "|refill|" .. m.a .. "|" .. m.refilled, decide = false, code = "refill" } end
        end
        local r = Adv.reminder(v, t)
        if r then return r end
        return nil
    end
    local mine
    for _, m in ipairs(v.members) do if m.a == my then mine = m end end
    if v.closed then
        local involved = mine
        for _, w in ipairs(v.waitlist) do if w.a == my then involved = w end end
        if involved and v.closedAt and t - v.closedAt < Adv.KEEP_CLOSED then
            return { key = v.id .. "|closed", decide = false, code = v.closeReason == "offline" and "offline" or v.state }
        end
        return nil
    end
    for _, i in ipairs(v.invited) do if i.a == my then return { key = v.id .. "|invite|" .. i.at, decide = true, code = "invite" } end end
    if v.kicked[my] and not mine then return { key = v.id .. "|kicked|" .. v.kicked[my], decide = false, code = "kicked" } end
    if mine then
        if mine.refilled then return { key = v.id .. "|refilled|" .. mine.refilled, decide = false, code = "refilled" } end
        local r = Adv.reminder(v, t)
        if r then return r end
        return nil
    end
    for _, w in ipairs(v.waitlist) do if w.a == my then return nil end end
    for _, p in ipairs(v.pending) do if p.a == my then return nil end end
    if myWorker and Adv.matches(v, myWorker, Adv.myLevel(), questLog) then
        return { key = v.id .. "|match", decide = false, code = "match" }
    end
    return nil
end

-- R-7.1: 60 and 15 minutes before the start.
function Adv.reminder(v, t)
    if v.timeMode == "n" or not v.start or t >= v.start then return nil end
    local list = { unpack(Adv.REMIND) }
    table.sort(list) -- the nearest reminder first
    for _, before in ipairs(list) do
        if v.start - t <= before then return { key = v.id .. "|remind|" .. before, decide = false, code = "remind" } end
    end
    return nil
end

-- My quest log as a set of quest IDs (R-4.1, R-5.1). nil when the client cannot tell.
function Adv.questLog()
    local set = {}
    local found = false
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetNumQuestLogEntries) == "function" and type(C_QuestLog.GetInfo) == "function" then
        local n = ns.num((ns.call(C_QuestLog.GetNumQuestLogEntries))) or 0
        for i = 1, n do
            local info = ns.call(C_QuestLog.GetInfo, i)
            -- 16001 (owner, 2026-11-23): isHeader skips the zone rows; questID 0 is the fallback.
            -- level, else difficultyLevel; isScaling quests follow the character's level.
            local qid = type(info) == "table" and ns.num(info.questID) or nil
            if qid and qid > 0 and info.isHeader ~= true then
                set[qid] = { title = info.title, level = ns.num(info.level) or ns.num(info.difficultyLevel),
                    scaling = info.isScaling == true }
                found = true
            end
        end
    elseif type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
        local n = ns.num((ns.call(GetNumQuestLogEntries))) or 0
        for i = 1, n do
            local title, level, _, isHeader, _, _, _, questID = ns.call(GetQuestLogTitle, i)
            if not isHeader and ns.num(questID) and questID > 0 then set[questID] = { title = title, level = level }; found = true end
        end
    else
        return nil
    end
    return set, found
end

-- Rows the page shows and the minimap number (R-6.2, R-8.1).
function Adv.rowsFor()
    local my = me()
    if not my then return {}, {}, 0 end
    local t = now()
    local seen = Adv.local_().seen
    local workers = Adv.workers()
    local myWorker = workers[my]
    local log = Adv.questLog()
    local tickets, count = {}, 0
    for _, v in pairs(Adv.all()) do
        local hide = v.closed and v.closedAt and t - v.closedAt >= Adv.KEEP_CLOSED
        if not hide then
            local att = Adv.attention(v, my, t, myWorker, log)
            if att and not att.decide and seen[att.key] then att = nil end
            if att then count = count + 1 end
            local roleHit = myWorker and not v.closed and v.leader ~= my
                and (((v.seats[myWorker.main] or 0) > 0) or ((myWorker.alt and (v.seats[myWorker.alt] or 0) > 0) or false))
            tickets[#tickets + 1] = { view = v, attention = att, roleHit = roleHit }
        end
    end
    -- My reopen prompts of tickets that already left the list count too.
    for id in pairs(Adv.local_().reopen) do
        if not Adv.get(id) then Adv.local_().reopen[id] = nil end
    end
    table.sort(tickets, function(x, y)
        local ax, ay = x.attention and 0 or 1, y.attention and 0 or 1
        if ax ~= ay then return ax < ay end
        local rx, ry = x.roleHit and 0 or 1, y.roleHit and 0 or 1 -- R-6.2: my role first
        if rx ~= ry then return rx < ry end
        local cx, cy = x.view.closed and 1 or 0, y.view.closed and 1 or 0
        if cx ~= cy then return cx < cy end
        if x.view.created ~= y.view.created then return x.view.created > y.view.created end
        return x.view.id < y.view.id
    end)
    -- Workers matching my open tickets (leaders see them, R-6.2).
    local matched = {}
    for _, row in ipairs(tickets) do
        local v = row.view
        if v.leader == my and not v.closed then
            for a, w in pairs(workers) do
                if a ~= my then
                    local m = Adv.member(a)
                    local inside = false
                    for _, list in ipairs({ v.members, v.waitlist, v.pending, v.invited }) do
                        for _, x in ipairs(list) do if x.a == a then inside = true end end
                    end
                    if not inside and Adv.matches(v, w, m and m.level) then
                        local key = "m" .. v.id .. "|" .. a
                        local att = not seen[key] and { key = key, decide = false, code = "worker" } or nil
                        if att then count = count + 1 end
                        matched[#matched + 1] = { ticket = v, worker = a, w = w, attention = att }
                    end
                end
            end
        end
    end
    table.sort(matched, function(x, y)
        if x.w.online ~= y.w.online then return x.w.online end -- R-5.5: offline workers after
        if x.ticket.id ~= y.ticket.id then return x.ticket.id < y.ticket.id end
        return guidLess(x.worker, y.worker)
    end)
    return tickets, matched, count
end

function Adv.attentionCount()
    local _, _, n = Adv.rowsFor()
    return n
end

function Adv.markSeen()
    local seen = Adv.local_().seen
    local tickets, matched = Adv.rowsFor()
    for _, r in ipairs(tickets) do if r.attention and not r.attention.decide then seen[r.attention.key] = true end end
    for _, r in ipairs(matched) do if r.attention then seen[r.attention.key] = true end end
end

-- R-11.3: the most wanted destination and the role it lacks.
function Adv.summary()
    local wants = {}
    for _, w in pairs(Adv.workers()) do
        for d in pairs(w.dungeons) do wants[d] = (wants[d] or 0) + 1 end
    end
    local best, n = nil, 0
    for d, c in pairs(wants) do if c > n or (c == n and best and d < best) then best, n = d, c end end
    if not best then return nil end
    local lack = {}
    for _, v in pairs(Adv.all()) do
        if v.dungeon == best and not v.closed then
            for _, r in ipairs(Adv.ROLES) do if (v.seats[r] or 0) > 0 then lack[r] = true end end
        end
    end
    return { dungeon = best, count = n, lack = lack }
end

---------------------------------------------------------------------------
-- R-7.3: entering the dungeon counts as departing
---------------------------------------------------------------------------

-- The dungeon I am in (an adventure code), or nil. GetInstanceInfo's
-- instance ID first (16001 IDs not verified), then the name.
function Adv.currentDungeon()
    if ns.call(IsInInstance) ~= true then return nil end
    local name, kind, _, _, _, _, _, instanceID = ns.call(GetInstanceInfo)
    if kind ~= nil and kind ~= "party" then return nil end
    local list = {}
    local id = ns.num(instanceID)
    for _, d in ipairs(ns.AdventureData.DUNGEONS) do
        if id and d.instance == id then list[#list + 1] = d.id end
    end
    if #list == 0 and str(name) ~= "" then
        for _, d in ipairs(ns.AdventureData.DUNGEONS) do
            local base = d.name:match("^(.-)：") or d.name
            if str(name):find(base, 1, true) then list[#list + 1] = d.id end
        end
    end
    return #list > 0 and list or nil
end

-- My open tickets for the dungeon I just entered become "departed".
function Adv.onEnterWorld()
    local here = Adv.currentDungeon()
    if not here then return 0 end
    local set = {}
    for _, d in ipairs(here) do set[d] = true end
    local n = 0
    for _, e in ipairs(listOf(me(), "T")) do
        if e.st == "o" and set[e.ds] then
            if Adv.leader(e.id, "depart") then n = n + 1 end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Upload (savedvariables §adventure): the readable shape
---------------------------------------------------------------------------

Adv.UPLOAD_TICKETS, Adv.UPLOAD_ACTIONS, Adv.UPLOAD_DECISIONS = 20, 50, 40
local ROLE = { t = "tank", h = "healer", d = "dps" }
local STATUS = { o = "open", g = "departed", c = "done", x = "cancel" }
local ACT = { ap = "apply", wd = "withdraw", ia = "accept", ir = "refuse" }
local DEC = { k = "kick", p = "approve", i = "invite" }
local TAG_NAMES = { { "quest", 1 }, { "repeat", 2 }, { "slow", 4 }, { "fast", 8 }, { "voice", 16 } }
local function validId(id) return type(id) == "string" and #id <= 64 and id:match("^[0-9a-z.]+$") ~= nil end

local function timeOf(mode, from, to)
    if mode == "n" or not (from and to) then return { mode = "now" } end
    return { mode = mode == "f" and "future" or "today", from = from, to = to }
end

function Adv.ticketUpload(e)
    local quests = {}
    for _, q in ipairs(splitDots(e.qs)) do if tonumber(q) then quests[#quests + 1] = tonumber(q) end end
    local tags = {}
    for _, tg in ipairs(TAG_NAMES) do if math.floor((e.tg or 0) / tg[2]) % 2 == 1 then tags[#tags + 1] = tg[1] end end
    local out = {
        src = "g", ver = e.ver or 1, created = e.cr, dungeon = e.ds ~= "" and e.ds or nil,
        quests = #quests > 0 and quests or nil, time = timeOf(e.tm, e.s, e.e),
        tags = #tags > 0 and tags or nil, note = (e.nt and e.nt ~= "") and Adv.cleanNote(e.nt) or nil,
        admit = e.md == "c" and "consent" or "direct", status = STATUS[e.st] or "open", statusAt = e.sa,
    }
    if out.dungeon then out.slots = { tank = e.rt or 1, healer = e.rh or 1, dps = e.rd or 3 }
    else out.size = e.sz or 5 end
    local list = Adv.decodeDecisions(e.dc)
    table.sort(list, function(x, y) return x.t > y.t end)
    for i = 1, math.min(#list, Adv.UPLOAD_DECISIONS) do
        local d = list[i]
        out.decisions = out.decisions or {}
        local guid = S().guidOf(d.a)
        if not out.decisions[guid] then out.decisions[guid] = { d = DEC[d.k], at = d.t } end
    end
    return out
end

-- The author's adventure part, or nil when there is nothing.
function Adv.uploadFor(a)
    if not a then return nil end
    local out = {}
    local t = now()
    local trec = led:get(a, "T")
    if trec then
        local entries = {}
        for _, e in ipairs(Adv.decodeList(trec.v) or {}) do
            local ended = e.st == "x" or e.st == "c"
            if validId(e.id) and e.id:sub(1, 1) == "a" and not (ended and t - (e.sa or t) >= Adv.KEEP_CLOSED) then
                entries[#entries + 1] = { e = e, ended = ended, at = e.sa or 0 }
            end
        end
        -- Over the cap: the ones that ended longest ago go first.
        table.sort(entries, function(x, y)
            if x.ended ~= y.ended then return not x.ended end
            if x.at ~= y.at then return x.at > y.at end
            return x.e.id < y.e.id
        end)
        local value, n = {}, 0
        for _, it in ipairs(entries) do
            if n >= Adv.UPLOAD_TICKETS then break end
            value[it.e.id] = Adv.ticketUpload(it.e)
            n = n + 1
        end
        if n > 0 then out.tickets = { recordedAt = trec.t, value = value } end
    end
    local wrec = led:get(a, "W")
    local w = wrec and (Adv.decodeList(wrec.v) or {})[1]
    if w and w.st ~= "x" and (w.ex or 0) > t then
        local quests = {}
        for _, q in ipairs(splitDots(w.qs)) do if tonumber(q) then quests[#quests + 1] = tonumber(q) end end
        local times = {}
        for _, sl in ipairs(Adv.decodeSlots(w.sl)) do
            if sl.now then times[#times + 1] = { mode = "now" }
            else
                local today = math.floor(sl.s / 86400) == math.floor(t / 86400)
                times[#times + 1] = { mode = today and "today" or "future", from = sl.s, to = sl.e }
            end
        end
        out.worker = { recordedAt = wrec.t, value = { dungeons = splitDots(w.ds), quests = quests, allQuests = w.qa == "1",
            main = ROLE[w.rm] or "dps", alt = ROLE[w.ra], times = times, expires = w.ex } }
        if #out.worker.value.dungeons == 0 then out.worker.value.dungeons = nil end
        if #quests == 0 then out.worker.value.quests = nil end
    end
    local arec = led:get(a, "A")
    if arec then
        local views = Adv.all()
        local entries = {}
        for _, e in ipairs(Adv.decodeList(arec.v) or {}) do
            local v = views[e.id]
            local recent = v and not (v.closed and v.closedAt and t - v.closedAt >= Adv.KEEP_CLOSED)
            if validId(e.id) and ACT[e.ac] and (recent or t - (e.at or 0) < Adv.KEEP_CLOSED) then
                entries[#entries + 1] = { e = e, ended = not v or v.closed, at = e.at or 0 }
            end
        end
        table.sort(entries, function(x, y)
            if x.ended ~= y.ended then return not x.ended end
            if x.at ~= y.at then return x.at > y.at end
            return x.e.id < y.e.id
        end)
        local value, n = {}, 0
        for _, it in ipairs(entries) do
            if n >= Adv.UPLOAD_ACTIONS then break end
            local e = it.e
            value[e.id] = { a = ACT[e.ac], at = e.at, firstAt = e.ap or e.at, role = ROLE[e.ro] }
            n = n + 1
        end
        if n > 0 then out.actions = { recordedAt = arec.t, value = value } end
    end
    if not out.tickets and not out.worker and not out.actions then return nil end
    return out
end

-- { aT, aW, aA = { t, h } }: member.share change detection.
function Adv.uploadState(a)
    local out = {}
    for _, g in ipairs({ "T", "W", "A" }) do
        local r = a and led:get(a, g)
        if r then out["a" .. g] = { t = r.t, h = r.h } end
    end
    return out
end

---------------------------------------------------------------------------
-- R-7.2: invite everyone online and accepted
---------------------------------------------------------------------------

-- The names to invite (full Name-Realm), online and accepted, not me.
function Adv.inviteList(v)
    local out = {}
    for _, m in ipairs(v.members) do
        if m.a ~= me() and Adv.isOnline(m.a) then
            local mm = Adv.member(m.a)
            if mm then out[#out + 1] = mm.name end
        end
    end
    return out
end

local inviteQueue = {}
-- From a button click. Tries to invite everyone; when the client refuses
-- (protected, not verified on 16001), the rest wait for one click each.
function Adv.form(id)
    local v = Adv.get(id)
    if not v or v.leader ~= me() then return 0, "not-leader" end
    local names = Adv.inviteList(v)
    local invite = (type(C_PartyInfo) == "table" and type(C_PartyInfo.InviteUnit) == "function" and C_PartyInfo.InviteUnit)
        or (type(InviteUnit) == "function" and InviteUnit) or nil
    Adv.leader(id, "depart")
    if not invite then inviteQueue = names; return 0, "no-api" end
    local n = 0
    inviteQueue = {}
    for i, name in ipairs(names) do
        local ok = pcall(invite, name)
        if ok then n = n + 1 else
            for j = i, #names do inviteQueue[#inviteQueue + 1] = names[j] end
            break
        end
    end
    return n, #inviteQueue > 0 and "one-by-one" or "ok"
end
function Adv.inviteNext()
    local name = table.remove(inviteQueue, 1)
    if not name then return nil end
    local invite = (type(C_PartyInfo) == "table" and type(C_PartyInfo.InviteUnit) == "function" and C_PartyInfo.InviteUnit) or InviteUnit
    if type(invite) == "function" then pcall(invite, name) end
    return name
end
function Adv.pendingInvites() return inviteQueue end

function Adv.resetSession()
    cache = { version = -1 }
    for k in pairs(offlineSince) do offlineSince[k] = nil end
    inviteQueue = {}
    led:resetSession()
end
