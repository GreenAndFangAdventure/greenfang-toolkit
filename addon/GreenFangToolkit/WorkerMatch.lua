-- WorkerMatch (GF-014-02, owner 2026-11-26): while my worker ticket (職工單)
-- is up, open adventure tickets of other members that fit it become one
-- 業務通知 each; a click on it opens 冒險業務 at that ticket (UI.focus), and
-- I press 申請 myself. Nothing is sent or uploaded from here: the matching
-- runs on this computer over what the ledger already holds.
--
-- What fits is Adventure.matches (the same rule the leaders' list uses):
-- the dungeon or the zone (or a shared quest), a free seat for my role, my
-- level and an overlapping slot. Ranked by how much is shared (a group /
-- elite quest, a quest, the place), then the number of shared quests, then
-- an online leader, then the earliest slot.
--
-- One notice per ticket (key "match|<ticket id>"): the next scans only push
-- again when the ticket changed (its version or its slots), so a read notice
-- does not come back every few minutes. A notice goes when the ticket no
-- longer fits (ended, cancelled, full, no seat for my role, I am in it or
-- invited), when my worker ticket is gone, when a switch turns it off, or at
-- its ttl (the end of the ticket's last slot, or my worker ticket's end).
-- GF-014's rules hold: its switch, its throttle, its burst limit, and in
-- combat the notice only waits (Notify.push queues it).
--
-- Settings, per character (事務設定 → 業務通知 → 設定, the bell's list):
--   on      the whole feature (default on: only someone who put a worker
--           ticket up gets these, and that is asking to be found)
--   alt     my support role counts too (default on; off = main role only)
--   quests  a match that rests only on quests counts (shared quests, or a
--           zone that only comes from my quests). GF-014-03: default off:
--           the dungeon or a zone I picked whole must match. Shared quests
--           still rank a match first either way.
--   chat    the match itself as the chat line, instead of GF-014's count
--           line for that notice (default off). Both follow GF-014's
--           聊天框提示: with it off, no chat line at all.
--
-- GF-014-03: only slots I can still join count (the finalized one once there
-- is one, not over, a seat for my role in it, overlapping one of my slots now
-- or later); the notice names the earliest of them. A notice held back in
-- combat is checked again before it shows (M.recheck).

local _, ns = ...
local str = ns.str

local M = {}
ns.WorkerMatch = M

M.MODULE = "adventure"
M.KEY_PREFIX = "match|"
M.DEBOUNCE = 2           -- seconds after a change before the scan
M.RESCAN = 120           -- seconds between scans while my worker ticket is up (slots end by time)
M.CHAT_GAP = 60          -- at most one chat line a minute
M.MIN_TTL = 60
M.DEFAULTS = { on = true, alt = true, quests = false, chat = false } -- GF-014-03: quests off
M.OPTIONS = {
    { key = "on", text = "職工單配對", tip = "我的職工單符合別人的冒險單時通知我（只在這台電腦比對）" },
    { key = "alt", text = "副職責也算", tip = "關掉時只比對主職責", sub = true },
    { key = "quests", text = "只有共同任務也算", tip = "預設關：地城或整區要相同；共同任務仍讓配對排前面", sub = true },
    { key = "chat", text = "配對時聊天框一行", tip = "聊天框印出這筆配對，取代「有 1 則新提示」（聊天框提示關掉時都不印；最多每分鐘一次）", sub = true },
}

local function A() return ns.Adventure end
local function N() return ns.Notify end
local function now() return ns.now() end

---------------------------------------------------------------------------
-- Settings (this character; GreenFangToolkitDB.settings.modules.notify.characters)
---------------------------------------------------------------------------

function M.settings()
    local F = ns.Framework
    local cs = (ns.db and F and F.charState) and F.charState("notify") or {}
    if type(cs.workerMatch) ~= "table" then cs.workerMatch = {} end
    return cs.workerMatch
end
function M.get(key)
    local v = M.settings()[key]
    if v == nil then return M.DEFAULTS[key] end
    return v == true
end
function M.set(key, on)
    if M.DEFAULTS[key] == nil then return end
    M.settings()[key] = on and true or false
    M.scan()
end

---------------------------------------------------------------------------
-- Matching (pure over Adventure's views)
---------------------------------------------------------------------------

local function involved(v, my)
    for _, list in ipairs({ v.members or {}, v.waitlist or {}, v.pending or {}, v.invited or {} }) do
        for _, x in ipairs(list) do if x.a == my then return true end end
    end
    return false
end

-- My worker ticket as Adventure.matches takes it, after the 副職責 switch.
function M.myWorker(opts)
    local my = ns.Share.selfAuthor()
    if not my then return nil end
    local w = A().workers()[my]
    if not w then return nil end
    local useAlt = opts and opts.alt
    if useAlt == nil then useAlt = M.get("alt") end
    if useAlt then return w end
    local copy = {}
    for k, x in pairs(w) do copy[k] = x end
    copy.alt = nil
    return copy
end

-- GF-014-03: the place is the dungeon, or a zone I picked as a whole (全區).
-- A zone that only comes from the quests I picked (qz) is not a place: it
-- rests on the quests, like a shared quest.
local function placeHit(v, w)
    if v.dungeon and w.dungeons and w.dungeons[v.dungeon] then return true end
    if v.zone and w.wholeZones and w.wholeZones[v.zone] then return true end
    return false
end
M.placeHit = placeHit

-- GF-014-03: a seat for this role in this slot: the ticket still has one, and
-- the members who take part in the slot have not filled the role.
local function membersIn(v, sl, role)
    local n = 0
    for _, m in ipairs(v.members or {}) do
        if m.role == role then
            local covers = m.slots == nil
            for _, id in ipairs(m.slots or {}) do if id == sl.id then covers = true; break end end
            if covers then n = n + 1 end
        end
    end
    return n
end
function M.seatIn(v, sl, role)
    if not role or (v.seats[role] or 0) <= 0 then return false end
    local cap = v.capacity and v.capacity[role]
    if sl and cap and membersIn(v, sl, role) >= cap then return false end
    return true
end

-- The role I would take there (in that slot when given): my main role when it
-- has a seat, else my support role.
function M.roleFor(v, w, sl)
    if v.seats.any then return M.seatIn(v, sl, "any") and "any" or nil end
    if M.seatIn(v, sl, w.main) then return w.main end
    if w.alt and M.seatIn(v, sl, w.alt) then return w.alt end
    return nil
end

-- GF-014-03: the slots I can still join that overlap my worker ticket: the
-- finalized one only once there is one, not over yet, a seat for my role in
-- it, and the overlap with one of my slots still ahead or going on.
-- { { slot, role, from, to } }, earliest overlap first.
function M.joinable(v, w, t)
    t = t or now()
    local Adv = A()
    local list = v.slots or {}
    if v.final then
        local only = {}
        for _, sl in ipairs(list) do if sl.id == v.final then only[1] = sl end end
        list = only
    end
    local out = {}
    for _, tsl in ipairs(list) do
        local ends = Adv.slotEnd(tsl) -- nil: 現在 without a length (not over by time)
        local role = not (ends and ends <= t) and M.roleFor(v, w, tsl) or nil
        if role then
            local a1, a2 = Adv.window(tsl, t)
            local from, to
            for _, sl in ipairs(w.slots or {}) do
                local b1, b2 = Adv.window(sl, t)
                local lo, hi = math.max(a1, b1), math.min(a2, b2)
                if lo < hi and hi > t then
                    if not from or lo < from then from = lo end
                    if not to or hi > to then to = hi end
                end
            end
            if from then out[#out + 1] = { slot = tsl, role = role, from = from, to = to } end
        end
    end
    table.sort(out, function(x, y)
        if x.from ~= y.from then return x.from < y.from end
        return tostring(x.slot.id) < tostring(y.slot.id)
    end)
    return out
end

-- When the notice goes by itself: the end of the last slot I can join (a 現在
-- slot without a length: open-ended, so my worker ticket's end), never after
-- my worker ticket.
function M.ticketEnd(v, slots, myEnd)
    local last
    for _, j in ipairs(slots or {}) do
        local e = A().slotEnd(j.slot) or myEnd
        if e and (not last or e > last) then last = e end
    end
    if myEnd and (not last or myEnd < last) then last = myEnd end
    return last
end

-- Every open ticket that fits my worker ticket, best first:
-- { view, score, shared, role, slot (the first overlapping one), ends }.
function M.candidates(opts)
    opts = opts or {}
    local Adv = A()
    local my = ns.Share.selfAuthor()
    local w = M.myWorker(opts)
    if not (my and w) then return {} end
    local quests = opts.quests
    if quests == nil then quests = M.get("quests") end
    local log = Adv.questLog()
    local level = Adv.myLevel()
    local t = opts.now or now()
    local out = {}
    for _, v in pairs(Adv.all()) do
        if v.leader ~= my and not v.closed and not v.departed and not involved(v, my) then
            local hit, _, score = Adv.matches(v, w, level, log)
            -- GF-014-03: what the match rests on: the place (dungeon / whole zone), or
            -- only the quests (shared quests, a zone that comes from my quests).
            local place = hit and placeHit(v, w)
            if hit and not quests and not place then hit = false end
            local slots = hit and M.joinable(v, w, t) or {}
            if #slots > 0 then
                local shared = 0
                for _, q in ipairs(v.quests or {}) do
                    if Adv.shares(w, tonumber(q) or q, log) then shared = shared + 1 end
                end
                out[#out + 1] = { view = v, score = score or 0, shared = shared, role = slots[1].role,
                    basis = place and "place" or "quest", slots = slots, slot = slots[1].slot,
                    from = slots[1].from, ends = M.ticketEnd(v, slots, w.expires) }
            end
        end
    end
    table.sort(out, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        if x.shared ~= y.shared then return x.shared > y.shared end
        local ox, oy = x.view.leaderOffline and 1 or 0, y.view.leaderOffline and 1 or 0
        if ox ~= oy then return ox < oy end
        local sx, sy = x.from or 0, y.from or 0
        if sx ~= sy then return sx < sy end
        return tostring(x.view.id) < tostring(y.view.id)
    end)
    return out
end

---------------------------------------------------------------------------
-- The notice
---------------------------------------------------------------------------

local function plain(s) return (str(s):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end

-- "職工單配對：死亡礦坑 明天 20:00 缺坦"
function M.text(c)
    local U = ns.AdventureUI
    local v = c.view
    local dest = (U and U.destText) and plain(U.destText(v)) or str(v.dungeon or v.zone or "")
    local when = (U and U.slotText and c.slot) and plain(U.slotText(c.slot)) or ""
    local role = (U and U.ROLE_NAME and U.ROLE_NAME[c.role]) or ""
    return "職工單配對：" .. dest .. (when ~= "" and (" " .. when) or "") .. (role ~= "" and (" 缺" .. role) or "")
end

-- What makes a ticket "the same" for the memory: its version and slots.
local function signature(c)
    local v = c.view
    local parts = { tostring(v.edited or v.created or ""), tostring(v.final or "") }
    for _, sl in ipairs(v.slots or {}) do parts[#parts + 1] = tostring(sl.id) .. ":" .. tostring(sl.s) .. ":" .. tostring(sl.d) end
    parts[#parts + 1] = c.role
    parts[#parts + 1] = "@" .. tostring(c.slot and c.slot.id) -- GF-014-03: the slot the notice shows
    return table.concat(parts, ",")
end

local function ttlOf(c, t)
    return math.max(M.MIN_TTL, (c.ends or (t + N().TTL)) - t)
end

-- GF-014-03: the chat line. 配對時聊天框一行 prints the match itself instead of
-- GF-014's count line for this notice; both follow 聊天框提示 (N.chatOn), so
-- that switch off means no chat line from here at all. At most one a minute;
-- never in combat (a notice released after combat may print it then).
local lastChat = -math.huge
function M.chatLine(t)
    return M.get("chat") and N().chatOn() and not ns.inCombat() and (t - lastChat) >= M.CHAT_GAP
end
local function say(c, t)
    lastChat = t
    M.stats.chat = M.stats.chat + 1
    ns.say(M.text(c))
end

local function keyId(key)
    return str(key):match("^" .. M.KEY_PREFIX:gsub("|", "%%|") .. "(.+)$")
end
M.keyId = keyId

local function memory()
    local mem = N().memory(M.MODULE)
    if type(mem.sent) ~= "table" then mem.sent = {} end
    return mem
end

M.stats = { scans = 0, pushed = 0, cleared = 0, chat = 0, rechecked = 0, dropped = 0 }

-- Push the new / changed matches, clear the ones that no longer fit.
-- Returns the candidates (scripts and tests).
function M.scan()
    M.stats.scans = M.stats.scans + 1
    if not (ns.db and N() and A()) then return {} end
    local mem = memory()
    local list = M.get("on") and M.candidates() or {}
    local t = now()
    local live = {}
    local w = M.myWorker({ alt = true })
    for _, c in ipairs(list) do
        local id = tostring(c.view.id)
        live[id] = true
        local sig = signature(c)
        if mem.sent[id] ~= sig then
            local line = M.chatLine(t)
            local res = N().push({ module = M.MODULE, key = M.KEY_PREFIX .. id, text = M.text(c),
                target = { page = "adventure", id = c.view.id }, ttl = ttlOf(c, t),
                summary = not line }) -- GF-014-03: the match line replaces the count line
            if res == "stored" or res == "merged" or res == "quiet" or res == "queued" then
                mem.sent[id] = sig
                M.stats.pushed = M.stats.pushed + 1
                -- Only for a notice that became new (not a quiet merge, not one waiting in combat).
                if line and (res == "stored" or res == "merged") then say(c, t) end
            end
        end
    end
    -- Gone: forget them and drop their notices.
    for id in pairs(mem.sent) do if not live[id] then mem.sent[id] = nil end end
    local n = N().clear(M.MODULE, function(key)
        local id = keyId(key)
        return id ~= nil and not live[id]
    end)
    M.stats.cleared = M.stats.cleared + (n or 0)
    if w then M.rescanLater() end
    return list
end

-- After a change (the adventure ledger, my worker ticket), a little later and once.
local pending = false
function M.schedule()
    if pending then return end
    pending = true
    ns.after(M.DEBOUNCE, function() pending = false; M.scan() end)
end
local rescan = false
function M.rescanLater()
    if rescan then return end
    rescan = true
    ns.after(M.RESCAN, function() rescan = false; M.scan() end)
end

-- GF-014-03: a notice that waited in combat is checked again before it shows:
-- gone when the ticket no longer fits (or the switch is off), else the newest
-- text, slot and ttl. Notify.afterCombat calls this (false = drop it).
function M.recheck(n)
    local id = keyId(n.key)
    if not id then return true end
    M.stats.rechecked = M.stats.rechecked + 1
    local mem = memory()
    local t = now()
    if M.get("on") then
        for _, c in ipairs(M.candidates()) do
            if tostring(c.view.id) == id then
                local line = M.chatLine(t)
                n.text, n.ttl, n.summary = M.text(c), ttlOf(c, t), not line
                n.target = { page = "adventure", id = c.view.id }
                mem.sent[id] = signature(c)
                if line then say(c, t) end
                return true
            end
        end
    end
    mem.sent[id] = nil
    M.stats.dropped = M.stats.dropped + 1
    return false
end

if A() and A().onChange then A().onChange(function() M.schedule() end) end
if N() and N().register then N().register(M.MODULE, { recheck = M.recheck }) end

-- The rows under 業務通知 → 設定 (NotifyUI draws a module's options when it has them).
for _, m in ipairs(N() and N().MODULES or {}) do
    if m.key == M.MODULE then
        m.options = {}
        for _, o in ipairs(M.OPTIONS) do
            local key = o.key
            m.options[#m.options + 1] = { key = key, text = o.text, tip = o.tip, sub = o.sub,
                get = function() return M.get(key) end, set = function(on) M.set(key, on) end }
        end
    end
end
